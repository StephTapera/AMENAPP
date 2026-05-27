/**
 * selah/classifySafety.ts
 *
 * Firebase Cloud Function callable: classifySafety2
 *
 * Classifies a user's private reflection text into one of the 9 SelahSafetyTheme
 * values. For crisis themes (selfHarm, abuse, trafficking, coercion), the response
 * includes a supportPayload with grounding steps, a trusted-human prompt, and
 * vetted crisis resource links.
 *
 * Uses claude-haiku-4-5-20251001 for fast classification. The support payload is
 * constructed server-side — the model only classifies, never generates support content.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
  ClassifySafetyRequest,
  ClassifySafetyResponse,
  SelahSafetyTheme,
  SelahSupportPayload,
  safetyThemeBlocksGeneration,
} from "./types";
import {
  buildSafetyClassifierPrompt,
  SAFETY_CLASSIFIER_PROMPT_VERSION,
} from "./selahPrompts";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const CLASSIFY_SAFETY_MODEL = "claude-haiku-4-5-20251001";

const ALLOWED_THEMES: SelahSafetyTheme[] = [
  "neutral",
  "anxiety",
  "grief",
  "doubt",
  "addiction",
  "selfHarm",
  "abuse",
  "trafficking",
  "coercion",
];

// ── Input sanitisation ────────────────────────────────────────────────────────

function stripControlChars(input: string): string {
  // eslint-disable-next-line no-control-regex
  return input.replace(/[ --]/g, "").trim();
}

// ── Crisis support payload (server-constructed, never model-generated) ────────

function buildCrisisSupportPayload(): SelahSupportPayload {
  return {
    groundingTitle: "You're not alone",
    groundingSteps: [
      "Take a slow breath",
      "You are safe right now",
      "What you're feeling is real and valid",
    ],
    trustedHumanPrompt:
      "Please reach out to someone you trust — a pastor, counselor, or trusted friend.",
    resourceLinks: [
      {
        id: "crisis-text",
        title: "Crisis Text Line",
        url: "https://www.crisistextline.org",
        region: "US",
      },
      {
        id: "988",
        title: "988 Suicide & Crisis Lifeline",
        url: "https://988lifeline.org",
        region: "US",
      },
      {
        id: "iasp",
        title: "International Crisis Centres",
        url: "https://www.iasp.info/resources/Crisis_Centres/",
        region: null,
      },
    ],
  };
}

// ── Anthropic API call ────────────────────────────────────────────────────────

interface AnthropicContentBlock {
  type?: string;
  text?: string;
}

interface AnthropicResponse {
  content?: AnthropicContentBlock[];
}

async function callAnthropicClassifySafety(
  apiKey: string,
  prompt: string
): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: CLASSIFY_SAFETY_MODEL,
      max_tokens: 128,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    console.error("selah_classify_safety_anthropic_error", {
      status: response.status,
      body: body.slice(0, 200),
    });
    throw new HttpsError("internal", `Anthropic API returned ${response.status}`);
  }

  const result = (await response.json()) as AnthropicResponse;
  const text = result.content?.[0]?.text ?? "";
  if (!text) {
    throw new HttpsError("internal", "Model returned an empty safety classification response");
  }
  return text;
}

// ── JSON extraction ───────────────────────────────────────────────────────────

function extractJSON(raw: string): string {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) return fenced[1].trim();
  const firstBrace = raw.indexOf("{");
  const lastBrace = raw.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    return raw.slice(firstBrace, lastBrace + 1);
  }
  return raw.trim();
}

// ── Callable ──────────────────────────────────────────────────────────────────

export const classifySafety2 = onCall(
  {
    enforceAppCheck: true,
    secrets: [anthropicApiKey],
    timeoutSeconds: 30,
    memory: "128MiB",
    region: "us-central1",
  },
  async (request) => {
    // ── Auth + App Check guard ──────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const uid = request.auth.uid;

    // ── Rate limiting ───────────────────────────────────────────────────────
    await enforceRateLimit(uid, [
      RATE_LIMITS.AI_PER_MINUTE,
      RATE_LIMITS.AI_PER_DAY,
    ]);

    // ── Input validation ────────────────────────────────────────────────────
    const data = request.data as Partial<ClassifySafetyRequest>;

    if (
      typeof data.reflectionText !== "string" ||
      data.reflectionText.trim().length === 0 ||
      data.reflectionText.length > 8000
    ) {
      throw new HttpsError(
        "invalid-argument",
        "reflectionText must be a non-empty string of at most 8000 characters."
      );
    }

    const reflectionText = stripControlChars(data.reflectionText).slice(0, 8000);

    // Final length guard after stripping — must have at least one character
    if (reflectionText.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "reflectionText must contain at least one printable character."
      );
    }

    // ── Anthropic call ──────────────────────────────────────────────────────
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
      throw new HttpsError("internal", "Anthropic API key is not configured.");
    }

    const prompt = buildSafetyClassifierPrompt(reflectionText);
    const rawText = await callAnthropicClassifySafety(apiKey, prompt);

    // ── Parse result ────────────────────────────────────────────────────────
    let parsed: { theme?: string; confidence?: number };

    try {
      parsed = JSON.parse(extractJSON(rawText)) as typeof parsed;
    } catch {
      console.error("selah_classify_safety_parse_failure", {
        rawSnippet: rawText.slice(0, 200),
      });
      throw new HttpsError(
        "internal",
        "Safety classification response could not be parsed."
      );
    }

    // Validate theme; default to neutral on unknown value to avoid hard failures
    const rawTheme = parsed.theme as string | undefined;
    let theme: SelahSafetyTheme = "neutral";
    if (rawTheme && ALLOWED_THEMES.includes(rawTheme as SelahSafetyTheme)) {
      theme = rawTheme as SelahSafetyTheme;
    } else if (rawTheme) {
      console.warn("selah_classify_safety_unknown_theme", { rawTheme });
    }

    const confidence =
      typeof parsed.confidence === "number" &&
      parsed.confidence >= 0 &&
      parsed.confidence <= 1
        ? parsed.confidence
        : 0.7;

    // ── Compute generation/share permissions ────────────────────────────────
    const blocked = safetyThemeBlocksGeneration(theme);
    const canGenerateDevotional = !blocked;
    const canShare = !blocked;

    // ── Support payload for crisis themes (server-constructed) ───────────────
    const supportPayload = blocked ? buildCrisisSupportPayload() : undefined;

    const result: ClassifySafetyResponse = {
      theme,
      confidence,
      canGenerateDevotional,
      canShare,
      supportPayload,
      promptVersion: SAFETY_CLASSIFIER_PROMPT_VERSION,
    };

    return result;
  }
);
