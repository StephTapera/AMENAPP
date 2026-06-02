// callable.ts — Callable Cloud Functions for Spaces AI (recaps, search, clips, study companion)

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

// ── Types ─────────────────────────────────────────────────────────────────────

interface GenerateRecapRequest {
  spaceId: string;
  sourceRef: string;
  sourceTitle: string;
}

interface SearchTranscriptsRequest {
  sourceRef: string;
  query: string;
}

interface GenerateClipRequest {
  spaceId: string;
  sourceRef: string;
  startSecs: number;
  durationSecs: number;
  title: string;
}

interface StudyCompanionQueryRequest {
  spaceId: string;
  videoId: string;
  question: string;
}

interface TranscriptSegment {
  id: string;
  sourceRef: string;
  text: string;
  startSecs: number;
  endSecs: number;
  speaker: string | null;
}

interface StudyCompanionSettings {
  enabled: boolean;
}

// ── generateRecap ─────────────────────────────────────────────────────────────

export const generateRecap = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as GenerateRecapRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const sourceRef = String(data?.sourceRef ?? "").trim();
    const sourceTitle = String(data?.sourceTitle ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!sourceRef) throw new functions.HttpsError("invalid-argument", "sourceRef is required.");
    if (!sourceTitle) throw new functions.HttpsError("invalid-argument", "sourceTitle is required.");
    if (sourceTitle.length > 200) {
      throw new functions.HttpsError("invalid-argument", "sourceTitle must be 200 characters or fewer.");
    }

    const recapRef = db.collection("spaces").doc(spaceId).collection("recaps").doc();
    const recapId = recapRef.id;

    const batch = db.batch();

    batch.set(recapRef, {
      id: recapId,
      spaceId,
      sourceRef,
      sourceTitle,
      keyPoints: [],
      scriptureRefs: [],
      actionItems: [],
      durationEstimateSecs: 90,
      generatedAt: FieldValue.serverTimestamp(),
      aegisReviewedAt: null,
    });

    const queueRef = db.collection("spaces").doc(spaceId).collection("recapQueue").doc(recapId);
    batch.set(queueRef, {
      recapId,
      sourceRef,
      requestedBy: userId,
      requestedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();
    logger.info(`generateRecap: queued recap ${recapId} for space ${spaceId}`);

    return { recapId, status: "queued" };
  }
);

// ── searchTranscripts ─────────────────────────────────────────────────────────

export const searchTranscripts = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as SearchTranscriptsRequest;
    const sourceRef = String(data?.sourceRef ?? "").trim();
    const query = String(data?.query ?? "").trim();

    if (!sourceRef) throw new functions.HttpsError("invalid-argument", "sourceRef is required.");
    if (query.length < 2) {
      throw new functions.HttpsError("invalid-argument", "query must be at least 2 characters.");
    }
    if (query.length > 200) {
      throw new functions.HttpsError("invalid-argument", "query must be 200 characters or fewer.");
    }

    // NOTE: Firestore does not support full-text search. This stub returns up to 10
    // transcript segments for the given sourceRef. In production, replace this with
    // Algolia or Vertex AI Search for proper keyword/semantic matching.
    const snap = await db
      .collection("transcripts")
      .where("sourceRef", "==", sourceRef)
      .limit(10)
      .get();

    const results: TranscriptSegment[] = snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        sourceRef: String(d.sourceRef ?? ""),
        text: String(d.text ?? ""),
        startSecs: Number(d.startSecs ?? 0),
        endSecs: Number(d.endSecs ?? 0),
        speaker: d.speaker ? String(d.speaker) : null,
      };
    });

    logger.info(`searchTranscripts: returned ${results.length} segments for sourceRef=${sourceRef}`);

    return { results, query };
  }
);

// ── generateClip ──────────────────────────────────────────────────────────────

export const generateClip = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as GenerateClipRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const sourceRef = String(data?.sourceRef ?? "").trim();
    const startSecs = Number(data?.startSecs);
    const durationSecs = Number(data?.durationSecs);
    const title = String(data?.title ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!sourceRef) throw new functions.HttpsError("invalid-argument", "sourceRef is required.");
    if (isNaN(startSecs) || startSecs < 0) {
      throw new functions.HttpsError("invalid-argument", "startSecs must be a non-negative number.");
    }
    if (isNaN(durationSecs) || durationSecs < 5 || durationSecs > 120) {
      throw new functions.HttpsError("invalid-argument", "durationSecs must be between 5 and 120.");
    }
    if (!title || title.length < 1 || title.length > 100) {
      throw new functions.HttpsError("invalid-argument", "title must be between 1 and 100 characters.");
    }

    const clipRef = db.collection("spaces").doc(spaceId).collection("clips").doc();
    const clipId = clipRef.id;

    const batch = db.batch();

    batch.set(clipRef, {
      id: clipId,
      spaceId,
      sourceRef,
      startSecs,
      durationSecs,
      title,
      thumbnailRef: null,
      shareUrl: null,
      generatedAt: FieldValue.serverTimestamp(),
      processingStatus: "queued",
    });

    const jobRef = db.collection("clipProcessingQueue").doc(clipId);
    batch.set(jobRef, {
      clipId,
      sourceRef,
      startSecs,
      durationSecs,
      requestedBy: userId,
      requestedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();
    logger.info(`generateClip: queued clip ${clipId} for space ${spaceId}`);

    return { clipId, status: "queued" };
  }
);

// ── studyCompanionQuery ───────────────────────────────────────────────────────

export const studyCompanionQuery = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as StudyCompanionQueryRequest;
    const spaceId = String(data?.spaceId ?? "").trim();
    const videoId = String(data?.videoId ?? "").trim();
    const question = String(data?.question ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!videoId) throw new functions.HttpsError("invalid-argument", "videoId is required.");
    if (question.length < 5) {
      throw new functions.HttpsError("invalid-argument", "question must be at least 5 characters.");
    }
    if (question.length > 500) {
      throw new functions.HttpsError("invalid-argument", "question must be 500 characters or fewer.");
    }

    // Verify host has opted in to the study companion feature
    const settingsRef = db
      .collection("spaces").doc(spaceId)
      .collection("settings").doc("studyCompanion");
    const settingsSnap = await settingsRef.get();

    if (!settingsSnap.exists) {
      throw new functions.HttpsError(
        "permission-denied",
        "Study companion not enabled for this space."
      );
    }

    const settings = settingsSnap.data() as StudyCompanionSettings;
    if (settings.enabled === false) {
      throw new functions.HttpsError(
        "permission-denied",
        "Study companion not enabled for this space."
      );
    }

    // Log the query for analytics and host review
    const logRef = db.collection("spaces").doc(spaceId).collection("studyCompanionLog").doc();
    await logRef.set({
      userId,
      videoId,
      question,
      askedAt: FieldValue.serverTimestamp(),
    });

    logger.info(`studyCompanionQuery: user ${userId} asked in space ${spaceId}`);

    // NOTE: In production this stub would call a retrieval-augmented generation pipeline
    // backed by the host's indexed transcript. The pipeline would return grounded citations.
    return {
      answer:
        "Study companion response is processing. This feature requires the host's transcript to be indexed.",
      citations: [] as string[],
      grounded: false,
    };
  }
);
