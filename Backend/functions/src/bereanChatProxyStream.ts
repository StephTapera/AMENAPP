/**
 * bereanChatProxyStream.ts
 *
 * True SSE streaming proxy for Berean AI.
 *
 * Unlike bereanChatProxy (Firebase callable, full-response), this HTTP function
 * uses Anthropic's streaming API and forwards server-sent events to the client
 * as they arrive. The key improvements over the callable approach:
 *
 *   1. First token appears in ~300 ms on a good network instead of waiting for
 *      the full response (was 2–5 s for a typical Berean reply).
 *   2. Cancellation propagates to the backend: when the iOS URLSession task is
 *      cancelled (user navigates away), the client connection drops. The
 *      req.on("close") handler fires the AbortController, which cancels the
 *      in-flight Anthropic fetch — stopping token consumption immediately.
 *   3. Cold starts are the same as the callable, but perceived latency is much
 *      lower because text begins arriving before generation completes.
 *
 * Auth: Manual Firebase ID token verification (Authorization: Bearer <idToken>).
 *       The callable SDK is not used so we can hold an open HTTP stream.
 *
 * SSE event shapes emitted to client:
 *   data: {"delta": "text chunk"}      — one or more chars from Anthropic stream
 *   data: {"done": true}               — stream complete
 *   data: {"error": "reason"}          — upstream error (stream aborted)
 *
 * URL (after deployment):
 *   https://us-central1-amen-5e359.cloudfunctions.net/bereanChatProxyStream
 */

import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions";
import * as admin from "firebase-admin";
import {enforceRateLimit, RATE_LIMITS, checkGlobalCircuitBreaker, incrementGlobalAICounter} from "./rateLimit";
import {checkAndIncrementDailyRateLimit, BEREAN_DAILY_LIMITS} from "./rateLimitHelper";
import {buildSensitiveTopicPolicyBlock} from "./berean/prompts/sensitiveTopicPolicy";
import type {SensitivityFlag, TopicClass} from "./berean/models/berean";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ── Types ────────────────────────────────────────────────────────────────────

interface StreamRequest {
    message: string;
    systemPromptSuffix?: string;
    maxTokens?: number;
    mode?: string;
    conversationId?: string;
    responseMode?: string;
    sensitivityFlags?: string[];
    escalationTriggered?: boolean;
    authorityEscalationRequired?: boolean;
    callData?: {
        conversationId?: string;
        memoryScope?: string;
        faithJourneyStage?: string;
        userPersona?: string;
        scriptureTranslation?: string;
        responseMode?: string;
        sensitivityFlags?: string[];
        postContext?: {
            postId: string;
            authorId: string;
            authorName: string;
            previewText: string;
            bodyText?: string;
            category: string;
            verseReference?: string;
            verseText?: string;
            mediaSummary?: string;
            isSensitive: boolean;
        };
    };
}

interface SensitivityContext {
    flags: SensitivityFlag[];
    topicClass: TopicClass | null;
}

// ── Crisis short-circuit ─────────────────────────────────────────────────────
// Same keywords and safe response as bereanChatProxy.ts (kept in sync).

const CRISIS_KEYWORDS = [
    "end it", "end my life", "kill myself", "want to die", "can't go on",
    "cannot go on", "no reason to live", "take my life", "don't want to be here",
    "dont want to be here", "don't want to exist", "dont want to exist",
    "wish i was dead", "nothing to live for", "better off dead",
    "better off without me", "going to hurt myself", "hurt myself",
    "self harm", "self-harm", "cut myself", "overdose", "jump off",
    "hang myself", "no point anymore", "can't take it anymore",
    "cant take it anymore", "give up on life", "end the pain",
    "suicidal", "suicide", "what's the point", "whats the point",
];

const ABUSE_KEYWORDS = [
    "my husband hits me", "my wife hits me", "he hits me", "she hits me",
    "abusive relationship", "domestic violence", "he threatens me",
    "she threatens me", "i am being abused", "spiritual abuse",
];

const DOCTRINAL_DISPUTE_KEYWORDS = [
    "predestination", "women in ministry", "speaking in tongues",
    "charismatic gifts", "calvinism", "arminian", "baptism saves",
    "once saved always saved",
];

const CRISIS_SAFE_RESPONSE = [
    "I care about you and I want you to be safe right now.",
    "",
    "If you're in crisis, please reach out immediately:",
    "• 988 Suicide & Crisis Lifeline — call or text 988",
    "• Crisis Text Line — text HOME to 741741",
    "• International Association for Suicide Prevention — https://www.iasp.info/resources/Crisis_Centres/",
    "",
    "You are not alone. A real person who can help is just a call or text away.",
    "Please reach out to them before we continue.",
].join("\n");

// ── Helpers ──────────────────────────────────────────────────────────────────

function containsAny(text: string, phrases: string[]): boolean {
    return phrases.some((p) => text.includes(p));
}

function analyzeSensitivity(
    message: string,
    callData?: StreamRequest["callData"]
): SensitivityContext {
    const lower = message.toLowerCase();
    const flags = new Set<SensitivityFlag>();
    const callDataFlags = callData?.sensitivityFlags ?? [];

    if (callDataFlags.includes("self_harm") || containsAny(lower, CRISIS_KEYWORDS)) {
        flags.add("crisis_escalation");
    }
    if (containsAny(lower, ABUSE_KEYWORDS)) {
        flags.add("pastoral_escalation");
    }
    if (containsAny(lower, DOCTRINAL_DISPUTE_KEYWORDS)) {
        flags.add("controversial_doctrine");
    }

    let topicClass: TopicClass | null = null;
    if (containsAny(lower, CRISIS_KEYWORDS)) topicClass = "suicidality";
    else if (containsAny(lower, ABUSE_KEYWORDS)) topicClass = "abuse_disclosure";
    else if (containsAny(lower, DOCTRINAL_DISPUTE_KEYWORDS)) topicClass = "doctrinal_dispute";

    return {flags: Array.from(flags), topicClass};
}

function buildBaseSystemPrompt(mode: string): string {
    const base = `You are Berean AI, a compassionate Biblical assistant for the AMEN Christian social app.
Your purpose is to help believers understand Scripture, grow in faith, and apply God's Word to their lives.

Core Principles:
- Always cite Scripture references (e.g., John 3:16, Psalm 23:1-6)
- Be encouraging, compassionate, and Christ-centered
- Acknowledge multiple theological perspectives when appropriate
- Refer complex theological questions to local church leaders
- Never claim to replace personal Bible study, pastoral guidance, therapy, or clinical care
- Never speak as if you have direct divine authority over a user's life
- For abuse, suicidality, or immediate safety concerns, prioritize human safety and local support
- For disputed doctrine, present faithful Christian differences with humility`;

    const modeAddition: Record<string, string> = {
        shepherd: "\n\nMode: Shepherd — Be encouraging and pastoral. Guide users gently toward Scripture.",
        scholar: "\n\nMode: Scholar — Provide deeper theological analysis with historical context and cross-references.",
        debater: "\n\nMode: Debater — Engage in respectful theological dialogue, exploring different perspectives.",
        builder: "\n\nMode: Builder — Be technical, practical, systems-oriented, direct.",
        strategist: "\n\nMode: Strategist — Focus on business, leverage, sequencing, risk, metrics.",
        creator: "\n\nMode: Creator — Be imaginative, clear, useful, compelling.",
        coach: "\n\nMode: Coach — Be concise, motivating, practical, action-oriented.",
        prayer: "\n\nMode: Prayer Guide — Help users craft meaningful prayers based on Scripture.",
    };

    return base + (modeAddition[mode] ?? modeAddition.shepherd);
}

function buildCallDataBlock(callData?: StreamRequest["callData"]): string {
    if (!callData) return "";
    const parts: string[] = [];

    if (callData.faithJourneyStage) {
        parts.push(`USER CONTEXT:\nThis user identifies as ${callData.faithJourneyStage}. Calibrate vocabulary accordingly.`);
    }
    if (callData.userPersona) {
        parts.push(`The user's persona or role is ${callData.userPersona}.`);
    }
    if (callData.scriptureTranslation) {
        parts.push(`Preferred Scripture translation: ${callData.scriptureTranslation}.`);
    }
    if (callData.memoryScope) {
        parts.push(`Memory scope for this request: ${callData.memoryScope}.`);
    }
    if (callData.postContext) {
        const pc = callData.postContext;
        const lines = [
            "POST CONTEXT:",
            `- Author: ${pc.authorName}`,
            `- Category: ${pc.category}`,
            `- Summary: ${pc.previewText}`,
        ];
        if (pc.bodyText) lines.push(`- Post body: ${pc.bodyText}`);
        if (pc.verseReference) lines.push(`- Scripture: ${pc.verseReference}`);
        if (pc.verseText) lines.push(`- Scripture text: ${pc.verseText}`);
        if (pc.isSensitive) lines.push("- Sensitive: do not reveal details beyond the summary.");
        parts.push(lines.join("\n"));
    }

    return parts.join("\n\n");
}

// ── Function ─────────────────────────────────────────────────────────────────

export const bereanChatProxyStream = onRequest(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
        minInstances: 1,
        // invoker: "public" so Firebase Auth token verification is manual (below).
        invoker: "public",
    },
    async (req, res) => {
        // CORS — needed for web; iOS doesn't send preflight but web does.
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");

        if (req.method === "OPTIONS") {
            res.status(204).send("");
            return;
        }

        if (req.method !== "POST") {
            res.status(405).json({error: "Method not allowed"});
            return;
        }

        // ── Auth ──────────────────────────────────────────────────────────────
        const authHeader = (req.headers.authorization ?? "") as string;
        if (!authHeader.startsWith("Bearer ")) {
            res.status(401).json({error: "Missing auth token"});
            return;
        }
        let uid: string;
        try {
            const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
            uid = decoded.uid;
        } catch {
            res.status(401).json({error: "Invalid auth token"});
            return;
        }

        // ── Rate limiting ─────────────────────────────────────────────────────
        try {
            await enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);
        } catch {
            res.status(429).json({error: "Rate limit exceeded"});
            return;
        }

        // SERVER-SIDE Berean-specific daily rate limit (UTC calendar-day window).
        // Stored under users/{uid}/rateLimits/ — authoritative backend guard.
        // Free tier: 20 Berean streaming requests per UTC day.
        try {
            await checkAndIncrementDailyRateLimit(uid, BEREAN_DAILY_LIMITS.bereanChat);
        } catch {
            res.status(429).json({error: "Daily Berean limit reached. Resets at midnight UTC."});
            return;
        }

        // Global circuit breaker — project-wide daily ceiling.
        try {
            await checkGlobalCircuitBreaker();
        } catch {
            res.status(429).json({error: "AI service is taking a brief rest for today. Please try again in a few hours."});
            return;
        }

        const requestStart = Date.now();

        // ── Validate input ────────────────────────────────────────────────────
        const body = req.body as StreamRequest;
        const {
            message,
            // systemPromptSuffix is accepted but never forwarded to the model prompt
            // (prompt-injection mitigation — C-01 security fix).
            maxTokens = 2000,
            mode = "shepherd",
            callData,
        } = body;

        if (!message || typeof message !== "string" || message.trim().length === 0) {
            res.status(400).json({error: "Message required"});
            return;
        }
        if (message.length > 4000) {
            res.status(400).json({error: "Message exceeds 4000 character limit"});
            return;
        }

        const apiKey = anthropicApiKey.value();

        // ── Crisis short-circuit (before streaming headers are sent) ──────────
        const lower = message.toLowerCase();
        const isCrisis =
            (body.sensitivityFlags ?? []).includes("self_harm") ||
            body.escalationTriggered === true ||
            callData?.sensitivityFlags?.includes("self_harm") ||
            containsAny(lower, CRISIS_KEYWORDS);

        if (isCrisis) {
            res.setHeader("Content-Type", "text/event-stream");
            res.setHeader("Cache-Control", "no-cache");
            res.setHeader("X-Accel-Buffering", "no");
            res.flushHeaders();
            // Stream the crisis response word-by-word so the view renders it
            for (const word of CRISIS_SAFE_RESPONSE.split(" ")) {
                res.write(`data: ${JSON.stringify({delta: word + " "})}\n\n`);
            }
            res.write(`data: ${JSON.stringify({done: true})}\n\n`);
            res.end();
            return;
        }

        // ── Build system prompt ───────────────────────────────────────────────
        const sensitivityCtx = analyzeSensitivity(message, callData);
        let systemPrompt = buildBaseSystemPrompt(mode);

        const sensitiveBlock = buildSensitiveTopicPolicyBlock(
            sensitivityCtx.flags,
            sensitivityCtx.topicClass
        );
        if (sensitiveBlock) systemPrompt += `\n\n${sensitiveBlock}`;

        const callDataBlock = buildCallDataBlock(callData);
        if (callDataBlock) systemPrompt += `\n\n${callDataBlock}`;

        // systemPromptSuffix is NOT appended — client-supplied text in the system prompt
        // is a prompt-injection vector. Mode customisation is handled entirely by
        // buildBaseSystemPrompt(mode) and the sensitivity/callData blocks above.

        // ── Model selection ───────────────────────────────────────────────────
        const model = mode === "scholar" || mode === "debater"
            ? "claude-3-5-sonnet-20241022"
            : "claude-3-haiku-20240307";

        // ── Set SSE headers ───────────────────────────────────────────────────
        res.setHeader("Content-Type", "text/event-stream");
        res.setHeader("Cache-Control", "no-cache");
        res.setHeader("Connection", "keep-alive");
        res.setHeader("X-Accel-Buffering", "no"); // prevent nginx buffering
        res.flushHeaders();

        // ── Abort Anthropic request if client disconnects ─────────────────────
        const controller = new AbortController();
        req.on("close", () => {
            controller.abort();
        });

        // ── Stream from Anthropic ─────────────────────────────────────────────
        try {
            const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01",
                },
                body: JSON.stringify({
                    model,
                    max_tokens: Math.min(maxTokens, 2000),
                    temperature: 0.7,
                    stream: true,
                    system: systemPrompt,
                    messages: [{role: "user", content: message}],
                }),
                signal: controller.signal,
            });

            if (!anthropicRes.ok) {
                const errText = await anthropicRes.text().catch((err: unknown) => { logger.error("bereanChatProxyStream error", { error: err instanceof Error ? err.message : String(err) }); return "unknown"; });
                logger.error("bereanChatProxyStream upstream error", { status: anthropicRes.status, errText });
                res.write(`data: ${JSON.stringify({error: "upstream_error"})}\n\n`);
                res.end();
                return;
            }

            const reader = anthropicRes.body!.getReader();
            const decoder = new TextDecoder();
            let buffer = "";

            while (true) {
                const {done, value} = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, {stream: true});
                const lines = buffer.split("\n");
                buffer = lines.pop() ?? "";

                for (const line of lines) {
                    if (!line.startsWith("data: ")) continue;
                    const rawData = line.slice(6).trim();
                    if (rawData === "[DONE]") continue;

                    try {
                        const event = JSON.parse(rawData) as Record<string, unknown>;
                        if (
                            event.type === "content_block_delta" &&
                            (event.delta as Record<string, unknown>)?.type === "text_delta"
                        ) {
                            const text = (event.delta as Record<string, unknown>).text as string;
                            if (text) {
                                res.write(`data: ${JSON.stringify({delta: text})}\n\n`);
                            }
                        } else if (event.type === "message_stop") {
                            res.write(`data: ${JSON.stringify({done: true})}\n\n`);
                        }
                    } catch {
                        // Skip malformed SSE lines
                    }
                }
            }

            // Structured telemetry — no UID, no message content.
            logger.info("berean_stream_succeeded", {
                mode,
                inputLength: message.length,
                latencyMs: Date.now() - requestStart,
                sensitive: (callData?.sensitivityFlags ?? []).length > 0,
            });
            // Fire-and-forget global counter increment.
            incrementGlobalAICounter().catch(() => {});

            res.end();
        } catch (error: unknown) {
            const isAbort =
                error instanceof Error && error.name === "AbortError";
            if (!isAbort) {
                logger.error("berean_stream_error", {
                    errorType: error instanceof Error ? error.name : "unknown",
                    latencyMs: Date.now() - requestStart,
                });
                try {
                    res.write(`data: ${JSON.stringify({error: "stream_error"})}\n\n`);
                } catch {
                    // Response already closed
                }
            }
            res.end();
        }
    }
);
