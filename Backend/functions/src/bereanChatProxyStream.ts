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
import * as admin from "firebase-admin";
import {enforceRateLimit, RATE_LIMITS} from "./rateLimit";
import {buildSensitiveTopicPolicyBlock} from "./berean/prompts/sensitiveTopicPolicy";
import type {SensitivityFlag, TopicClass} from "./berean/models/berean";
import {ensureAIDisclosure} from "./berean/services/aiDisclosure";
import {validateRawTextOutput} from "./berean/services/SafetyValidator";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// ── Types ────────────────────────────────────────────────────────────────────

interface StreamRequest {
    message: string;
    maxTokens?: number;
    mode?: string;
    modelId?: string;
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

type BereanTierLocal = "free" | "plus" | "pro" | "founder";

const PROD_BEREAN_MODELS = {
    core: "claude-haiku-4-5-20251001",
    standard: "claude-sonnet-4-6",
    deep: "claude-opus-4-7",
} as const;

const PROD_TIER_CEILING: Record<BereanTierLocal, string> = {
    free: PROD_BEREAN_MODELS.core,
    plus: PROD_BEREAN_MODELS.standard,
    pro: PROD_BEREAN_MODELS.deep,
    founder: PROD_BEREAN_MODELS.deep,
};

const PROD_MODEL_PRECEDENCE: Record<string, number> = {
    [PROD_BEREAN_MODELS.core]: 0,
    "claude-3-haiku-20240307": 0,
    [PROD_BEREAN_MODELS.standard]: 1,
    "claude-3-5-sonnet-20241022": 1,
    [PROD_BEREAN_MODELS.deep]: 2,
    "claude-3-opus-20240229": 2,
};

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

async function getBereanTierForUser(uid: string): Promise<BereanTierLocal> {
    try {
        const subscription = await admin.firestore().collection("userSubscriptions").doc(uid).get();
        const subData = subscription.data() ?? {};
        const tier = (subData.tier ?? subData.plan ?? subData.status) as string | undefined;
        const valid: BereanTierLocal[] = ["free", "plus", "pro", "founder"];
        return valid.includes(tier as BereanTierLocal) ? (tier as BereanTierLocal) : "free";
    } catch {
        return "free";
    }
}

function resolveEntitledModel(
    clientModelId: string | undefined,
    mode: string,
    tier: BereanTierLocal
): { modelId: string; downgraded: boolean } {
    const ceiling = PROD_TIER_CEILING[tier];

    let desired: string;
    if (clientModelId && clientModelId.trim().length > 0) {
        const id = clientModelId.trim();
        if (id === "deep" || id.includes("opus")) desired = PROD_BEREAN_MODELS.deep;
        else if (id === "standard" || id.includes("sonnet")) desired = PROD_BEREAN_MODELS.standard;
        else desired = PROD_BEREAN_MODELS.core;
    } else if (["scholar", "debater", "strategist", "deep_study"].includes(mode)) {
        desired = PROD_BEREAN_MODELS.standard;
    } else {
        desired = PROD_BEREAN_MODELS.core;
    }

    const desiredPrec = PROD_MODEL_PRECEDENCE[desired] ?? 0;
    const ceilingPrec = PROD_MODEL_PRECEDENCE[ceiling] ?? 0;
    const downgraded = desiredPrec > ceilingPrec;
    return { modelId: downgraded ? ceiling : desired, downgraded };
}

async function reserveStreamQuota(uid: string, bereanTier: BereanTierLocal): Promise<void> {
    const today = new Date().toISOString().slice(0, 10).replace(/-/g, "");
    const ref = admin.firestore()
        .collection("aiUsage").doc(uid).collection("daily").doc(today);

    await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists ? snap.data() : {};
        const current = Number(data?.requestCount ?? 0);
        const tier = bereanTier === "free" ? "free" : "pro";
        const dailyLimit = tier === "free" ? 15 : 150;
        if (current >= dailyLimit) {
            throw new Error("stream_quota_exceeded");
        }
        tx.set(ref, {
            uid,
            requestCount: current + 1,
            lastStreamRequestAt: admin.firestore.FieldValue.serverTimestamp(),
            // streamRequestCount is legacy telemetry only; quota arithmetic uses requestCount.
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
    });
}

// ── Function ─────────────────────────────────────────────────────────────────

export const bereanChatProxyStream = onRequest(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
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

        const appCheckToken = req.header("X-Firebase-AppCheck");
        if (!appCheckToken) {
            res.status(401).json({error: "Missing App Check token"});
            return;
        }
        try {
            await admin.appCheck().verifyToken(appCheckToken);
        } catch {
            res.status(401).json({error: "Invalid App Check token"});
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
        const bereanTier = await getBereanTierForUser(uid);
        try {
            await enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);
            await reserveStreamQuota(uid, bereanTier);
        } catch {
            res.status(429).json({error: "Rate limit exceeded"});
            return;
        }

        // ── Validate input ────────────────────────────────────────────────────
        const body = req.body as StreamRequest;
        const {
            message,
            maxTokens = 2000,
            mode = "shepherd",
            modelId,
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
            const disclosedCrisisResponse = ensureAIDisclosure(CRISIS_SAFE_RESPONSE);
            for (const word of disclosedCrisisResponse.split(" ")) {
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

        // ── Model selection ───────────────────────────────────────────────────
        const {modelId: model, downgraded} = resolveEntitledModel(modelId, mode, bereanTier);
        if (downgraded) {
            console.info("ℹ️ berean_stream_model_downgraded", {
                tier: bereanTier,
                granted: model,
            });
        }

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
                const errText = await anthropicRes.text().catch(() => "unknown");
                console.error(`❌ [bereanChatProxyStream] Anthropic error ${anthropicRes.status}:`, errText);
                res.write(`data: ${JSON.stringify({error: "upstream_error"})}\n\n`);
                res.end();
                return;
            }

            const reader = anthropicRes.body!.getReader();
            const decoder = new TextDecoder();
            let buffer = "";
            let responseText = "";

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
                                responseText += text;
                            }
                        } else if (event.type === "message_stop") {
                            // Emission happens after full validation below.
                        }
                    } catch {
                        // Skip malformed SSE lines
                    }
                }
            }

            const validation = validateRawTextOutput(responseText);
            const safeText = ensureAIDisclosure(
                validation.isValid ? responseText : validation.sanitizedText
            );
            res.write(`data: ${JSON.stringify({delta: safeText})}\n\n`);
            res.write(`data: ${JSON.stringify({
                done: true,
                aiDisclosureApplied: true,
                safetyStatus: validation.isValid ? "passed" : "sanitized",
            })}\n\n`);
            res.end();
        } catch (error: unknown) {
            const isAbort =
                error instanceof Error && error.name === "AbortError";
            if (!isAbort) {
                console.error("❌ [bereanChatProxyStream] Stream error:", error);
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
