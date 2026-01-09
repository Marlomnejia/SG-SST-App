"use strict";

const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

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
    return null;
  }
  const chunks = [];
  for (let i = 0; i < tokens.length; i += 500) {
    chunks.push(tokens.slice(i, i + 500));
  }
  for (const chunk of chunks) {
    await admin.messaging().sendMulticast({
      tokens: chunk,
      notification: payload.notification,
      data: payload.data || {},
    });
  }
  return null;
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

  const adminsSnapshot = await admin
    .firestore()
    .collection("users")
    .where("role", "==", "admin")
    .where("notificationsEnabled", "==", true)
    .get();

  const tokens = await collectTokens(adminsSnapshot);
  return sendNotification(tokens, {
    notification: {
      title: "Nuevo reporte SG-SST",
      body: `${tipo} - ${categoria} (${lugar})`,
    },
    data: {
      eventId: event.params.eventId,
      type: "event_created",
    },
  });
});
