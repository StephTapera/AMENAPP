import * as admin from "firebase-admin";
import { modelRouter } from "../berean/services/ModelRouter";
import { validateRawTextOutput } from "../berean/services/SafetyValidator";
import type { ContextAction, BereanContextPayload } from "./bereanSelectionActions";
import { actionInstruction } from "./bereanSelectionActions";
import type { EmotionalContextSummary } from "./emotionalContextAnalyzer";
import { buildContextualSuggestions } from "./contextualSuggestionEngine";
import { deriveContextualSearchHints } from "./contextualSearchService";
import { shouldCreateTimelineCompression } from "./timelineCompressionService";

const db = () => admin.firestore();

export interface ContextEngineResult {
  id: string;
  title: string;
  answer: string;
  scriptureReferences: string[];
  suggestedActions: string[];
  safetyNotice: string;
  threadId: string;
}

function actionTitle(action: ContextAction): string {
  return action
    .replace(/([A-Z])/g, " $1")
    .replace(/^./, (first) => first.toUpperCase())
    .trim();
}

function buildSystemPrompt(): string {
  return [
    "You are Berean, Amen's contextual intelligence layer.",
    "Respond with humility, Scripture-grounding, and clear uncertainty when needed.",
    "Do not fabricate spiritual authority, fake memory, emotional certainty, pastoral endorsement, or private context.",
    "Do not claim God told you something about the user.",
    "When sensitive or crisis content appears, preserve user agency and direct them toward trusted human support.",
    "Return JSON matching Berean's structured response contract with answerText, scriptureReferences, studyCards, reflectionPrompts, prayerPrompt, leadershipPrompt, sensitivitySummary, suggestedNextActions, and confidenceNotes.",
  ].join("\n");
}

function buildUserPrompt(
  action: ContextAction,
  payload: BereanContextPayload,
  emotional: EmotionalContextSummary
): string {
  return [
    `Requested action: ${actionTitle(action)}`,
    `Instruction: ${actionInstruction(action)}`,
    `Surface: ${payload.sourceSurface}`,
    `Content type: ${payload.contentType}`,
    payload.scriptureReference ? `Scripture reference: ${payload.scriptureReference}` : "",
    payload.surroundingText ? `Surrounding context: ${payload.surroundingText}` : "",
    `Emotional context signal: ${emotional.primaryState}`,
    emotional.sensitivityFlags.length ? `Safety flags: ${emotional.sensitivityFlags.join(", ")}` : "",
    "",
    "Selected content:",
    payload.selectedText,
  ].filter(Boolean).join("\n");
}

export async function runBereanContextEngine(
  userId: string,
  action: ContextAction,
  payload: BereanContextPayload,
  emotional: EmotionalContextSummary
): Promise<ContextEngineResult> {
  const threadId = db().collection("users").doc(userId).collection("savedContextThreads").doc().id;
  const response = await modelRouter.callStructured({
    systemPrompt: buildSystemPrompt(),
    userPrompt: buildUserPrompt(action, payload, emotional),
    tier: action === "historicalContext" || action === "compareScripture" ? "deep" : "standard",
    maxTokens: action === "summarize" || action === "define" ? 512 : 900,
  });

  const validation = validateRawTextOutput(response.answerText);
  const suggestions = buildContextualSuggestions(action, payload);
  const searchHints = deriveContextualSearchHints(payload);
  const now = admin.firestore.Timestamp.now();
  const resultId = db().collection("users").doc(userId).collection("contextActions").doc().id;
  const scriptureReferences = response.scriptureReferences.length > 0
    ? response.scriptureReferences
    : (payload.scriptureReference ? [payload.scriptureReference] : []);

  await db().batch()
    .set(db().collection("users").doc(userId).collection("contextSelections").doc(payload.id || resultId), {
      userId,
      selectionId: payload.id || resultId,
      selectedTextPreview: payload.selectedText.slice(0, 160),
      textLength: payload.selectedText.length,
      sourceSurface: payload.sourceSurface,
      sourceId: payload.sourceId ?? "",
      contentType: payload.contentType,
      scriptureReference: payload.scriptureReference ?? "",
      searchHints,
      createdAt: now,
    })
    .set(db().collection("users").doc(userId).collection("contextActions").doc(resultId), {
      userId,
      actionId: resultId,
      threadId,
      action,
      sourceSurface: payload.sourceSurface,
      sourceId: payload.sourceId ?? "",
      contentType: payload.contentType,
      scriptureReference: payload.scriptureReference ?? "",
      safetyFlags: emotional.sensitivityFlags,
      responsePreview: validation.sanitizedText.slice(0, 240),
      createdAt: now,
    })
    .set(db().collection("users").doc(userId).collection("savedContextThreads").doc(threadId), {
      userId,
      threadId,
      title: actionTitle(action),
      sourceSurface: payload.sourceSurface,
      sourceId: payload.sourceId ?? "",
      contentType: payload.contentType,
      scriptureReferences,
      answer: validation.sanitizedText,
      suggestedActions: suggestions,
      createdAt: now,
      updatedAt: now,
    })
    .set(db().collection("users").doc(userId).collection("contextualMemory").doc(threadId), {
      userId,
      threadId,
      sourceSurface: payload.sourceSurface,
      contentType: payload.contentType,
      scriptureReference: payload.scriptureReference ?? "",
      action,
      createdAt: now,
    })
    .commit();

  if (shouldCreateTimelineCompression(payload)) {
    await db().collection("users").doc(userId).collection("timelineCompression").doc(threadId).set({
      userId,
      threadId,
      sourceSurface: payload.sourceSurface,
      sourceId: payload.sourceId ?? "",
      state: "queued",
      createdAt: now,
    });
  }

  return {
    id: resultId,
    title: actionTitle(action),
    answer: validation.sanitizedText,
    scriptureReferences,
    suggestedActions: suggestions,
    safetyNotice: "AI-assisted. Berean is not a pastor, therapist, doctor, or substitute for trusted human care.",
    threadId,
  };
}
