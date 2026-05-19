// berean/controllers/evaluateAuthorityEscalation.ts
// Authority Alignment System: evaluates whether a message requires escalation.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { authorityGuardrailEngine } from "../services/AuthorityGuardrailEngine";
import { spiritualStateEngine } from "../services/SpiritualStateEngine";

export const bereanEvaluateAuthorityEscalation = onCall(
  { region: "us-central1", timeoutSeconds: 10 , enforceAppCheck: true }, 
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const { messageText, sensitivityFlags = [] } = request.data as {
      messageText: string;
      sensitivityFlags?: string[];
    };

    if (!messageText) throw new HttpsError("invalid-argument", "messageText required.");

    const classification = spiritualStateEngine.classify(messageText);
    const result = authorityGuardrailEngine.evaluate(
      messageText,
      [...(classification.sensitivityFlags ?? []), ...sensitivityFlags] as any[]
    );

    return {
      success: true,
      topicClass: result.topicClass,
      escalationRequired: result.escalationRequired,
      escalationTargets: result.escalationTargets,
      safeResponsePolicy: result.safeResponsePolicy,
    };
  }
);
