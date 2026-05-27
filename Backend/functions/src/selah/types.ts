/**
 * selah/types.ts
 *
 * Canonical type definitions for the Selah Bible Engine — Phase 2 (Berean Intelligence).
 * All callables in this module share these types. Scripture text is intentionally never
 * returned in API responses; callers must resolve verseId client-side from a trusted store.
 */

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

export type SelahLensActionKind =
  | "understand"
  | "crossReferences"
  | "reflect"
  | "pray"
  | "addToSession"
  | "more";

// ── Study Sheet ─────────────────────────────────────────────────────────────

export interface BereanStudySheetRequest {
  verseId: string;
  translation: SelahTranslation;
  verseText: string;
  locale?: string;
}

export interface BereanStudySheetLayers {
  text: BereanStudySheetTextLayer;
  context: BereanStudySheetContextLayer;
  interpretation: BereanStudySheetInterpretationLayer;
  application: BereanStudySheetApplicationLayer;
}

export interface BereanStudySheetTextLayer {
  observations: string[];
  keyTerms: BereanKeyTerm[];
  uncertaintyNotes: string[];
}

export interface BereanKeyTerm {
  id: string;
  term: string;
  note: string;
}

export interface BereanStudySheetContextLayer {
  historicalNotes: string[];
  literaryNotes: string[];
  canonicalLinks: string[];
}

export interface BereanStudySheetInterpretationLayer {
  summary: string;
  interpretiveOptions: BereanInterpretiveOption[];
  denominationalPosture: string;
  uncertaintyNotes: string[];
}

export interface BereanInterpretiveOption {
  id: string;
  label: string;
  summary: string;
  confidence: number;
}

export interface BereanStudySheetApplicationLayer {
  prompts: string[];
  cautions: string[];
  prayerSeed?: string;
}

export interface BereanStudySheetProvenance {
  provider: string;
  model: string;
  runId: string;
  scriptureSource: string;
  scriptureLoadedByClient: boolean;
  factInterpretationSeparated: boolean;
}

/**
 * Scripture text is intentionally absent — resolve verseId client-side from trusted store.
 */
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

// ── Verse Theme Classification ───────────────────────────────────────────────

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

// ── Safety Classification ────────────────────────────────────────────────────

export interface ClassifySafetyRequest {
  reflectionText: string;
  verseId?: string;
  locale?: string;
}

export interface SelahSupportPayload {
  groundingTitle: string;
  groundingSteps: string[];
  trustedHumanPrompt: string;
  resourceLinks: SelahResourceLink[];
}

export interface SelahResourceLink {
  id: string;
  title: string;
  url: string;
  region?: string | null;
}

export interface ClassifySafetyResponse {
  theme: SelahSafetyTheme;
  confidence: number;
  canGenerateDevotional: boolean;
  canShare: boolean;
  supportPayload?: SelahSupportPayload;
  promptVersion: string;
}

// ── Guard functions ──────────────────────────────────────────────────────────

/**
 * Returns true for themes that must block AI-generated content and require
 * human support routing (self-harm, abuse, trafficking, coercion).
 */
export function safetyThemeBlocksGeneration(theme: SelahSafetyTheme): boolean {
  return ["selfHarm", "abuse", "trafficking", "coercion"].includes(theme);
}

/**
 * Throws if the study sheet response contains any field that echoes scripture text.
 * Scripture must always be resolved client-side from the trusted scripture store.
 */
export function assertNoScriptureTextInResponse(response: BereanStudySheetResponse): void {
  const forbidden = ["verseText", "scriptureText", "textContent", "passageText"];
  const s = JSON.stringify(response);
  for (const k of forbidden) {
    if (s.includes(`"${k}"`)) {
      throw new Error(
        `StudySheetResponse must not contain field ${k}; resolve verseId client-side.`
      );
    }
  }
}
