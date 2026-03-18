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

async function main() {
  const args = parseArgs(process.argv);
  const projectId = requireArg(args, "projectId");
  const serviceAccountPath = requireArg(args, "serviceAccount");
  const apply = toBool(args.apply, false);

  const absolutePath = path.resolve(serviceAccountPath);
  const serviceAccount = require(absolutePath);

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  const firestore = admin.firestore();
  const rootCollections = await firestore.listCollections();
  const collectionIds = rootCollections.map((c) => c.id);

  console.log(`[wipe] Proyecto: ${projectId}`);
  console.log(`[wipe] Colecciones raiz detectadas: ${collectionIds.length}`);
  for (const id of collectionIds) {
    console.log(`  - ${id}`);
  }

  if (!apply) {
    console.log("[wipe] Modo simulacion (--apply false). No se elimino nada.");
    return;
  }

  for (const collectionRef of rootCollections) {
    console.log(`[wipe] Eliminando coleccion: ${collectionRef.id}`);
    await firestore.recursiveDelete(collectionRef);
  }

  const after = await firestore.listCollections();
  console.log(`[wipe] Colecciones raiz restantes: ${after.length}`);
  console.log("[wipe] Limpieza total de Firestore completada.");
}

main().catch((error) => {
  console.error("[wipe] ERROR:", error.message);
  process.exitCode = 1;
});

