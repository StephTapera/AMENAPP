import { onCall, HttpsError } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import {
  allowedContextActions,
  sanitizeContextResponse,
  sanitizePayload,
  selectedTextLength,
  isSupportedContextSource,
  ContextAction,
} from "./bereanSelectionActions";
import { analyzeEmotionalContext } from "./emotionalContextAnalyzer";
import { runBereanContextEngine } from "./bereanContextEngine";
import { recordStudyContinuity } from "./studyContinuityService";
import { recordAmbientSuggestion } from "./ambientIntelligenceService";

export const routeBereanContextualAction = onCall(
  { region: "us-central1", timeoutSeconds: 60, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const userId = request.auth.uid;
    const action = String((request.data as Record<string, unknown>).action ?? "") as ContextAction;
    if (!allowedContextActions.includes(action)) {
      throw new HttpsError("invalid-argument", "Unsupported contextual action.");
    }

    const rawPayload = (request.data as Record<string, unknown>).payload;
    if (selectedTextLength(rawPayload) > 6000) {
      throw new HttpsError("invalid-argument", "Selected text is too long.");
    }

    const payload = sanitizePayload(rawPayload);
    if (!payload.selectedText) {
      throw new HttpsError("invalid-argument", "Selected text is required.");
    }
    if (!isSupportedContextSource(payload)) {
      throw new HttpsError("invalid-argument", "Unsupported context source.");
    }

    try {
      await enforceRateLimit(userId, [
        RATE_LIMITS.bereanContextualActionPerMinute,
        RATE_LIMITS.bereanDailyBudget,
      ]);
    } catch (error) {
      if ((error as { code?: string }).code === "resource-exhausted") {
        throw new HttpsError("resource-exhausted", "Too many Berean actions. Please wait a minute and try again.");
      }
      throw error;
    }

    const emotional = analyzeEmotionalContext(payload);
    const result = await runBereanContextEngine(userId, action, payload, emotional);

    await Promise.all([
      recordStudyContinuity(userId, action, payload, result.threadId),
      recordAmbientSuggestion(userId, action, payload, result.suggestedActions),
    ]);

    return sanitizeContextResponse(result as unknown as Record<string, unknown>);
  }
);
