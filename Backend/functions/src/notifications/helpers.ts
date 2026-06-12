/**
 * notifications/helpers.ts
 *
 * Shared utility functions for the notification pipeline.
 * Block/mute checks, device token retrieval, preference loading,
 * idempotency key generation, and grouping key generation.
 */

import * as admin from "firebase-admin";
import {
    NotificationType,
    NotificationActor,
    RouteType,
    RoutePayload,
    LockScreenPrivacy,
    NotificationPreferences,
    CategoryPreference,
} from "./types";

const db = admin.firestore();

// ─── Block Check ────────────────────────────────────────────────────

/**
 * Returns true if either user has blocked the other.
 * Checks both directions for bidirectional block enforcement.
 */
export async function isBlocked(
    userId: string,
    targetId: string
): Promise<boolean> {
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
export async function isMuted(
    recipientId: string,
    actorId: string
): Promise<boolean> {
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
export async function isFollowing(
    followerId: string,
    followedId: string
): Promise<boolean> {
    // Follow docs use composite ID pattern: followerId_followedId
    const followDoc = await db
        .collection("follows")
        .doc(`${followerId}_${followedId}`)
        .get();
    if (followDoc.exists) return true;

    // Fallback: query by fields in case doc ID pattern differs
    const snapshot = await db
        .collection("follows")
        .where("followerId", "==", followerId)
        .where("followedId", "==", followedId)
        .limit(1)
        .get();
    return !snapshot.empty;
}

// ─── Device Tokens ──────────────────────────────────────────────────

export interface DeviceToken {
    token: string;
    platform: string;
    enabled: boolean;
}

/**
 * Fetches all active device tokens for a user.
 * Returns only enabled tokens with non-empty values.
 */
export async function getDeviceTokens(
    userId: string
): Promise<DeviceToken[]> {
    const snapshot = await db
        .collection("users")
        .doc(userId)
        .collection("deviceTokens")
        .where("enabled", "==", true)
        .get();

    const tokens: DeviceToken[] = [];
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
    if (
        legacyToken &&
        typeof legacyToken === "string" &&
        !tokens.some((t) => t.token === legacyToken)
    ) {
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
export async function markTokenInvalid(
    userId: string,
    token: string
): Promise<void> {
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

const DEFAULT_CATEGORY_PREF: CategoryPreference = {
    enabled: true,
    pushEnabled: true,
    soundEnabled: true,
    badgeEnabled: true,
};

const DEFAULT_PREFERENCES: NotificationPreferences = {
    mode: "meaningful",
    lockScreenPrivacy: LockScreenPrivacy.Full,
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
export async function getUserPreferences(
    userId: string
): Promise<NotificationPreferences> {
    const doc = await db
        .collection("users")
        .doc(userId)
        .collection("settings")
        .doc("notifications")
        .get();

    if (!doc.exists) return { ...DEFAULT_PREFERENCES };

    const data = doc.data() || {};
    return {
        mode: data.mode || DEFAULT_PREFERENCES.mode,
        lockScreenPrivacy:
            data.lockScreenPrivacy || DEFAULT_PREFERENCES.lockScreenPrivacy,
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
export function isCategoryPushEnabled(
    prefs: NotificationPreferences,
    category: string
): boolean {
    const catPref = prefs.categories[category] || DEFAULT_CATEGORY_PREF;
    return catPref.enabled && catPref.pushEnabled;
}

// ─── Content Visibility ─────────────────────────────────────────────

/**
 * Checks if a post exists and is not removed/flagged.
 */
export async function isPostVisible(postId: string): Promise<boolean> {
    const doc = await db.collection("posts").doc(postId).get();
    if (!doc.exists) return false;
    const data = doc.data();
    if (!data) return false;
    if (data.removed === true) return false;
    if (data.flaggedForReview === true) return false;
    return true;
}

/**
 * Checks if a comment exists and is not removed.
 */
export async function isCommentVisible(commentId: string): Promise<boolean> {
    const doc = await db.collection("comments").doc(commentId).get();
    if (!doc.exists) return false;
    const data = doc.data();
    if (!data) return false;
    if (data.removed === true || data.deleted === true) return false;
    return true;
}

/**
 * Checks if a user account is active and not suspended.
 */
export async function isUserActive(userId: string): Promise<boolean> {
    const doc = await db.collection("users").doc(userId).get();
    if (!doc.exists) return false;
    const data = doc.data();
    if (!data) return false;
    if (data.suspended === true || data.deactivated === true) return false;
    return true;
}

/**
 * Checks if a user's account is private.
 */
export async function isPrivateAccount(userId: string): Promise<boolean> {
    const doc = await db.collection("users").doc(userId).get();
    if (!doc.exists) return false;
    return doc.data()?.isPrivate === true;
}

// ─── Actor Info ─────────────────────────────────────────────────────

/**
 * Fetches actor display info for notification rendering.
 */
export async function getActorInfo(
    actorId: string
): Promise<NotificationActor | null> {
    const doc = await db.collection("users").doc(actorId).get();
    if (!doc.exists) return null;
    const data = doc.data();
    if (!data) return null;
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
export function buildIdempotencyKey(
    type: NotificationType,
    actorId: string,
    targetId: string
): string {
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
export function buildGroupingKey(
    type: NotificationType,
    targetEntityId: string
): string {
    return `${type}_${targetEntityId}`;
}

// ─── Route Builders ─────────────────────────────────────────────────

/**
 * Builds primary and fallback route info for a notification candidate.
 * Ensures every notification has a typed route + graceful fallback.
 */
export function buildRoutes(
    type: NotificationType,
    opts: {
        postId?: string;
        commentId?: string;
        parentCommentId?: string;
        replyId?: string;
        actorId?: string;
        conversationId?: string;
        prayerId?: string;
        noteId?: string;
    }
): {
    targetRouteType: RouteType;
    routePayload: RoutePayload;
    fallbackRouteType: RouteType;
    fallbackRoutePayload: RoutePayload;
} {
    switch (type) {
        case NotificationType.Follow:
        case NotificationType.FollowRequestAccepted:
            return {
                targetRouteType: RouteType.Profile,
                routePayload: { userId: opts.actorId },
                fallbackRouteType: RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };

        case NotificationType.Amen:
        case NotificationType.Repost:
            return {
                targetRouteType: RouteType.Post,
                routePayload: { postId: opts.postId },
                fallbackRouteType: RouteType.Profile,
                fallbackRoutePayload: { userId: opts.actorId },
            };

        case NotificationType.Comment:
            return {
                targetRouteType: RouteType.PostComment,
                routePayload: {
                    postId: opts.postId,
                    commentId: opts.commentId,
                    scrollAnchorId: opts.commentId,
                },
                fallbackRouteType: RouteType.Post,
                fallbackRoutePayload: { postId: opts.postId },
            };

        case NotificationType.Reply:
            return {
                targetRouteType: RouteType.PostReply,
                routePayload: {
                    postId: opts.postId,
                    commentId: opts.replyId || opts.commentId,
                    parentCommentId: opts.parentCommentId,
                    scrollAnchorId: opts.replyId || opts.commentId,
                },
                fallbackRouteType: RouteType.PostComment,
                fallbackRoutePayload: {
                    postId: opts.postId,
                    commentId: opts.parentCommentId,
                },
            };

        case NotificationType.Mention:
            if (opts.commentId) {
                return {
                    targetRouteType: RouteType.MentionInComment,
                    routePayload: {
                        postId: opts.postId,
                        commentId: opts.commentId,
                        scrollAnchorId: opts.commentId,
                    },
                    fallbackRouteType: RouteType.Post,
                    fallbackRoutePayload: { postId: opts.postId },
                };
            }
            return {
                targetRouteType: RouteType.Post,
                routePayload: { postId: opts.postId },
                fallbackRouteType: RouteType.Profile,
                fallbackRoutePayload: { userId: opts.actorId },
            };

        case NotificationType.PrayerSupported:
        case NotificationType.PrayerAnswered:
            return {
                targetRouteType: RouteType.Prayer,
                routePayload: { prayerId: opts.prayerId },
                fallbackRouteType: RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };

        case NotificationType.ChurchNoteShared:
        case NotificationType.ChurchNoteReplied:
            return {
                targetRouteType: RouteType.ChurchNote,
                routePayload: { noteId: opts.noteId },
                fallbackRouteType: RouteType.NotificationsInbox,
                fallbackRoutePayload: {},
            };

        default:
            return {
                targetRouteType: RouteType.NotificationsInbox,
                routePayload: {},
                fallbackRouteType: RouteType.NotificationsInbox,
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
export function buildPushText(
    type: NotificationType,
    actorName: string,
    privacy: LockScreenPrivacy,
    opts: {
        commentText?: string;
        actorCount?: number;
        contentPrivacy?: "public" | "limited";
    } = {}
): { title: string; body: string } {
    // Privacy-safe generic messages (user's lock screen preference)
    if (privacy === LockScreenPrivacy.Minimal) {
        return { title: "AMEN", body: "You have a new notification" };
    }

    // M-4 fix: never include comment/reply text for non-public content in push body.
    // The APNs mutable-content flag allows the NotificationServiceExtension to
    // fetch and display the text on-device after the user authenticates.
    const includeCommentText =
        opts.contentPrivacy !== "limited" && !!opts.commentText;

    const othersText =
        opts.actorCount && opts.actorCount > 1
            ? ` and ${opts.actorCount - 1} other${opts.actorCount > 2 ? "s" : ""}`
            : "";
    const displayName =
        privacy === LockScreenPrivacy.NameOnly
            ? actorName
            : actorName;

    switch (type) {
        case NotificationType.Follow:
            return {
                title: "New Follower",
                body: `${displayName}${othersText} started following you`,
            };
        case NotificationType.FollowRequestAccepted:
            return {
                title: "Follow Request Accepted",
                body: `${displayName} accepted your follow request`,
            };
        case NotificationType.Amen:
            return {
                title: "Amen",
                body: `${displayName}${othersText} said Amen to your post`,
            };
        case NotificationType.Comment:
            return {
                title: "New Comment",
                body: includeCommentText
                    ? `${displayName} commented: ${opts.commentText!.substring(0, 80)}`
                    : `${displayName} commented on your post`,
            };
        case NotificationType.Reply:
            return {
                title: "New Reply",
                body: includeCommentText
                    ? `${displayName} replied: ${opts.commentText!.substring(0, 80)}`
                    : `${displayName} replied to your comment`,
            };
        case NotificationType.Mention:
            return {
                title: "Mentioned You",
                body: `${displayName} mentioned you`,
            };
        case NotificationType.Repost:
            return {
                title: "Repost",
                body: `${displayName} reposted your post`,
            };
        case NotificationType.PrayerSupported:
            return {
                title: "Prayer Support",
                body: `${displayName} is praying for you`,
            };
        case NotificationType.PrayerAnswered:
            return {
                title: "Answered Prayer",
                body: "A prayer you supported has been answered!",
            };
        case NotificationType.ChurchNoteShared:
            return {
                title: "Church Note Shared",
                body: `${displayName} shared a church note with you`,
            };
        case NotificationType.ChurchNoteReplied:
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
export function getCategoryForType(type: NotificationType): string {
    switch (type) {
        case NotificationType.Follow:
        case NotificationType.FollowRequestAccepted:
            return "follows";
        case NotificationType.Comment:
        case NotificationType.Reply:
        case NotificationType.Repost:
            return "conversations";
        case NotificationType.Mention:
            return "mentions";
        case NotificationType.Amen:
            return "reactions";
        case NotificationType.PrayerReminder:
        case NotificationType.PrayerAnswered:
        case NotificationType.PrayerSupported:
            return "prayerUpdates";
        case NotificationType.ChurchNoteShared:
        case NotificationType.ChurchNoteReplied:
            return "churchNotes";
        case NotificationType.Message:
        case NotificationType.MessageRequest:
        case NotificationType.MessageRequestAccepted:
            return "directMessages";
        case NotificationType.ActionThreadInvite:
        case NotificationType.ActionThreadUpdate:
        case NotificationType.ActionThreadReminder:
            return "actionThreads";
        default:
            return "all";
    }
}
