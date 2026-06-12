/**
 * feedRanking.ts
 * AMEN — Global Resilience: Constitutional Feed Ranking
 *
 * Firebase Gen-2 callable Cloud Functions (region: us-central1):
 *
 *   rankFeedPosts          — Score and rank candidate posts for a user's feed
 *                            using constitutional signals. Hard-rules guarantee
 *                            safety and trust outrank engagement. Stores ranking
 *                            events for auditability.
 *
 *   getRankingExplanation  — Return human-readable reasons for why a specific
 *                            post was ranked the way it was, using the most
 *                            recent stored ranking event.
 *
 * Firestore layout:
 *   /posts/{postId}                              — Post document
 *   /trustProfiles/{userId}                      — TrustProfile document
 *   /follows/{followerId}__{followedId}          — Follow edge document
 *   /posts/{postId}/rankingEvents/{newId}        — Immutable ranking audit events
 *
 * Constitutional invariants enforced:
 *   1. safetyScore == 0.0 → always ranked last (hard rule, not just weight).
 *   2. Engagement weight (0.05) can never exceed the combined weight of
 *      safety (0.20) + trust (0.20) + relationship (0.25) = 0.65.
 *   3. Virality risk deducted at −0.20 to penalise unvetted viral spread.
 *   4. contextFrictionRequired flag surfaced to the client for UX enforcement.
 *
 * Auth: every callable requires a valid Firebase Auth token (uid in request.auth).
 * App Check: enforced via { enforceAppCheck: true }.
 */

import * as admin from "firebase-admin";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface FeedRankingSignals {
    relationshipScore: number;
    trustScore: number;
    safetyScore: number;
    spiritualUsefulnessScore: number;
    contextCompletenessScore: number;
    freshnessScore: number;
    engagementScore: number;
    viralityRiskScore: number;
}

interface RankedPost {
    postId: string;
    score: number;
    signals: FeedRankingSignals;
    contextFrictionRequired: boolean;
    sourceNeededPrompt?: string;
}

interface RankingEvent {
    userId: string;
    signals: FeedRankingSignals;
    score: number;
    rankedAt: FirebaseFirestore.FieldValue;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Exponential decay with a 24-hour half-life.
 * freshnessScore = 2^(−ageInHours / 24)  → 1.0 when brand-new, ~0.5 at 24 h.
 */
function computeFreshnessScore(createdAtMs: number): number {
    const ageInHours = (Date.now() - createdAtMs) / (1000 * 60 * 60);
    return Math.pow(2, -ageInHours / 24);
}

/**
 * Resolve a Firestore Timestamp, JS Date, or epoch-millis number to
 * milliseconds since epoch.  Returns Date.now() as a safe fallback.
 */
function toMs(value: unknown): number {
    if (!value) return Date.now();
    if (typeof value === "number") return value;
    // Firestore Timestamp
    if (
        typeof value === "object" &&
        value !== null &&
        "toMillis" in value &&
        typeof (value as { toMillis: unknown }).toMillis === "function"
    ) {
        return (value as { toMillis: () => number }).toMillis();
    }
    // JS Date or date-like
    const d = new Date(value as string | number | Date);
    return isNaN(d.getTime()) ? Date.now() : d.getTime();
}

/**
 * Build constitutional FeedRankingSignals for one post.
 *
 * @param userId       - The requesting user's UID
 * @param postSnap     - Firestore DocumentSnapshot for /posts/{postId}
 * @param trustSnap    - Firestore DocumentSnapshot for /trustProfiles/{authorId}
 * @param followsUser  - true if userId follows post.authorId
 * @param mutualFriend - true if authorId and userId share a mutual connection
 */
function computeSignals(
    _userId: string,
    postData: FirebaseFirestore.DocumentData,
    trustData: FirebaseFirestore.DocumentData | undefined,
    followsUser: boolean,
    mutualFriend: boolean
): FeedRankingSignals {
    // --- Relationship ---
    let relationshipScore: number;
    if (followsUser) {
        relationshipScore = 1.0;
    } else if (mutualFriend) {
        relationshipScore = 0.6;
    } else {
        relationshipScore = 0.3;
    }

    // --- Trust ---
    const trustScore: number =
        typeof trustData?.communityTrustScore === "number"
            ? trustData.communityTrustScore
            : 0.5;

    // --- Safety ---
    const moderationStatus: string = postData.moderationStatus ?? "unknown";
    let safetyScore: number;
    if (moderationStatus === "approved") {
        safetyScore = 1.0;
    } else if (moderationStatus === "caution") {
        safetyScore = 0.5;
    } else if (moderationStatus === "quarantined") {
        safetyScore = 0.0;
    } else {
        // Unknown status treated conservatively as caution
        safetyScore = 0.5;
    }

    // --- Spiritual usefulness ---
    const tags: string[] = Array.isArray(postData.tags) ? postData.tags : [];
    const spiritualTags = ["scripture", "prayer", "devotional"];
    const spiritualUsefulnessScore = tags.some((t) =>
        spiritualTags.includes(t.toLowerCase())
    )
        ? 0.8
        : 0.3;

    // --- Context completeness ---
    const hasCaption =
        typeof postData.caption === "string" && postData.caption.trim().length > 0;
    const hasSourceUrl =
        typeof postData.sourceUrl === "string" && postData.sourceUrl.trim().length > 0;
    const hasScriptureRef =
        typeof postData.scriptureRef === "string" &&
        postData.scriptureRef.trim().length > 0;
    const authorVerified = postData.authorVerified === true;
    const contextCompletenessScore =
        hasCaption && (hasSourceUrl || hasScriptureRef || authorVerified) ? 0.9 : 0.4;

    // --- Freshness ---
    const createdAtMs = toMs(postData.createdAt);
    const freshnessScore = computeFreshnessScore(createdAtMs);

    // --- Engagement (capped contribution) ---
    const likeCount: number =
        typeof postData.likeCount === "number" ? postData.likeCount : 0;
    const engagementScore = Math.min(likeCount / 1000, 1.0);

    // --- Virality risk ---
    const reshareCount: number =
        typeof postData.reshareCount === "number" ? postData.reshareCount : 0;
    const reshareVelocity: number =
        typeof postData.reshareVelocity === "number" ? postData.reshareVelocity : 0;
    const viralityRiskScore =
        reshareCount > 500 && reshareVelocity > 50 ? 0.9 : 0.1;

    return {
        relationshipScore,
        trustScore,
        safetyScore,
        spiritualUsefulnessScore,
        contextCompletenessScore,
        freshnessScore,
        engagementScore,
        viralityRiskScore,
    };
}

/**
 * Apply the constitutional weighted formula.
 *
 * Weights (must sum to 1.00 before the virality deduction which brings the
 * effective maximum below 1.0 for viral posts):
 *   0.25  relationship   — relational relevance
 *   0.20  trust          — community trust score
 *   0.20  safety         — moderation status
 *   0.15  spiritual      — scripture / devotional / prayer
 *   0.10  context        — completeness / sourcing
 *   0.05  freshness      — recency decay
 *   0.05  engagement     — likes (capped)
 *  −0.20  virality risk  — deduction for unvetted viral spread
 */
function computeScore(s: FeedRankingSignals): number {
    const raw =
        0.25 * s.relationshipScore +
        0.20 * s.trustScore +
        0.20 * s.safetyScore +
        0.15 * s.spiritualUsefulnessScore +
        0.10 * s.contextCompletenessScore +
        0.05 * s.freshnessScore +
        0.05 * s.engagementScore -
        0.20 * s.viralityRiskScore;

    return Math.max(raw, 0);
}

// ---------------------------------------------------------------------------
// 1. rankFeedPosts
// ---------------------------------------------------------------------------

export const rankFeedPosts = onCall(
    {
        region: "us-central1",
        enforceAppCheck: true,
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Authentication required to rank feed posts."
            );
        }

        const data = request.data as {
            userId?: unknown;
            candidatePostIds?: unknown;
        };

        const userId =
            typeof data.userId === "string" ? data.userId : request.auth.uid;

        if (
            !Array.isArray(data.candidatePostIds) ||
            data.candidatePostIds.length === 0
        ) {
            throw new HttpsError(
                "invalid-argument",
                "candidatePostIds must be a non-empty array of strings."
            );
        }

        const candidatePostIds = data.candidatePostIds as string[];

        if (candidatePostIds.length > 200) {
            throw new HttpsError(
                "invalid-argument",
                "candidatePostIds may contain at most 200 entries per call."
            );
        }

        const db = getFirestore();

        // Batch-fetch all post documents
        const postRefs = candidatePostIds.map((id) =>
            db.collection("posts").doc(id)
        );
        const postSnaps = await db.getAll(...postRefs);

        // Collect unique author IDs to batch-fetch trust profiles
        const authorIds = new Set<string>();
        for (const snap of postSnaps) {
            if (snap.exists) {
                const d = snap.data()!;
                if (typeof d.authorId === "string") authorIds.add(d.authorId);
            }
        }

        // Batch-fetch trust profiles
        const trustProfileMap = new Map<
            string,
            FirebaseFirestore.DocumentData | undefined
        >();
        if (authorIds.size > 0) {
            const trustRefs = Array.from(authorIds).map((aid) =>
                db.collection("trustProfiles").doc(aid)
            );
            const trustSnaps = await db.getAll(...trustRefs);
            for (const snap of trustSnaps) {
                trustProfileMap.set(snap.id, snap.exists ? snap.data() : undefined);
            }
        }

        // Determine which authors the requesting user follows
        // Follow document IDs use the pattern: {followerId}__{followedId}
        const followChecks = Array.from(authorIds).map(async (authorId) => {
            const followId = `${userId}__${authorId}`;
            const followSnap = await db
                .collection("follows")
                .doc(followId)
                .get();
            return { authorId, follows: followSnap.exists };
        });
        const followResults = await Promise.all(followChecks);
        const followedAuthorIds = new Set<string>(
            followResults.filter((r) => r.follows).map((r) => r.authorId)
        );

        // Build a map of postId → ranked result
        const ranked: RankedPost[] = [];
        const quarantinedPosts: RankedPost[] = [];

        for (const snap of postSnaps) {
            if (!snap.exists) {
                logger.warn(`rankFeedPosts: post ${snap.id} not found, skipping`);
                continue;
            }

            const postData = snap.data()!;
            const authorId: string = postData.authorId ?? "";
            const trustData = trustProfileMap.get(authorId);

            const followsUser = followedAuthorIds.has(authorId);
            // Mutual friend resolution: for simplicity, check if the author follows the user back
            // A full mutual-friend graph lookup is deferred to a dedicated relationship service
            // to avoid N+1 read explosion. We default to false unless a mutualFriends field
            // is present on the post or trust profile (set by an upstream relationship CF).
            const mutualFriend = trustData?.mutualConnectionWith === userId;

            const signals = computeSignals(
                userId,
                postData,
                trustData,
                followsUser,
                mutualFriend
            );

            const score = computeScore(signals);

            // Constitutional flags
            const contextFrictionRequired =
                signals.viralityRiskScore > 0.8 || signals.safetyScore < 0.6;

            const sourceNeededPrompt: string | undefined =
                postData.hasUnsourcedClaim === true ? "Source needed" : undefined;

            const result: RankedPost = {
                postId: snap.id,
                score,
                signals,
                contextFrictionRequired,
                ...(sourceNeededPrompt ? { sourceNeededPrompt } : {}),
            };

            // HARD RULE: quarantined posts always rank last
            if (signals.safetyScore === 0.0) {
                quarantinedPosts.push(result);
            } else {
                ranked.push(result);
            }

            // Store ranking event for audit trail
            const rankingEvent: RankingEvent = {
                userId,
                signals,
                score,
                rankedAt: FieldValue.serverTimestamp(),
            };

            try {
                await db
                    .collection("posts")
                    .doc(snap.id)
                    .collection("rankingEvents")
                    .add(rankingEvent);
            } catch (err) {
                // Non-fatal: audit write failure should not block feed delivery
                logger.error(
                    `rankFeedPosts: failed to write rankingEvent for post ${snap.id}`,
                    err
                );
            }
        }

        // Sort non-quarantined posts descending by score
        ranked.sort((a, b) => b.score - a.score);

        // Quarantined posts appended at the end (HARD RULE)
        const finalRanking = [...ranked, ...quarantinedPosts];

        logger.info(
            `rankFeedPosts: ranked ${finalRanking.length} posts for user ${userId} ` +
            `(${quarantinedPosts.length} quarantined)`
        );

        return finalRanking;
    }
);

// ---------------------------------------------------------------------------
// 2. getRankingExplanation
// ---------------------------------------------------------------------------

export const getRankingExplanation = onCall(
    {
        region: "us-central1",
        enforceAppCheck: true,
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Authentication required to retrieve ranking explanation."
            );
        }

        const data = request.data as {
            userId?: unknown;
            postId?: unknown;
        };

        const userId =
            typeof data.userId === "string" ? data.userId : request.auth.uid;

        if (typeof data.postId !== "string" || data.postId.trim().length === 0) {
            throw new HttpsError("invalid-argument", "postId must be a non-empty string.");
        }

        const postId = data.postId.trim();
        const db = getFirestore();

        // Fetch the most recent ranking event for this user + post
        const eventsSnap = await db
            .collection("posts")
            .doc(postId)
            .collection("rankingEvents")
            .where("userId", "==", userId)
            .orderBy("rankedAt", "desc")
            .limit(1)
            .get();

        if (eventsSnap.empty) {
            throw new HttpsError(
                "not-found",
                `No ranking event found for post ${postId} and user ${userId}.`
            );
        }

        const eventData = eventsSnap.docs[0].data() as {
            signals: FeedRankingSignals;
            score: number;
        };

        const s: FeedRankingSignals = eventData.signals;
        const reasons: string[] = [];

        // Build human-readable reasons from signals
        if (s.relationshipScore > 0.7) {
            reasons.push("Someone you follow shared this");
        } else if (s.relationshipScore > 0.4) {
            reasons.push("A mutual connection shared this");
        } else {
            reasons.push("This is from someone outside your network");
        }

        if (s.trustScore > 0.8) {
            reasons.push("Posted by a trusted community member");
        } else if (s.trustScore < 0.3) {
            reasons.push("This author has a low community trust score");
        }

        if (s.spiritualUsefulnessScore > 0.7) {
            reasons.push("Contains scripture or spiritual content");
        }

        if (s.safetyScore === 0.0) {
            reasons.push("This post has been quarantined and ranked last");
        } else if (s.safetyScore < 0.6) {
            reasons.push("This post has a safety caution flag");
        }

        if (s.contextCompletenessScore > 0.8) {
            reasons.push("Well-sourced post with supporting context");
        } else if (s.contextCompletenessScore < 0.5) {
            reasons.push("Missing source or contextual information");
        }

        if (s.freshnessScore > 0.85) {
            reasons.push("Recently posted");
        } else if (s.freshnessScore < 0.25) {
            reasons.push("This is older content");
        }

        if (s.engagementScore > 0.5) {
            reasons.push("Popular post with significant engagement");
        }

        if (s.viralityRiskScore > 0.8) {
            reasons.push(
                "Ranked lower because this post is spreading unusually fast without full vetting"
            );
        }

        // Determine the single most impactful factor by weighted contribution
        const weightedContributions: Array<{ label: string; value: number }> = [
            { label: "Your relationship with this person", value: 0.25 * s.relationshipScore },
            { label: "Community trust score", value: 0.20 * s.trustScore },
            { label: "Post safety rating", value: 0.20 * s.safetyScore },
            { label: "Spiritual content value", value: 0.15 * s.spiritualUsefulnessScore },
            { label: "Source completeness", value: 0.10 * s.contextCompletenessScore },
            { label: "Post recency", value: 0.05 * s.freshnessScore },
            { label: "Community engagement", value: 0.05 * s.engagementScore },
        ];

        // Virality risk is a deduction — surface it as the top factor only if it
        // actively dragged the score down significantly
        const viralityDeduction = 0.20 * s.viralityRiskScore;
        if (viralityDeduction > 0.15) {
            weightedContributions.push({
                label: "Virality risk deduction",
                value: -viralityDeduction,
            });
        }

        weightedContributions.sort((a, b) => Math.abs(b.value) - Math.abs(a.value));
        const topFactor = weightedContributions[0]?.label ?? "Overall constitutional score";

        logger.info(
            `getRankingExplanation: explanation generated for post ${postId} user ${userId} ` +
            `(${reasons.length} reasons, topFactor="${topFactor}")`
        );

        return {
            reasons,
            topFactor,
        };
    }
);
