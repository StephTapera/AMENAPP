// types.ts
// AMEN Conversation OS — Shared TypeScript Types
//
// All Conversation OS backend engines share these types.
// Never send raw full message history to models — always compress first.

import type { firestore } from "firebase-admin";

// MARK: - Surface & Org

export type ConversationOSSurface =
  | "amen_spaces" | "direct_messages" | "group_messages"
  | "church_discussion" | "prayer_room" | "berean_study"
  | "event_chat" | "leadership_room" | "creator_community"
  | "classroom_discussion" | "media_comments" | "org_hub" | "admin_channel";

export type OrgType =
  | "church" | "school" | "business" | "enterprise" | "ministry"
  | "creator_community" | "prayer_group" | "study_group"
  | "leadership_team" | "event" | "operational_team";

export type UserRole =
  | "teacher" | "student" | "church_leader" | "volunteer"
  | "business_manager" | "creator" | "moderator" | "admin" | "group_member";

export const SENSITIVE_SURFACES: ConversationOSSurface[] = [
  "prayer_room", "leadership_room", "admin_channel"
];

export function isSensitiveSurface(s: ConversationOSSurface): boolean {
  return SENSITIVE_SURFACES.includes(s);
}

// MARK: - Semantic Tags

export type SemanticTag =
  | "decision" | "question" | "announcement" | "task"
  | "prayer_request" | "teaching_moment" | "blocker"
  | "reminder" | "conflict" | "escalation" | "encouragement" | "consensus";

export type SummaryType =
  | "catch_up" | "decision" | "operational" | "educational"
  | "reflection" | "community" | "unresolved" | "weekly_memory" | "prayer_digest";

export type ActionStatus = "pending" | "in_progress" | "resolved" | "dismissed";
export type DecisionStatus = "proposed" | "confirmed" | "challenged" | "outdated";
export type Urgency = "low" | "medium" | "high" | "critical";
export type SummaryLength = "brief" | "balanced" | "deep";

// MARK: - Raw Message (from Firestore — never sent raw to LLM)

export interface RawMessage {
  id: string;
  senderId: string;
  senderDisplayName: string;
  text: string;
  timestamp: firestore.Timestamp;
  threadId: string;
  reactionCount: number;
  replyCount: number;
  tags?: SemanticTag[];
  isEdited?: boolean;
}

// MARK: - Conversation Context

export interface ConversationContext {
  spaceId: string;
  threadId?: string;
  surface: ConversationOSSurface;
  orgType: OrgType;
  userRole: UserRole;
  orgId?: string;
  isSensitive: boolean;
  participantCount: number;
  messageCount: number;
  windowStart: Date;
  windowEnd: Date;
}

// MARK: - Compressed Chunk (retrieve → rank → compress → summarize)

export interface CompressedChunk {
  id: string;
  summary: string;
  messageIds: string[];
  tags: SemanticTag[];
  timeRange: { start: Date; end: Date };
  tokenCount: number;
  participantDisplayNames: string[];
  sentiment: "positive" | "neutral" | "negative" | "urgent";
}

// MARK: - Topic Cluster

export interface TopicCluster {
  id: string;
  title: string;
  summary: string;
  tags: SemanticTag[];
  messageCount: number;
  participantCount: number;
  confidence: number;
  messageRefs: Array<{ id: string; preview: string; timestamp: Date; senderDisplayName: string }>;
  createdAt: Date;
  updatedAt: Date;
}

// MARK: - Action Items & Decisions

export interface ActionItem {
  id: string;
  title: string;
  description: string;
  assigneeId?: string;
  assigneeDisplayName?: string;
  dueDate?: Date;
  sourceMessageId: string;
  threadId: string;
  status: ActionStatus;
  confidence: number;
  createdAt: Date;
}

export interface Decision {
  id: string;
  summary: string;
  sourceSnippet: string;
  participants: string[];
  confirmedBy: string[];
  status: DecisionStatus;
  threadId: string;
  confidence: number;
  createdAt: Date;
}

export interface UnresolvedQuestion {
  id: string;
  question: string;
  sourceSnippet: string;
  askedByDisplayName: string;
  threadId: string;
  askedAt: Date;
}

export interface Blocker {
  id: string;
  description: string;
  sourceSnippet: string;
  threadId: string;
  confidence: number;
  detectedAt: Date;
}

// MARK: - Summary Provenance (required on every generated doc)

export interface SummaryProvenance {
  provider: string;
  modelVersion: string;
  generatedAt: Date;
  compressionRatio: number;
  moderationPassed: boolean;
  permissionsValidated: boolean;
  inputTokens: number;
  outputTokens: number;
}

// MARK: - Conversation Summary

export interface ConversationSummary {
  id: string;
  spaceId: string;
  threadId?: string;
  surface: ConversationOSSurface;
  summaryText: string;
  summaryType: SummaryType;
  topicClusters: TopicCluster[];
  decisions: Decision[];
  actionItems: ActionItem[];
  unresolvedQuestions: UnresolvedQuestion[];
  blockers: Blocker[];
  generatedAt: Date;
  coverageWindowStart: Date;
  coverageWindowEnd: Date;
  messageCount: number;
  confidence: number;
  provenance: SummaryProvenance;
}

// MARK: - Organizational Memory

export interface OrganizationalMemory {
  id: string;
  orgId: string;
  weekLabel: string;
  recurringTopics: string[];
  keyDecisions: Decision[];
  unresolvedItems: UnresolvedQuestion[];
  collaborationPatterns: string[];
  summaryText: string;
  generatedAt: Date;
  provenance: SummaryProvenance;
}

// MARK: - Priority Signal

export interface PrioritySignal {
  id: string;
  type: "mention" | "unresolved_question" | "pending_decision" | "blocker"
      | "urgent_thread" | "consensus_forming" | "action_required";
  title: string;
  description: string;
  urgency: Urgency;
  threadId: string;
  spaceId: string;
  relevantToRoles: UserRole[];
  score: number;
  createdAt: Date;
}

// MARK: - Permissions Context

export interface PermissionsContext {
  userId: string;
  spaceId?: string;
  roomId?: string;
  orgId?: string;
  surface: ConversationOSSurface;
  requestedAction:
    | "summarize" | "cluster" | "extract_actions"
    | "memory_query" | "personalize" | "read_insights";
}

// MARK: - Moderation Result

export interface ModerationResult {
  passed: boolean;
  flaggedCategories: string[];
  confidence: number;
  requiresReview: boolean;
  crisisDetected: boolean;
}

// MARK: - Personalized Summary Request

export interface PersonalizedSummaryRequest {
  userId: string;
  spaceId: string;
  surface: ConversationOSSurface;
  userRole: UserRole;
  orgType: OrgType;
  unreadCount: number;
  lastVisitedAt?: Date;
  followedTopics: string[];
  preferredLength: SummaryLength;
}

// MARK: - Ingestion Event

export type IngestionEventType =
  | "new_message" | "reply" | "reaction" | "edit" | "media"
  | "file" | "link" | "poll" | "task" | "mention"
  | "prayer_request" | "study_prompt" | "event";

export interface IngestionEvent {
  eventId: string;
  spaceId: string;
  threadId: string;
  eventType: IngestionEventType;
  senderId: string;
  timestamp: Date;
  textPreview?: string;
}

// MARK: - LLM Budget

export interface LLMBudget {
  maxInputTokens: number;
  maxOutputTokens: number;
  timeoutMs: number;
  provider: "openai" | "claude" | "gemini";
  model: string;
}

export const DEFAULT_SUMMARY_BUDGET: LLMBudget = {
  maxInputTokens: 4096,
  maxOutputTokens: 512,
  timeoutMs: 15000,
  provider: "openai",
  model: "gpt-4o-mini",
};

export const DEEP_SUMMARY_BUDGET: LLMBudget = {
  maxInputTokens: 8192,
  maxOutputTokens: 1024,
  timeoutMs: 25000,
  provider: "claude",
  model: "claude-opus-4-5-20251101",
};
