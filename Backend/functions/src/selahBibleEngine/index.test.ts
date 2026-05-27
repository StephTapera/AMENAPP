import {
  actionsForTheme,
  assertNoScriptureTextInStudySheet,
  buildSafetyResponse,
  classifyThemeHeuristically,
  sanitizeStudySheetResponse,
  studySheetCacheKey,
} from "./index";
import { BereanStudySheetResponse } from "./contracts";

describe("Selah Bible Engine contracts", () => {
  it("creates stable cache keys without Firestore-hostile characters", () => {
    expect(studySheetCacheKey("PSA.1.3", "ESV", "selah-study-v1")).toBe("ESV_PSA_1_3_selah-study-v1");
  });

  it("rejects study sheet responses carrying scripture text fields", () => {
    const response = minimalResponse() as BereanStudySheetResponse & { verseText: string };
    response.verseText = "He shall be like a tree...";
    expect(() => assertNoScriptureTextInStudySheet(response)).toThrow(/verseText/);
  });

  it("sanitizes cross references to verse ids only", () => {
    const response = minimalResponse();
    response.crossReferences = [" Jer.17.8 ", "John 15:5 says text", "", "PSA.1.3"];
    const clean = sanitizeStudySheetResponse(response);
    expect(clean.crossReferences).toEqual(["JER.17.8", "JOHN15", "PSA.1.3"]);
  });

  it("routes self harm reflections to support and disables generation and sharing", () => {
    const result = buildSafetyResponse("I want to die and I can't keep going.");
    expect(result.theme).toBe("selfHarm");
    expect(result.canGenerateDevotional).toBe(false);
    expect(result.canShare).toBe(false);
    expect(result.supportPayload?.resourceLinks.some((link) => link.id === "988")).toBe(true);
  });

  it("orders anxious passages toward prayer and session actions", () => {
    const classification = classifyThemeHeuristically("I am afraid and overwhelmed by worry.");
    expect(classification.theme).toBe("anxiety");
    expect(actionsForTheme(classification.theme).slice(0, 2)).toEqual(["pray", "addToSession"]);
  });
});

function minimalResponse(): BereanStudySheetResponse {
  return {
    cacheKey: "ESV_PSA_1_3_selah-study-v1",
    verseId: "PSA.1.3",
    translation: "ESV",
    layers: {
      text: { observations: ["Observation"], keyTerms: [], uncertaintyNotes: [] },
      context: { historicalNotes: [], literaryNotes: [], canonicalLinks: [] },
      interpretation: {
        summary: "Summary",
        interpretiveOptions: [],
        denominationalPosture: "neutral",
        uncertaintyNotes: [],
      },
      application: { prompts: [], cautions: [], prayerSeed: "Prayer" },
    },
    crossReferences: [],
    provenance: {
      provider: "test",
      model: "test",
      runId: "run",
      scriptureSource: "client_firestore_scripture_store",
      scriptureLoadedByClient: true,
      factInterpretationSeparated: true,
    },
    generatedAt: new Date(0).toISOString(),
    promptVersion: "selah-study-v1",
  };
}
