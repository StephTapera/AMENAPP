/**
 * reasonScorers.ts
 *
 * Signal-scoring helpers for getUserProfileMiniContext.
 * Each scorer reads a minimal set of cached/indexed Firestore fields
 * and returns a { kind, score, payload } reason, or null if no signal.
 *
 * No OpenAI/Pinecone writes. No PII logged beyond uid.
 */

import * as admin from "firebase-admin";

const db = admin.firestore();

export interface ScoredReason {
    kind: string;
    score: number;
    payload: string;
}

/**
 * Score mutual-connection overlap using the follows_index collection
 * so we never do a full following-list scan.
 * Reads: 1 (viewer following list) + 1 (target follower list) = 2 max.
 */
export async function scoreMutuals(
    viewerUid: string,
    targetUid: string
): Promise<{ reason: ScoredReason | null; namedMutuals: string[] }> {
    const [viewerFollowingSnap, targetFollowersSnap] = await Promise.all([
        db.collection("users").doc(viewerUid).collection("following").limit(500).get(),
        db.collection("users").doc(targetUid).collection("followers").limit(500).get(),
    ]);

    const viewerFollowing = new Set(viewerFollowingSnap.docs.map(d => d.id));
    const targetFollowers = new Set(targetFollowersSnap.docs.map(d => d.id));
    const mutualIds = [...viewerFollowing].filter(id => targetFollowers.has(id));

    if (mutualIds.length === 0) return { reason: null, namedMutuals: [] };

    // Fetch display names for up to 3 mutuals (batch read)
    const previewIds = mutualIds.slice(0, 3);
    const mutualDocs = await db.getAll(...previewIds.map(id => db.collection("users").doc(id)));
    const namedMutuals = mutualDocs
        .filter(d => d.exists)
        .map(d => (d.data()?.displayName || d.data()?.username || "Someone") as string);

    const count = mutualIds.length;
    const score = Math.min(count / 10, 1.0);
    const payload = count === 1 ? "1 mutual connection" : `${count} mutual connections`;

    return { reason: { kind: "mutualConnections", score, payload }, namedMutuals };
}

/**
 * Score topic/interest overlap using pre-indexed interests arrays.
 * Reads: 0 additional (caller passes user docs already fetched).
 */
export function scoreTopicOverlap(
    viewerInterests: string[],
    targetInterests: string[]
): ScoredReason | null {
    const shared = viewerInterests.filter(t => targetInterests.includes(t));
    if (shared.length === 0) return null;

    const count = shared.length;
    const score = Math.min(count / 5, 1.0);
    const payload = count === 1
        ? `Shared interest: ${shared[0]}`
        : `${count} shared interests including ${shared[0]}`;

    return { kind: "topicOverlap", score, payload };
}

/**
 * Score prayer topic overlap using prayerThemes arrays.
 * Reads: 0 additional (caller passes user docs already fetched).
 */
export function scorePrayerOverlap(
    viewerThemes: string[],
    targetThemes: string[]
): { reason: ScoredReason | null; overlapCount: number } {
    const shared = viewerThemes.filter(t => targetThemes.includes(t));
    if (shared.length === 0) return { reason: null, overlapCount: 0 };

    const count = shared.length;
    // Prayer overlap weighted 20% higher than topic overlap
    const score = Math.min((count / 3) * 1.2, 1.0);
    const payload = count === 1 ? "1 shared prayer topic" : `${count} shared prayer topics`;

    return { reason: { kind: "prayerOverlap", score, payload }, overlapCount: count };
}

/**
 * Score testimony theme overlap using post tags.
 * Reads: 2 (one posts query per uid, run in parallel by caller).
 */
export function scoreTestimonyOverlap(
    viewerTags: string[],
    targetTags: string[],
    targetTestimonyTheme: string | null
): { reason: ScoredReason | null; theme: string | null } {
    const viewerSet = new Set(viewerTags);
    const shared = targetTags.filter(t => viewerSet.has(t));

    if (shared.length === 0) return { reason: null, theme: targetTestimonyTheme };

    const score = Math.min(shared.length / 3, 1.0);
    const theme = shared[0] || targetTestimonyTheme;
    const payload = shared.length === 1
        ? `Shared testimony theme: ${shared[0]}`
        : `${shared.length} shared testimony themes`;

    return { reason: { kind: "testimonyOverlap", score, payload }, theme };
}

/**
 * Score city/community overlap.
 * Reads: 0 additional (caller passes user docs already fetched).
 */
export function scoreCityCommunity(
    viewerCity: string | null,
    targetCity: string | null
): { reason: ScoredReason | null; cityCommunity: string | null } {
    if (!viewerCity || !targetCity) return { reason: null, cityCommunity: null };
    if (viewerCity.toLowerCase() !== targetCity.toLowerCase()) return { reason: null, cityCommunity: null };

    return {
        reason: { kind: "communityOverlap", score: 0.4, payload: `Also in ${targetCity}` },
        cityCommunity: targetCity,
    };
}

/**
 * Popularity fallback — used only when primary signals are low.
 * Reads: 0 additional (caller passes followerCount from user doc).
 */
export function scorePopularityFallback(
    followerCount: number
): ScoredReason | null {
    if (followerCount < 100) return null;

    const score = Math.min(followerCount / 10_000, 0.5);
    const payload = followerCount >= 1_000
        ? `Followed by ${(followerCount / 1_000).toFixed(1)}K people`
        : `Followed by ${followerCount} people`;

    return { kind: "popularInArea", score, payload };
}
