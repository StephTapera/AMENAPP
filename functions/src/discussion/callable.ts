// callable.ts — Discussion system callable Cloud Functions

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { generateBereanSummary } from "./llmAdapter";
import { embedText, cosineSimilarity } from "./embeddingAdapter";

// Secrets must be declared here so the runtime injects them into process.env
// before the module-level adapter functions read them.
export const BEREAN_LLM_KEY_SECRET = defineSecret("BEREAN_LLM_KEY");
export const EMBEDDING_KEY_SECRET   = defineSecret("EMBEDDING_KEY");

const db = getFirestore();

// ── Local interfaces ──────────────────────────────────────────────────────────

interface AskBereanRequest {
  threadId: string;
}

interface DetectDuplicateRequest {
  threadId: string;
  draftBody: string;
}

interface ComputeReputationRequest {
  uid: string;
}

interface PostCommentRequest {
  threadId: string;
  parentCommentId?: string;
  body: string;
  destination: string;
  thresholdPassedAt: string | number;
}

interface MarkHelpfulRequest {
  commentId: string;
  threadId: string;
}

interface UpdateWatchProgressRequest {
  postId: string;
  progressFraction: number;
  durationSecs: number;
  watchedSecs: number;
  transcriptRead?: boolean;
}

interface GetWatchProgressRequest {
  postId: string;
}

// ── Book-name → OSIS key map ──────────────────────────────────────────────────

const BOOK_MAP: Record<string, string> = {
  genesis: "GEN",
  gen: "GEN",
  exodus: "EXO",
  exo: "EXO",
  leviticus: "LEV",
  lev: "LEV",
  numbers: "NUM",
  num: "NUM",
  deuteronomy: "DEU",
  deu: "DEU",
  joshua: "JOS",
  jos: "JOS",
  judges: "JDG",
  jdg: "JDG",
  ruth: "RUT",
  rut: "RUT",
  psalms: "PSA",
  psalm: "PSA",
  psa: "PSA",
  ps: "PSA",
  proverbs: "PRO",
  pro: "PRO",
  prov: "PRO",
  ecclesiastes: "ECC",
  ecc: "ECC",
  isaiah: "ISA",
  isa: "ISA",
  jeremiah: "JER",
  jer: "JER",
  ezekiel: "EZK",
  ezk: "EZK",
  daniel: "DAN",
  dan: "DAN",
  matthew: "MAT",
  mat: "MAT",
  matt: "MAT",
  mark: "MRK",
  mrk: "MRK",
  luke: "LUK",
  luk: "LUK",
  john: "JHN",
  jhn: "JHN",
  acts: "ACT",
  act: "ACT",
  romans: "ROM",
  rom: "ROM",
  corinthians: "1CO",
  galatians: "GAL",
  gal: "GAL",
  ephesians: "EPH",
  eph: "EPH",
  philippians: "PHP",
  php: "PHP",
  colossians: "COL",
  col: "COL",
  hebrews: "HEB",
  heb: "HEB",
  james: "JAS",
  jas: "JAS",
  revelation: "REV",
  rev: "REV",
};

// Numbered book prefixes (e.g. "1 John", "2 Corinthians")
const NUMBERED_BOOK_MAP: Record<string, string> = {
  "1 samuel": "1SA",
  "2 samuel": "2SA",
  "1 kings": "1KI",
  "2 kings": "2KI",
  "1 chronicles": "1CH",
  "2 chronicles": "2CH",
  "1 corinthians": "1CO",
  "2 corinthians": "2CO",
  "1 thessalonians": "1TH",
  "2 thessalonians": "2TH",
  "1 timothy": "1TI",
  "2 timothy": "2TI",
  "1 peter": "1PE",
  "2 peter": "2PE",
  "1 john": "1JN",
  "2 john": "2JN",
  "3 john": "3JN",
};

/**
 * Detects Bible verse references in the given body and returns OSIS keys.
 * Exported for testability.
 */
export function detectVerseKeys(body: string): string[] {
  const keys: string[] = [];
  const seen = new Set<string>();

  // Match patterns like "1 John 3:16", "Romans 8:28", "Psalm 23:1"
  const regex = /\b((?:[123]\s+)?[A-Za-z]+)\s+(\d+):(\d+)\b/g;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(body)) !== null) {
    const rawBook = match[1].trim();
    const chapter = match[2];
    const verse = match[3];
    const lowerRaw = rawBook.toLowerCase();

    // Try exact key in numbered map first
    let osisBook: string | undefined;

    // Check numbered book map (e.g. "1 john")
    for (const [pattern, osis] of Object.entries(NUMBERED_BOOK_MAP)) {
      if (lowerRaw === pattern) {
        osisBook = osis;
        break;
      }
    }

    // Fall back to plain book map
    if (!osisBook) {
      // Strip leading digit + space for numbered books that slip through
      const stripped = lowerRaw.replace(/^[123]\s+/, "");
      osisBook = BOOK_MAP[lowerRaw] ?? BOOK_MAP[stripped];
    }

    if (osisBook) {
      const osisKey = `${osisBook}.${chapter}.${verse}`;
      if (!seen.has(osisKey)) {
        seen.add(osisKey);
        keys.push(osisKey);
      }
    }
  }

  return keys;
}

// ── askBerean ─────────────────────────────────────────────────────────────────

export const askBerean = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as AskBereanRequest;
    const threadId = String(data?.threadId ?? "").trim();
    if (!threadId) throw new functions.HttpsError("invalid-argument", "threadId is required.");

    // ── Rate limit check ──────────────────────────────────────────────────────
    const rateLimitDocId = `${userId}_${threadId}`;
    const rateLimitRef = db
      .collection("discussions")
      .doc("rateLimits")
      .collection("askBerean")
      .doc(rateLimitDocId);

    const rateLimitSnap = await rateLimitRef.get();
    if (rateLimitSnap.exists) {
      const lastCalledAt: FirebaseFirestore.Timestamp = rateLimitSnap.data()?.lastCalledAt;
      if (lastCalledAt) {
        const secondsElapsed = (Date.now() - lastCalledAt.toMillis()) / 1000;
        if (secondsElapsed < 600) {
          throw new functions.HttpsError(
            "resource-exhausted",
            "Rate limit: wait 10 minutes between Berean queries."
          );
        }
      }
    }

    // ── Fetch thread ──────────────────────────────────────────────────────────
    const threadRef = db.collection("threads").doc(threadId);
    const threadSnap = await threadRef.get();
    if (!threadSnap.exists) throw new functions.HttpsError("not-found", "Thread not found.");

    const threadData = threadSnap.data()!;
    if (threadData.isLocked) {
      throw new functions.HttpsError("failed-precondition", "Thread is locked.");
    }

    // ── Fetch comments ────────────────────────────────────────────────────────
    const commentsSnap = await db
      .collection("threads")
      .doc(threadId)
      .collection("comments")
      .where("isDeleted", "==", false)
      .orderBy("createdAt", "asc")
      .limit(50)
      .get();

    const commentLines = commentsSnap.docs
      .map((d, i) => {
        const body = String(d.data().body ?? "").slice(0, 300);
        return `${i + 1}. ${body}`;
      })
      .join("\n");

    const postType = String(threadData.postType ?? "general");

    const prompt = `You are Berean, a biblical discussion assistant. Analyze this thread and respond with JSON only.
Thread about post type: ${postType}
Comments (${commentsSnap.size} total):
${commentLines}

Return JSON with exactly these fields:
{ "summary": "string", "agreementPoints": ["..."], "openQuestions": ["..."], "biblicalRefs": ["OSIS verse keys only, e.g. JHN.3.16"], "studyQuestions": ["..."] }`;

    logger.info(`askBerean: generating summary for thread ${threadId}, ${commentsSnap.size} comments.`);

    // ── Call LLM ──────────────────────────────────────────────────────────────
    const llmResult = await generateBereanSummary(prompt);

    let summary = llmResult.summary;
    let agreementPoints = llmResult.agreementPoints;
    let openQuestions = llmResult.openQuestions;
    let biblicalRefs = llmResult.biblicalRefs;
    let studyQuestions = llmResult.studyQuestions;

    // When NOT mock, try to re-parse the raw summary as JSON (LLM may have
    // returned JSON-formatted text in the summary field from a previous round)
    if (!llmResult.isMock) {
      try {
        const candidate = JSON.parse(llmResult.summary) as {
          summary?: string;
          agreementPoints?: string[];
          openQuestions?: string[];
          biblicalRefs?: string[];
          studyQuestions?: string[];
        };
        summary = String(candidate.summary ?? summary);
        agreementPoints = Array.isArray(candidate.agreementPoints) ? candidate.agreementPoints : agreementPoints;
        openQuestions = Array.isArray(candidate.openQuestions) ? candidate.openQuestions : openQuestions;
        biblicalRefs = Array.isArray(candidate.biblicalRefs) ? candidate.biblicalRefs : biblicalRefs;
        studyQuestions = Array.isArray(candidate.studyQuestions) ? candidate.studyQuestions : studyQuestions;
      } catch {
        // summary was already a plain string — use as-is
      }
    }

    // ── Write BereanSummary doc ───────────────────────────────────────────────
    const summaryRef = db.collection("threads").doc(threadId).collection("bereanSummaries").doc();
    const summaryId = summaryRef.id;

    const summaryDoc = {
      id: summaryId,
      threadId,
      requestedBy: userId,
      summary,
      agreementPoints,
      openQuestions,
      biblicalRefs,
      studyQuestions,
      generatedAt: FieldValue.serverTimestamp(),
      tokenCount: llmResult.tokenCount,
      isMock: llmResult.isMock,
    };

    const batch = db.batch();
    batch.set(summaryRef, summaryDoc);
    batch.update(threadRef, { bereanSummaryRef: summaryRef.path });
    batch.set(rateLimitRef, { lastCalledAt: FieldValue.serverTimestamp() }, { merge: true });
    await batch.commit();

    logger.info(`askBerean: summary ${summaryId} written for thread ${threadId}.`);

    return { summaryId, summary, agreementPoints, openQuestions, biblicalRefs, studyQuestions, isMock: llmResult.isMock };
  }
);

// ── detectDuplicate ───────────────────────────────────────────────────────────

export const detectDuplicate = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as DetectDuplicateRequest;
    const threadId = String(data?.threadId ?? "").trim();
    const draftBody = String(data?.draftBody ?? "").trim();

    if (!threadId) throw new functions.HttpsError("invalid-argument", "threadId is required.");
    if (draftBody.length < 5 || draftBody.length > 2000) {
      throw new functions.HttpsError("invalid-argument", "draftBody must be 5–2000 characters.");
    }

    // Short-circuit when embedding key is absent
    if (!EMBEDDING_KEY_SECRET.value()) {
      logger.info("detectDuplicate: EMBEDDING_KEY not set — short-circuiting.");
      return { isDuplicate: false, similarCommentIds: [], similarityScore: 0, suggestion: null };
    }

    logger.info(`detectDuplicate: embedding draft for thread ${threadId}.`);
    const draftEmbedding = await embedText(draftBody);

    // Fetch up to 30 comments that have an embedding stored
    const commentsSnap = await db
      .collection("threads")
      .doc(threadId)
      .collection("comments")
      .where("isDeleted", "==", false)
      .where("embedding", "!=", null)
      .limit(30)
      .get();

    const scored: Array<{ id: string; score: number }> = [];

    for (const doc of commentsSnap.docs) {
      const embedding = doc.data().embedding as number[] | null;
      if (!embedding || !Array.isArray(embedding)) continue;
      const score = cosineSimilarity(draftEmbedding, embedding);
      scored.push({ id: doc.id, score });
    }

    scored.sort((a, b) => b.score - a.score);

    const DUPLICATE_THRESHOLD = 0.82;
    const RELATED_THRESHOLD = 0.65;

    const top3 = scored.slice(0, 3).filter((s) => s.score > DUPLICATE_THRESHOLD);
    const topScore = scored.length > 0 ? scored[0].score : 0;
    const isDuplicate = topScore > DUPLICATE_THRESHOLD;

    let suggestion: string | null = null;
    if (isDuplicate) {
      suggestion = "supportExisting";
    } else if (topScore > RELATED_THRESHOLD) {
      suggestion = "addAngle";
    }

    logger.info(`detectDuplicate: topScore=${topScore}, isDuplicate=${isDuplicate}.`);

    return {
      isDuplicate,
      similarCommentIds: top3.map((s) => s.id),
      similarityScore: topScore,
      suggestion,
    };
  }
);

// ── computeReputation ─────────────────────────────────────────────────────────

export const computeReputation = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ComputeReputationRequest;
    const uid = String(data?.uid ?? "").trim();
    if (!uid) throw new functions.HttpsError("invalid-argument", "uid is required.");

    logger.info(`computeReputation: computing for uid=${uid}.`);

    const eventsSnap = await db
      .collection("reputationEvents")
      .where("toUID", "==", uid)
      .limit(500)
      .get();

    const breakdown = { helpfulMark: 0, acceptedAnswer: 0, firstComment: 0, bereanCite: 0 };

    for (const doc of eventsSnap.docs) {
      const type = String(doc.data().type ?? "");
      switch (type) {
        case "helpfulMark":
          breakdown.helpfulMark += 3;
          break;
        case "acceptedAnswer":
          breakdown.acceptedAnswer += 10;
          break;
        case "firstComment":
          breakdown.firstComment += 1;
          break;
        case "bereanCite":
          breakdown.bereanCite += 2;
          break;
        default:
          break;
      }
    }

    const totalPoints = breakdown.helpfulMark + breakdown.acceptedAnswer + breakdown.firstComment + breakdown.bereanCite;

    let badgeTier: string;
    if (totalPoints >= 200) {
      badgeTier = "elder";
    } else if (totalPoints >= 50) {
      badgeTier = "berean";
    } else if (totalPoints >= 10) {
      badgeTier = "seeker";
    } else {
      badgeTier = "none";
    }

    logger.info(`computeReputation: uid=${uid} totalPoints=${totalPoints} badge=${badgeTier}.`);

    return { uid, totalPoints, badgeTier, breakdown };
  }
);

// ── postComment ───────────────────────────────────────────────────────────────

export const postComment = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as PostCommentRequest;
    const threadId = String(data?.threadId ?? "").trim();
    const parentCommentId = data?.parentCommentId ? String(data.parentCommentId).trim() : "";
    const body = String(data?.body ?? "").trim();
    const destination = String(data?.destination ?? "").trim();
    const thresholdPassedAt = data?.thresholdPassedAt;

    // ── Validate ──────────────────────────────────────────────────────────────
    if (!threadId) throw new functions.HttpsError("invalid-argument", "threadId is required.");
    if (body.length < 1 || body.length > 2000) {
      throw new functions.HttpsError("invalid-argument", "body must be 1–2000 characters.");
    }
    const VALID_DESTINATIONS = ["public", "reflection", "churchNotes"];
    if (!VALID_DESTINATIONS.includes(destination)) {
      throw new functions.HttpsError("invalid-argument", "destination must be one of: public, reflection, churchNotes.");
    }

    // ── Fetch thread ──────────────────────────────────────────────────────────
    const threadRef = db.collection("threads").doc(threadId);
    const threadSnap = await threadRef.get();
    if (!threadSnap.exists) throw new functions.HttpsError("not-found", "Thread not found.");
    if (threadSnap.data()?.isLocked) {
      throw new functions.HttpsError("failed-precondition", "Thread is locked.");
    }

    // ── Resolve depth ─────────────────────────────────────────────────────────
    let depth = 0;
    if (parentCommentId) {
      const parentRef = db.collection("threads").doc(threadId).collection("comments").doc(parentCommentId);
      const parentSnap = await parentRef.get();
      if (!parentSnap.exists) throw new functions.HttpsError("not-found", "Parent comment not found.");
      depth = (parentSnap.data()?.depth ?? 0) + 1;
      if (depth > 2) {
        throw new functions.HttpsError("invalid-argument", "Max reply depth is 2.");
      }
    }

    // ── Detect verse keys ─────────────────────────────────────────────────────
    const verseKeys = detectVerseKeys(body);

    // ── Resolve display name ──────────────────────────────────────────────────
    const authorDisplayName = request.auth?.token?.name
      ? String(request.auth.token.name)
      : userId;

    // ── Write comment ─────────────────────────────────────────────────────────
    const commentRef = db.collection("threads").doc(threadId).collection("comments").doc();
    const commentId = commentRef.id;

    let parsedThreshold: Date | null = null;
    try {
      parsedThreshold = thresholdPassedAt ? new Date(thresholdPassedAt) : null;
    } catch {
      parsedThreshold = null;
    }

    const commentDoc = {
      id: commentId,
      threadId,
      authorUID: userId,
      authorDisplayName,
      authorAvatarURL: null,
      parentCommentId: parentCommentId || null,
      depth,
      body,
      verseKeys,
      destination,
      helpfulCount: 0,
      isAcceptedAnswer: false,
      isDeleted: false,
      deletedAt: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: null,
      reportedAt: null,
      thresholdPassedAt: parsedThreshold,
      embedding: null,
    };

    const batch = db.batch();
    batch.set(commentRef, commentDoc);

    // Increment comment count on thread
    batch.update(threadRef, { commentCount: FieldValue.increment(1) });

    // firstComment reputation event
    const repFirstRef = db.collection("reputationEvents").doc();
    batch.set(repFirstRef, {
      id: repFirstRef.id,
      type: "firstComment",
      fromUID: userId,
      toUID: userId,
      commentId,
      threadId,
      points: 1,
      createdAt: FieldValue.serverTimestamp(),
    });

    // bereanCite reputation event (if verse keys detected)
    let awardedBereanCite = false;
    if (verseKeys.length > 0) {
      const repCiteRef = db.collection("reputationEvents").doc();
      batch.set(repCiteRef, {
        id: repCiteRef.id,
        type: "bereanCite",
        fromUID: userId,
        toUID: userId,
        commentId,
        threadId,
        points: 2,
        createdAt: FieldValue.serverTimestamp(),
      });
      awardedBereanCite = true;
    }

    // Queue embedding job
    const embeddingQueueRef = db.collection("embeddingQueue").doc(commentId);
    batch.set(embeddingQueueRef, {
      commentId,
      threadId,
      body,
      requestedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    logger.info(`postComment: comment ${commentId} posted to thread ${threadId}, depth=${depth}, verseKeys=${verseKeys.length}.`);

    return { commentId, verseKeys, awardedBereanCite };
  }
);

// ── markHelpful ───────────────────────────────────────────────────────────────

export const markHelpful = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as MarkHelpfulRequest;
    const commentId = String(data?.commentId ?? "").trim();
    const threadId = String(data?.threadId ?? "").trim();

    if (!commentId) throw new functions.HttpsError("invalid-argument", "commentId is required.");
    if (!threadId) throw new functions.HttpsError("invalid-argument", "threadId is required.");

    // ── Fetch comment ─────────────────────────────────────────────────────────
    const commentRef = db.collection("threads").doc(threadId).collection("comments").doc(commentId);
    const commentSnap = await commentRef.get();

    if (!commentSnap.exists) throw new functions.HttpsError("not-found", "Comment not found.");
    const commentData = commentSnap.data()!;
    if (commentData.isDeleted) throw new functions.HttpsError("not-found", "Comment not found.");

    // Cannot mark own comment
    if (commentData.authorUID === userId) {
      throw new functions.HttpsError("failed-precondition", "Cannot mark your own comment as helpful.");
    }

    // ── Idempotency check ─────────────────────────────────────────────────────
    const existingSnap = await db
      .collection("reputationEvents")
      .where("fromUID", "==", userId)
      .where("commentId", "==", commentId)
      .where("type", "==", "helpfulMark")
      .limit(1)
      .get();

    if (!existingSnap.empty) {
      const existingId = existingSnap.docs[0].id;
      logger.info(`markHelpful: already marked — returning existing event ${existingId}.`);
      return { eventId: existingId, isNew: false, helpfulCount: commentData.helpfulCount ?? 0 };
    }

    // ── Write rep event + increment ───────────────────────────────────────────
    const eventRef = db.collection("reputationEvents").doc();
    const eventId = eventRef.id;

    const batch = db.batch();
    batch.set(eventRef, {
      id: eventId,
      type: "helpfulMark",
      fromUID: userId,
      toUID: commentData.authorUID,
      commentId,
      threadId,
      points: 3,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.update(commentRef, { helpfulCount: FieldValue.increment(1) });
    await batch.commit();

    const newHelpfulCount = (commentData.helpfulCount ?? 0) + 1;
    logger.info(`markHelpful: event ${eventId} written for comment ${commentId}.`);

    return { eventId, isNew: true, helpfulCount: newHelpfulCount };
  }
);

// ── updateWatchProgress ───────────────────────────────────────────────────────

export const updateWatchProgress = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as UpdateWatchProgressRequest;
    const postId = String(data?.postId ?? "").trim();
    const progressFraction = Number(data?.progressFraction ?? 0);
    const durationSecs = Number(data?.durationSecs ?? 0);
    const watchedSecs = Number(data?.watchedSecs ?? 0);
    const transcriptRead = Boolean(data?.transcriptRead ?? false);

    if (!postId) throw new functions.HttpsError("invalid-argument", "postId is required.");
    if (progressFraction < 0 || progressFraction > 1) {
      throw new functions.HttpsError("invalid-argument", "progressFraction must be 0–1.");
    }
    if (durationSecs <= 0) {
      throw new functions.HttpsError("invalid-argument", "durationSecs must be greater than 0.");
    }
    if (watchedSecs < 0) {
      throw new functions.HttpsError("invalid-argument", "watchedSecs must be >= 0.");
    }

    const docId = `${userId}_${postId}`;
    const docRef = db.collection("watchProgress").doc(docId);

    await docRef.set(
      {
        userId,
        postId,
        progressFraction,
        durationSecs,
        watchedSecs,
        transcriptRead,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const shouldNudge = progressFraction < 0.8 && !transcriptRead;

    logger.info(`updateWatchProgress: upserted ${docId}, progress=${progressFraction}, shouldNudge=${shouldNudge}.`);

    return { shouldNudge };
  }
);

// ── getWatchProgress ──────────────────────────────────────────────────────────

export const getWatchProgress = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as GetWatchProgressRequest;
    const postId = String(data?.postId ?? "").trim();
    if (!postId) throw new functions.HttpsError("invalid-argument", "postId is required.");

    const docId = `${userId}_${postId}`;
    const docRef = db.collection("watchProgress").doc(docId);
    const snap = await docRef.get();

    if (!snap.exists) {
      logger.info(`getWatchProgress: no record for ${docId}.`);
      return { progressFraction: null, transcriptRead: false, shouldNudge: true };
    }

    const doc = snap.data()!;
    const progressFraction = typeof doc.progressFraction === "number" ? doc.progressFraction : null;
    const transcriptRead = Boolean(doc.transcriptRead ?? false);
    const shouldNudge = (progressFraction === null || progressFraction < 0.8) && !transcriptRead;

    logger.info(`getWatchProgress: ${docId} progress=${progressFraction}, shouldNudge=${shouldNudge}.`);

    return { progressFraction, transcriptRead, shouldNudge };
  }
);
