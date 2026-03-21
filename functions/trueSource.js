/**
 * trueSource.js
 * TrueSource — content authentication for AMEN posts.
 *
 * Functions:
 *   trueSourceSign   — Callable: sign a post's content hash with HMAC-SHA256.
 *                      Called by the iOS client right after post publish.
 *   trueSourceVerify — Callable: verify that a signature is still valid.
 *                      Lightweight — the iOS client does the content hash check
 *                      locally; this function provides the server-side signature
 *                      validation for cross-device or web verification.
 *
 * Secret: TRUESOURCE_SIGNING_KEY stored in Firebase Secret Manager.
 * The key never leaves the server. iOS only stores/displays the signature.
 *
 * Signature payload (canonical):
 *   `{post_id}:{author_id}:{content_hash}:{timestamp_unix}`
 */

"use strict";

const crypto = require("crypto");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {checkRateLimit} = require("./rateLimiter");

const SIGNING_KEY = defineSecret("TRUESOURCE_SIGNING_KEY");

const db = () => admin.firestore();

// ── Sign ─────────────────────────────────────────────────────────────────────

exports.trueSourceSign = onCall(
    {
      region: "us-central1",
      secrets: [SIGNING_KEY],
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "truesource_sign", 50, 3600);

      const {post_id, author_id, content_hash, is_ai_assisted} = request.data;

      if (!post_id || !author_id || !content_hash) {
        throw new HttpsError("invalid-argument", "post_id, author_id, and content_hash are required");
      }

      // Verify the caller is the post author
      if (uid !== author_id) {
        throw new HttpsError("permission-denied", "Only the post author can sign their post");
      }

      // Verify the post exists in Firestore
      const postDoc = await db().collection("posts").doc(post_id).get();
      if (!postDoc.exists) {
        throw new HttpsError("not-found", "Post not found");
      }
      const postData = postDoc.data();
      if (postData.authorId !== uid) {
        throw new HttpsError("permission-denied", "Post author mismatch");
      }

      // Build canonical payload
      const timestamp = Math.floor(Date.now() / 1000);
      const canonicalPayload = `${post_id}:${author_id}:${content_hash}:${timestamp}`;

      // HMAC-SHA256 with the server secret
      const key = SIGNING_KEY.value();
      const signature = crypto
          .createHmac("sha256", key)
          .update(canonicalPayload)
          .digest("hex");

      // Compute fingerprint (SHA-256 of canonical payload — public, non-secret)
      const fingerprint = crypto
          .createHash("sha256")
          .update(canonicalPayload)
          .digest("hex");

      const record = {
        post_id,
        author_id,
        signature,
        fingerprint,
        signed_at: admin.firestore.FieldValue.serverTimestamp(),
        is_ai_assisted: !!is_ai_assisted,
        content_hash,
        timestamp_unix: timestamp,
      };

      // Write to the post document
      await db().collection("posts").doc(post_id).update({
        trueSource: record,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`TrueSource signed post ${post_id} by ${uid}`);

      // Return without the signature (client doesn't need it for display;
      // only the fingerprint + metadata is needed for the badge)
      return {
        post_id,
        author_id,
        fingerprint,
        signed_at: new Date().toISOString(),
        is_ai_assisted: !!is_ai_assisted,
        content_hash,
      };
    },
);

// ── Verify ───────────────────────────────────────────────────────────────────

exports.trueSourceVerify = onCall(
    {
      region: "us-central1",
      secrets: [SIGNING_KEY],
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {post_id, current_content_hash} = request.data;
      if (!post_id) throw new HttpsError("invalid-argument", "post_id required");

      const postDoc = await db().collection("posts").doc(post_id).get();
      if (!postDoc.exists) throw new HttpsError("not-found", "Post not found");

      const ts = postDoc.data()?.trueSource;
      if (!ts) return {status: "unsigned"};

      // Re-derive the canonical payload and re-sign with server key
      const canonicalPayload = `${ts.post_id}:${ts.author_id}:${ts.content_hash}:${ts.timestamp_unix}`;
      const key = SIGNING_KEY.value();
      const expectedSig = crypto
          .createHmac("sha256", key)
          .update(canonicalPayload)
          .digest("hex");

      const signatureValid = crypto.timingSafeEqual(
          Buffer.from(ts.signature, "hex"),
          Buffer.from(expectedSig, "hex"),
      );

      if (!signatureValid) {
        return {status: "invalid_signature"};
      }

      // Content tamper check
      if (current_content_hash && current_content_hash !== ts.content_hash) {
        return {status: "tampered", original_hash: ts.content_hash};
      }

      return {
        status: "verified",
        post_id: ts.post_id,
        author_id: ts.author_id,
        fingerprint: ts.fingerprint,
        is_ai_assisted: ts.is_ai_assisted,
        signed_at: ts.signed_at,
      };
    },
);
