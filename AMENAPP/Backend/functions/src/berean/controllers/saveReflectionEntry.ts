// berean/controllers/saveReflectionEntry.ts
// Persists a private reflection entry to /users/{uid}/reflectionEntries/.
// Private by default — never accessible to other users without explicit sharing.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { discipleshipRepository } from "../repositories/DiscipleshipRepository";
import { analyticsService } from "../services/AnalyticsService";

export const bereanSaveReflectionEntry = onCall(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const userId = request.auth.uid;
    const {
      conversationId,
      title,
      text,
      passageIds = [],
      themeIds = [],
      privacyLevel = "private",
      sourceType = "study",
    } = request.data as {
      conversationId: string;
      title?: string;
      text: string;
      passageIds?: string[];
      themeIds?: string[];
      privacyLevel?: "private" | "shareable_with_leader";
      sourceType?: "study" | "immersion" | "follow_up" | "manual";
    };

    if (!text || text.trim().length === 0) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (!conversationId) {
      throw new HttpsError("invalid-argument", "conversationId is required.");
    }

    const now = admin.firestore.Timestamp.now();
    const reflectionEntryId = await discipleshipRepository.saveReflection(userId, {
      userId,
      conversationId,
      passageIds,
      themeIds,
      title: title ?? "Reflection",
      text: text.trim(),
      privacyLevel,
      sourceType,
      createdAt: now,
      updatedAt: now,
    });

    await discipleshipRepository.logEvent(userId, "reflection_submitted", {
      conversationId,
      reflectionEntryId,
      passageIds,
      themeIds,
    });

    analyticsService.log({ event: "reflection_saved", userId, conversationId });

    return { success: true, reflectionEntryId };
  }
);
