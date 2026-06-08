/**
 * voicePrayer.js
 * AMEN App — Voice Prayer & Testimony Comments Pipeline
 *
 * Exports:
 *   createVoicePrayerUploadSession  — mint upload path + Firestore stub
 *   finalizeVoicePrayerComment      — NeMo Guard moderation + activate comment
 *   reactToVoicePrayerComment       — increment reaction counter (no double-react)
 *   deleteVoicePrayerComment        — soft-delete + Storage cleanup
 *   reportVoicePrayerComment        — report → moderationQueue, auto-block at 3
 *   getVoicePrayerPlaybackURL       — generate 1-hour signed URL
 *
 * admin.initializeApp() is called in index.js — not here.
 * Firebase Functions v2 (onCall), region us-central1.
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";
const STORAGE_BUCKET = "amen-5e359.firebasestorage.app";

const VALID_TYPES = ["prayer", "testimony"];
const VALID_VISIBILITIES = [
  "public",
  "followers",
  "church",
  "prayer_circle",
  "private",
];
const VALID_REACTIONS = ["prayed", "amen", "encourage"];
const MAX_DURATION_MS = 120000; // 2 minutes
const AUTO_BLOCK_REPORT_THRESHOLD = 3;

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Require an authenticated caller; throw if not. */
function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
}

/** Lazy accessor so we don't hold a reference before initializeApp() finishes. */
function db() {
  return admin.firestore();
}

/** Lazy accessor for the default Storage bucket. */
function bucket() {
  return admin.storage().bucket(STORAGE_BUCKET);
}

/**
 * Call NVIDIA NIM NeMo Guard content-safety endpoint.
 *
 * @param {string} apiKey  - Raw NVIDIA_API_KEY secret value.
 * @param {string} prompt  - The text to evaluate.
 * @returns {{ safe: boolean, raw: string }}
 */
async function nemoGuardCheck(apiKey, prompt) {
  const fetch = (await import("node-fetch")).default;

  const body = {
    model: "nvidia/llama-3.1-nemoguard-8b-content-safety",
    messages: [
      {
        role: "user",
        content: prompt,
      },
    ],
    max_tokens: 64,
    temperature: 0,
  };

  const response = await fetch(
      "https://integrate.api.nvidia.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
      },
  );

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(
        `NeMo Guard returned HTTP ${response.status}: ${errText}`,
    );
  }

  const json = await response.json();
  const raw = (json.choices?.[0]?.message?.content ?? "").trim().toLowerCase();

  // NeMo Guard content-safety model returns a label such as
  // "safe", "unsafe", or "off_topic".  Treat anything that is not
  // explicitly "safe" as not safe to be conservative.
  const safe = raw === "safe";
  return {safe, raw};
}

// ─── 1. createVoicePrayerUploadSession ────────────────────────────────────────

exports.createVoicePrayerUploadSession = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {postId, type, durationMs} = request.data;
      const uid = request.auth.uid;

      // ── Validate inputs ────────────────────────────────────────────────────
      if (typeof postId !== "string" || postId.trim() === "") {
        throw new HttpsError("invalid-argument", "postId is required.");
      }
      if (!VALID_TYPES.includes(type)) {
        throw new HttpsError(
            "invalid-argument",
            `type must be one of: ${VALID_TYPES.join(", ")}.`,
        );
      }
      if (
        typeof durationMs !== "number" ||
        durationMs <= 0 ||
        durationMs > MAX_DURATION_MS
      ) {
        throw new HttpsError(
            "invalid-argument",
            `durationMs must be a positive number no greater than ${MAX_DURATION_MS}.`,
        );
      }

      // ── Verify post exists ─────────────────────────────────────────────────
      const postSnap = await db().collection("posts").doc(postId).get();
      if (!postSnap.exists) {
        throw new HttpsError("not-found", `Post ${postId} does not exist.`);
      }

      // ── Create Firestore stub ──────────────────────────────────────────────
      const voiceCommentRef = db().collection("voiceComments").doc();
      const voiceCommentId = voiceCommentRef.id;
      const uploadPath = `voice_comments/${postId}/${voiceCommentId}.m4a`;

      const stub = {
        postId,
        authorId: uid,
        type,
        durationMs,
        waveform: [],
        visibility: "public",
        storagePath: uploadPath,
        status: "uploading",
        transcriptText: null,
        moderation: null,
        reactions: {prayed: 0, amen: 0, encourage: 0},
        reportCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await voiceCommentRef.set(stub);

      return {voiceCommentId, uploadPath};
    },
);

// ─── 2. finalizeVoicePrayerComment ────────────────────────────────────────────

exports.finalizeVoicePrayerComment = onCall(
    {region: REGION, secrets: [NVIDIA_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {
        voiceCommentId,
        postId,
        type,
        durationMs,
        waveform,
        visibility,
      } = request.data;
      const uid = request.auth.uid;

      // ── Validate inputs ────────────────────────────────────────────────────
      if (typeof voiceCommentId !== "string" || voiceCommentId.trim() === "") {
        throw new HttpsError("invalid-argument", "voiceCommentId is required.");
      }
      if (typeof postId !== "string" || postId.trim() === "") {
        throw new HttpsError("invalid-argument", "postId is required.");
      }
      if (!VALID_TYPES.includes(type)) {
        throw new HttpsError(
            "invalid-argument",
            `type must be one of: ${VALID_TYPES.join(", ")}.`,
        );
      }
      if (
        typeof durationMs !== "number" ||
        durationMs <= 0 ||
        durationMs > MAX_DURATION_MS
      ) {
        throw new HttpsError(
            "invalid-argument",
            `durationMs must be between 1 and ${MAX_DURATION_MS}.`,
        );
      }
      if (!Array.isArray(waveform)) {
        throw new HttpsError("invalid-argument", "waveform must be an array.");
      }
      if (!VALID_VISIBILITIES.includes(visibility)) {
        throw new HttpsError(
            "invalid-argument",
            `visibility must be one of: ${VALID_VISIBILITIES.join(", ")}.`,
        );
      }

      // ── Verify ownership ───────────────────────────────────────────────────
      const vcRef = db().collection("voiceComments").doc(voiceCommentId);
      const vcSnap = await vcRef.get();
      if (!vcSnap.exists) {
        throw new HttpsError(
            "not-found",
            `Voice comment ${voiceCommentId} does not exist.`,
        );
      }
      const vcData = vcSnap.data();
      if (vcData.authorId !== uid) {
        throw new HttpsError(
            "permission-denied",
            "You are not the author of this voice comment.",
        );
      }

      // ── Fetch post content for safety check ───────────────────────────────
      let postContext = "";
      try {
        const postSnap = await db().collection("posts").doc(postId).get();
        if (postSnap.exists) {
          const postData = postSnap.data();
          postContext =
            postData.text ||
            postData.caption ||
            postData.title ||
            "";
        }
      } catch (_) {
        // Non-fatal — safety check will proceed with minimal context.
      }

      // ── Build NeMo Guard prompt ────────────────────────────────────────────
      // We don't have a transcript yet, so we safety-check based on the
      // associated post content and the declared comment metadata.
      const safetyPrompt = [
        `A user is submitting a ${type} voice comment (${Math.round(durationMs / 1000)}s)`,
        `on a Christian social media app.`,
        postContext
          ? `The post they are responding to contains: "${postContext.slice(0, 300)}"`
          : "No post text is available.",
        `Evaluate whether this context is appropriate for a faith-based community.`,
      ].join(" ");

      let moderationResult;
      let decision;
      const checkedAt = new Date().toISOString();

      try {
        moderationResult = await nemoGuardCheck(
            NVIDIA_API_KEY.value(),
            safetyPrompt,
        );
      } catch (err) {
        // Moderation service error — fail open with a warning, still activate.
        console.error("[voicePrayer] NeMo Guard error:", err.message);
        moderationResult = {safe: true, raw: "error_fallback"};
      }

      const {safe, raw: nemoRaw} = moderationResult;

      if (safe) {
        decision = "allow";
        await vcRef.update({
          status: "active",
          waveform,
          visibility,
          type,
          durationMs,
          moderation: {safe: true, checkedAt, nemoLabel: nemoRaw},
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        // "off_topic" label from NeMo should be surfaced distinctly.
        decision = nemoRaw === "off_topic" ? "off_topic" : "blocked";

        await vcRef.update({
          status: "blocked",
          waveform,
          visibility,
          type,
          durationMs,
          moderation: {safe: false, checkedAt, nemoLabel: nemoRaw},
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Add to moderation queue for human review.
        await db().collection("moderationQueue").add({
          type: "voice_comment_moderation",
          voiceCommentId,
          postId,
          authorId: uid,
          nemoLabel: nemoRaw,
          decision,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {decision};
    },
);

// ─── 3. reactToVoicePrayerComment ─────────────────────────────────────────────

exports.reactToVoicePrayerComment = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {voiceCommentId, postId, reaction} = request.data;
      const uid = request.auth.uid;

      // ── Validate inputs ────────────────────────────────────────────────────
      if (typeof voiceCommentId !== "string" || voiceCommentId.trim() === "") {
        throw new HttpsError("invalid-argument", "voiceCommentId is required.");
      }
      if (typeof postId !== "string" || postId.trim() === "") {
        throw new HttpsError("invalid-argument", "postId is required.");
      }
      if (!VALID_REACTIONS.includes(reaction)) {
        throw new HttpsError(
            "invalid-argument",
            `reaction must be one of: ${VALID_REACTIONS.join(", ")}.`,
        );
      }

      // ── Verify voice comment exists and is active ──────────────────────────
      const vcRef = db().collection("voiceComments").doc(voiceCommentId);
      const vcSnap = await vcRef.get();
      if (!vcSnap.exists) {
        throw new HttpsError(
            "not-found",
            `Voice comment ${voiceCommentId} does not exist.`,
        );
      }
      const vcData = vcSnap.data();
      if (vcData.status !== "active") {
        throw new HttpsError(
            "failed-precondition",
            "This voice comment is not available for reactions.",
        );
      }

      // ── Prevent double reactions ───────────────────────────────────────────
      const reactionRef = vcRef.collection("reactions").doc(uid);
      const reactionSnap = await reactionRef.get();
      if (reactionSnap.exists) {
        throw new HttpsError(
            "already-exists",
            "You have already reacted to this voice comment.",
        );
      }

      // ── Atomically increment + record reaction ─────────────────────────────
      const batch = db().batch();

      batch.update(vcRef, {
        [`reactions.${reaction}`]: admin.firestore.FieldValue.increment(1),
      });

      batch.set(reactionRef, {
        reaction,
        uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();

      return {success: true};
    },
);

// ─── 4. deleteVoicePrayerComment ──────────────────────────────────────────────

exports.deleteVoicePrayerComment = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {voiceCommentId, postId} = request.data;
      const uid = request.auth.uid;
      const isAdmin = request.auth.token?.admin === true;

      // ── Validate inputs ────────────────────────────────────────────────────
      if (typeof voiceCommentId !== "string" || voiceCommentId.trim() === "") {
        throw new HttpsError("invalid-argument", "voiceCommentId is required.");
      }
      if (typeof postId !== "string" || postId.trim() === "") {
        throw new HttpsError("invalid-argument", "postId is required.");
      }

      // ── Load voice comment ─────────────────────────────────────────────────
      const vcRef = db().collection("voiceComments").doc(voiceCommentId);
      const vcSnap = await vcRef.get();
      if (!vcSnap.exists) {
        throw new HttpsError(
            "not-found",
            `Voice comment ${voiceCommentId} does not exist.`,
        );
      }
      const vcData = vcSnap.data();

      // ── Authorisation: must be author or admin ─────────────────────────────
      if (vcData.authorId !== uid && !isAdmin) {
        throw new HttpsError(
            "permission-denied",
            "You do not have permission to delete this voice comment.",
        );
      }

      // ── Delete Storage file (best-effort) ─────────────────────────────────
      const storagePath = `voice_comments/${postId}/${voiceCommentId}.m4a`;
      try {
        await bucket().file(storagePath).delete();
      } catch (storageErr) {
        // File may already be deleted or never fully uploaded — log and continue.
        console.warn(
            `[voicePrayer] Storage delete warning for ${storagePath}:`,
            storageErr.message,
        );
      }

      // ── Soft-delete Firestore doc ──────────────────────────────────────────
      await vcRef.update({
        status: "deleted",
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: uid,
      });

      return {success: true};
    },
);

// ─── 5. reportVoicePrayerComment ──────────────────────────────────────────────

exports.reportVoicePrayerComment = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {voiceCommentId, postId, reason} = request.data;
      const uid = request.auth.uid;

      // ── Validate inputs ────────────────────────────────────────────────────
      if (typeof voiceCommentId !== "string" || voiceCommentId.trim() === "") {
        throw new HttpsError("invalid-argument", "voiceCommentId is required.");
      }
      if (typeof postId !== "string" || postId.trim() === "") {
        throw new HttpsError("invalid-argument", "postId is required.");
      }
      if (typeof reason !== "string" || reason.trim() === "") {
        throw new HttpsError("invalid-argument", "reason is required.");
      }

      // ── Load voice comment ─────────────────────────────────────────────────
      const vcRef = db().collection("voiceComments").doc(voiceCommentId);
      const vcSnap = await vcRef.get();
      if (!vcSnap.exists) {
        throw new HttpsError(
            "not-found",
            `Voice comment ${voiceCommentId} does not exist.`,
        );
      }
      const vcData = vcSnap.data();

      // ── Cannot report your own comment ─────────────────────────────────────
      if (vcData.authorId === uid) {
        throw new HttpsError(
            "failed-precondition",
            "You cannot report your own voice comment.",
        );
      }

      // ── Add to moderation queue ────────────────────────────────────────────
      await db().collection("moderationQueue").add({
        type: "voice_comment_report",
        voiceCommentId,
        postId,
        reportedBy: uid,
        reportedAuthorId: vcData.authorId,
        reason: reason.slice(0, 500),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // ── Increment reportCount and auto-block if threshold reached ──────────
      await vcRef.update({
        reportCount: admin.firestore.FieldValue.increment(1),
      });

      // Re-read the updated count to check threshold.
      const updatedSnap = await vcRef.get();
      const updatedData = updatedSnap.data();
      const newCount = updatedData?.reportCount ?? 0;

      if (newCount >= AUTO_BLOCK_REPORT_THRESHOLD && updatedData?.status === "active") {
        await vcRef.update({
          status: "blocked",
          moderatorAlert: true,
          autoBlockedAt: admin.firestore.FieldValue.serverTimestamp(),
          autoBlockReason: `Auto-blocked after ${newCount} reports.`,
        });
      }

      return {success: true};
    },
);

// ─── 6. getVoicePrayerPlaybackURL ─────────────────────────────────────────────

exports.getVoicePrayerPlaybackURL = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);

      const {storagePath} = request.data;

      // ── Validate path (prevent traversal) ─────────────────────────────────
      if (typeof storagePath !== "string" || storagePath.trim() === "") {
        throw new HttpsError("invalid-argument", "storagePath is required.");
      }
      if (!storagePath.startsWith("voice_comments/")) {
        throw new HttpsError(
            "invalid-argument",
            "storagePath must begin with 'voice_comments/'.",
        );
      }
      // Reject any path traversal attempts.
      if (storagePath.includes("..")) {
        throw new HttpsError(
            "invalid-argument",
            "storagePath contains invalid path components.",
        );
      }

      // ── Generate signed URL valid for 1 hour ──────────────────────────────
      const expiresAt = Date.now() + 60 * 60 * 1000; // 1 hour from now

      let url;
      try {
        const [signedUrl] = await bucket().file(storagePath).getSignedUrl({
          action: "read",
          expires: expiresAt,
        });
        url = signedUrl;
      } catch (err) {
        console.error(
            `[voicePrayer] getSignedUrl error for ${storagePath}:`,
            err.message,
        );
        throw new HttpsError(
            "internal",
            "Unable to generate playback URL. The file may not exist yet.",
        );
      }

      return {url};
    },
);
