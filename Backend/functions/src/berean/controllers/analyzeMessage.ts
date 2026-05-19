// berean/controllers/analyzeMessage.ts
// Lightweight spiritual state classification without full LLM response.
// Used for posture detection before composing.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { classifySpiritualState } from "../services/SpiritualStateEngine";

export const bereanAnalyzeMessage = onCall(
  { region: "us-central1", timeoutSeconds: 10 , enforceAppCheck: true }, 
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const { messageText } = request.data as {
      messageText: string;
    };

    if (!messageText) throw new HttpsError("invalid-argument", "messageText required.");

    const classification = await classifySpiritualState(
      request.auth.uid,
      messageText,
      []
    );

    const compatibilityPayload = {
      primaryState: classification.primaryState,
      signals: classification.signals,
      selectedResponseMode: classification.selectedResponseMode,
      sensitivityFlags: [],
      escalationTriggered: classification.escalationTriggered,
      escalationReason: classification.escalationReason ?? null,
      sessionId: classification.sessionId,
      classifiedAt: classification.classifiedAt.toMillis() / 1000,
    };

    return {
      success: true,
      ...compatibilityPayload,
      classification: compatibilityPayload,
    };
  }
);
