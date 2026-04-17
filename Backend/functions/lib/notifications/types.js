"use strict";
/**
 * notifications/types.ts
 *
 * Core TypeScript interfaces, enums, and constants for AMEN's
 * server-side notification pipeline. Mirrors the Swift
 * AppNotification model and NotificationType enum exactly.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.NOTIFICATION_RETENTION_DAYS = exports.MAX_NOTIFICATIONS_PER_USER = exports.ACTOR_RATE_LIMIT_PER_HOUR = exports.MAX_INLINE_ACTORS = exports.GROUPING_WINDOW_MS = exports.LockScreenPrivacy = exports.RouteType = exports.PolicyResult = exports.NotificationType = exports.DEEP_LINK_VERSION = exports.SCHEMA_VERSION = void 0;
// ─── Schema Version ─────────────────────────────────────────────────
/** Current notification schema version. Existing docs without this field are v1. */
exports.SCHEMA_VERSION = "2";
/** Current deep link payload version. */
exports.DEEP_LINK_VERSION = "1";
// ─── Notification Types ─────────────────────────────────────────────
/**
 * Matches Swift's `AppNotification.NotificationType` raw values exactly.
 * Any additions here MUST be mirrored in the Swift enum.
 */
var NotificationType;
(function (NotificationType) {
    NotificationType["Follow"] = "follow";
    NotificationType["FollowRequestAccepted"] = "follow_request_accepted";
    NotificationType["Amen"] = "amen";
    NotificationType["Comment"] = "comment";
    NotificationType["Reply"] = "reply";
    NotificationType["Mention"] = "mention";
    NotificationType["Repost"] = "repost";
    NotificationType["Message"] = "message";
    NotificationType["MessageRequest"] = "message_request";
    NotificationType["MessageRequestAccepted"] = "message_request_accepted";
    NotificationType["PrayerReminder"] = "prayer_reminder";
    NotificationType["PrayerAnswered"] = "prayer_answered";
    NotificationType["PrayerSupported"] = "prayer_supported";
    NotificationType["ChurchNoteShared"] = "church_note_shared";
    NotificationType["ChurchNoteReplied"] = "church_note_replied";
    NotificationType["ActionThreadInvite"] = "action_thread_invite";
    NotificationType["ActionThreadUpdate"] = "action_thread_update";
    NotificationType["ActionThreadReminder"] = "action_thread_reminder";
})(NotificationType || (exports.NotificationType = NotificationType = {}));
// ─── Policy Result ──────────────────────────────────────────────────
var PolicyResult;
(function (PolicyResult) {
    /** Notification is allowed — write to inbox and send push. */
    PolicyResult["Allow"] = "allow";
    /** Notification is suppressed entirely — do not write. */
    PolicyResult["Suppress"] = "suppress";
    /** Write to inbox but downrank priority (no push). */
    PolicyResult["Downrank"] = "downrank";
    /** Bundle into digest instead of immediate delivery. */
    PolicyResult["Digest"] = "digest";
    /** Write to inbox only (no push, not downranked). */
    PolicyResult["InAppOnly"] = "in_app_only";
})(PolicyResult || (exports.PolicyResult = PolicyResult = {}));
// ─── Route Types ────────────────────────────────────────────────────
/** Matches Swift's NotificationRoute enum cases for deep link routing. */
var RouteType;
(function (RouteType) {
    RouteType["Post"] = "post";
    RouteType["PostComment"] = "post_comment";
    RouteType["PostReply"] = "post_reply";
    RouteType["MentionInComment"] = "mention_in_comment";
    RouteType["Profile"] = "profile";
    RouteType["Conversation"] = "conversation";
    RouteType["FollowRequests"] = "follow_requests";
    RouteType["Prayer"] = "prayer";
    RouteType["ChurchNote"] = "church_note";
    RouteType["NotificationsInbox"] = "notifications_inbox";
})(RouteType || (exports.RouteType = RouteType = {}));
// ─── Privacy Level ──────────────────────────────────────────────────
var LockScreenPrivacy;
(function (LockScreenPrivacy) {
    LockScreenPrivacy["Full"] = "full";
    LockScreenPrivacy["Minimal"] = "minimal";
    LockScreenPrivacy["NameOnly"] = "nameOnly";
})(LockScreenPrivacy || (exports.LockScreenPrivacy = LockScreenPrivacy = {}));
// ─── Grouping ───────────────────────────────────────────────────────
/** Aggregation window duration in milliseconds (2 hours). */
exports.GROUPING_WINDOW_MS = 2 * 60 * 60 * 1000;
/** Maximum number of actors stored inline in a grouped notification. */
exports.MAX_INLINE_ACTORS = 5;
// ─── Constants ──────────────────────────────────────────────────────
/** Spam rate-limit: max notifications from a single actor to a single recipient per hour. */
exports.ACTOR_RATE_LIMIT_PER_HOUR = 20;
/** Max notifications stored per user before archival. */
exports.MAX_NOTIFICATIONS_PER_USER = 500;
/** Notification retention period in days. */
exports.NOTIFICATION_RETENTION_DAYS = 90;
//# sourceMappingURL=types.js.map