// berean/models/berean.ts
// Core TypeScript interfaces for the Berean Spiritual Intelligence Layers.
// Shared across controllers, services, and repositories.

// ── Conversation ──────────────────────────────────────────────────────────────

export interface BereanConversation {
  id: string;
  userId: string;
  title: string;
  currentMode: "chat" | "study" | "journey" | "reflect" | "discuss";
  lastMessageAt: FirebaseFirestore.Timestamp;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface BereanMessage {
  id: string;
  conversationId: string;
  userId: string;
  role: "user" | "assistant" | "system";
  text: string;
  responseMode: string | null;
  primaryThemes: string[];
  passageIds: string[];
  sensitivityFlags: string[];
  structuredCards: StudyCard[];
  leadershipPromptShown: boolean;
  createdAt: FirebaseFirestore.Timestamp;
}

// ── Structured Response ───────────────────────────────────────────────────────

export interface BereanStructuredResponse {
  success: boolean;
  message: {
    answerText: string;
    responseMode: string;
    scriptureReferences: string[];
    studyCards: StudyCard[];
    reflectionPrompts: string[];
    prayerPrompt: string | null;
    leadershipPrompt: LeadershipPrompt | null;
    sensitivitySummary: SensitivitySummary;
    suggestedNextActions: SuggestedAction[];
    confidenceNotes: ConfidenceNotes;
  };
}

export interface StudyCard {
  type:
    | "context"
    | "cross_ref"
    | "theme"
    | "word_study"
    | "christ_connection"
    | "application"
    | "leadership"
    | "crisis_resource";
  title: string;
  body: string;
  metadata?: Record<string, unknown>;
}

export interface LeadershipPrompt {
  show: boolean;
  title?: string;
  body?: string;
  targetTypes?: string[];
}

export interface SensitivitySummary {
  primaryState: string;
  sensitivityFlags: string[];
  topicClass: string | null;
}

export interface SuggestedAction {
  type:
    | "open_passage"
    | "save_reflection"
    | "start_immersion"
    | "view_journey"
    | "talk_to_leader";
  label: string;
  payload?: Record<string, unknown>;
}

export interface ConfidenceNotes {
  containsInterpretiveCaution: boolean;
  containsLeadershipRedirect: boolean;
}

// ── Spiritual State ───────────────────────────────────────────────────────────

export type SpiritualPrimaryState =
  | "curious"
  | "devotional"
  | "academic"
  | "confused"
  | "grieving"
  | "ashamed"
  | "angry"
  | "church_hurt"
  | "seeking_guidance"
  | "crisis"
  | "resistant"
  | "reflective"
  | "neutral";

export type ResponseMode =
  | "study"
  | "gentle_pastoral"
  | "prayerful_reflection"
  | "crisis_safe"
  | "leadership_redirect"
  | "short_grounding"
  | "deep_exegesis"
  | "balanced";

export type SensitivityFlag =
  | "self_harm"
  | "suicidal_language"
  | "abuse"
  | "spiritual_abuse"
  | "trauma"
  | "marriage_crisis"
  | "doctrinal_conflict"
  | "pastoral_conflict"
  | "medical"
  | "legal"
  | "psychosis_sensitive_religious_language";

export interface SpiritualStateClassification {
  primaryState: SpiritualPrimaryState;
  secondaryStates: SpiritualPrimaryState[];
  confidence: number;
  responseMode: ResponseMode;
  sensitivityFlags: SensitivityFlag[];
  leadershipEscalationRecommended: boolean;
  crisisSupportRecommended: boolean;
}

// ── Authority ─────────────────────────────────────────────────────────────────

export type TopicClass =
  | "doctrinal_dispute"
  | "church_conflict"
  | "abuse_disclosure"
  | "suicidality"
  | "medical_override"
  | "legal_conflict"
  | "marriage_crisis"
  | "spiritual_oppression"
  | "major_life_decision"
  | "pastoral_discernment";

export interface SafeResponsePolicy {
  allowedResponseDepth: "limited" | "guided" | "full";
  mustShowLeadershipCard: boolean;
  mustShowCrisisSupport: boolean;
  mustShowMedicalDisclaimer: boolean;
  mustShowLegalDisclaimer: boolean;
}

export interface AuthorityEscalationResult {
  topicClass: TopicClass | null;
  escalationRequired: boolean;
  escalationTargets: string[];
  safeResponsePolicy: SafeResponsePolicy;
}

// ── Safety Event ──────────────────────────────────────────────────────────────

export interface BereanSafetyEvent {
  id: string;
  userId: string;
  conversationId: string;
  messageId: string;
  eventType: string;
  severity: "low" | "medium" | "high" | "critical";
  topicClass: string | null;
  actionTaken: string;
  leadershipRedirectShown: boolean;
  crisisSupportShown: boolean;
  createdAt: FirebaseFirestore.Timestamp;
}

// ── Discipleship ──────────────────────────────────────────────────────────────

export interface DiscipleshipProfile {
  topThemesStudied: string[];
  recentThemes: string[];
  growthSignals: string[];
  practiceCompletionStats: Record<string, number>;
  preferredStudyMode: "devotional" | "study" | "guided" | "mixed";
  churchConnected: boolean;
  hasPastorConnection: boolean;
  hasMentorConnection: boolean;
  discipleshipStageEstimate:
    | "new_believer"
    | "growing"
    | "established"
    | "leader"
    | "unknown";
  followUpsOptIn: boolean;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface PracticeRecommendation {
  id: string;
  userId: string;
  sourceThemeIds: string[];
  sourcePassageIds: string[];
  recommendationType:
    | "prayer"
    | "reflection"
    | "conversation"
    | "memory_verse"
    | "service"
    | "reconciliation"
    | "rest";
  title: string;
  body: string;
  status: "open" | "dismissed" | "completed";
  createdAt: FirebaseFirestore.Timestamp;
  completedAt: FirebaseFirestore.Timestamp | null;
}

export interface FollowUpPrompt {
  id: string;
  userId: string;
  sourceConversationId: string;
  sourceThemeIds: string[];
  sourcePassageIds: string[];
  promptType: "reflection" | "practice" | "leadership" | "memory_verse";
  title: string;
  body: string;
  scheduledFor: FirebaseFirestore.Timestamp;
  status: "pending" | "sent" | "completed" | "dismissed";
  createdAt: FirebaseFirestore.Timestamp;
}

export interface ReflectionEntry {
  id: string;
  userId: string;
  conversationId: string;
  passageIds: string[];
  themeIds: string[];
  title: string;
  text: string;
  privacyLevel: "private" | "shareable_with_leader";
  sourceType: "study" | "immersion" | "follow_up" | "manual";
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface LeadershipReferral {
  id: string;
  userId: string;
  sourceConversationId: string;
  sourceThemeIds: string[];
  sourcePassageIds: string[];
  type:
    | "pastor"
    | "mentor"
    | "small_group_leader"
    | "trusted_friend"
    | "doctor"
    | "therapist"
    | "legal_authority"
    | "emergency_services";
  status: "suggested" | "accepted" | "dismissed" | "completed";
  createdAt: FirebaseFirestore.Timestamp;
}

// ── LLM Output Contract ───────────────────────────────────────────────────────

export interface LLMStructuredOutput {
  answerText: string;
  scriptureReferences: string[];
  studyCards: StudyCard[];
  reflectionPrompts: string[];
  prayerPrompt: string | null;
  leadershipPrompt: LeadershipPrompt;
  sensitivitySummary: SensitivitySummary;
  suggestedNextActions: SuggestedAction[];
  confidenceNotes: ConfidenceNotes;
}
