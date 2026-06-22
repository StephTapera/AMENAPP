import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const REGION = "us-central1";
const MAX_TEXT_LENGTH = 12000;

export const REQUIRED_BEREAN_CALLABLES = [
  "bereanAsk",
  "bereanStreamMessage",
  "parseScriptureReference",
  "saveBereanInsight",
  "savePrayerEntry",
  "createDiscernmentResult",
  "analyzeAmenMediaWithBerean",
  "addInsightToWalkWithChrist",
  "getBereanSuggestions",
] as const;

export type BereanProductMode =
  | "scripture_study"
  | "ask_berean"
  | "prayer_companion"
  | "discernment"
  | "media_insight"
  | "work_life_wisdom"
  | "safety_review";

export interface ParsedScriptureReference {
  raw: string;
  book: string;
  chapter: number;
  verseStart: number | null;
  verseEnd: number | null;
  translation: string;
  source: "reference_parser";
  text: null;
  contextBefore: null;
  contextAfter: null;
}

const db = () => admin.firestore();

function requireContext(request: { auth?: { uid: string } | null; app?: unknown }): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!request.app) {
    throw new HttpsError("unauthenticated", "App Check required.");
  }
  return request.auth.uid;
}

function stringField(data: Record<string, unknown>, key: string, fallback = ""): string {
  const value = data[key];
  return typeof value === "string" ? value.trim() : fallback;
}

function optionalStringArray(value: unknown, limit = 20): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter(Boolean).slice(0, limit)
    : [];
}

function cleanText(value: unknown, fieldName: string, required = true): string {
  if (typeof value !== "string") {
    if (!required) return "";
    throw new HttpsError("invalid-argument", `${fieldName} must be a string.`);
  }
  const trimmed = value.trim();
  if (required && !trimmed) {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }
  if (trimmed.length > MAX_TEXT_LENGTH) {
    throw new HttpsError("invalid-argument", `${fieldName} is too long.`);
  }
  return trimmed;
}

export function routeBereanMode(input: string, requestedMode?: string): BereanProductMode {
  const explicit = normalizeMode(requestedMode);
  if (explicit) return explicit;

  const lower = input.toLowerCase();
  if (detectSafetyLabels(input).length > 0) return "safety_review";
  if (parseReferences(input).length > 0) return "scripture_study";
  if (/\b(what should i do|should i|discern|decision|choose|wise choice)\b/.test(lower)) return "discernment";
  if (/\b(pray|prayer|lament|intercede|gratitude)\b/.test(lower)) return "prayer_companion";
  if (/\b(sermon|video|audio|podcast|caption|transcript|clip|post)\b/.test(lower)) return "media_insight";
  if (/\b(work|job|boss|leadership|conflict|anxiety|relationship|finance)\b/.test(lower)) return "work_life_wisdom";
  return "ask_berean";
}

function normalizeMode(value?: string): BereanProductMode | null {
  switch ((value ?? "").toLowerCase().replace(/\s+/g, "_")) {
  case "scripture_study":
  case "ask_berean":
  case "prayer_companion":
  case "discernment":
  case "media_insight":
  case "work_life_wisdom":
  case "safety_review":
    return value!.toLowerCase().replace(/\s+/g, "_") as BereanProductMode;
  default:
    return null;
  }
}

export function detectSafetyLabels(input: string): string[] {
  const checks: Array<[string, RegExp]> = [
    ["shame_heavy_language", /\b(god hates me|worthless|disgusting|no hope|condemned forever)\b/i],
    ["spiritual_manipulation", /\b(god told me you must|if you had faith you would|submit without question)\b/i],
    ["abusive_counsel", /\b(stay and endure abuse|ignore the abuse|do not tell anyone)\b/i],
    ["false_certainty", /\b(god (?:definitely )?told me|thus says the lord|guaranteed blessing)\b/i],
    ["prosperity_gospel_claim", /\b(seed faith|guaranteed wealth|sow.*financial breakthrough)\b/i],
    ["legalism_risk", /\b(god will only love you if|saved by obeying)\b/i],
    ["antinomian_risk", /\b(sin does not matter|obedience is irrelevant)\b/i],
    ["self_harm_language", /\b(kill myself|end my life|suicidal|self harm|hurt myself|nothing to live for)\b/i],
    ["sexual_exploitation", /\b(nude|sexual exploit|minor.*sexual|porn)\b/i],
    ["rage_bait", /\b(destroy them|humiliate them|make them pay)\b/i],
    ["cult_like_control", /\b(cut off everyone|only our leader|never question the leader)\b/i],
    ["unverified_prophecy", /\b(prophecy says|god told me to tell you)\b/i],
    ["medical_legal_financial_overreach", /\b(stop your medication|ignore your doctor|legal advice|guaranteed investment)\b/i],
  ];
  return checks.filter(([, pattern]) => pattern.test(input)).map(([label]) => label);
}

export function parseReferences(input: string, translation = "ESV"): ParsedScriptureReference[] {
  const bookPattern = "(?:[1-3]\\s*)?[A-Za-z]+(?:\\s+of\\s+[A-Za-z]+)?";
  const pattern = new RegExp(`\\b(${bookPattern})\\s+(\\d{1,3})(?::(\\d{1,3})(?:[\\u2013-](\\d{1,3}))?)?\\b`, "g");
  const results: ParsedScriptureReference[] = [];
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(input)) !== null) {
    const raw = match[0];
    results.push({
      raw,
      book: match[1].replace(/\s+/g, " ").trim(),
      chapter: Number(match[2]),
      verseStart: match[3] ? Number(match[3]) : null,
      verseEnd: match[4] ? Number(match[4]) : null,
      translation,
      source: "reference_parser",
      text: null,
      contextBefore: null,
      contextAfter: null,
    });
  }
  return results.slice(0, 12);
}

function suggestionRail(mode: BereanProductMode): string[] {
  switch (mode) {
  case "scripture_study":
    return ["Show cross references?", "Explain the original language?", "Turn this into a study plan?"];
  case "prayer_companion":
    return ["Save this prayer?", "Add this to Walk With Christ?", "Create a shorter prayer?"];
  case "discernment":
    return ["Check motives?", "Discuss this with a mentor?", "Give me one next step?"];
  case "media_insight":
    return ["Save key moments?", "Review claims against Scripture?", "Share summary?"];
  case "safety_review":
    return ["Rewrite more pastorally?", "Flag overreach?", "Suggest a safer next step?"];
  case "work_life_wisdom":
    return ["Give me a shorter answer?", "Create an action step?", "Add this to Walk With Christ?"];
  case "ask_berean":
    return ["Show cross references?", "Give me a shorter answer?", "Save this insight?"];
  }
}

export const parseScriptureReference = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const text = cleanText(data.text ?? data.reference, "text");
    const translation = stringField(data, "translation", "ESV") || "ESV";
    return { references: parseReferences(text, translation), doesNotIncludeBibleText: true };
  }
);

export const bereanAsk = onCall(
  { region: REGION, timeoutSeconds: 30, enforceAppCheck: true },
  async (request) => {
    const userId = requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const text = cleanText(data.text ?? data.message ?? data.userMessage, "text");
    const mode = routeBereanMode(text, stringField(data, "mode"));
    const conversationId = stringField(data, "conversationId") || db().collection("ids").doc().id;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const references = parseReferences(text, stringField(data, "translation", "ESV") || "ESV");
    const safetyLabels = detectSafetyLabels(text);

    await db().collection("users").doc(userId).collection("bereanConversations").doc(conversationId).set({
      id: conversationId,
      userId,
      mode,
      title: text.slice(0, 80),
      updatedAt: now,
      lastMessageAt: now,
      scriptureReferences: references.map((ref) => ref.raw),
      safetyState: safetyLabels.length ? "review_required" : "clear",
    }, { merge: true });

    const messageRef = db().collection("users").doc(userId).collection("bereanMessages").doc();
    await messageRef.set({
      id: messageRef.id,
      conversationId,
      role: "user",
      content: text,
      blocks: [{ type: "text", body: text }],
      createdAt: now,
      sources: references.map((ref) => ({ reference: ref.raw, translation: ref.translation, verifiedText: false })),
      safetyLabels: [],
      serverSafetyLabels: safetyLabels,
    });

    return {
      success: true,
      conversationId,
      messageId: messageRef.id,
      mode,
      scriptureReferences: references,
      safetyLabels,
      suggestions: suggestionRail(mode),
      orchestration: "accepted_for_berean_orchestrator",
    };
  }
);

export const bereanStreamMessage = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const text = cleanText(data.text ?? data.message ?? data.userMessage, "text");
    return {
      success: true,
      streamFunction: "bereanChatProxyStream",
      mode: routeBereanMode(text, stringField(data, "mode")),
      requiresBearerIdToken: true,
      requiresAppCheckToken: true,
      userId,
    };
  }
);

export const savePrayerEntry = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const entryRef = db().collection("users").doc(userId).collection("prayerEntries").doc();
    await entryRef.set({
      id: entryRef.id,
      userId,
      sourceMessageId: stringField(data, "sourceMessageId"),
      prayerText: cleanText(data.prayerText, "prayerText"),
      scriptureAnchor: stringField(data, "scriptureAnchor"),
      reflectionQuestion: stringField(data, "reflectionQuestion"),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      privateByDefault: true,
      privacyLevel: "private",
    });
    return { success: true, prayerEntryId: entryRef.id, privateByDefault: true };
  }
);

export const createDiscernmentResult = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const resultRef = db().collection("users").doc(userId).collection("discernmentResults").doc();
    await resultRef.set({
      id: resultRef.id,
      userId,
      question: cleanText(data.question, "question"),
      biblicalPrinciples: optionalStringArray(data.biblicalPrinciples),
      motiveCheck: stringField(data, "motiveCheck"),
      wisdomCheck: stringField(data, "wisdomCheck"),
      riskFlags: optionalStringArray(data.riskFlags),
      fruitCheck: stringField(data, "fruitCheck"),
      nextStep: stringField(data, "nextStep"),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, discernmentResultId: resultRef.id };
  }
);

export const analyzeAmenMediaWithBerean = onCall(
  { region: REGION, timeoutSeconds: 20, enforceAppCheck: true },
  async (request) => {
    const userId = requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const content = cleanText(data.transcript ?? data.caption ?? data.summary ?? data.url, "media");
    const insightRef = db().collection("mediaInsights").doc();
    const safetyLabels = detectSafetyLabels(content);
    await insightRef.set({
      id: insightRef.id,
      userId,
      sourceUrl: stringField(data, "url"),
      summarySource: content.slice(0, 4000),
      scriptureReferences: parseReferences(content).map((ref) => ref.raw),
      safetyLabels,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      serverValidated: true,
    });
    return { success: true, mediaInsightId: insightRef.id, safetyLabels };
  }
);

export const addInsightToWalkWithChrist = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    const userId = requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const pathRef = db().collection("users").doc(userId).collection("walkWithChristPath").doc();
    await pathRef.set({
      id: pathRef.id,
      userId,
      insightId: cleanText(data.insightId, "insightId"),
      title: stringField(data, "title", "Berean insight"),
      summary: stringField(data, "summary"),
      scriptureReferences: optionalStringArray(data.scriptureReferences),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "berean",
    });
    return { success: true, walkWithChristPathId: pathRef.id };
  }
);

export const getBereanSuggestions = onCall(
  { region: REGION, timeoutSeconds: 15, enforceAppCheck: true },
  async (request) => {
    requireContext(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const text = typeof data.text === "string" ? data.text : "";
    const mode = routeBereanMode(text, stringField(data, "mode"));
    return { success: true, mode, suggestions: suggestionRail(mode) };
  }
);
