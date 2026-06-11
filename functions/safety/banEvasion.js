"use strict";

/**
 * banEvasion.js
 *
 * Detects and blocks ban-evasion attempts on the AMEN platform.
 *
 * Privacy model:
 *   Raw phone numbers are NEVER stored.  The caller is responsible for
 *   normalising the phone number (E.164) and computing SHA-256 before passing
 *   it here.  This module only ever sees and stores the hash.
 *
 * Detection signals:
 *   phoneHash         — SHA-256 hex of normalised phone number
 *   deviceFingerprint — Opaque string produced by the client (IDFV, FID, or
 *                       a composite of stable device attributes).  Treat as
 *                       best-effort; a determined evader can rotate it.
 *
 * Exports:
 *   checkBanEvasion(db, uid, phoneHash, deviceFingerprint)
 *   recordBanEvasionSignal(db, bannedUid, phoneHash, deviceFingerprint)
 */

const { FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");

// ─── Collection names ─────────────────────────────────────────────────────────

const COL_BANNED_IDENTIFIERS = "bannedIdentifiers";
const COL_ACCOUNT_SUSPENSIONS = "accountSuspensions";
const COL_BAN_EVASION_CASES   = "banEvasionCases";
const COL_USERS                = "users";

// ─── checkBanEvasion ──────────────────────────────────────────────────────────

/**
 * Checks whether a newly-created (or recently-authenticated) account matches
 * any identifier belonging to a banned user.
 *
 * If a match is found:
 *   1. The new account is auto-suspended (status = "suspended_ban_evasion").
 *   2. A ban-evasion review case is created in banEvasionCases/{caseId}.
 *   3. The user's profile is flagged so the app can gate access immediately.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid                New account UID being checked
 * @param {string|null} phoneHash     SHA-256 hex of normalised E.164 phone, or null
 * @param {string|null} deviceFingerprint  Opaque device identifier, or null
 * @returns {Promise<{
 *   isBanEvader: boolean,
 *   matchedOn: string[],    // which signals matched: "phone" | "device"
 *   caseId: string|null,
 * }>}
 */
async function checkBanEvasion(db, uid, phoneHash, deviceFingerprint) {
  if (!db)  throw new Error("[banEvasion] db is required");
  if (!uid) throw new Error("[banEvasion] uid is required");

  const matchedOn = [];
  const matchedBannedUids = new Set();

  // ── Check phoneHash ───────────────────────────────────────────────────────
  if (phoneHash) {
    const phoneSnap = await db
      .collection(COL_BANNED_IDENTIFIERS)
      .where("phoneHash", "==", phoneHash)
      .where("active", "==", true)
      .limit(1)
      .get();

    if (!phoneSnap.empty) {
      matchedOn.push("phone");
      phoneSnap.docs.forEach((d) => {
        if (d.data().bannedUid) matchedBannedUids.add(d.data().bannedUid);
      });
    }
  }

  // ── Check deviceFingerprint ───────────────────────────────────────────────
  if (deviceFingerprint) {
    const deviceSnap = await db
      .collection(COL_BANNED_IDENTIFIERS)
      .where("deviceFingerprint", "==", deviceFingerprint)
      .where("active", "==", true)
      .limit(1)
      .get();

    if (!deviceSnap.empty) {
      matchedOn.push("device");
      deviceSnap.docs.forEach((d) => {
        if (d.data().bannedUid) matchedBannedUids.add(d.data().bannedUid);
      });
    }
  }

  if (matchedOn.length === 0) {
    return { isBanEvader: false, matchedOn: [], caseId: null };
  }

  // ── Matched — auto-suspend and open a review case ─────────────────────────
  const caseId = crypto.randomUUID();
  const batch  = db.batch();

  // 1. Suspend the new account.
  batch.set(
    db.collection(COL_ACCOUNT_SUSPENSIONS).doc(uid),
    {
      uid,
      status:    "suspended_ban_evasion",
      reason:    "ban_evasion_auto_detected",
      matchedOn,
      caseId,
      createdAt: FieldValue.serverTimestamp(),
      reviewedAt: null,
      reviewedBy: null,
    }
  );

  // 2. Flag the user document.
  batch.set(
    db.collection(COL_USERS).doc(uid),
    {
      accountStatus:        "suspended_ban_evasion",
      banEvasionCaseId:     caseId,
      banEvasionDetectedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // 3. Open a ban-evasion review case (immutable — do not update, only create).
  batch.set(
    db.collection(COL_BAN_EVASION_CASES).doc(caseId),
    {
      caseId,
      newUid:           uid,
      matchedOn,
      matchedBannedUids: Array.from(matchedBannedUids),
      // Store hashes for audit trail, never raw values.
      phoneHash:         phoneHash ?? null,
      // We intentionally do NOT store the raw deviceFingerprint in the case
      // document to limit PII exposure.  The presence of "device" in matchedOn
      // is sufficient for review.
      deviceFingerprintProvided: !!deviceFingerprint,
      status:   "pending_review",
      createdAt: FieldValue.serverTimestamp(),
    }
  );

  await batch.commit();

  console.warn(
    `[banEvasion] BAN EVASION DETECTED uid=${uid} matchedOn=${matchedOn.join(",")} caseId=${caseId}`
  );

  return { isBanEvader: true, matchedOn, caseId };
}

// ─── recordBanEvasionSignal ───────────────────────────────────────────────────

/**
 * Records the phone hash and device fingerprint of a user who has been banned,
 * so future accounts using the same identifiers can be detected.
 *
 * Called by the account-ban workflow after a moderation decision is finalised.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} bannedUid           UID of the account that was banned
 * @param {string|null} phoneHash      SHA-256 hex of normalised E.164 phone
 * @param {string|null} deviceFingerprint
 * @returns {Promise<void>}
 */
async function recordBanEvasionSignal(db, bannedUid, phoneHash, deviceFingerprint) {
  if (!db)       throw new Error("[banEvasion] db is required");
  if (!bannedUid) throw new Error("[banEvasion] bannedUid is required");

  if (!phoneHash && !deviceFingerprint) {
    // Nothing to record — not an error, just a no-op.
    console.log(`[banEvasion] recordBanEvasionSignal: no identifiers provided for uid=${bannedUid}, skipping`);
    return;
  }

  const writes = [];
  const now = FieldValue.serverTimestamp();

  if (phoneHash) {
    // Deduplicate: only create if this hash isn't already recorded.
    const existing = await db
      .collection(COL_BANNED_IDENTIFIERS)
      .where("phoneHash", "==", phoneHash)
      .limit(1)
      .get();

    if (existing.empty) {
      writes.push(
        db.collection(COL_BANNED_IDENTIFIERS).add({
          type:      "phone",
          phoneHash,
          bannedUid,
          active:    true,
          createdAt: now,
        })
      );
    }
  }

  if (deviceFingerprint) {
    const existingDevice = await db
      .collection(COL_BANNED_IDENTIFIERS)
      .where("deviceFingerprint", "==", deviceFingerprint)
      .limit(1)
      .get();

    if (existingDevice.empty) {
      writes.push(
        db.collection(COL_BANNED_IDENTIFIERS).add({
          type:              "device",
          deviceFingerprint,
          bannedUid,
          active:            true,
          createdAt:         now,
        })
      );
    }
  }

  await Promise.all(writes);

  console.log(
    `[banEvasion] Signals recorded for bannedUid=${bannedUid} ` +
    `phone=${!!phoneHash} device=${!!deviceFingerprint}`
  );
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  checkBanEvasion,
  recordBanEvasionSignal,
};
