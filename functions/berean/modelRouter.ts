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

import * as admin from "firebase-admin";
import Anthropic from "@anthropic-ai/sdk";
import { GoogleGenerativeAI } from "@google/generative-ai";

// ── TYPES ─────────────────────────────────────────────────────────────────────

export type TaskClass =
  | "conversational"
  | "theological"
  | "longDocument"
  | "safetyReview"
  | "moderation";

export type Provider = "anthropic" | "openai" | "google";

export interface FallbackEntry {
  provider: Provider;
  model: string;
}

export interface ModelRouterConfig {
  taskClass: TaskClass;
  provider: Provider;
  model: string;
  maxTokens: number;
  timeoutMs: number;
  fallbackChain: FallbackEntry[];
}

export interface ModelCallLog {
  traceId: string;
  taskClass: TaskClass;
  provider: Provider;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  outcome: "success" | "fallback" | "error";
  timestamp: admin.firestore.Timestamp;
}

export interface RouteModelCallParams {
  taskClass: TaskClass;
  systemPrompt: string;
  userPrompt: string;
  traceId: string;
  db: admin.firestore.Firestore;
}

export interface RouteModelCallResult {
  text: string;
  log: ModelCallLog;
}

// ── DEFAULT ROUTING TABLE (v1) ────────────────────────────────────────────────

export const ROUTING_TABLE_VERSION = "v1";

export const DEFAULT_ROUTING_TABLE: Record<TaskClass, ModelRouterConfig> = {
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

function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

// ── PROVIDER CALL IMPLEMENTATIONS ─────────────────────────────────────────────

/**
 * callAnthropic — uses @anthropic-ai/sdk with process.env.ANTHROPIC_API_KEY.
 * Returns the generated text string.
 */
async function callAnthropic(
  model: string,
  systemPrompt: string,
  userPrompt: string,
  maxTokens: number,
  timeoutMs: number,
): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error("callAnthropic: ANTHROPIC_API_KEY is not set in environment");
  }

  const client = new Anthropic({ apiKey });

  // Wrap in a Promise.race so we honour timeoutMs.
  const callPromise = client.messages.create({
    model,
    max_tokens: maxTokens,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const timeoutPromise = new Promise<never>((_, reject) =>
    setTimeout(
      () => reject(new Error(`callAnthropic: timeout after ${timeoutMs}ms`)),
      timeoutMs,
    ),
  );

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
async function callGoogle(
  model: string,
  systemPrompt: string,
  userPrompt: string,
  maxTokens: number,
  timeoutMs: number,
): Promise<string> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("callGoogle: GEMINI_API_KEY is not set in environment");
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const genModel = genAI.getGenerativeModel({
    model,
    generationConfig: { maxOutputTokens: maxTokens },
    systemInstruction: systemPrompt,
  });

  const callPromise = genModel.generateContent({
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
  });

  const timeoutPromise = new Promise<never>((_, reject) =>
    setTimeout(
      () => reject(new Error(`callGoogle: timeout after ${timeoutMs}ms`)),
      timeoutMs,
    ),
  );

  const result = await Promise.race([callPromise, timeoutPromise]);
  const text = result.response.text();
  if (typeof text !== "string") {
    throw new Error("callGoogle: response.text() did not return a string");
  }
  return text;
}

// ── DISPATCH BY PROVIDER ──────────────────────────────────────────────────────

async function dispatchProvider(
  provider: Provider,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  maxTokens: number,
  timeoutMs: number,
): Promise<string> {
  switch (provider) {
    case "anthropic":
      return callAnthropic(model, systemPrompt, userPrompt, maxTokens, timeoutMs);
    case "google":
      return callGoogle(model, systemPrompt, userPrompt, maxTokens, timeoutMs);
    case "openai":
      // openai is a valid FallbackEntry provider type but is not a primary route
      // in DEFAULT_ROUTING_TABLE. Kept here for completeness and future use.
      throw new Error(
        `dispatchProvider: OpenAI calls are not implemented in modelRouter.ts — ` +
          `use router/callModel.js for tasks that require OpenAI`,
      );
    default: {
      // Exhaustive check
      const _exhaustive: never = provider;
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
async function loadFirestoreRoutingTable(
  db: admin.firestore.Firestore,
): Promise<Record<TaskClass, ModelRouterConfig> | null> {
  try {
    const snap = await db.doc("bereanConfig/modelRouterV1").get();
    if (!snap.exists) return null;
    const data = snap.data();
    if (!data) return null;
    return data as Record<TaskClass, ModelRouterConfig>;
  } catch {
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
export async function routeModelCall(
  params: RouteModelCallParams,
): Promise<RouteModelCallResult> {
  const { taskClass, systemPrompt, userPrompt, traceId, db } = params;

  // ── 1. Feature flag gate ────────────────────────────────────────────────────
  const flagSnap = await db.doc("featureFlags/trustArchitecture").get();
  const flags = flagSnap.exists ? flagSnap.data() ?? {} : {};
  if (flags["modelRouter"] !== true) {
    throw new Error("ModelRouter not enabled");
  }

  // ── 2. Load routing config (Firestore override → DEFAULT_ROUTING_TABLE) ─────
  const firestoreTable = await loadFirestoreRoutingTable(db);
  const routingTable: Record<TaskClass, ModelRouterConfig> =
    firestoreTable ?? DEFAULT_ROUTING_TABLE;
  const config: ModelRouterConfig = routingTable[taskClass];

  // ── 3. Build the ordered call chain: [primary, ...fallbackChain] ─────────────
  interface CallSlot {
    provider: Provider;
    model: string;
  }
  const callChain: CallSlot[] = [
    { provider: config.provider, model: config.model },
    ...config.fallbackChain,
  ];

  // ── 4. Try providers in order ────────────────────────────────────────────────
  let text = "";
  let usedProvider: Provider = config.provider;
  let usedModel = config.model;
  let outcome: ModelCallLog["outcome"] = "error";
  let lastError: Error | null = null;
  const startTime = performance.now();

  for (let i = 0; i < callChain.length; i++) {
    const slot = callChain[i];
    try {
      text = await dispatchProvider(
        slot.provider,
        slot.model,
        systemPrompt,
        userPrompt,
        config.maxTokens,
        config.timeoutMs,
      );
      usedProvider = slot.provider;
      usedModel = slot.model;
      outcome = i === 0 ? "success" : "fallback";
      break;
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      // For safetyReview the fallback chain is empty, so this loop exits after 1 try.
    }
  }

  const latencyMs = Math.round(performance.now() - startTime);

  // ── 5. If all providers failed, record error outcome (text stays empty) ──────
  if (outcome === "error") {
    // We still log the failure before re-throwing so the audit trail is complete.
    const log: ModelCallLog = {
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
  const log: ModelCallLog = {
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
