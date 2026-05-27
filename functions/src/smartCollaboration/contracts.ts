// contracts.ts
// AMEN Smart Collaboration Layer — TypeScript contracts
//
// Mirrors the Swift types in AmenSmartCollaborationContracts.swift.
// Single source of truth for all Cloud Function request/response shapes
// and Firestore sub-collection paths.
//
// Non-negotiable rules:
//   1. generatedBy is always a service account ID — never the caller's uid.
//   2. requestorId on ThreadPrayerSignal is NEVER returned to non-requestors.
//   3. All AI text fields are written server-side only — never from client payloads.
//   4. No raw message body text in any logged or analytics field.

import type { firestore as FirebaseFirestore } from "firebase-admin";

// MARK: - Thread Type

export type SmartThreadType = "dm" | "channel" | "discussion";

// MARK: - ThreadSmartContext
// Stored at: conversations/{id}/smartContext/main
//            spaces/{spaceId}/channels/{channelId}/smartContext/main

export interface ThreadSmartContext {
  id: string;
  threadId: string;
  threadType: SmartThreadType;
  /** Service account ID — never the caller uid. */
  generatedBy: string;
  generatedAt: FirebaseFirestore.Timestamp;
  modelVersion: string;
  /** AI-generated summary text. Written server-side only. */
  summaryText: string;
  keyThemes: string[];
  participantCount: number;
  messageCount: number;
  /** Citation anchor — last source messageId used for generation. */
  lastSourceMessageId: string;
  /** True when new messages arrived since last generation pass. */
  isStale: boolean;
}

// MARK: - ThreadDetectedAction
// Stored at: conversations/{id}/smartActions/{actionId}
//            spaces/{spaceId}/channels/{channelId}/smartActions/{actionId}

export interface ThreadDetectedAction {
  id: string;
  threadId: string;
  actionType: "followUp" | "decision" | "commitment" | "openQuestion" | "reminder";
  /** Always framed as "possible: …" — use labelAsSuggested() from safety.ts */
  suggestedText: string;
  /** Never forced — always optional. */
  assigneeSuggestion?: string;
  /** Always optional. Never treat as a hard deadline. */
  dueDateSuggestion?: FirebaseFirestore.Timestamp;
  /** Citation anchor — which message triggered this action detection. */
  sourceMessageId: string;
  /** Confidence score 0.0–1.0. Values below 0.5 should not be auto-surfaced. */
  confidence: number;
  status: "suggested" | "accepted" | "dismissed" | "completed";
  /** Service account ID. Never a user UID. */
  generatedBy: string;
  generatedAt: FirebaseFirestore.Timestamp;
  modelVersion: string;
}

// MARK: - ThreadPrayerSignal
// Stored at: conversations/{id}/prayerSignals/{signalId}
//            spaces/{spaceId}/channels/{channelId}/prayerSignals/{signalId}
//
// Privacy contract:
//   - requestorId NEVER returned to non-requestors in any callable response.
//   - prayerTheme is a category label only — never raw prayer text.
//   - Auto-amplification requires explicit opt-in (see requiresExplicitOptIn).

export interface ThreadPrayerSignal {
  id: string;
  threadId: string;
  /** NEVER exposed to non-requestors. Strip before any public/group response. */
  requestorId: string;
  /** Category label only: e.g. "health", "family" — never raw prayer text. */
  prayerTheme: string;
  isAnonymous: boolean;
  sourceMessageId: string;
  moderationStatus: "pending" | "approved" | "rejected" | "escalated";
  /** Service account ID. Never a user UID. */
  generatedBy: string;
  generatedAt: FirebaseFirestore.Timestamp;
  modelVersion: string;
}

// MARK: - ThreadSummary
// Stored at: conversations/{id}/summary/main
//            spaces/{spaceId}/channels/{channelId}/summary/main

export interface ThreadSummary {
  id: string;
  threadId: string;
  /** AI-generated summary text. Written server-side only. */
  summaryText: string;
  bulletPoints: string[];
  messageRangeStart: FirebaseFirestore.Timestamp;
  messageRangeEnd: FirebaseFirestore.Timestamp;
  /** Evidence citations — messageIds used to produce this summary. */
  sourceMessageIds: string[];
  /** Service account ID. Never a user UID. */
  generatedBy: string;
  generatedAt: FirebaseFirestore.Timestamp;
  modelVersion: string;
  isStale: boolean;
}

// MARK: - ThreadPresenceSnapshot
// Stored at: conversations/{id}/presence/{userId}
//            spaces/{spaceId}/channels/{channelId}/presence/{userId}
//
// Security rule: self-write only.
// States are approximate — max 30-minute TTL enforced by expiresAt.

export interface ThreadPresenceSnapshot {
  userId: string;
  state: "activeNow" | "recentlyActive" | "mayReplyLater" | "focus" | "quiet";
  updatedAt: FirebaseFirestore.Timestamp;
  /** Approximate states expire — maximum 30 minutes from updatedAt. */
  expiresAt: FirebaseFirestore.Timestamp;
}

// MARK: - GroupPulse
// Stored at: spaces/{spaceId}/channels/{channelId}/pulse/main

export interface GroupPulse {
  id: string;
  channelId: string;
  urgency: "normal" | "elevated" | "urgent";
  activeParticipantCount: number;
  /** Topic momentum 0.0–1.0. Server-computed. */
  topicMomentum: number;
  /** undefined unless strong evidence exists. Never inferred or assumed. */
  isAligned?: boolean;
  alignmentEvidenceMessageIds: string[];
  /** Service account ID. Never a user UID. */
  generatedBy: string;
  generatedAt: FirebaseFirestore.Timestamp;
  modelVersion: string;
  isStale: boolean;
}

// MARK: - Firestore Path Helpers
// Mirrors Swift AmenSmartCollaborationPaths — single source of truth.

export const SmartPaths = {
  // DM thread sub-collections
  dmSmartContext: (conversationId: string) =>
    `conversations/${conversationId}/smartContext/main`,
  dmSmartActions: (conversationId: string) =>
    `conversations/${conversationId}/smartActions`,
  dmPrayerSignals: (conversationId: string) =>
    `conversations/${conversationId}/prayerSignals`,
  dmSummary: (conversationId: string) =>
    `conversations/${conversationId}/summary/main`,
  dmPresence: (conversationId: string, userId: string) =>
    `conversations/${conversationId}/presence/${userId}`,

  // Channel sub-collections
  channelSmartContext: (spaceId: string, channelId: string) =>
    `spaces/${spaceId}/channels/${channelId}/smartContext/main`,
  channelSmartActions: (spaceId: string, channelId: string) =>
    `spaces/${spaceId}/channels/${channelId}/smartActions`,
  channelPrayerSignals: (spaceId: string, channelId: string) =>
    `spaces/${spaceId}/channels/${channelId}/prayerSignals`,
  channelSummary: (spaceId: string, channelId: string) =>
    `spaces/${spaceId}/channels/${channelId}/summary/main`,
  channelPresence: (spaceId: string, channelId: string, userId: string) =>
    `spaces/${spaceId}/channels/${channelId}/presence/${userId}`,
  channelPulse: (spaceId: string, channelId: string) =>
    `spaces/${spaceId}/channels/${channelId}/pulse/main`,
} as const;

// MARK: - Callable Request / Response Shapes

export interface SmartCallableRequest {
  threadId: string;
  threadType: SmartThreadType;
  /** Required when threadType === 'channel'. */
  spaceId?: string;
  /** Required when threadType === 'channel'. */
  channelId?: string;
}

export interface SmartCallableResponse {
  success: boolean;
  /** Async jobs return a jobId for status polling. */
  jobId?: string;
  error?: string;
}
