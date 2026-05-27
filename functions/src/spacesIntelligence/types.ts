// types.ts
// AMEN Spaces Ambient Intelligence — TypeScript Types
//
// Extends ConversationOS types for the Spaces Intelligence layer.
// All AI-generated fields are server-written only — never trust client-supplied confidence/provenance.

// MARK: - Space Types

export type AmenSpaceType =
  | "church_ministry" | "prayer_group" | "sermon_prep" | "bible_study"
  | "school_classroom" | "leadership_room" | "operations_hub"
  | "creator_community" | "family_group" | "discipleship_cohort"
  | "event_workspace" | "support_community";

export const AI_INFERENCE_BLOCKED_TYPES: AmenSpaceType[] = ["support_community"];
export const SUMMARY_OPT_IN_REQUIRED: AmenSpaceType[] = ["prayer_group", "leadership_room"];
export const EMOTIONAL_CONTEXT_BLOCKED: AmenSpaceType[] = ["family_group", "support_community"];

export function aiInferenceAllowed(spaceType: AmenSpaceType): boolean {
  return !AI_INFERENCE_BLOCKED_TYPES.includes(spaceType);
}

// MARK: - Memory Graph

export type MemoryLayer =
  | "user" | "relationship" | "group" | "spiritual" | "organizational" | "temporal";

export interface MemoryNode {
  id: string;
  spaceId: string;
  userId?: string;
  layer: MemoryLayer;
  title: string;
  body: string;
  tags: string[];
  scriptureRefs: string[];
  relatedNodeIds: string[];
  confidence: number;
  generatedAt: FirebaseFirestore.Timestamp;
  expiresAt?: FirebaseFirestore.Timestamp;
  dismissed: boolean;
  // Server-written provenance — client cannot set this field
  provenance: string;
}

// MARK: - Semantic Pin

export type PinType =
  | "prayer" | "scripture" | "reflection" | "testimony"
  | "task" | "announcement" | "meeting" | "decision"
  | "highly_referenced" | "emotionally_important" | "unresolved" | "requires_follow_up"
  | "momentum_building" | "fading_urgency" | "resolved";

export const SERVER_PIN_TYPES: PinType[] = [
  "highly_referenced", "emotionally_important", "unresolved",
  "requires_follow_up", "momentum_building", "fading_urgency", "resolved"
];

export interface SemanticPin {
  id: string;
  spaceId: string;
  threadId?: string;
  messageId?: string;
  pinnedBy: string;
  pinType: PinType;
  title: string;
  preview: string;
  tags: string[];
  scriptureRef?: string;
  score: number;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  evolutionHistory: PinEvolutionEvent[];
}

export interface PinEvolutionEvent {
  fromType: PinType;
  toType: PinType;
  reason: string;
  occurredAt: FirebaseFirestore.Timestamp;
}

// MARK: - Ambient Signal

export type AmbientSignalType =
  | "prayer_request_updated" | "related_to_sermon" | "converging_theme"
  | "unresolved_follow_up" | "participation_drop" | "bible_study_link"
  | "leadership_action_needed" | "spiritual_theme_recurring";

export interface AmbientSignal {
  id: string;
  spaceId: string;
  signalType: AmbientSignalType;
  title: string;
  body: string;
  confidence: number;
  relevantToUserId?: string;
  threadId?: string;
  createdAt: FirebaseFirestore.Timestamp;
  dismissed: boolean;
  // Server-written only
  provenance: string;
  moderationPassed: boolean;
}

// MARK: - Catch-Up Intelligence

export interface CatchUpIntelligence {
  id: string;
  spaceId: string;
  userId: string;
  generatedAt: FirebaseFirestore.Timestamp;
  coverageWindowStart: FirebaseFirestore.Timestamp;
  coverageWindowEnd: FirebaseFirestore.Timestamp;
  emotionalLayer?: EmotionalLayer;
  organizationalLayer?: OrgLayer;
  spiritualLayer?: SpiritualLayer;
  personalLayer?: PersonalLayer;
  confidence: number;
  dismissed: boolean;
  provenance: string;
}

export interface EmotionalLayer {
  urgencyLevel: string;
  prayerIntensity: string;
  encouragementHighlights: string[];
  tensionIndicators: string[];
}

export interface OrgLayer {
  decisions: string[];
  blockers: string[];
  deadlines: string[];
  unresolvedItems: number;
}

export interface SpiritualLayer {
  scriptureThemes: string[];
  theologicalDevelopments: string[];
  prayerOutcomes: string[];
  recurringVerses: string[];
}

export interface PersonalLayer {
  mentionsForUser: string[];
  closePeopleUpdates: string[];
  unresolvedResponses: string[];
}

// MARK: - Spiritual Continuity

export interface SpiritualContinuityRecord {
  id: string;
  userId: string;
  spaceId?: string;
  theme: string;
  scriptureJourney: string[];
  recurringPrayerTopics: string[];
  unfinishedReflections: string[];
  selahMoments: number;
  discipleshipContinuityScore: number;
  lastActivityAt: FirebaseFirestore.Timestamp;
  generatedAt: FirebaseFirestore.Timestamp;
  provenance: string;
}
