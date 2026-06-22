"use strict";
/**
 * berean/modelRouter.ts — Frontier Intelligence Layer (Model Router)
 * Berean Trust Architecture · Layer 1 · Version: v1
 *
 * Responsibilities:
 *   1. Load per-task routing config from Firestore (live override) or DEFAULT_ROUTING_TABLE
 *   2. Call the primary provider; walk the fallbackChain on failure
 *   3. Measure latency precisely (performance.now())
 *   4. Write a ModelCallLog to Firestore bereanModelLogs/{traceId}
 *   5. Return generated text + log
 *
 * Feature flag gate: featureFlags/trustArchitecture → modelRouter === true
 * All API keys sourced from process.env (Firebase secrets) — never hard-coded.
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_ROUTING_TABLE = exports.ROUTING_TABLE_VERSION = void 0;
exports.routeModelCall = routeModelCall;
const admin = __importStar(require("firebase-admin"));
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
const generative_ai_1 = require("@google/generative-ai");
// ── DEFAULT ROUTING TABLE (v1) ────────────────────────────────────────────────
exports.ROUTING_TABLE_VERSION = "v1";
exports.DEFAULT_ROUTING_TABLE = {
    conversational: {
        taskClass: "conversational",
        provider: "google",
        model: "gemini-1.5-flash",
        maxTokens: 2000,
        timeoutMs: 8000,
        fallbackChain: [
            { provider: "anthropic", model: "claude-haiku-4-5" },
        ],
    },
    theological: {
        taskClass: "theological",
        provider: "anthropic",
        model: "claude-sonnet-4-6",
        maxTokens: 4000,
        timeoutMs: 20000,
        fallbackChain: [
            { provider: "google", model: "gemini-1.5-pro" },
        ],
    },
    longDocument: {
        taskClass: "longDocument",
        provider: "google",
        model: "gemini-1.5-pro",
        maxTokens: 8000,
        timeoutMs: 45000,
        fallbackChain: [
            { provider: "anthropic", model: "claude-sonnet-4-6" },
        ],
    },
    safetyReview: {
        taskClass: "safetyReview",
        provider: "anthropic",
        model: "claude-sonnet-4-6",
        maxTokens: 2000,
        timeoutMs: 10000,
        fallbackChain: [], // no fallback — fail closed
    },
    moderation: {
        taskClass: "moderation",
        provider: "google",
        model: "gemini-1.5-flash",
        maxTokens: 1000,
        timeoutMs: 5000,
        fallbackChain: [
            { provider: "anthropic", model: "claude-haiku-4-5" },
        ],
    },
};
// ── TOKEN ESTIMATION ──────────────────────────────────────────────────────────
// Rough 4-chars-per-token heuristic; exact counts unavailable without streaming.
function estimateTokens(text) {
    return Math.ceil(text.length / 4);
}
// ── PROVIDER CALL IMPLEMENTATIONS ─────────────────────────────────────────────
/**
 * callAnthropic — uses @anthropic-ai/sdk with process.env.ANTHROPIC_API_KEY.
 * Returns the generated text string.
 */
async function callAnthropic(model, systemPrompt, userPrompt, maxTokens, timeoutMs) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        throw new Error("callAnthropic: ANTHROPIC_API_KEY is not set in environment");
    }
    const client = new sdk_1.default({ apiKey });
    // Wrap in a Promise.race so we honour timeoutMs.
    const callPromise = client.messages.create({
        model,
        max_tokens: maxTokens,
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }],
    });
    const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error(`callAnthropic: timeout after ${timeoutMs}ms`)), timeoutMs));
    const response = await Promise.race([callPromise, timeoutPromise]);
    const firstBlock = response.content[0];
    if (!firstBlock || firstBlock.type !== "text") {
        throw new Error("callAnthropic: no text content in response");
    }
    return firstBlock.text;
}
/**
 * callGoogle — uses @google/generative-ai with process.env.GEMINI_API_KEY.
 * Returns the generated text string.
 */
async function callGoogle(model, systemPrompt, userPrompt, maxTokens, timeoutMs) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        throw new Error("callGoogle: GEMINI_API_KEY is not set in environment");
    }
    const genAI = new generative_ai_1.GoogleGenerativeAI(apiKey);
    const genModel = genAI.getGenerativeModel({
        model,
        generationConfig: { maxOutputTokens: maxTokens },
        systemInstruction: systemPrompt,
    });
    const callPromise = genModel.generateContent({
        contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    });
    const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error(`callGoogle: timeout after ${timeoutMs}ms`)), timeoutMs));
    const result = await Promise.race([callPromise, timeoutPromise]);
    const text = result.response.text();
    if (typeof text !== "string") {
        throw new Error("callGoogle: response.text() did not return a string");
    }
    return text;
}
// ── DISPATCH BY PROVIDER ──────────────────────────────────────────────────────
async function dispatchProvider(provider, model, systemPrompt, userPrompt, maxTokens, timeoutMs) {
    switch (provider) {
        case "anthropic":
            return callAnthropic(model, systemPrompt, userPrompt, maxTokens, timeoutMs);
        case "google":
            return callGoogle(model, systemPrompt, userPrompt, maxTokens, timeoutMs);
        case "openai":
            // openai is a valid FallbackEntry provider type but is not a primary route
            // in DEFAULT_ROUTING_TABLE. Kept here for completeness and future use.
            throw new Error(`dispatchProvider: OpenAI calls are not implemented in modelRouter.ts — ` +
                `use router/callModel.js for tasks that require OpenAI`);
        default: {
            // Exhaustive check
            const _exhaustive = provider;
            throw new Error(`dispatchProvider: unknown provider "${_exhaustive}"`);
        }
    }
}
// ── FIRESTORE CONFIG LOADER ────────────────────────────────────────────────────
/**
 * Load the routing table from Firestore (live admin override).
 * Document shape: bereanConfig/modelRouterV1 → { [taskClass]: ModelRouterConfig }
 * Returns null if the document does not exist; caller falls back to DEFAULT_ROUTING_TABLE.
 */
async function loadFirestoreRoutingTable(db) {
    try {
        const snap = await db.doc("bereanConfig/modelRouterV1").get();
        if (!snap.exists)
            return null;
        const data = snap.data();
        if (!data)
            return null;
        return data;
    }
    catch {
        // Non-fatal: fall back to defaults rather than blocking all AI calls.
        return null;
    }
}
// ── MAIN EXPORTED FUNCTION ─────────────────────────────────────────────────────
/**
 * routeModelCall — selects the right model for a task class, calls it with
 * fallback handling, logs the result to Firestore, and returns the text + log.
 *
 * Feature flag gate: Firestore doc "featureFlags/trustArchitecture"
 * field "modelRouter" must be explicitly true; otherwise throws.
 *
 * Log destination: Firestore "bereanModelLogs/{traceId}"
 */
async function routeModelCall(params) {
    const { taskClass, systemPrompt, userPrompt, traceId, db } = params;
    // ── 1. Feature flag gate ────────────────────────────────────────────────────
    const flagSnap = await db.doc("featureFlags/trustArchitecture").get();
    const flags = flagSnap.exists ? flagSnap.data() ?? {} : {};
    if (flags["modelRouter"] !== true) {
        throw new Error("ModelRouter not enabled");
    }
    // ── 2. Load routing config (Firestore override → DEFAULT_ROUTING_TABLE) ─────
    const firestoreTable = await loadFirestoreRoutingTable(db);
    const routingTable = firestoreTable ?? exports.DEFAULT_ROUTING_TABLE;
    const config = routingTable[taskClass];
    const callChain = [
        { provider: config.provider, model: config.model },
        ...config.fallbackChain,
    ];
    // ── 4. Try providers in order ────────────────────────────────────────────────
    let text = "";
    let usedProvider = config.provider;
    let usedModel = config.model;
    let outcome = "error";
    let lastError = null;
    const startTime = performance.now();
    for (let i = 0; i < callChain.length; i++) {
        const slot = callChain[i];
        try {
            text = await dispatchProvider(slot.provider, slot.model, systemPrompt, userPrompt, config.maxTokens, config.timeoutMs);
            usedProvider = slot.provider;
            usedModel = slot.model;
            outcome = i === 0 ? "success" : "fallback";
            break;
        }
        catch (err) {
            lastError = err instanceof Error ? err : new Error(String(err));
            // For safetyReview the fallback chain is empty, so this loop exits after 1 try.
        }
    }
    const latencyMs = Math.round(performance.now() - startTime);
    // ── 5. If all providers failed, record error outcome (text stays empty) ──────
    if (outcome === "error") {
        // We still log the failure before re-throwing so the audit trail is complete.
        const log = {
            traceId,
            taskClass,
            provider: config.provider,
            model: config.model,
            latencyMs,
            inputTokens: estimateTokens(systemPrompt + userPrompt),
            outputTokens: 0,
            outcome: "error",
            timestamp: admin.firestore.Timestamp.now(),
        };
        await db
            .collection("bereanModelLogs")
            .doc(traceId)
            .set(log)
            .catch(() => {
            // Non-fatal — don't suppress the original error with a logging error.
        });
        throw lastError ?? new Error("routeModelCall: all providers failed");
    }
    // ── 6. Build + persist the log ────────────────────────────────────────────────
    const log = {
        traceId,
        taskClass,
        provider: usedProvider,
        model: usedModel,
        latencyMs,
        inputTokens: estimateTokens(systemPrompt + userPrompt),
        outputTokens: estimateTokens(text),
        outcome,
        timestamp: admin.firestore.Timestamp.now(),
    };
    await db.collection("bereanModelLogs").doc(traceId).set(log);
    return { text, log };
}
