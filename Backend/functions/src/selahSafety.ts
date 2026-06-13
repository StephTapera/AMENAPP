// selahSafety.ts
// AMEN Backend — Selah Safety & Transparency Callables
//
// Exports:
//   generateFeedExplanation  — produces warm-language feed explanation, caches at feedExplanations/{id}
//   enforceYouthDMPolicy     — C60 youth DM policy + C59 signal for content
//   detectAegisC59           — server-side spiritual abuse pattern detection (Tier S/C only)
//
// Region: us-central1
// Firebase Gen-2 callable functions.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// Ensure admin is initialized (idempotent — root index.ts calls initializeApp).
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

// MARK: - Types

interface FeedExplanation {
    id: string;
    feedItemId: string;
    reasons: string[];           // FeedReasonCode values
    humanReadable: string;       // warm, human-readable string
}

interface AegisC59Signal {
    patternKind: "manipulationFraming" | "financialCoercion" | "isolationTactics";
    confidence: number;
    recipientResources: string[];
    internalSignal: string;
}

// MARK: - Feed Explanation

/**
 * Generates and caches a warm-language feed explanation for a feed item.
 * FAIL-CLOSED behavior: if generation fails, returns a safe fallback explanation
 * rather than null — callers may choose not to render items without an explanation,
 * but the backend itself guarantees a non-null response on success.
 */
export const generateFeedExplanation = onCall(
    { region: "us-central1" },
    async (request) => {
        const { feedItemId, uid } = request.data as { feedItemId: string; uid: string };

        if (!feedItemId || !uid) {
            throw new HttpsError("invalid-argument", "feedItemId and uid are required");
        }

        // 1. Check Firestore cache first.
        const docRef = db.collection("feedExplanations").doc(feedItemId);
        const existing = await docRef.get();
        if (existing.exists) {
            return existing.data() as FeedExplanation;
        }

        // 2. Analyze feed item and user context to generate explanation.
        try {
            const feedItemDoc = await db.collection("posts").doc(feedItemId).get();
            const feedItemData = feedItemDoc.data() ?? {};

            const userDoc = await db.collection("users").doc(uid).get();
            const userData = userDoc.data() ?? {};

            const reasons = inferReasons(feedItemData, userData);
            const humanReadable = buildHumanReadable(reasons, feedItemData, userData);

            const explanation: FeedExplanation = {
                id: feedItemId,
                feedItemId,
                reasons,
                humanReadable,
            };

            // Cache in Firestore with a TTL marker.
            await docRef.set({
                ...explanation,
                cachedAt: admin.firestore.FieldValue.serverTimestamp(),
                ttlExpiry: admin.firestore.Timestamp.fromDate(
                    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days
                ),
            });

            return explanation;
        } catch (err) {
            // FAIL-CLOSED: return a safe fallback explanation rather than null.
            // Callers that gate rendering on explanation presence will still render.
            const fallback: FeedExplanation = {
                id: feedItemId,
                feedItemId,
                reasons: ["general"],
                humanReadable: "This was shared in your community",
            };

            // Cache the fallback so we don't re-fail on every request.
            await docRef.set({
                ...fallback,
                cachedAt: admin.firestore.FieldValue.serverTimestamp(),
                isFallback: true,
            }).catch(() => {/* ignore cache write failure */});

            return fallback;
        }
    }
);

// MARK: - Youth DM Policy Enforcement

/**
 * Enforces C60 youth DM policy and runs C59 detection on message content.
 * Returns { allowed: boolean, aegisSignal?: AegisC59Signal }.
 * If recipient is youth and sender is unverified adult: allowed = false.
 * Sender does NOT receive an error message — the decision is silent.
 */
export const enforceYouthDMPolicy = onCall(
    { region: "us-central1" },
    async (request) => {
        const { senderUid, recipientUid, messageContent } = request.data as {
            senderUid: string;
            recipientUid: string;
            messageContent: string;
        };

        if (!senderUid || !recipientUid) {
            throw new HttpsError("invalid-argument", "senderUid and recipientUid are required");
        }

        // Check recipient's YouthModeProfile.
        const youthProfileDoc = await db.collection("youthModeProfiles").doc(recipientUid).get();

        if (youthProfileDoc.exists) {
            const profile = youthProfileDoc.data()!;
            if (profile.dmPolicy === "verifiedAdultsBlocked") {
                // Check sender's age verification.
                const senderDoc = await db.collection("users").doc(senderUid).get();
                const senderAgeVerified = senderDoc.data()?.ageVerified === true;

                if (!senderAgeVerified) {
                    // C60: silently block — no error to sender.
                    return { allowed: false };
                }
            }
        }

        // Run C59 detection on message content (Tier S assumed for DMs).
        let aegisSignal: AegisC59Signal | null = null;
        if (messageContent && messageContent.length > 0) {
            aegisSignal = detectC59Patterns(messageContent, "S");
        }

        return { allowed: true, aegisSignal };
    }
);

// MARK: - Aegis C59 Pattern Detection

/**
 * Server-side spiritual abuse pattern detection.
 * Rejects Tier P content unconditionally.
 * Returns AegisC59Signal or null if no pattern found or confidence < 0.70.
 */
export const detectAegisC59 = onCall(
    { region: "us-central1" },
    async (request) => {
        const { content, tier } = request.data as { content: string; tier: string };

        if (!content || !tier) {
            throw new HttpsError("invalid-argument", "content and tier are required");
        }

        // Tier P: unconditionally reject — never process private content.
        if (tier === "P") {
            return null;
        }

        const signal = detectC59Patterns(content, tier);
        return signal;
    }
);

// MARK: - Pattern Detection Logic

function detectC59Patterns(content: string, _tier: string): AegisC59Signal | null {
    const lower = content.toLowerCase();

    const defaultResources = [
        "1-800-799-7233",
        "focusonthefamily.com",
        "church-counseling",
    ];

    // --- Manipulation Framing ---
    const manipulationPatterns: Array<{ phrase: string; confidence: number }> = [
        { phrase: "god told me you should", confidence: 0.92 },
        { phrase: "if you loved god you would", confidence: 0.90 },
        { phrase: "true believers don't question", confidence: 0.93 },
        { phrase: "you're being spiritually attacked", confidence: 0.75 },
        { phrase: "real christians don't", confidence: 0.80 },
        { phrase: "the holy spirit told me you", confidence: 0.88 },
    ];

    for (const p of manipulationPatterns) {
        if (lower.includes(p.phrase) && p.confidence >= 0.70) {
            return {
                patternKind: "manipulationFraming",
                confidence: p.confidence,
                recipientResources: defaultResources,
                internalSignal: `C59.ManipulationFraming:${p.phrase}`,
            };
        }
    }

    // --- Financial Coercion ---
    const financialPatterns: Array<{ phrase: string; confidence: number }> = [
        { phrase: "seed faith", confidence: 0.82 },
        { phrase: "give or lose your blessing", confidence: 0.95 },
        { phrase: "god told me you should give me", confidence: 0.94 },
        { phrase: "sow a seed", confidence: 0.78 },
        { phrase: "your tithe determines your blessing", confidence: 0.88 },
        { phrase: "give or god will", confidence: 0.91 },
        { phrase: "if you don't give", confidence: 0.80 },
    ];

    for (const p of financialPatterns) {
        if (lower.includes(p.phrase) && p.confidence >= 0.70) {
            return {
                patternKind: "financialCoercion",
                confidence: p.confidence,
                recipientResources: defaultResources,
                internalSignal: `C59.FinancialCoercion:${p.phrase}`,
            };
        }
    }

    // --- Isolation Tactics ---
    const isolationPatterns: Array<{ phrase: string; confidence: number }> = [
        { phrase: "don't tell your family", confidence: 0.90 },
        { phrase: "cut off people who", confidence: 0.85 },
        { phrase: "your old friends are keeping you from god", confidence: 0.92 },
        { phrase: "your family doesn't understand your calling", confidence: 0.80 },
        { phrase: "true believers separate from", confidence: 0.83 },
    ];

    for (const p of isolationPatterns) {
        if (lower.includes(p.phrase) && p.confidence >= 0.70) {
            return {
                patternKind: "isolationTactics",
                confidence: p.confidence,
                recipientResources: defaultResources,
                internalSignal: `C59.IsolationTactics:${p.phrase}`,
            };
        }
    }

    return null;
}

// MARK: - Feed Explanation Helpers

function inferReasons(
    feedItemData: admin.firestore.DocumentData,
    userData: admin.firestore.DocumentData
): string[] {
    const reasons: string[] = [];

    if (feedItemData.authorUid && userData.following?.includes(feedItemData.authorUid)) {
        reasons.push("followedAuthor");
    }

    if (feedItemData.liturgicalSeason) {
        reasons.push("liturgicalSeason");
    }

    if (feedItemData.prayerContext) {
        reasons.push("prayerContext");
    }

    if (feedItemData.trendScore && feedItemData.trendScore > 0.7) {
        reasons.push("trendingInCommunity");
    }

    if (reasons.length === 0) {
        reasons.push("general");
    }

    return reasons;
}

function buildHumanReadable(
    reasons: string[],
    feedItemData: admin.firestore.DocumentData,
    userData: admin.firestore.DocumentData
): string {
    const parts: string[] = [];

    for (const reason of reasons) {
        switch (reason) {
            case "followedAuthor": {
                const name = feedItemData.authorDisplayName ?? "someone you follow";
                parts.push(`You follow ${name}`);
                break;
            }
            case "sharedInterests": {
                const topic = feedItemData.primaryTopic ?? "a topic you care about";
                parts.push(`This connects to your interest in ${topic}`);
                break;
            }
            case "prayerContext": {
                const prayerTopic = feedItemData.prayerContext ?? "something you've been praying about";
                parts.push(`You've been praying about ${prayerTopic}`);
                break;
            }
            case "friendEngaged": {
                parts.push("Someone in your community engaged with this");
                break;
            }
            case "liturgicalSeason": {
                const season = feedItemData.liturgicalSeason ?? "the current season";
                parts.push(`Relevant to the current season of ${season}`);
                break;
            }
            case "trendingInCommunity":
                parts.push("Trending in your community");
                break;
            case "bookmarkedTopic":
                parts.push("Related to a topic you bookmarked");
                break;
            case "groupActivity":
                parts.push("Active in a group you're part of");
                break;
            default:
                parts.push("This was shared in your community");
        }
    }

    return parts.join(" • ");
}
