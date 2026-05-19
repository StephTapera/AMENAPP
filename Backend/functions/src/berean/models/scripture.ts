// berean/models/scripture.ts
// TypeScript interfaces for the Living Scripture Graph data model.
// Mirrors the Firestore collection schemas defined in the architecture spec.

import { Timestamp } from "firebase-admin/firestore";

// ── Scripture Book ────────────────────────────────────────────────────────────

export interface ScriptureBook {
  name: string;
  testament: "old" | "new";
  abbreviation: string;
  order: number;
  chapterCount: number;
  metadata: Record<string, unknown>;
  updatedAt: Timestamp;
}

// ── Scripture Passage ─────────────────────────────────────────────────────────
// passageId format: "romans_5_3" or "john_3_16_18"

export interface ScripturePassageDoc {
  book: string;
  chapterStart: number;
  chapterEnd: number;
  verseStart: number;
  verseEnd: number;
  translation: string;
  text: string;
  summary: string;
  testament: "old" | "new";
  people: string[];
  places: string[];
  timelineEra: string;
  majorThemes: string[];
  christConnectionIds: string[];
  crossRefIds: string[];
  wordInsightIds: string[];
  applicationPathIds: string[];
  contextSummary: string;
  embeddingRef: string | null;
  cacheVersion: number;
  updatedAt: Timestamp;
}

// ── Cross Reference ───────────────────────────────────────────────────────────

export interface ScriptureCrossRefDoc {
  sourcePassageId: string;
  targetPassageId: string;
  relationshipType:
    | "theme"
    | "quotation"
    | "echo"
    | "prophecy"
    | "fulfillment"
    | "parallel"
    | "contrast";
  explanation: string;
  strengthScore: number;
  updatedAt: Timestamp;
}

// ── Word Insight (Hebrew/Greek) ───────────────────────────────────────────────

export interface ScriptureWordInsightDoc {
  passageId: string;
  lemma: string;
  language: "hebrew" | "aramaic" | "greek";
  transliteration: string;
  morphology: string;
  definition: string;
  nuance: string;
  translationNotes: string[];
  doctrinalSensitivity: "low" | "medium" | "high";
  updatedAt: Timestamp;
}

// ── Christ Connection ─────────────────────────────────────────────────────────

export interface ScriptureChristConnectionDoc {
  sourcePassageId: string;
  targetChristPassageIds: string[];
  connectionType:
    | "type"
    | "promise"
    | "fulfillment"
    | "character"
    | "mission"
    | "suffering"
    | "kingship"
    | "priesthood";
  explanation: string;
  confidenceLevel: "high" | "medium" | "careful_inference";
  updatedAt: Timestamp;
}

// ── Theme ─────────────────────────────────────────────────────────────────────

export interface ScriptureThemeDoc {
  name: string;
  description: string;
  parentThemes: string[];
  relatedThemeIds: string[];
  passageIds: string[];
  applicationTags: string[];
  pastoralSensitivityLevel: "low" | "medium" | "high";
  updatedAt: Timestamp;
}

// ── Application Path ──────────────────────────────────────────────────────────

export interface ScriptureApplicationPathDoc {
  title: string;
  themeIds: string[];
  passageIds: string[];
  audienceTags: string[];
  lifeSituationTags: string[];
  reflectionPrompts: string[];
  practicePrompts: string[];
  leadershipDiscussionPrompts: string[];
  updatedAt: Timestamp;
}

// ── Scene Context ─────────────────────────────────────────────────────────────

export interface ScriptureSceneContextDoc {
  passageId: string;
  settingSummary: string;
  historicalDetails: string[];
  socialDynamics: string[];
  religiousContext: string[];
  politicalContext: string[];
  interpretiveWarnings: string[];
  reflectionHooks: string[];
  updatedAt: Timestamp;
}

// ── Character Lens ────────────────────────────────────────────────────────────

export interface ScriptureCharacterLensDoc {
  passageId: string;
  characterName: string;
  roleInPassage: string;
  observedMotivations: string[];
  socialPosition: string;
  risksOrCosts: string[];
  reflectionQuestions: string[];
  updatedAt: Timestamp;
}

// ── Historical Annotation ─────────────────────────────────────────────────────

export interface HistoricalAnnotationDoc {
  passageId: string;
  category: "cultural" | "political" | "religious" | "linguistic" | "geographic";
  title: string;
  body: string;
  confidence: "high" | "medium" | "careful_inference";
  updatedAt: Timestamp;
}

// ── Immersion Reflection Prompt ───────────────────────────────────────────────

export interface ImmersionReflectionPromptDoc {
  passageId: string;
  promptType:
    | "observation"
    | "context"
    | "christ_connection"
    | "self_reflection"
    | "prayer";
  promptText: string;
  updatedAt: Timestamp;
}

// ── Study Cache ───────────────────────────────────────────────────────────────

export interface StudyCacheDoc {
  cacheType:
    | "passage_study"
    | "theme_explorer"
    | "word_study"
    | "immersion_payload";
  sourceId: string;
  locale: string;
  translation: string;
  payload: Record<string, unknown>;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  version: number;
}

// ── Hydrated Payload types (returned to client) ───────────────────────────────

export interface PassagePayload {
  id: string;
  reference: string;
  text: string;
  summary: string;
  themes: ThemePayload[];
  crossReferences: CrossRefPayload[];
  wordInsights: WordStudyPayload[];
  christConnection: ChristConnectionPayload | null;
  applicationPaths: ApplicationPathPayload[];
  sceneContext: SceneContextPayload | null;
  cacheHit: boolean;
}

export interface ThemePayload {
  id: string;
  name: string;
  description: string;
  category: string;
}

export interface CrossRefPayload {
  id: string;
  targetReference: string;
  targetText: string;
  relationshipType: string;
  strength: number;
}

export interface WordStudyPayload {
  id: string;
  surfaceWord: string;
  originalWord: string;
  transliteration: string;
  strongsNumber: string | null;
  definition: string;
  semanticRange: string[];
  language: string;
  devotionalNote: string | null;
}

export interface ChristConnectionPayload {
  connectionStatement: string;
  ntFulfillmentReference: string | null;
  connectionType: string;
  confidence: number;
}

export interface ApplicationPathPayload {
  id: string;
  prompt: string;
  category: string;
  relational: boolean;
  actionStep: string | null;
}

export interface SceneContextPayload {
  historicalSetting: string;
  culturalNotes: string[];
  authorContext: string | null;
  geographicalContext: string | null;
  datePeriod: string | null;
  keyFigures: string[];
  literaryGenre: string;
  studyStructure: ImmersionStudyStructurePayload | null;
}

export interface ImmersionStudyStructurePayload {
  observation: string;
  interpretation: string;
  reflection: string;
  hasInterpretiveDebate: boolean;
  interpretiveDebateNote: string | null;
}

export interface ImmersionPayload {
  sceneContext: SceneContextPayload;
  characterLenses: CharacterLensPayload[];
  historicalAnnotations: HistoricalAnnotationPayload[];
  reflectionPrompts: ReflectionPromptPayload[];
}

export interface CharacterLensPayload {
  id: string;
  characterName: string;
  roleInPassage: string;
  observedMotivations: string[];
  socialPosition: string;
  risksOrCosts: string[];
  reflectionQuestions: string[];
}

export interface HistoricalAnnotationPayload {
  id: string;
  category: string;
  title: string;
  body: string;
  confidence: string;
}

export interface ReflectionPromptPayload {
  id: string;
  promptType: string;
  promptText: string;
}
