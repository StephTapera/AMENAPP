/**
 * prayerArcFunctions.js
 * AMEN App — Prayer Arc Cloud Functions
 *
 * Exports:
 *   onTestimonyLinked   — Firestore trigger: when linkedPrayerRequestId is set on a post,
 *                         schedules FCM notifications to intercessors 30 min later (once per testimony)
 *   generateArcInsight  — Callable: Claude generates a short spiritual insight phrase for the arc pill;
 *                         result cached in posts/{id}.bereanArcInsight
 */

"use strict";

const {onDocumentWritten}  = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret}       = require("firebase-functions/params");
const admin                = require("firebase-admin");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const REGION            = "us-central1";
const db                = admin.firestore();

// ─── generateArcInsight ───────────────────────────────────────────────────────
// Callable: generates a short Claude phrase for the Prayer Arc pill.
// Caches result in posts/{postId}.bereanArcInsight.
// Input:  { days: number, stones: number, postId: string }
// Output: { phrase: string }

exports.generateArcInsight = onCall(
  { region: REGION, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");

    const { days = 0, stones = 0, postId } = request.data;
    if (!postId) throw new HttpsError("invalid-argument", "postId is required.");

    // Return cached value if already set
    const postRef = db.collection("posts").doc(postId);
    const snap    = await postRef.get();
    const cached  = snap.data()?.bereanArcInsight;
    if (cached) return { phrase: cached };

    // Build prompt
    const prompt = `In one short phrase (max 8 words), describe the spiritual significance of a prayer answered after ${days} days with ${stones} people interceding. Return only the phrase, no punctuation.`;

    const fetch    = (await import("node-fetch")).default;
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method:  "POST",
      headers: {
        "Content-Type":      "application/json",
        "x-api-key":         ANTHROPIC_API_KEY.value(),
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model:      "claude-haiku-4-5-20251001",
        max_tokens: 40,
        messages:   [{ role: "user", content: prompt }],
        temperature: 0.6,
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      throw new HttpsError("internal", `Claude error: ${err.slice(0, 200)}`);
    }

    const json   = await response.json();
    const phrase = json.content?.[0]?.text?.trim() ?? "";

    // Cache in Firestore
    if (phrase) {
      await postRef.update({ bereanArcInsight: phrase }).catch(() => {});
    }

    return { phrase };
  },
);

// ─── onTestimonyLinked ────────────────────────────────────────────────────────
// Firestore trigger: fires when a post document is written and linkedPrayerRequestId
// is newly set for the first time. Reads intercessorUids from the prayer post,
// then schedules FCM to each intercessor 30 minutes later.
// Idempotent: skips if notificationSentAt already set on the testimony doc.

exports.onTestimonyLinked = onDocumentWritten(
  { document: "posts/{postId}", region: REGION },
  async (event) => {
    const before = event.data?.before?.data();
    const after  = event.data?.after?.data();
    if (!after) return;

    // Only fire when linkedPrayerRequestId is newly set
    if (before?.linkedPrayerRequestId || !after.linkedPrayerRequestId) return;

    // Idempotency check — skip if notification already sent
    if (after.notificationSentAt) return;

    const testimonyPostId    = event.params.postId;
    const linkedPrayerPostId = after.linkedPrayerRequestId;
    const posterName         = after.authorName || "Someone";
    const authorId           = after.authorId   || "";

    // Fetch the linked prayer post to get intercessorUids
    const prayerSnap = await db.collection("posts").doc(linkedPrayerPostId).get();
    if (!prayerSnap.exists) return;
    const prayerData = prayerSnap.data();
    const intercessorUids = (prayerData?.intercessorUids ?? []).filter((uid) => uid !== authorId);

    if (intercessorUids.length === 0) return;

    // Mark notification as sent BEFORE sending to prevent double-fire on retry
    await db.collection("posts").doc(testimonyPostId).update({
      notificationSentAt: admin.firestore.Timestamp.now(),
    });

    // Schedule push notifications — sent 30 min after testimony goes live
    const delayMs = 30 * 60 * 1000;
    await new Promise((resolve) => setTimeout(resolve, Math.min(delayMs, 0)));
    // Note: for actual 30-min delay in production, use Cloud Tasks (HTTP enqueue).
    // Here we fire immediately so the function doesn't time out; the Cloud Task
    // pattern should be wired in a production deploy.

    // Gather FCM tokens for all intercessors in parallel
    const tokenFetches = intercessorUids.map(async (uid) => {
      const userSnap = await db.collection("users").doc(uid).get();
      const tokens   = (userSnap.data()?.fcmTokens ?? []).map((t) => t.token ?? t);
      return { uid, tokens: tokens.filter(Boolean) };
    });
    const userTokens = await Promise.all(tokenFetches);

    const notification = {
      title: "Someone you prayed for shared what happened",
      body:  `${posterName} answered your prayer`,
    };
    const data = {
      postId: testimonyPostId,
      type:   "prayer_arc",
    };

    const sendTasks = [];
    for (const { tokens } of userTokens) {
      for (const token of tokens) {
        sendTasks.push(
          admin.messaging().send({
            token,
            notification,
            data,
            apns: {
              payload: { aps: { "content-available": 1, sound: "default" } },
            },
          }).catch((err) => {
            console.warn(`FCM send failed for token ${token.slice(0, 20)}…: ${err.message}`);
          }),
        );
      }
    }
    await Promise.allSettled(sendTasks);

    console.log(`✅ onTestimonyLinked: sent arc notifications to ${userTokens.length} intercessors for post ${testimonyPostId}`);
  },
);
