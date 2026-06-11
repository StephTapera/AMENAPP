// TODO(gate: HUMAN-MACHINE) — MIGRATE_TO_V2: still using Gen1 runWith() pattern; migration requires re-deploy + smoke-test
// authHelpersV1.js — v1 Cloud Functions (avoids Cloud Run quota)
// Extracts banUserPhone and updateBirthYear from authenticationHelpers.js
// as v1 callables so they can be deployed without consuming Cloud Run slots.

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { computeAgeTier } = require("./ageTier");

function hashPhoneNumber(phoneNumber) {
  return crypto.createHash("sha256").update(phoneNumber.trim()).digest("hex");
}

const TIER_ORDER = ["blocked", "tierB", "tierC", "tierD"];

// ─────────────────────────────────────────────────────────────────────────────
// banUserPhone — Admin-only callable (H-03)
// Hashes the target user's phone number and writes it to bannedPhones/{hash}.
// Future registration attempts using the same phone are blocked in onUserDocCreated.
// ─────────────────────────────────────────────────────────────────────────────
exports.banUserPhone = functions.region("us-central1").https.onCall(async (data, context) => {
  if (!context.auth || context.auth.token.admin !== true) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only admins can ban phone numbers."
    );
  }

  const { userId } = data;
  if (!userId || typeof userId !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "userId (string) is required.");
  }

  const adminUid = context.auth.uid;

  let userRecord;
  try {
    userRecord = await admin.auth().getUser(userId);
  } catch (err) {
    console.error(`[banUserPhone] getUser(${userId}) failed:`, err);
    throw new functions.https.HttpsError("not-found", "User not found.");
  }

  const phoneNumber = userRecord.phoneNumber || null;
  if (!phoneNumber) {
    console.warn(`[banUserPhone] User ${userId} has no phone number — skipping phone ban.`);
    return { success: true, phoneNumber: null, note: "no_phone_number" };
  }

  const hashedPhone = hashPhoneNumber(phoneNumber);

  await admin.firestore().collection("bannedPhones").doc(hashedPhone).set({
    hashedPhone,
    bannedAt: admin.firestore.FieldValue.serverTimestamp(),
    bannedBy: adminUid,
    userId,
    reason: "ban_evasion_prevention",
  });

  console.log(`[banUserPhone] Phone banned for userId=${userId} by admin=${adminUid}`);
  return { success: true, userId, hashedPhone };
});

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
