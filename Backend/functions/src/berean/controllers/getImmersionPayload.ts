// berean/controllers/getImmersionPayload.ts
// Scripture Immersion Mode: returns scene context, character lenses,
// historical annotations, and reflection prompts for a passage.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { passageRepository } from "../repositories/PassageRepository";
import { cacheRepository } from "../repositories/CacheRepository";
import { analyticsService } from "../services/AnalyticsService";
import {
  CharacterLensPayload,
  HistoricalAnnotationPayload,
  ReflectionPromptPayload,
  SceneContextPayload,
} from "../models/scripture";

export const bereanGetImmersionPayload = onCall(
  { region: "us-central1", timeoutSeconds: 20 , enforceAppCheck: true }, 
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.app) throw new HttpsError("unauthenticated", "App Check required.");

    const userId = request.auth.uid;
    const { passageId } = request.data as { passageId: string };
    if (!passageId) throw new HttpsError("invalid-argument", "passageId required.");

    // Cache check
    const cacheKey = cacheRepository.cacheKeyForImmersion(passageId);
    const cached = await cacheRepository.get(cacheKey);
    if (cached) {
      analyticsService.log({ event: "immersion_opened", userId, passageId, cacheHit: true });
      return { success: true, ...cached };
    }

    // Fetch in parallel
    const [sceneContextDoc, characterLensDocs, annotationDocs, promptDocs] =
      await Promise.all([
        passageRepository.getSceneContext(passageId),
        passageRepository.getCharacterLenses(passageId),
        passageRepository.getHistoricalAnnotations(passageId),
        passageRepository.getImmersionPrompts(passageId),
      ]);

    const sceneContext: SceneContextPayload | null = sceneContextDoc
      ? {
          historicalSetting: sceneContextDoc.data.settingSummary,
          culturalNotes: sceneContextDoc.data.historicalDetails ?? [],
          authorContext: null,
          geographicalContext: null,
          datePeriod: null,
          keyFigures: [],
          literaryGenre: "narrative",
          studyStructure: sceneContextDoc.data.reflectionHooks?.length
            ? {
                observation: sceneContextDoc.data.reflectionHooks[0] ?? "",
                interpretation: sceneContextDoc.data.reflectionHooks[1] ?? "",
                reflection: sceneContextDoc.data.reflectionHooks[2] ?? "",
                hasInterpretiveDebate: (sceneContextDoc.data.interpretiveWarnings ?? []).length > 0,
                interpretiveDebateNote:
                  sceneContextDoc.data.interpretiveWarnings?.[0] ?? null,
              }
            : null,
        }
      : null;

    const characterLenses: CharacterLensPayload[] = characterLensDocs.map((c) => ({
      id: c.id,
      characterName: c.data.characterName,
      roleInPassage: c.data.roleInPassage,
      observedMotivations: c.data.observedMotivations,
      socialPosition: c.data.socialPosition,
      risksOrCosts: c.data.risksOrCosts,
      reflectionQuestions: c.data.reflectionQuestions,
    }));

    const historicalAnnotations: HistoricalAnnotationPayload[] = annotationDocs.map((a) => ({
      id: a.id,
      category: a.data.category,
      title: a.data.title,
      body: a.data.body,
      confidence: a.data.confidence,
    }));

    const reflectionPrompts: ReflectionPromptPayload[] = promptDocs.map((p) => ({
      id: p.id,
      promptType: p.data.promptType,
      promptText: p.data.promptText,
    }));

    const payload = {
      sceneContext,
      characterLenses,
      historicalAnnotations,
      reflectionPrompts,
    };

    // Cache it
    await cacheRepository.set(cacheKey, payload as any, "immersion_payload", passageId);

    analyticsService.log({ event: "immersion_opened", userId, passageId, cacheHit: false });

    return { success: true, ...payload };
  }
);
