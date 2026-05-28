/**
 * explainVideoContent.ts
 *
 * Callable: explainVideoContent
 *   Generates an AI-powered explanation of a video post using its server-generated transcript.
 *
 * CONTRACT
 * ────────
 * Input  { postId: string, mediaId: string }
 * Output { explanation: string, themes: string[], scriptureRefs: string[], cachedAt: string }
 *
 * SECURITY
 * ────────
 * - Auth + App Check both enforced (enforceAppCheck: true).
 * - Server re-checks post visibility, block status, and flagged/removed state.
 * - Private/community-only posts deny non-members.
 * - Blocked, removed, or flagged content returns permission-denied — never explained.
 * - Transcript must exist (captionsGenerationState == "ready") — no client-side fake summaries.
 * - Client cannot write to any mediaMeta explanation field (Firestore rules enforce this).
 *
 * SAFETY
 * ──────
 * - Claude output is passed through a lightweight moderation filter before persisting.
 * - Overconfident spiritual claims ("God is telling you to…") are stripped.
 * - Filter fails closed: if moderation is uncertain, explanation is withheld.
 *
 * PERFORMANCE
 * ───────────
 * - Returns cached explanation if < 24 h old (no Claude call).
 * - Timeout: 55 s (hard margin under 60 s Cloud Run limit).
 * - Each media item explains independently; failures don't cascade.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {getBereanEntitlement} from "./berean/services/BereanEntitlementService";
import {enforceRateLimit, RATE_LIMITS} from "./rateLimit";

if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const EXPLANATION_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 h
const MAX_TRANSCRIPT_CHARS = 12_000;                   // ~3k tokens — keep cost bounded
const CLAUDE_MODEL = "claude-haiku-4-5-20251001";      // fast + cheap for summaries
const CLAUDE_MAX_TOKENS = 600;

// Patterns that indicate manipulative or overconfident spiritual language.
// These are stripped / cause a moderation block depending on density.
const OVERCONFIDENT_PATTERNS = [
    /god is (telling|commanding|requiring) you/i,
    /you must (tithe|give|donate|sow)/i,
    /this (video|message|word) is specifically for you/i,
    /if you don't (share|act|believe) (this|now)/i,
    /prophetic (word|declaration) for your (life|season)/i,
    /\b(guaranteed|certain(ly)?|definitely) (blessed|healed|prosperous)/i,
];

// ─── Exports ──────────────────────────────────────────────────────────────────

export const explainVideoContent = onCall(
    {
        secrets: [anthropicApiKey],
        enforceAppCheck: true,
        timeoutSeconds: 55,
        memory: "256MiB",
    },
    async (request) => {
        // ── Auth ──────────────────────────────────────────────────────────────
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }
        const callerId = request.auth.uid;

        // ── Input validation ──────────────────────────────────────────────────
        const {postId, mediaId} = (request.data ?? {}) as {postId?: string; mediaId?: string};
        if (!postId || typeof postId !== "string" || postId.trim().length === 0) {
            throw new HttpsError("invalid-argument", "postId is required.");
        }
        if (!mediaId || typeof mediaId !== "string" || mediaId.trim().length === 0) {
            throw new HttpsError("invalid-argument", "mediaId is required.");
        }

        const postRef = db.collection("posts").doc(postId);
        const mediaMetaRef = postRef.collection("mediaMeta").doc(mediaId);

        // ── Server-side visibility + safety gate ──────────────────────────────
        const [postSnap, mediaMetaSnap] = await Promise.all([
            postRef.get(),
            mediaMetaRef.get(),
        ]);

        if (!postSnap.exists) {
            throw new HttpsError("not-found", "Post not found.");
        }

        const post = postSnap.data()!;

        // Removed / flagged content must never be explained.
        if (post.removed === true || post.isRemoved === true) {
            throw new HttpsError("permission-denied", "Content is no longer available.");
        }
        if (post.flaggedForReview === true) {
            throw new HttpsError("permission-denied", "Content is under review.");
        }

        // Visibility check: private posts are only readable by their author.
        const visibility: string = post.visibility ?? "everyone";
        const authorId: string = post.authorId ?? post.userId ?? "";

        if (visibility === "private" && callerId !== authorId) {
            throw new HttpsError("permission-denied", "Content is private.");
        }

        // Community-only posts: caller must be a community member.
        if (visibility === "community" || visibility === "members") {
            const communityId: string = post.communityId ?? "";
            if (communityId) {
                const memberSnap = await db
                    .collection("communities").doc(communityId)
                    .collection("members").doc(callerId)
                    .get();
                if (!memberSnap.exists) {
                    throw new HttpsError("permission-denied", "Community members only.");
                }
            }
        }

        // Block check: if the post author has blocked this caller (or vice versa), deny.
        const [callerBlockedByAuthor, callerBlockedAuthor] = await Promise.all([
            db.collection("blockedUsers").doc(`${authorId}_${callerId}`).get(),
            db.collection("blockedUsers").doc(`${callerId}_${authorId}`).get(),
        ]);
        if (callerBlockedByAuthor.exists || callerBlockedAuthor.exists) {
            throw new HttpsError("permission-denied", "Content unavailable.");
        }

        // ── Transcript gate ───────────────────────────────────────────────────
        const mediaMeta = mediaMetaSnap.exists ? mediaMetaSnap.data()! : {};
        const captionsState: string = mediaMeta.captionsGenerationState ?? "unknown";

        if (captionsState !== "ready") {
            throw new HttpsError(
                "failed-precondition",
                captionsState === "generating"
                    ? "Transcript is still generating. Try again shortly."
                    : "Transcript not available for this video."
            );
        }

        // ── Cache check ───────────────────────────────────────────────────────
        const cachedAt: admin.firestore.Timestamp | undefined = mediaMeta.explanationCachedAt;
        if (
            cachedAt &&
            mediaMeta.explanationText &&
            Date.now() - cachedAt.toMillis() < EXPLANATION_CACHE_TTL_MS
        ) {
            return {
                explanation: mediaMeta.explanationText as string,
                themes: (mediaMeta.explanationThemes as string[]) ?? [],
                scriptureRefs: (mediaMeta.explanationScriptureRefs as string[]) ?? [],
                cachedAt: cachedAt.toDate().toISOString(),
            };
        }

        // ── Entitlement gate ──────────────────────────────────────────────────
        // Cache hits (above) are served to all tiers — AI cost is only incurred
        // on a fresh Claude call. Gate here so free users still see cached results.
        const entitlement = await getBereanEntitlement(callerId);
        if (entitlement.tier === "free") {
            throw new HttpsError("permission-denied", "Video explanations require an AMEN+ subscription.");
        }
        await enforceRateLimit(callerId, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);

        // ── Read transcript ───────────────────────────────────────────────────
        const captionTracksSnap = await mediaMetaRef
            .collection("captionTracks")
            .orderBy("createdAt", "desc")
            .limit(1)
            .get();

        if (captionTracksSnap.empty) {
            throw new HttpsError("failed-precondition", "Transcript not available for this video.");
        }

        const trackData = captionTracksSnap.docs[0].data();
        const rawTranscript: string =
            (trackData.editedTranscript as string | null) ??
            (trackData.generatedTranscript as string | null) ??
            "";

        if (rawTranscript.trim().length < 30) {
            throw new HttpsError("failed-precondition", "Transcript is too short to explain.");
        }

        const transcript = rawTranscript.slice(0, MAX_TRANSCRIPT_CHARS);

        // ── Call Claude ───────────────────────────────────────────────────────
        const apiKey = anthropicApiKey.value();
        if (!apiKey) {
            throw new HttpsError("internal", "AI service not configured.");
        }

        const promptText = buildExplainPrompt(transcript, post.title ?? "", authorId);

        let rawExplanation: string;
        let themes: string[] = [];
        let scriptureRefs: string[] = [];

        try {
            const result = await callClaude(apiKey, promptText);
            rawExplanation = result.explanation;
            themes = result.themes;
            scriptureRefs = result.scriptureRefs;
        } catch (err) {
            console.error("[explainVideoContent] Claude call failed:", err);
            throw new HttpsError("internal", "AI generation failed. Please try again.");
        }

        // ── Safety / moderation filter ────────────────────────────────────────
        const {passed, filtered} = moderateExplanation(rawExplanation);
        if (!passed) {
            // Fail closed — don't persist or return a flagged explanation.
            throw new HttpsError(
                "internal",
                "Explanation could not be generated safely. Please try again."
            );
        }

        // ── Persist to Firestore (server-owned fields only) ───────────────────
        const now = admin.firestore.FieldValue.serverTimestamp();
        await mediaMetaRef.set(
            {
                explanationText: filtered,
                explanationThemes: themes,
                explanationScriptureRefs: scriptureRefs,
                explanationGeneratedBy: "server",
                explanationCachedAt: now,
                explanationGenerationState: "ready",
                updatedAt: now,
            },
            {merge: true}
        );

        return {
            explanation: filtered,
            themes,
            scriptureRefs,
            cachedAt: new Date().toISOString(),
        };
    }
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

function buildExplainPrompt(transcript: string, title: string, _authorId: string): string {
    const titleLine = title ? `Video title: "${title}"\n\n` : "";
    return `You are a helpful assistant for a Christian community app. Analyze the following sermon or teaching video transcript and provide a clear, balanced explanation.

${titleLine}Transcript:
"""
${transcript}
"""

Respond ONLY with a valid JSON object in this exact format — no markdown, no extra text:
{
  "explanation": "<2-4 sentence neutral summary of the video's main message, accessible to someone who hasn't seen it>",
  "themes": ["<theme1>", "<theme2>", "<theme3>"],
  "scriptureRefs": ["<Book Chapter:Verse>", "..."]
}

Rules:
- Be accurate, balanced, and factual.
- Do not add spiritual directives not present in the transcript.
- Do not use first-person ("I believe", "you should").
- themes: 2–4 short topic labels (e.g. "Faith", "Prayer", "Forgiveness").
- scriptureRefs: only references explicitly mentioned in the transcript. Empty array if none.
- explanation: max 3 sentences.`;
}

interface ClaudeResult {
    explanation: string;
    themes: string[];
    scriptureRefs: string[];
}

async function callClaude(apiKey: string, prompt: string): Promise<ClaudeResult> {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        body: JSON.stringify({
            model: CLAUDE_MODEL,
            max_tokens: CLAUDE_MAX_TOKENS,
            messages: [{role: "user", content: prompt}],
        }),
    });

    if (!response.ok) {
        const body = await response.text();
        throw new Error(`Claude API ${response.status}: ${body.slice(0, 200)}`);
    }

    const data = (await response.json()) as {
        content?: Array<{type?: string; text?: string}>;
    };

    const text = data.content?.find((b) => b.type === "text")?.text ?? "";

    // Strip any markdown code fences Claude might add despite the prompt.
    const jsonText = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```\s*$/i, "").trim();

    let parsed: {explanation?: string; themes?: string[]; scriptureRefs?: string[]};
    try {
        parsed = JSON.parse(jsonText);
    } catch {
        throw new Error(`Claude returned non-JSON: ${jsonText.slice(0, 200)}`);
    }

    const explanation = typeof parsed.explanation === "string" ? parsed.explanation.trim() : "";
    const themes = Array.isArray(parsed.themes)
        ? parsed.themes.filter((t): t is string => typeof t === "string").slice(0, 5)
        : [];
    const scriptureRefs = Array.isArray(parsed.scriptureRefs)
        ? parsed.scriptureRefs.filter((r): r is string => typeof r === "string").slice(0, 10)
        : [];

    if (!explanation) {
        throw new Error("Claude returned empty explanation.");
    }

    return {explanation, themes, scriptureRefs};
}

interface ModerationResult {
    passed: boolean;
    filtered: string;
}

function moderateExplanation(text: string): ModerationResult {
    // Count how many overconfident-language patterns are present.
    const hitCount = OVERCONFIDENT_PATTERNS.filter((p) => p.test(text)).length;

    // Two or more hits → fail closed (don't return anything).
    if (hitCount >= 2) {
        return {passed: false, filtered: ""};
    }

    // One hit → strip the offending sentence and return the rest.
    let filtered = text;
    if (hitCount === 1) {
        // Remove sentences containing the pattern.
        filtered = text
            .split(/(?<=[.!?])\s+/)
            .filter((sentence) => !OVERCONFIDENT_PATTERNS.some((p) => p.test(sentence)))
            .join(" ")
            .trim();
    }

    // Reject if the remaining text is too short to be useful after stripping.
    if (filtered.length < 20) {
        return {passed: false, filtered: ""};
    }

    return {passed: true, filtered};
}
