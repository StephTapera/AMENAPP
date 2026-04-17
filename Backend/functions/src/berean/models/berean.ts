/**
 * berean.ts — Shared TypeScript types for the Berean Spiritual Intelligence Layers.
 * Mirrors the Swift domain models in BereanSpiritualModels.swift,
 * ScriptureGraphModels.swift, and DiscipleshipModels.swift.
 */

// ---------------------------------------------------------------------------
// Spiritual State
// ---------------------------------------------------------------------------

export type SpiritualPrimaryState =
  | "academic"
  | "devotional"
  | "grieving"
  | "crisis"
  | "wrestling"
  | "prayerful"
  | "discerning"
  | "neutral";

export type ResponseMode =
  | "scholarly"
  | "pastoral"
  | "comfort"
  | "crisis"
  | "exploratory"
  | "prayer_support"
  | "balanced";

export type SensitivityFlag =
  | "divine_authority_assertion"
  | "scripture_contradiction"
  | "pastoral_escalation"
  | "crisis_escalation"
  | "controversial_doctrine"
  | "minor_user"
  | "scrupulosity_risk";

export interface SpiritualStateSignals {
  emotionalIntensity: number;     // 0–1
  containsDoubt: boolean;
  referencesHardship: boolean;
  crisisSignalDetected: boolean;
  doctrinalQuery: boolean;
  mentionedLeader: boolean;
  classificationConfidence: number; // 0–1
}

export interface SpiritualStateClassification {
  primaryState: SpiritualPrimaryState;
  signals: SpiritualStateSignals;
  selectedResponseMode: ResponseMode;
  escalationTriggered: boolean;
  escalationReason?: string;
  sessionId: string;
  classifiedAt: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Study Cards
// ---------------------------------------------------------------------------

export type StudyCardType =
  | "scripture"
  | "word_study"
  | "historical_context"
  | "commentary"
  | "application"
  | "reflection"
  | "cross_reference"
  | "christ_connection"
  | "leader_referral"
  | "crisis_resource";

export interface StudyCard {
  id: string;
  type: StudyCardType;
  title: string;
  content: string;
  scriptureRef?: string;
  resourceURL?: string;
  sortOrder: number;
}

// ---------------------------------------------------------------------------
// Structured Response
// ---------------------------------------------------------------------------

export interface BereanStructuredResponse {
  responseId: string;
  answer: string;
  responseMode: ResponseMode;
  spiritualState?: SpiritualStateClassification;
  studyCards: StudyCard[];
  sensitivityFlags: SensitivityFlag[];
  leadershipPromptShown: boolean;
  followUpSuggestion?: string;
  anchorPassage?: string;
  doctrinalConfidence: number;   // 0–1
  generatedAt: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Scripture Graph
// ---------------------------------------------------------------------------

export type OriginalLanguage = "greek" | "hebrew" | "aramaic";

export type CrossRefRelationship =
  | "fulfillment"
  | "parallel"
  | "contrast"
  | "quotation"
  | "allusion"
  | "commentary"
  | "application";

export interface ScriptureReference {
  book: string;
  chapter: number;
  verseStart: number;
  verseEnd?: number;
  translation: string;
}

export interface WordStudyItem {
  id: string;
  surfaceWord: string;
  originalWord: string;
  transliteration: string;
  strongsNumber?: string;
  definition: string;
  semanticRange: string[];
  language: OriginalLanguage;
  devotionalNote?: string;
}

export interface ChristConnectionItem {
  passageId: string;
  connectionStatement: string;
  ntFulfillmentReference?: ScriptureReference;
  connectionType: "direct_prophecy" | "typology" | "thematic_pattern" | "fulfillment";
  confidence: number;     // 0–1; only show if ≥ 0.6
  hermeneuticalTradition?: string;
}

export interface ApplicationPath {
  id: string;
  passageId: string;
  prompt: string;
  category: "personal" | "relational" | "communal" | "evangelistic" | "justice";
  relational: boolean;
  actionStep?: string;
}

export interface ImmersionStudyStructure {
  observation: string;
  interpretation: string;
  reflection: string;
  hasInterpretiveDebate: boolean;
  interpretiveDebateNote?: string;
}

export interface ScriptureSceneContext {
  passageId: string;
  historicalSetting: string;
  culturalNotes: string[];
  authorContext?: string;
  geographicalContext?: string;
  datePeriod?: string;
  keyFigures: string[];
  literaryGenre: string;
  studyStructure?: ImmersionStudyStructure;
}

export interface ScripturePassagePayload {
  id: string;
  reference: ScriptureReference;
  text: string;
  summary: string;
  themes: ScriptureTheme[];
  crossReferences: ScriptureCrossRef[];
  wordInsights: WordStudyItem[];
  christConnection?: ChristConnectionItem;
  applicationPaths: ApplicationPath[];
  sceneContext?: ScriptureSceneContext;
  cachedAt: FirebaseFirestore.Timestamp;
}

export interface ScriptureTheme {
  id: string;
  name: string;
  description: string;
  relatedPassages: string[];
  category: "theological" | "narrative" | "prophetic" | "wisdom" | "ethical" | "eschatological";
}

export interface ScriptureCrossRef {
  id: string;
  sourcePassageId: string;
  targetReference: ScriptureReference;
  targetText: string;
  relationshipType: CrossRefRelationship;
  strength: number;   // 0–1
}

// ---------------------------------------------------------------------------
// Discipleship
// ---------------------------------------------------------------------------

export type DiscipleshipEventType =
  | "study_session_completed"
  | "reflection_submitted"
  | "practice_completed"
  | "leader_connected"
  | "leader_referral_accepted"
  | "growth_path_started"
  | "growth_path_completed"
  | "crisis_escalated"
  | "prayer_recorded"
  | "scripture_memorized";

export interface DiscipleshipEvent {
  id: string;
  userId: string;
  eventType: DiscipleshipEventType;
  passageId?: string;
  passageReference?: string;
  bereanSessionId?: string;
  note?: string;
  occurredAt: FirebaseFirestore.Timestamp;
}

export interface LeadershipReferral {
  id: string;
  userId: string;
  leaderUserId?: string;
  triggerFlag: SensitivityFlag;
  contextSummary: string;
  suggestedNextStep: string;
  status: "pending" | "notified" | "acknowledged" | "resolved" | "expired";
  createdAt: FirebaseFirestore.Timestamp;
  acknowledgedAt?: FirebaseFirestore.Timestamp;
  resolvedAt?: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Follow-Up Prompts
// ---------------------------------------------------------------------------

export interface FollowUpPrompt {
  id: string;
  userId: string;
  promptText: string;
  sourceSessionId: string;
  passageReference: string;
  scheduledFor: FirebaseFirestore.Timestamp;
  status: "pending" | "delivered" | "dismissed" | "engaged";
  createdAt: FirebaseFirestore.Timestamp;
  dismissedAt?: FirebaseFirestore.Timestamp;
  engagedAt?: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Request / Response contracts for Cloud Functions
// ---------------------------------------------------------------------------

export interface GenerateStructuredResponseRequest {
  conversationId: string;
  userMessage: string;
  passageContext?: string;        // Passage currently being studied (optional)
  previousMessages?: Array<{ role: "user" | "assistant"; content: string }>;
}

export interface StudyPassageRequest {
  reference: string;              // e.g. "John 3:16" or "Romans 8:28-30"
  translation?: string;           // Default: "ESV"
  includeWordStudy?: boolean;
  includeChristConnection?: boolean;
  includeImmersionMode?: boolean;
}
