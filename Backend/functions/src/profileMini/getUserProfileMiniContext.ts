/**
 * getUserProfileMiniContext.ts
 *
 * Cloud Function: getUserProfileMiniContext
 *
 * Returns enriched context for a UserProfileViewMini card.
 * Reads cached Firestore fields only — no AI calls, no Pinecone writes.
 * Results cached per viewer+target+surface+trigger combination for 60 seconds.
 *
 * Firestore read budget: ≤ 12 reads per cold call, 1 on cache hit.
 * PII logged: uid + targetUserId only (no names, emails, or content).
 */

import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import {
    scoreMutuals,
    scoreTopicOverlap,
    scorePrayerOverlap,
    scoreTestimonyOverlap,
    scoreCityCommunity,
    scorePopularityFallback,
    ScoredReason,
} from "./reasonScorers";
import {
    resolveOpenTableTrigger,
    resolvePrayerTrigger,
    resolveTestimonyTrigger,
    ResolvedTrigger,
} from "./triggerResolvers";

const db = admin.firestore();

// ─── Request / Response Types ────────────────────────────────────────

interface Request {
    targetUserId: string;
    surface: "discovery" | "openTable" | "prayer" | "testimonies";
    /** Optional: specific artifact that triggered this suggestion. */
    triggerArtifactId?: string;
    /** Type of the triggering artifact, required when triggerArtifactId is set. */
    triggerArtifactType?: "openTableThread" | "prayerPost" | "testimonyPost";
}

interface ProfileMiniContextResponse {
    reasons: ScoredReason[];          // up to 3, sorted by score desc
    namedMutuals: string[];           // display names for mutual preview
    topicOverlap: number;
    prayerOverlap: number;
    testimonyTheme: string | null;
    cityCommunity: string | null;
    popularityFallback: boolean;
    trigger: ResolvedTrigger | null;
    pronoun: string | null;           // grammatical pronoun: "he/him", "she/her", "they/them"
    pronunciation: string | null;     // name phonetics: "MAR-kus", separate from pronoun
    canMessage: boolean;
    isFollowed: boolean;
}

const CACHE_TTL_MS = 60_000; // 60 seconds

// ─── Callable ────────────────────────────────────────────────────────

export const getUserProfileMiniContext = onCall({ enforceAppCheck: true }, async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
        // Auth guard
        if (!context.auth) {
            throw new HttpsError("unauthenticated", "Auth required.");
        }

        // App Check enforcement
        if (context.app == undefined) {
            throw new HttpsError(
                "failed-precondition",
                "The function must be called from an App Check verified app."
            );
        }

        const viewerUid = context.auth.uid;
        const { targetUserId, surface, triggerArtifactId, triggerArtifactType } = data;

        if (!targetUserId || typeof targetUserId !== "string") {
            throw new HttpsError("invalid-argument", "targetUserId is required.");
        }

        if (viewerUid === targetUserId) {
            throw new HttpsError("invalid-argument", "Cannot request context for self.");
        }

        // Rate limit — same budget as suggested accounts rail (10/min, 100/day)
        await enforceRateLimit(viewerUid, [
            RATE_LIMITS.SUGGEST_PER_MINUTE,
            RATE_LIMITS.SUGGEST_PER_DAY,
        ]);

        // ── Cache check (1 read) ──────────────────────────────────────
        // Include triggerArtifactId in cache key so different triggers get fresh results.
        const cacheDocId = triggerArtifactId
            ? `${targetUserId}_${surface}_${triggerArtifactId}`
            : `${targetUserId}_${surface}`;

        const cacheRef = db
            .collection("users").doc(viewerUid)
            .collection("profileMiniCache").doc(cacheDocId);

        const cacheSnap = await cacheRef.get();
        if (cacheSnap.exists) {
            const cached = cacheSnap.data()!;
            const age = Date.now() - (cached.cachedAt?.toDate?.()?.getTime?.() ?? 0);
            if (age < CACHE_TTL_MS) {
                return cached.payload as ProfileMiniContextResponse;
            }
        }

        // ── Parallel reads: viewer doc, target doc, isFollowed, block (4 reads) ──
        const [viewerDoc, targetDoc, followsIndexDoc, blockDoc] = await Promise.all([
            db.collection("users").doc(viewerUid).get(),
            db.collection("users").doc(targetUserId).get(),
            db.collection("follows_index").doc(`${viewerUid}_${targetUserId}`).get(),
            db.collection("blockedUsers").doc(`${viewerUid}_${targetUserId}`).get(),
        ]);

        if (!targetDoc.exists) {
            throw new HttpsError("not-found", "Target user not found.");
        }

        const viewerData = viewerDoc.data() ?? {};
        const targetData = targetDoc.data()!;

        const isFollowed = followsIndexDoc.exists;
        const isBlocked = blockDoc.exists;

        // canMessage: not blocked + target has DMs open (defaults true if field absent)
        const targetDmOpen: boolean = targetData.dmOpen !== false;
        const canMessage = !isBlocked && targetDmOpen;

        // ── Score reasons (mutuals require 2 more reads) ─────────────
        const viewerInterests: string[] = viewerData.interests || [];
        const targetInterests: string[] = targetData.interests || [];
        const viewerPrayerThemes: string[] = viewerData.prayerThemes || [];
        const targetPrayerThemes: string[] = targetData.prayerThemes || [];
        const targetFollowerCount: number = targetData.followerCount || 0;
        const targetPronoun: string | null = targetData.pronoun || null;
        const targetPronunciation: string | null = targetData.pronunciation || null;

        // Mutuals (2 reads)
        const { reason: mutualReason, namedMutuals } = await scoreMutuals(viewerUid, targetUserId);

        // Zero-read scorers (use data already fetched)
        const topicResult = scoreTopicOverlap(viewerInterests, targetInterests);
        const { reason: prayerReason, overlapCount: prayerOverlapCount } =
            scorePrayerOverlap(viewerPrayerThemes, targetPrayerThemes);
        const { reason: communityReason, cityCommunity } =
            scoreCityCommunity(viewerData.city || null, targetData.city || null);

        // Testimony overlap (2 reads, only on testimony/discovery surface)
        let testimonyResult: { reason: ScoredReason | null; theme: string | null } =
            { reason: null, theme: null };

        if (surface === "testimonies" || surface === "discovery") {
            const [viewerTestimonySnap, targetTestimonySnap] = await Promise.all([
                db.collection("posts")
                    .where("authorId", "==", viewerUid)
                    .where("category", "==", "testimony")
                    .limit(10)
                    .get(),
                db.collection("posts")
                    .where("authorId", "==", targetUserId)
                    .where("category", "==", "testimony")
                    .limit(10)
                    .get(),
            ]);
            const viewerTags = viewerTestimonySnap.docs.flatMap(d => d.data().tags || []) as string[];
            const targetTags = targetTestimonySnap.docs.flatMap(d => d.data().tags || []) as string[];
            const targetTheme = targetTags[0] || null;
            testimonyResult = scoreTestimonyOverlap(viewerTags, targetTags, targetTheme);
        }

        const popularityFallback = scorePopularityFallback(targetFollowerCount);

        // ── Collect and rank reasons ───────────────────────────────────
        const allReasons: ScoredReason[] = [
            prayerReason,
            testimonyResult.reason,
            mutualReason,
            topicResult,
            communityReason,
            popularityFallback,
        ].filter((r): r is ScoredReason => r !== null);

        allReasons.sort((a, b) => b.score - a.score);
        const reasons = allReasons.slice(0, 3);

        // ── Resolve surface-specific trigger (1–2 reads) ──────────────
        // If the caller passed a specific artifact, use it directly.
        let trigger: ResolvedTrigger | null = null;
        try {
            switch (surface) {
            case "openTable":
                trigger = await resolveOpenTableTrigger(viewerUid, targetUserId, triggerArtifactId);
                break;
            case "prayer":
                trigger = await resolvePrayerTrigger(targetUserId, viewerUid, triggerArtifactId);
                break;
            case "testimonies":
                trigger = await resolveTestimonyTrigger(targetUserId, viewerUid, triggerArtifactId);
                break;
            }
        } catch (err) {
            // Non-fatal: missing artifact returns null trigger, not a 500.
            functions.logger.warn("profileMini trigger resolve failed", {
                uid: viewerUid,
                targetUserId,
                triggerArtifactType,
                triggerArtifactId,
            });
            trigger = null;
        }

        // ── Build response ─────────────────────────────────────────────
        const payload: ProfileMiniContextResponse = {
            reasons,
            namedMutuals,
            topicOverlap: topicResult ? allReasons.filter(r => r.kind === "topicOverlap").length : 0,
            prayerOverlap: prayerOverlapCount,
            testimonyTheme: testimonyResult.theme,
            cityCommunity,
            popularityFallback: popularityFallback !== null,
            trigger,
            pronoun: targetPronoun,
            pronunciation: targetPronunciation,
            canMessage,
            isFollowed,
        };

        // ── Write cache (non-fatal) ────────────────────────────────────
        cacheRef.set({
            payload,
            cachedAt: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(e => functions.logger.warn("profileMini cache write failed", { uid: viewerUid }, e));

        return payload;
    }
);
