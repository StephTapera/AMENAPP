/**
 * amenRouting.ts
 *
 * Provider-abstracted callModel abstraction for AMEN Living Intelligence.
 * Feature code NEVER imports provider SDKs directly — all routing goes through here.
 *
 * Rules:
 *  - intelligence.summarize → Anthropic (Claude), fail-closed: no fallback, no fabrication
 *  - intelligence.classify_need / .match / .world_response → Anthropic, distinct system prompts
 *  - moderateContent → Perspective API when available, strict keyword deny-list fallback
 *  - EVERY external service call is fail-closed: if unavailable, refuse — never fabricate
 */

import { defineSecret } from "firebase-functions/params";

export const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
export const PERSPECTIVE_API_KEY = defineSecret("PERSPECTIVE_API_KEY");

// ─── Task types ────────────────────────────────────────────────────────────────

export type ModelTask =
  | "intelligence.summarize"       // Berean/Claude, fail-closed, REAL citations only
  | "intelligence.classify_need"   // need detection over posts/prayers/announcements
  | "intelligence.match"           // event & prayer matching → matchScore + matchReasons
  | "intelligence.world_response"  // GLOBAL cards: known/contested/how-to-respond
  | "catalog_qa";                  // RAG-powered creator catalog question answering

export interface CallModelInput {
  task: ModelTask;
  input: string;
  context?: Record<string, unknown>;
  userId: string;
  safetyLevel?: "standard" | "strict";
}

export interface CallModelOutput {
  result?: unknown;
  error?: string;
  model?: string;
  taskId?: string;
}

export interface ModerationResult {
  safe: boolean;
  reason?: string;
}

// ─── System prompts per task ────────────────────────────────────────────────────

const SYSTEM_PROMPTS: Record<ModelTask, string> = {
  "intelligence.summarize": `You are Berean, a theologically rigorous AI assistant for the AMEN platform.
Your role is to summarize content with REAL scripture citations only — never fabricate references.
Format: up to 3 concise bullet points. Each bullet may include one verified scripture reference (book chapter:verse).
If you cannot summarize accurately, respond with {"error":"summarization_unavailable"}.
Never speculate about facts, events, or people. Refuse if you cannot verify.`,

  "intelligence.classify_need": `You are an AI assistant for AMEN that classifies community needs.
Given a post, prayer, or announcement, identify:
- needType: "VOLUNTEER" | "DONATION" | "PRAYER" | "PRESENCE" | "SKILL" | "RESOURCE" | "NONE"
- urgency: "IMMEDIATE" | "THIS_WEEK" | "ONGOING" | "NONE"
- confidence: 0.0–1.0
Respond ONLY with valid JSON. Never invent needs that are not explicit in the input.`,

  "intelligence.match": `You are an AMEN platform AI that matches opportunities to users.
Given a user context and an opportunity description, compute:
- matchScore: 0–100 integer
- matchReasons: string[] (1–4 brief plain-English reasons e.g. "Your church is hosting this")
Rules: Only reference facts present in the input. Never fabricate church names, dates, or relationships.
Respond ONLY with valid JSON: {"matchScore": number, "matchReasons": string[]}`,

  "intelligence.world_response": `You are a trusted Christian world-events reporter for the AMEN platform.
Your job is to help the Christian community understand world events and respond faithfully.

ABSOLUTE RULES:
1. Never assert unverified facts. If something is disputed, say so in whatIsContested.
2. Never produce partisan political framing, editorial commentary, or hot takes.
3. Never tell users WHAT to think politically — only what is factually known and how Christians can respond.
4. Cite the original source; never fabricate quotes or statistics.
5. If input mentions disaster/conflict/persecution, use a lament-and-act frame: acknowledge suffering with compassion before moving to response.
6. If you do not have reliable information, say "Details are still emerging" rather than guessing.
If the topic is too politically charged or ambiguous, respond with {"error":"topic_requires_human_discernment"}.
Respond ONLY with valid JSON: {"whatIsKnown":"...","whatIsContested":"...","howToRespond":"..."}`,

  "catalog_qa": `You are a catalog Q&A assistant for the AMEN platform.
You answer questions about a creator's published works ONLY from the source excerpts provided.

ABSOLUTE RULES:
1. CITE-OR-REFUSE: every answer must include at least one citation from the provided sources. If no qualifying source exists, respond with {"refused":true,"refusalReason":"no_qualifying_source"}.
2. NEVER fabricate quotes, statements, or attribute beliefs to the creator without a direct citation.
3. Distinguish creator_said (direct quote) from ai_summary (AI paraphrase). Never blend them.
4. If you cannot answer accurately from the provided sources, refuse.
Respond ONLY with valid JSON: {"answer":"...","citations":[{"workId":"...","snippet":"...","confidence":0.0}],"mode":"creator_said"|"ai_summary","confidence":0.0,"refused":false}`,
};

// ─── callModel ─────────────────────────────────────────────────────────────────

/**
 * Route a model task to the correct provider.
 * Fail-closed: if the provider is unavailable, return {error: ...} — never fabricate.
 */
export async function callModel(input: CallModelInput): Promise<CallModelOutput> {
  const apiKey = ANTHROPIC_API_KEY.value();

  if (!apiKey) {
    // Fail-closed: no key = no inference
    return { error: "model_provider_unavailable" };
  }

  const systemPrompt = SYSTEM_PROMPTS[input.task];
  const model = "claude-haiku-4-5"; // cost-efficient tier for intelligence tasks

  let userMessage = input.input;
  if (input.context && Object.keys(input.context).length > 0) {
    userMessage = `Context: ${JSON.stringify(input.context)}\n\n${input.input}`;
  }

  const maxTokens = input.task === "intelligence.summarize" ? 512 : 256;

  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        max_tokens: maxTokens,
        system: systemPrompt,
        messages: [{ role: "user", content: userMessage }],
      }),
      signal: AbortSignal.timeout(15_000),
    });

    if (!response.ok) {
      // Provider returned an error status — fail-closed
      return { error: "model_provider_unavailable", model };
    }

    const data = (await response.json()) as {
      content?: Array<{ type: string; text: string }>;
      error?: { message: string };
    };

    if (data.error) {
      return { error: "model_provider_unavailable", model };
    }

    const rawText = data.content?.find((b) => b.type === "text")?.text ?? "";

    if (!rawText) {
      return { error: "model_empty_response", model };
    }

    // For JSON tasks, parse and return; for summarize, return raw text
    if (input.task === "intelligence.summarize") {
      // summarize may be plain bullets or JSON error sentinel
      if (rawText.trim().startsWith("{")) {
        try {
          const parsed = JSON.parse(rawText) as unknown;
          return { result: parsed, model };
        } catch {
          // Wasn't JSON — treat as text bullets
        }
      }
      return { result: rawText, model };
    }

    // All other tasks expect JSON
    try {
      const parsed = JSON.parse(rawText) as unknown;
      return { result: parsed, model };
    } catch {
      return { error: "model_invalid_response_format", model };
    }
  } catch (err: unknown) {
    // Network timeout, DNS failure, etc — fail-closed
    const isTimeout =
      err instanceof Error &&
      (err.name === "TimeoutError" || err.message.includes("timeout"));
    return {
      error: isTimeout ? "model_timeout" : "model_provider_unavailable",
      model,
    };
  }
}

// ─── Strict keyword deny-list for fallback moderation ──────────────────────────

// Words/phrases that are categorically unacceptable; list is intentionally conservative.
// Fail-closed fallback only — Perspective API is always preferred when available.
const DENY_LIST_PATTERNS: RegExp[] = [
  /\b(csam|child\s+porn|cp\s+link)\b/i,
  /\b(bomb\s+making|how\s+to\s+make\s+a\s+bomb|ied\s+instructions)\b/i,
  /\b(suicide\s+method|how\s+to\s+kill\s+myself)\b/i,
  /\b(kys|kill\s+yourself)\b/i,
  /\b(n[i1]gg[ae]r|f[a@]gg[o0]t|ch[i1]nk|sp[i1]c|w[e3]tb[a@]ck)\b/i,
];

function matchesDenyList(text: string): { matched: boolean; pattern?: string } {
  for (const pattern of DENY_LIST_PATTERNS) {
    if (pattern.test(text)) {
      return { matched: true, pattern: pattern.source };
    }
  }
  return { matched: false };
}

// ─── moderateContent ──────────────────────────────────────────────────────────

/**
 * Fail-closed content moderation.
 * Tries Perspective API first; falls back to keyword deny-list if key unavailable.
 * If Perspective API is DOWN (network error), returns {safe: false} — never allow through.
 */
export async function moderateContent(text: string): Promise<ModerationResult> {
  if (!text || text.trim().length === 0) {
    return { safe: true };
  }

  // Always run the local deny-list first — it's synchronous and catches hard blocks
  const denyCheck = matchesDenyList(text);
  if (denyCheck.matched) {
    return { safe: false, reason: "content_matches_deny_list" };
  }

  const perspectiveKey = PERSPECTIVE_API_KEY.value();

  if (!perspectiveKey) {
    // No Perspective key — deny-list passed, allow as best-effort
    // This is intentionally NOT fail-closed for the fallback path: deny-list
    // passed means content is not categorically harmful.
    return { safe: true };
  }

  // Perspective API call
  const strictThreshold = 0.75;
  const standardThreshold = 0.85;

  try {
    const response = await fetch(
      `https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze?key=${perspectiveKey}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          comment: { text },
          requestedAttributes: {
            TOXICITY: {},
            SEVERE_TOXICITY: {},
            IDENTITY_ATTACK: {},
            THREAT: {},
            SEXUALLY_EXPLICIT: {},
          },
          languages: ["en"],
        }),
        signal: AbortSignal.timeout(8_000),
      }
    );

    if (!response.ok) {
      // Perspective API returned error status — fail-closed
      return { safe: false, reason: "moderation_unavailable" };
    }

    const data = (await response.json()) as {
      attributeScores?: Record<
        string,
        { summaryScore?: { value: number } }
      >;
    };

    const scores = data.attributeScores ?? {};

    // SEVERE_TOXICITY uses a lower threshold
    const severeToxicity = scores["SEVERE_TOXICITY"]?.summaryScore?.value ?? 0;
    if (severeToxicity >= strictThreshold) {
      return { safe: false, reason: `severe_toxicity:${severeToxicity.toFixed(2)}` };
    }

    const checkAttrs: Array<{ key: string; threshold: number }> = [
      { key: "TOXICITY", threshold: standardThreshold },
      { key: "IDENTITY_ATTACK", threshold: strictThreshold },
      { key: "THREAT", threshold: strictThreshold },
      { key: "SEXUALLY_EXPLICIT", threshold: strictThreshold },
    ];

    for (const { key, threshold } of checkAttrs) {
      const score = scores[key]?.summaryScore?.value ?? 0;
      if (score >= threshold) {
        return { safe: false, reason: `${key.toLowerCase()}:${score.toFixed(2)}` };
      }
    }

    return { safe: true };
  } catch {
    // Network failure, timeout — fail-closed: refuse, don't allow through
    return { safe: false, reason: "moderation_unavailable" };
  }
}
