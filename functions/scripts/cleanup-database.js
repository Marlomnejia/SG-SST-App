/* eslint-disable no-console */
const path = require("path");
const fs = require("fs");
const admin = require("firebase-admin");

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      out[key] = "true";
      continue;
    }
    out[key] = next;
    i++;
  }
  return out;
}

function toBool(value, fallback = false) {
  if (value == null) return fallback;
  const normalized = String(value).trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes";
}

function requireArg(args, key) {
  const value = (args[key] || "").trim();
  if (!value) {
    throw new Error(`Falta argumento requerido --${key}`);
  }
  return value;
}

async function listAllAuthUids(auth) {
  const uids = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      uids.push(user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return new Set(uids);
}

function loadAuthUidsFromExport(authUsersFilePath) {
  const absolutePath = path.resolve(authUsersFilePath);
  const raw = fs.readFileSync(absolutePath, "utf8");
  const parsed = JSON.parse(raw);
  const users = Array.isArray(parsed.users) ? parsed.users : [];
  const uids = new Set();
  for (const user of users) {
    const uid = String(user.localId || user.uid || user.userId || "").trim();
    if (uid) uids.add(uid);
  }
  return uids;
}

async function main() {
  const args = parseArgs(process.argv);
  const projectId = requireArg(args, "projectId");
  const serviceAccountPath = requireArg(args, "serviceAccount");
  const authUsersFile = (args.authUsersFile || "").trim();
  const apply = toBool(args.apply, false);

  const absolutePath = path.resolve(serviceAccountPath);
  const serviceAccount = require(absolutePath);

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  const firestore = admin.firestore();
  const authUids = authUsersFile
    ? loadAuthUidsFromExport(authUsersFile)
    : await listAllAuthUids(admin.auth());
  const institutionsSnap = await firestore.collection("institutions").get();
  const institutionIds = new Set(institutionsSnap.docs.map((d) => d.id));

  const summary = {
    usersOrphans: 0,
    invitationsInvalid: 0,
    responsesOrphans: 0,
    attendanceOrphans: 0,
    progressOrphans: 0,
    readsOrphans: 0,
    totalDeletes: 0,
  };

  const deleteRefs = [];

  const usersSnap = await firestore.collection("users").get();
  for (const doc of usersSnap.docs) {
    if (!authUids.has(doc.id)) {
      summary.usersOrphans++;
      deleteRefs.push(doc.ref);
    }
  }

  const invitationsSnap = await firestore.collection("invitations").get();
  for (const doc of invitationsSnap.docs) {
    const data = doc.data() || {};
    const institutionId = String(data.institutionId || "").trim();
    if (!institutionId || !institutionIds.has(institutionId)) {
      summary.invitationsInvalid++;
      deleteRefs.push(doc.ref);
    }
  }

  const responsesSnap = await firestore.collectionGroup("responses").get();
  for (const doc of responsesSnap.docs) {
    if (!authUids.has(doc.id)) {
      summary.responsesOrphans++;
      deleteRefs.push(doc.ref);
    }
  }

  const attendanceSnap = await firestore.collectionGroup("attendance").get();
  for (const doc of attendanceSnap.docs) {
    if (!authUids.has(doc.id)) {
      summary.attendanceOrphans++;
      deleteRefs.push(doc.ref);
    }
  }

  const progressSnap = await firestore.collectionGroup("progress").get();
  for (const doc of progressSnap.docs) {
    if (!authUids.has(doc.id)) {
      summary.progressOrphans++;
      deleteRefs.push(doc.ref);
    }
  }

  const readsSnap = await firestore.collectionGroup("reads").get();
  for (const doc of readsSnap.docs) {
    if (!authUids.has(doc.id)) {
      summary.readsOrphans++;
      deleteRefs.push(doc.ref);
    }
  }

  summary.totalDeletes = deleteRefs.length;

  console.log(`[cleanup] Proyecto: ${projectId}`);
  console.log(`[cleanup] Usuarios en Auth: ${authUids.size}`);
  console.log(`[cleanup] Instituciones: ${institutionIds.size}`);
  console.log("[cleanup] Detectado:");
  console.log(`  users huérfanos: ${summary.usersOrphans}`);
  console.log(`  invitations inválidas: ${summary.invitationsInvalid}`);
  console.log(`  responses huérfanas: ${summary.responsesOrphans}`);
  console.log(`  attendance huérfanas: ${summary.attendanceOrphans}`);
  console.log(`  progress huérfanas: ${summary.progressOrphans}`);
  console.log(`  reads huérfanas: ${summary.readsOrphans}`);
  console.log(`  TOTAL a eliminar: ${summary.totalDeletes}`);

  if (!apply) {
    console.log("[cleanup] Modo simulación (--apply false). No se eliminó nada.");
    return;
  }

  const writer = firestore.bulkWriter();
  let deleted = 0;
  writer.onWriteResult(() => {
    deleted++;
  });

  for (const ref of deleteRefs) {
    writer.delete(ref);
  }

  await writer.close();
  console.log(`[cleanup] Eliminación completada. Docs eliminados: ${deleted}`);
}

main().catch((error) => {
  console.error("[cleanup] ERROR:", error.message);
  process.exitCode = 1;
});
