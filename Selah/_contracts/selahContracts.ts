export const SELAH_CONTRACTS_VERSION = "2026-05-25-v1" as const;

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
  // Scripture text is intentionally absent. Resolve every verseId from the trusted scripture store client-side.
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

export interface SelahResourceLink {
  id: string;
  title: string;
  url: string;
  region?: string;
}

export type SelahReflectionShareScope = "justMe" | "accountabilityPartner" | "namedGroup";

export interface SelahReflectionDocument {
  id: string;
  ownerUid: string;
  verseId?: string;
  translation?: SelahTranslation;
  body: string;
  safetyTheme: SelahSafetyTheme;
  shareScope: SelahReflectionShareScope;
  sharedWithUid?: string;
  sharedWithGroupId?: string;
  isShareEligible: boolean;
  relationalSignals: SelahRelationalSignals;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface SelahRelationalSignals {
  prayedByGroupCount: number;
  lastPrayerAt?: FirebaseFirestore.Timestamp;
}

export type GuidedSelahStep = "read" | "listen" | "understand" | "reflect" | "pray" | "apply" | "complete";

export interface GuidedSelahSessionDocument {
  id: string;
  ownerUid: string;
  verseId: string;
  translation: SelahTranslation;
  currentStep: GuidedSelahStep;
  completedSteps: GuidedSelahStep[];
  reflectionId?: string;
  cachedStudySheetKey?: string;
  recentThemes: SelahSafetyTheme[];
  startedAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  completedAt?: FirebaseFirestore.Timestamp;
}

export interface SelahVerseThemeTagDocument {
  id: string;
  verseId: string;
  translation: SelahTranslation;
  theme: SelahSafetyTheme;
  confidence: number;
  promptVersion: string;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface SelahStudySheetCacheDocument {
  id: string;
  verseId: string;
  translation: SelahTranslation;
  response: BereanStudySheetResponse;
  promptVersion: string;
  createdAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp;
}

export function safetyThemeBlocksGeneration(theme: SelahSafetyTheme): boolean {
  return ["selfHarm", "abuse", "trafficking", "coercion"].includes(theme);
}

export function assertNoScriptureTextInStudySheet(response: BereanStudySheetResponse): void {
  const forbiddenKeys = ["verseText", "scriptureText", "textContent", "passageText"];
  const serialized = JSON.stringify(response);
  for (const key of forbiddenKeys) {
    if (serialized.includes(`"${key}"`)) {
      throw new Error(`StudySheetResponse must not contain ${key}; resolve verseId client-side.`);
    }
  }
}
