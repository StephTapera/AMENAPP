// churchNotesContextEngine.ts
// Generates context for a Church Note: related scripture, themes, prayer prompts,
// reflection questions, small group questions, and action suggestions.
// Uses Claude Haiku for LLM calls; local heuristics for scripture detection.

import * as admin from "firebase-admin";
import Anthropic from "@anthropic-ai/sdk";
import {
  CNContextRequest,
  CNContextResult,
  CNDetectedTheme,
  CNRelatedScripture,
  CNPrayerPrompt,
  CNReflectionQuestion,
  CNSmallGroupQuestion,
  CNActionSuggestion,
  CNLLMContext,
  CNProvenanceLabel,
  CN_MAX_INPUT_CHARS,
  CN_MAX_OUTPUT_CHARS,
  CN_SYSTEM_PROMPT_HEADER,
} from "./types.js";

const anthropic = new Anthropic();
const db = admin.firestore();

// MARK: - Scripture Detection (local — no LLM needed)

const SCRIPTURE_PATTERN = /(?:(?:1|2|3)\s)?[A-Z][a-z]+(?:\s[A-Z][a-z]+)?\s\d+:\d+(?:-\d+)?/g;

function detectScriptureReferences(text: string): CNRelatedScripture[] {
  const matches = [...text.matchAll(SCRIPTURE_PATTERN)];
  const seen = new Set<string>();
  return matches.flatMap((m) => {
    const ref = m[0];
    if (seen.has(ref)) return [];
    seen.add(ref);
    return [{
      id: crypto.randomUUID(),
      reference: ref,
      provenance: {
        source: "your note",
        confidence: "confirmed",
        whySuggested: "Referenced directly in your note text",
      },
    }];
  });
}

// MARK: - LLM Context Builder

function buildLLMContext(req: CNContextRequest): CNLLMContext {
  let noteText = req.noteText;
  const isTruncated = noteText.length > CN_MAX_INPUT_CHARS;
  if (isTruncated) noteText = noteText.slice(0, CN_MAX_INPUT_CHARS);

  return {
    noteText,
    sermonTitle: req.sermonTitle,
    scriptureReferences: req.scriptureReferences ?? [],
    wordCount: noteText.split(/\s+/).length,
    isTruncated,
  };
}

// MARK: - Context Generation via LLM

async function generateContextWithLLM(ctx: CNLLMContext): Promise<{
  themes: CNDetectedTheme[];
  prayerPrompts: CNPrayerPrompt[];
  reflectionQuestions: CNReflectionQuestion[];
  smallGroupQuestions: CNSmallGroupQuestion[];
  actionSuggestions: CNActionSuggestion[];
}> {
  const prompt = `${CN_SYSTEM_PROMPT_HEADER}

Here are notes from a church service or personal study:
${ctx.sermonTitle ? `Sermon: "${ctx.sermonTitle}"\n` : ""}${ctx.scriptureReferences.length > 0 ? `Scripture references: ${ctx.scriptureReferences.join(", ")}\n` : ""}
Notes:
${ctx.noteText}

Return a JSON object with these fields:
{
  "themes": [{ "theme": string, "whySuggested": string, "isRecurring": false, "exampleQuote": string }],
  "prayerPrompts": [{ "text": string, "category": "personal"|"intercession"|"thanksgiving"|"surrender", "whySuggested": string }],
  "reflectionQuestions": [{ "text": string, "isPersonal": true }],
  "smallGroupQuestions": [{ "text": string }],
  "actionSuggestions": [{ "type": "personalAction"|"prayerItem"|"followUpReminder"|"smallGroupQuestion", "text": string, "sourceQuote": string|null }]
}

Rules:
- themes: max 5, ranked by prominence
- prayerPrompts: max 4, humble language only
- reflectionQuestions: max 4
- smallGroupQuestions: max 3
- actionSuggestions: max 4, only if clearly indicated by note content
- Never claim certainty. Never diagnose. Never state "God told you."
- All suggestions must be traceable to the note content.
- Return ONLY valid JSON, no markdown.`;

  const message = await anthropic.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: CN_MAX_OUTPUT_CHARS,
    messages: [{ role: "user", content: prompt }],
  });

  const raw = message.content[0].type === "text" ? message.content[0].text : "{}";

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = {};
  }

  const prov = (why: string, source = "your note"): CNProvenanceLabel => ({
    source,
    confidence: "possible",
    whySuggested: why,
  });

  const themes: CNDetectedTheme[] = ((parsed.themes as unknown[]) ?? []).slice(0, 5).map((t: unknown) => {
    const theme = t as Record<string, unknown>;
    return {
      id: crypto.randomUUID(),
      theme: String(theme.theme ?? ""),
      occurrenceCount: 1,
      isRecurring: false,
      exampleQuotes: theme.exampleQuote ? [String(theme.exampleQuote)] : [],
      provenance: prov(String(theme.whySuggested ?? "Detected in note content")),
    };
  });

  const prayerPrompts: CNPrayerPrompt[] = ((parsed.prayerPrompts as unknown[]) ?? []).slice(0, 4).map((p: unknown) => {
    const prompt = p as Record<string, unknown>;
    return {
      id: crypto.randomUUID(),
      text: String(prompt.text ?? ""),
      category: (["personal", "intercession", "thanksgiving", "surrender"].includes(String(prompt.category))
        ? String(prompt.category) : "personal") as CNPrayerPrompt["category"],
      provenance: prov(String(prompt.whySuggested ?? "Derived from note themes")),
    };
  });

  const reflectionQuestions: CNReflectionQuestion[] = ((parsed.reflectionQuestions as unknown[]) ?? []).slice(0, 4).map((q: unknown) => ({
    id: crypto.randomUUID(),
    text: String((q as Record<string, unknown>).text ?? ""),
    isPersonal: true,
    provenance: prov("Generated from note content"),
  }));

  const smallGroupQuestions: CNSmallGroupQuestion[] = ((parsed.smallGroupQuestions as unknown[]) ?? []).slice(0, 3).map((q: unknown) => ({
    id: crypto.randomUUID(),
    text: String((q as Record<string, unknown>).text ?? ""),
    provenance: prov("Generated from note content"),
  }));

  const validActionTypes = ["personalAction", "prayerItem", "followUpReminder", "smallGroupQuestion", "mentorMessage", "calendarSuggestion"];
  const actionSuggestions: CNActionSuggestion[] = ((parsed.actionSuggestions as unknown[]) ?? []).slice(0, 4).map((a: unknown) => {
    const action = a as Record<string, unknown>;
    return {
      id: crypto.randomUUID(),
      type: (validActionTypes.includes(String(action.type)) ? String(action.type) : "personalAction") as CNActionSuggestion["type"],
      text: String(action.text ?? ""),
      sourceQuote: action.sourceQuote ? String(action.sourceQuote) : undefined,
      provenance: prov("Detected from note content"),
      approvalState: "pending",
    };
  });

  return { themes, prayerPrompts, reflectionQuestions, smallGroupQuestions, actionSuggestions };
}

// MARK: - Main Export

export async function generateChurchNotesContext(req: CNContextRequest): Promise<CNContextResult> {
  const ctx = buildLLMContext(req);
  const scriptures = detectScriptureReferences(req.noteText);
  const { themes, prayerPrompts, reflectionQuestions, smallGroupQuestions, actionSuggestions } =
    await generateContextWithLLM(ctx);

  const result: CNContextResult = {
    noteId: req.noteId,
    userId: req.userId,
    relatedScriptures: scriptures,
    relatedNotes: [],   // populated by memory engine cross-reference
    detectedThemes: themes,
    prayerPrompts,
    reflectionQuestions,
    smallGroupQuestions,
    actionSuggestions,
    generatedAt: admin.firestore.Timestamp.now(),
  };

  // Persist to Firestore (server-owned write)
  await db
    .collection("churchNotes")
    .doc(req.noteId)
    .collection("context")
    .doc(crypto.randomUUID())
    .set(result);

  return result;
}
