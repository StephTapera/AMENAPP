/**
 * bereanChatProxyStream.ts
 *
 * True SSE streaming proxy for Berean AI.
 * Called by ClaudeService.swift's streamProxyResponse() via URLSession.bytes().
 *
 * Security model (all checks server-side):
 *   1. Method guard (POST only)
 *   2. App Check: X-Firebase-AppCheck header verified
 *   3. Auth: Firebase ID token (Authorization: Bearer) verified
 *   4. Rate limit: per-user per-minute bucket
 *   5. Daily quota: per-user per-day, tier-based limit
 *   6. Input validation: message length, type
 *   7. Model entitlement: tier ceiling enforced before LLM call
 *   8. Output safety: validateRawTextOutput on assembled response
 */

import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import {
    enforceBereanRateLimit,
    enforceBereanDailyQuota,
    getBereanUserTier,
    BereanTier,
} from "./berean/shared/rateLimit";
import { validateRawTextOutput } from "./berean/services/SafetyValidator";
import { buildSensitiveTopicPolicyBlock } from "./berean/prompts/sensitiveTopicPolicy";
import type { SensitivityFlag, TopicClass } from "./berean/models/berean";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const BEREAN_MODELS = {
    core: "claude-haiku-4-5-20251001",
    standard: "claude-sonnet-4-6",
    deep: "claude-opus-4-7",
    coreFallback: "claude-3-haiku-20240307",
    standardFallback: "claude-3-5-sonnet-20241022",
} as const;

const TIER_CEILING: Record<BereanTier, string> = {
    free: BEREAN_MODELS.core,
    plus: BEREAN_MODELS.standard,
    pro: BEREAN_MODELS.deep,
    founder: BEREAN_MODELS.deep,
};

const MODEL_PRECEDENCE: Record<string, number> = {
    [BEREAN_MODELS.core]: 0,
    [BEREAN_MODELS.coreFallback]: 0,
    [BEREAN_MODELS.standard]: 1,
    [BEREAN_MODELS.standardFallback]: 1,
    [BEREAN_MODELS.deep]: 2,
};

export const bereanChatProxyStream = onRequest(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 120,
        memory: "256MiB",
        cors: false,
    },
    async (req, res) => {
        // ── 1. Method ─────────────────────────────────────────────────────────
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        // ── 2. App Check ──────────────────────────────────────────────────────
        const appCheckToken = req.header("X-Firebase-AppCheck");
        if (!appCheckToken) {
            console.warn("⚠️ bereanChatProxyStream: missing App Check token");
            res.status(401).json({ error: "App Check attestation required." });
            return;
        }
        try {
            await admin.appCheck().verifyToken(appCheckToken);
        } catch (err) {
            console.warn("⚠️ bereanChatProxyStream: invalid App Check token", err);
            res.status(401).json({ error: "Invalid App Check token." });
            return;
        }

        // ── 3. Auth ───────────────────────────────────────────────────────────
        const authHeader = req.header("Authorization");
        if (!authHeader?.startsWith("Bearer ")) {
            res.status(401).json({ error: "Authentication required." });
            return;
        }
        const idToken = authHeader.slice(7);
        let uid: string;
        try {
            const decoded = await admin.auth().verifyIdToken(idToken);
            uid = decoded.uid;
        } catch (err) {
            console.warn("⚠️ bereanChatProxyStream: invalid auth token", err);
            res.status(401).json({ error: "Invalid authentication token." });
            return;
        }

        // ── 4. Parse body ─────────────────────────────────────────────────────
        const body = req.body as Record<string, unknown>;
        const message = body.message as string | undefined;
        const mode = (body.mode as string | undefined) ?? "shepherd";
        const selectedMode = body.selectedMode as string | undefined;
        const maxTokens = Math.min(Number(body.maxTokens ?? 2000), 2000);
        const temperature = Math.min(Math.max(Number(body.temperature ?? 0.7), 0), 1);
        const systemPromptSuffix = body.systemPromptSuffix as string | undefined;
        const conversationHistory = (
            body.conversationHistory as Array<{ role: string; content: string }> | undefined
        ) ?? [];

        if (!message || typeof message !== "string" || message.trim().length === 0) {
            res.status(400).json({ error: "Message is required." });
            return;
        }
        if (message.length > 4000) {
            res.status(400).json({ error: "Message exceeds maximum length of 4000 characters." });
            return;
        }

        // ── 5. Rate limit ─────────────────────────────────────────────────────
        try {
            await enforceBereanRateLimit(uid, "berean_chat_proxy");
        } catch (err) {
            if (err instanceof Error && err.name === "BereanRateLimitError") {
                console.info("ℹ️ berean_rate_limit_hit", { uid, mode });
                res.status(429).json({ error: "Too many requests. Please wait a moment." });
                return;
            }
            throw err;
        }

        // ── 6. Tier + daily quota ─────────────────────────────────────────────
        const userTier = await getBereanUserTier(uid);
        let quotaInfo: { messagesUsed: number; dailyLimit: number } | null = null;
        try {
            quotaInfo = await enforceBereanDailyQuota(uid, userTier);
        } catch (err) {
            if (err instanceof Error && err.name === "BereanDailyQuotaError") {
                console.info("ℹ️ berean_daily_quota_hit", { uid, tier: userTier });
                res.status(429).json({
                    error: "Daily Berean message limit reached. Upgrade your plan for more messages.",
                    quotaExceeded: true,
                });
                return;
            }
            throw err;
        }

        // ── 7. Model entitlement ──────────────────────────────────────────────
        const ceiling = TIER_CEILING[userTier];
        const clientModelHint = selectedMode ?? (body.modelId as string | undefined);

        let desiredModel: string;
        if (clientModelHint && clientModelHint.trim().length > 0) {
            const hint = clientModelHint.trim();
            if (hint === "deep" || hint.includes("opus")) desiredModel = BEREAN_MODELS.deep;
            else if (hint === "standard" || hint.includes("sonnet")) desiredModel = BEREAN_MODELS.standard;
            else desiredModel = BEREAN_MODELS.core;
        } else if (
            mode === "scholar" || mode === "debater" ||
            mode === "strategist" || mode === "deep_study"
        ) {
            desiredModel = BEREAN_MODELS.standard;
        } else {
            desiredModel = BEREAN_MODELS.core;
        }

        const desiredPrecedence = MODEL_PRECEDENCE[desiredModel] ?? 0;
        const ceilingPrecedence = MODEL_PRECEDENCE[ceiling] ?? 0;
        let finalModel = desiredModel;
        let modelDowngraded = false;

        if (desiredPrecedence > ceilingPrecedence) {
            finalModel = ceiling;
            modelDowngraded = true;
            console.info("ℹ️ berean_model_downgraded", {
                uid,
                requested: desiredModel,
                granted: ceiling,
                tier: userTier,
            });
        }

        const fallbackModel = finalModel.includes("opus")
            ? BEREAN_MODELS.standardFallback
            : finalModel.includes("sonnet")
                ? BEREAN_MODELS.coreFallback
                : BEREAN_MODELS.standardFallback;

        // ── 8. Build system prompt ─────────────────────────────────────────────
        const apiKey = anthropicApiKey.value();
        if (!apiKey) {
            res.status(500).json({ error: "Berean AI not configured." });
            return;
        }

        let systemPrompt = buildBereanSystemPrompt(mode);

        const callData = body.callData as Record<string, unknown> | undefined;
        const sensitivityFlags = (callData?.sensitivityFlags as string[] | undefined) ?? [];
        const policyBlock = buildSensitiveTopicPolicyBlock(
            sensitivityFlags as unknown as SensitivityFlag[],
            null as unknown as TopicClass
        );
        if (policyBlock) systemPrompt += `\n\n${policyBlock}`;

        if (systemPromptSuffix?.trim()) {
            systemPrompt += `\n\n${systemPromptSuffix.trim()}`;
        }

        // ── 9. Condense history ───────────────────────────────────────────────
        const condensedHistory = condenseHistory(conversationHistory, 1300);
        const messages: Array<{ role: "user" | "assistant"; content: string }> = [
            ...condensedHistory,
            { role: "user", content: message },
        ];

        // ── 10. SSE headers ───────────────────────────────────────────────────
        res.setHeader("Content-Type", "text/event-stream");
        res.setHeader("Cache-Control", "no-cache");
        res.setHeader("Connection", "keep-alive");
        res.setHeader("X-Accel-Buffering", "no");
        res.flushHeaders();

        // ── 11. Stream from Anthropic ─────────────────────────────────────────
        const controller = new AbortController();
        req.on("close", () => controller.abort());

        let assembled = "";
        let modelUsed = finalModel;

        try {
            const streamResult = await callAnthropicStream({
                apiKey,
                model: finalModel,
                fallbackModel,
                maxTokens,
                temperature,
                systemPrompt,
                messages,
                signal: controller.signal,
                onChunk: (text) => {
                    assembled += text;
                    res.write(`data: ${JSON.stringify({ delta: text })}\n\n`);
                },
            });
            modelUsed = streamResult.modelUsed;
        } catch (err) {
            if ((err as Error)?.name === "AbortError") {
                res.end();
                return;
            }
            console.error("❌ bereanChatProxyStream LLM error:", err);
            res.write(`data: ${JSON.stringify({ error: "AI service error. Please try again." })}\n\n`);
            res.end();
            return;
        }

        // ── 12. Safety validation ─────────────────────────────────────────────
        if (assembled.trim()) {
            const validated = validateRawTextOutput(assembled);
            if (!validated.isValid) {
                console.warn("⚠️ Stream output safety violation", {
                    uid,
                    violations: validated.violations,
                });
            }
        }

        // ── 13. Terminal done event ───────────────────────────────────────────
        const deepCreditsRemaining =
            userTier === "plus" && quotaInfo
                ? Math.max(0, quotaInfo.dailyLimit - quotaInfo.messagesUsed)
                : null;

        res.write(
            `data: ${JSON.stringify({
                done: true,
                acceptedMode: modelTierLabel(modelUsed),
                fallbackMode: modelDowngraded ? modelTierLabel(desiredModel) : null,
                entitlementRequired: modelDowngraded,
                quotaExceeded: false,
                deepCreditsRemaining,
            })}\n\n`
        );

        res.end();
    }
);

// ── Anthropic streaming helper ─────────────────────────────────────────────

async function callAnthropicStream(params: {
    apiKey: string;
    model: string;
    fallbackModel: string;
    maxTokens: number;
    temperature: number;
    systemPrompt: string;
    messages: Array<{ role: "user" | "assistant"; content: string }>;
    signal: AbortSignal;
    onChunk: (text: string) => void;
}): Promise<{ modelUsed: string }> {
    const attemptStream = async (model: string): Promise<boolean> => {
        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": params.apiKey,
                "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
                model,
                max_tokens: params.maxTokens,
                temperature: params.temperature,
                stream: true,
                system: params.systemPrompt,
                messages: params.messages,
            }),
            signal: params.signal,
        });

        if (!response.ok) {
            const shouldFallback =
                response.status >= 500 || response.status === 429 || response.status === 529;
            if (shouldFallback) return false;
            const errText = await response.text();
            throw new Error(`Anthropic error ${response.status}: ${errText}`);
        }

        if (!response.body) throw new Error("No response body from Anthropic");

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        try {
            while (true) {
                if (params.signal.aborted) break;
                const { done, value } = await reader.read();
                if (done) break;

                buffer += decoder.decode(value, { stream: true });
                const lines = buffer.split("\n");
                buffer = lines.pop() ?? "";

                for (const line of lines) {
                    if (!line.startsWith("data: ")) continue;
                    const jsonStr = line.slice(6).trim();
                    if (jsonStr === "[DONE]") break;
                    try {
                        const event = JSON.parse(jsonStr) as Record<string, unknown>;
                        if (event.type === "content_block_delta") {
                            const delta = event.delta as Record<string, unknown> | undefined;
                            if (delta?.type === "text_delta" && typeof delta.text === "string") {
                                params.onChunk(delta.text);
                            }
                        }
                    } catch {
                        // Skip malformed events
                    }
                }
            }
        } finally {
            reader.releaseLock();
        }
        return true;
    };

    const primaryOk = await attemptStream(params.model);
    if (primaryOk) return { modelUsed: params.model };

    console.warn(
        `⚠️ Primary model ${params.model} failed. Falling back to ${params.fallbackModel}.`
    );
    await attemptStream(params.fallbackModel);
    return { modelUsed: params.fallbackModel };
}

// ── System prompt builder ──────────────────────────────────────────────────

function buildBereanSystemPrompt(mode: string): string {
    const base = `You are Berean AI, a compassionate Biblical assistant for the AMEN Christian social app.
Your purpose is to help believers understand Scripture, grow in faith, and apply God's Word to their lives.

Core Principles:
- Always cite Scripture references (e.g., John 3:16, Psalm 23:1-6)
- Be encouraging, compassionate, and Christ-centered
- Acknowledge multiple theological perspectives when appropriate
- Refer complex theological questions to local church leaders
- Never claim to replace personal Bible study, pastoral guidance, therapy, or clinical care
- Never speak as if you have direct divine authority over a user's life
- For abuse, suicidality, or immediate safety concerns, prioritize human safety over theological analysis
- For disputed doctrine, present faithful Christian differences with humility and do not treat one tradition as the only valid view`;

    const modes: Record<string, string> = {
        shepherd: `${base}\n\nMode: Shepherd — Guide users gently toward Scripture and practical application with pastoral warmth.`,
        scholar: `${base}\n\nMode: Scholar — Provide deeper theological analysis with historical context and original language insights.`,
        debater: `${base}\n\nMode: Debater — Engage in respectful theological dialogue, exploring perspectives with Scripture-backed reasoning.`,
        prayer: `${base}\n\nMode: Prayer Guide — Help users craft meaningful Scripture-rooted prayers.`,
        strategist: `${base}\n\nMode: Deep Study Strategist — Provide structured, multi-layered Biblical analysis with systematic study plans and cross-references.`,
        deep_study: `${base}\n\nMode: Deep Study — Provide comprehensive exegetical analysis, historical background, original language insights, and layered practical application.`,
    };

    return modes[mode] ?? modes.shepherd;
}

// ── History condensation ───────────────────────────────────────────────────

function condenseHistory(
    history: Array<{ role: string; content: string }>,
    tokenBudget: number
): Array<{ role: "user" | "assistant"; content: string }> {
    const valid = history.filter(
        (m): m is { role: "user" | "assistant"; content: string } =>
            m.role === "user" || m.role === "assistant"
    );
    const estimate = (msgs: typeof valid) =>
        msgs.reduce((sum, m) => sum + Math.ceil(m.content.length / 4) + 8, 0);

    if (estimate(valid) <= tokenBudget) return valid;

    const recent: typeof valid = [];
    let tokens = 0;
    for (let i = valid.length - 1; i >= 0; i--) {
        const t = Math.ceil(valid[i].content.length / 4) + 8;
        if (tokens + t > tokenBudget && recent.length >= 4) break;
        recent.unshift(valid[i]);
        tokens += t;
    }
    return recent;
}

// ── Helpers ────────────────────────────────────────────────────────────────

function modelTierLabel(modelId: string): string {
    if (modelId.includes("opus")) return "deep";
    if (modelId.includes("sonnet")) return "standard";
    return "core";
}
