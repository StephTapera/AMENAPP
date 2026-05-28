/**
 * generateDynamicReplyPreviews.ts
 *
 * Server-owned generation of inline reply preview candidates for PostCard.
 *
 * Clients only rotate between server-approved candidates and never generate
 * preview text locally.
 */

import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

const db = admin.firestore();

const MIN_REFRESH_INTERVAL_MS = 10 * 60 * 1000;
const MAX_CANDIDATES = 6;
const COMMENT_FETCH_LIMIT = 50;
const ACTIVE_POST_AGE_HOURS = 72;

const W = {
    relevance: 0.30,
    engagementQuality: 0.20,
    authorAffinity: 0.20,
    safetyScore: 0.15,
    recency: 0.10,
    spiritualUsefulness: 0.05,
};

const PREVIEW_TEXT_BLOCKLIST = [
    /https?:\/\//i,
    /\bkill yourself\b/i,
    /\bsuicide\b/i,
    /\bporn\b/i,
    /\bsexual\b/i,
    /\bviolent\b/i,
];

const SHARED_FEED_PREVIEW_TYPES: PreviewKind[] = [
    "topReply",
    "prayerMomentum",
    "communityPulse",
    "bereanInsight",
];

type PreviewKind =
    | "topReply"
    | "followedReply"
    | "communityPulse"
    | "bereanInsight"
    | "prayerMomentum"
    | "trustedCommunitySignal";

interface PreviewCandidate {
    id: string;
    postId: string;
    replyId: string | null;
    sourceCommentIds: string[];
    type: PreviewKind;
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

interface Comment {
    id: string;
    authorId: string;
    authorName: string;
    authorProfileImageURL?: string;
    text: string;
    amenCount?: number;
    lightbulbCount?: number;
    createdAt: admin.firestore.Timestamp;
    isDeleted?: boolean;
    isHidden?: boolean;
    flaggedForReview?: boolean;
    removed?: boolean;
}

interface ViewerProfile {
    uid: string;
    churchId: string | null;
    communityId: string | null;
}

interface RelationshipContext {
    followsAuthor: boolean;
    mutualTopicCount: number;
}

interface CommunityMatchCounts {
    visibleChurchCount: number;
    visibleCommunityCount: number;
}

interface CommunityPulseResult {
    previewText: string;
    sourceCommentIds: string[];
    confidence: number;
}

export const onCommentCreatedUpdatePreviews = onDocumentCreated(
    "posts/{postId}/comments/{commentId}",
    async (event) => {
        await maybeRefreshPreviews(event.params.postId, "comment_created");
    }
);

export const onCommentDeletedUpdatePreviews = onDocumentDeleted(
    "posts/{postId}/comments/{commentId}",
    async (event) => {
        await generateAndWritePreviews(event.params.postId, "comment_deleted");
    }
);

export const onUserProfileImageUpdatedRefreshPreviews = onDocumentUpdated(
    "users/{userId}",
    async (event) => {
        const before = event.data?.before?.data();
        const after = event.data?.after?.data();
        const beforeURL = typeof before?.profileImageURL === "string" ? before.profileImageURL : null;
        const afterURL = typeof after?.profileImageURL === "string" ? after.profileImageURL : null;

        if (!shouldRefreshPreviewAvatars(beforeURL, afterURL)) return;

        const commentsSnap = await db
            .collectionGroup("comments")
            .where("authorId", "==", event.params.userId)
            .orderBy("createdAt", "desc")
            .limit(25)
            .get();

        const postIds = Array.from(new Set(
            commentsSnap.docs
                .map((doc) => doc.ref.parent.parent?.id ?? null)
                .filter((value): value is string => Boolean(value))
        ));

        await Promise.allSettled(postIds.map((postId) => generateAndWritePreviews(postId, "profile_image_updated")));
    }
);

export const refreshDynamicReplyPreviews = onCall(async (request) => {
    if (request.app == undefined) {
        throw new HttpsError("unauthenticated", "App Check required.");
    }
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const postId = request.data?.postId as string | undefined;
    if (!postId || typeof postId !== "string") {
        throw new HttpsError("invalid-argument", "postId is required.");
    }

    await maybeRefreshPreviews(postId, "callable_refresh", request.auth.uid);
    return { success: true };
});

// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const scheduledReplyPreviewRefresh = onSchedule("every 30 minutes", async () => {
    // Idempotency: lock by 30-minute window
    const nowMs = Date.now();
    const windowMs = 30 * 60 * 1000;
    const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
    const lockRef = db.doc(`system/scheduledJobLocks/replyPreviewRefresh_${windowKey}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
        const snap = await tx.get(lockRef);
        if (snap.exists && snap.data()?.status === "completed") {
            return false;
        }
        tx.set(lockRef, {
            status: "running",
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            windowKey,
            expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
        });
        return true;
    });

    if (!lockAcquired) {
        logger.info("scheduledReplyPreviewRefresh already completed this window, skipping", { windowKey });
        return;
    }

    try {
        const cutoff = admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - ACTIVE_POST_AGE_HOURS * 60 * 60 * 1000)
        );

        const snapshot = await db
            .collection("posts")
            .where("updatedAt", ">=", cutoff)
            .orderBy("updatedAt", "desc")
            .limit(100)
            .get();

        await Promise.allSettled(
            snapshot.docs.map((doc) => maybeRefreshPreviews(doc.id, "scheduled_refresh"))
        );
        logger.info("scheduledReplyPreviewRefresh complete", { postCount: snapshot.size });

        await lockRef.update({
            status: "completed",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (err) {
        await lockRef.update({
            status: "failed",
            error: String(err),
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        throw err;
    }
});

async function maybeRefreshPreviews(postId: string, reason: string, viewerId?: string): Promise<void> {
    const metaRef = db.doc(`posts/${postId}/dynamicReplyPreviewMeta/state`);
    const meta = await metaRef.get();

    if (meta.exists) {
        const lastRefreshed = meta.data()?.lastRefreshedAt as admin.firestore.Timestamp | undefined;
        if (lastRefreshed) {
            const ageMs = Date.now() - lastRefreshed.toMillis();
            if (ageMs < MIN_REFRESH_INTERVAL_MS && reason !== "comment_deleted") {
                logger.info("preview_write_suppressed", { postId, reason, ageMs });
                return;
            }
        }
    }

    await generateAndWritePreviews(postId, reason, viewerId);
}

async function generateAndWritePreviews(postId: string, reason: string, viewerId?: string): Promise<void> {
    const start = Date.now();

    try {
        const postDoc = await db.doc(`posts/${postId}`).get();
        if (!postDoc.exists) return;
        const post = postDoc.data() ?? {};

        const commentsSnap = await db
            .collection(`posts/${postId}/comments`)
            .orderBy("createdAt", "desc")
            .limit(COMMENT_FETCH_LIMIT)
            .get();

        const comments: Comment[] = commentsSnap.docs.map((doc) => ({
            id: doc.id,
            ...(doc.data() as Omit<Comment, "id">),
        }));

        const safeComments = comments.filter(isSafeComment);
        const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 60 * 1000));
        const candidates: PreviewCandidate[] = [];

        const topComment = topRankedComment(safeComments);
        if (topComment) {
            candidates.push(buildReplyCandidate(postId, topComment, "topReply", expiresAt));
        }

        if (post.category === "prayer" || post.linkedPrayerRequestId) {
            const prayerComments = safeComments.filter(isPrayerComment);
            if (prayerComments.length >= 2) {
                candidates.push(buildAggregateCandidate(
                    postId,
                    "prayerMomentum",
                    `${prayerComments.length} people are praying with this`,
                    prayerComments.slice(0, 3),
                    0.78,
                    expiresAt,
                    "prayer_count"
                ));
            }
        }

        if (safeComments.length >= 3) {
            const pulse = detectCommunityPulse(safeComments);
            if (pulse) {
                candidates.push(buildAggregateCandidate(
                    postId,
                    "communityPulse",
                    pulse.previewText,
                    safeComments.filter((comment) => pulse.sourceCommentIds.includes(comment.id)).slice(0, 3),
                    0.65 + pulse.confidence * 0.05,
                    expiresAt,
                    "community_pulse"
                ));
            }
        }

        const commenterProfiles = await loadCommenterProfiles(safeComments);
        if (viewerId) {
            const followedReply = await selectFollowedReplyCandidate(viewerId, safeComments, commenterProfiles, topComment?.id ?? null);
            if (followedReply) {
                candidates.push(buildReplyCandidate(postId, followedReply, "followedReply", expiresAt));
            }

            const viewerProfile = await loadViewerProfile(viewerId);
            if (viewerProfile) {
                const trustedSignal = buildTrustedCommunitySignalCandidate(postId, safeComments, commenterProfiles, viewerProfile, expiresAt);
                if (trustedSignal) {
                    candidates.push(trustedSignal);
                }
            }
        }

        const bereanInsight = generateBereanInsightCandidate(postId, safeComments, expiresAt);
        if (bereanInsight) {
            candidates.push(bereanInsight);
        }

        const finalCandidates = candidates
            .filter((candidate) => passesPreviewModeration(candidate.previewText))
            .sort((a, b) => b.score - a.score)
            .slice(0, MAX_CANDIDATES);

        const denormalizedCandidates = denormalizePreviewCandidates(finalCandidates);
        const batch = db.batch();

        for (const candidate of finalCandidates) {
            batch.set(db.doc(`posts/${postId}/dynamicReplyPreviews/${candidate.id}`), candidate);
        }

        const existingSnap = await db.collection(`posts/${postId}/dynamicReplyPreviews`).get();
        const newIds = new Set(finalCandidates.map((candidate) => candidate.id));
        existingSnap.docs
            .filter((doc) => !newIds.has(doc.id))
            .forEach((doc) => batch.delete(doc.ref));

        batch.set(db.doc(`posts/${postId}`), {
            dynamicReplyPreviewCandidates: denormalizedCandidates,
        }, { merge: true });

        batch.set(
            db.doc(`posts/${postId}/dynamicReplyPreviewMeta/state`),
            { lastRefreshedAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
        );

        await batch.commit();

        logger.info("preview_candidates_generated", {
            postId,
            reason,
            viewerId: viewerId ?? null,
            candidateCount: finalCandidates.length,
            denormalizedCount: denormalizedCandidates.length,
            latencyMs: Date.now() - start,
        });
    } catch (err) {
        logger.error("preview_generation_error", { postId, reason, err });
    }
}

function isSafeComment(comment: Comment): boolean {
    if (comment.isDeleted) return false;
    if (comment.isHidden) return false;
    if (comment.flaggedForReview) return false;
    if (comment.removed) return false;
    if (!comment.text || comment.text.trim().length < 3) return false;
    return true;
}

function isPrayerComment(comment: Comment): boolean {
    return /praying|prayer|pray|amen|intercede|lifting|standing with/i.test(comment.text);
}

function rankComment(comment: Comment): number {
    const now = Date.now();
    const ageMs = now - (comment.createdAt?.toMillis?.() ?? now);
    const ageDays = ageMs / (1000 * 60 * 60 * 24);
    const engagementQuality = Math.min(((comment.amenCount ?? 0) + (comment.lightbulbCount ?? 0)) / 20, 1);
    const recency = Math.max(0, 1 - ageDays / 7);
    const textLength = Math.min(comment.text.length / 120, 1);
    const hasScripture = /\d:\d|\bRomans|John|Psalm|Matthew|Luke|Acts|Phil/i.test(comment.text) ? 1 : 0;

    return (
        W.relevance * textLength +
        W.engagementQuality * engagementQuality +
        W.authorAffinity * 0.5 +
        W.safetyScore * 1.0 +
        W.recency * recency +
        W.spiritualUsefulness * hasScripture
    );
}

function topRankedComment(comments: Comment[]): Comment | null {
    if (comments.length === 0) return null;
    return comments.reduce((best, comment) => rankComment(comment) > rankComment(best) ? comment : best);
}

const SPIRITUAL_THEMES: [RegExp, string][] = [
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

export function detectCommunityPulse(comments: Comment[]): CommunityPulseResult | null {
    const themeCounts: Record<string, number> = {};
    const themeSources: Record<string, string[]> = {};

    for (const comment of comments) {
        for (const [pattern, label] of SPIRITUAL_THEMES) {
            if (!pattern.test(comment.text)) continue;
            themeCounts[label] = (themeCounts[label] ?? 0) + 1;
            themeSources[label] = [...(themeSources[label] ?? []), comment.id];
        }
    }

    const sorted = Object.entries(themeCounts)
        .filter(([, count]) => count >= 2)
        .sort((lhs, rhs) => rhs[1] - lhs[1])
        .slice(0, 3);

    if (sorted.length === 0) return null;

    const sourceCommentIds = Array.from(new Set(
        sorted.flatMap(([label]) => themeSources[label] ?? [])
    )).slice(0, 3);

    return {
        previewText: sorted.map(([label]) => label).join(", "),
        sourceCommentIds,
        confidence: Math.min(1, (sorted[0]?.[1] ?? 0) / Math.max(2, comments.length - 1)),
    };
}

async function loadViewerProfile(viewerId: string): Promise<ViewerProfile | null> {
    const viewerSnap = await db.collection("users").doc(viewerId).get();
    if (!viewerSnap.exists) return null;
    const data = viewerSnap.data() ?? {};
    return {
        uid: viewerId,
        churchId: typeof data.churchId === "string" ? data.churchId : null,
        communityId: typeof data.communityId === "string" ? data.communityId : null,
    };
}

async function loadCommenterProfiles(comments: Comment[]): Promise<Map<string, FirebaseFirestore.DocumentData>> {
    const authorIds = Array.from(new Set(comments.map((comment) => comment.authorId))).slice(0, 20);
    const snapshots = await Promise.all(authorIds.map((authorId) => db.collection("users").doc(authorId).get()));
    return new Map(snapshots.filter((doc) => doc.exists).map((doc) => [doc.id, doc.data() ?? {}]));
}

async function loadRelationshipContext(viewerId: string, authorId: string): Promise<RelationshipContext> {
    const [followSnap, relationshipSnap] = await Promise.all([
        db.collection("follows_index").doc(`${viewerId}_${authorId}`).get(),
        db.collection("relationship_activity_state").doc(`${viewerId}_${authorId}`).get(),
    ]);

    const relationshipData = relationshipSnap.data() ?? {};
    const mutualTopics = Array.isArray(relationshipData.mutualTopics)
        ? relationshipData.mutualTopics.filter((value): value is string => typeof value === "string")
        : [];

    return {
        followsAuthor: followSnap.exists,
        mutualTopicCount: mutualTopics.length,
    };
}

export async function selectFollowedReplyCandidate(
    viewerId: string,
    comments: Comment[],
    commenterProfiles: Map<string, FirebaseFirestore.DocumentData>,
    excludedCommentId: string | null = null
): Promise<Comment | null> {
    const ranked = [...comments].sort((lhs, rhs) => rankComment(rhs) - rankComment(lhs));
    let best: { comment: Comment; score: number } | null = null;

    for (const comment of ranked) {
        if (comment.id === excludedCommentId) continue;
        const relationship = await loadRelationshipContext(viewerId, comment.authorId);
        const affinity = relationship.followsAuthor ? 1 : relationship.mutualTopicCount >= 2 ? 0.72 : 0;
        if (affinity <= 0) continue;

        const profile = commenterProfiles.get(comment.authorId);
        if (!comment.authorProfileImageURL && typeof profile?.profileImageURL === "string") {
            comment.authorProfileImageURL = profile.profileImageURL;
        }

        const score = rankComment(comment) + affinity;
        if (!best || score > best.score) {
            best = { comment, score };
        }
    }

    return best?.comment ?? null;
}

function buildTrustedCommunitySignalCandidate(
    postId: string,
    comments: Comment[],
    commenterProfiles: Map<string, FirebaseFirestore.DocumentData>,
    viewerProfile: ViewerProfile,
    expiresAt: admin.firestore.Timestamp
): PreviewCandidate | null {
    const counts = countVisibleCommunityMatches(comments, commenterProfiles, viewerProfile);

    if (counts.visibleCommunityCount >= 2 && viewerProfile.communityId) {
        const related = comments
            .filter((comment) => commenterProfiles.get(comment.authorId)?.communityId === viewerProfile.communityId)
            .slice(0, 3);
        return buildAggregateCandidate(
            postId,
            "trustedCommunitySignal",
            `${counts.visibleCommunityCount} people in your community replied`,
            related,
            0.73,
            expiresAt,
            "visible_community_graph"
        );
    }

    if (counts.visibleChurchCount >= 2 && viewerProfile.churchId) {
        const related = comments
            .filter((comment) => commenterProfiles.get(comment.authorId)?.churchId === viewerProfile.churchId)
            .slice(0, 3);
        return buildAggregateCandidate(
            postId,
            "trustedCommunitySignal",
            `${counts.visibleChurchCount} people from your church replied`,
            related,
            0.75,
            expiresAt,
            "visible_church_graph"
        );
    }

    return null;
}

export function countVisibleCommunityMatches(
    comments: Comment[],
    commenterProfiles: Map<string, FirebaseFirestore.DocumentData>,
    viewerProfile: ViewerProfile
): CommunityMatchCounts {
    let visibleChurchCount = 0;
    let visibleCommunityCount = 0;
    const seenChurch = new Set<string>();
    const seenCommunity = new Set<string>();

    for (const comment of comments) {
        const profile = commenterProfiles.get(comment.authorId);
        if (!profile) continue;

        if (
            viewerProfile.churchId &&
            profile.churchId === viewerProfile.churchId &&
            isMembershipVisible(profile, "church") &&
            !seenChurch.has(comment.authorId)
        ) {
            visibleChurchCount += 1;
            seenChurch.add(comment.authorId);
        }

        if (
            viewerProfile.communityId &&
            profile.communityId === viewerProfile.communityId &&
            isMembershipVisible(profile, "community") &&
            !seenCommunity.has(comment.authorId)
        ) {
            visibleCommunityCount += 1;
            seenCommunity.add(comment.authorId);
        }
    }

    return { visibleChurchCount, visibleCommunityCount };
}

function isMembershipVisible(profile: FirebaseFirestore.DocumentData, scope: "church" | "community"): boolean {
    const shareKey = scope === "church" ? "shareChurchMembership" : "shareCommunityMembership";
    const visibilityKey = scope === "church" ? "churchVisibility" : "communityVisibility";

    if (profile[shareKey] === false) return false;
    if (profile[shareKey] === true) return true;
    return profile[visibilityKey] === "public" || profile[visibilityKey] === "followers";
}

export function generateBereanInsightCandidate(
    postId: string,
    comments: Comment[],
    expiresAt: admin.firestore.Timestamp
): PreviewCandidate | null {
    if (comments.length < 4) return null;

    const pulse = detectCommunityPulse(comments);
    if (!pulse || pulse.confidence < 0.68) return null;

    const previewText = `Berean: replies focus on ${pulse.previewText.replace(/,\s*/g, " + ")}`;
    if (!passesPreviewModeration(previewText)) return null;

    const related = comments.filter((comment) => pulse.sourceCommentIds.includes(comment.id)).slice(0, 3);
    return buildAggregateCandidate(
        postId,
        "bereanInsight",
        previewText,
        related,
        0.71 + pulse.confidence * 0.1,
        expiresAt,
        "berean_safe_summary"
    );
}

export function passesPreviewModeration(text: string): boolean {
    const normalized = text.trim();
    if (normalized.length < 4 || normalized.length > 120) return false;
    return PREVIEW_TEXT_BLOCKLIST.every((pattern) => !pattern.test(normalized));
}

export function denormalizePreviewCandidates(candidates: PreviewCandidate[]): PreviewCandidate[] {
    return candidates
        .filter((candidate) => candidate.moderationState === "approved")
        .filter((candidate) => SHARED_FEED_PREVIEW_TYPES.includes(candidate.type))
        .slice(0, 3);
}

export function shouldRefreshPreviewAvatars(beforeURL: string | null, afterURL: string | null): boolean {
    return Boolean(afterURL && beforeURL !== afterURL);
}

function buildAggregateCandidate(
    postId: string,
    type: PreviewKind,
    previewText: string,
    relatedComments: Comment[],
    score: number,
    expiresAt: admin.firestore.Timestamp,
    source: string
): PreviewCandidate {
    return {
        id: `${postId}-${type}`,
        postId,
        replyId: null,
        sourceCommentIds: relatedComments.map((comment) => comment.id).slice(0, 3),
        type,
        previewText,
        authorId: null,
        authorDisplayName: null,
        avatarURLs: relatedComments
            .map((comment) => comment.authorProfileImageURL)
            .filter((value): value is string => Boolean(value))
            .slice(0, 3),
        participantUserIds: relatedComments.map((comment) => comment.authorId).slice(0, 3),
        score,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
        moderationState: "approved",
        source,
    };
}

function buildReplyCandidate(
    postId: string,
    comment: Comment,
    type: "topReply" | "followedReply",
    expiresAt: admin.firestore.Timestamp
): PreviewCandidate {
    const previewText = comment.text.length > 72
        ? `${comment.text.slice(0, 70).trimEnd()}…`
        : comment.text;

    return {
        id: `${postId}-${comment.id}-${type}`,
        postId,
        replyId: comment.id,
        sourceCommentIds: [comment.id],
        type,
        previewText,
        authorId: comment.authorId,
        authorDisplayName: comment.authorName,
        avatarURLs: comment.authorProfileImageURL ? [comment.authorProfileImageURL] : [],
        participantUserIds: [comment.authorId],
        score: rankComment(comment),
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
        moderationState: "approved",
        source: "comment",
    };
}
