// accessPassTypes.ts — Amen Access Pass type definitions

import * as admin from "firebase-admin";

export type AmenAccessTargetType =
  | "space"
  | "discussion"
  | "smallGroup"
  | "church"
  | "organization"
  | "event"
  | "sermonNotes"
  | "prayerRoom";

export type AmenAccessMode =
  | "preview"
  | "join"
  | "request"
  | "checkIn"
  | "roleGated";

export type AmenAccessPassStatus = "active" | "paused" | "revoked" | "expired";

export type AmenAccessAction =
  | "join"
  | "request"
  | "preview"
  | "checkIn"
  | "openSermonNotes"
  | "askForPrayer"
  | "meetLeader"
  | "followChurch";

export interface AmenAccessPass {
  accessPassId: string;

  tokenHash: string;
  tokenVersion: number;

  targetType: AmenAccessTargetType;
  targetId: string;

  orgId?: string;
  churchId?: string;
  spaceId?: string;

  createdByUid: string;
  createdByDisplayName?: string;

  mode: AmenAccessMode;
  status: AmenAccessPassStatus;

  title: string;
  subtitle?: string;
  description?: string;

  verifiedHostName?: string;
  verifiedHostType?: "church" | "organization" | "creator" | "smallGroup";
  verifiedHostBadge?: boolean;

  requiresAuth: boolean;
  requiresApproval: boolean;

  allowedEmailDomains?: string[];
  allowedRoleIds?: string[];
  allowedMemberUids?: string[];

  maxUses?: number;
  usesCount: number;
  maxUsesPerUser?: number;

  startsAt?: admin.firestore.Timestamp;
  expiresAt?: admin.firestore.Timestamp;

  checkInDurationMinutes?: number;

  safetyProfile: {
    isSensitive: boolean;
    requiresModeratorApproval: boolean;
    allowYouthAccess: boolean;
    allowGuestPreview: boolean;
    showMemberVisibilityWarning: boolean;
    showPrayerPrivacyWarning: boolean;
  };

  landingConfig: {
    headline: string;
    body: string;
    primaryActionLabel: string;
    secondaryActionLabel?: string;
    allowedActions: AmenAccessAction[];
  };

  audit: {
    createdAt: admin.firestore.Timestamp;
    updatedAt: admin.firestore.Timestamp;
    lastUsedAt?: admin.firestore.Timestamp;
    revokedAt?: admin.firestore.Timestamp;
    revokedByUid?: string;
    revokeReason?: string;
  };
}

export interface AccessPassEvent {
  eventId: string;
  type:
    | "created"
    | "resolved"
    | "previewed"
    | "joined"
    | "requested"
    | "checkedIn"
    | "denied"
    | "revoked"
    | "expired"
    | "rateLimited"
    | "abuseFlagged";
  uid?: string;
  anonymousSessionId?: string;
  accessPassId: string;
  targetType: string;
  targetId: string;
  reason?: string;
  devicePlatform?: "ios" | "web" | "android";
  appVersion?: string;
  createdAt: admin.firestore.Timestamp;
}

export interface AmenAccessRequest {
  requestId: string;
  accessPassId: string;
  targetType: AmenAccessTargetType;
  targetId: string;
  requesterUid: string;
  requesterDisplayName?: string;
  requesterPhotoURL?: string;
  orgId?: string;
  churchId?: string;
  spaceId?: string;
  status: "pending" | "approved" | "denied" | "cancelled" | "expired";
  requestMessage?: string;
  reviewedByUid?: string;
  reviewedAt?: admin.firestore.Timestamp;
  denialReason?: string;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
}

export interface AmenAccessCheckIn {
  checkInId: string;
  accessPassId: string;
  uid: string;
  targetType: AmenAccessTargetType;
  targetId: string;
  startedAt: admin.firestore.Timestamp;
  expiresAt: admin.firestore.Timestamp;
  status: "active" | "expired" | "revoked";
}

// Privacy-shaped preview returned to clients — tokenHash never included
export interface AccessPassPreviewResponse {
  accessPassId: string;
  targetType: AmenAccessTargetType;
  targetId: string;
  title: string;
  subtitle?: string;
  description?: string;
  verifiedHostName?: string;
  verifiedHostBadge: boolean;
  mode: AmenAccessMode;
  requiredAction: string;
  communityRulesSummary?: string;
  visibilityWarning?: string;
  privacyWarning?: string;
  allowedActions: AmenAccessAction[];
  requiresAuth: boolean;
  requiresApproval: boolean;
  alreadyMember: boolean;
  existingRequestPending: boolean;
}

// Admin listing response — tokenHash never included
export interface AccessPassAdminSummary
  extends Omit<AmenAccessPass, "tokenHash" | "tokenVersion"> {
  pendingRequestCount?: number;
}

// Sensitive target types that default to Request mode
export const SENSITIVE_TARGET_TYPES: AmenAccessTargetType[] = [
  "prayerRoom",
  "smallGroup",
];

// Target types that never allow direct Join without explicit admin override
export const RESTRICTED_DIRECT_JOIN_TYPES: AmenAccessTargetType[] = [
  "prayerRoom",
];
