/**
 * getSuggestedFollows.ts
 *
 * Callable Cloud Function: "getSuggestedFollows"
 * Called by iOS via functions.httpsCallable("getSuggestedFollows")
 *
 * Input:  { limit?: number, includeNearby?: boolean, geoHash?: string }
 * Output: { suggestions: Array<SuggestedFollow> }
 *
 * Scoring algorithm:
 *   sameChurchId       → +40 pts
 *   mutualFollows      → +30 pts each, capped at +60 pts total
 *   sameCity           → +15 pts
 *   geoHash prefix     → +20 pts  (requires includeNearby + geoHash)
 *   newUserBonus       → +5  pts  (account created within 30 days)
 *
 * Filters:  self, already-following, blocked (either direction), dismissed
 * Private accounts are included with isPrivate:true but shown with a
 * "Follow to see their posts" reason — the follow request must still be sent.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

const db = admin.firestore();

// ─── Score constants ──────────────────────────────────────────────────────────

const SCORE_SAME_CHURCH   = 40;
const SCORE_MUTUAL_EACH   = 30;
const SCORE_MUTUAL_CAP    = 60;   // max mutual bonus regardless of mutual count
const SCORE_SAME_CITY     = 15;
const SCORE_GEO_HASH      = 20;
const SCORE_NEW_USER      = 5;
const NEW_USER_WINDOW_MS  = 30 * 24 * 60 * 60 * 1000; // 30 days

// ─── Types ────────────────────────────────────────────────────────────────────

interface GetSuggestedFollowsRequest {
    limit?: number;
    includeNearby?: boolean;
    geoHash?: string;
}

export interface SuggestedFollow {
    uid: string;
    displayName: string;
    username: string;
    photoURL: string | null;
    bio: string | null;
    isVerified: boolean;
    isPrivate: boolean;
    followerCount: number;
    reason: string;   // human-readable explanation shown in UI
    score: number;    // raw score for sorting (not shown in UI)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Build the set of user IDs that must never surface as suggestions.
 * Includes: self, already-following, blocked by/blocking, 24-hour dismissed.
 */
async function buildExclusionSet(uid: string): Promise<Set<string>> {
    const excluded = new Set<string>([uid]);

    const [followingSnap, blockedByMeSnap, feedbackSnap] = await Promise.all([
        db.collection("users").doc(uid).collection("following").limit(5000).get(),
        db.collection("users").doc(uid).collection("blockedUsers").limit(5000).get(),
        db.collection("users").doc(uid).collection("suggestionFeedback")
            .where("action", "in", ["dismiss", "follow"])
            .get(),
    ]);

    followingSnap.docs.forEach(d => excluded.add(d.id));
    blockedByMeSnap.docs.forEach(d => excluded.add(d.id));

    // Feedback: permanently exclude followed candidates; exclude dismissed within
    // a 24-hour cooldown so the same person doesn't re-appear immediately.
    const DISMISS_COOLDOWN_MS = 24 * 60 * 60 * 1000;
    const now = Date.now();
    feedbackSnap.docs.forEach(d => {
        const { action, timestamp } = d.data();
        if (action === "follow") {
            excluded.add(d.id);
        } else if (action === "dismiss") {
            const ts: number = timestamp?.toDate?.()?.getTime?.() ?? 0;
            if (now - ts < DISMISS_COOLDOWN_MS) excluded.add(d.id);
        }
    });

    return excluded;
}

/**
 * Collect the set of user-IDs the caller follows (capped at 200 for performance).
 */
async function getFollowingIds(uid: string): Promise<string[]> {
    const snap = await db.collection("users").doc(uid).collection("following").limit(200).get();
    return snap.docs.map(d => d.id);
}

/**
 * For each followed user, get who they follow and count overlaps.
 * Returns a Map<candidateId, mutualFollowerIds[]>.
 */
async function getMutualMap(
    followingIds: string[],
    excluded: Set<string>
): Promise<Map<string, string[]>> {
    const mutualMap = new Map<string, string[]>();
    const sample = followingIds.slice(0, 30); // cap to keep read count bounded

    await Promise.all(sample.map(async (friendId) => {
        const snap = await db.collection("users").doc(friendId)
            .collection("following").limit(50).get();
        for (const doc of snap.docs) {
            const cid = doc.id;
            if (excluded.has(cid)) continue;
            const existing = mutualMap.get(cid);
            if (existing) {
                existing.push(friendId);
            } else {
                mutualMap.set(cid, [friendId]);
            }
        }
    }));

    return mutualMap;
}

/**
 * Check whether uidB has blocked uidA (reverse direction).
 * Used only for high-value candidates to save reads.
 */
async function isBlockedByCandidate(myUid: string, candidateUid: string): Promise<boolean> {
    const snap = await db.collection("users").doc(candidateUid)
        .collection("blockedUsers").doc(myUid).get();
    return snap.exists;
}

/**
 * Build a human-readable reason string for this suggestion.
 */
function buildReason(params: {
    sameChurch: boolean;
    churchName?: string;
    mutualCount: number;
    mutualNames: string[];
    sameCity: boolean;
    city?: string;
    nearbyGeo: boolean;
    isNewUser: boolean;
    isPrivate: boolean;
}): string {
    if (params.isPrivate) {
        if (params.sameChurch && params.churchName) {
            return `Member of ${params.churchName} · Private account`;
        }
        if (params.mutualCount > 0) {
            return `Followed by ${params.mutualNames[0]}${params.mutualCount > 1 ? ` + ${params.mutualCount - 1} more` : ""} · Private account`;
        }
        return "People you may know · Private account";
    }
    if (params.sameChurch && params.churchName) {
        return `Member of ${params.churchName}`;
    }
    if (params.mutualCount >= 3) {
        return `Followed by ${params.mutualNames.slice(0, 2).join(", ")} + ${params.mutualCount - 2} others`;
    }
    if (params.mutualCount === 2) {
        return `Followed by ${params.mutualNames[0]} and 1 other`;
    }
    if (params.mutualCount === 1) {
        return `Followed by ${params.mutualNames[0]}`;
    }
    if (params.nearbyGeo || params.sameCity) {
        return params.city ? `Near you in ${params.city}` : "Near you";
    }
    if (params.isNewUser) {
        return "New to AMEN · Say welcome";
    }
    return "Suggested for you";
}

// ─── Main Cloud Function ──────────────────────────────────────────────────────

export const getSuggestedFollows = functions.https.onCall(
    async (data: GetSuggestedFollowsRequest, context) => {
        // Auth guard
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
        }

        // App Check guard
        if (context.app == null) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Must be called from an App Check verified app."
            );
        }

        // Rate limit: reuse the suggest bucket (10/min, 100/day)
        await enforceRateLimit(context.auth.uid, [
            RATE_LIMITS.SUGGEST_PER_MINUTE,
            RATE_LIMITS.SUGGEST_PER_DAY,
        ]);

        const uid = context.auth.uid;
        const limit = Math.min(Math.max(data.limit ?? 20, 1), 40);
        const includeNearby = data.includeNearby === true;
        const incomingGeoHash: string | undefined =
            typeof data.geoHash === "string" && data.geoHash.length >= 4
                ? data.geoHash
                : undefined;

        // ── 1. Caller profile ─────────────────────────────────────────────────
        const [callerDoc, excluded] = await Promise.all([
            db.collection("users").doc(uid).get(),
            buildExclusionSet(uid),
        ]);

        if (!callerDoc.exists) {
            throw new functions.https.HttpsError("not-found", "Caller profile not found.");
        }

        const callerData = callerDoc.data()!;
        const callerChurchId: string | undefined = callerData.churchId;
        const callerCity: string | undefined = callerData.city;
        const callerGeoHash: string | undefined =
            incomingGeoHash ?? callerData.geoHash ?? callerData.discoveryGeoHash;

        // ── 2. Candidate pools ────────────────────────────────────────────────

        const candidateScores = new Map<string, number>();
        const mutualMap = new Map<string, string[]>();

        // Pool A: Same church
        if (callerChurchId) {
            const churchSnap = await db.collection("users")
                .where("churchId", "==", callerChurchId)
                .where("isPublic", "==", true)
                .limit(60)
                .get();
            for (const doc of churchSnap.docs) {
                if (!excluded.has(doc.id)) {
                    candidateScores.set(
                        doc.id,
                        (candidateScores.get(doc.id) ?? 0) + SCORE_SAME_CHURCH
                    );
                }
            }
            // Private accounts in same church — include with lower score
            const privateChurchSnap = await db.collection("users")
                .where("churchId", "==", callerChurchId)
                .where("isPublic", "==", false)
                .limit(20)
                .get();
            for (const doc of privateChurchSnap.docs) {
                if (!excluded.has(doc.id)) {
                    // Private church members still get church score — reason will flag them
                    candidateScores.set(
                        doc.id,
                        (candidateScores.get(doc.id) ?? 0) + SCORE_SAME_CHURCH
                    );
                }
            }
        }

        // Pool B: Mutual follows (friends-of-friends)
        const followingIds = await getFollowingIds(uid);
        const rawMutualMap = await getMutualMap(followingIds, excluded);
        for (const [cid, friendIds] of rawMutualMap.entries()) {
            mutualMap.set(cid, friendIds);
            const bonus = Math.min(friendIds.length * SCORE_MUTUAL_EACH, SCORE_MUTUAL_CAP);
            candidateScores.set(cid, (candidateScores.get(cid) ?? 0) + bonus);
        }

        // Pool C: Same city
        if (callerCity) {
            const citySnap = await db.collection("users")
                .where("city", "==", callerCity)
                .where("isPublic", "==", true)
                .limit(40)
                .get();
            for (const doc of citySnap.docs) {
                if (!excluded.has(doc.id)) {
                    candidateScores.set(
                        doc.id,
                        (candidateScores.get(doc.id) ?? 0) + SCORE_SAME_CITY
                    );
                }
            }
        }

        // Pool D: GeoHash prefix (nearby, opt-in only)
        if (includeNearby && callerGeoHash && callerGeoHash.length >= 4) {
            // Match the first 4 chars of the geoHash (≈ 40km × 20km cell)
            const geoPrefix = callerGeoHash.substring(0, 4);
            const geoSnap = await db.collection("users")
                .where("discoveryGeoHash", ">=", geoPrefix)
                .where("discoveryGeoHash", "<",  geoPrefix + "")
                .where("isPublic", "==", true)
                .limit(40)
                .get();
            for (const doc of geoSnap.docs) {
                if (!excluded.has(doc.id) && doc.id !== uid) {
                    candidateScores.set(
                        doc.id,
                        (candidateScores.get(doc.id) ?? 0) + SCORE_GEO_HASH
                    );
                }
            }
        }

        // ── 3. Fetch candidate profiles ───────────────────────────────────────

        // Sort candidates by score descending before fetching profiles so we
        // fetch the best candidates first and can stop early.
        const sortedCandidateIds = Array.from(candidateScores.entries())
            .sort((a, b) => b[1] - a[1])
            .map(([id]) => id)
            .slice(0, 80); // fetch at most 80 profiles

        if (sortedCandidateIds.length === 0) {
            return { suggestions: [] };
        }

        // Batch-fetch all candidate profiles in one db.getAll call (up to 80)
        const profileRefs = sortedCandidateIds.map(id => db.collection("users").doc(id));
        const profileDocs = await db.getAll(...profileRefs);

        // Pre-fetch mutual user display names (for reason strings) in one pass
        const allMutualIds = new Set<string>();
        for (const ids of mutualMap.values()) {
            ids.slice(0, 2).forEach(id => allMutualIds.add(id));
        }
        const mutualNameCache = new Map<string, string>();
        if (allMutualIds.size > 0) {
            const mutualRefs = Array.from(allMutualIds).map(id => db.collection("users").doc(id));
            const mutualDocs = await db.getAll(...mutualRefs);
            for (const mDoc of mutualDocs) {
                if (mDoc.exists) {
                    const d = mDoc.data()!;
                    mutualNameCache.set(mDoc.id, d.displayName ?? d.username ?? "Someone");
                }
            }
        }

        // ── 4. Build scored suggestion list ───────────────────────────────────

        const now = Date.now();
        const suggestions: SuggestedFollow[] = [];

        for (const doc of profileDocs) {
            if (!doc.exists) continue;
            const d = doc.data()!;
            const cid = doc.id;

            // Hard filters: banned/spam accounts
            if (d.isBanned || d.isModHold || d.isSpam) continue;

            // Bidirectional block check for high-score candidates only
            // (saves reads for low-quality candidates that will be filtered by limit)
            const rawScore = candidateScores.get(cid) ?? 0;
            if (rawScore >= SCORE_SAME_CHURCH) {
                if (await isBlockedByCandidate(uid, cid)) continue;
            }

            // New-user bonus
            let finalScore = rawScore;
            const createdAt: number = d.createdAt?.toDate?.()?.getTime?.() ?? 0;
            const isNewUser = createdAt > 0 && (now - createdAt) < NEW_USER_WINDOW_MS;
            if (isNewUser) finalScore += SCORE_NEW_USER;

            // Determine geo match for reason string
            const candGeoHash: string | undefined = d.discoveryGeoHash ?? d.geoHash;
            const nearbyGeo = includeNearby
                && !!callerGeoHash
                && !!candGeoHash
                && callerGeoHash.substring(0, 4) === candGeoHash.substring(0, 4);

            const sameCity = !!callerCity && callerCity === d.city;
            const sameChurch = !!callerChurchId && callerChurchId === d.churchId;
            const churchName: string | undefined = sameChurch
                ? (callerData.churchName ?? undefined)
                : undefined;

            const mutualIds = mutualMap.get(cid) ?? [];
            const mutualNames = mutualIds
                .slice(0, 3)
                .map(mid => mutualNameCache.get(mid) ?? "Someone");

            const isPrivate = d.isPublic === false;

            const reason = buildReason({
                sameChurch,
                churchName,
                mutualCount: mutualIds.length,
                mutualNames,
                sameCity,
                city: callerCity,
                nearbyGeo,
                isNewUser,
                isPrivate,
            });

            suggestions.push({
                uid: cid,
                displayName: d.displayName ?? d.username ?? "User",
                username: d.username ?? cid.substring(0, 8),
                photoURL: d.profileImageURL ?? d.photoURL ?? null,
                bio: d.bio ?? null,
                isVerified: d.isVerified === true,
                isPrivate,
                followerCount: d.followerCount ?? d.followersCount ?? 0,
                reason,
                score: finalScore,
            });

            if (suggestions.length >= limit * 2) break; // collect enough to sort & trim
        }

        // ── 5. Sort and trim ──────────────────────────────────────────────────
        suggestions.sort((a, b) => b.score - a.score);
        const trimmed = suggestions.slice(0, limit);

        return { suggestions: trimmed };
    }
);
