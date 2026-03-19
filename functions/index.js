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

function normalizeKey(value) {
  return String(value || "").trim().toLowerCase().replaceAll(" ", "_");
}

function normalizeRole(value) {
  return String(value || "").trim().toLowerCase();
}

function isInstitutionAdminRole(role) {
  const normalized = normalizeRole(role);
  return (
    normalized === "admin_sst" ||
    normalized === "adminsst" ||
    normalized === "admin"
  );
}

function timestampToMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function formatDateTimeLabel(value) {
  const millis = timestampToMillis(value);
  if (!millis) return "";
  const date = new Date(millis);
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  return `${d}/${m}/${y} ${hh}:${mm}`;
}

function normalizeReportStatus(raw) {
  const normalized = normalizeKey(raw);
  if (normalized.includes("revisi")) return "en_revision";
  if (normalized.includes("proceso")) return "en_proceso";
  if (normalized.includes("solucion")) return "cerrado";
  if (normalized.includes("cerrad")) return "cerrado";
  if (normalized.includes("rechaz")) return "rechazado";
  if (normalized.includes("report")) return "reportado";
  return normalized || "reportado";
}

function reportStatusLabel(raw) {
  switch (normalizeReportStatus(raw)) {
    case "reportado":
      return "Reportado";
    case "en_revision":
      return "En revision";
    case "en_proceso":
      return "En proceso";
    case "cerrado":
      return "Cerrado";
    case "rechazado":
      return "Rechazado";
    default:
      return String(raw || "Reportado");
  }
}

function normalizeActionPlanStatus(raw) {
  const normalized = normalizeKey(raw);
  if (normalized.includes("curso")) return "en_curso";
  if (normalized.includes("ejecut")) return "ejecutado";
  if (normalized.includes("verif")) return "verificado";
  if (normalized.includes("cerr")) return "cerrado";
  return normalized || "pendiente";
}

function normalizeInspectionStatus(raw) {
  const normalized = normalizeKey(raw);
  if (normalized.includes("progress") || normalized.includes("curso")) {
    return "in_progress";
  }
  if (normalized.includes("find") || normalized.includes("hallazgo")) {
    return "completed_with_findings";
  }
  if (normalized.includes("complet") || normalized.includes("cerrad")) {
    return "completed";
  }
  if (normalized.includes("cancel")) {
    return "cancelled";
  }
  return normalized || "scheduled";
}

function isInvalidTokenErrorCode(code) {
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}

async function cleanupInvalidTokens(tokens) {
  if (!tokens.length) return;
  const firestore = admin.firestore();
  for (const token of tokens) {
    try {
      const users = await firestore
        .collection("users")
        .where("fcmTokens", "array-contains", token)
        .get();
      if (users.empty) continue;
      const batch = firestore.batch();
      users.forEach((userDoc) => {
        batch.set(
          userDoc.ref,
          {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      });
      await batch.commit();
      console.log(
        `[FCM][cleanup] Token invalido eliminado de ${users.size} perfil(es).`
      );
    } catch (e) {
      console.error("[FCM][cleanup] Error limpiando token invalido:", e);
    }
  }
}

async function sendNotification(tokens, payload) {
  const uniqueTokens = [...new Set(tokens.filter((token) => !!token))];
  if (!uniqueTokens.length) {
    console.log("[FCM] No hay tokens para enviar notificacion.");
    return { successCount: 0, failureCount: 0 };
  }
  const normalizedData = {};
  const rawData = payload.data || {};
  Object.keys(rawData).forEach((key) => {
    const value = rawData[key];
    normalizedData[String(key)] = value == null ? "" : String(value);
  });
  const chunks = [];
  for (let i = 0; i < uniqueTokens.length; i += 500) {
    chunks.push(uniqueTokens.slice(i, i + 500));
  }
  let totalSuccess = 0;
  let totalFailure = 0;
  const invalidTokens = new Set();
  for (const chunk of chunks) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: payload.notification,
      data: normalizedData,
      android: {
        priority: "high",
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          channelId: "sst_alerts",
          priority: "high",
          sound: "default",
          defaultVibrateTimings: true,
        },
      },
    });
    totalSuccess += response.successCount || 0;
    totalFailure += response.failureCount || 0;
    console.log(
      `[FCM] Envio chunk size=${chunk.length} success=${response.successCount} failure=${response.failureCount}`
    );
    if (response.failureCount > 0 && Array.isArray(response.responses)) {
      response.responses.forEach((result, index) => {
        if (!result.success && result.error) {
          const code = String(result.error.code || "");
          console.log(
            `[FCM][error] token=${chunk[index]} code=${code} message=${result.error.message}`
          );
          if (isInvalidTokenErrorCode(code)) {
            invalidTokens.add(chunk[index]);
          }
        }
      });
    }
  }
  if (invalidTokens.size > 0) {
    await cleanupInvalidTokens([...invalidTokens]);
  }
  return {
    successCount: totalSuccess,
    failureCount: totalFailure,
    invalidTokenCount: invalidTokens.size,
  };
}

async function sendTopicNotification(topic, payload) {
  const normalizedTopic = String(topic || "").trim();
  if (!normalizedTopic) {
    return { successCount: 0, failureCount: 0 };
  }

  const normalizedData = {};
  const rawData = payload.data || {};
  Object.keys(rawData).forEach((key) => {
    const value = rawData[key];
    normalizedData[String(key)] = value == null ? "" : String(value);
  });

  try {
    const messageId = await admin.messaging().send({
      topic: normalizedTopic,
      notification: payload.notification,
      data: normalizedData,
      android: {
        priority: "high",
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          channelId: "sst_alerts",
          priority: "high",
          sound: "default",
          defaultVibrateTimings: true,
        },
      },
    });
    console.log(`[FCM][topic] topic=${normalizedTopic} messageId=${messageId}`);
    return { successCount: 1, failureCount: 0 };
  } catch (e) {
    console.error(`[FCM][topic] Error enviando a topic=${normalizedTopic}:`, e);
    return { successCount: 0, failureCount: 1 };
  }
}

async function collectInstitutionUserTokens(
  institutionId,
  {
    allowedRoles = ["user", "employee"],
    includeDisabled = true,
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
    (allowedRoles || []).map((role) =>
      String(role || "").trim().toLowerCase()
    )
  );
  const uniqueTokens = new Set();
  let matchedRoles = 0;
  let enabledUsers = 0;

  usersSnapshot.forEach((doc) => {
    const data = doc.data() || {};
    const role = String(data.role || "").trim().toLowerCase();
    if (normalizedRoles.size > 0 && !normalizedRoles.has(role)) {
      return;
    }
    matchedRoles += 1;

    const notificationsEnabled = data.notificationsEnabled !== false;
    if (notificationsEnabled) {
      enabledUsers += 1;
    } else if (!includeDisabled) {
      return;
    }

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
  if (data.notificationsEnabled === false) {
    console.log(
      `[FCM] Usuario ${uid} con notificationsEnabled=false. Se enviara si tiene tokens.`
    );
  }
  const tokens = await collectTokens({
    forEach(callback) {
      callback(userSnap);
    },
  });
  console.log(`[FCM] uid=${uid} tokens_directos=${tokens.length}`);
  return tokens;
}

async function collectInstitutionAdminTokens(institutionId) {
  if (!institutionId) return [];
  const usersRef = admin.firestore().collection("users");
  const [institutionUsers, superAdmins] = await Promise.all([
    usersRef.where("institutionId", "==", institutionId).get(),
    usersRef.where("role", "==", "admin").get(),
  ]);
  const tokenSet = new Set();
  const snapshots = [institutionUsers, superAdmins];
  for (const snapshot of snapshots) {
    snapshot.forEach((doc) => {
      const data = doc.data() || {};
      const role = normalizeRole(data.role);
      if (snapshot === institutionUsers && !isInstitutionAdminRole(role)) {
        return;
      }
      const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
      for (const token of tokens) {
        if (token) tokenSet.add(token);
      }
    });
  }
  return [...tokenSet];
}

async function collectSuperAdminTokens() {
  // Evita depender de coincidencia exacta de role (ej: "admin ", "Admin")
  // y tolera variantes usadas en algunos perfiles legacy.
  const snap = await admin.firestore().collection("users").get();
  const tokenSet = new Set();
  let matched = 0;
  snap.forEach((doc) => {
    const data = doc.data() || {};
    const role = normalizeRole(data.role);
    const roleKey = normalizeKey(data.role).replaceAll("-", "_");
    const isSuperAdmin =
      role === "admin" ||
      roleKey === "super_admin" ||
      roleKey === "superadmin" ||
      roleKey === "super_administrador";
    if (!isSuperAdmin) return;
    matched += 1;
    const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    for (const token of tokens) {
      if (token) tokenSet.add(token);
    }
  });
  const tokens = [...tokenSet];
  console.log(
    `[FCM][super_admin_tokens] usersTotal=${snap.size} matched=${matched} tokens=${tokens.length}`
  );
  return tokens;
}

async function collectInstitutionRoleTokens(
  institutionId,
  allowedRoles = ["admin_sst", "adminsst", "admin"]
) {
  if (!institutionId) return [];
  const roleSet = new Set(
    (allowedRoles || []).map((role) => normalizeRole(role))
  );
  const usersSnap = await admin
    .firestore()
    .collection("users")
    .where("institutionId", "==", institutionId)
    .get();
  const tokenSet = new Set();
  usersSnap.forEach((doc) => {
    const data = doc.data() || {};
    const role = normalizeRole(data.role);
    if (!roleSet.has(role)) return;
    const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    for (const token of tokens) {
      if (token) tokenSet.add(token);
    }
  });
  return [...tokenSet];
}

function labelRsvpResponse(value) {
  const normalized = normalizeKey(value);
  if (normalized === "yes" || normalized === "si" || normalized === "asistir") {
    return "Asistira";
  }
  if (normalized === "no" || normalized.includes("no_puedo")) {
    return "No puede asistir";
  }
  if (normalized === "maybe" || normalized === "quizas" || normalized === "tal_vez") {
    return "Quizas";
  }
  return String(value || "Sin respuesta");
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
  if (String(data.reportId || "").trim().length > 0) {
    // Reportes estructurados notifican desde reports/{reportId}
    // para evitar duplicados en admin_sst.
    return null;
  }
  const tipo = data.tipo || "Evento";
  const categoria = data.categoria || "Sin categoria";
  const lugar = data.lugar || "Sin lugar";
  const severidad = normalizeKey(data.severidad);
  const isCritical =
    severidad === "grave" ||
    severidad === "alta" ||
    severidad === "critical" ||
    severidad === "critica";
  const institutionId = data.institutionId || null;
  let tokens = [];
  if (institutionId) {
    tokens = await collectInstitutionAdminTokens(institutionId);
  } else {
    const usersRef = admin.firestore().collection("users");
    const adminsSnapshot = await usersRef
      .where("role", "in", ["admin", "admin_sst", "adminsst"])
      .get();
    tokens = await collectTokens(adminsSnapshot);
  }

  console.log(
    `[FCM][event_created] eventId=${event.params.eventId} institutionId=${institutionId || "none"} tokens=${tokens.length}`
  );

  return sendNotification(tokens, {
    notification: {
      title: isCritical ? "Alerta critica SG-SST" : "Nuevo reporte SG-SST",
      body: `${tipo} - ${categoria} (${lugar})`,
    },
    data: {
      eventId: event.params.eventId,
      type: isCritical ? "critical_event_created" : "event_created",
      severity: severidad,
      ...(institutionId ? { institutionId: String(institutionId) } : {}),
    },
  });
});

exports.notifyReportCreated = onDocumentCreated(
  "reports/{reportId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    const institutionId = String(data.institutionId || "").trim();
    const reportType = String(data.reportType || "Reporte SG-SST").trim();
    const eventType = String(data.eventType || "Incidente").trim();
    const location = data.location || {};
    const place = String(location.placeName || location.area || "").trim();
    const placeLabel = place.length > 0 ? place : "Sin ubicacion";
    const severity = normalizeKey(data.severity);
    const isCritical =
      severity === "grave" ||
      severity === "alta" ||
      severity === "critical" ||
      severity === "critica";

    let tokens = [];
    if (institutionId) {
      tokens = await collectInstitutionAdminTokens(institutionId);
    } else {
      const adminsSnapshot = await admin
        .firestore()
        .collection("users")
        .where("role", "in", ["admin", "admin_sst", "adminsst"])
        .get();
      tokens = await collectTokens(adminsSnapshot);
    }

    console.log(
      `[FCM][report_created] reportId=${event.params.reportId} institutionId=${institutionId || "none"} tokens=${tokens.length}`
    );

    return sendNotification(tokens, {
      notification: {
        title: isCritical ? "Alerta critica SG-SST" : "Nuevo reporte SG-SST",
        body: `${eventType} - ${reportType} (${placeLabel})`,
      },
      data: {
        type: isCritical ? "critical_event_created" : "event_created",
        reportId: event.params.reportId,
        institutionId,
        severity,
      },
    });
  }
);

exports.notifyReportStatusChanged = onDocumentUpdated(
  "reports/{reportId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeStatus = normalizeReportStatus(before.status || before.estado);
    const afterStatus = normalizeReportStatus(after.status || after.estado);

    if (beforeStatus === afterStatus) {
      return null;
    }

    const reporterUid = String(after.createdBy || before.createdBy || "").trim();
    if (!reporterUid) {
      return null;
    }

    const history = Array.isArray(after.statusHistory) ? after.statusHistory : [];
    const latest = history.length > 0 ? history[history.length - 1] : null;
    const changedBy = String(latest?.changedBy || "").trim();

    if (changedBy && changedBy === reporterUid) {
      return null;
    }

    const tokens = await collectUserTokensByUid(reporterUid);
    if (!tokens.length) {
      return null;
    }

    const caseNumber = String(after.caseNumber || event.params.reportId).trim();
    const label = reportStatusLabel(afterStatus);
    const note = String(latest?.note || "").trim();
    const body = note
      ? `Caso ${caseNumber}: ${label}. ${note}`
      : `Caso ${caseNumber}: ${label}.`;

    return sendNotification(tokens, {
      notification: {
        title: "Actualizacion de reporte",
        body,
      },
      data: {
        type: "report_status_changed",
        reportId: event.params.reportId,
        caseNumber,
        status: afterStatus,
        institutionId: String(after.institutionId || before.institutionId || ""),
      },
    });
  }
);

exports.queueInstitutionPendingEmail = onDocumentCreated(
  "institutions/{institutionId}",
  async (event) => {
    console.log(
      "[MAIL][institution_pending] Envio por correo deshabilitado por configuracion."
    );
    return null;
  }
);

exports.notifyInstitutionPendingPush = onDocumentCreated(
  "institutions/{institutionId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    const status = String(data.status || "pending").trim().toLowerCase();
    if (status !== "pending") {
      return null;
    }

    const institutionId = event.params.institutionId;
    const institutionName = String(data.name || "Institucion").trim();
    const tokens = await collectSuperAdminTokens();
    const payload = {
      notification: {
        title: "Nueva institucion pendiente",
        body: `${institutionName} requiere validacion.`,
      },
      data: {
        type: "institution_pending",
        institutionId,
        institutionName,
      },
    };

    const tokenResult = await sendNotification(tokens, payload);
    if ((tokenResult.successCount || 0) > 0) {
      return tokenResult;
    }

    console.log(
      "[FCM][institution_pending] Sin envios por token. Usando fallback topic=role_admin."
    );
    return sendTopicNotification("role_admin", payload);
  }
);

exports.queueInstitutionApprovedEmail = onDocumentUpdated(
  "institutions/{institutionId}",
  async (event) => {
    console.log(
      "[MAIL][institution_approved] Envio por correo deshabilitado por configuracion."
    );
    return null;
  }
);

exports.notifyInstitutionApprovedPush = onDocumentUpdated(
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
    const tokens = await collectInstitutionRoleTokens(institutionId, [
      "admin_sst",
      "adminsst",
      "user",
      "employee",
    ]);

    return sendNotification(tokens, {
      notification: {
        title: "Institucion aprobada",
        body: `${institutionName} ya esta activa en EduSST.`,
      },
      data: {
        type: "institution_approved",
        institutionId,
        institutionName,
      },
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

exports.notifyTrainingRsvpCreated = onDocumentCreated(
  "institutions/{institutionId}/trainings/{trainingId}/responses/{userId}",
  async (event) => {
    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const responseData = event.data ? event.data.data() : {};

    const trainingSnap = await admin
      .firestore()
      .collection("institutions")
      .doc(institutionId)
      .collection("trainings")
      .doc(trainingId)
      .get();
    const trainingData = trainingSnap.exists ? trainingSnap.data() || {} : {};
    if (String(trainingData.status || "").trim().toLowerCase() === "cancelled") {
      return null;
    }

    const title = String(trainingData.title || "Capacitacion SST").trim();
    const userName = String(
      responseData.userName || responseData.userEmail || event.params.userId
    ).trim();
    const responseLabel = labelRsvpResponse(responseData.response);
    const roleTokens = await collectInstitutionRoleTokens(institutionId, [
      "admin_sst",
      "adminsst",
      "admin",
    ]);
    const createdByUid = String(trainingData.createdBy || "").trim();
    const createdByTokens = await collectUserTokensByUid(createdByUid);
    const tokens = [...new Set([...roleTokens, ...createdByTokens])];
    console.log(
      `[FCM][RSVP][create] institutionId=${institutionId} trainingId=${trainingId} roleTokens=${roleTokens.length} createdByTokens=${createdByTokens.length} totalTokens=${tokens.length}`
    );

    return sendNotification(tokens, {
      notification: {
        title: "Nueva confirmacion de asistencia",
        body: `${userName}: ${responseLabel} en "${title}".`,
      },
      data: {
        type: "training_rsvp_created",
        institutionId,
        trainingId,
        userId: event.params.userId,
        response: String(responseData.response || ""),
      },
    });
  }
);

exports.notifyTrainingRsvpUpdated = onDocumentUpdated(
  "institutions/{institutionId}/trainings/{trainingId}/responses/{userId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const previousResponse = String(before.response || "").trim().toLowerCase();
    const currentResponse = String(after.response || "").trim().toLowerCase();
    if (!currentResponse || currentResponse === previousResponse) {
      return null;
    }

    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const userId = event.params.userId;

    const trainingSnap = await admin
      .firestore()
      .collection("institutions")
      .doc(institutionId)
      .collection("trainings")
      .doc(trainingId)
      .get();
    const trainingData = trainingSnap.exists ? trainingSnap.data() || {} : {};
    if (String(trainingData.status || "").trim().toLowerCase() === "cancelled") {
      return null;
    }

    const title = String(trainingData.title || "Capacitacion SST").trim();
    const userName = String(
      after.userName || after.userEmail || userId
    ).trim();
    const responseLabel = labelRsvpResponse(after.response);
    const roleTokens = await collectInstitutionRoleTokens(institutionId, [
      "admin_sst",
      "adminsst",
      "admin",
    ]);
    const createdByUid = String(trainingData.createdBy || "").trim();
    const createdByTokens = await collectUserTokensByUid(createdByUid);
    const tokens = [...new Set([...roleTokens, ...createdByTokens])];
    console.log(
      `[FCM][RSVP][update] institutionId=${institutionId} trainingId=${trainingId} roleTokens=${roleTokens.length} createdByTokens=${createdByTokens.length} totalTokens=${tokens.length}`
    );

    return sendNotification(tokens, {
      notification: {
        title: "Confirmacion de asistencia actualizada",
        body: `${userName}: ${responseLabel} en "${title}".`,
      },
      data: {
        type: "training_rsvp_updated",
        institutionId,
        trainingId,
        userId,
        response: String(after.response || ""),
      },
    });
  }
);

exports.notifyTrainingVideoWatchedOnCreate = onDocumentCreated(
  "institutions/{institutionId}/trainings/{trainingId}/progress/{userId}",
  async (event) => {
    const progressData = event.data ? event.data.data() : {};
    if (progressData.watched !== true) return null;

    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const userId = event.params.userId;

    const [trainingSnap, userSnap] = await Promise.all([
      admin
        .firestore()
        .collection("institutions")
        .doc(institutionId)
        .collection("trainings")
        .doc(trainingId)
        .get(),
      admin.firestore().collection("users").doc(userId).get(),
    ]);

    const trainingData = trainingSnap.exists ? trainingSnap.data() || {} : {};
    if (String(trainingData.status || "").trim().toLowerCase() === "cancelled") {
      return null;
    }
    const title = String(trainingData.title || "Capacitacion SST").trim();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const userName = String(
      userData.displayName || userData.email || userId
    ).trim();

    const tokens = await collectInstitutionRoleTokens(institutionId, [
      "admin_sst",
      "adminsst",
    ]);

    return sendNotification(tokens, {
      notification: {
        title: "Video completado",
        body: `${userName} marco como visto "${title}".`,
      },
      data: {
        type: "training_video_watched",
        institutionId,
        trainingId,
        userId,
      },
    });
  }
);

exports.notifyTrainingVideoWatchedOnUpdate = onDocumentUpdated(
  "institutions/{institutionId}/trainings/{trainingId}/progress/{userId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    if (before.watched === true || after.watched !== true) {
      return null;
    }

    const institutionId = event.params.institutionId;
    const trainingId = event.params.trainingId;
    const userId = event.params.userId;

    const [trainingSnap, userSnap] = await Promise.all([
      admin
        .firestore()
        .collection("institutions")
        .doc(institutionId)
        .collection("trainings")
        .doc(trainingId)
        .get(),
      admin.firestore().collection("users").doc(userId).get(),
    ]);

    const trainingData = trainingSnap.exists ? trainingSnap.data() || {} : {};
    if (String(trainingData.status || "").trim().toLowerCase() === "cancelled") {
      return null;
    }
    const title = String(trainingData.title || "Capacitacion SST").trim();
    const userData = userSnap.exists ? userSnap.data() || {} : {};
    const userName = String(
      userData.displayName || userData.email || userId
    ).trim();

    const tokens = await collectInstitutionRoleTokens(institutionId, [
      "admin_sst",
      "adminsst",
    ]);

    return sendNotification(tokens, {
      notification: {
        title: "Video completado",
        body: `${userName} marco como visto "${title}".`,
      },
      data: {
        type: "training_video_watched",
        institutionId,
        trainingId,
        userId,
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

exports.notifyActionPlanAssignedOnCreate = onDocumentCreated(
  "planesDeAccion/{planId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    const responsibleUid = String(data.responsibleUid || "").trim();
    if (!responsibleUid) return null;

    const title = String(data.title || "Plan de accion").trim();
    const dueLabel = formatDateTimeLabel(data.dueDate || data.fechaLimite);
    const dueText = dueLabel ? ` Fecha limite: ${dueLabel}.` : "";
    const body = `Se te asigno "${title}".${dueText}`;
    const tokens = await collectUserTokensByUid(responsibleUid);

    console.log(
      `[FCM][action_plan_assigned] planId=${event.params.planId} responsibleUid=${responsibleUid} tokens=${tokens.length}`
    );

    return sendNotification(tokens, {
      notification: {
        title: "Nuevo plan de accion",
        body,
      },
      data: {
        type: "action_plan_assigned",
        planId: event.params.planId,
        originReportId: String(data.originReportId || data.eventoId || ""),
        institutionId: String(data.institutionId || ""),
      },
    });
  }
);

exports.notifyActionPlanReadyForValidation = onDocumentUpdated(
  "planesDeAccion/{planId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeStatus = normalizeActionPlanStatus(
      before.status || before.estado
    );
    const afterStatus = normalizeActionPlanStatus(after.status || after.estado);
    if (beforeStatus === afterStatus || afterStatus !== "ejecutado") {
      return null;
    }

    const assignedByUid = String(after.assignedBy || "").trim();
    const institutionId = String(after.institutionId || "").trim();
    const planId = event.params.planId;
    const title = String(after.title || "Plan de accion").trim();

    const tokenSet = new Set();
    if (assignedByUid) {
      const assignedByTokens = await collectUserTokensByUid(assignedByUid);
      for (const token of assignedByTokens) tokenSet.add(token);
    }
    if (institutionId) {
      const adminTokens = await collectInstitutionAdminTokens(institutionId);
      for (const token of adminTokens) tokenSet.add(token);
    }

    const tokens = [...tokenSet];
    if (!tokens.length) return null;

    console.log(
      `[FCM][action_plan_validation] planId=${planId} institutionId=${institutionId} tokens=${tokens.length}`
    );

    return sendNotification(tokens, {
      notification: {
        title: "Plan pendiente de validacion",
        body: `El plan "${title}" fue marcado como ejecutado.`,
      },
      data: {
        type: "action_plan_pending_validation",
        planId,
        originReportId: String(after.originReportId || after.eventoId || ""),
        institutionId,
      },
    });
  }
);

exports.notifyActionPlanDeadlineReminders = onSchedule(
  "every 60 minutes",
  async () => {
    const nowMs = Date.now();
    const firestore = admin.firestore();
    const [pendingSnap, progressSnap] = await Promise.all([
      firestore.collection("planesDeAccion").where("status", "==", "pendiente").get(),
      firestore.collection("planesDeAccion").where("status", "==", "en_curso").get(),
    ]);
    const docs = [...pendingSnap.docs, ...progressSnap.docs];
    const userTokenCache = new Map();
    const adminTokenCache = new Map();

    for (const doc of docs) {
      const data = doc.data() || {};
      const dueMs = timestampToMillis(data.dueDate || data.fechaLimite);
      if (!dueMs) continue;

      const status = normalizeActionPlanStatus(data.status || data.estado);
      if (status === "cerrado" || status === "verificado") continue;

      const flags = data.reminderFlags || {};
      const responsibleUid = String(data.responsibleUid || "").trim();
      const institutionId = String(data.institutionId || "").trim();
      const title = String(data.title || "Plan de accion").trim();

      let changed = false;
      const should72h = shouldSendReminder(dueMs, nowMs, 72, 60);
      const should24h = shouldSendReminder(dueMs, nowMs, 24, 60);
      const shouldOverdue = dueMs <= nowMs;

      const getResponsibleTokens = async () => {
        if (!responsibleUid) return [];
        if (!userTokenCache.has(responsibleUid)) {
          userTokenCache.set(
            responsibleUid,
            await collectUserTokensByUid(responsibleUid)
          );
        }
        return userTokenCache.get(responsibleUid) || [];
      };

      if (should72h && !flags.sent72h) {
        const tokens = await getResponsibleTokens();
        await sendNotification(tokens, {
          notification: {
            title: "Recordatorio de plan de accion",
            body: `"${title}" vence en 72 horas.`,
          },
          data: {
            type: "action_plan_due_72h",
            planId: doc.id,
            institutionId,
          },
        });
        flags.sent72h = admin.firestore.FieldValue.serverTimestamp();
        changed = true;
      }

      if (should24h && !flags.sent24h) {
        const tokens = await getResponsibleTokens();
        await sendNotification(tokens, {
          notification: {
            title: "Plan proximo a vencer",
            body: `"${title}" vence en 24 horas.`,
          },
          data: {
            type: "action_plan_due_24h",
            planId: doc.id,
            institutionId,
          },
        });
        flags.sent24h = admin.firestore.FieldValue.serverTimestamp();
        changed = true;
      }

      if (shouldOverdue && !flags.sentOverdue) {
        const tokenSet = new Set();
        const responsibleTokens = await getResponsibleTokens();
        for (const token of responsibleTokens) tokenSet.add(token);
        if (institutionId) {
          if (!adminTokenCache.has(institutionId)) {
            adminTokenCache.set(
              institutionId,
              await collectInstitutionAdminTokens(institutionId)
            );
          }
          const adminTokens = adminTokenCache.get(institutionId) || [];
          for (const token of adminTokens) tokenSet.add(token);
        }
        await sendNotification([...tokenSet], {
          notification: {
            title: "Plan vencido",
            body: `"${title}" supero la fecha limite.`,
          },
          data: {
            type: "action_plan_overdue",
            planId: doc.id,
            institutionId,
          },
        });
        flags.sentOverdue = admin.firestore.FieldValue.serverTimestamp();
        changed = true;
      }

      if (changed) {
        await doc.ref.set(
          { reminderFlags: flags, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
      }
    }

    return null;
  }
);

exports.notifyInspectionAssignedOnCreate = onDocumentCreated(
  "institutions/{institutionId}/inspections/{inspectionId}",
  async (event) => {
    const data = event.data ? event.data.data() : {};
    const assignedToUid = String(data.assignedToUid || "").trim();
    if (!assignedToUid) return null;

    const tokens = await collectUserTokensByUid(assignedToUid);
    const title = String(data.title || "Inspeccion SST").trim();
    const whenLabel = formatDateTimeLabel(data.scheduledAt);
    const whenText = whenLabel ? ` Programada: ${whenLabel}.` : "";

    return sendNotification(tokens, {
      notification: {
        title: "Nueva inspeccion asignada",
        body: `"${title}".${whenText}`,
      },
      data: {
        type: "inspection_assigned",
        inspectionId: event.params.inspectionId,
        institutionId: event.params.institutionId,
      },
    });
  }
);

exports.notifyInspectionAssignmentChanged = onDocumentUpdated(
  "institutions/{institutionId}/inspections/{inspectionId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeUid = String(before.assignedToUid || "").trim();
    const afterUid = String(after.assignedToUid || "").trim();
    if (!afterUid || beforeUid === afterUid) return null;

    const tokens = await collectUserTokensByUid(afterUid);
    const title = String(after.title || "Inspeccion SST").trim();

    return sendNotification(tokens, {
      notification: {
        title: "Inspeccion reasignada",
        body: `Ahora eres responsable de "${title}".`,
      },
      data: {
        type: "inspection_reassigned",
        inspectionId: event.params.inspectionId,
        institutionId: event.params.institutionId,
      },
    });
  }
);

exports.notifyInspectionStatusUpdates = onDocumentUpdated(
  "institutions/{institutionId}/inspections/{inspectionId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const beforeStatus = normalizeInspectionStatus(before.status);
    const afterStatus = normalizeInspectionStatus(after.status);
    if (beforeStatus === afterStatus) return null;

    const inspectionId = event.params.inspectionId;
    const institutionId = event.params.institutionId;
    const title = String(after.title || "Inspeccion SST").trim();
    const assignedToUid = String(after.assignedToUid || "").trim();
    const createdBy = String(after.createdBy || "").trim();
    const tokenSet = new Set();

    if (afterStatus === "cancelled" && assignedToUid) {
      const assignedTokens = await collectUserTokensByUid(assignedToUid);
      for (const token of assignedTokens) tokenSet.add(token);
    }

    if (
      (afterStatus === "completed" || afterStatus === "completed_with_findings") &&
      createdBy
    ) {
      const creatorTokens = await collectUserTokensByUid(createdBy);
      for (const token of creatorTokens) tokenSet.add(token);
    }

    const tokens = [...tokenSet];
    if (!tokens.length) return null;

    let body = `La inspeccion "${title}" actualizo su estado.`;
    let type = "inspection_status_updated";
    if (afterStatus === "cancelled") {
      body = `La inspeccion "${title}" fue cancelada.`;
      type = "inspection_cancelled";
    } else if (afterStatus === "completed_with_findings") {
      body = `Finalizo "${title}" con hallazgos.`;
      type = "inspection_completed_with_findings";
    } else if (afterStatus === "completed") {
      body = `Finalizo "${title}" sin hallazgos.`;
      type = "inspection_completed";
    }

    return sendNotification(tokens, {
      notification: {
        title: "Actualizacion de inspeccion",
        body,
      },
      data: {
        type,
        inspectionId,
        institutionId,
        status: afterStatus,
      },
    });
  }
);

exports.notifyInspectionReminders = onSchedule("every 30 minutes", async () => {
  const firestore = admin.firestore();
  const nowMs = Date.now();
  const [scheduledSnap, inProgressSnap] = await Promise.all([
    firestore.collectionGroup("inspections").where("status", "==", "scheduled").get(),
    firestore
      .collectionGroup("inspections")
      .where("status", "==", "in_progress")
      .get(),
  ]);
  const docs = [...scheduledSnap.docs, ...inProgressSnap.docs];
  const userTokenCache = new Map();
  const adminTokenCache = new Map();

  for (const doc of docs) {
    const data = doc.data() || {};
    const institutionId = doc.ref.parent.parent ? doc.ref.parent.parent.id : "";
    const assignedToUid = String(data.assignedToUid || "").trim();
    if (!assignedToUid) continue;

    const scheduledMs = timestampToMillis(data.scheduledAt || data.dueAt);
    const dueMs = timestampToMillis(data.dueAt || data.scheduledAt);
    if (!scheduledMs || !dueMs) continue;

    const flags = data.reminderFlags || {};
    const title = String(data.title || "Inspeccion SST").trim();
    const should24h = shouldSendReminder(scheduledMs, nowMs, 24, 30);
    const should1h = shouldSendReminder(scheduledMs, nowMs, 1, 20);
    const shouldOverdue = dueMs <= nowMs;
    let changed = false;

    if (!userTokenCache.has(assignedToUid)) {
      userTokenCache.set(
        assignedToUid,
        await collectUserTokensByUid(assignedToUid)
      );
    }
    const assignedTokens = userTokenCache.get(assignedToUid) || [];

    if (should24h && !flags.sent24h) {
      await sendNotification(assignedTokens, {
        notification: {
          title: "Inspeccion programada",
          body: `"${title}" inicia en 24 horas.`,
        },
        data: {
          type: "inspection_reminder_24h",
          inspectionId: doc.id,
          institutionId,
        },
      });
      flags.sent24h = admin.firestore.FieldValue.serverTimestamp();
      changed = true;
    }

    if (should1h && !flags.sent1h) {
      await sendNotification(assignedTokens, {
        notification: {
          title: "Recordatorio de inspeccion",
          body: `"${title}" inicia en 1 hora.`,
        },
        data: {
          type: "inspection_reminder_1h",
          inspectionId: doc.id,
          institutionId,
        },
      });
      flags.sent1h = admin.firestore.FieldValue.serverTimestamp();
      changed = true;
    }

    if (shouldOverdue && !flags.sentOverdue) {
      const tokenSet = new Set(assignedTokens);
      if (institutionId) {
        if (!adminTokenCache.has(institutionId)) {
          adminTokenCache.set(
            institutionId,
            await collectInstitutionAdminTokens(institutionId)
          );
        }
        const adminTokens = adminTokenCache.get(institutionId) || [];
        for (const token of adminTokens) tokenSet.add(token);
      }
      await sendNotification([...tokenSet], {
        notification: {
          title: "Inspeccion vencida",
          body: `"${title}" supero su fecha limite.`,
        },
        data: {
          type: "inspection_overdue",
          inspectionId: doc.id,
          institutionId,
        },
      });
      flags.sentOverdue = admin.firestore.FieldValue.serverTimestamp();
      changed = true;
    }

    if (changed) {
      await doc.ref.set(
        { reminderFlags: flags, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
    }
  }

  return null;
});

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
      beforeVerification !== "requiere_ajuste"
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
