// churchNotesRecapEngine.ts
// Generates source-grounded Smart Recaps for Church Notes.
// Output is always marked as requiring user review before saving.

import * as admin from "firebase-admin";
import Anthropic from "@anthropic-ai/sdk";
import {
  CNSmartRecap,
  CNProvenanceLabel,
  CN_MAX_INPUT_CHARS,
  CN_MAX_OUTPUT_CHARS,
  CN_SYSTEM_PROMPT_HEADER,
} from "./types.js";

const anthropic = new Anthropic();
const db = admin.firestore();

// MARK: - Main Export

export async function generateChurchNotesRecap(
  noteId: string,
  userId: string,
  noteText: string,
  sermonTitle?: string,
  scriptureReferences?: string[]
): Promise<CNSmartRecap> {
  const truncated = noteText.length > CN_MAX_INPUT_CHARS;
  const text = noteText.slice(0, CN_MAX_INPUT_CHARS);

  const prompt = `${CN_SYSTEM_PROMPT_HEADER}

${sermonTitle ? `Sermon: "${sermonTitle}"\n` : ""}${scriptureReferences?.length ? `Scriptures: ${scriptureReferences.join(", ")}\n` : ""}
Church notes:
${text}

Write a brief, source-grounded recap of these notes. Return JSON:
{
  "whatStoodOut": string,          // 2-3 sentences. What the notes focused on. Humble tone.
  "prayerItems": [string],         // max 3 prayer items, derived from note content only
  "nextStep": string,              // 1 sentence, gentle suggestion
  "relatedScriptures": [string],   // scripture references found in notes (max 3)
  "whySuggested": string           // brief explanation of what sources were used
}

Rules:
- Speak reflectively. Never claim certainty.
- "A recurring theme appears to be..." not "God is telling you..."
- Prayer items must be traceable to note content.
- nextStep must be gentle and optional.
- Return ONLY valid JSON.`;

  const message = await anthropic.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1500,
    messages: [{ role: "user", content: prompt }],
  });

  const raw = message.content[0].type === "text" ? message.content[0].text : "{}";
  let parsed: Record<string, unknown>;
  try { parsed = JSON.parse(raw); } catch { parsed = {}; }

  const prov: CNProvenanceLabel = {
    source: truncated ? "your note (truncated)" : "your note",
    confidence: "possible",
    whySuggested: String(parsed.whySuggested ?? "Generated from note content — please review before saving"),
  };

  const recap: CNSmartRecap = {
    id: crypto.randomUUID(),
    noteId,
    userId,
    whatStoodOut: String(parsed.whatStoodOut ?? "Here is a brief recap of your notes."),
    prayerItems: ((parsed.prayerItems as string[]) ?? []).slice(0, 3),
    nextStep: parsed.nextStep ? String(parsed.nextStep) : undefined,
    relatedScriptures: ((parsed.relatedScriptures as string[]) ?? []).slice(0, 3),
    relatedNoteIds: [],
    isEdited: false,
    generatedAt: admin.firestore.Timestamp.now(),
    provenance: prov,
  };

  // Server-owned write — client can only edit/approve
  await db
    .collection("churchNotes")
    .doc(noteId)
    .collection("recaps")
    .doc(recap.id)
    .set(recap);

  return recap;
}
