// berean/controllers/generateDiscipleshipNextStep.ts
// Generates practice recommendations and follow-up prompts after a study session.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { discipleshipTrackerService } from "../services/DiscipleshipTrackerService";

export const bereanGenerateDiscipleshipNextStep = onCall(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const userId = request.auth.uid;
    const {
      conversationId,
      sourceThemeIds = [],
      sourcePassageIds = [],
    } = request.data as {
      conversationId: string;
      sourceThemeIds?: string[];
      sourcePassageIds?: string[];
    };

    if (!conversationId) {
      throw new HttpsError("invalid-argument", "conversationId required.");
    }

    const result = await discipleshipTrackerService.generateNextSteps(
      userId,
      conversationId,
      sourceThemeIds,
      sourcePassageIds
    );

    return {
      success: true,
      recommendations: result.recommendations,
      followUpSuggestions: result.followUps,
    };
  }
);
