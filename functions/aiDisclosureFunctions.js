/**
 * aiDisclosureFunctions.js
 * Trust Spine — AI Disclosures (Phase 1, System 35).
 *
 * Every AI action that touches user-visible content must be recorded here.
 * The label + explanation that the iOS client shows MUST come from this
 * collection — never client-rendered guesses.
 *
 * Callables:
 *   registerAIDisclosure    — record an AI action (assist / edit / generate /
 *                             translate / summarize / enhance audio /
 *                             enhance lighting / suggest caption / safety
 *                             review / accessibility alt-text).
 *   getAIDisclosureDetails  — fetch user-visible disclosure details for a
 *                             specific disclosureId. Authenticated read.
 *
 * Collection: /aiDisclosures/{disclosureId}
 */

"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");

const db = () => admin.firestore();

// Allowed action types — every one of these maps to a user-visible label.
const ACTION_LABELS = {
  ai_assisted: {
    label: "AI Assisted",
    explanation: "AI helped with parts of this post — the creator approved the result.",
  },
  ai_edited: {
    label: "AI Edited",
    explanation: "AI applied edits to this media. The original capture has been modified.",
  },
  ai_generated: {
    label: "AI Generated",
    explanation: "This media was created by AI. No real-world capture was involved.",
  },
  ai_translated: {
    label: "AI Translated",
    explanation: "AI provided a translation. The original wording is preserved.",
  },
  ai_summarized: {
    label: "AI Summarized",
    explanation: "AI produced a summary. The full original is still available.",
  },
  ai_enhanced_audio: {
    label: "AI Enhanced Audio",
    explanation: "AI cleaned up or stabilized the audio. The spoken content is unchanged.",
  },
  ai_enhanced_lighting: {
    label: "AI Enhanced Lighting",
    explanation: "AI adjusted lighting. The subject of the media is unchanged.",
  },
  ai_suggested_caption: {
    label: "AI Suggested Caption",
    explanation: "AI suggested wording. The creator approved or edited it before posting.",
  },
  ai_safety_reviewed: {
    label: "AI Safety Reviewed",
    explanation: "AI checked this content against safety policies before publishing.",
  },
  ai_alt_text: {
    label: "Alt Text Assisted",
    explanation: "AI generated an accessibility description. The creator can edit it.",
  },
};

function clampString(s, n) {
  if (typeof s !== "string") return "";
  return s.slice(0, n);
}

function clampNumber(n, lo, hi) {
  const v = typeof n === "number" && isFinite(n) ? n : lo;
  return Math.max(lo, Math.min(hi, v));
}

exports.registerAIDisclosure = onCall(
    {
      region: "us-central1",
      enforceAppCheck: true,
    },
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      await checkRateLimit(uid, "register_ai_disclosure", 200, 3600);

      const {
        postId,
        mediaId,
        actionType,
        modelProvider,
        purpose,
        confidence,
      } = request.data || {};

      if (typeof postId !== "string" || !postId) {
        throw new HttpsError("invalid-argument", "postId required");
      }
      if (typeof mediaId !== "string" || !mediaId) {
        throw new HttpsError("invalid-argument", "mediaId required");
      }
      const mapping = ACTION_LABELS[actionType];
      if (!mapping) {
        throw new HttpsError("invalid-argument", "actionType invalid");
      }

      const disclosureId = `${postId}_${mediaId}_${actionType}`;
      const doc = {
        postId,
        mediaId,
        ownerUid: uid,
        actionType,
        modelProvider: clampString(modelProvider, 64) || null,
        purpose: clampString(purpose, 200),
        userVisibleLabel: mapping.label,
        userVisibleExplanation: mapping.explanation,
        confidence: clampNumber(confidence, 0, 1),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db().collection("aiDisclosures").doc(disclosureId).set(doc, {merge: false});

      // Mark provenance.disclosureSatisfied = true once any disclosure is registered.
      const provenanceId = `${postId}_${mediaId}`;
      const provRef = db().collection("provenance").doc(provenanceId);
      const provSnap = await provRef.get();
      if (provSnap.exists) {
        await provRef.update({
          disclosureSatisfied: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      return {
        disclosureId,
        userVisibleLabel: mapping.label,
        userVisibleExplanation: mapping.explanation,
      };
    },
);

exports.getAIDisclosureDetails = onCall(
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

      const snap = await db()
          .collection("aiDisclosures")
          .where("postId", "==", postId)
          .where("mediaId", "==", mediaId)
          .limit(20)
          .get();

      const records = [];
      snap.forEach((d) => {
        const x = d.data() || {};
        records.push({
          id: d.id,
          postId: x.postId,
          mediaId: x.mediaId,
          ownerUid: x.ownerUid,
          actionType: x.actionType,
          modelProvider: x.modelProvider || null,
          purpose: x.purpose || "",
          userVisibleLabel: x.userVisibleLabel,
          userVisibleExplanation: x.userVisibleExplanation,
          confidence: typeof x.confidence === "number" ? x.confidence : 0,
        });
      });

      return {records};
    },
);
