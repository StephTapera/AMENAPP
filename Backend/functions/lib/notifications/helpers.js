"use strict";
/**
 * notifications/helpers.ts
 *
 * Shared utility functions for the notification pipeline.
 * Block/mute checks, device token retrieval, preference loading,
 * idempotency key generation, and grouping key generation.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.isBlocked = isBlocked;
exports.isMuted = isMuted;
exports.isFollowing = isFollowing;
exports.getDeviceTokens = getDeviceTokens;
exports.markTokenInvalid = markTokenInvalid;
exports.getUserPreferences = getUserPreferences;
exports.isCategoryPushEnabled = isCategoryPushEnabled;
exports.isPostVisible = isPostVisible;
exports.isCommentVisible = isCommentVisible;
exports.isUserActive = isUserActive;
exports.isPrivateAccount = isPrivateAccount;
exports.getActorInfo = getActorInfo;
exports.buildIdempotencyKey = buildIdempotencyKey;
exports.buildGroupingKey = buildGroupingKey;
exports.buildRoutes = buildRoutes;
exports.buildPushText = buildPushText;
exports.getCategoryForType = getCategoryForType;
const admin = __importStar(require("firebase-admin"));
const types_1 = require("./types");
const db = admin.firestore();
// ─── Block Check ────────────────────────────────────────────────────
/**
 * Returns true if either user has blocked the other.
 * Checks both directions for bidirectional block enforcement.
 */
async function isBlocked(userId, targetId) {
    const [blockA, blockB] = await Promise.all([
        db
            .collection("users")
            .doc(userId)
            .collection("blockedUsers")
            .doc(targetId)
            .get(),
        db
            .collection("users")
            .doc(targetId)
            .collection("blockedUsers")
            .doc(userId)
            .get(),
    ]);
    return blockA.exists || blockB.exists;
}
// ─── Mute Check ─────────────────────────────────────────────────────
/**
 * Returns true if the recipient has muted the actor.
 * Mute = suppress push, still write in-app at lower priority.
 */
async function isMuted(recipientId, actorId) {
    const muteDoc = await db
        .collection("users")
        .doc(recipientId)
        .collection("mutedUsers")
        .doc(actorId)
        .get();
    return muteDoc.exists;
}
// ─── Follow Relationship ────────────────────────────────────────────
/**
 * Returns true if followerId follows followedId.
 * Used for private account visibility checks.
 */
async function isFollowing(followerId, followedId) {
    // Follow docs use composite ID pattern: followerId_followedId
    const followDoc = await db
        .collection("follows")
        .doc(`${followerId}_${followedId}`)
        .get();
    if (followDoc.exists)
        return true;
    // Fallback: query by fields in case doc ID pattern differs
    const snapshot = await db
        .collection("follows")
        .where("followerId", "==", followerId)
        .where("followedId", "==", followedId)
        .limit(1)
        .get();
    return !snapshot.empty;
}
/**
 * Fetches all active device tokens for a user.
 * Returns only enabled tokens with non-empty values.
 */
async function getDeviceTokens(userId) {
    const snapshot = await db
        .collection("users")
        .doc(userId)
        .collection("deviceTokens")
        .where("enabled", "==", true)
        .get();
    const tokens = [];
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const token = data.token || doc.id;
        if (token && typeof token === "string" && token.length > 0) {
            tokens.push({
                token,
                platform: data.platform || "ios",
                enabled: true,
            });
        }
    }
    // Also check the legacy top-level fcmToken field
    const userDoc = await db.collection("users").doc(userId).get();
    const legacyToken = userDoc.data()?.fcmToken;
    if (legacyToken &&
        typeof legacyToken === "string" &&
        !tokens.some((t) => t.token === legacyToken)) {
        tokens.push({
            token: legacyToken,
            platform: "ios",
            enabled: true,
        });
    }
    return tokens;
}
/**
 * Mark a device token as invalid (unregistered or expired).
 * Called when FCM returns messaging/registration-token-not-registered.
 */
async function markTokenInvalid(userId, token) {
    // Try subcollection first
    const snapshot = await db
        .collection("users")
        .doc(userId)
        .collection("deviceTokens")
        .where("token", "==", token)
        .limit(1)
        .get();
    if (!snapshot.empty) {
        await snapshot.docs[0].ref.update({ enabled: false });
    }
}
// ─── User Preferences ───────────────────────────────────────────────
const DEFAULT_CATEGORY_PREF = {
    enabled: true,
    pushEnabled: true,
    soundEnabled: true,
    badgeEnabled: true,
};
const DEFAULT_PREFERENCES = {
    mode: "meaningful",
    lockScreenPrivacy: types_1.LockScreenPrivacy.Full,
    quietHoursEnabled: false,
    quietHoursStart: null,
    quietHoursEnd: null,
    quietHoursTimezone: null,
    sundayModeEnabled: false,
    categories: {},
};
/**
 * Loads the user's notification preferences from Firestore.
 * Returns sensible defaults if no preferences document exists.
 */
async function getUserPreferences(userId) {
    const doc = await db
        .collection("users")
        .doc(userId)
        .collection("settings")
        .doc("notifications")
        .get();
    if (!doc.exists)
        return { ...DEFAULT_PREFERENCES };
    const data = doc.data() || {};
    return {
        mode: data.mode || DEFAULT_PREFERENCES.mode,
        lockScreenPrivacy: data.lockScreenPrivacy || DEFAULT_PREFERENCES.lockScreenPrivacy,
        quietHoursEnabled: data.quietHoursEnabled ?? false,
        quietHoursStart: data.quietHoursStart ?? null,
        quietHoursEnd: data.quietHoursEnd ?? null,
        quietHoursTimezone: data.quietHoursTimezone ?? null,
        sundayModeEnabled: data.sundayModeEnabled ?? false,
        categories: data.categories || {},
    };
}
/**
 * Check if a specific notification category is enabled for push.
 */
function isCategoryPushEnabled(prefs, category) {
    const catPref = prefs.categories[category] || DEFAULT_CATEGORY_PREF;
    return catPref.enabled && catPref.pushEnabled;
}
// ─── Content Visibility ─────────────────────────────────────────────
/**
 * Checks if a post exists and is not removed/flagged.
 */
async function isPostVisible(postId) {
    const doc = await db.collection("posts").doc(postId).get();
    if (!doc.exists)
        return false;
    const data = doc.data();
    if (!data)
        return false;
    if (data.removed === true)
        return false;
    if (data.flaggedForReview === true)
        return false;
    return true;
}
/**
 * Checks if a comment exists and is not removed.
 */
async function isCommentVisible(commentId) {
    const doc = await db.collection("comments").doc(commentId).get();
    if (!doc.exists)
        return false;
    const data = doc.data();
    if (!data)
        return false;
    if (data.removed === true || data.deleted === true)
        return false;
    return true;
}
/**
 * Checks if a user account is active and not suspended.
 */
async function isUserActive(userId) {
    const doc = await db.collection("users").doc(userId).get();
    if (!doc.exists)
        return false;
    const data = doc.data();
    if (!data)
        return false;
    if (data.suspended === true || data.deactivated === true)
        return false;
    return true;
}
/**
 * Checks if a user's account is private.
 */
async function isPrivateAccount(userId) {
    const doc = await db.collection("users").doc(userId).get();
    if (!doc.exists)
        return false;
    return doc.data()?.isPrivate === true;
}
// ─── Actor Info ─────────────────────────────────────────────────────
/**
 * Fetches actor display info for notification rendering.
 */
async function getActorInfo(actorId) {
    const doc = await db.collection("users").doc(actorId).get();
    if (!doc.exists)
        return null;
    const data = doc.data();
    if (!data)
        return null;
    return {
        id: actorId,
        name: data.name || data.displayName || "Someone",
        username: data.username || "",
        profileImageURL: data.profileImageURL || null,
    };
}
// ─── Idempotency Key ────────────────────────────────────────────────
/**
 * Generates a deterministic idempotency key to prevent duplicate notifications.
 * Pattern: `{type}_{actorId}_{targetId}`
 */
function buildIdempotencyKey(type, actorId, targetId) {
    return `${type}_${actorId}_${targetId}`;
}
// ─── Grouping Key ───────────────────────────────────────────────────
/**
 * Generates a deterministic grouping key for notification aggregation.
 * Notifications with the same grouping key within the aggregation window
 * will be merged into a single grouped notification.
 *
 * Pattern: `{type}_{targetEntityId}`
 * Examples: "amen_post_abc123", "follow_user_xyz"
 */
function buildGroupingKey(type, targetEntityId) {
    return `${type}_${targetEntityId}`;
}
// ─── Route Builders ─────────────────────────────────────────────────
/**
 * Builds primary and fallback route info for a notification candidate.
 * Ensures every notification has a typed route + graceful fallback.
 */
function buildRoutes(type, opts) {
    switch (type) {
        case types_1.NotificationType.Follow:
        case types_1.NotificationType.FollowRequestAccepted:
            return {
                targetRouteType: types_1.RouteType.Profile,
                routePayload: { userId: opts.actorId },
                fallbackRouteType: types_1.RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };
        case types_1.NotificationType.Amen:
        case types_1.NotificationType.Repost:
            return {
                targetRouteType: types_1.RouteType.Post,
                routePayload: { postId: opts.postId },
                fallbackRouteType: types_1.RouteType.Profile,
                fallbackRoutePayload: { userId: opts.actorId },
            };
        case types_1.NotificationType.Comment:
            return {
                targetRouteType: types_1.RouteType.PostComment,
                routePayload: {
                    postId: opts.postId,
                    commentId: opts.commentId,
                    scrollAnchorId: opts.commentId,
                },
                fallbackRouteType: types_1.RouteType.Post,
                fallbackRoutePayload: { postId: opts.postId },
            };
        case types_1.NotificationType.Reply:
            return {
                targetRouteType: types_1.RouteType.PostReply,
                routePayload: {
                    postId: opts.postId,
                    commentId: opts.replyId || opts.commentId,
                    parentCommentId: opts.parentCommentId,
                    scrollAnchorId: opts.replyId || opts.commentId,
                },
                fallbackRouteType: types_1.RouteType.PostComment,
                fallbackRoutePayload: {
                    postId: opts.postId,
                    commentId: opts.parentCommentId,
                },
            };
        case types_1.NotificationType.Mention:
            if (opts.commentId) {
                return {
                    targetRouteType: types_1.RouteType.MentionInComment,
                    routePayload: {
                        postId: opts.postId,
                        commentId: opts.commentId,
                        scrollAnchorId: opts.commentId,
                    },
                    fallbackRouteType: types_1.RouteType.Post,
                    fallbackRoutePayload: { postId: opts.postId },
                };
            }
            return {
                targetRouteType: types_1.RouteType.Post,
                routePayload: { postId: opts.postId },
                fallbackRouteType: types_1.RouteType.Profile,
                fallbackRoutePayload: { userId: opts.actorId },
            };
        case types_1.NotificationType.PrayerSupported:
        case types_1.NotificationType.PrayerAnswered:
            return {
                targetRouteType: types_1.RouteType.Prayer,
                routePayload: { prayerId: opts.prayerId },
                fallbackRouteType: types_1.RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };
        case types_1.NotificationType.ChurchNoteShared:
        case types_1.NotificationType.ChurchNoteReplied:
            return {
                targetRouteType: types_1.RouteType.ChurchNote,
                routePayload: { noteId: opts.noteId },
                fallbackRouteType: types_1.RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };
        default:
            return {
                targetRouteType: types_1.RouteType.NotificationsInbox,
                routePayload: {},
                fallbackRouteType: types_1.RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };
    }
}
// ─── Push Body Builders ─────────────────────────────────────────────
/**
 * Generates push notification title and body text.
 * Respects lock screen privacy settings AND post-level content privacy.
 *
 * @param contentPrivacy  "public" if the parent post is fully public; "limited"
 *   for followers-only, trustedCircle, church, space, or private posts.
 *   When "limited", commentText is NEVER included in the visible push body —
 *   the content is only resolved on-device after auth via mutable-content.
 *   See docs/privacy-model.md §9 (Payload hygiene) and M-4 audit finding.
 */
function buildPushText(type, actorName, privacy, opts = {}) {
    // Privacy-safe generic messages (user's lock screen preference)
    if (privacy === types_1.LockScreenPrivacy.Minimal) {
        return { title: "AMEN", body: "You have a new notification" };
    }
    // M-4 fix: never include comment/reply text for non-public content in push body.
    // The APNs mutable-content flag allows the NotificationServiceExtension to
    // fetch and display the text on-device after the user authenticates.
    const includeCommentText = opts.contentPrivacy !== "limited" && !!opts.commentText;
    const othersText = opts.actorCount && opts.actorCount > 1
        ? ` and ${opts.actorCount - 1} other${opts.actorCount > 2 ? "s" : ""}`
        : "";
    const displayName = privacy === types_1.LockScreenPrivacy.NameOnly
        ? actorName
        : actorName;
    switch (type) {
        case types_1.NotificationType.Follow:
            return {
                title: "New Follower",
                body: `${displayName}${othersText} started following you`,
            };
        case types_1.NotificationType.FollowRequestAccepted:
            return {
                title: "Follow Request Accepted",
                body: `${displayName} accepted your follow request`,
            };
        case types_1.NotificationType.Amen:
            return {
                title: "Amen",
                body: `${displayName}${othersText} said Amen to your post`,
            };
        case types_1.NotificationType.Comment:
            return {
                title: "New Comment",
                body: includeCommentText
                    ? `${displayName} commented: ${opts.commentText.substring(0, 80)}`
                    : `${displayName} commented on your post`,
            };
        case types_1.NotificationType.Reply:
            return {
                title: "New Reply",
                body: includeCommentText
                    ? `${displayName} replied: ${opts.commentText.substring(0, 80)}`
                    : `${displayName} replied to your comment`,
            };
        case types_1.NotificationType.Mention:
            return {
                title: "Mentioned You",
                body: `${displayName} mentioned you`,
            };
        case types_1.NotificationType.Repost:
            return {
                title: "Repost",
                body: `${displayName} reposted your post`,
            };
        case types_1.NotificationType.PrayerSupported:
            return {
                title: "Prayer Support",
                body: `${displayName} is praying for you`,
            };
        case types_1.NotificationType.PrayerAnswered:
            return {
                title: "Answered Prayer",
                body: "A prayer you supported has been answered!",
            };
        case types_1.NotificationType.ChurchNoteShared:
            return {
                title: "Church Note Shared",
                body: `${displayName} shared a church note with you`,
            };
        case types_1.NotificationType.ChurchNoteReplied:
            return {
                title: "Church Note Reply",
                body: `${displayName} replied to your church note`,
            };
        default:
            return { title: "AMEN", body: "You have a new notification" };
    }
}
// ─── Notification Category Mapper ───────────────────────────────────
/**
 * Maps a NotificationType to its preference category key.
 * Matches Swift's NotificationType.filterCategory.
 */
function getCategoryForType(type) {
    switch (type) {
        case types_1.NotificationType.Follow:
        case types_1.NotificationType.FollowRequestAccepted:
            return "follows";
        case types_1.NotificationType.Comment:
        case types_1.NotificationType.Reply:
        case types_1.NotificationType.Repost:
            return "conversations";
        case types_1.NotificationType.Mention:
            return "mentions";
        case types_1.NotificationType.Amen:
            return "reactions";
        case types_1.NotificationType.PrayerReminder:
        case types_1.NotificationType.PrayerAnswered:
        case types_1.NotificationType.PrayerSupported:
            return "prayerUpdates";
        case types_1.NotificationType.ChurchNoteShared:
        case types_1.NotificationType.ChurchNoteReplied:
            return "churchNotes";
        case types_1.NotificationType.Message:
        case types_1.NotificationType.MessageRequest:
        case types_1.NotificationType.MessageRequestAccepted:
            return "directMessages";
        case types_1.NotificationType.ActionThreadInvite:
        case types_1.NotificationType.ActionThreadUpdate:
        case types_1.NotificationType.ActionThreadReminder:
            return "actionThreads";
        default:
            return "all";
    }
}
//# sourceMappingURL=helpers.js.map