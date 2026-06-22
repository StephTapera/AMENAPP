/**
 * berean/modelRouter.ts
 *
 * Trust Architecture Layer 1 — Model Router Cloud Function
 *
 * Routes LLM calls to the appropriate provider and model based on task class.
 * Supports Firestore-based routing overrides for hot-patching without redeployment.
 * Implements a primary → fallback chain; throws HttpsError only when both fail.
 *
 * Secrets (set via: firebase functions:secrets:set <NAME>):
 *   ANTHROPIC_API_KEY — @anthropic-ai/sdk  (already in package.json ^0.36.3)
 *   OPENAI_API_KEY    — raw fetch to api.openai.com  (openai npm package NOT in package.json;
 *                        fetch is used instead to avoid adding a dependency)
 *
 * Firestore override collection: model_router_config/{taskClass}
 *   Fields: primaryModel, primaryProvider, fallbackModel, fallbackProvider,
 *           timeoutMs, temperature (all optional — unset fields fall back to hardcoded defaults)
 *
 * Audit log collection: berean_model_logs/{auto-id}
 */

import Anthropic from "@anthropic-ai/sdk";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

// ─── Types ────────────────────────────────────────────────────────────────────

export type TaskClass =
  | "FAST_CONVERSATIONAL"
  | "DEEP_THEOLOGICAL"
  | "LONG_DOCUMENT"
  | "SAFETY_REVIEW"
  | "MODERATION"
  | "VERIFICATION";

export interface ModelRouterInput {
  taskClass: TaskClass;
  prompt: string;
  systemPrompt?: string;
  temperature?: number;
  maxTokens?: number;
}

export interface ModelRouterResult {
  content: string;
  provider: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
}

// ─── Secrets ──────────────────────────────────────────────────────────────────

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const openaiApiKey = defineSecret("OPENAI_API_KEY");

// ─── Routing Table ────────────────────────────────────────────────────────────

interface RouteSpec {
  primaryProvider: "anthropic" | "openai" | "openai-moderation";
  primaryModel: string;
  fallbackProvider?: "anthropic" | "openai" | "openai-moderation";
  fallbackModel?: string;
  timeoutMs: number;
  temperature: number;
  maxTokens: number;
}

const HARDCODED_ROUTES: Record<TaskClass, RouteSpec> = {
  FAST_CONVERSATIONAL: {
    primaryProvider: "anthropic",
    primaryModel: "claude-haiku-4-5",
    fallbackProvider: "openai",
    fallbackModel: "gpt-4o-mini",
    timeoutMs: 5_000,
    temperature: 0.7,
    maxTokens: 1024,
  },
  DEEP_THEOLOGICAL: {
    primaryProvider: "anthropic",
    primaryModel: "claude-sonnet-4-6",
    fallbackProvider: "openai",
    fallbackModel: "gpt-4o",
    timeoutMs: 30_000,
    temperature: 0.7,
    maxTokens: 4096,
  },
  LONG_DOCUMENT: {
    primaryProvider: "anthropic",
    primaryModel: "claude-sonnet-4-6",   // 200k context window
    timeoutMs: 60_000,
    temperature: 0.5,
    maxTokens: 8192,
  },
  SAFETY_REVIEW: {
    primaryProvider: "anthropic",
    primaryModel: "claude-sonnet-4-6",
    timeoutMs: 15_000,
    temperature: 0.1,
    maxTokens: 2048,
  },
  MODERATION: {
    primaryProvider: "openai-moderation",
    primaryModel: "omni-moderation-latest",
    fallbackProvider: "anthropic",
    fallbackModel: "claude-haiku-4-5",
    timeoutMs: 5_000,
    temperature: 0.0,
    maxTokens: 512,
  },
  VERIFICATION: {
    primaryProvider: "anthropic",
    primaryModel: "claude-haiku-4-5",
    timeoutMs: 10_000,
    temperature: 0.2,
    maxTokens: 1024,
  },
};

// ─── Firestore Override Loader ────────────────────────────────────────────────

/**
 * Reads an optional Firestore document at model_router_config/{taskClass}.
 * Any field present overwrites the hardcoded default for that route.
 * Missing fields silently fall back to the hardcoded table.
 * Errors are caught and logged — routing never fails due to config fetch.
 */
async function loadRouteSpec(taskClass: TaskClass): Promise<RouteSpec> {
  const base: RouteSpec = { ...HARDCODED_ROUTES[taskClass] };
  try {
    const db = admin.firestore();
    const snap = await db
      .collection("model_router_config")
      .doc(taskClass)
      .get();
    if (snap.exists) {
      const ov = snap.data() as Partial<RouteSpec>;
      if (ov.primaryProvider !== undefined) base.primaryProvider = ov.primaryProvider;
      if (ov.primaryModel !== undefined) base.primaryModel = ov.primaryModel;
      if (ov.fallbackProvider !== undefined) base.fallbackProvider = ov.fallbackProvider;
      if (ov.fallbackModel !== undefined) base.fallbackModel = ov.fallbackModel;
      if (typeof ov.timeoutMs === "number") base.timeoutMs = ov.timeoutMs;
      if (typeof ov.temperature === "number") base.temperature = ov.temperature;
      if (typeof ov.maxTokens === "number") base.maxTokens = ov.maxTokens;
    }
  } catch (err) {
    functions.logger.warn("[modelRouter] Firestore config override fetch failed — using hardcoded defaults", { taskClass, err });
  }
  return base;
}

// ─── Firestore Audit Logger ───────────────────────────────────────────────────

interface AuditLog {
  taskClass: TaskClass;
  provider: string;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  outcome: "success" | "error";
  timestamp: admin.firestore.FieldValue;
}

async function writeAuditLog(entry: AuditLog): Promise<void> {
  try {
    await admin.firestore().collection("berean_model_logs").add(entry);
  } catch (err) {
    // Audit log failures are never fatal
    functions.logger.warn("[modelRouter] Audit log write failed", { err });
  }
}

// ─── Provider Implementations ─────────────────────────────────────────────────

/** Call Anthropic via the official SDK with an AbortSignal-based timeout. */
async function callAnthropic(
  model: string,
  prompt: string,
  systemPrompt: string | undefined,
  temperature: number,
  maxTokens: number,
  timeoutMs: number,
  anthropicKey: string
): Promise<ModelRouterResult> {
  const start = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const client = new Anthropic({ apiKey: anthropicKey });
    const response = await client.messages.create(
      {
        model,
        max_tokens: maxTokens,
        temperature,
        ...(systemPrompt ? { system: systemPrompt } : {}),
        messages: [{ role: "user", content: prompt }],
      },
      { signal: controller.signal }
    );

    const content = response.content
      .filter((b) => b.type === "text")
      .map((b) => (b as Anthropic.TextBlock).text)
      .join("");

    return {
      content,
      provider: "anthropic",
      model,
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
      latencyMs: Date.now() - start,
    };
  } finally {
    clearTimeout(timer);
  }
}

interface OpenAIChatResponse {
  choices?: Array<{ message?: { content?: string } }>;
  usage?: { prompt_tokens?: number; completion_tokens?: number };
  error?: { message?: string };
}

/** Call OpenAI chat completions via raw fetch (openai package not in package.json). */
async function callOpenAI(
  model: string,
  prompt: string,
  systemPrompt: string | undefined,
  temperature: number,
  maxTokens: number,
  timeoutMs: number,
  openaiKey: string
): Promise<ModelRouterResult> {
  const start = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const messages: Array<{ role: string; content: string }> = [];
    if (systemPrompt) messages.push({ role: "system", content: systemPrompt });
    messages.push({ role: "user", content: prompt });

    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({ model, messages, temperature, max_tokens: maxTokens }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`OpenAI HTTP ${res.status}: ${text.slice(0, 200)}`);
    }

    const data = (await res.json()) as OpenAIChatResponse;
    const content = data.choices?.[0]?.message?.content ?? "";
    return {
      content,
      provider: "openai",
      model,
      inputTokens: data.usage?.prompt_tokens ?? 0,
      outputTokens: data.usage?.completion_tokens ?? 0,
      latencyMs: Date.now() - start,
    };
  } finally {
    clearTimeout(timer);
  }
}

interface OpenAIModerationResponse {
  results?: Array<{
    flagged?: boolean;
    categories?: Record<string, boolean>;
    category_scores?: Record<string, number>;
  }>;
  error?: { message?: string };
}

/**
 * Call OpenAI Moderation endpoint.
 * Returns a synthetic content string (JSON-encoded result) so the caller
 * always gets a uniform ModelRouterResult regardless of task class.
 */
async function callOpenAIModeration(
  model: string,
  prompt: string,
  timeoutMs: number,
  openaiKey: string
): Promise<ModelRouterResult> {
  const start = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({ model, input: prompt }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`OpenAI Moderation HTTP ${res.status}: ${text.slice(0, 200)}`);
    }

    const data = (await res.json()) as OpenAIModerationResponse;
    return {
      content: JSON.stringify(data.results?.[0] ?? {}),
      provider: "openai-moderation",
      model,
      inputTokens: 0,   // Moderation API does not expose token counts
      outputTokens: 0,
      latencyMs: Date.now() - start,
    };
  } finally {
    clearTimeout(timer);
  }
}

// ─── Single Provider Dispatch ─────────────────────────────────────────────────

async function callProvider(
  provider: "anthropic" | "openai" | "openai-moderation",
  model: string,
  input: ModelRouterInput,
  spec: RouteSpec,
  anthropicKey: string,
  openaiKey: string
): Promise<ModelRouterResult> {
  const temp = input.temperature ?? spec.temperature;
  const tokens = input.maxTokens ?? spec.maxTokens;

  switch (provider) {
    case "anthropic":
      return callAnthropic(
        model,
        input.prompt,
        input.systemPrompt,
        temp,
        tokens,
        spec.timeoutMs,
        anthropicKey
      );

    case "openai":
      return callOpenAI(
        model,
        input.prompt,
        input.systemPrompt,
        temp,
        tokens,
        spec.timeoutMs,
        openaiKey
      );

    case "openai-moderation":
      return callOpenAIModeration(model, input.prompt, spec.timeoutMs, openaiKey);

    default: {
      // TypeScript exhaustiveness guard
      const _exhaustive: never = provider;
      throw new Error(`Unknown provider: ${_exhaustive}`);
    }
  }
}

// ─── Core Router Logic (shared by CF and internal helper) ─────────────────────

/**
 * Internal CF-to-CF callable helper.
 * Safe to call from other Cloud Functions without going through the HTTPS callable layer.
 */
export async function routeModel(input: ModelRouterInput): Promise<ModelRouterResult> {
  const { taskClass } = input;

  if (!(taskClass in HARDCODED_ROUTES)) {
    throw new HttpsError("invalid-argument", `Unknown taskClass: ${taskClass}`);
  }

  const spec = await loadRouteSpec(taskClass);
  const anthropicKey = anthropicApiKey.value();
  const openaiKey = openaiApiKey.value();

  let primaryError: unknown = null;
  let result: ModelRouterResult | null = null;

  // ── Primary attempt ──────────────────────────────────────────────────────────
  try {
    result = await callProvider(
      spec.primaryProvider,
      spec.primaryModel,
      input,
      spec,
      anthropicKey,
      openaiKey
    );
    await writeAuditLog({
      taskClass,
      provider: result.provider,
      model: result.model,
      latencyMs: result.latencyMs,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      outcome: "success",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    return result;
  } catch (err) {
    primaryError = err;
    functions.logger.warn("[modelRouter] Primary provider failed", {
      taskClass,
      provider: spec.primaryProvider,
      model: spec.primaryModel,
      err: String(err),
    });
    await writeAuditLog({
      taskClass,
      provider: spec.primaryProvider,
      model: spec.primaryModel,
      latencyMs: 0,
      inputTokens: 0,
      outputTokens: 0,
      outcome: "error",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // ── Fallback attempt ─────────────────────────────────────────────────────────
  if (spec.fallbackProvider && spec.fallbackModel) {
    try {
      result = await callProvider(
        spec.fallbackProvider,
        spec.fallbackModel,
        input,
        spec,
        anthropicKey,
        openaiKey
      );
      await writeAuditLog({
        taskClass,
        provider: result.provider,
        model: result.model,
        latencyMs: result.latencyMs,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        outcome: "success",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      return result;
    } catch (fallbackErr) {
      functions.logger.error("[modelRouter] Fallback provider also failed", {
        taskClass,
        fallbackProvider: spec.fallbackProvider,
        fallbackModel: spec.fallbackModel,
        primaryError: String(primaryError),
        fallbackError: String(fallbackErr),
      });
      await writeAuditLog({
        taskClass,
        provider: spec.fallbackProvider,
        model: spec.fallbackModel,
        latencyMs: 0,
        inputTokens: 0,
        outputTokens: 0,
        outcome: "error",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  // ── Both providers exhausted ─────────────────────────────────────────────────
  throw new HttpsError(
    "unavailable",
    `modelRouter: all providers failed for taskClass ${taskClass}. Primary error: ${String(primaryError)}`
  );
}

// ─── Public Cloud Function ────────────────────────────────────────────────────

/**
 * modelRouter — Trust Architecture Layer 1 HTTPS Callable
 *
 * Clients send { taskClass, prompt, systemPrompt?, temperature?, maxTokens? }
 * and receive { content, provider, model, inputTokens, outputTokens, latencyMs }.
 *
 * App Check is enforced — calls without a valid app attestation are rejected.
 * Authentication is required — anonymous or unauthenticated calls are rejected.
 */
export const modelRouter = onCall(
  {
    secrets: [anthropicApiKey, openaiApiKey],
    region: "us-east1",
    enforceAppCheck: true,
    timeoutSeconds: 65,   // must exceed the longest task timeout (LONG_DOCUMENT = 60s)
    memory: "256MiB",
  },
  async (request): Promise<ModelRouterResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check attestation required.");
    }

    const data = request.data as Partial<ModelRouterInput>;

    // ── Input validation ───────────────────────────────────────────────────────
    const taskClass = data.taskClass;
    if (!taskClass || !(taskClass in HARDCODED_ROUTES)) {
      throw new HttpsError(
        "invalid-argument",
        `taskClass must be one of: ${Object.keys(HARDCODED_ROUTES).join(", ")}`
      );
    }

    const prompt = data.prompt;
    if (!prompt || typeof prompt !== "string" || prompt.trim().length === 0) {
      throw new HttpsError("invalid-argument", "prompt is required and must be a non-empty string.");
    }

    const MAX_PROMPT_LENGTH = 200_000; // generous ceiling for LONG_DOCUMENT
    if (prompt.length > MAX_PROMPT_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `prompt exceeds maximum length of ${MAX_PROMPT_LENGTH} characters.`
      );
    }

    const systemPrompt =
      typeof data.systemPrompt === "string" ? data.systemPrompt.slice(0, 10_000) : undefined;

    const temperature =
      typeof data.temperature === "number"
        ? Math.min(Math.max(data.temperature, 0), 1)
        : undefined;

    const maxTokens =
      typeof data.maxTokens === "number"
        ? Math.min(Math.max(Math.floor(data.maxTokens), 1), 100_000)
        : undefined;

    const input: ModelRouterInput = { taskClass, prompt, systemPrompt, temperature, maxTokens };
    return routeModel(input);
  }
);
