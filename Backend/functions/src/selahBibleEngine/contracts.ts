export const SELAH_CONTRACTS_VERSION = "2026-05-25-v1" as const;
export const SELAH_STUDY_PROMPT_VERSION = "selah-study-v1" as const;
export const SELAH_THEME_PROMPT_VERSION = "selah-theme-v1" as const;
export const SELAH_SAFETY_PROMPT_VERSION = "selah-safety-v1" as const;

export type SelahSafetyTheme =
  | "neutral"
  | "anxiety"
  | "grief"
  | "doubt"
  | "addiction"
  | "selfHarm"
  | "abuse"
  | "trafficking"
  | "coercion";

export type SelahTranslation = "KJV" | "ESV";
export type SelahLensActionKind = "understand" | "crossReferences" | "reflect" | "pray" | "addToSession" | "more";

export interface BereanStudySheetRequest {
  verseId: string;
  translation: SelahTranslation;
  verseText: string;
  locale?: string;
}

export interface BereanStudySheetResponse {
  cacheKey: string;
  verseId: string;
  translation: SelahTranslation;
  layers: BereanStudySheetLayers;
  crossReferences: string[];
  provenance: BereanStudySheetProvenance;
  generatedAt: string;
  promptVersion: string;
}

export interface BereanStudySheetLayers {
  text: { observations: string[]; keyTerms: BereanKeyTerm[]; uncertaintyNotes: string[] };
  context: { historicalNotes: string[]; literaryNotes: string[]; canonicalLinks: string[] };
  interpretation: {
    summary: string;
    interpretiveOptions: BereanInterpretiveOption[];
    denominationalPosture: string;
    uncertaintyNotes: string[];
  };
  application: { prompts: string[]; cautions: string[]; prayerSeed?: string };
}

export interface BereanKeyTerm { id: string; term: string; note: string }
export interface BereanInterpretiveOption { id: string; label: string; summary: string; confidence: number }

export interface BereanStudySheetProvenance {
  provider: string;
  model: string;
  runId: string;
  scriptureSource: string;
  scriptureLoadedByClient: boolean;
  factInterpretationSeparated: boolean;
}

export interface ClassifyVerseThemeRequest {
  verseId: string;
  translation: SelahTranslation;
  verseText: string;
}

export interface ClassifyVerseThemeResponse {
  verseId: string;
  theme: SelahSafetyTheme;
  confidence: number;
  suggestedActions: SelahLensActionKind[];
  promptVersion: string;
}

export interface ClassifySafetyRequest {
  reflectionText: string;
  verseId?: string;
  locale?: string;
}

export interface ClassifySafetyResponse {
  theme: SelahSafetyTheme;
  confidence: number;
  canGenerateDevotional: boolean;
  canShare: boolean;
  supportPayload?: SelahSupportPayload;
  promptVersion: string;
}

export interface SelahSupportPayload {
  groundingTitle: string;
  groundingSteps: string[];
  trustedHumanPrompt: string;
  resourceLinks: SelahResourceLink[];
}

export interface SelahResourceLink { id: string; title: string; url: string; region?: string }

export function safetyThemeBlocksGeneration(theme: SelahSafetyTheme): boolean {
  return ["selfHarm", "abuse", "trafficking", "coercion"].includes(theme);
}
