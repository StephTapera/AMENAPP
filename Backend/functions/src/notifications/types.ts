/**
 * notifications/types.ts
 *
 * Core TypeScript interfaces, enums, and constants for AMEN's
 * server-side notification pipeline. Mirrors the Swift
 * AppNotification model and NotificationType enum exactly.
 */

// ─── Schema Version ─────────────────────────────────────────────────

/** Current notification schema version. Existing docs without this field are v1. */
export const SCHEMA_VERSION = "2";

/** Current deep link payload version. */
export const DEEP_LINK_VERSION = "1";

// ─── Notification Types ─────────────────────────────────────────────

/**
 * Matches Swift's `AppNotification.NotificationType` raw values exactly.
 * Any additions here MUST be mirrored in the Swift enum.
 */
export enum NotificationType {
    Follow = "follow",
    FollowRequestAccepted = "follow_request_accepted",
    Amen = "amen",
    Comment = "comment",
    Reply = "reply",
    Mention = "mention",
    Repost = "repost",
    Message = "message",
    MessageRequest = "message_request",
    MessageRequestAccepted = "message_request_accepted",
    PrayerReminder = "prayer_reminder",
    PrayerAnswered = "prayer_answered",
    PrayerSupported = "prayer_supported",
    ChurchNoteShared = "church_note_shared",
    ChurchNoteReplied = "church_note_replied",
    ActionThreadInvite = "action_thread_invite",
    ActionThreadUpdate = "action_thread_update",
    ActionThreadReminder = "action_thread_reminder",
}

// ─── Policy Result ──────────────────────────────────────────────────

export enum PolicyResult {
    /** Notification is allowed — write to inbox and send push. */
    Allow = "allow",
    /** Notification is suppressed entirely — do not write. */
    Suppress = "suppress",
    /** Write to inbox but downrank priority (no push). */
    Downrank = "downrank",
    /** Bundle into digest instead of immediate delivery. */
    Digest = "digest",
    /** Write to inbox only (no push, not downranked). */
    InAppOnly = "in_app_only",
}

// ─── Route Types ────────────────────────────────────────────────────

/** Matches Swift's NotificationRoute enum cases for deep link routing. */
export enum RouteType {
    Post = "post",
    PostComment = "post_comment",
    PostReply = "post_reply",
    MentionInComment = "mention_in_comment",
    Profile = "profile",
    Conversation = "conversation",
    FollowRequests = "follow_requests",
    Prayer = "prayer",
    ChurchNote = "church_note",
    NotificationsInbox = "notifications_inbox",
}

// ─── Notification Actor ─────────────────────────────────────────────

/** A single actor in a grouped notification. Matches Swift's NotificationActor. */
export interface NotificationActor {
    id: string;
    name: string;
    username: string;
    profileImageURL: string | null;
}

// ─── Route Payload ──────────────────────────────────────────────────

export interface RoutePayload {
    postId?: string;
    commentId?: string;
    parentCommentId?: string;
    replyId?: string;
    userId?: string;
    conversationId?: string;
    prayerId?: string;
    noteId?: string;
    highlightMode?: string;
    scrollAnchorId?: string;
}

// ─── Notification Document ──────────────────────────────────────────

/**
 * Full Firestore document shape for `users/{uid}/notifications/{id}`.
 * Backward-compatible with existing v1 documents — all new fields are optional.
 */
export interface NotificationDocument {
    // Core identity
    userId: string;
    type: string; // NotificationType raw value
    idempotencyKey: string;
    schemaVersion: string;

    // Actor info (primary actor for non-grouped, or latest actor for grouped)
    actorId: string | null;
    actorName: string | null;
    actorUsername: string | null;
    actorProfileImageURL: string | null;

    // Target entity IDs
    postId: string | null;
    commentId: string | null;
    parentCommentId: string | null;
    conversationId: string | null;
    prayerId: string | null;
    noteId: string | null;
    commentText: string | null;

    // Grouping (Threads-style multi-actor)
    groupId: string | null;
    actors: NotificationActor[] | null;
    actorCount: number | null;

    // State machine
    read: boolean;
    seenAt: FirebaseFirestore.Timestamp | null;
    openedAt: FirebaseFirestore.Timestamp | null;
    dismissedAt: FirebaseFirestore.Timestamp | null;

    // Routing
    targetRouteType: string | null;
    routePayload: RoutePayload | null;
    fallbackRouteType: string | null;
    fallbackRoutePayload: RoutePayload | null;
    deepLinkVersion: string;

    // Smart notification metadata
    priority: number | null; // 0-100
    invalidTarget: boolean;

    // Push delivery tracking
    pushDelivered: boolean;
    pushDeliveredAt: FirebaseFirestore.Timestamp | null;

    // Timestamps
    createdAt: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
    updatedAt: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue | null;
}

// ─── Notification Candidate ─────────────────────────────────────────

/**
 * Pre-policy-evaluation candidate. Built from the raw Firestore event,
 * before any filtering, grouping, or delivery decisions.
 */
export interface NotificationCandidate {
    recipientId: string;
    type: NotificationType;
    actorId: string;
    actorName: string;
    actorUsername: string;
    actorProfileImageURL: string | null;

    // Target references
    postId: string | null;
    commentId: string | null;
    parentCommentId: string | null;
    conversationId: string | null;
    prayerId: string | null;
    noteId: string | null;
    commentText: string | null;

    // Pre-computed routing
    targetRouteType: RouteType;
    routePayload: RoutePayload;
    fallbackRouteType: RouteType;
    fallbackRoutePayload: RoutePayload;
}

// ─── Push Payload ───────────────────────────────────────────────────

/** FCM message payload matching APNs requirements. */
export interface PushPayload {
    notification: {
        title: string;
        body: string;
    };
    data: {
        type: string;
        notificationId: string;
        targetRouteType: string;
        routePayload: string; // JSON-encoded RoutePayload
        fallbackRouteType: string;
        fallbackRoutePayload: string; // JSON-encoded RoutePayload
        collapseKey: string;
        schemaVersion: string;
        deepLinkVersion: string;
    };
    apns: {
        payload: {
            aps: {
                badge: number;
                sound: string;
                "mutable-content": number;
                "thread-id": string;
                category: string;
            };
        };
    };
}

// ─── Privacy Level ──────────────────────────────────────────────────

export enum LockScreenPrivacy {
    Full = "full",
    Minimal = "minimal",
    NameOnly = "nameOnly",
}

// ─── Notification Preferences ───────────────────────────────────────

export interface NotificationPreferences {
    mode: "meaningful" | "balanced" | "everything";
    lockScreenPrivacy: LockScreenPrivacy;
    quietHoursEnabled: boolean;
    quietHoursStart: string | null; // "22:00"
    quietHoursEnd: string | null;   // "07:00"
    quietHoursTimezone: string | null; // IANA timezone string, e.g. "America/Chicago"
    sundayModeEnabled: boolean;
    categories: Record<string, CategoryPreference>;
}

export interface CategoryPreference {
    enabled: boolean;
    pushEnabled: boolean;
    soundEnabled: boolean;
    badgeEnabled: boolean;
}

// ─── Grouping ───────────────────────────────────────────────────────

/** Aggregation window duration in milliseconds (2 hours). */
export const GROUPING_WINDOW_MS = 2 * 60 * 60 * 1000;

/** Maximum number of actors stored inline in a grouped notification. */
export const MAX_INLINE_ACTORS = 5;

// ─── Constants ──────────────────────────────────────────────────────

/** Spam rate-limit: max notifications from a single actor to a single recipient per hour. */
export const ACTOR_RATE_LIMIT_PER_HOUR = 20;

/** Max notifications stored per user before archival. */
export const MAX_NOTIFICATIONS_PER_USER = 500;

/** Notification retention period in days. */
export const NOTIFICATION_RETENTION_DAYS = 90;
