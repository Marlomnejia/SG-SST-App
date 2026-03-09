"use strict";

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");

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
  const tokens = [];
  querySnapshot.forEach((doc) => {
    const data = doc.data() || {};
    const list = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    for (const token of list) {
      if (token && !tokens.includes(token)) {
        tokens.push(token);
      }
    }
  });
  return tokens;
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

async function collectInstitutionUserTokens(institutionId) {
  if (!institutionId) return [];
  const usersSnapshot = await admin
    .firestore()
    .collection("users")
    .where("institutionId", "==", institutionId)
    .where("notificationsEnabled", "==", true)
    .where("role", "in", ["user", "employee"])
    .get();
  const tokens = await collectTokens(usersSnapshot);
  console.log(
    `[FCM] institutionId=${institutionId} users=${usersSnapshot.size} tokens=${tokens.length}`
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
