// berean/services/ScriptureGraphService.ts
// Hydrates a full scripture passage payload from Firestore collections.
// Uses caching for common passages to keep latency low.

import { passageRepository } from "../repositories/PassageRepository";
import { cacheRepository } from "../repositories/CacheRepository";
import {
  PassagePayload,
  ThemePayload,
  CrossRefPayload,
  WordStudyPayload,
  ChristConnectionPayload,
  ApplicationPathPayload,
  SceneContextPayload,
} from "../models/scripture";

export class ScriptureGraphService {
  async hydratePassage(
    passageId: string,
    options: {
      includeWordStudy?: boolean;
      includeChristConnection?: boolean;
      includeApplication?: boolean;
      includeImmersionMode?: boolean;
      translation?: string;
    } = {}
  ): Promise<PassagePayload | null> {
    const {
      includeWordStudy = true,
      includeChristConnection = true,
      includeApplication = true,
      includeImmersionMode = false,
      translation = "ESV",
    } = options;

    // ── Cache check ──────────────────────────────────────────────────────────
    const cacheKey = cacheRepository.cacheKeyForPassage(passageId, translation);
    const cached = await cacheRepository.get(cacheKey);
    if (cached) {
      return { ...(cached as unknown as PassagePayload), cacheHit: true };
    }

    // ── Fetch passage ────────────────────────────────────────────────────────
    const passageDoc = await passageRepository.getPassage(passageId);
    if (!passageDoc) return null;

    // ── Parallel fetch all related data ─────────────────────────────────────
    const [
      crossRefDocs,
      wordInsightDocs,
      christConnectionDocs,
      themeDocs,
      applicationPathDocs,
      sceneContextDoc,
    ] = await Promise.all([
      passageRepository.getCrossRefs(passageId),
      includeWordStudy ? passageRepository.getWordInsights(passageId) : Promise.resolve([]),
      includeChristConnection ? passageRepository.getChristConnections(passageId) : Promise.resolve([]),
      passageRepository.getThemesByIds(passageDoc.majorThemes ?? []),
      includeApplication ? passageRepository.getApplicationPaths(passageDoc.applicationPathIds ?? []) : Promise.resolve([]),
      includeImmersionMode ? passageRepository.getSceneContext(passageId) : Promise.resolve(null),
    ]);

    // ── Build themes payload ─────────────────────────────────────────────────
    const themes: ThemePayload[] = themeDocs.map((t) => ({
      id: t.id,
      name: t.data.name,
      description: t.data.description,
      category: t.data.pastoralSensitivityLevel ?? "low",
    }));

    // ── Build cross refs payload ─────────────────────────────────────────────
    const crossReferences: CrossRefPayload[] = crossRefDocs.map((c) => ({
      id: c.id,
      targetReference: c.data.targetPassageId,
      targetText: c.data.explanation,
      relationshipType: c.data.relationshipType,
      strength: c.data.strengthScore,
    }));

    // ── Build word study payload ─────────────────────────────────────────────
    const wordInsights: WordStudyPayload[] = wordInsightDocs.map((w) => ({
      id: w.id,
      surfaceWord: w.data.lemma,
      originalWord: w.data.lemma,
      transliteration: w.data.transliteration,
      strongsNumber: null,
      definition: w.data.definition,
      semanticRange: w.data.translationNotes ?? [],
      language: w.data.language,
      devotionalNote: w.data.nuance ?? null,
    }));

    // ── Build christ connection payload ──────────────────────────────────────
    const christConnection: ChristConnectionPayload | null =
      christConnectionDocs.length > 0
        ? {
            connectionStatement: christConnectionDocs[0].data.explanation,
            ntFulfillmentReference:
              christConnectionDocs[0].data.targetChristPassageIds?.[0] ?? null,
            connectionType: christConnectionDocs[0].data.connectionType,
            confidence: christConnectionDocs[0].data.confidenceLevel === "high" ? 0.95 :
              christConnectionDocs[0].data.confidenceLevel === "medium" ? 0.75 : 0.55,
          }
        : null;

    // ── Build application paths payload ─────────────────────────────────────
    const applicationPaths: ApplicationPathPayload[] = applicationPathDocs.map((a) => ({
      id: a.id,
      prompt: a.data.reflectionPrompts?.[0] ?? a.data.title,
      category: a.data.audienceTags?.[0] ?? "personal",
      relational: (a.data.audienceTags ?? []).some((t) =>
        ["relational", "communal"].includes(t)
      ),
      actionStep: a.data.practicePrompts?.[0] ?? null,
    }));

    // ── Build scene context payload ──────────────────────────────────────────
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

    // ── Assemble final payload ───────────────────────────────────────────────
    const payload: PassagePayload = {
      id: passageId,
      reference: `${passageDoc.book} ${passageDoc.chapterStart}:${passageDoc.verseStart}`,
      text: passageDoc.text,
      summary: passageDoc.summary,
      themes,
      crossReferences,
      wordInsights,
      christConnection,
      applicationPaths,
      sceneContext,
      cacheHit: false,
    };

    // ── Cache it ─────────────────────────────────────────────────────────────
    await cacheRepository.set(
      cacheKey,
      payload as unknown as Record<string, unknown>,
      "passage_study",
      passageId
    );

    return payload;
  }
}

export const scriptureGraphService = new ScriptureGraphService();
