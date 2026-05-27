/**
 * selah/classifyVerseTheme.ts
 *
 * Firebase Cloud Function callable: classifyVerseTheme2
 *
 * Classifies a Bible verse into one of the 9 SelahSafetyTheme values and
 * suggests up to 4 SelahLensActionKind values in priority order. Results are
 * cached in Firestore for 7 days (verse themes are stable).
 *
 * Uses claude-haiku-4-5-20251001 for fast, low-cost classification.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import {
  ClassifyVerseThemeRequest,
  ClassifyVerseThemeResponse,
  SelahLensActionKind,
  SelahSafetyTheme,
  SelahTranslation,
} from "./types";
import {
  buildVerseThemePrompt,
  VERSE_THEME_PROMPT_VERSION,
} from "./selahPrompts";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const db = admin.firestore();
const ALLOWED_TRANSLATIONS: SelahTranslation[] = ["KJV", "ESV"];
const CLASSIFY_THEME_MODEL = "claude-haiku-4-5-20251001";
const THEME_CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days

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

// ── Cache tag ID ─────────────────────────────────────────────────────────────

function computeTagId(verseId: string, translation: SelahTranslation): string {
  return `${translation}_${verseId.replace(/[^a-zA-Z0-9]/g, "_")}_${VERSE_THEME_PROMPT_VERSION}`;
}

// ── Theme → suggested actions mapping (server-authoritative) ─────────────────

function suggestedActionsForTheme(theme: SelahSafetyTheme): SelahLensActionKind[] {
  switch (theme) {
    case "neutral":
    case "doubt":
    case "addiction":
      return ["understand", "crossReferences", "reflect", "pray"];
    case "anxiety":
    case "grief":
      return ["pray", "reflect", "understand", "addToSession"];
    case "selfHarm":
    case "abuse":
    case "trafficking":
    case "coercion":
      // No understand/addToSession for crisis themes — route to prayer + reflection only
      return ["pray", "reflect"];
  }
}

// ── Anthropic API call ────────────────────────────────────────────────────────

interface AnthropicContentBlock {
  type?: string;
  text?: string;
}

interface AnthropicResponse {
  content?: AnthropicContentBlock[];
}

async function callAnthropicClassifyTheme(
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
      model: CLASSIFY_THEME_MODEL,
      max_tokens: 256,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    console.error("selah_classify_theme_anthropic_error", {
      status: response.status,
      body: body.slice(0, 200),
    });
    throw new HttpsError("internal", `Anthropic API returned ${response.status}`);
  }

  const result = (await response.json()) as AnthropicResponse;
  const text = result.content?.[0]?.text ?? "";
  if (!text) {
    throw new HttpsError("internal", "Model returned an empty classification response");
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

export const classifyVerseTheme2 = onCall(
  {
    enforceAppCheck: true,
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
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
    const data = request.data as Partial<ClassifyVerseThemeRequest>;

    if (typeof data.verseId !== "string" || data.verseId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "verseId is required.");
    }

    if (!ALLOWED_TRANSLATIONS.includes(data.translation as SelahTranslation)) {
      throw new HttpsError("invalid-argument", "translation must be KJV or ESV.");
    }

    if (
      typeof data.verseText !== "string" ||
      data.verseText.trim().length === 0 ||
      data.verseText.length > 2000
    ) {
      throw new HttpsError(
        "invalid-argument",
        "verseText must be a non-empty string of at most 2000 characters."
      );
    }

    const verseId = stripControlChars(data.verseId).slice(0, 100);
    const translation = data.translation as SelahTranslation;
    const verseText = stripControlChars(data.verseText).slice(0, 2000);

    // ── Cache lookup ────────────────────────────────────────────────────────
    const tagId = computeTagId(verseId, translation);
    const tagRef = db.collection("verseThemeTags").doc(tagId);
    const cached = await tagRef.get();

    if (cached.exists) {
      const cachedData = cached.data();
      const updatedAt: admin.firestore.Timestamp | undefined = cachedData?.updatedAt;
      if (updatedAt && Date.now() - updatedAt.toMillis() < THEME_CACHE_TTL_MS) {
        const cachedTheme = cachedData?.theme as SelahSafetyTheme | undefined;
        const cachedConfidence = cachedData?.confidence as number | undefined;
        if (cachedTheme && ALLOWED_THEMES.includes(cachedTheme)) {
          const cached: ClassifyVerseThemeResponse = {
            verseId,
            theme: cachedTheme,
            confidence: cachedConfidence ?? 0.7,
            suggestedActions: suggestedActionsForTheme(cachedTheme),
            promptVersion: VERSE_THEME_PROMPT_VERSION,
          };
          return cached;
        }
      }
    }

    // ── Anthropic call ──────────────────────────────────────────────────────
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
      throw new HttpsError("internal", "Anthropic API key is not configured.");
    }

    const prompt = buildVerseThemePrompt(verseId, verseText);
    const rawText = await callAnthropicClassifyTheme(apiKey, prompt);

    // ── Parse and validate ──────────────────────────────────────────────────
    let parsed: { theme?: string; confidence?: number; suggestedActions?: string[] };

    try {
      parsed = JSON.parse(extractJSON(rawText)) as typeof parsed;
    } catch {
      console.error("selah_classify_theme_parse_failure", {
        verseId,
        rawSnippet: rawText.slice(0, 200),
      });
      throw new HttpsError(
        "internal",
        "Theme classification response could not be parsed."
      );
    }

    // Validate the theme value against the known enum
    const rawTheme = parsed.theme as string | undefined;
    if (!rawTheme || !ALLOWED_THEMES.includes(rawTheme as SelahSafetyTheme)) {
      console.warn("selah_classify_theme_unknown", { verseId, rawTheme });
      // Fall back to neutral rather than failing — classification is advisory
      parsed.theme = "neutral";
    }

    const theme = parsed.theme as SelahSafetyTheme;
    const confidence =
      typeof parsed.confidence === "number" &&
      parsed.confidence >= 0 &&
      parsed.confidence <= 1
        ? parsed.confidence
        : 0.7;

    // Server-authoritative action mapping — ignore the model's suggestedActions
    const suggestedActions = suggestedActionsForTheme(theme);

    const result: ClassifyVerseThemeResponse = {
      verseId,
      theme,
      confidence,
      suggestedActions,
      promptVersion: VERSE_THEME_PROMPT_VERSION,
    };

    // ── Persist to cache ────────────────────────────────────────────────────
    await tagRef.set(
      {
        id: tagId,
        verseId,
        translation,
        theme,
        confidence,
        promptVersion: VERSE_THEME_PROMPT_VERSION,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return result;
  }
);
