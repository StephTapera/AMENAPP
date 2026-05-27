// churchNotesActionExtractionEngine.ts
// Extracts action suggestions from Church Notes and processing job outputs.
// All extracted actions require user approval before being saved as canonical actionItems.
// No silent task creation.

import * as admin from "firebase-admin";
import Anthropic from "@anthropic-ai/sdk";
import {
  CNExtractedAction,
  CNProvenanceLabel,
  CN_MAX_INPUT_CHARS,
  CN_SYSTEM_PROMPT_HEADER,
} from "./types.js";

const anthropic = new Anthropic();
const db = admin.firestore();

// MARK: - Source Text Resolution

async function resolveSourceText(noteId: string, jobId: string): Promise<{ text: string; sourceLabel: string }> {
  // Prefer approved transcript > OCR > summary draft
  const jobSnap = await db
    .collection("churchNotes")
    .doc(noteId)
    .collection("processingJobs")
    .doc(jobId)
    .get();

  if (!jobSnap.exists) {
    return { text: "", sourceLabel: "unknown" };
  }

  const job = jobSnap.data() as Record<string, unknown>;

  if (job.approvedTranscriptText && job.transcriptText) {
    return { text: String(job.transcriptText).slice(0, CN_MAX_INPUT_CHARS), sourceLabel: "transcript" };
  }
  if (job.approvedOcrText && job.ocrText) {
    return { text: String(job.ocrText).slice(0, CN_MAX_INPUT_CHARS), sourceLabel: "OCR" };
  }
  if (job.approvedSummaryDraft && job.summaryDraft) {
    return { text: String(job.summaryDraft).slice(0, CN_MAX_INPUT_CHARS), sourceLabel: "summary draft" };
  }

  return { text: "", sourceLabel: "none available" };
}

// MARK: - Action Extraction via LLM

async function extractActionsWithLLM(
  text: string,
  sourceLabel: string,
  noteId: string,
  jobId: string,
  userId: string
): Promise<CNExtractedAction[]> {
  if (!text || text.length < 30) return [];

  const prompt = `${CN_SYSTEM_PROMPT_HEADER}

Extract concrete actions from these church/sermon notes. Return JSON array:
[{
  "type": "personalAction"|"prayerItem"|"followUpReminder"|"smallGroupQuestion"|"mentorMessage",
  "text": string,             // the action text (concise, first-person where appropriate)
  "sourceQuote": string|null, // exact quote from notes that triggered this, or null
  "whySuggested": string      // brief explanation
}]

Source: ${sourceLabel}
Notes:
${text}

Rules:
- Only include actions clearly indicated by the content (not inferred)
- Max 5 actions total
- prayerItem: something the person committed to pray about
- personalAction: something they said they would do
- followUpReminder: something they should revisit or follow up on
- smallGroupQuestion: a question worth discussing with others
- mentorMessage: something worth sharing with a mentor or pastor
- Never invent actions not grounded in the content
- Return ONLY valid JSON array.`;

  const message = await anthropic.messages.create({
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1500,
    messages: [{ role: "user", content: prompt }],
  });

  const raw = message.content[0].type === "text" ? message.content[0].text : "[]";
  let parsed: unknown[];
  try { parsed = JSON.parse(raw); } catch { parsed = []; }
  if (!Array.isArray(parsed)) parsed = [];

  const validTypes = ["personalAction", "prayerItem", "followUpReminder", "smallGroupQuestion", "mentorMessage", "calendarSuggestion"];

  return parsed.slice(0, 5).map((a: unknown) => {
    const action = a as Record<string, unknown>;
    const prov: CNProvenanceLabel = {
      source: sourceLabel,
      confidence: "possible",
      whySuggested: String(action.whySuggested ?? "Extracted from note content"),
    };
    return {
      id: crypto.randomUUID(),
      noteId,
      userId,
      type: (validTypes.includes(String(action.type)) ? String(action.type) : "personalAction") as CNExtractedAction["type"],
      text: String(action.text ?? ""),
      sourceQuote: action.sourceQuote ? String(action.sourceQuote) : undefined,
      jobId,
      approvalState: "pending" as const,
      provenance: prov,
      createdAt: admin.firestore.Timestamp.now(),
    };
  });
}

// MARK: - Main Export

export async function extractChurchNotesActions(
  noteId: string,
  userId: string,
  jobId: string
): Promise<CNExtractedAction[]> {
  const { text, sourceLabel } = await resolveSourceText(noteId, jobId);
  const actions = await extractActionsWithLLM(text, sourceLabel, noteId, jobId, userId);

  // Store as pending suggestions — client must approve before canonical actionItem is created
  for (const action of actions) {
    await db
      .collection("churchNotes")
      .doc(noteId)
      .collection("actions")
      .doc(action.id)
      .set(action);
  }

  return actions;
}
