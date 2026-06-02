/**
 * spacesAIFunctions.js
 * AMEN Spaces — AI catch-up callables
 * Handles: generateRecap, searchTranscripts, generateClip, studyCompanionQuery
 *
 * AEGIS RULE: All AI output must be written with aegisReviewedAt: null and
 * reviewed before the iOS client shows it to users.
 * AmenReplayRecapCard checks aegisReviewedAt !== null before rendering.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

// ── generateRecap ─────────────────────────────────────────────────────────────

exports.generateRecap = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId } = request.data ?? {};
  if (!spaceId || !roomId) {
    throw new HttpsError("invalid-argument", "spaceId and roomId are required.");
  }

  const roomSnap = await db.collection("spaces").doc(spaceId)
    .collection("liveRooms").doc(roomId).get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Live room not found.");
  if (roomSnap.data()?.state !== "ended") {
    throw new HttpsError("failed-precondition", "Recap can only be generated after the room ends.");
  }

  // Check entitlement
  const entSnap = await db.collection("spaces").doc(spaceId)
    .collection("entitlements").doc(userId).get();
  if (!entSnap.exists || !entSnap.data()?.isActive) {
    throw new HttpsError("permission-denied", "Active entitlement required.");
  }

  const recapId = `recap_${roomId}`;
  const recapRef = db.collection("spaces").doc(spaceId).collection("recaps").doc(recapId);
  const existingRecap = await recapRef.get();
  if (existingRecap.exists) {
    return { recapId, alreadyExists: true };
  }

  // Write stub — Aegis will review before iOS shows it (aegisReviewedAt stays null)
  await recapRef.set({
    id: recapId, spaceId, roomId,
    title: "Recap pending", summary: "",
    keyPoints: [], scriptureReferences: [],
    chapters: [], autoClips: [],
    transcriptSegments: [],
    aegisReviewedAt: null,
    createdAt: FieldValue.serverTimestamp(),
    generatedBy: userId,
  });

  return { recapId, ok: true };
});

// ── searchTranscripts ─────────────────────────────────────────────────────────

exports.searchTranscripts = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, query, limit: limitVal } = request.data ?? {};
  if (!spaceId || !query || query.trim().length === 0) {
    throw new HttpsError("invalid-argument", "spaceId and query are required.");
  }

  const entSnap = await db.collection("spaces").doc(spaceId)
    .collection("entitlements").doc(userId).get();
  if (!entSnap.exists || !entSnap.data()?.isActive) {
    throw new HttpsError("permission-denied", "Active entitlement required.");
  }

  const pageSize = Math.min(Math.max(parseInt(limitVal ?? 20), 1), 100);

  // Firestore full-text search is limited — in production wire to Algolia/Typesense.
  // This returns recently-reviewed recaps that contain the query string in their summary.
  const snap = await db.collection("spaces").doc(spaceId).collection("recaps")
    .where("aegisReviewedAt", "!=", null)
    .orderBy("aegisReviewedAt", "desc")
    .limit(pageSize)
    .get();

  const lowerQuery = query.toLowerCase();
  const results = snap.docs
    .map((d) => d.data())
    .filter((r) =>
      r.summary?.toLowerCase().includes(lowerQuery) ||
      r.title?.toLowerCase().includes(lowerQuery) ||
      (r.keyPoints ?? []).some((kp) => kp.toLowerCase?.().includes(lowerQuery))
    )
    .map((r) => ({
      recapId: r.id, roomId: r.roomId,
      title: r.title, summary: r.summary,
      matchType: "summary",
    }));

  return { results };
});

// ── generateClip ──────────────────────────────────────────────────────────────

exports.generateClip = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, roomId, startMs, endMs, title } = request.data ?? {};
  if (!spaceId || !roomId || typeof startMs !== "number" || typeof endMs !== "number") {
    throw new HttpsError("invalid-argument", "spaceId, roomId, startMs, endMs are required.");
  }
  if (endMs - startMs < 5000 || endMs - startMs > 180000) {
    throw new HttpsError("invalid-argument", "Clip must be 5 seconds to 3 minutes.");
  }

  const entSnap = await db.collection("spaces").doc(spaceId)
    .collection("entitlements").doc(userId).get();
  if (!entSnap.exists || !entSnap.data()?.isActive) {
    throw new HttpsError("permission-denied", "Active entitlement required.");
  }

  const clipId = `clip_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  await db.collection("spaces").doc(spaceId).collection("clips").doc(clipId).set({
    id: clipId, spaceId, roomId,
    startMs, endMs,
    title: title ?? "Clip",
    createdBy: userId,
    url: null, // populated by media processing pipeline
    createdAt: FieldValue.serverTimestamp(),
  });

  return { clipId, ok: true };
});

// ── studyCompanionQuery ───────────────────────────────────────────────────────

exports.studyCompanionQuery = onCall({ enforceAppCheck: false }, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, recapId, question } = request.data ?? {};
  if (!spaceId || !recapId || !question || question.trim().length === 0) {
    throw new HttpsError("invalid-argument", "spaceId, recapId, and question are required.");
  }
  if (question.length > 500) {
    throw new HttpsError("invalid-argument", "Question must be ≤500 chars.");
  }

  const entSnap = await db.collection("spaces").doc(spaceId)
    .collection("entitlements").doc(userId).get();
  if (!entSnap.exists || !entSnap.data()?.isActive) {
    throw new HttpsError("permission-denied", "Active entitlement required.");
  }

  const recapSnap = await db.collection("spaces").doc(spaceId)
    .collection("recaps").doc(recapId).get();
  if (!recapSnap.exists) throw new HttpsError("not-found", "Recap not found.");
  if (!recapSnap.data()?.aegisReviewedAt) {
    throw new HttpsError("failed-precondition", "Recap has not yet passed Aegis review.");
  }

  // Provenance enforcement: only answer from Aegis-reviewed recap content.
  // If recap has no key points or scripture references, return empty citations.
  const recap = recapSnap.data();
  const citations = [
    ...(recap.keyPoints ?? []).map((kp, i) => ({ type: "keyPoint", index: i, text: kp })),
    ...(recap.scriptureReferences ?? []).map((ref) => ({ type: "scripture", reference: ref })),
  ];

  if (citations.length === 0) {
    // AmenStudyCompanionSheet checks citations.length === 0 → shows "could not be grounded"
    return { answer: null, citations: [] };
  }

  // In production: call Berean AI with recap context + question.
  // For now return citations only; the iOS client will call bereanBibleQA separately.
  return {
    answer: null, // iOS client resolves answer via bereanBibleQA with these citations
    citations,
    recapTitle: recap.title,
  };
});
