"use strict";
/**
 * bereanChatProxy.ts
 *
 * Anthropic Claude proxy for Berean AI assistant.
 * Routes requests from ClaudeService.swift through Firebase Cloud Functions
 * to api.anthropic.com, keeping the API key secure in Firebase Secret Manager.
 *
 * Setup:
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 *
 * Model Selection:
 *   - Haiku (claude-3-haiku-20240307): Real-time interactions, fast responses
 *   - Sonnet (claude-3-5-sonnet-20241022): Scholar/debater modes, deep analysis
 */
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
exports.bereanChatProxy = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const rateLimit_1 = require("./rateLimit");
const sensitiveTopicPolicy_1 = require("./berean/prompts/sensitiveTopicPolicy");
const SpiritualStateEngine_1 = require("./berean/services/SpiritualStateEngine");
const conversationHistory_1 = require("./berean/services/conversationHistory");
const aiDisclosure_1 = require("./berean/services/aiDisclosure");
const agentIdentity_1 = require("./agents/agentIdentity");
const agentOutcomes_1 = require("./agents/agentOutcomes");
const agentObservability_1 = require("./agents/agentObservability");
const anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
/**
 * Berean AI Chat Proxy
 * Proxies Claude API calls with secure API key management
 */
exports.bereanChatProxy = (0, https_1.onCall)({
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
    // Reject calls from clients that cannot produce a valid App Check token.
    // Prevents scripted abuse of the Anthropic API proxy with a stolen
    // Firebase Auth token alone (no attested iOS binary required).
    enforceAppCheck: true,
}, async (request) => {
    // Verify authentication
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated to use Berean AI");
    }
    if (!request.app) {
        console.warn("⚠️ bereanChatProxy: App Check attestation missing");
        throw new https_1.HttpsError("unauthenticated", "App Check attestation required.");
    }
    // ── P0-5 server fix: under-13 / no-DOB rejection (fail-closed) ─────────
    // Read the caller's birth year from users/{uid}.  If birthYear is absent
    // (unknown age) or indicates under-13 we reject immediately — before any
    // LLM call or rate-limit check.  Fail-closed: no birthYear == treat as minor.
    const callerUid = request.auth.uid;
    try {
        const userSnap = await admin.firestore()
            .collection("users")
            .doc(callerUid)
            .get();
        const userData = userSnap.data() ?? {};
        // Accept birthYear (number), birthdate (ISO string), or minorStatus (bool).
        const birthYear = (() => {
            if (typeof userData.birthYear === "number")
                return userData.birthYear;
            if (typeof userData.birthdate === "string" && userData.birthdate.length >= 4) {
                const parsed = parseInt(userData.birthdate.slice(0, 4), 10);
                return isNaN(parsed) ? null : parsed;
            }
            return null;
        })();
        const currentYear = new Date().getFullYear();
        const isMinorByAge = birthYear !== null && (currentYear - birthYear) < 13;
        const isMinorByFlag = userData.minorStatus === true;
        const noDob = birthYear === null && userData.minorStatus !== false;
        if (isMinorByAge || isMinorByFlag || noDob) {
            console.warn("⚠️ bereanChatProxy: under-13 / no-DOB rejection", {
                uid: callerUid,
                isMinorByAge,
                isMinorByFlag,
                noDob,
            });
            throw new https_1.HttpsError("failed-precondition", "Berean AI is not available for users under 13.");
        }
    }
    catch (err) {
        // Re-throw HttpsErrors (our own rejections) without wrapping.
        if (err?.code && typeof err.code === "string")
            throw err;
        // Firestore read failure: fail-closed — do not allow access.
        console.error("❌ bereanChatProxy: failed to read user doc for age check", {
            code: err?.code ?? "unknown",
        });
        throw new https_1.HttpsError("internal", "Unable to verify user eligibility. Please try again.");
    }
    // CRITICAL-CF FIX: Per-user rate limiting.
    // Enforce both a per-minute burst limit and a daily token budget cap.
    // Throws HttpsError("resource-exhausted") if either window is exceeded.
    await (0, rateLimit_1.enforceRateLimit)(request.auth.uid, [
        rateLimit_1.RATE_LIMITS.AI_PER_MINUTE,
        rateLimit_1.RATE_LIMITS.AI_PER_DAY,
    ]);
    const data = request.data;
    const { message, conversationHistory = [], mode = "shepherd", memoryScope, callData, } = data;
    const maxTokens = Math.min(Math.max(Number(data.maxTokens ?? 2000), 128), 2000);
    const temperature = Math.min(Math.max(Number(data.temperature ?? 0.7), 0), 1);
    const systemPromptSuffix = typeof data.systemPromptSuffix === "string"
        ? data.systemPromptSuffix.slice(0, 1500)
        : undefined;
    // Validate input
    if (!message || typeof message !== "string" || message.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", "Message is required and must be a non-empty string");
    }
    // HIGH FIX: Enforce maximum message length.
    // Without this, a client can send a 500KB+ string directly to the Anthropic
    // API, incurring large token costs and risking function timeouts / OOM.
    // 4000 characters covers any realistic single message while keeping tokens
    // well within the per-call budget.
    const MAX_MESSAGE_LENGTH = 4000;
    if (message.length > MAX_MESSAGE_LENGTH) {
        throw new https_1.HttpsError("invalid-argument", `Message exceeds maximum length of ${MAX_MESSAGE_LENGTH} characters.`);
    }
    // Get API key from secret
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
        console.error("❌ ANTHROPIC_API_KEY not configured");
        throw new Error("Berean AI is not configured. Please contact support.");
    }
    let agentRunId = null;
    let selectedModel = null;
    try {
        const sensitivityContext = analyzeSensitivity(message, callData);
        const agentIdentity = (0, agentIdentity_1.resolveBereanAgentIdentity)(mode);
        agentRunId = await (0, agentObservability_1.startAgentRun)({
            uid: request.auth.uid,
            surface: "berean.chat.callable",
            agentId: agentIdentity.agentId,
            agentVersion: agentIdentity.version,
            sessionId: callData?.conversationId,
            mode,
            inputLength: message.length,
            metadata: {
                historyCount: conversationHistory.length,
                sensitivityFlagsCount: (callData?.sensitivityFlags ?? []).length,
                responseMode: callData?.responseMode,
            },
        });
        // ── Server-side safety backstop ───────────────────────────────────────
        // Interactive Berean chat via sendBereanChatMessage() already runs
        // makeChatPreflight() on the client and forwards responseMode via callData.
        // Utility callers (sendMessage) skip preflight — they don't set
        // callData.responseMode but they also never set callData.conversationId.
        //
        // If a request arrives with a conversationId (interactive chat) but no
        // responseMode (preflight was skipped or bypassed), run classifySpiritualState
        // server-side so crisis messages always get a safe response regardless of
        // which client code path was used.
        const hasConversationId = !!callData?.conversationId;
        const preflightWasRun = !!callData?.responseMode;
        if (hasConversationId && !preflightWasRun) {
            let serverClassification;
            try {
                serverClassification = await (0, SpiritualStateEngine_1.classifySpiritualState)(request.auth.uid, message, []);
            }
            catch {
                // Classification failure is non-fatal — continue to Claude call
            }
            if (serverClassification?.escalationTriggered) {
                await (0, agentObservability_1.logAgentSpan)(agentRunId, {
                    type: "crisis_short_circuit",
                    status: "warn",
                    summary: "Server-side preflight detected escalation; returned crisis response.",
                    metadata: { mode },
                });
                await (0, agentObservability_1.finishAgentRun)(agentRunId, {
                    status: "blocked",
                    outcomeScore: 100,
                    visibleSummary: "Crisis short-circuit returned safety resources.",
                    metadata: { model: "crisis-short-circuit" },
                });
                return {
                    response: CRISIS_SAFE_RESPONSE,
                    model: "crisis-short-circuit",
                    usage: null,
                    agentRunId,
                    outcomeStatus: "blocked",
                    outcomeScore: 100,
                    safetyStatus: "blocked",
                };
            }
        }
        // ── Daily quota enforcement ──────────────────────────────────────────────
        const uid = request.auth.uid;
        const db = admin.firestore();
        const today = new Date().toISOString().split("T")[0].replace(/-/g, ""); // yyyyMMdd
        const quotaBucket = db.collection("aiUsage").doc(uid).collection("daily").doc(today);
        await db.runTransaction(async (txn) => {
            const snap = await txn.get(quotaBucket);
            const current = snap.exists ? (snap.data()?.requestCount ?? 0) : 0;
            const subscriptionSnap = await txn.get(db.collection("userSubscriptions").doc(uid));
            const subscriptionTier = subscriptionSnap.data()?.tier;
            const tierValue = typeof subscriptionTier === "string" ? subscriptionTier : "free";
            const tier = ["plus", "pro", "founder"].includes(tierValue) ? "pro" : "free";
            const dailyLimit = tier === "free" ? 15 : 150;
            if (current >= dailyLimit) {
                throw new https_1.HttpsError("resource-exhausted", "Daily Berean limit reached. Upgrade for more.");
            }
            // Increment atomically
            txn.set(quotaBucket, {
                requestCount: current + 1,
                tier,
                lastRequestAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        // Select model based on mode and client hint — but enforce tier ceiling server-side.
        // Tier is read from Firestore; falls back to "free" so unknown users get the safe default.
        const bereanTier = await getBereanTierForUser(request.auth.uid);
        const { modelId: model, downgraded } = resolveEntitledModel(data.modelId, mode, bereanTier);
        selectedModel = model;
        if (downgraded) {
            console.info("ℹ️ berean_model_downgraded", {
                tier: bereanTier,
                granted: model,
            });
        }
        await (0, agentObservability_1.logAgentSpan)(agentRunId, {
            type: "model_selected",
            status: "ok",
            summary: "Entitled model selected for Berean callable response.",
            metadata: { tier: bereanTier, model, downgraded },
        });
        // Build system prompt
        let systemPrompt = buildSystemPrompt(mode);
        systemPrompt += `\n\n${(0, agentIdentity_1.buildAgentIdentityPromptBlock)(agentIdentity)}`;
        const sensitivePolicyBlock = (0, sensitiveTopicPolicy_1.buildSensitiveTopicPolicyBlock)(sensitivityContext.flags, sensitivityContext.topicClass);
        if (sensitivePolicyBlock) {
            systemPrompt += `\n\n${sensitivePolicyBlock}`;
        }
        const contextualPrompt = buildCallDataPrompt(callData ?? { memoryScope });
        if (contextualPrompt) {
            systemPrompt += `\n\n${contextualPrompt}`;
        }
        if (systemPromptSuffix) {
            systemPrompt += `\n\n${systemPromptSuffix}`;
        }
        await (0, agentObservability_1.logAgentSpan)(agentRunId, {
            type: "prompt_built",
            status: "ok",
            summary: "Server-owned identity bundle and safety policy were applied.",
            metadata: {
                agentId: agentIdentity.agentId,
                agentVersion: agentIdentity.version,
                sensitivityFlags: sensitivityContext.flags,
                topicClass: sensitivityContext.topicClass,
            },
        });
        // Build messages array.
        //
        // SECURITY: the client-supplied history is sanitized before forwarding
        // to Anthropic. Only {role:"user"|"assistant", content:string} entries
        // are kept; "system"/"developer"/"tool" roles are dropped so a client
        // cannot smuggle a second system prompt past `buildSystemPrompt`. All
        // unknown fields are stripped, content is coerced to string and capped
        // at 1200 chars, and the array is capped at the last 12 entries.
        const messages = [
            ...(0, conversationHistory_1.sanitizeConversationHistory)(conversationHistory),
            { role: "user", content: message },
        ];
        // Call Claude API
        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
                model,
                max_tokens: maxTokens,
                temperature,
                system: systemPrompt,
                messages,
            }),
        });
        if (!response.ok) {
            await response.text().catch(() => "");
            console.error("❌ Claude API error", { status: response.status });
            throw new Error(`Claude API error: ${response.status}`);
        }
        const result = await response.json();
        // Extract text from response
        const responseText = result.content?.[0]?.text || "";
        const outcome = (0, agentOutcomes_1.evaluateBereanOutcome)(responseText || "Berean encountered an issue — tap to retry.", {
            mode,
            sensitivityFlags: sensitivityContext.flags,
        });
        const safeResponseText = (0, aiDisclosure_1.ensureAIDisclosure)(outcome.finalText);
        if (outcome.status !== "passed") {
            console.warn("⚠️ Berean proxy output sanitized", {
                outcomeStatus: outcome.status,
                violations: outcome.violations,
            });
        }
        await (0, agentObservability_1.logAgentSpan)(agentRunId, {
            type: "outcome_evaluated",
            status: outcome.status === "passed" ? "ok" : "warn",
            summary: outcome.visibleSummary,
            metadata: {
                score: outcome.score,
                violationsCount: outcome.violations.length,
                checks: outcome.checks.map((check) => ({
                    name: check.name,
                    passed: check.passed,
                    severity: check.severity,
                })),
            },
        });
        await (0, agentObservability_1.finishAgentRun)(agentRunId, {
            status: outcome.status,
            outcomeScore: outcome.score,
            visibleSummary: outcome.visibleSummary,
            metadata: { model },
        });
        // Log usage for monitoring (no UID — opaque metrics only)
        console.log("✅ berean_chat_proxy_succeeded", {
            model,
            outputTokens: result.usage?.output_tokens || 0,
        });
        return {
            response: safeResponseText,
            model,
            usage: result.usage,
            agentRunId,
            outcomeStatus: outcome.status,
            outcomeScore: outcome.score,
            safetyStatus: outcome.status === "passed" ? "ok" : outcome.status,
        };
    }
    catch (error) {
        if (agentRunId) {
            await (0, agentObservability_1.finishAgentRun)(agentRunId, {
                status: "failed",
                visibleSummary: "Berean callable request failed before a response was returned.",
                metadata: {
                    model: selectedModel,
                    code: error?.code ?? "unknown",
                    name: error?.name ?? "Error",
                },
            }).catch(() => undefined);
        }
        console.error("❌ Berean Chat Proxy error", {
            code: error?.code ?? "unknown",
            name: error?.name ?? "Error",
        });
        throw new Error("Failed to process Berean AI request");
    }
});
const PROD_BEREAN_MODELS = {
    core: "claude-haiku-4-5-20251001",
    standard: "claude-sonnet-4-6",
    deep: "claude-opus-4-7",
};
const PROD_TIER_CEILING = {
    free: PROD_BEREAN_MODELS.core,
    plus: PROD_BEREAN_MODELS.standard,
    pro: PROD_BEREAN_MODELS.deep,
    founder: PROD_BEREAN_MODELS.deep,
};
const PROD_MODEL_PRECEDENCE = {
    [PROD_BEREAN_MODELS.core]: 0,
    "claude-3-haiku-20240307": 0,
    [PROD_BEREAN_MODELS.standard]: 1,
    "claude-3-5-sonnet-20241022": 1,
    [PROD_BEREAN_MODELS.deep]: 2,
    "claude-3-opus-20240229": 2,
};
async function getBereanTierForUser(uid) {
    try {
        const subscription = await admin.firestore().collection("userSubscriptions").doc(uid).get();
        const subData = subscription.data() ?? {};
        const tier = (subData.tier ?? subData.plan ?? subData.status);
        const valid = ["free", "plus", "pro", "founder"];
        return valid.includes(tier) ? tier : "free";
    }
    catch {
        return "free";
    }
}
function resolveEntitledModel(clientModelId, mode, tier) {
    const ceiling = PROD_TIER_CEILING[tier];
    let desired;
    if (clientModelId && clientModelId.trim().length > 0) {
        const id = clientModelId.trim();
        if (id === "deep" || id.includes("opus"))
            desired = PROD_BEREAN_MODELS.deep;
        else if (id === "standard" || id.includes("sonnet"))
            desired = PROD_BEREAN_MODELS.standard;
        else
            desired = PROD_BEREAN_MODELS.core;
    }
    else if (["scholar", "debater", "strategist", "deep_study"].includes(mode)) {
        desired = PROD_BEREAN_MODELS.standard;
    }
    else {
        desired = PROD_BEREAN_MODELS.core;
    }
    const desiredPrec = PROD_MODEL_PRECEDENCE[desired] ?? 0;
    const ceilingPrec = PROD_MODEL_PRECEDENCE[ceiling] ?? 0;
    const downgraded = desiredPrec > ceilingPrec;
    return { modelId: downgraded ? ceiling : desired, downgraded };
}
/**
 * Build system prompt based on Berean mode
 */
function buildSystemPrompt(mode) {
    const basePrompt = `You are Berean AI, a compassionate Biblical assistant for the AMEN Christian social app.
Your purpose is to help believers understand Scripture, grow in faith, and apply God's Word to their lives.

Core Principles:
- Always cite Scripture references (e.g., John 3:16, Psalm 23:1-6)
- Be encouraging, compassionate, and Christ-centered
- Acknowledge multiple theological perspectives when appropriate
- Refer complex theological questions to local church leaders
- Never claim to replace personal Bible study, pastoral guidance, therapy, or clinical care
- Never speak as if you have direct divine authority over a user's life
- Never tell a user that God is commanding them to leave a church, end a relationship, stop medication, or ignore wise human counsel
- For abuse, suicidality, or immediate safety concerns, prioritize human safety and local support over theological analysis
- For disputed doctrine, present faithful Christian differences with humility and do not treat one tradition as the only valid view`;
    const modePrompts = {
        shepherd: `${basePrompt}

Mode: Shepherd - You are encouraging and pastoral. Guide users gently toward Scripture and practical application.`,
        scholar: `${basePrompt}

Mode: Scholar - You provide deeper theological analysis with historical context, original language insights, and cross-references. Maintain academic rigor while being accessible.`,
        debater: `${basePrompt}

Mode: Debater - You engage in respectful theological dialogue, exploring different perspectives and challenging assumptions with Scripture. Ask probing questions and encourage critical thinking.`,
        prayer: `${basePrompt}

Mode: Prayer Guide - Help users craft meaningful prayers based on Scripture. Suggest Biblical prayer patterns and relevant passages for their situation.`,
        strategist: `${basePrompt}

Mode: Deep Study Strategist - Provide structured, multi-layered Biblical analysis with systematic study plans, exegetical depth, cross-references, and historical-theological context.`,
        deep_study: `${basePrompt}

Mode: Deep Study - Provide comprehensive exegetical analysis, historical background, original language insights, and layered practical application at full scholarly depth.`,
    };
    return modePrompts[mode] || modePrompts.shepherd;
}
function analyzeSensitivity(message, callData) {
    const lower = message.toLowerCase();
    const flags = new Set();
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
    let topicClass = null;
    if (containsAny(lower, CRISIS_KEYWORDS)) {
        topicClass = "suicidality";
    }
    else if (containsAny(lower, ABUSE_KEYWORDS)) {
        topicClass = "abuse_disclosure";
    }
    else if (containsAny(lower, MEDICAL_KEYWORDS)) {
        topicClass = "medical_override";
    }
    else if (containsAny(lower, LEGAL_KEYWORDS)) {
        topicClass = "legal_conflict";
    }
    else if (containsAny(lower, CHURCH_CONFLICT_KEYWORDS)) {
        topicClass = "church_conflict";
    }
    else if (containsAny(lower, MAJOR_DECISION_KEYWORDS)) {
        topicClass = "major_life_decision";
    }
    else if (containsAny(lower, DOCTRINAL_DISPUTE_KEYWORDS)) {
        topicClass = "doctrinal_dispute";
    }
    return {
        flags: Array.from(flags),
        topicClass,
    };
}
function containsAny(text, phrases) {
    return phrases.some((phrase) => text.includes(phrase));
}
// ensureAIDisclosure() now lives in berean/services/aiDisclosure.ts so the
// streaming proxy (bereanChatProxyStream.ts) can apply the same disclosure
// at the terminal SSE event.
// Crisis-safe response returned when server-side classification detects escalation
// on a request that bypassed client-side preflight.
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
// 25-pattern list aligned with CrisisSupportViewModel.detectHighRiskLanguage()
const CRISIS_KEYWORDS = [
    "end it",
    "end my life",
    "kill myself",
    "want to die",
    "can't go on",
    "cannot go on",
    "no reason to live",
    "take my life",
    "don't want to be here",
    "dont want to be here",
    "don't want to exist",
    "dont want to exist",
    "wish i was dead",
    "nothing to live for",
    "better off dead",
    "better off without me",
    "going to hurt myself",
    "hurt myself",
    "self harm",
    "self-harm",
    "cut myself",
    "overdose",
    "jump off",
    "hang myself",
    "no point anymore",
    "can't take it anymore",
    "cant take it anymore",
    "give up on life",
    "end the pain",
    "suicidal",
    "suicide",
    "what's the point",
    "whats the point",
];
const ABUSE_KEYWORDS = [
    "my husband hits me",
    "my wife hits me",
    "he hits me",
    "she hits me",
    "abusive relationship",
    "domestic violence",
    "he threatens me",
    "she threatens me",
    "i am being abused",
    "spiritual abuse",
];
const MEDICAL_KEYWORDS = [
    "should i stop my medication",
    "stop taking my medication",
    "stop therapy",
    "doctor said",
    "medical advice",
    "diagnosis",
];
const LEGAL_KEYWORDS = [
    "legal advice",
    "lawsuit",
    "custody",
    "attorney",
    "lawyer",
    "press charges",
];
const DOCTRINAL_DISPUTE_KEYWORDS = [
    "predestination",
    "women in ministry",
    "speaking in tongues",
    "charismatic gifts",
    "calvinism",
    "arminian",
    "baptism saves",
    "once saved always saved",
];
const MAJOR_DECISION_KEYWORDS = [
    "should i marry",
    "should i divorce",
    "should i move",
    "should i quit my job",
    "should i leave my church",
    "major decision",
];
const CHURCH_CONFLICT_KEYWORDS = [
    "my pastor",
    "church conflict",
    "church hurt",
    "elder",
    "leadership conflict",
    "leave this church",
];
function buildCallDataPrompt(callData) {
    if (!callData) {
        return "";
    }
    const parts = [];
    if ("faithJourneyStage" in callData && callData.faithJourneyStage) {
        parts.push(`USER CONTEXT:\nThis user identifies as ${callData.faithJourneyStage}. Calibrate vocabulary and assumed background knowledge accordingly.`);
    }
    if ("userPersona" in callData && callData.userPersona) {
        parts.push(`The user's persona or role is ${callData.userPersona}. Use that to tailor examples and framing, but do not weaken safety or humility guardrails.`);
    }
    if ("scriptureTranslation" in callData && callData.scriptureTranslation) {
        parts.push(`Preferred Scripture translation for this turn: ${callData.scriptureTranslation}. Preserve that translation context when referring back to quoted passages.`);
    }
    const effectiveMemoryScope = ("memoryScope" in callData && callData.memoryScope) || undefined;
    if (effectiveMemoryScope) {
        parts.push(`Memory scope for this request: ${effectiveMemoryScope}.`);
    }
    if ("postContext" in callData && callData.postContext) {
        const postContext = callData.postContext;
        const postLines = [
            "POST CONTEXT:",
            `- Post ID: ${postContext.postId}`,
            `- Author: ${postContext.authorName}`,
            `- Category: ${postContext.category}`,
            `- Safe summary: ${postContext.previewText}`,
        ];
        if (postContext.bodyText) {
            const capped = postContext.bodyText.slice(0, 500);
            postLines.push(`- Post body: ${capped}`);
        }
        if (postContext.verseReference) {
            postLines.push(`- Scripture reference: ${postContext.verseReference}`);
        }
        if (postContext.verseText) {
            postLines.push(`- Scripture text: ${postContext.verseText}`);
        }
        if (postContext.mediaSummary) {
            postLines.push(`- Media metadata: ${postContext.mediaSummary}`);
        }
        if (postContext.isSensitive) {
            postLines.push("- This post is sensitive. Do not reveal hidden details beyond the safe summary.");
        }
        parts.push(postLines.join("\n"));
    }
    return parts.join("\n\n");
}
//# sourceMappingURL=bereanChatProxy.js.map