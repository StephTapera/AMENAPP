// berean/controllers/studyPassage.ts
// Living Scripture Graph hydration endpoint.
// Called by BereanAPIClient.swift studyPassage().

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { scriptureGraphService } from "../services/ScriptureGraphService";
import { passageRepository } from "../repositories/PassageRepository";
import { analyticsService } from "../services/AnalyticsService";
import { discipleshipTrackerService } from "../services/DiscipleshipTrackerService";

export const bereanStudyPassage = onCall(
  { region: "us-central1", timeoutSeconds: 30 },
  async (request) => {
    // ── Auth ─────────────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const userId = request.auth.uid;
    const {
      reference,
      translation = "ESV",
      includeWordStudy = true,
      includeChristConnection = true,
      includeImmersionMode = false,
    } = request.data as {
      reference: string;
      translation?: string;
      includeWordStudy?: boolean;
      includeChristConnection?: boolean;
      includeImmersionMode?: boolean;
    };

    if (!reference || typeof reference !== "string") {
      throw new HttpsError("invalid-argument", "reference is required.");
    }

    const passageId = passageRepository.normalizeReference(reference);

    analyticsService.log({
      event: "passage_opened",
      userId,
      passageId,
    });

    // ── Hydrate ──────────────────────────────────────────────────────────────
    const payload = await scriptureGraphService.hydratePassage(passageId, {
      includeWordStudy,
      includeChristConnection,
      includeApplication: true,
      includeImmersionMode,
      translation,
    });

    if (!payload) {
      // Passage not in Firestore yet — return a minimal stub
      // In production this would trigger an async enrichment job
      return {
        id: passageId,
        reference,
        text: "",
        summary: `${reference} — detailed study data is being prepared.`,
        themes: [],
        crossReferences: [],
        wordInsights: [],
        christConnection: null,
        applicationPaths: [],
        sceneContext: null,
        cacheHit: false,
      };
    }

    if (payload.cacheHit) {
      analyticsService.log({ event: "cache_hit", userId, passageId });
    } else {
      analyticsService.log({ event: "cache_miss", userId, passageId });
    }

    // Fire-and-forget: record discipleship study event
    discipleshipTrackerService
      .recordStudySession(userId, "study_" + passageId, passageId, payload.themes.map((t) => t.id))
      .catch(() => {});

    return payload;
  }
);
