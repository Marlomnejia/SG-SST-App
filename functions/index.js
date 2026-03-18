"use strict";

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { user } = require("firebase-functions/v1/auth");

admin.initializeApp();

function addMonths(date, months) {
  const d = new Date(date.getTime());
  const newMonth = d.getMonth() + months;
  d.setMonth(newMonth);
  if (d.getMonth() !== ((newMonth % 12) + 12) % 12) {
    d.setDate(0);
  }
  return d;
}

async function collectTokens(querySnapshot) {
  const uniqueTokens = new Set();
  querySnapshot.forEach((doc) => {
    const data = doc.data() || {};
    const list = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    for (const token of list) {
      if (token) {
        uniqueTokens.add(token);
      }
    }
  });
  return [...uniqueTokens];
}

async function sendNotification(tokens, payload) {
  if (!tokens.length) {
    console.log("[FCM] No hay tokens para enviar notificacion.");
    return null;
  }
  const chunks = [];
  for (let i = 0; i < tokens.length; i += 500) {
    chunks.push(tokens.slice(i, i + 500));
  }
  for (const chunk of chunks) {
    const response = await admin.messaging().sendMulticast({
      tokens: chunk,
      notification: payload.notification,
      data: payload.data || {},
    });
    console.log(
      `[FCM] Envio chunk size=${chunk.length} success=${response.successCount} failure=${response.failureCount}`
    );
  }
  return null;
}

async function collectInstitutionUserTokens(
  institutionId,
  {
    allowedRoles = ["user", "employee"],
    includeDisabled = false,
  } = {}
) {
  if (!institutionId) return [];

  // Evita depender de queries compuestas con indice (role + notificationsEnabled)
  // y tolera perfiles antiguos sin notificationsEnabled.
  const usersSnapshot = await admin
    .firestore()
    .collection("users")
    .where("institutionId", "==", institutionId)
    .get();

  const normalizedRoles = new Set(
    (allowedRoles || []).map((role) => String(role || "").trim())
  );
  const uniqueTokens = new Set();
  let matchedRoles = 0;
  let enabledUsers = 0;

  usersSnapshot.forEach((doc) => {
    const data = doc.data() || {};
    const role = String(data.role || "").trim();
    if (normalizedRoles.size > 0 && !normalizedRoles.has(role)) {
      return;
    }
    matchedRoles += 1;

    const notificationsEnabled = data.notificationsEnabled !== false;
    if (!includeDisabled && !notificationsEnabled) {
      return;
    }
    enabledUsers += 1;

    const list = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    for (const token of list) {
      if (token) uniqueTokens.add(token);
    }
  });

  const tokens = [...uniqueTokens];
  console.log(
    `[FCM] institutionId=${institutionId} usersTotal=${usersSnapshot.size} usersByRole=${matchedRoles} usersEnabled=${enabledUsers} tokens=${tokens.length}`
  );
  return tokens;
}

async function collectUserTokensByUid(uid) {
  if (!uid) return [];
  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  if (!userSnap.exists) {
    console.log(`[FCM] Usuario ${uid} no encontrado para notificacion directa.`);
    return [];
  }
  const data = userSnap.data() || {};
  if (data.notificationsEnabled !== true) {
    console.log(`[FCM] Usuario ${uid} tiene notificaciones desactivadas.`);
    return [];
  }
  const tokens = await collectTokens({
    forEach(callback) {
      callback(userSnap);
    },
  });
  console.log(`[FCM] uid=${uid} tokens_directos=${tokens.length}`);
  return tokens;
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

async function queueEmail(to, subject, text, html, metadata = {}) {
  const normalizedTo = normalizeEmail(to);
  if (!normalizedTo) {
    return null;
  }

  // Compatible con la extension "Trigger Email" (firestore-send-email)
  return admin.firestore().collection("mail").add({
    to: [normalizedTo],
    message: {
      subject,
      text,
      html,
    },
    metadata: {
      source: "sg-sst-functions",
      ...metadata,
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function collectInstitutionAdminEmails(institutionId) {
  if (!institutionId) return [];
  const usersSnap = await admin
    .firestore()
    .collection("users")
    .where("institutionId", "==", institutionId)
    .where("role", "==", "admin_sst")
    .get();

  const emails = new Set();
  usersSnap.forEach((doc) => {
    const data = doc.data() || {};
    const email = normalizeEmail(data.email);
    if (email) emails.add(email);
  });
  return [...emails];
}

async function queueInstitutionEmails({
  institutionId,
  institutionName,
  subject,
  text,
  html,
  extraEmails = [],
  reason = "",
}) {
  const recipients = new Set();
  for (const email of extraEmails) {
    const normalized = normalizeEmail(email);
    if (normalized) recipients.add(normalized);
  }

  const adminEmails = await collectInstitutionAdminEmails(institutionId);
  for (const email of adminEmails) {
    recipients.add(email);
  }

  if (!recipients.size) {
    console.log(
      `[MAIL][institution] institutionId=${institutionId} sin destinatarios (${reason}).`
    );
    return null;
  }

  await Promise.all(
    [...recipients].map((email) =>
      queueEmail(email, subject, text, html, {
        institutionId: String(institutionId || ""),
        institutionName: String(institutionName || ""),
        reason,
      })
    )
  );

  console.log(
    `[MAIL][institution] institutionId=${institutionId} reason=${reason} queued=${recipients.size}`
  );
  return null;
}

function shouldSendReminder(startAtMs, nowMs, targetHours, windowMinutes = 15) {
  const targetMs = targetHours * 60 * 60 * 1000;
  const delta = startAtMs - nowMs;
  const toleranceMs = windowMinutes * 60 * 1000;
  return delta <= targetMs && delta > (targetMs - toleranceMs);
}

exports.reassignExpiredTrainings = onSchedule("every 24 hours", async () => {
    const now = admin.firestore.Timestamp.now();

    const assignmentsSnapshot = await admin
      .firestore()
      .collection("assignments")
      .where("autoReassign", "==", true)
      .where("archived", "==", false)
      .get();

    const batch = admin.firestore().batch();

    for (const doc of assignmentsSnapshot.docs) {
      const data = doc.data();
      const dueDate = data.dueDate;
      const trainingId = data.trainingId;
      const target = data.target;

      if (!trainingId || !target) {
        continue;
      }

      let shouldReassign = false;

      if (dueDate && dueDate.toMillis() <= now.toMillis()) {
        shouldReassign = true;
      } else if (!dueDate && target !== "all") {
        const trainingDoc = await admin
          .firestore()
          .collection("trainings")
          .doc(trainingId)
          .get();
        const trainingData = trainingDoc.exists ? trainingDoc.data() : null;
        const validityMonths = trainingData?.validityMonths ?? 12;

        const certSnapshot = await admin
          .firestore()
          .collection("certificates")
          .where("trainingId", "==", trainingId)
          .where("userId", "==", target)
          .orderBy("issuedAt", "desc")
          .limit(1)
          .get();

        if (!certSnapshot.empty) {
          const cert = certSnapshot.docs[0].data();
          const issuedAt = cert.issuedAt?.toDate();
          if (issuedAt) {
            const expiresAt = addMonths(issuedAt, validityMonths);
            if (new Date() > expiresAt) {
              shouldReassign = true;
            }
          }
        }
      }

      if (!shouldReassign) {
        continue;
      }

      const trainingDoc = await admin
        .firestore()
        .collection("trainings")
        .doc(trainingId)
        .get();
      const trainingData = trainingDoc.exists ? trainingDoc.data() : null;
      const validityMonths = trainingData?.validityMonths ?? 12;

      const newDueDate = admin.firestore.Timestamp.fromDate(
        addMonths(new Date(), validityMonths)
      );

      const newAssignmentRef = admin.firestore().collection("assignments").doc();
      batch.set(newAssignmentRef, {
        trainingId,
        target,
        dueDate: newDueDate,
        autoReassign: true,
        assignedAt: admin.firestore.FieldValue.serverTimestamp(),
        previousAssignmentId: doc.id,
      });

      const logRef = admin.firestore().collection("assignmentLogs").doc();
      batch.set(logRef, {
        trainingId,
        target,
        previousAssignmentId: doc.id,
        newAssignmentId: newAssignmentRef.id,
        reason: dueDate && dueDate.toMillis() <= now.toMillis()
          ? "due_date"
          : "certificate_expired",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      batch.update(doc.ref, {
        archived: true,
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return null;
  });

exports.notifyNewEvent = onDocumentCreated("eventos/{eventId}", async (event) => {
  const data = event.data ? event.data.data() : {};
  const tipo = data.tipo || "Evento";
  const categoria = data.categoria || "Sin categoria";
  const lugar = data.lugar || "Sin lugar";
  const institutionId = data.institutionId || null;

  const usersRef = admin.firestore().collection("users");
  const adminSnapshots = [];

  if (institutionId) {
    const institutionAdmins = await usersRef
      .where("institutionId", "==", institutionId)
      .where("notificationsEnabled", "==", true)
      .where("role", "==", "admin_sst")
      .get();
    adminSnapshots.push(institutionAdmins);

    const superAdmins = await usersRef
      .where("notificationsEnabled", "==", true)
      .where("role", "==", "admin")
      .get();
    adminSnapshots.push(superAdmins);
  } else {
    const adminsSnapshot = await usersRef
      .where("role", "in", ["admin", "admin_sst"])
      .where("notificationsEnabled", "==", true)
      .get();
    adminSnapshots.push(adminsSnapshot);
  }

  let tokens = [];
  for (const snap of adminSnapshots) {
    const snapTokens = await collectTokens(snap);
    tokens = [...new Set([...tokens, ...snapTokens])];
  }

  console.log(
    `[FCM][event_created] eventId=${event.params.eventId} institutionId=${institutionId || "none"} tokens=${tokens.length}`
  );

  return sendNotification(tokens, {
    notification: {
      title: "Nuevo reporte SG-SST",
      body: `${tipo} - ${categoria} (${lugar})`,
    },
    data: {
      eventId: event.params.eventId,
      type: "event_created",
      ...(institutionId ? { institutionId: String(institutionId) } : {}),
    },
  });
});

exports.queueInstitutionPendingEmail = onDocumentCreated(
  "institutions/{institutionId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    const status = String(data.status || "pending").trim().toLowerCase();
    if (status !== "pending") {
      return null;
    }

    const institutionId = event.params.institutionId;
    const institutionName = String(data.name || "tu institucion").trim();
    const contactEmail = normalizeEmail(data.email);
    const inviteCode = String(data.inviteCode || "").trim();

    const subject = "Registro recibido - Validacion de institucion SG-SST";
    const text =
      `Hola.\n\n` +
      `Recibimos el registro de la institucion "${institutionName}". ` +
      `Tu solicitud esta en estado PENDIENTE de validacion por Super Admin.\n\n` +
      (inviteCode
        ? `Codigo de invitacion (se habilita al aprobar): ${inviteCode}\n\n`
        : "") +
      `Te notificaremos por este medio cuando sea aprobada.\n\n` +
      `EduSST`;
    const html =
      `<p>Hola.</p>` +
      `<p>Recibimos el registro de la institucion <b>${institutionName}</b>. ` +
      `Tu solicitud esta en estado <b>PENDIENTE</b> de validacion por Super Admin.</p>` +
      (inviteCode
        ? `<p>Codigo de invitacion (se habilita al aprobar): <b>${inviteCode}</b></p>`
        : "") +
      `<p>Te notificaremos por este medio cuando sea aprobada.</p>` +
      `<p><b>EduSST</b></p>`;

    return queueInstitutionEmails({
      institutionId,
      institutionName,
      subject,
      text,
      html,
      extraEmails: contactEmail ? [contactEmail] : [],
      reason: "institution_pending",
    });
  }
);

exports.queueInstitutionApprovedEmail = onDocumentUpdated(
  "institutions/{institutionId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeStatus = String(before.status || "").trim().toLowerCase();
    const afterStatus = String(after.status || "").trim().toLowerCase();

    if (beforeStatus === afterStatus || afterStatus !== "active") {
      return null;
    }

    const institutionId = event.params.institutionId;
    const institutionName = String(after.name || "tu institucion").trim();
    const contactEmail = normalizeEmail(after.email);
    const inviteCode = String(after.inviteCode || "").trim();

    const subject = "Institucion aprobada - SG-SST activo";
    const text =
      `Hola.\n\n` +
      `La institucion "${institutionName}" fue APROBADA y ya se encuentra activa en EduSST.\n\n` +
      (inviteCode ? `Codigo de invitacion: ${inviteCode}\n\n` : "") +
      `Ya puedes ingresar y gestionar los modulos del sistema.\n\n` +
      `EduSST`;
    const html =
      `<p>Hola.</p>` +
      `<p>La institucion <b>${institutionName}</b> fue <b>APROBADA</b> y ya se encuentra activa en EduSST.</p>` +
      (inviteCode ? `<p>Codigo de invitacion: <b>${inviteCode}</b></p>` : "") +
      `<p>Ya puedes ingresar y gestionar los modulos del sistema.</p>` +
      `<p><b>EduSST</b></p>`;

    return queueInstitutionEmails({
      institutionId,
      institutionName,
      subject,
      text,
      html,
      extraEmails: contactEmail ? [contactEmail] : [],
      reason: "institution_approved",
    });
  }
);

exports.notifyTrainingReminders = onSchedule("every 15 minutes", async () => {
  const nowMs = Date.now();
  const trainingsSnapshot = await admin
    .firestore()
    .collectionGroup("trainings")
    .where("type", "==", "scheduled")
    .where("status", "==", "published")
    .get();

  for (const doc of trainingsSnapshot.docs) {
    const data = doc.data() || {};
    const scheduled = data.scheduled || {};
    const startAt = scheduled.startAt;
    if (!startAt || typeof startAt.toMillis !== "function") {
      continue;
    }

    const startAtMs = startAt.toMillis();
    if (startAtMs <= nowMs) {
      continue;
    }

    const institutionId = doc.ref.parent.parent
      ? doc.ref.parent.parent.id
      : null;
    if (!institutionId) {
      continue;
    }

    const reminderFlags = data.reminderFlags || {};
    const should24h = shouldSendReminder(startAtMs, nowMs, 24);
    const should1h = shouldSendReminder(startAtMs, nowMs, 1);

    let sentSomething = false;
    const tokens = (should24h || should1h)
      ? await collectInstitutionUserTokens(institutionId)
      : [];

    if (should24h && !reminderFlags.sent24h) {
      await sendNotification(tokens, {
        notification: {
          title: "Capacitacion programada",
          body: `Tienes capacitacion manana: ${data.title || "SST"}`,
        },
        data: {
          type: "training_reminder_24h",
          trainingId: doc.id,
          institutionId,
        },
      });
      reminderFlags.sent24h = admin.firestore.FieldValue.serverTimestamp();
      sentSomething = true;
    }

    if (should1h && !reminderFlags.sent1h) {
      await sendNotification(tokens, {
        notification: {
          title: "Recordatorio de capacitacion",
          body: `Tu capacitacion inicia en 1 hora: ${data.title || "SST"}`,
        },
        data: {
          type: "training_reminder_1h",
          trainingId: doc.id,
          institutionId,
        },
      });
      reminderFlags.sent1h = admin.firestore.FieldValue.serverTimestamp();
      sentSomething = true;
    }

    if (sentSomething) {
      await doc.ref.update({ reminderFlags });
    }
  }
  return null;
});

exports.notifyTrainingCancelled = onDocumentUpdated(
  "institutions/{institutionId}/trainings/{trainingId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};

    if (before.status === "cancelled" || after.status !== "cancelled") {
      return null;
    }

    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const tokens = await collectInstitutionUserTokens(institutionId);

    return sendNotification(tokens, {
      notification: {
        title: "Capacitacion cancelada",
        body: `La capacitacion "${after.title || "SST"}" fue cancelada por administracion.`,
      },
      data: {
        type: "training_cancelled",
        trainingId,
        institutionId,
      },
    });
  }
);

exports.notifyTrainingPublishedOnCreate = onDocumentCreated(
  "institutions/{institutionId}/trainings/{trainingId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    if ((data.status || "") !== "published") {
      return null;
    }

    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const tokens = await collectInstitutionUserTokens(institutionId);

    return sendNotification(tokens, {
      notification: {
        title: "Nueva capacitacion disponible",
        body: `Ya puedes revisar "${data.title || "Capacitacion SST"}".`,
      },
      data: {
        type: "training_published",
        trainingId,
        institutionId,
      },
    });
  }
);

exports.notifyTrainingPublishedOnUpdate = onDocumentUpdated(
  "institutions/{institutionId}/trainings/{trainingId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (before.status === "published" || after.status !== "published") {
      return null;
    }

    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const tokens = await collectInstitutionUserTokens(institutionId);

    return sendNotification(tokens, {
      notification: {
        title: "Capacitacion publicada",
        body: `Se publico "${after.title || "Capacitacion SST"}".`,
      },
      data: {
        type: "training_published",
        trainingId,
        institutionId,
      },
    });
  }
);

exports.notifyDocumentPublishedOnCreate = onDocumentCreated(
  "institutions/{institutionId}/documents/{documentId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    if (data.isPublished !== true) {
      return null;
    }

    const institutionId = event.params.institutionId;
    const documentId = event.params.documentId;
    const tokens = await collectInstitutionUserTokens(institutionId);

    return sendNotification(tokens, {
      notification: {
        title: "Nuevo documento SST",
        body: `Se publico "${data.title || "Documento SST"}".`,
      },
      data: {
        type: "document_published",
        documentId,
        institutionId,
      },
    });
  }
);

exports.notifyDocumentPublishedOnUpdate = onDocumentUpdated(
  "institutions/{institutionId}/documents/{documentId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (before.isPublished === true || after.isPublished !== true) {
      return null;
    }

    const institutionId = event.params.institutionId;
    const documentId = event.params.documentId;
    const tokens = await collectInstitutionUserTokens(institutionId);

    return sendNotification(tokens, {
      notification: {
        title: "Documento SST publicado",
        body: `Ya puedes consultar "${after.title || "Documento SST"}".`,
      },
      data: {
        type: "document_published",
        documentId,
        institutionId,
      },
    });
  }
);

exports.notifyActionPlanStatusUpdates = onDocumentUpdated(
  "planesDeAccion/{planId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const responsibleUid = after.responsibleUid || before.responsibleUid || null;

    if (!responsibleUid) {
      return null;
    }

    const beforeStatus = String(before.status || before.estado || "").trim().toLowerCase();
    const afterStatus = String(after.status || after.estado || "").trim().toLowerCase();
    const beforeVerification = String(before.verificationStatus || "").trim().toLowerCase();
    const afterVerification = String(after.verificationStatus || "").trim().toLowerCase();

    let payload = null;

    if (
      afterVerification === "requiere_ajuste" &&
      (beforeVerification !== "requiere_ajuste" || beforeStatus !== afterStatus)
    ) {
      payload = {
        notification: {
          title: "Plan requiere ajuste",
          body: `Tu plan "${after.title || "Plan de accion"}" fue devuelto para correccion.`,
        },
        data: {
          type: "action_plan_requires_adjustment",
          planId: event.params.planId,
          originReportId: String(after.originReportId || after.eventoId || ""),
        },
      };
    } else if (afterStatus === "cerrado" && beforeStatus !== "cerrado") {
      payload = {
        notification: {
          title: "Plan cerrado",
          body: `El plan "${after.title || "Plan de accion"}" fue cerrado por administracion.`,
        },
        data: {
          type: "action_plan_closed",
          planId: event.params.planId,
          originReportId: String(after.originReportId || after.eventoId || ""),
        },
      };
    }

    if (!payload) {
      return null;
    }

    const tokens = await collectUserTokensByUid(responsibleUid);
    console.log(
      `[FCM][action_plan] planId=${event.params.planId} responsibleUid=${responsibleUid} status=${afterStatus} verification=${afterVerification} tokens=${tokens.length}`
    );

    return sendNotification(tokens, payload);
  }
);

exports.cleanupDeletedAuthUserProfile = user().onDelete(async (deletedUser) => {
  const uid = deletedUser && deletedUser.uid ? deletedUser.uid : null;
  if (!uid) {
    console.log("[AUTH_CLEANUP] Evento sin uid, se omite.");
    return null;
  }

  try {
    await admin.firestore().collection("users").doc(uid).delete();
    console.log(`[AUTH_CLEANUP] Perfil users/${uid} eliminado.`);
  } catch (e) {
    console.error(`[AUTH_CLEANUP] Error eliminando users/${uid}:`, e);
    throw e;
  }

  return null;
});
