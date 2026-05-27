import { readFile } from "node:fs/promises";
import process from "node:process";
import { initializeApp, applicationDefault, cert } from "firebase-admin/app";
import { FieldValue, GeoPoint, Timestamp, getFirestore } from "firebase-admin/firestore";

const seedPath = new URL("./smartChurches.seed.json", import.meta.url);
const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (serviceAccountPath) {
  const serviceAccount = JSON.parse(await readFile(serviceAccountPath, "utf8"));
  initializeApp({ credential: cert(serviceAccount) });
} else {
  initializeApp({ credential: applicationDefault() });
}

const db = getFirestore();
const churches = JSON.parse(await readFile(seedPath, "utf8"));
const batch = db.batch();

for (const church of churches) {
  const ref = db.collection("churches").doc(church.id);
  const createdAt = church.createdAt ? Timestamp.fromDate(new Date(church.createdAt)) : FieldValue.serverTimestamp();
  const updatedAt = church.updatedAt ? Timestamp.fromDate(new Date(church.updatedAt)) : FieldValue.serverTimestamp();
  const geoPoint = new GeoPoint(church.location.lat, church.location.lng);

  batch.set(ref, {
    ...church,
    geoPoint,
    createdAt,
    updatedAt,
  }, { merge: true });
}

await batch.commit();
console.log(`Imported ${churches.length} smart church seed docs into churches.`);
