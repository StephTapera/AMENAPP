import * as admin from "firebase-admin";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  BereanStudySheetRequest,
  BereanStudySheetResponse,
  ClassifySafetyRequest,
  ClassifySafetyResponse,
  ClassifyVerseThemeRequest,
  ClassifyVerseThemeResponse,
  SELAH_SAFETY_PROMPT_VERSION,
  SELAH_STUDY_PROMPT_VERSION,
  SELAH_THEME_PROMPT_VERSION,
  SelahLensActionKind,
  SelahSafetyTheme,
  SelahTranslation,
  safetyThemeBlocksGeneration,
} from "./contracts";
import { STUDY_SHEET_SYSTEM_PROMPT_V1, STUDY_SHEET_USER_PROMPT_V1 } from "./prompts/studySheet.v1";
import { REFLECTION_SAFETY_CLASSIFIER_PROMPT_V1, VERSE_THEME_CLASSIFIER_PROMPT_V1 } from "./prompts/classifiers.v1";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const modelId = "claude-haiku-4-5-20251001";
const sensitiveThemes: SelahSafetyTheme[] = ["selfHarm", "abuse", "trafficking", "coercion"];
const allowedTranslations: SelahTranslation[] = ["KJV", "ESV"];
const allowedThemes: SelahSafetyTheme[] = ["neutral", "anxiety", "grief", "doubt", "addiction", ...sensitiveThemes];

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

export const bereanStudySheet = onCall(
  { region: "us-central1", timeoutSeconds: 60, memory: "256MiB", enforceAppCheck: true, secrets: [anthropicApiKey] },
  async (request) => {
    requireCallableAuth(request.auth, request.app);
    const input = validateStudySheetRequest(request.data);
    const cacheKey = studySheetCacheKey(input.verseId, input.translation, SELAH_STUDY_PROMPT_VERSION);
    const cacheRef = db().collection("studySheetCache").doc(cacheKey);
    const cached = await cacheRef.get();
    if (cached.exists) {
      const cachedData = cached.data()?.response as BereanStudySheetResponse | undefined;
      if (cachedData) {
        assertNoScriptureTextInStudySheet(cachedData);
        return cachedData;
      }
    }

    const generated = await generateStudySheet(input, cacheKey);
    assertNoScriptureTextInStudySheet(generated);
    await cacheRef.set({
      id: cacheKey,
      verseId: input.verseId,
      translation: input.translation,
      response: generated,
      promptVersion: SELAH_STUDY_PROMPT_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
    });
    return generated;
  }
);

export const classifyVerseTheme = onCall(
  { region: "us-central1", timeoutSeconds: 30, memory: "128MiB", enforceAppCheck: true, secrets: [anthropicApiKey] },
  async (request) => {
    requireCallableAuth(request.auth, request.app);
    const input = validateVerseThemeRequest(request.data);
    const tagId = studySheetCacheKey(input.verseId, input.translation, SELAH_THEME_PROMPT_VERSION);
    const heuristic = classifyThemeHeuristically(input.verseText);
    const response: ClassifyVerseThemeResponse = {
      verseId: input.verseId,
      theme: heuristic.theme,
      confidence: heuristic.confidence,
      suggestedActions: actionsForTheme(heuristic.theme),
      promptVersion: SELAH_THEME_PROMPT_VERSION,
    };
    await db().collection("verseThemeTags").doc(tagId).set({
      id: tagId,
      verseId: input.verseId,
      translation: input.translation,
      theme: response.theme,
      confidence: response.confidence,
      promptVersion: response.promptVersion,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return response;
  }
);

export const classifySafety = onCall(
  { region: "us-central1", timeoutSeconds: 30, memory: "128MiB", enforceAppCheck: true, secrets: [anthropicApiKey] },
  async (request) => {
    requireCallableAuth(request.auth, request.app);
    return buildSafetyResponse(validateSafetyRequest(request.data).reflectionText);
  }
);

export async function generateStudySheet(input: BereanStudySheetRequest, cacheKey: string): Promise<BereanStudySheetResponse> {
  const apiKey = anthropicApiKey.value();
  const generatedAt = new Date().toISOString();
  let parsed: Partial<BereanStudySheetResponse> | null = null;
  let provider = "selah-fallback";
  let model = "rule-based-fallback";
  let runId = `fallback_${Date.now()}`;

  if (apiKey) {
    try {
      const raw = await callAnthropicJSON(apiKey, input);
      parsed = JSON.parse(raw) as Partial<BereanStudySheetResponse>;
      provider = "anthropic";
      model = modelId;
      runId = `anthropic_${Date.now()}`;
    } catch (error) {
      console.warn("selah_study_sheet_ai_fallback", { verseId: input.verseId, error: error instanceof Error ? error.message : String(error) });
    }
  }

  const fallback = fallbackStudySheet(input);
  return sanitizeStudySheetResponse({
    cacheKey,
    verseId: input.verseId,
    translation: input.translation,
    layers: parsed?.layers ?? fallback.layers,
    crossReferences: sanitizeVerseIds(parsed?.crossReferences ?? fallback.crossReferences),
    provenance: {
      provider,
      model,
      runId,
      scriptureSource: "client_firestore_scripture_store",
      scriptureLoadedByClient: true,
      factInterpretationSeparated: true,
    },
    generatedAt,
    promptVersion: SELAH_STUDY_PROMPT_VERSION,
  });
}

export function validateStudySheetRequest(data: unknown): BereanStudySheetRequest {
  const value = data as Partial<BereanStudySheetRequest>;
  if (!value || typeof value.verseId !== "string" || value.verseId.trim().length === 0) {
    throw new HttpsError("invalid-argument", "verseId is required.");
  }
  if (!allowedTranslations.includes(value.translation as SelahTranslation)) {
    throw new HttpsError("invalid-argument", "translation must be KJV or ESV.");
  }
  if (typeof value.verseText !== "string" || value.verseText.trim().length === 0 || value.verseText.length > 3000) {
    throw new HttpsError("invalid-argument", "verseText is required and must be under 3000 characters.");
  }
  return {
    verseId: value.verseId.trim(),
    translation: value.translation as SelahTranslation,
    verseText: sanitizeInput(value.verseText, 3000),
    locale: typeof value.locale === "string" ? value.locale.slice(0, 16) : undefined,
  };
}

export function validateVerseThemeRequest(data: unknown): ClassifyVerseThemeRequest {
  const value = validateStudySheetRequest(data);
  return { verseId: value.verseId, translation: value.translation, verseText: value.verseText };
}

export function validateSafetyRequest(data: unknown): ClassifySafetyRequest {
  const value = data as Partial<ClassifySafetyRequest>;
  if (!value || typeof value.reflectionText !== "string" || value.reflectionText.trim().length === 0 || value.reflectionText.length > 8000) {
    throw new HttpsError("invalid-argument", "reflectionText is required and must be under 8000 characters.");
  }
  return {
    reflectionText: sanitizeInput(value.reflectionText, 8000),
    verseId: typeof value.verseId === "string" ? value.verseId.slice(0, 120) : undefined,
    locale: typeof value.locale === "string" ? value.locale.slice(0, 16) : undefined,
  };
}

export function buildSafetyResponse(text: string): ClassifySafetyResponse {
  const classification = classifyThemeHeuristically(text);
  const theme = classification.theme;
  const blocked = safetyThemeBlocksGeneration(theme);
  return {
    theme,
    confidence: classification.confidence,
    canGenerateDevotional: !blocked,
    canShare: !blocked,
    supportPayload: blocked ? supportPayloadFor(theme) : undefined,
    promptVersion: SELAH_SAFETY_PROMPT_VERSION,
  };
}

export function classifyThemeHeuristically(text: string): { theme: SelahSafetyTheme; confidence: number } {
  const lower = text.toLowerCase();
  const checks: Array<[SelahSafetyTheme, RegExp, number]> = [
    ["selfHarm", /(kill myself|end my life|want to die|suicid|self[- ]?harm|hurt myself|can't keep going)/i, 0.98],
    ["trafficking", /(traffick|being sold|forced sex|pimp|held against my will)/i, 0.95],
    ["coercion", /(coerc|forced me|threatened me|blackmail|won't let me leave)/i, 0.9],
    ["abuse", /(abuse|hit me|hurting me|unsafe at home|assault|domestic violence)/i, 0.9],
    ["addiction", /(addict|relapse|porn|alcohol|drugs|substance|can't stop)/i, 0.82],
    ["grief", /(grief|mourning|died|loss|funeral|widow|weeping)/i, 0.78],
    ["anxiety", /(anxious|anxiety|afraid|fear|worry|panic|overwhelmed)/i, 0.76],
    ["doubt", /(doubt|unbelief|questioning|confused|deconstruct|faith crisis)/i, 0.72],
  ];
  for (const [theme, pattern, confidence] of checks) {
    if (pattern.test(lower)) return { theme, confidence };
  }
  return { theme: "neutral", confidence: 0.64 };
}

export function actionsForTheme(theme: SelahSafetyTheme): SelahLensActionKind[] {
  switch (theme) {
    case "anxiety":
    case "grief":
      return ["pray", "addToSession", "reflect", "understand", "more"];
    case "doubt":
    case "neutral":
      return ["understand", "crossReferences", "reflect", "pray", "more"];
    case "addiction":
      return ["pray", "reflect", "addToSession", "understand", "more"];
    case "selfHarm":
    case "abuse":
    case "trafficking":
    case "coercion":
      return ["pray", "reflect", "more"];
  }
}

export function studySheetCacheKey(verseId: string, translation: SelahTranslation, promptVersion: string): string {
  return `${translation}_${verseId}_${promptVersion}`.replace(/[^A-Za-z0-9_-]/g, "_");
}

export function assertNoScriptureTextInStudySheet(response: BereanStudySheetResponse): void {
  const forbidden = ["verseText", "scriptureText", "passageText", "quotedText"];
  const seen = new Set<object>();
  function visit(value: unknown): void {
    if (!value || typeof value !== "object") return;
    if (seen.has(value as object)) return;
    seen.add(value as object);
    for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
      if (forbidden.includes(key)) throw new Error(`StudySheetResponse must not contain ${key}.`);
      visit(child);
    }
  }
  visit(response);
}

export function sanitizeStudySheetResponse(response: BereanStudySheetResponse): BereanStudySheetResponse {
  const clean = JSON.parse(JSON.stringify(response)) as BereanStudySheetResponse;
  assertNoScriptureTextInStudySheet(clean);
  clean.crossReferences = sanitizeVerseIds(clean.crossReferences);
  clean.layers.text.observations = clean.layers.text.observations.slice(0, 6).map((item) => stripScriptureEcho(item));
  clean.layers.context.historicalNotes = clean.layers.context.historicalNotes.slice(0, 6).map((item) => stripScriptureEcho(item));
  clean.layers.context.literaryNotes = clean.layers.context.literaryNotes.slice(0, 6).map((item) => stripScriptureEcho(item));
  clean.layers.interpretation.summary = stripScriptureEcho(clean.layers.interpretation.summary);
  clean.layers.application.prompts = clean.layers.application.prompts.slice(0, 5).map((item) => stripScriptureEcho(item));
  clean.layers.application.cautions = [
    ...clean.layers.application.cautions,
    "Do not treat faithful obedience as a guarantee of health, wealth, or immediate visible success.",
  ].slice(0, 5).map((item) => stripScriptureEcho(item));
  return clean;
}

async function callAnthropicJSON(apiKey: string, input: BereanStudySheetRequest): Promise<string> {
  const prompt = STUDY_SHEET_USER_PROMPT_V1
    .replace("{{verseId}}", input.verseId)
    .replace("{{translation}}", input.translation)
    .replace("{{verseText}}", input.verseText);
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: modelId,
      max_tokens: 1400,
      temperature: 0.2,
      system: `${STUDY_SHEET_SYSTEM_PROMPT_V1}\n\n${VERSE_THEME_CLASSIFIER_PROMPT_V1}\n\n${REFLECTION_SAFETY_CLASSIFIER_PROMPT_V1}`,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!response.ok) throw new Error(`Anthropic returned ${response.status}`);
  const json = await response.json() as { content?: Array<{ text?: string }> };
  return json.content?.[0]?.text ?? "";
}

function fallbackStudySheet(input: BereanStudySheetRequest): Pick<BereanStudySheetResponse, "layers" | "crossReferences"> {
  return {
    layers: {
      text: {
        observations: ["The selected verse is analyzed from the trusted scripture text supplied by the app."],
        keyTerms: [{ id: "main-image", term: "Central image", note: "Review repeated nouns, verbs, and metaphors in the surrounding paragraph." }],
        uncertaintyNotes: ["Original-language notes require verified lexical data before making strong claims."],
      },
      context: {
        historicalNotes: ["Read the verse within its book, chapter, and covenant setting before applying it directly."],
        literaryNotes: ["Notice whether the verse is poetry, narrative, wisdom, prophecy, gospel, or epistle."],
        canonicalLinks: ["Resolve cross references from the local scripture store before display."],
      },
      interpretation: {
        summary: "A faithful reading should move from textual observation to context before personal application.",
        interpretiveOptions: [{ id: "default", label: "Denominationally neutral", summary: "Hold application close to the passage and avoid claims the text does not make.", confidence: 0.7 }],
        denominationalPosture: "neutral",
        uncertaintyNotes: ["This fallback avoids detailed claims that need model or scholarly enrichment."],
      },
      application: {
        prompts: ["What does this verse call me to notice, trust, confess, or practice today?"],
        cautions: ["Avoid treating the verse as a formula for guaranteed outcomes."],
        prayerSeed: "Lord, help me receive this passage truthfully and respond faithfully.",
      },
    },
    crossReferences: fallbackCrossReferences(input.verseId),
  };
}

function fallbackCrossReferences(verseId: string): string[] {
  if (/psa(lms)?[._-]?1[._-]?3/i.test(verseId)) return ["JER.17.7", "JER.17.8", "JHN.15.5"];
  return [];
}

function sanitizeVerseIds(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  return values
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim().toUpperCase().replace(/[^A-Z0-9._-]/g, ""))
    .filter(Boolean)
    .slice(0, 12);
}

function supportPayloadFor(theme: SelahSafetyTheme) {
  const resourceLinks = [
    { id: "988", title: "988 Suicide & Crisis Lifeline", url: "https://988lifeline.org", region: "US" },
    { id: "emergency", title: "Emergency services", url: "tel:911", region: "US" },
  ];
  const trustedHumanPrompt = theme === "selfHarm"
    ? "Please contact a trusted person now and consider calling or texting 988 if you may hurt yourself."
    : "Please contact a trusted person, pastor, counselor, or local support service who can help you make a concrete safety plan.";
  return {
    groundingTitle: "Pause and get support",
    groundingSteps: ["Put both feet on the floor.", "Name five things you can see.", "Move near another safe person if possible."],
    trustedHumanPrompt,
    resourceLinks,
  };
}

function stripScriptureEcho(text: string | undefined): string {
  return (text ?? "").replace(/[“”"]/g, "").slice(0, 500);
}

function sanitizeInput(text: string, limit: number): string {
  return text.replace(/```/g, "'''").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "").trim().slice(0, limit);
}

function requireCallableAuth(auth: unknown, app: unknown): void {
  if (!auth) throw new HttpsError("unauthenticated", "Authentication required.");
  if (!app) throw new HttpsError("unauthenticated", "App Check required.");
}
