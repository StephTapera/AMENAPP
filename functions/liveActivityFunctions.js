/**
 * liveActivityFunctions.js
 * AMEN App — Prayer Request Live Activity Cloud Functions
 *
 * Exports:
 *   prayForRequest          — onCall (App Check enforced): mark uid as praying
 *   onPrayingUserWritten    — Firestore trigger: increment/decrement prayingCount
 *   onPrayerRequestUpdated  — Firestore trigger: send APNs "update" pushes
 *   onPrayerRequestCreated  — Firestore trigger: send APNs "start" (Phase 3, iOS 17.2+)
 *
 * APNs secrets (set via `firebase functions:secrets:set`):
 *   APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID
 *
 * admin.initializeApp() is called in index.js — not here.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten, onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { sendLiveActivityUpdate, sendLiveActivityStart } = require("./apnsLiveActivity");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const APNS_KEY      = defineSecret("APNS_KEY");
const APNS_KEY_ID   = defineSecret("APNS_KEY_ID");
const APNS_TEAM_ID  = defineSecret("APNS_TEAM_ID");
const APNS_BUNDLE_ID = defineSecret("APNS_BUNDLE_ID");

const APNS_SECRETS = [APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID];

// ─── Constants ─────────────────────────────────────────────────────────────────

const REGION = "us-east1"; // us-central1 quota exhausted; mirrors restoredFunctionsOverflow.js

// ─── prayForRequest ────────────────────────────────────────────────────────────

/**
 * Idempotent: writes prayingUsers/{uid} for the given prayerRequest.
 * uid is sourced from request.auth (Firebase Auth token) or request.data.uid
 * (App Group bridge from widget extension when App Check is the only gate).
 */
exports.prayForRequest = onCall(
  { region: REGION, enforceAppCheck: true, secrets: [] },
  async (request) => {
    const uid = request.auth?.uid ?? request.data?.uid;
    if (!uid || typeof uid !== "string") {
      throw new HttpsError("unauthenticated", "User not authenticated.");
    }

    const { requestId } = request.data;
    if (!requestId || typeof requestId !== "string") {
      throw new HttpsError("invalid-argument", "requestId is required.");
    }

    const db = admin.firestore();
    const prayingRef = db
      .collection("prayerRequests").doc(requestId)
      .collection("prayingUsers").doc(uid);

    const existing = await prayingRef.get();
    const alreadyPrayed = existing.exists;

    await prayingRef.set({ at: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

    return { ok: true, alreadyPrayed };
  }
);

// ─── onPrayingUserWritten ──────────────────────────────────────────────────────

/**
 * When a prayingUsers/{uid} doc is created or deleted,
 * atomically increment/decrement prayerRequests/{id}.prayingCount.
 */
exports.onPrayingUserWritten = onDocumentWritten(
  { document: "prayerRequests/{id}/prayingUsers/{uid}", region: REGION },
  async (event) => {
    const wasCreated = !event.data.before.exists && event.data.after.exists;
    const wasDeleted = event.data.before.exists && !event.data.after.exists;
    if (!wasCreated && !wasDeleted) return;

    const delta = wasCreated ? 1 : -1;
    const requestRef = admin.firestore()
      .collection("prayerRequests").doc(event.params.id);

    await requestRef.update({
      prayingCount: admin.firestore.FieldValue.increment(delta),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

// ─── onPrayerRequestUpdated ────────────────────────────────────────────────────

/**
 * When prayerRequests/{id} is updated (prayingCount, encouragementCount, or
 * isAnswered changes), send an APNs "update" push to all registered Live
 * Activity tokens. Tokens that return 410 (Gone) are deleted.
 */
exports.onPrayerRequestUpdated = onDocumentUpdated(
  {
    document: "prayerRequests/{id}",
    region: REGION,
    secrets: APNS_SECRETS,
  },
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    const prayingChanged      = before.prayingCount !== after.prayingCount;
    const encourageChanged    = before.encouragementCount !== after.encouragementCount;
    const isAnsweredChanged   = before.isAnswered !== after.isAnswered;

    if (!prayingChanged && !encourageChanged && !isAnsweredChanged) return;

    const contentState = {
      prayingCount: after.prayingCount ?? 0,
      encouragementCount: after.encouragementCount ?? 0,
      isAnswered: after.isAnswered ?? false,
    };

    const secrets = { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID };
    const tokensSnap = await admin.firestore()
      .collection("prayerRequests").doc(event.params.id)
      .collection("liveActivityTokens")
      .get();

    const deletes = [];
    await Promise.all(
      tokensSnap.docs.map(async (doc) => {
        const result = await sendLiveActivityUpdate(secrets, doc.id, contentState);
        if (result.status === 410) {
          deletes.push(doc.ref.delete());
        }
      })
    );
    await Promise.all(deletes);
  }
);

// ─── onPrayerRequestCreated (Phase 3 — push-to-start) ─────────────────────────

/**
 * When a new prayerRequests/{id} doc is created, send APNs "start" pushes to
 * the close circle of the requester (users with prayerPartner edges).
 * Gated by Remote Config flag `liveActivityPushToStartEnabled` (checked server-side
 * via the document field set by the iOS client before creation, or a Firestore
 * Remote Config read). For simplicity, enabled when the document includes
 * `pushToStartEnabled: true`; otherwise skipped.
 */
exports.onPrayerRequestCreated = onDocumentCreated(
  {
    document: "prayerRequests/{id}",
    region: REGION,
    secrets: APNS_SECRETS,
  },
  async (event) => {
    const data = event.data.data();
    if (!data.pushToStartEnabled) return; // Gated server-side

    const requesterUid = data.requesterUid;
    if (!requesterUid) return;

    const db = admin.firestore();
    const contentState = {
      prayingCount: data.prayingCount ?? 0,
      encouragementCount: data.encouragementCount ?? 0,
      isAnswered: false,
    };
    const attributes = {
      requestId: event.params.id,
      requesterName: data.requesterName ?? "",
      title: data.title ?? "",
    };

    // Audience: users with a prayerPartner edge pointing to requesterUid.
    const edgesSnap = await db
      .collection("edges")
      .where("type", "==", "prayerPartner")
      .where("targetUid", "==", requesterUid)
      .limit(50)
      .get();

    const secrets = { APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID };
    const deletes = [];

    await Promise.all(
      edgesSnap.docs.map(async (edgeDoc) => {
        const audienceUid = edgeDoc.data().sourceUid;
        if (!audienceUid) return;

        const ptsSnap = await db
          .collection("users").doc(audienceUid)
          .collection("ptsTokens")
          .get();

        await Promise.all(
          ptsSnap.docs.map(async (tokenDoc) => {
            const result = await sendLiveActivityStart(
              secrets,
              tokenDoc.id,
              "PrayerRequestAttributes",
              attributes,
              contentState,
              {
                title: `${data.requesterName} is asking for prayer`,
                body: data.title ?? "",
              }
            );
            if (result.status === 410) {
              deletes.push(tokenDoc.ref.delete());
            }
          })
        );
      })
    );
    await Promise.all(deletes);
  }
);
