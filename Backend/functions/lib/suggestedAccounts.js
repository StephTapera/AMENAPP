"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.logSuggestionFeedback = exports.getSuggestedAccountsRail = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const rateLimit_1 = require("./rateLimit");
const db = admin.firestore();
// ─── Scoring Weights ─────────────────────────────────────────────────
const WEIGHTS = {
    graphAffinity: 0.28,
    topicAffinity: 0.18,
    mutualContext: 0.14,
    freshness: 0.12,
    profileQuality: 0.10,
    safetyScore: 0.10,
    conversionLikelihood: 0.08,
    fatiguePenalty: -0.18,
    dismissPenalty: -0.25,
};
// ─── Helpers ─────────────────────────────────────────────────────────
/**
 * Load user IDs the caller should never see as suggestions.
 */
async function loadExclusions(uid) {
    const excluded = new Set();
    excluded.add(uid); // Never suggest yourself
    const [followingSnap, blockedSnap, mutedSnap, feedbackSnap,] = await Promise.all([
        db.collection("users").doc(uid).collection("following").limit(5000).get(),
        db.collection("users").doc(uid).collection("blockedUsers").limit(5000).get(),
        db.collection("users").doc(uid).collection("mutedUsers").limit(5000).get(),
        db.collection("users").doc(uid).collection("suggestionFeedback")
            .where("action", "in", ["dismiss", "follow"])
            .get(),
    ]);
    followingSnap.docs.forEach(d => excluded.add(d.id));
    blockedSnap.docs.forEach(d => excluded.add(d.id));
    mutedSnap.docs.forEach(d => excluded.add(d.id));
    // Check dismiss cooldown (24 hours) and permanent follows
    const now = Date.now();
    const DISMISS_COOLDOWN_MS = 24 * 60 * 60 * 1000;
    feedbackSnap.docs.forEach(d => {
        const data = d.data();
        if (data.action === "follow") {
            excluded.add(d.id);
        }
        else if (data.action === "dismiss") {
            const ts = data.timestamp?.toDate?.()?.getTime?.() ?? 0;
            if (now - ts < DISMISS_COOLDOWN_MS) {
                excluded.add(d.id);
            }
        }
    });
    return excluded;
}
/**
 * Check if a user is blocked in either direction.
 */
async function isBlockedEitherDirection(uidA, uidB) {
    const [ab, ba] = await Promise.all([
        db.collection("users").doc(uidA).collection("blockedUsers").doc(uidB).get(),
        db.collection("users").doc(uidB).collection("blockedUsers").doc(uidA).get(),
    ]);
    return ab.exists || ba.exists;
}
/**
 * Get second-degree connections: friends-of-friends.
 */
async function getSecondDegreeConnections(uid, excluded, maxCandidates) {
    const candidates = new Map();
    // Get a sample of users the caller follows
    const followingSnap = await db.collection("users").doc(uid)
        .collection("following")
        .limit(100)
        .get();
    const followedIds = followingSnap.docs.map(d => d.id);
    // For each followed user, get who they follow (second-degree)
    const batchSize = 20; // Process in batches to limit reads
    for (let i = 0; i < Math.min(followedIds.length, batchSize); i++) {
        const friendId = followedIds[i];
        const friendFollowingSnap = await db.collection("users").doc(friendId)
            .collection("following")
            .limit(50)
            .get();
        for (const doc of friendFollowingSnap.docs) {
            const candidateId = doc.id;
            if (excluded.has(candidateId))
                continue;
            const existing = candidates.get(candidateId);
            if (existing) {
                existing.graphScore += 1;
                existing.mutualIds.push(friendId);
            }
            else {
                candidates.set(candidateId, { graphScore: 1, mutualIds: [friendId] });
            }
            if (candidates.size >= maxCandidates)
                break;
        }
        if (candidates.size >= maxCandidates)
            break;
    }
    return candidates;
}
/**
 * Get popular/active accounts as fallback candidates.
 */
async function getPopularAccounts(excluded, limit) {
    const snap = await db.collection("users")
        .where("isPublic", "==", true)
        .orderBy("followerCount", "desc")
        .limit(limit + excluded.size) // Over-fetch to account for exclusions
        .get();
    return snap.docs
        .map(d => d.id)
        .filter(id => !excluded.has(id))
        .slice(0, limit);
}
/**
 * Build a reason string for a suggestion based on surface and signals.
 */
function buildReason(surface, mutualCount, mutualNames, sharedTopicCount, accountType) {
    if (surface === "prayer" && accountType === "church") {
        return { reasonType: "sharedChurch", reasonText: "Active in prayer communities you follow" };
    }
    if (surface === "testimonies" && accountType === "creator") {
        return { reasonType: "similarContent", reasonText: "Shares powerful testimonies" };
    }
    if (mutualCount >= 3) {
        return { reasonType: "mutualFollowers", reasonText: `Followed by ${mutualNames.slice(0, 2).join(", ")} and ${mutualCount - 2} others` };
    }
    if (mutualCount >= 1) {
        return { reasonType: "mutualFollowers", reasonText: `Followed by ${mutualNames[0]}${mutualCount > 1 ? ` and ${mutualCount - 1} other${mutualCount > 2 ? "s" : ""}` : ""}` };
    }
    if (sharedTopicCount >= 2) {
        return { reasonType: "sharedInterests", reasonText: "Shares your interests" };
    }
    return { reasonType: "generic", reasonText: "Suggested for you" };
}
/**
 * Compute composite score for a candidate.
 */
function computeScore(params) {
    return Math.max(0, Math.min(1, WEIGHTS.graphAffinity * params.graphAffinity +
        WEIGHTS.topicAffinity * params.topicAffinity +
        WEIGHTS.mutualContext * params.mutualContext +
        WEIGHTS.freshness * params.freshness +
        WEIGHTS.profileQuality * params.profileQuality +
        WEIGHTS.safetyScore * params.safetyScore +
        WEIGHTS.conversionLikelihood * params.conversionLikelihood +
        WEIGHTS.fatiguePenalty * params.fatiguePenalty +
        WEIGHTS.dismissPenalty * params.dismissPenalty));
}
/**
 * Diversify results: ensure no more than 2 from the same topic or popularity tier.
 */
function diversify(candidates, limit) {
    const result = [];
    const topicCounts = new Map();
    const typeCounts = new Map();
    const MAX_PER_TOPIC = 2;
    const MAX_PER_TYPE = 3;
    for (const c of candidates) {
        // Topic cap
        const primaryTopic = c.sharedTopics[0] || "__none__";
        const topicCount = topicCounts.get(primaryTopic) ?? 0;
        if (topicCount >= MAX_PER_TOPIC)
            continue;
        // Type cap
        const typeCount = typeCounts.get(c.accountType) ?? 0;
        if (typeCount >= MAX_PER_TYPE)
            continue;
        result.push(c);
        topicCounts.set(primaryTopic, topicCount + 1);
        typeCounts.set(c.accountType, typeCount + 1);
        if (result.length >= limit)
            break;
    }
    return result;
}
// ─── 1. getSuggestedAccountsRail ─────────────────────────────────────
exports.getSuggestedAccountsRail = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    // CRITICAL-CF FIX: Per-user rate limiting.
    // getSuggestedAccountsRail makes dozens of Firestore reads per call.
    // Without rate limiting, a script can trigger unbounded read costs.
    await (0, rateLimit_1.enforceRateLimit)(context.auth.uid, [
        rateLimit_1.RATE_LIMITS.SUGGEST_PER_MINUTE,
        rateLimit_1.RATE_LIMITS.SUGGEST_PER_DAY,
    ]);
    const uid = context.auth.uid;
    const surface = data.surface || "openTable";
    const limit = Math.min(data.limit ?? 15, 30);
    // 1. Load exclusions
    const excluded = await loadExclusions(uid);
    // 2. Candidate generation: second-degree graph + popular fallback
    const graphCandidates = await getSecondDegreeConnections(uid, excluded, 100);
    // Add popular fallback if graph candidates are sparse
    if (graphCandidates.size < limit) {
        const popular = await getPopularAccounts(excluded, limit * 2);
        for (const id of popular) {
            if (!graphCandidates.has(id)) {
                graphCandidates.set(id, { graphScore: 0, mutualIds: [] });
            }
        }
    }
    // 3. Load candidate profiles in batches
    const candidateIds = Array.from(graphCandidates.keys()).slice(0, 80);
    const scored = [];
    // HIGH FIX: Pre-fetch caller interests once (was being re-fetched inside
    // the per-candidate loop — O(n) reads for a single document).
    const callerDoc = await db.collection("users").doc(uid).get();
    const callerInterests = callerDoc.data()?.interests || [];
    // HIGH FIX: Collect ALL mutual IDs needed across all candidates up-front,
    // then fetch them in one db.getAll() call instead of N serial awaits.
    // For 30 candidates × 3 mutuals = 90 reads → 1 batched RPC.
    const allMutualIds = new Set();
    for (const id of candidateIds) {
        for (const mid of (graphCandidates.get(id)?.mutualIds ?? []).slice(0, 3)) {
            allMutualIds.add(mid);
        }
    }
    const mutualCache = new Map();
    if (allMutualIds.size > 0) {
        const mutualRefs = Array.from(allMutualIds).map(id => db.collection("users").doc(id));
        // db.getAll supports up to 500 refs per call; our cap of 80 candidates × 3 = 240 max
        const mutualDocs = await db.getAll(...mutualRefs);
        for (const mDoc of mutualDocs) {
            if (mDoc.exists)
                mutualCache.set(mDoc.id, mDoc.data());
        }
    }
    // HIGH FIX: Batch-fetch all feedback docs for this user+candidates in one getAll.
    // Was previously a serial await per candidate — O(n) reads.
    const feedbackCache = new Map();
    if (candidateIds.length > 0) {
        const feedbackRefs = candidateIds.map(id => db.collection("users").doc(uid).collection("suggestionFeedback").doc(id));
        const feedbackDocs = await db.getAll(...feedbackRefs);
        for (const fbDoc of feedbackDocs) {
            if (fbDoc.exists)
                feedbackCache.set(fbDoc.id, fbDoc.data());
        }
    }
    // HIGH FIX #20: Pre-fetch testimony excerpts for all candidates in parallel
    // when surface === "testimonies". Previously each candidate triggered a
    // serial await inside the loop — O(n) sequential Firestore queries.
    // Promise.all collapses all N queries into one parallel RPC batch.
    const testimonyCache = new Map(); // candidateId → excerpt
    if (surface === "testimonies" && candidateIds.length > 0) {
        await Promise.all(candidateIds.map(async (candidateId) => {
            try {
                const snap = await db.collection("posts")
                    .where("authorId", "==", candidateId)
                    .where("category", "==", "testimony")
                    .orderBy("createdAt", "desc")
                    .limit(1)
                    .get();
                if (!snap.empty) {
                    const content = snap.docs[0].data().content || "";
                    testimonyCache.set(candidateId, content.length > 120 ? content.substring(0, 120) + "..." : content);
                }
            }
            catch {
                // Non-fatal: missing testimony is fine
            }
        }));
    }
    // Batch reads (Firestore getAll limit is 100)
    const BATCH = 30;
    for (let i = 0; i < candidateIds.length; i += BATCH) {
        const batch = candidateIds.slice(i, i + BATCH);
        const refs = batch.map(id => db.collection("users").doc(id));
        const docs = await db.getAll(...refs);
        for (const doc of docs) {
            if (!doc.exists)
                continue;
            const userData = doc.data();
            const candidateId = doc.id;
            // Safety filtering
            if (userData.isBanned || userData.isModHold || userData.isSpam)
                continue;
            if (userData.isMinor && surface === "prayer")
                continue; // Age-policy
            // Bidirectional block check (sample — only for top candidates)
            if (graphCandidates.get(candidateId).graphScore > 2) {
                if (await isBlockedEitherDirection(uid, candidateId))
                    continue;
            }
            const graph = graphCandidates.get(candidateId);
            const mutualIds = graph.mutualIds;
            // Build mutual names from the pre-fetched cache (no serial awaits)
            const mutualNames = [];
            const mutualAvatarURLs = [];
            for (const mid of mutualIds.slice(0, 3)) {
                const mData = mutualCache.get(mid);
                if (mData) {
                    mutualNames.push(mData.displayName || mData.username || "Someone");
                    mutualAvatarURLs.push(mData.profileImageURL || "");
                }
            }
            // Topic affinity: count shared interests/topics
            const candidateInterests = userData.interests || [];
            const sharedTopics = callerInterests.filter(t => candidateInterests.includes(t));
            // Freshness: accounts active in last 7 days score higher
            const lastActive = userData.lastActiveAt?.toDate?.()?.getTime?.() ?? 0;
            const daysSinceActive = (Date.now() - lastActive) / (24 * 60 * 60 * 1000);
            const freshness = daysSinceActive < 1 ? 1.0 : daysSinceActive < 7 ? 0.7 : daysSinceActive < 30 ? 0.3 : 0.1;
            // Profile quality: bio, avatar, post count
            const hasBio = (userData.bio || "").length > 10 ? 0.3 : 0;
            const hasAvatar = userData.profileImageURL ? 0.3 : 0;
            const postActivity = Math.min((userData.postCount || 0) / 20, 0.4);
            const profileQuality = hasBio + hasAvatar + postActivity;
            // Conversion likelihood: based on similar users' follow-through
            const followerRatio = userData.followerCount > 0
                ? Math.min((userData.followerCount || 0) / ((userData.followingCount || 1)), 3) / 3
                : 0.2;
            // Fatigue: use pre-fetched feedback cache (no serial await)
            let fatiguePenalty = 0;
            let dismissPenalty = 0;
            const fb = feedbackCache.get(candidateId);
            if (fb) {
                const ignores = fb.ignores || 0;
                if (ignores >= 3)
                    fatiguePenalty = (ignores - 2) * 0.15;
                if (fb.action === "dismiss") {
                    const ts = fb.timestamp?.toDate?.()?.getTime?.() ?? 0;
                    const hoursSince = (Date.now() - ts) / (60 * 60 * 1000);
                    if (hoursSince < 24)
                        dismissPenalty = 1.0;
                }
            }
            const normalizedGraph = Math.min(graph.graphScore / 5, 1.0);
            const topicAffinity = Math.min(sharedTopics.length / 3, 1.0);
            const mutualContext = Math.min(mutualIds.length / 5, 1.0);
            const score = computeScore({
                graphAffinity: normalizedGraph,
                topicAffinity,
                mutualContext,
                freshness,
                profileQuality,
                safetyScore: userData.isBanned ? 0 : 1.0,
                conversionLikelihood: followerRatio,
                fatiguePenalty,
                dismissPenalty,
            });
            const accountType = userData.accountType || "personal";
            const reason = buildReason(surface, mutualIds.length, mutualNames, sharedTopics.length, accountType);
            // Surface-specific fields
            let prayerThemes = [];
            let recentTestimonyExcerpt = null;
            if (surface === "prayer") {
                prayerThemes = (userData.prayerThemes || userData.interests || []).slice(0, 3);
            }
            if (surface === "testimonies") {
                // Use pre-fetched cache (see testimonyCache above — no serial await)
                recentTestimonyExcerpt = testimonyCache.get(candidateId) ?? null;
            }
            scored.push({
                id: candidateId,
                displayName: userData.displayName || userData.username || "User",
                handle: userData.username || candidateId.substring(0, 8),
                avatarURL: userData.profileImageURL || null,
                isVerified: userData.isVerified || false,
                isPrivate: !(userData.isPublic ?? true),
                accountType,
                reasonType: reason.reasonType,
                reasonText: reason.reasonText,
                mutualCount: mutualIds.length,
                mutualNames,
                mutualAvatarURLs,
                score,
                contextLine: reason.reasonText,
                bio: userData.bio || null,
                prayerThemes,
                recentTestimonyExcerpt,
                followerCount: userData.followerCount || 0,
                postCount: userData.postCount || 0,
                sharedTopics,
            });
        }
    }
    // 4. Sort by score descending
    scored.sort((a, b) => b.score - a.score);
    // 5. Diversify
    const diversified = diversify(scored, limit);
    // 6. Cache results for this surface
    try {
        await db.collection("users").doc(uid)
            .collection("suggestedRailCache").doc(surface)
            .set({
            items: diversified,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            surface,
        });
    }
    catch (e) {
        // Cache write failure is non-fatal
        functions.logger.warn("Failed to write suggestion cache", e);
    }
    return diversified;
});
// ─── 2. logSuggestionFeedback ────────────────────────────────────────
exports.logSuggestionFeedback = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const uid = context.auth.uid;
    const { targetUserId, action, surface, position } = data;
    if (!targetUserId || !action || !surface) {
        throw new functions.https.HttpsError("invalid-argument", "targetUserId, action, and surface are required");
    }
    const validActions = ["dismiss", "follow", "ignore", "hide_rail", "show_fewer"];
    if (!validActions.includes(action)) {
        throw new functions.https.HttpsError("invalid-argument", `Invalid action: ${action}`);
    }
    const feedbackRef = db.collection("users").doc(uid)
        .collection("suggestionFeedback").doc(targetUserId);
    const feedbackData = {
        action,
        surface,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (typeof position === "number") {
        feedbackData.position = position;
    }
    // For ignores, increment the counter
    if (action === "ignore") {
        feedbackData.ignores = admin.firestore.FieldValue.increment(1);
    }
    await feedbackRef.set(feedbackData, { merge: true });
    // If followed, also invalidate the cache for this surface
    if (action === "follow" || action === "dismiss") {
        try {
            const cacheRef = db.collection("users").doc(uid)
                .collection("suggestedRailCache").doc(surface);
            const cacheSnap = await cacheRef.get();
            if (cacheSnap.exists) {
                const cached = cacheSnap.data();
                const items = cached?.items || [];
                const filtered = items.filter(i => i.id !== targetUserId);
                await cacheRef.update({ items: filtered });
            }
        }
        catch (e) {
            // Cache update failure is non-fatal
            functions.logger.warn("Failed to update suggestion cache after feedback", e);
        }
    }
    return { ok: true };
});
//# sourceMappingURL=suggestedAccounts.js.map