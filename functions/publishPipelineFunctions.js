/**
 * publishPipelineFunctions.js
 * Phase 2 — Spatial Social OS Publish Pipeline (System 35 trust gates).
 *
 * Adds a single trust-gate callable that an upgraded composer can call
 * before `finalizePostPublish`. It validates that:
 *   1. The post is owned by the caller.
 *   2. Every media item has a /provenance/{postId_mediaId} record.
 *   3. Every media item whose provenance.disclosureRequired === true ALSO
 *      has at least one /aiDisclosures record.
 *   4. provenance.moderationStatus is not "blocked".
 *
 * This does NOT replace `finalizePostPublish` (which does the storage
 * authorization + atomic counters). It runs *before* finalizePostPublish
 * as a precheck. The composer pattern is:
 *   1. Upload media + register provenance + register AI disclosures
 *   2. Call publishPostWithTrustGates(postId, mediaIds)
 *      → returns { ok: true } or HttpsError('failed-precondition', ...)
 *   3. Call finalizePostPublish(postId, mediaUrls)
 *
 * Callable: publishPostWithTrustGates
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = () => admin.firestore();

exports.publishPostWithTrustGates = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {postId, mediaIds} = request.data || {};
      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }
      if (!Array.isArray(mediaIds) || mediaIds.length === 0 || mediaIds.length > 10) {
        throw new HttpsError("invalid-argument", "mediaIds must be a non-empty array of <=10");
      }

      // 1. Verify post ownership.
      const postSnap = await db().collection("posts").doc(postId).get();
      if (!postSnap.exists) {
        throw new HttpsError("not-found", "Post not found");
      }
      const post = postSnap.data() || {};
      const authorField = post.authorId || post.ownerUid || post.userId;
      if (authorField !== uid) {
        throw new HttpsError("permission-denied", "Not your post");
      }

      const failures = [];

      // 2 + 3 + 4. Fetch all provenance + disclosure docs in parallel.
      const checks = await Promise.all(
          mediaIds.map(async (mediaId) => {
            if (typeof mediaId !== "string" || !mediaId) {
              return {mediaId, reason: "invalid_media_id"};
            }
            const provId = `${postId}_${mediaId}`;
            const provSnap = await db().collection("provenance").doc(provId).get();
            if (!provSnap.exists) {
              return {mediaId, reason: "missing_provenance"};
            }
            const prov = provSnap.data() || {};
            if (prov.moderationStatus === "blocked") {
              return {mediaId, reason: "moderation_blocked"};
            }
            if (prov.disclosureRequired === true) {
              const discSnap = await db()
                  .collection("aiDisclosures")
                  .where("postId", "==", postId)
                  .where("mediaId", "==", mediaId)
                  .limit(1)
                  .get();
              if (discSnap.empty) {
                return {mediaId, reason: "missing_ai_disclosure"};
              }
            }
            return null;
          }),
      );

      checks.forEach((c) => {
        if (c) failures.push(c);
      });

      if (failures.length > 0) {
        throw new HttpsError(
            "failed-precondition",
            "Trust gates failed",
            {failures},
        );
      }

      // Stamp the post with a trust-gate pass marker so downstream consumers
      // (immersive media viewer, discovery ranker) can quickly tell the post
      // cleared the spine without re-querying every media item.
      await db().collection("posts").doc(postId).update({
        trustGatesPassed: true,
        trustGatesPassedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {ok: true, postId, mediaCount: mediaIds.length};
    },
);
