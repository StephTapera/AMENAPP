import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

const db = admin.firestore();

function requireAuth(request: CallableRequest): string {
  if (!request.auth) throw new HttpsError("unauthenticated", "Authentication required.");
  return request.auth.uid;
}
function requireAppCheck(request: CallableRequest): void {
  if (!request.app) throw new HttpsError("failed-precondition", "App Check required.");
}

// Label priority mapping
const AI_USE_TYPE_TO_LABEL: Record<string, string> = {
  draft_generation: "ai_assisted_post",
  tone_rewrite_major: "ai_assisted_post",
  translation: "translated_with_ai",
  tone_rewrite_minor: "ai_assisted_tone",
  safety_rewrite: "edited_for_safety",
  sermon_notes_summary: "notes_summarized",
  prayer_generation: "prayer_assisted",
  scripture_suggestion: "scripture_suggested",
  berean_insert: "berean_assisted",
  tone_check: "tone_checked",
  alt_text_generation: "alt_text_assisted"
};

const LABEL_PRIORITY: Record<string, number> = {
  ai_assisted_post: 1,
  translated_with_ai: 2,
  ai_assisted_tone: 3,
  edited_for_safety: 4,
  notes_summarized: 5,
  prayer_assisted: 6,
  scripture_suggested: 7,
  berean_assisted: 8,
  tone_checked: 9,
  alt_text_assisted: 10
};

const DISCLOSURE_REQUIRED_LABELS = new Set([
  "ai_assisted_post", "translated_with_ai", "notes_summarized",
  "prayer_assisted", "edited_for_safety", "berean_assisted"
]);

function derivePrimaryLabel(aiUseTypes: string[]): string | null {
  const labels = aiUseTypes.map(t => AI_USE_TYPE_TO_LABEL[t]).filter(Boolean);
  if (labels.length === 0) return null;
  return labels.reduce((best, current) =>
    (LABEL_PRIORITY[current] || 99) < (LABEL_PRIORITY[best] || 99) ? current : best
  );
}

export const recordPostAIUsage = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  const uid = requireAuth(request);

  const {
    targetType,
    targetId,
    aiUseTypes,
    userAcceptedSuggestion,
    aiGeneratedPercentageEstimate,
    toneCheckSummary
  } = request.data as {
    targetType: string;
    targetId: string;
    aiUseTypes: string[];
    userAcceptedSuggestion: boolean;
    aiGeneratedPercentageEstimate?: number;
    toneCheckSummary?: Record<string, number>;
  };

  if (!targetType || !targetId) throw new HttpsError("invalid-argument", "targetType and targetId required.");
  if (!Array.isArray(aiUseTypes) || aiUseTypes.length === 0) {
    throw new HttpsError("invalid-argument", "aiUseTypes must be non-empty array.");
  }

  const validTypes = new Set(Object.keys(AI_USE_TYPE_TO_LABEL));
  const filteredTypes = aiUseTypes.filter(t => validTypes.has(t));
  if (filteredTypes.length === 0) throw new HttpsError("invalid-argument", "No valid aiUseTypes provided.");

  const primaryLabel = derivePrimaryLabel(filteredTypes);
  const disclosureRequired = primaryLabel ? DISCLOSURE_REQUIRED_LABELS.has(primaryLabel) : false;

  const aiUsageData: Record<string, unknown> = {
    usedAI: true,
    aiUseTypes: filteredTypes,
    primaryLabel,
    userAcceptedSuggestion: userAcceptedSuggestion || false,
    disclosureRequired,
    rawPromptStored: false,
    rawUserTextStored: false,
    modelVersion: "amen-ai-v1",
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  if (aiGeneratedPercentageEstimate !== undefined) {
    aiUsageData["aiGeneratedPercentageEstimate"] = Math.max(0, Math.min(1, aiGeneratedPercentageEstimate));
  }
  if (toneCheckSummary) {
    aiUsageData["toneCheckSummary"] = {
      kindnessScore: toneCheckSummary["kindnessScore"] || 0,
      clarityScore: toneCheckSummary["clarityScore"] || 0,
      humilityScore: toneCheckSummary["humilityScore"] || 0,
      peaceScore: toneCheckSummary["peaceScore"] || 0
    };
  }

  // Write to the appropriate collection based on targetType
  try {
    if (targetType === "post") {
      const postRef = db.collection("posts").doc(targetId);
      const postSnap = await postRef.get();
      // Verify this is the author
      if (!postSnap.exists) throw new HttpsError("not-found", "Post not found.");
      if (postSnap.data()?.["userId"] !== uid) throw new HttpsError("permission-denied", "Not the author.");

      // Prevent downgrade: if disclosureRequired label exists, don't allow lowering
      const existing = postSnap.data()?.["aiUsage"] as Record<string, unknown> | undefined;
      if (existing?.["disclosureRequired"] && !disclosureRequired) {
        throw new HttpsError("permission-denied", "Cannot remove required AI disclosure.");
      }

      await postRef.update({
        "aiUsage": aiUsageData,
        "aiUsage.createdAt": postSnap.data()?.["aiUsage"]?.["createdAt"] || admin.firestore.FieldValue.serverTimestamp()
      });
    } else if (targetType === "prayer") {
      await db.collection("users").doc(uid).collection("prayers").doc(targetId)
        .update({ "aiUsage": aiUsageData });
    }
    // Note: comments handled similarly; extend as needed

    // Log analytics event (no raw text)
    await db.collection("users").doc(uid).collection("aiUsageEvents").add({
      userId: uid,
      targetType,
      targetId,
      aiUseTypes: filteredTypes,
      primaryLabel,
      eventType: "tone_rewrite_accepted",
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    return { primaryLabel, disclosureRequired, recorded: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("recordPostAIUsage error", error);
    throw new HttpsError("internal", "Failed to record AI usage.");
  }
});

export const getAILabelDetail = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { targetType, targetId } = request.data as { targetType: string; targetId: string };

  let aiUsage: Record<string, unknown> | null = null;

  try {
    if (targetType === "post") {
      const post = await db.collection("posts").doc(targetId).get();
      if (post.exists) aiUsage = (post.data()?.["aiUsage"] as Record<string, unknown>) || null;
    }

    if (!aiUsage) return { found: false };

    return {
      found: true,
      usedAI: aiUsage["usedAI"],
      primaryLabel: aiUsage["primaryLabel"],
      aiUseTypes: aiUsage["aiUseTypes"],
      disclosureRequired: aiUsage["disclosureRequired"],
      toneCheckSummary: aiUsage["toneCheckSummary"] || null,
      rawPromptStored: false,
      rawUserTextStored: false
    };
  } catch (error) {
    logger.error("getAILabelDetail error", error);
    return { found: false };
  }
});

export const evaluateTone = onCall({ enforceAppCheck: true }, async (request) => {
  requireAppCheck(request);
  requireAuth(request);

  const { text, context, isRestModeActive } = request.data as {
    text: string;
    context: string;
    isRestModeActive: boolean;
  };

  if (!text || text.trim().length < 5) {
    throw new HttpsError("invalid-argument", "Text too short to evaluate.");
  }

  // In production: call OpenAI/Claude with tone evaluation prompt
  // API keys are server-side only (process.env.OPENAI_API_KEY etc.)
  // Raw text is NOT stored or logged

  // Suppress unused variable warning — context is part of the API contract
  void context;

  // Heuristic fallback (replace with real AI call in production)
  const result = evaluateToneLocally(text, isRestModeActive);

  return result;
});

function evaluateToneLocally(text: string, isRestMode: boolean): Record<string, unknown> {
  const lower = text.toLowerCase();
  let kindness = 0.7, humility = 0.6, peace = 0.7;
  const clarity = 0.7, truthfulness = 0.7, pastoral = 0.6;
  let shameRisk = 0.0, manipulationRisk = 0.0;
  const concerns: string[] = [];

  // Kindness deductions
  if (lower.includes("you always") || lower.includes("you never")) {
    kindness -= 0.3;
    concerns.push("Absolute language can feel attacking rather than honest.");
  }
  if (lower.includes("stupid") || lower.includes("foolish")) {
    kindness -= 0.4;
    concerns.push("Labeling others affects how they receive feedback.");
  }

  // Shame detection
  if (lower.includes("should be ashamed") || lower.includes("how could you")) {
    shameRisk = 0.7;
    concerns.push("This may trigger shame, which closes rather than opens hearts.");
  }

  // Spiritual manipulation
  if (lower.includes("god told me") || lower.includes("if you were really")) {
    manipulationRisk = 0.75;
    concerns.push("Claiming divine authority over others can be spiritually coercive.");
  }

  // Peace adjustments
  if (lower.includes("!") || (text.match(/!/g) || []).length > 2) { peace -= 0.1; }
  if (isRestMode) {
    // Stricter Sunday thresholds
    peace = Math.max(peace - 0.1, 0);
    humility = Math.max(humility - 0.05, 0);
  }

  const saveForMondayRecommended = isRestMode && (peace < 0.5 || shameRisk > 0.4 || concerns.length > 1);

  // Suppress unused variable warnings — all scores are part of the return contract
  void truthfulness;
  void pastoral;

  return {
    kindnessScore: Math.max(0, Math.min(1, kindness)),
    clarityScore: Math.max(0, Math.min(1, clarity)),
    humilityScore: Math.max(0, Math.min(1, humility)),
    peaceScore: Math.max(0, Math.min(1, peace)),
    truthfulnessScore: Math.max(0, Math.min(1, truthfulness)),
    scriptureIntegrityScore: null,
    shameLanguageRisk: shameRisk,
    manipulationRisk,
    pastoralSensitivityScore: Math.max(0, Math.min(1, pastoral)),
    concerns,
    suggestedRewrite: concerns.length > 0
      ? "Consider sharing your observation rather than your conclusion about the person."
      : null,
    suggestedMode: isRestMode ? "peacemaking" : "clear",
    labelIfPublished: concerns.length === 0 ? "tone_checked" : "ai_assisted_tone",
    saveForMondayRecommended
  };
}
