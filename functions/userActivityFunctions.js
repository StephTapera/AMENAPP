/**
 * userActivityFunctions.js
 * AMEN App — User Activity & FCM Token Lifecycle Cloud Functions
 *
 * Exports:
 *   onUserActivity     — callable: rate-limited lastActiveAt update (skip if <5 min since last)
 *   onFcmTokenRefresh  — callable: save/refresh FCM token + timezoneOffset on user doc
 *   onPostActivity     — Firestore trigger: update lastActiveAt when user creates a post
 *   onPrayerActivity   — Firestore trigger: update lastActiveAt when user creates a prayer
 *   onTestimonyActivity— Firestore trigger: update lastActiveAt when testimony linked to prayer
 */

"use strict";

const {onCall, HttpsError}     = require("firebase-functions/v2/https");
const {onDocumentCreated,
       onDocumentWritten}      = require("firebase-functions/v2/firestore");
const admin                    = require("firebase-admin");

const db     = admin.firestore();
const REGION = "us-central1";

// ─── Helpers ────────────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
}

// ─── onUserActivity ──────────────────────────────────────────────────────────
// Callable. Updates `lastActiveAt` on the user's Firestore doc.
// Rate-limited: skips the write if the stored value is <5 minutes old to avoid
// hammering Firestore on every scroll event or background fetch.
//
// Input:  {} (no payload needed — uid comes from auth context)
// Output: { updated: boolean }

exports.onUserActivity = onCall(
  { region: REGION, timeoutSeconds: 10 },
  async (request) => {
    requireAuth(request);
    const uid = request.auth.uid;
    const now = admin.firestore.Timestamp.now();
    const FIVE_MINUTES_MS = 5 * 60 * 1000;

    const userRef = db.collection("users").doc(uid);
    const snap    = await userRef.get();
    if (!snap.exists) return { updated: false };

    const last = snap.data()?.lastActiveAt?.toMillis?.() ?? 0;
    if (now.toMillis() - last < FIVE_MINUTES_MS) {
      return { updated: false };           // too soon — skip write
    }

    await userRef.update({ lastActiveAt: now });
    return { updated: true };
  },
);

// ─── onFcmTokenRefresh ────────────────────────────────────────────────────────
// Callable. Saves the device FCM token + timezone offset to the user doc.
// Keeps only the 5 most recent tokens (multi-device support, pruning old ones).
//
// Input:  { token: string, timezoneOffset: number }  (timezoneOffset = UTC±minutes)
// Output: { saved: boolean }

exports.onFcmTokenRefresh = onCall(
  { region: REGION, timeoutSeconds: 15 },
  async (request) => {
    requireAuth(request);
    const uid = request.auth.uid;
    const { token, timezoneOffset = 0 } = request.data;

    if (!token || typeof token !== "string") {
      throw new HttpsError("invalid-argument", "token is required.");
    }

    const userRef  = db.collection("users").doc(uid);
    const snap     = await userRef.get();
    if (!snap.exists) return { saved: false };

    const existing = snap.data()?.fcmTokens ?? [];

    // De-dup: remove any old entry for the same token, then prepend the new entry.
    const filtered = existing.filter((t) => t.token !== token);
    const updated  = [
      { token, updatedAt: admin.firestore.Timestamp.now(), timezoneOffset },
      ...filtered,
    ].slice(0, 5); // keep max 5 devices

    await userRef.update({
      fcmTokens:       updated,
      timezoneOffset,
      lastActiveAt:    admin.firestore.Timestamp.now(),
    });

    return { saved: true };
  },
);

// ─── onPostActivity ───────────────────────────────────────────────────────────
// Firestore trigger: updates lastActiveAt when a new post is created by a user.
// Lightweight — no external calls, pure Firestore write.

exports.onPostActivity = onDocumentCreated(
  { document: "posts/{postId}", region: REGION },
  async (event) => {
    const post = event.data?.data();
    const uid  = post?.userId || post?.authorId;
    if (!uid) return;
    await db.collection("users").doc(uid).update({
      lastActiveAt: admin.firestore.Timestamp.now(),
    }).catch(() => {}); // non-fatal
  },
);

// ─── onPrayerActivity ─────────────────────────────────────────────────────────
// Firestore trigger: updates lastActiveAt when a user creates a prayer request.

exports.onPrayerActivity = onDocumentCreated(
  { document: "prayers/{prayerId}", region: REGION },
  async (event) => {
    const prayer = event.data?.data();
    const uid    = prayer?.userId || prayer?.authorId;
    if (!uid) return;
    await db.collection("users").doc(uid).update({
      lastActiveAt: admin.firestore.Timestamp.now(),
    }).catch(() => {});
  },
);

// ─── onTestimonyActivity ──────────────────────────────────────────────────────
// Firestore trigger: when a post is written with type="testimony" and
// linkedPrayerRequestId is newly set, updates the author's lastActiveAt.
// This is also the hook point for the Prayer Arc notification (see prayerArcFunctions.js).

exports.onTestimonyActivity = onDocumentWritten(
  { document: "posts/{postId}", region: REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    if (!after) return;

    // Only fire when linkedPrayerRequestId is newly set
    const wasLinked = !!before?.linkedPrayerRequestId;
    const isLinked  = !!after?.linkedPrayerRequestId;
    if (wasLinked || !isLinked) return;

    const uid = after.userId || after.authorId;
    if (!uid) return;

    await db.collection("users").doc(uid).update({
      lastActiveAt: admin.firestore.Timestamp.now(),
    }).catch(() => {});
  },
);
