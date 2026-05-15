import { clamp01 } from "./livingEntryScoring";

export interface ClassificationInput {
  title?: string;
  body?: string;
  type?: string;
}

export interface ClassificationResult {
  type: string;
  intent: string;
  spiritualWeight: number;
  emotionalWeight: number;
  scriptureRefs: string[];
  tags: string[];
  aiSummary: string;
  suggestedNextAction: string;
  reflectionPrompt: string;
  provider: "openai" | "claude" | "heuristic";
}

export interface ReflectionLearningResult {
  aiLearningSummary: string;
  nextTriggerSuggestion: string;
  provider: "claude" | "openai" | "heuristic";
}

export interface EvolutionResult {
  aiSummary: string;
  suggestedNextAction: string;
  provider: "claude" | "openai" | "heuristic";
}

type Provider = (input: ClassificationInput) => Promise<ClassificationResult | null>;

const SAFE_TYPES = new Set(["note", "reminder", "churchNote", "sermonInsight", "prayer", "followUp", "reflection", "task"]);
const SAFE_INTENTS = new Set(["spiritualGrowth", "churchVisit", "sermonReflection", "prayerCare", "relationship", "work", "rest", "personal", "unknown"]);
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";

export async function classifyWithFallback(
  input: ClassificationInput,
  primary: Provider,
  fallback: Provider
): Promise<ClassificationResult> {
  const primaryResult = await primary(input).catch(() => null);
  if (primaryResult) return sanitizeClassification(primaryResult);
  const fallbackResult = await fallback(input).catch(() => null);
  if (fallbackResult) return sanitizeClassification(fallbackResult);
  return heuristicClassification(input);
}

export async function openAIClassification(input: ClassificationInput): Promise<ClassificationResult | null> {
  if (!process.env.OPENAI_API_KEY) return null;

  const response = await postOpenAIJSON(
    systemPrompt("Classify a Living Entry for a spiritually-aware productivity app."),
    [
      "Return compact JSON only.",
      "Use only safe enum values.",
      "Do not add manipulative or shaming language.",
      "Store short summaries rather than repeating full sensitive text.",
    ].join(" "),
    {
      entry: redactInputForModel(input),
      schema: classificationSchemaDescription(),
    }
  );

  return parseClassification(response, "openai");
}

export async function claudeClassification(input: ClassificationInput): Promise<ClassificationResult | null> {
  if (!process.env.ANTHROPIC_API_KEY) return null;

  const response = await postClaudeJSON(
    systemPrompt("Classify a Living Entry for a spiritually-aware productivity app."),
    {
      instructions: [
        "Return JSON only.",
        "Use calm, non-coercive wording.",
        "Do not generate spiritual claims as certainty.",
        "Keep summaries short and privacy-aware.",
      ],
      entry: redactInputForModel(input),
      schema: classificationSchemaDescription(),
    }
  );

  return parseClassification(response, "claude");
}

export async function generateReflectionLearning(input: {
  entryType?: string;
  entryTitle?: string;
  answer?: string;
  helpfulness?: string;
}): Promise<ReflectionLearningResult> {
  const fallback = heuristicReflectionLearning(input);

  const claude = await generateClaudeReflectionLearning(input).catch(() => null);
  if (claude) return claude;

  const openAI = await generateOpenAIReflectionLearning(input).catch(() => null);
  if (openAI) return openAI;

  return fallback;
}

export async function generateEvolutionSuggestion(input: {
  type?: string;
  title?: string;
  body?: string;
  churchName?: string;
  state?: string;
}): Promise<EvolutionResult> {
  const fallback = heuristicEvolutionSuggestion(input);

  const claude = await generateClaudeEvolutionSuggestion(input).catch(() => null);
  if (claude) return claude;

  const openAI = await generateOpenAIEvolutionSuggestion(input).catch(() => null);
  if (openAI) return openAI;

  return fallback;
}

export function heuristicClassification(input: ClassificationInput): ClassificationResult {
  const text = `${input.title ?? ""} ${input.body ?? ""}`.toLowerCase();
  const type = safeType(input.type ?? inferType(text));
  const intent = safeIntent(inferIntent(text, type));
  const scriptureRefs = Array.from(text.matchAll(/\b([1-3]?\s?[A-Za-z]+)\s+\d+:\d+(?:-\d+)?\b/g)).map((match) => match[0]).slice(0, 3);
  const tags = Array.from(
    new Set([
      intent,
      type,
      text.includes("church") ? "church" : "",
      text.includes("prayer") ? "prayer" : "",
      text.includes("forgive") ? "forgiveness" : "",
    ].filter(Boolean))
  );
  return {
    type,
    intent,
    spiritualWeight: clamp01(type === "prayer" || type === "churchNote" ? 0.82 : text.includes("church") ? 0.68 : 0.38),
    emotionalWeight: clamp01(text.includes("overwhelmed") || text.includes("anxious") ? 0.72 : 0.34),
    scriptureRefs,
    tags,
    aiSummary: buildSummary(input),
    suggestedNextAction: buildNextAction(type, intent),
    reflectionPrompt: buildReflectionPrompt(type),
    provider: "heuristic",
  };
}

function sanitizeClassification(result: ClassificationResult): ClassificationResult {
  return {
    ...result,
    type: safeType(result.type),
    intent: safeIntent(result.intent),
    spiritualWeight: clamp01(result.spiritualWeight),
    emotionalWeight: clamp01(result.emotionalWeight),
    scriptureRefs: result.scriptureRefs.map((value) => value.trim()).filter(Boolean).slice(0, 5),
    tags: result.tags.map((value) => value.trim().toLowerCase()).filter(Boolean).slice(0, 8),
    aiSummary: trimSentence(result.aiSummary, 180),
    suggestedNextAction: trimSentence(result.suggestedNextAction, 180),
    reflectionPrompt: trimSentence(result.reflectionPrompt, 180),
  };
}

function parseClassification(payload: unknown, provider: "openai" | "claude"): ClassificationResult | null {
  if (!isRecord(payload)) return null;

  const type = safeType(asString(payload.type));
  const intent = safeIntent(asString(payload.intent));
  const scriptureRefs = asStringArray(payload.scriptureRefs).slice(0, 5);
  const tags = asStringArray(payload.tags).slice(0, 8);
  const aiSummary = trimSentence(asString(payload.aiSummary), 180);
  const suggestedNextAction = trimSentence(asString(payload.suggestedNextAction), 180);
  const reflectionPrompt = trimSentence(asString(payload.reflectionPrompt), 180);

  if (!aiSummary || !suggestedNextAction || !reflectionPrompt) return null;

  return {
    type,
    intent,
    spiritualWeight: clamp01(asNumber(payload.spiritualWeight)),
    emotionalWeight: clamp01(asNumber(payload.emotionalWeight)),
    scriptureRefs,
    tags,
    aiSummary,
    suggestedNextAction,
    reflectionPrompt,
    provider,
  };
}

async function generateClaudeReflectionLearning(input: {
  entryType?: string;
  entryTitle?: string;
  answer?: string;
  helpfulness?: string;
}): Promise<ReflectionLearningResult | null> {
  if (!process.env.ANTHROPIC_API_KEY) return null;

  const response = await postClaudeJSON(
    systemPrompt("Write gentle, pastoral reflection follow-up copy for a productivity app."),
    {
      instructions: [
        "Return JSON only.",
        "Keep it calm and non-judgmental.",
        "Avoid certainty about God's intent.",
      ],
      reflection: {
        entryType: safeType(input.entryType ?? "note"),
        entryTitle: sanitizeFreeText(input.entryTitle, 120),
        answer: sanitizeFreeText(input.answer, 240),
        helpfulness: sanitizeFreeText(input.helpfulness, 24),
      },
      schema: {
        aiLearningSummary: "string <= 160 chars",
        nextTriggerSuggestion: "string <= 160 chars",
      },
    }
  );

  return parseReflectionLearning(response, "claude");
}

async function generateOpenAIReflectionLearning(input: {
  entryType?: string;
  entryTitle?: string;
  answer?: string;
  helpfulness?: string;
}): Promise<ReflectionLearningResult | null> {
  if (!process.env.OPENAI_API_KEY) return null;

  const response = await postOpenAIJSON(
    systemPrompt("Write gentle reflection follow-up copy for a spiritually-aware productivity app."),
    "Return JSON only. Use calm language. Avoid shame or certainty.",
    {
      reflection: {
        entryType: safeType(input.entryType ?? "note"),
        entryTitle: sanitizeFreeText(input.entryTitle, 120),
        answer: sanitizeFreeText(input.answer, 240),
        helpfulness: sanitizeFreeText(input.helpfulness, 24),
      },
      schema: {
        aiLearningSummary: "string <= 160 chars",
        nextTriggerSuggestion: "string <= 160 chars",
      },
    }
  );

  return parseReflectionLearning(response, "openai");
}

function parseReflectionLearning(payload: unknown, provider: "claude" | "openai"): ReflectionLearningResult | null {
  if (!isRecord(payload)) return null;
  const aiLearningSummary = trimSentence(asString(payload.aiLearningSummary), 160);
  const nextTriggerSuggestion = trimSentence(asString(payload.nextTriggerSuggestion), 160);
  if (!aiLearningSummary || !nextTriggerSuggestion) return null;
  return { aiLearningSummary, nextTriggerSuggestion, provider };
}

function heuristicReflectionLearning(input: {
  entryType?: string;
  entryTitle?: string;
  answer?: string;
  helpfulness?: string;
}): ReflectionLearningResult {
  const type = safeType(input.entryType ?? "note");
  const helpfulness = String(input.helpfulness ?? "helpful");
  const answer = sanitizeFreeText(input.answer, 160);
  const title = sanitizeFreeText(input.entryTitle, 80) || "This entry";

  return {
    aiLearningSummary: answer
      ? `${title} reflected ${helpfulness === "mistimed" ? "timing friction" : "ongoing meaning"}: ${answer}`
      : `${title} was completed and can guide future timing.`,
    nextTriggerSuggestion: helpfulness === "mistimed"
      ? "Try surfacing this in a quieter window next time."
      : type === "prayer"
        ? "Keep future prayer reminders gentle and easy to revisit."
        : "Keep a similar reminder rhythm unless the user defers again.",
    provider: "heuristic",
  };
}

async function generateClaudeEvolutionSuggestion(input: {
  type?: string;
  title?: string;
  body?: string;
  churchName?: string;
  state?: string;
}): Promise<EvolutionResult | null> {
  if (!process.env.ANTHROPIC_API_KEY) return null;

  const response = await postClaudeJSON(
    systemPrompt("Generate gentle next-step suggestions for a spiritually-aware productivity app."),
    {
      instructions: [
        "Return JSON only.",
        "Stay encouraging but not pushy.",
        "Keep summaries short.",
      ],
      entry: sanitizeEvolutionPayload(input),
      schema: {
        aiSummary: "string <= 180 chars",
        suggestedNextAction: "string <= 180 chars",
      },
    }
  );

  return parseEvolutionResult(response, "claude");
}

async function generateOpenAIEvolutionSuggestion(input: {
  type?: string;
  title?: string;
  body?: string;
  churchName?: string;
  state?: string;
}): Promise<EvolutionResult | null> {
  if (!process.env.OPENAI_API_KEY) return null;

  const response = await postOpenAIJSON(
    systemPrompt("Generate gentle next-step suggestions for a spiritually-aware productivity app."),
    "Return JSON only. Keep language calm. Avoid shaming or artificial urgency.",
    {
      entry: sanitizeEvolutionPayload(input),
      schema: {
        aiSummary: "string <= 180 chars",
        suggestedNextAction: "string <= 180 chars",
      },
    }
  );

  return parseEvolutionResult(response, "openai");
}

function parseEvolutionResult(payload: unknown, provider: "claude" | "openai"): EvolutionResult | null {
  if (!isRecord(payload)) return null;
  const aiSummary = trimSentence(asString(payload.aiSummary), 180);
  const suggestedNextAction = trimSentence(asString(payload.suggestedNextAction), 180);
  if (!aiSummary || !suggestedNextAction) return null;
  return { aiSummary, suggestedNextAction, provider };
}

function heuristicEvolutionSuggestion(input: {
  type?: string;
  title?: string;
  body?: string;
  churchName?: string;
}): EvolutionResult {
  const type = safeType(input.type ?? "note");
  const title = sanitizeFreeText(input.title, 100) || "This entry";
  const churchName = sanitizeFreeText(input.churchName, 80);

  if (type === "churchNote") {
    return {
      aiSummary: `${title} is still active from your church reflection.`,
      suggestedNextAction: "Turn one takeaway into a prayer or one action for this week.",
      provider: "heuristic",
    };
  }

  if (type === "prayer") {
    return {
      aiSummary: `${title} has stayed present across multiple moments.`,
      suggestedNextAction: "Keep it active, mark it answered, or add a short reflection.",
      provider: "heuristic",
    };
  }

  if (type === "followUp" && churchName) {
    return {
      aiSummary: `${title} still points back to ${churchName}.`,
      suggestedNextAction: "Open service details or directions when you are ready to revisit it.",
      provider: "heuristic",
    };
  }

  return {
    aiSummary: `${title} is still open and may need a gentler next step.`,
    suggestedNextAction: "Keep it visible, defer it, or archive it if it no longer fits this week.",
    provider: "heuristic",
  };
}

function sanitizeEvolutionPayload(input: {
  type?: string;
  title?: string;
  body?: string;
  churchName?: string;
  state?: string;
}) {
  return {
    type: safeType(input.type ?? "note"),
    title: sanitizeFreeText(input.title, 120),
    body: sanitizeFreeText(input.body, 260),
    churchName: sanitizeFreeText(input.churchName, 80),
    state: sanitizeFreeText(input.state, 24),
  };
}

function inferType(text: string): string {
  if (text.includes("pray")) return "prayer";
  if (text.includes("sermon") || text.includes("church note")) return "churchNote";
  if (text.includes("follow up")) return "followUp";
  if (text.includes("remind")) return "reminder";
  return "note";
}

function inferIntent(text: string, type: string): string {
  if (type === "prayer") return "prayerCare";
  if (text.includes("visit church") || text.includes("service time")) return "churchVisit";
  if (type === "churchNote" || text.includes("sermon")) return "sermonReflection";
  if (text.includes("rest") || text.includes("sabbath")) return "rest";
  if (text.includes("work")) return "work";
  return "spiritualGrowth";
}

function buildSummary(input: ClassificationInput): string {
  const source = sanitizeFreeText(input.title || input.body || "This entry", 100);
  return `${source}${source.length >= 100 ? "..." : ""}`;
}

function buildNextAction(type: string, intent: string): string {
  if (type === "churchNote") return "Turn one takeaway into a prayer or one action this week.";
  if (type === "prayer") return "Keep it active, mark it answered, or add a short reflection.";
  if (intent === "churchVisit") return "Check service times or directions before Sunday.";
  return "Keep this visible, defer it, or archive it when it no longer fits.";
}

function buildReflectionPrompt(type: string): string {
  if (type === "churchNote") return "What should you remember from this?";
  if (type === "prayer") return "Keep praying, mark answered, or archive?";
  return "Was this helpful, mistimed, or no longer needed?";
}

function safeType(value: string): string {
  return SAFE_TYPES.has(value) ? value : "note";
}

function safeIntent(value: string): string {
  return SAFE_INTENTS.has(value) ? value : "unknown";
}

function redactInputForModel(input: ClassificationInput) {
  return {
    title: sanitizeFreeText(input.title, 140),
    body: sanitizeFreeText(input.body, 340),
    typeHint: safeType(input.type ?? "note"),
  };
}

function sanitizeFreeText(value: unknown, limit: number): string {
  return String(value ?? "")
    .replace(/\b[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}\b/g, "[redacted-email]")
    .replace(/\+?\d[\d\s().-]{7,}\d/g, "[redacted-phone]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limit);
}

function trimSentence(value: string, limit: number): string {
  return sanitizeFreeText(value, limit).replace(/\s+[,.!?;:]+$/g, "").trim();
}

function classificationSchemaDescription() {
  return {
    type: Array.from(SAFE_TYPES),
    intent: Array.from(SAFE_INTENTS),
    spiritualWeight: "number 0...1",
    emotionalWeight: "number 0...1",
    scriptureRefs: "array of <= 5 strings",
    tags: "array of <= 8 strings",
    aiSummary: "short string <= 180 chars",
    suggestedNextAction: "short string <= 180 chars",
    reflectionPrompt: "short string <= 180 chars",
  };
}

function systemPrompt(task: string): string {
  return [
    task,
    "You are working for Amen, a spiritually-aware notes and reminder app.",
    "Use gentle, calm language.",
    "Do not shame, pressure, or manipulate the user.",
    "Do not claim certainty about God's will or spiritual status.",
    "Return only the requested JSON object.",
  ].join(" ");
}

async function postOpenAIJSON(system: string, instructions: string, payload: unknown): Promise<unknown> {
  const response = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.OPENAI_LIVING_ENTRIES_MODEL ?? process.env.OPENAI_MODEL ?? "gpt-4.1-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: `${instructions}\n${JSON.stringify(payload)}` },
      ],
    }),
  });

  if (!response.ok) return null;
  const json = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  return parseJSONObject(json.choices?.[0]?.message?.content);
}

async function postClaudeJSON(system: string, payload: unknown): Promise<unknown> {
  const response = await fetch(CLAUDE_URL, {
    method: "POST",
    headers: {
      "x-api-key": String(process.env.ANTHROPIC_API_KEY),
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: process.env.CLAUDE_LIVING_ENTRIES_MODEL ?? process.env.ANTHROPIC_MODEL ?? "claude-3-5-sonnet-20241022",
      max_tokens: 500,
      temperature: 0.2,
      system,
      messages: [
        {
          role: "user",
          content: JSON.stringify(payload),
        },
      ],
    }),
  });

  if (!response.ok) return null;
  const json = await response.json() as { content?: Array<{ type?: string; text?: string }> };
  const text = json.content?.find((part) => part.type === "text")?.text;
  return parseJSONObject(text);
}

function parseJSONObject(text: string | undefined): unknown {
  if (!text) return null;
  const cleaned = text.trim().replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/\s*```$/i, "");
  try {
    return JSON.parse(cleaned);
  } catch {
    return null;
  }
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : Number(value ?? 0) || 0;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
