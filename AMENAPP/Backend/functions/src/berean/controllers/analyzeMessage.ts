// berean/controllers/analyzeMessage.ts
// Lightweight spiritual state classification without full LLM response.
// Used for posture detection before composing.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { spiritualStateEngine } from "../services/SpiritualStateEngine";

export const bereanAnalyzeMessage = onCall(
  { region: "us-central1", timeoutSeconds: 10 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const { conversationId, messageText, clientContext } = request.data as {
      conversationId: string;
      messageText: string;
      clientContext?: { currentPassageId?: string; currentMode?: string };
    };

    if (!messageText) throw new HttpsError("invalid-argument", "messageText required.");

    const classification = spiritualStateEngine.classify(messageText, clientContext);

    return {
      success: true,
      classification: {
        primaryState: classification.primaryState,
        secondaryStates: classification.secondaryStates,
        confidence: classification.confidence,
        responseMode: classification.responseMode,
        sensitivityFlags: classification.sensitivityFlags,
        leadershipEscalationRecommended: classification.leadershipEscalationRecommended,
        crisisSupportRecommended: classification.crisisSupportRecommended,
      },
    };
  }
);
