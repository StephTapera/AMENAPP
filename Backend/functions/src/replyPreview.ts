/**
 * replyPreview.ts
 *
 * CONTRACT.md-authoritative implementations of:
 *   onReplyCreate        — marks posts/{postId}.previewDirty = true at dirty thresholds
 *   rebuildReplyPreviews — callable + dirty-flag trigger that runs the resolver ladder
 *                          and writes DynamicReplyPreview docs to the subcollection.
 *
 * Resolver ladder (CONTRACT.md §13), scoring formula (CONTRACT.md §15),
 * and dirty thresholds (CONTRACT.md §16) are implemented verbatim.
 *
 * References:
 *   - Firestore schema:   CONTRACT.md §11
 *   - Cloud fn sigs:      CONTRACT.md §12
 *   - Resolver ladder:    CONTRACT.md §13
 *   - Scoring formula:    CONTRACT.md §15
 *   - Dirty thresholds:   CONTRACT.md §16
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { moderatePreviewText } from "./moderation/previewModerationProvider";
import { rankDynamicReplyCandidate } from "./ranking/dynamicReplyPreviewRanking";
import { logPreviewError, logPreviewEvent } from "./utils/previewLogger";

// ─── Constants ────────────────────────────────────────────────────────────────

/** CONTRACT.md §16 — exact thresholds */
const DIRTY_THRESHOLDS: ReadonlyArray<number> = [5, 12, 30, 75];

/** CONTRACT.md §13 — bereanInsight confidence gate */
const BEREAN_CONFIDENCE_GATE = 0.72;

/** CONTRACT.md §13 — bereanInsight volume gate */
const BEREAN_VOLUME_GATE = 12;

/** CONTRACT.md §13 — communityPulse volume gate */
const PULSE_VOLUME_GATE = 5;

/** Max comments to fetch when building candidates */
const COMMENT_FETCH_LIMIT = 60;

/** Max DynamicReplyPreview docs written per post */
const MAX_PREVIEW_DOCS = 6;

/** TTL for generated previews (30 min) */
const PREVIEW_TTL_MS = 30 * 60 * 1000;

const db = admin.firestore();

// ─── Internal Types ───────────────────────────────────────────────────────────

type ReplyPreviewType =
    | "topReply"
    | "followedReply"
    | "communityPulse"
    | "bereanInsight"
    | "prayerMomentum"
    | "trustedCommunitySignal";

interface RawComment {
    id: string;
    postId: string;
    authorId: string;
    authorDisplayName: string;
    text: string;
    amenCount: number;
    lightbulbCount: number;
    replyCount: number;
    prayerCount: number;
    saveCount: number;
    reportCount: number;
    createdAt: admin.firestore.Timestamp;
    isDeleted?: boolean;
    isHidden?: boolean;
    flaggedForReview?: boolean;
    removed?: boolean;
    moderationStatus?: "visible" | "pending" | "hidden" | "parent_deleted";
    authorProfileImageURL?: string;
}

/** CONTRACT.md §10 ReplyCandidate — input to the resolver */
interface ReplyCandidate {
    id: string;
    postId: string;
    authorUID: string;
    authorDisplayName: string;
    text: string;
    relevanceScore: number;       // 0.0–1.0
    spiritualUsefulness: number;  // 0.0–1.0
    engagementScore: number;      // 0.0–1.0
    createdAt: admin.firestore.Timestamp;
    safetyPassed: boolean;
    authorProfileImageURL?: string;
}

/** Internal Firestore write shape — matches CONTRACT.md §11 field names */
interface DynamicReplyPreviewDoc {
    id: string;
    postId: string;
    replyId: string | null;
    sourceCommentIds: string[];
    type: ReplyPreviewType;
    previewText: string;
    authorId: string | null;
    authorDisplayName: string | null;
    avatarURLs: string[];
    participantUserIds: string[];
    score: number;
    generatedAt: admin.firestore.FieldValue;
    expiresAt: admin.firestore.Timestamp;
    moderationState: "approved";
    source: string | null;
}

interface CommunityPulse {
    previewText: string;
    sourceCommentIds: string[];
    confidence: number;
}

// ─── Scoring formula (CONTRACT.md §15) ───────────────────────────────────────

/**
 * compositeScore = 0.35 × relevanceScore
 *               + 0.25 × spiritualUsefulness
 *               + 0.25 × engagementScore
 *               + 0.15 × recencyScore
 *
 * recencyScore = 1.0 - min(1.0, hoursSinceCreated / 168.0)
 */
function contractCompositeScore(candidate: ReplyCandidate): number {
    const now = Date.now();
    const ageHours = Math.max(0, (now - candidate.createdAt.toMillis()) / (1000 * 60 * 60));
    const recencyScore = 1.0 - Math.min(1.0, ageHours / 168.0);

    return (
        0.35 * candidate.relevanceScore +
        0.25 * candidate.spiritualUsefulness +
        0.25 * candidate.engagementScore +
        0.15 * recencyScore
    );
}

// ─── Safety helpers ───────────────────────────────────────────────────────────

function isSafeRawComment(comment: RawComment): boolean {
    if (comment.isDeleted || comment.isHidden || comment.flaggedForReview || comment.removed) return false;
    if (comment.moderationStatus && comment.moderationStatus !== "visible") return false;
    if (!comment.text || comment.text.trim().length < 3) return false;
    const result = moderatePreviewText({ text: comment.text, commentId: comment.id, source: "replyPreview" });
    return result.passed && result.confidence >= 0.65;
}

function safetyPassedForText(text: string): boolean {
    const result = moderatePreviewText({ text, source: "replyPreview_candidate" });
    return result.passed && result.confidence >= 0.65;
}

// ─── Score sub-components for ReplyCandidate construction ─────────────────────

function clamp01(v: number): number {
    return Math.max(0, Math.min(1, v));
}

function computeRelevanceScore(text: string): number {
    const len = text.trim().length;
    if (len < 8) return 0.15;
    if (len <= 180) return clamp01(len / 120);
    return clamp01(1 - (len - 180) / 300);
}

function computeSpiritualUsefulness(text: string): number {
    const lower = text.toLowerCase();
    let score = 0;
    if (/\bpray|prayer|amen|encourage|standing with\b/.test(lower)) score += 0.4;
    if (/\b(john|psalm|romans|matthew|luke|acts)\b|\d+:\d+/.test(lower)) score += 0.35;
    if (/\bhope|grace|faith|peace|repentance|lament\b/.test(lower)) score += 0.25;
    return clamp01(score);
}

function computeEngagementScore(comment: RawComment): number {
    const positive =
        (comment.amenCount ?? 0) +
        (comment.lightbulbCount ?? 0) +
        (comment.replyCount ?? 0) +
        (comment.prayerCount ?? 0) +
        (comment.saveCount ?? 0);
    const reports = comment.reportCount ?? 0;
    return clamp01((positive - reports * 2) / 20);
}

// ─── RawComment → ReplyCandidate ─────────────────────────────────────────────

function toReplyCandidate(comment: RawComment): ReplyCandidate {
    return {
        id: comment.id,
        postId: comment.postId,
        authorUID: comment.authorId,
        authorDisplayName: comment.authorDisplayName,
        text: comment.text,
        relevanceScore: computeRelevanceScore(comment.text),
        spiritualUsefulness: computeSpiritualUsefulness(comment.text),
        engagementScore: computeEngagementScore(comment),
        createdAt: comment.createdAt,
        safetyPassed: isSafeRawComment(comment),
        authorProfileImageURL: comment.authorProfileImageURL,
    };
}

// ─── Community Pulse detector ─────────────────────────────────────────────────

const SPIRITUAL_THEMES: Array<[RegExp, string]> = [
    [/hope|hopeful/i, "hope"],
    [/grace/i, "grace"],
    [/faith/i, "faith"],
    [/healing|heal/i, "healing"],
    [/prayer|pray/i, "prayer"],
    [/grief|loss|mourning/i, "grief"],
    [/calling|purpose/i, "calling"],
    [/resurrection|risen/i, "resurrection"],
    [/peace/i, "peace"],
    [/surrender/i, "surrender"],
    [/trust|faithful/i, "trust"],
    [/scripture|verse|bible/i, "scripture"],
    [/forgive|forgiveness/i, "forgiveness"],
    [/community|together/i, "community"],
];

function detectCommunityPulseFromCandidates(candidates: ReplyCandidate[]): CommunityPulse | null {
    const themeCounts: Record<string, number> = {};
    const themeSources: Record<string, string[]> = {};

    for (const candidate of candidates) {
        for (const [pattern, label] of SPIRITUAL_THEMES) {
            if (!pattern.test(candidate.text)) continue;
            themeCounts[label] = (themeCounts[label] ?? 0) + 1;
            themeSources[label] = [...(themeSources[label] ?? []), candidate.id];
        }
    }

    const sorted = Object.entries(themeCounts)
        .filter(([, count]) => count >= 2)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 3);

    if (sorted.length === 0) return null;

    const sourceCommentIds = Array.from(
        new Set(sorted.flatMap(([label]) => themeSources[label] ?? []))
    ).slice(0, 3);

    const confidence = Math.min(1, (sorted[0]?.[1] ?? 0) / Math.max(2, candidates.length - 1));

    return {
        previewText: sorted.map(([label]) => label).join(", "),
        sourceCommentIds,
        confidence,
    };
}

// ─── Preview doc builders ─────────────────────────────────────────────────────

function buildSingleReplyDoc(
    postId: string,
    candidate: ReplyCandidate,
    type: "topReply" | "followedReply",
    score: number,
    expiresAt: admin.firestore.Timestamp
): DynamicReplyPreviewDoc {
    const raw = candidate.text.trim();
    const previewText = raw.length > 120 ? `${raw.slice(0, 118).trimEnd()}…` : raw;

    return {
        id: `${postId}-${candidate.id}-${type}`,
        postId,
        replyId: candidate.id,
        sourceCommentIds: [candidate.id],
        type,
        previewText,
        authorId: candidate.authorUID,
        authorDisplayName: candidate.authorDisplayName,
        avatarURLs: candidate.authorProfileImageURL ? [candidate.authorProfileImageURL] : [],
        participantUserIds: [candidate.authorUID],
        score,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
        moderationState: "approved",
        source: type === "followedReply" ? "followed_reply_resolver" : "top_reply_resolver",
    };
}

function buildAggregateDoc(
    postId: string,
    type: ReplyPreviewType,
    previewText: string,
    relatedCandidates: ReplyCandidate[],
    score: number,
    expiresAt: admin.firestore.Timestamp,
    source: string
): DynamicReplyPreviewDoc {
    return {
        id: `${postId}-${type}`,
        postId,
        replyId: null,
        sourceCommentIds: relatedCandidates.map((c) => c.id).slice(0, 3),
        type,
        previewText,
        authorId: null,
        authorDisplayName: null,
        avatarURLs: relatedCandidates
            .map((c) => c.authorProfileImageURL)
            .filter((u): u is string => Boolean(u))
            .slice(0, 3),
        participantUserIds: relatedCandidates.map((c) => c.authorUID).slice(0, 3),
        score,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
        moderationState: "approved",
        source,
    };
}

// ─── Berean insight ───────────────────────────────────────────────────────────

function buildBereanInsightDoc(
    postId: string,
    candidates: ReplyCandidate[],
    expiresAt: admin.firestore.Timestamp
): DynamicReplyPreviewDoc | null {
    if (candidates.length < BEREAN_VOLUME_GATE) return null;

    const pulse = detectCommunityPulseFromCandidates(candidates);
    if (!pulse || pulse.confidence < BEREAN_CONFIDENCE_GATE) return null;

    const previewText = `Berean: replies focus on ${pulse.previewText.replace(/,\s*/g, " + ")}`;
    if (!safetyPassedForText(previewText)) return null;

    const relatedCandidates = candidates
        .filter((c) => pulse.sourceCommentIds.includes(c.id))
        .slice(0, 3);

    return buildAggregateDoc(
        postId,
        "bereanInsight",
        previewText,
        relatedCandidates,
        0.71 + pulse.confidence * 0.1,
        expiresAt,
        "berean_resolver"
    );
}

// ─── Resolver ladder (CONTRACT.md §13) ───────────────────────────────────────

/**
 * Runs the five-step resolver ladder from CONTRACT.md §13.
 * Returns an ordered array of DynamicReplyPreviewDoc ready to write.
 *
 *   Step 1 — followedReply (viewerFollows set required)
 *   Step 2 — bereanInsight (confidence ≥ 0.72 AND replyCount ≥ 12)
 *   Step 3 — communityPulse (replyCount ≥ 5)
 *   Step 4 — topReply (always-available fallback)
 *   Step 5 — no preview
 */
async function runResolverLadder(
    postId: string,
    safeCandidates: ReplyCandidate[],
    viewerFollows: Set<string>,
    expiresAt: admin.firestore.Timestamp
): Promise<DynamicReplyPreviewDoc[]> {
    const results: DynamicReplyPreviewDoc[] = [];

    // Step 1 — followedReply
    const followedCandidates = safeCandidates.filter((c) => viewerFollows.has(c.authorUID));
    if (followedCandidates.length > 0) {
        const best = followedCandidates.reduce((prev, curr) =>
            contractCompositeScore(curr) > contractCompositeScore(prev) ? curr : prev
        );
        const doc = buildSingleReplyDoc(postId, best, "followedReply", contractCompositeScore(best), expiresAt);
        if (safetyPassedForText(doc.previewText)) {
            results.push(doc);
        }
    }

    // Step 2 — bereanInsight
    if (safeCandidates.length >= BEREAN_VOLUME_GATE) {
        const bereanDoc = buildBereanInsightDoc(postId, safeCandidates, expiresAt);
        if (bereanDoc) results.push(bereanDoc);
    }

    // Step 3 — communityPulse
    if (safeCandidates.length >= PULSE_VOLUME_GATE) {
        const last30 = safeCandidates.slice(0, 30);
        const pulse = detectCommunityPulseFromCandidates(last30);
        if (pulse) {
            const previewText = pulse.previewText;
            if (safetyPassedForText(previewText)) {
                const relatedCandidates = last30.filter((c) => pulse.sourceCommentIds.includes(c.id)).slice(0, 3);
                results.push(
                    buildAggregateDoc(
                        postId,
                        "communityPulse",
                        previewText,
                        relatedCandidates,
                        0.65 + pulse.confidence * 0.05,
                        expiresAt,
                        "community_pulse_resolver"
                    )
                );
            }
        }
    }

    // Step 4 — topReply (always-available fallback)
    if (safeCandidates.length > 0) {
        // Exclude any candidate already used in followedReply to avoid duplication
        const followedId = results.find((r) => r.type === "followedReply")?.replyId ?? null;
        const topPool = safeCandidates.filter((c) => c.id !== followedId);
        if (topPool.length > 0) {
            const top = topPool.reduce((prev, curr) =>
                contractCompositeScore(curr) > contractCompositeScore(prev) ? curr : prev
            );
            const doc = buildSingleReplyDoc(postId, top, "topReply", contractCompositeScore(top), expiresAt);
            if (safetyPassedForText(doc.previewText)) {
                results.push(doc);
            }
        }
    }

    // Step 5 — no preview (empty results slice)
    return results.slice(0, MAX_PREVIEW_DOCS);
}

// ─── Follow-graph loader ──────────────────────────────────────────────────────

async function loadViewerFollowsForPost(postId: string): Promise<Set<string>> {
    // For trigger-initiated rebuilds there is no authenticated viewer.
    // We load all follow-relationships for the post author so the shared
    // feed preview (stored on the post doc) can still surface a followedReply
    // for the author's followers. Client-personalised selection happens at
    // read-time via the iOS resolver layer.
    try {
        const postSnap = await db.doc(`posts/${postId}`).get();
        if (!postSnap.exists) return new Set();
        const authorId = postSnap.data()?.authorId as string | undefined;
        if (!authorId) return new Set();

        const followsSnap = await db
            .collection("follows_index")
            .where("followedId", "==", authorId)
            .limit(200)
            .get();

        return new Set(followsSnap.docs.map((d) => d.data().followerId as string).filter(Boolean));
    } catch {
        return new Set();
    }
}

// ─── Core rebuild logic ───────────────────────────────────────────────────────

async function performRebuild(postId: string, reason: string, callerUid?: string): Promise<void> {
    const start = Date.now();
    logPreviewEvent("reply_preview_rebuild_started", { postId, refreshReason: reason, viewerId: callerUid ?? null });

    try {
        const postSnap = await db.doc(`posts/${postId}`).get();
        if (!postSnap.exists) {
            logPreviewEvent("reply_preview_rebuild_skipped", { postId, refreshReason: reason, suppressionReason: "post_not_found" });
            return;
        }

        // Fetch comments — ordered by createdAt desc to get most recent first
        const commentsSnap = await db
            .collection(`posts/${postId}/comments`)
            .orderBy("createdAt", "desc")
            .limit(COMMENT_FETCH_LIMIT)
            .get();

        const rawComments: RawComment[] = commentsSnap.docs.map((doc) => {
            const data = doc.data();
            return {
                id: doc.id,
                postId,
                authorId: String(data.authorId ?? ""),
                authorDisplayName: String(data.authorName ?? data.authorDisplayName ?? ""),
                text: String(data.text ?? data.content ?? ""),
                amenCount: Number(data.amenCount ?? 0),
                lightbulbCount: Number(data.lightbulbCount ?? 0),
                replyCount: Number(data.replyCount ?? 0),
                prayerCount: Number(data.prayerCount ?? 0),
                saveCount: Number(data.saveCount ?? 0),
                reportCount: Number(data.reportCount ?? 0),
                createdAt: data.createdAt as admin.firestore.Timestamp,
                isDeleted: Boolean(data.isDeleted ?? false),
                isHidden: Boolean(data.isHidden ?? false),
                flaggedForReview: Boolean(data.flaggedForReview ?? false),
                removed: Boolean(data.removed ?? false),
                moderationStatus: data.moderationStatus as RawComment["moderationStatus"],
                authorProfileImageURL: typeof data.authorProfileImageURL === "string"
                    ? data.authorProfileImageURL
                    : undefined,
            };
        });

        // Score each comment using the ranking module + contract §15 formula
        const candidates: ReplyCandidate[] = rawComments.map(toReplyCandidate);

        // Use ranking module's full scoring for finer-grained signals
        const rankedCandidates: Array<ReplyCandidate & { rankScore: number }> = candidates.map((c) => {
            const rankResult = rankDynamicReplyCandidate({
                comment: {
                    id: c.id,
                    text: c.text,
                    amenCount: Math.round(c.engagementScore * 20),
                    createdAt: c.createdAt,
                },
                safetyConfidence: c.safetyPassed ? 0.9 : 0,
            });
            return { ...c, rankScore: rankResult.finalScore };
        });

        // Filter to safety-passed candidates only, sorted by composite score desc
        const safeCandidates = rankedCandidates
            .filter((c) => c.safetyPassed)
            .sort((a, b) => contractCompositeScore(b) - contractCompositeScore(a));

        logPreviewEvent("reply_preview_candidates_scored", {
            postId,
            refreshReason: reason,
            candidateCountIn: rawComments.length,
            candidateCountOut: safeCandidates.length,
        });

        // Load follow-graph for resolver ladder step 1
        const viewerFollows = callerUid
            ? await (async () => {
                const followedIds = await db
                    .collection("follows_index")
                    .where("followerId", "==", callerUid)
                    .limit(500)
                    .get()
                    .then((snap) => new Set(snap.docs.map((d) => d.data().followedId as string).filter(Boolean)));
                return followedIds;
            })()
            : await loadViewerFollowsForPost(postId);

        const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + PREVIEW_TTL_MS));

        // Run the resolver ladder (CONTRACT.md §13)
        const previewDocs = await runResolverLadder(postId, safeCandidates, viewerFollows, expiresAt);

        logPreviewEvent("reply_preview_resolver_completed", {
            postId,
            refreshReason: reason,
            candidateCountIn: safeCandidates.length,
            candidateCountOut: previewDocs.length,
        });

        // Batch write — replace subcollection + update post doc
        const batch = db.batch();

        // Write new preview docs
        for (const doc of previewDocs) {
            batch.set(db.doc(`posts/${postId}/dynamicReplyPreviews/${doc.id}`), doc);
        }

        // Delete stale preview docs not in current result set
        const existingSnap = await db.collection(`posts/${postId}/dynamicReplyPreviews`).get();
        const newIds = new Set(previewDocs.map((d) => d.id));
        existingSnap.docs
            .filter((d) => !newIds.has(d.id))
            .forEach((d) => batch.delete(d.ref));

        // Denormalize approved non-viewer-specific previews onto the post doc
        // (CONTRACT.md §11: previewDirty reset + expiresAt update)
        const sharedTypes: ReplyPreviewType[] = ["topReply", "prayerMomentum", "communityPulse", "bereanInsight"];
        const denormalized = previewDocs
            .filter((d) => sharedTypes.includes(d.type))
            .slice(0, 3);

        batch.set(
            db.doc(`posts/${postId}`),
            {
                dynamicReplyPreviewCandidates: denormalized,
                expiresAt,
                previewDirty: false,
                replyCount: rawComments.length,
            },
            { merge: true }
        );

        // Update meta state doc
        batch.set(
            db.doc(`posts/${postId}/dynamicReplyPreviewMeta/state`),
            { lastRefreshedAt: admin.firestore.FieldValue.serverTimestamp(), rebuiltBy: callerUid ?? "trigger" },
            { merge: true }
        );

        await batch.commit();

        logPreviewEvent("reply_preview_rebuild_completed", {
            postId,
            refreshReason: reason,
            viewerId: callerUid ?? null,
            candidateCountIn: rawComments.length,
            candidateCountOut: previewDocs.length,
            latencyMs: Date.now() - start,
        });
    } catch (error) {
        logPreviewError("reply_preview_rebuild_failed", {
            postId,
            refreshReason: reason,
            viewerId: callerUid ?? null,
            latencyMs: Date.now() - start,
            error,
        });
        // Surface to caller when invoked as a callable so the client can retry
        if (callerUid) throw new HttpsError("internal", "Preview rebuild failed. Please retry.");
    }
}

// ─── Dirty-threshold logic (CONTRACT.md §16) ─────────────────────────────────

async function markDirtyIfThresholdCrossed(postId: string, reason: string): Promise<void> {
    const countSnap = await db.collection(`posts/${postId}/comments`).count().get();
    const replyCount = countSnap.data().count;

    // Always denormalize the latest count
    await db.doc(`posts/${postId}`).set({ replyCount }, { merge: true });

    const crossedThreshold = DIRTY_THRESHOLDS.includes(replyCount);
    if (!crossedThreshold) {
        logPreviewEvent("reply_preview_dirty_skip", {
            postId,
            refreshReason: reason,
            candidateCountIn: replyCount,
            suppressionReason: "reply_count_not_at_dirty_threshold",
        });
        return;
    }

    logPreviewEvent("reply_preview_dirty_mark", {
        postId,
        refreshReason: reason,
        candidateCountIn: replyCount,
    });

    // Mark dirty AND enqueue rebuild inline (no Cloud Tasks required at this scale)
    await db.doc(`posts/${postId}`).set({ previewDirty: true }, { merge: true });
    await performRebuild(postId, reason);
}

// ─── Exported Cloud Functions ─────────────────────────────────────────────────

/**
 * onReplyCreate
 *
 * CONTRACT.md §12:
 *   Trigger: Firestore onCreate — posts/{postId}/comments/{commentId}
 *   Action:  Reads new comment count.
 *            If count crosses a dirty threshold in [5, 12, 30, 75]:
 *              Set posts/{postId}.previewDirty = true
 *              Enqueue rebuildReplyPreviews for this postId.
 */
export const onReplyCreate = onDocumentCreated(
    "posts/{postId}/comments/{commentId}",
    async (event) => {
        const { postId } = event.params;
        await markDirtyIfThresholdCrossed(postId, "on_reply_create");
    }
);

/**
 * rebuildReplyPreviews
 *
 * CONTRACT.md §12:
 *   Trigger: Firestore onUpdate (previewDirty: false → true)
 *            OR direct callable invocation
 *   Action:  Fetch top N comments for postId.
 *            Score each as ReplyCandidate using the scoring formula (§15).
 *            Run resolver ladder (§13).
 *            Write approved DynamicReplyPreview docs to subcollection.
 *            Set posts/{postId}.previewDirty = false.
 *
 * As a callable the caller must supply { postId: string }.
 * The dirty-flag trigger variant is exported separately as
 * rebuildReplyPreviewsOnDirty to avoid name collision.
 */
export const rebuildReplyPreviews = onCall(
    { enforceAppCheck: true },
    async (request) => {
        if (request.app == undefined) {
            throw new HttpsError("unauthenticated", "App Check required.");
        }
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        const postId = request.data?.postId as string | undefined;
        if (!postId || typeof postId !== "string" || postId.trim().length === 0) {
            throw new HttpsError("invalid-argument", "postId is required.");
        }

        await performRebuild(postId.trim(), "callable_rebuild", request.auth.uid);
        return { success: true, postId: postId.trim() };
    }
);

/**
 * rebuildReplyPreviewsOnDirty
 *
 * Firestore trigger half of CONTRACT.md §12 rebuildReplyPreviews:
 *   Fires when posts/{postId}.previewDirty transitions false → true.
 *   Guards against spurious triggers by checking both before and after values.
 */
export const rebuildReplyPreviewsOnDirty = onDocumentUpdated(
    "posts/{postId}",
    async (event) => {
        const before = event.data?.before?.data() ?? {};
        const after = event.data?.after?.data() ?? {};

        // Only rebuild when previewDirty transitions to true
        if (before.previewDirty === true || after.previewDirty !== true) return;

        await performRebuild(event.params.postId, "dirty_flag_rebuild");
    }
);
