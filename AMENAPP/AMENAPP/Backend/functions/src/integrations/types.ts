// integrations/types.ts
// AMEN Integrations Platform — TypeScript type contracts
// Privacy: encrypted tokens NEVER in main account documents
// Security: all callables require App Check (enforced by Firebase config) + Auth

import * as admin from "firebase-admin";

export type AmenIntegrationProvider = "microsoft" | "zoom" | "slack";

export type AmenIntegrationStatus =
  | "connected"
  | "expired"
  | "revoked"
  | "error"
  | "pending";

// Firestore: integrationAccounts/{uid}_{provider}
export interface AmenIntegrationAccount {
  accountId: string;
  uid: string;
  provider: AmenIntegrationProvider;
  status: AmenIntegrationStatus;
  isOrgLevel: boolean;
  organizationId?: string;
  connectedAt: admin.firestore.Timestamp;
  expiresAt?: admin.firestore.Timestamp;
  providerMetadata: AmenIntegrationProviderMetadata;
  scopes: string[];
  audit: {
    createdAt: admin.firestore.Timestamp;
    updatedAt: admin.firestore.Timestamp;
  };
}

export interface AmenIntegrationProviderMetadata {
  displayName?: string;
  email?: string;
  tenantId?: string;
  microsoftUserId?: string;
  zoomUserId?: string;
  zoomAccountId?: string;
  workspaceName?: string;
  workspaceId?: string;
  workspaceUrl?: string;
  slackUserId?: string;
  botUserId?: string;
}

// Firestore: integrationTokens/{accountId}
// NEVER returned to client. Written by backend only.
export interface AmenIntegrationTokenRecord {
  accountId: string;
  uid: string;
  provider: AmenIntegrationProvider;
  encryptedAccessToken: string;
  encryptedRefreshToken?: string;
  tokenType: string;
  expiresAt: admin.firestore.Timestamp;
  scopes: string[];
  updatedAt: admin.firestore.Timestamp;
}

// Firestore: oauthStates/{stateToken}
// TTL: 10 minutes. One-time use.
export interface AmenOAuthState {
  stateToken: string;
  uid: string;
  provider: AmenIntegrationProvider;
  redirectUri: string;
  codeVerifier?: string;
  createdAt: admin.firestore.Timestamp;
  expiresAt: admin.firestore.Timestamp;
  consumed: boolean;
}

// Firestore: gatheringMeetingLinks/{gatheringId}
export interface AmenGatheringMeetingLink {
  gatheringId: string;
  provider: AmenIntegrationProvider | "manual";
  providerMeetingId?: string;
  joinUrl: string;
  startAt: admin.firestore.Timestamp;
  endAt?: admin.firestore.Timestamp;
  createdByUid: string;
  idempotencyKey: string;
  status: "active" | "cancelled";
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

// Firestore: gatheringReminders/{reminderId}
export interface AmenGatheringReminder {
  reminderId: string;
  gatheringId: string;
  scheduledFor: admin.firestore.Timestamp;
  sentAt?: admin.firestore.Timestamp;
  recipientUids: string[];
  status: "pending" | "sent" | "failed";
  createdByUid: string;
  createdAt: admin.firestore.Timestamp;
}

// Firestore: gatheringFollowUps/{gatheringId}
export interface AmenGatheringFollowUp {
  gatheringId: string;
  status: "pending" | "completed" | "dismissed";
  hostUid: string;
  scripture?: string;
  actionItems?: string[];
  prayerPoints?: string[];
  sharedToSpaceId?: string;
  completedAt?: admin.firestore.Timestamp;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

// AI Suggestion types
export interface AmenGatheringTitleSuggestion {
  title: string;
  rationale?: string;
}

export interface AmenGatheringAgendaItem {
  durationMinutes: number;
  activity: string;
  scriptureReference?: string;
}

export interface AmenGatheringScriptureSuggestion {
  reference: string;
  theme: string;
  preview: string;
}

// Firestore: integrationAuditLogs/{logId}
export interface AmenIntegrationAuditLog {
  logId: string;
  uid: string;
  provider?: AmenIntegrationProvider;
  action: AmenIntegrationAuditAction;
  metadata?: Record<string, string | number | boolean>;
  timestamp: admin.firestore.Timestamp;
}

export type AmenIntegrationAuditAction =
  | "oauth_started"
  | "oauth_completed"
  | "oauth_failed"
  | "token_refreshed"
  | "token_refresh_failed"
  | "connection_revoked"
  | "meeting_link_created"
  | "meeting_link_failed"
  | "reminder_sent"
  | "reminder_failed"
  | "follow_up_completed"
  | "slack_notification_sent"
  | "slack_notification_failed";

// Provider meeting creation input/output
export interface CreateMeetingInput {
  gatheringId: string;
  title: string;
  startAtMs: number;
  endAtMs?: number;
  timezone?: string;
  isRecurring?: boolean;
  recurrenceRule?: string;
  waitingRoom?: boolean;
  passcode?: string;
}

export interface CreateMeetingOutput {
  providerMeetingId: string;
  joinUrl: string;
  hostUrl?: string; // Only returned internally, never to client
  startAt: Date;
  endAt?: Date;
}

// Slack notification input
export interface SlackNotificationInput {
  channelId: string;
  text: string;
  metadata?: Record<string, string>;
}
