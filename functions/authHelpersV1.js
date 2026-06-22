// TODO(gate: HUMAN-MACHINE) — MIGRATE_TO_V2: still using Gen1 runWith() pattern; migration requires re-deploy + smoke-test
// authHelpersV1.js — v1 Cloud Functions (avoids Cloud Run quota)
// Contains: updateBirthYear only.
//
// SECURITY FIX (HIGH 2026-06-11): banUserPhone has been removed from this file.
// The Gen2 copy in authenticationHelpers.js enforces App Check via enforceAppCheck: true.
// This v1 duplicate lacked App Check, meaning a valid Firebase Auth token (no App Check)
// was sufficient to call it from scripts. Only the Gen2 version in authenticationHelpers.js
// should be used. Clients must be updated to call the Gen2 endpoint.
// Verify in Firebase Console that no clients call the v1 banUserPhone endpoint directly.

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { computeAgeTier } = require("./ageTier");

const TIER_ORDER = ["blocked", "tierB", "tierC", "tierD"];

// ─────────────────────────────────────────────────────────────────────────────
// updateBirthYear — server-enforced age-downgrade protection (M-02)
// Adults (tierD) cannot re-declare as minors without moderator review.
// ─────────────────────────────────────────────────────────────────────────────
exports.updateBirthYear = functions.region("us-central1").https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be authenticated.");
  }

  const uid = context.auth.uid;
  const { birthYear } = data || {};

  if (!birthYear || typeof birthYear !== "number" || birthYear < 1900 || birthYear > new Date().getFullYear()) {
    throw new functions.https.HttpsError("invalid-argument", "A valid birthYear (number) is required.");
  }

  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError("not-found", "User document not found.");
  }

  const existingData = userDoc.data();
  const currentTier = existingData.ageTier || "blocked";
  const currentYear = new Date().getFullYear();
  const newTier = computeAgeTier(birthYear, currentYear);

  // M-02: Prevent age downgrade. Adults cannot re-declare as minors.
  if (TIER_ORDER.indexOf(newTier) < TIER_ORDER.indexOf(currentTier)) {
    console.warn(`[updateBirthYear] Downgrade attempt uid=${uid} ${currentTier} -> ${newTier}`);
    throw new functions.https.HttpsError(
      "permission-denied",
      "Age changes that reduce your age tier require moderator review."
    );
  }

  await db.collection("users").doc(uid).update({
    birthYear,
    ageTier: newTier,
    ageTierSetAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`[updateBirthYear] uid=${uid} birthYear=${birthYear} ageTier=${newTier}`);
  return { success: true, ageTier: newTier };
});
