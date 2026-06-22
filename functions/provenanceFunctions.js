/**
 * provenanceFunctions.js
 * Trust Spine — Media Provenance (Phase 1, System 35).
 *
 * Callables:
 *   registerMediaProvenance — record where a piece of media came from, what
 *                             edits were applied, and what AI touched it.
 *                             Owner-only write, backend-validated.
 *   getPostProvenance       — return the user-visible provenance summary for
 *                             a post. Reader must be authenticated.
 *
 * Collection: /provenance/{provenanceId}
 *   Document shape mirrors Swift `MediaProvenance` model in SocialOSModels.swift.
 *
 * NON-NEGOTIABLE: client cannot forge authenticityConfidence, syntheticMediaStatus,
 *                 disclosureRequired, disclosureSatisfied, or moderationStatus.
 *                 Those are server-derived from a small allowed input set.
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

const ALLOWED_SOURCE_TYPES = new Set([
  "device_camera",
  "device_library",
  "screen_recording",
  "external_import",
  "ai_generated",
  "ai_assisted",
  "unknown",
]);

const ALLOWED_CREDENTIALS_STATUS = new Set([
  "verified",
  "pending",
  "not_applicable",
  "failed",
]);

// Server-derived from sourceType + aiEvents. Never client-set.
function deriveSyntheticMediaStatus(sourceType, aiEvents) {
  if (sourceType === "ai_generated") return "ai_generated_media";
  if (Array.isArray(aiEvents) && aiEvents.length > 0) {
    const hasMediaEdit = aiEvents.some((e) => {
      const t = (e && e.actionType) || "";
      return t.includes("edit") || t.includes("enhance") || t.includes("generate");
    });
    if (hasMediaEdit) return "ai_edited_media";
    return "ai_assisted_metadata";
  }
  return "clean";
}

// Server-derived from synthetic status + capture flag. Never client-set.
function deriveAuthenticityConfidence(capturedOnDevice, syntheticStatus) {
  if (syntheticStatus === "ai_generated_media") return 0.10;
  if (syntheticStatus === "ai_edited_media") return 0.50;
  if (syntheticStatus === "ai_assisted_metadata") return 0.80;
  return capturedOnDevice ? 0.95 : 0.75;
}

// Disclosure required whenever AI touched the media.
function deriveDisclosureRequired(syntheticStatus) {
  return syntheticStatus !== "clean";
}

exports.registerMediaProvenance = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "register_provenance", 200, 3600);

      const {
        postId,
        mediaId,
        capturedOnDevice,
        sourceType,
        contentCredentialsStatus,
        editEvents,
        aiEvents,
      } = request.data || {};

      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }
      if (typeof mediaId !== "string" || !mediaId) {
        throw new HttpsError("invalid-argument", "mediaId required");
      }
      if (typeof capturedOnDevice !== "boolean") {
        throw new HttpsError("invalid-argument", "capturedOnDevice must be boolean");
      }
      if (!ALLOWED_SOURCE_TYPES.has(sourceType)) {
        throw new HttpsError("invalid-argument", "sourceType invalid");
      }
      const credStatus = ALLOWED_CREDENTIALS_STATUS.has(contentCredentialsStatus)
        ? contentCredentialsStatus
        : "not_applicable";

      const sanitizedEditEvents = Array.isArray(editEvents)
        ? editEvents.slice(0, 32).map((e) => ({
            editType: typeof e.editType === "string" ? e.editType.slice(0, 64) : "unknown",
            tool: typeof e.tool === "string" ? e.tool.slice(0, 64) : null,
            aiAssisted: !!e.aiAssisted,
            timestamp: admin.firestore.Timestamp.now(),
          }))
        : [];

      const sanitizedAIEvents = Array.isArray(aiEvents)
        ? aiEvents.slice(0, 32).map((e) => ({
            actionType: typeof e.actionType === "string" ? e.actionType.slice(0, 64) : "unknown",
            provider: typeof e.provider === "string" ? e.provider.slice(0, 64) : null,
            purpose: typeof e.purpose === "string" ? e.purpose.slice(0, 200) : "",
            userApproved: !!e.userApproved,
            timestamp: admin.firestore.Timestamp.now(),
          }))
        : [];

      const syntheticStatus = deriveSyntheticMediaStatus(sourceType, sanitizedAIEvents);
      const confidence = deriveAuthenticityConfidence(capturedOnDevice, syntheticStatus);
      const disclosureRequired = deriveDisclosureRequired(syntheticStatus);

      const provenanceId = `${postId}_${mediaId}`;
      const ref = db().collection("provenance").doc(provenanceId);

      const now = admin.firestore.FieldValue.serverTimestamp();

      const doc = {
        postId,
        mediaId,
        ownerUid: uid,
        capturedOnDevice,
        sourceType,
        uploadedAt: now,
        editEvents: sanitizedEditEvents,
        aiEvents: sanitizedAIEvents,
        authenticityConfidence: confidence,
        contentCredentialsStatus: credStatus,
        syntheticMediaStatus: syntheticStatus,
        disclosureRequired,
        disclosureSatisfied: !disclosureRequired,
        moderationStatus: "pending",
        createdAt: now,
        updatedAt: now,
      };

      await ref.set(doc, {merge: false});

      return {
        provenanceId,
        authenticityConfidence: confidence,
        syntheticMediaStatus: syntheticStatus,
        disclosureRequired,
      };
    },
);

exports.getPostProvenance = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {postId, mediaId} = request.data || {};
      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }
      if (typeof mediaId !== "string" || !mediaId) {
        throw new HttpsError("invalid-argument", "mediaId required");
      }

      const provenanceId = `${postId}_${mediaId}`;
      const snap = await db().collection("provenance").doc(provenanceId).get();
      if (!snap.exists) {
        return {status: "not_found"};
      }
      const d = snap.data() || {};
      return {
        status: "ok",
        provenanceId,
        postId: d.postId,
        mediaId: d.mediaId,
        ownerUid: d.ownerUid,
        capturedOnDevice: !!d.capturedOnDevice,
        sourceType: d.sourceType || "unknown",
        authenticityConfidence: typeof d.authenticityConfidence === "number"
          ? d.authenticityConfidence
          : 0.5,
        contentCredentialsStatus: d.contentCredentialsStatus || "not_applicable",
        syntheticMediaStatus: d.syntheticMediaStatus || "unknown",
        disclosureRequired: !!d.disclosureRequired,
        disclosureSatisfied: !!d.disclosureSatisfied,
        moderationStatus: d.moderationStatus || "pending",
        editEvents: Array.isArray(d.editEvents) ? d.editEvents : [],
        aiEvents: Array.isArray(d.aiEvents) ? d.aiEvents : [],
      };
    },
);
