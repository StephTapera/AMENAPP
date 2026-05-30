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
  | "balanced"
  // Extended modes used by responseModePrompt.ts
  | "deep_exegesis"
  | "study"
  | "gentle_pastoral"
  | "prayerful_reflection"
  | "crisis_safe"
  | "leadership_redirect"
  | "short_grounding";

export type SensitivityFlag =
  | "divine_authority_assertion"
  | "scripture_contradiction"
  | "pastoral_escalation"
  | "crisis_escalation"
  | "controversial_doctrine"
  | "minor_user"
  | "scrupulosity_risk"
  // Extended flags used by sensitiveTopicPolicy.ts
  | "self_harm"
  | "suicidal_language"
  | "abuse"
  | "spiritual_abuse"
  | "medical"
  | "legal"
  | "doctrinal_conflict";

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
  sensitivityFlags?: SensitivityFlag[];
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

// ---------------------------------------------------------------------------
// Conversation / Message
// ---------------------------------------------------------------------------

export interface BereanMessage {
  id: string;
  conversationId: string;
  role: "user" | "assistant";
  content: string;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface BereanConversation {
  id: string;
  userId: string;
  title: string;
  currentMode: "chat" | "study" | "prayer" | "discipleship";
  lastMessageAt: FirebaseFirestore.Timestamp;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Discipleship Profile / Practice
// ---------------------------------------------------------------------------

export interface DiscipleshipProfile {
  userId: string;
  totalStudySessions: number;
  lastStudiedBook?: string;
  currentGrowthPath?: string;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface PracticeRecommendation {
  id: string;
  userId: string;
  title: string;
  description: string;
  category: "prayer" | "study" | "community" | "service" | "rest";
  status: "open" | "completed" | "dismissed";
  sourceSessionId?: string;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface ReflectionEntry {
  id: string;
  userId: string;
  passageReference?: string;
  reflectionText?: string;
  text?: string;
  title?: string;
  mood?: string;
  conversationId?: string;
  passageIds?: string[];
  themeIds?: string[];
  privacyLevel?: "private" | "shareable_with_leader";
  sourceType?: "study" | "immersion" | "follow_up" | "manual";
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// Safety Event
// ---------------------------------------------------------------------------

export interface BereanSafetyEvent {
  id: string;
  userId: string;
  conversationId: string;
  messageId?: string;
  eventType: "crisis_detected" | "authority_violation" | "sensitivity_flag" | "escalation";
  flagsTriggered: SensitivityFlag[];
  actionTaken: "crisis_card_shown" | "leadership_referral_created" | "response_patched" | "logged_only";
  generatedAt: FirebaseFirestore.Timestamp;
}

// ---------------------------------------------------------------------------
// LLM Output
// ---------------------------------------------------------------------------

export type TopicClass =
  | "scripture_study"
  | "prayer"
  | "doctrine"
  | "pastoral_care"
  | "crisis"
  | "general"
  | "off_topic"
  | "suicidality"
  | "abuse_disclosure"
  | "medical_override"
  | "legal_conflict"
  | "church_conflict"
  | "major_life_decision"
  | "doctrinal_dispute"
  | "pastoral_discernment";

export interface LLMStudyCard {
  type: string;
  title: string;
  body: string;
  scriptureRef?: string;
  metadata?: Record<string, unknown>;
}

export interface LLMStructuredOutput {
  answerText: string;
  responseMode: ResponseMode;
  scriptureReferences?: string[];
  studyCards: LLMStudyCard[];
  reflectionPrompts: string[];
  prayerPrompt?: string | null;
  leadershipPrompt?: {
    show?: boolean;
    title?: string;
    body: string;
    targetTypes?: string[];
  };
  sensitivitySummary?: {
    primaryState: string;
    sensitivityFlags: string[];
    topicClass: TopicClass | null;
  };
  suggestedNextActions?: Array<{
    type: string;
    label: string;
    payload: Record<string, unknown>;
  }>;
  confidenceNotes?: Record<string, unknown>;
  doctrinalConfidence: number;
  anchorPassage?: string;
  followUpSuggestion?: string;
}
