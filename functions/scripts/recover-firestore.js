/* eslint-disable no-console */
const path = require("path");
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

function randomInviteCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

function buildUserPayload({
  userRecord,
  role,
  institutionId,
  now,
  forceRewrite,
  existing,
}) {
  const base = {
    email: userRecord.email || "",
    displayName:
      userRecord.displayName ||
      ((userRecord.email || "").includes("@")
        ? userRecord.email.split("@")[0]
        : "Usuario"),
    photoUrl: userRecord.photoURL || null,
    jobTitle: role === "admin_sst" ? "Administrador SG-SST" : "",
    institutionId: institutionId || null,
    campus: "",
    phone: "",
    notificationsEnabled: true,
    fcmTokens: [],
    role,
    updatedAt: now,
  };

  if (!existing || forceRewrite) {
    return {
      ...base,
      createdAt: existing?.createdAt || now,
    };
  }

  return {
    ...existing,
    ...base,
    createdAt: existing.createdAt || now,
  };
}

async function listAllAuthUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

async function main() {
  const args = parseArgs(process.argv);
  const projectId = requireArg(args, "projectId");
  const institutionName = requireArg(args, "institutionName");
  const adminSstUidArg = (args.adminSstUid || "").trim();
  const adminSstEmail = (args.adminSstEmail || "").trim().toLowerCase();
  if (!adminSstUidArg && !adminSstEmail) {
    throw new Error("Debes enviar --adminSstUid o --adminSstEmail");
  }
  const institutionId = (args.institutionId || "").trim() || undefined;
  const superAdminUid = (args.superAdminUid || "").trim() || "";
  const superAdminEmail = (args.superAdminEmail || "").trim().toLowerCase();
  const assignAllUsers = toBool(args.assignAllUsers, true);
  const forceRewriteUsers = toBool(args.forceRewriteUsers, false);
  const serviceAccountPath = (args.serviceAccount || "").trim();

  if (serviceAccountPath) {
    const absolutePath = path.resolve(serviceAccountPath);
    const serviceAccount = require(absolutePath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
    });
  } else {
    admin.initializeApp({projectId});
  }

  const firestore = admin.firestore();
  const auth = admin.auth();
  const now = admin.firestore.FieldValue.serverTimestamp();

  console.log("[recover] Proyecto:", projectId);
  console.log("[recover] institutionName:", institutionName);
  if (adminSstUidArg) console.log("[recover] adminSstUid:", adminSstUidArg);
  if (adminSstEmail) console.log("[recover] adminSstEmail:", adminSstEmail);
  if (superAdminUid) console.log("[recover] superAdminUid:", superAdminUid);
  if (superAdminEmail) console.log("[recover] superAdminEmail:", superAdminEmail);

  const institutionRef = institutionId
    ? firestore.collection("institutions").doc(institutionId)
    : firestore.collection("institutions").doc();
  const institutionSnap = await institutionRef.get();

  if (!institutionSnap.exists) {
    const inviteCode = randomInviteCode();
    await institutionRef.set({
      name: institutionName,
      nit: "RECOVERY-NIT",
      department: "N/A",
      city: "N/A",
      address: "N/A",
      type: "private",
      institutionPhone: "N/A",
      rectorCellPhone: "N/A",
      email: "recovery@local",
      documentsUrls: {},
      inviteCode,
      status: "active",
      isActive: true,
      createdAt: now,
      updatedAt: now,
    });
    console.log("[recover] Institucion creada:", institutionRef.id);
  } else {
    await institutionRef.set(
      {
        status: "active",
        isActive: true,
        updatedAt: now,
      },
      {merge: true},
    );
    console.log("[recover] Institucion existente reactivada:", institutionRef.id);
  }

  const userRecords = await listAllAuthUsers(auth);
  console.log(`[recover] Usuarios Auth encontrados: ${userRecords.length}`);

  let adminSstUid = adminSstUidArg;
  if (!adminSstUid && adminSstEmail) {
    const adminUser = userRecords.find(
      (u) => (u.email || "").toLowerCase() === adminSstEmail,
    );
    if (!adminUser) {
      throw new Error(
        `No se encontró usuario Auth para --adminSstEmail=${adminSstEmail}`,
      );
    }
    adminSstUid = adminUser.uid;
    console.log("[recover] adminSstUid resuelto por email:", adminSstUid);
  }

  let createdOrUpdated = 0;
  for (const record of userRecords) {
    let role = "user";
    let userInstitutionId = assignAllUsers ? institutionRef.id : null;

    if (record.uid === adminSstUid) {
      role = "admin_sst";
      userInstitutionId = institutionRef.id;
    } else if (
      (superAdminUid && record.uid === superAdminUid) ||
      (superAdminEmail && (record.email || "").toLowerCase() === superAdminEmail)
    ) {
      role = "admin";
      userInstitutionId = null;
    }

    const userRef = firestore.collection("users").doc(record.uid);
    const userSnap = await userRef.get();
    const existing = userSnap.exists ? userSnap.data() : null;
    const payload = buildUserPayload({
      userRecord: record,
      role,
      institutionId: userInstitutionId,
      now,
      forceRewrite: forceRewriteUsers,
      existing,
    });

    await userRef.set(payload, {merge: true});
    createdOrUpdated++;
  }

  console.log(`[recover] users/{uid} recreados/actualizados: ${createdOrUpdated}`);
  console.log("[recover] institutionId final:", institutionRef.id);
  console.log("[recover] Listo.");
}

main().catch((error) => {
  console.error("[recover] ERROR:", error.message);
  process.exitCode = 1;
});
