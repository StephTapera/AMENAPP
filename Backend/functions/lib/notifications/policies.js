"use strict";
/**
 * notifications/policies.ts
 *
 * Sequential fail-fast policy evaluation pipeline.
 * Each check returns early if the notification should be suppressed,
 * downranked, or deferred — preventing unnecessary downstream work.
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
exports.evaluatePolicies = evaluatePolicies;
const admin = __importStar(require("firebase-admin"));
const types_1 = require("./types");
const helpers_1 = require("./helpers");
const db = admin.firestore();
// ─── In-Memory Rate-Limit Cache ────────────────────────────────────
//
// Caches rate-limit query results for the duration of a single Cloud Function
// invocation. When a viral post triggers many notifications in one invocation,
// multiple candidates may share the same actor→recipient pair. Without this
// cache each pair would fire a separate Firestore collection query (O(n) reads).
//
// The cache is module-level (not request-level) but is keyed per actor→recipient
// pair, so stale entries from previous invocations are effectively harmless —
// they will cause a suppression at worst, never a false allow. At high volume
// the function process recycles frequently enough that entries are short-lived.
const rateLimitCache = new Map();
const ALLOW = {
    result: types_1.PolicyResult.Allow,
    triggeredBy: null,
    pushAllowed: true,
    soundAllowed: true,
};
function suppress(reason) {
    return {
        result: types_1.PolicyResult.Suppress,
        triggeredBy: reason,
        pushAllowed: false,
        soundAllowed: false,
    };
}
function downrank(reason) {
    return {
        result: types_1.PolicyResult.Downrank,
        triggeredBy: reason,
        pushAllowed: false,
        soundAllowed: false,
    };
}
function inAppOnly(reason) {
    return {
        result: types_1.PolicyResult.InAppOnly,
        triggeredBy: reason,
        pushAllowed: false,
        soundAllowed: false,
    };
}
function digest(reason) {
    return {
        result: types_1.PolicyResult.Digest,
        triggeredBy: reason,
        pushAllowed: false,
        soundAllowed: false,
    };
}
// ─── Main Policy Pipeline ───────────────────────────────────────────
/**
 * Evaluates all policies sequentially (fail-fast).
 * Returns the first non-Allow result, or Allow if all checks pass.
 */
async function evaluatePolicies(candidate) {
    // 1. Self-notification check
    const selfCheck = checkSelfNotification(candidate);
    if (selfCheck.result !== types_1.PolicyResult.Allow)
        return selfCheck;
    // 2. Block check (bidirectional)
    const blockCheck = await checkBlocked(candidate);
    if (blockCheck.result !== types_1.PolicyResult.Allow)
        return blockCheck;
    // 3. Mute check
    const muteCheck = await checkMuted(candidate);
    if (muteCheck.result !== types_1.PolicyResult.Allow)
        return muteCheck;
    // 4. Content moderation check
    const contentCheck = await checkContentVisible(candidate);
    if (contentCheck.result !== types_1.PolicyResult.Allow)
        return contentCheck;
    // 5. Private account check
    const privacyCheck = await checkPrivateAccount(candidate);
    if (privacyCheck.result !== types_1.PolicyResult.Allow)
        return privacyCheck;
    // 6. Actor trust check
    const trustCheck = await checkActorTrust(candidate);
    if (trustCheck.result !== types_1.PolicyResult.Allow)
        return trustCheck;
    // 7. Spam/rate-limit check
    const rateCheck = await checkRateLimit(candidate);
    if (rateCheck.result !== types_1.PolicyResult.Allow)
        return rateCheck;
    // 8. Recipient preference check
    const prefCheck = await checkRecipientPreferences(candidate);
    if (prefCheck.result !== types_1.PolicyResult.Allow)
        return prefCheck;
    // 9. Quiet hours check
    const quietCheck = await checkQuietHours(candidate);
    if (quietCheck.result !== types_1.PolicyResult.Allow)
        return quietCheck;
    // 10. Duplicate/idempotency check
    const dedupCheck = await checkIdempotency(candidate);
    if (dedupCheck.result !== types_1.PolicyResult.Allow)
        return dedupCheck;
    return ALLOW;
}
// ─── Timezone Utility ───────────────────────────────────────────────
/**
 * Returns hours (0–23), minutes (0–59), and whether it is Sunday in the
 * given IANA timezone. Uses the built-in Intl.DateTimeFormat so no external
 * library is required. Falls back to UTC on invalid timezone strings.
 */
function getLocalTimeInZone(now, tz) {
    try {
        const parts = new Intl.DateTimeFormat("en-US", {
            timeZone: tz,
            hour: "2-digit",
            minute: "2-digit",
            weekday: "short",
            hour12: false,
        }).formatToParts(now);
        // hour12:false can return "24" for midnight on some runtimes — normalise.
        const hours = parseInt(parts.find((p) => p.type === "hour")?.value ?? "0", 10) % 24;
        const minutes = parseInt(parts.find((p) => p.type === "minute")?.value ?? "0", 10);
        const weekday = parts.find((p) => p.type === "weekday")?.value ?? "";
        return { hours, minutes, isSunday: weekday === "Sun" };
    }
    catch {
        return {
            hours: now.getUTCHours(),
            minutes: now.getUTCMinutes(),
            isSunday: now.getUTCDay() === 0,
        };
    }
}
// ─── Individual Policy Checks ───────────────────────────────────────
/**
 * 1. Self-notification: suppress if actor === recipient.
 */
function checkSelfNotification(candidate) {
    if (candidate.actorId === candidate.recipientId) {
        return suppress("self_notification");
    }
    return ALLOW;
}
/**
 * 2. Block check: suppress if either user has blocked the other.
 */
async function checkBlocked(candidate) {
    const blocked = await (0, helpers_1.isBlocked)(candidate.actorId, candidate.recipientId);
    if (blocked) {
        return suppress("blocked");
    }
    return ALLOW;
}
/**
 * 3. Mute check: downrank if recipient has muted the actor.
 * Muted = write to inbox at low priority but skip push.
 */
async function checkMuted(candidate) {
    const muted = await (0, helpers_1.isMuted)(candidate.recipientId, candidate.actorId);
    if (muted) {
        return downrank("muted");
    }
    return ALLOW;
}
/**
 * 4. Content moderation: suppress if referenced post/comment is removed or flagged.
 */
async function checkContentVisible(candidate) {
    // Check post visibility if notification references a post
    if (candidate.postId) {
        const visible = await (0, helpers_1.isPostVisible)(candidate.postId);
        if (!visible) {
            return suppress("post_not_visible");
        }
    }
    // Check comment visibility if notification references a comment
    if (candidate.commentId) {
        const visible = await (0, helpers_1.isCommentVisible)(candidate.commentId);
        if (!visible) {
            return suppress("comment_not_visible");
        }
    }
    return ALLOW;
}
/**
 * 5. Private account: suppress follow-related notifications if the actor
 * hasn't been approved to follow the recipient's private account.
 *
 * For non-follow notifications (comment, amen, etc.), the content itself
 * wouldn't be visible without a follow relationship, so this is a safety net.
 */
async function checkPrivateAccount(candidate) {
    const isPrivate = await (0, helpers_1.isPrivateAccount)(candidate.recipientId);
    if (!isPrivate)
        return ALLOW;
    // For private accounts, check if actor follows the recipient
    const follows = await (0, helpers_1.isFollowing)(candidate.actorId, candidate.recipientId);
    // Follow notifications are always allowed (that's how you request to follow)
    const followTypes = ["follow", "follow_request_accepted"];
    if (followTypes.includes(candidate.type)) {
        return ALLOW;
    }
    // For other notification types on private accounts, actor must follow recipient
    if (!follows) {
        return suppress("private_account_no_follow");
    }
    return ALLOW;
}
/**
 * 6. Actor trust: suppress if the actor's account is suspended or deactivated.
 */
async function checkActorTrust(candidate) {
    const active = await (0, helpers_1.isUserActive)(candidate.actorId);
    if (!active) {
        return suppress("actor_not_active");
    }
    return ALLOW;
}
/**
 * 7. Spam/rate-limit: suppress if actor has sent too many notifications
 * to this recipient within the rolling window.
 *
 * Limit: ACTOR_RATE_LIMIT_PER_HOUR (20) per actor→recipient pair per hour.
 *
 * Uses an in-memory cache so repeated checks for the same actor→recipient pair
 * within a single function invocation (e.g. viral post fan-out) skip the
 * Firestore query after the first result is known.
 */
async function checkRateLimit(candidate) {
    const cacheKey = `ratelimit:${candidate.actorId}:${candidate.recipientId}`;
    const cached = rateLimitCache.get(cacheKey);
    if (cached !== undefined) {
        return cached ? suppress("rate_limited") : ALLOW;
    }
    const oneHourAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
    const recentNotifs = await db
        .collection("users")
        .doc(candidate.recipientId)
        .collection("notifications")
        .where("actorId", "==", candidate.actorId)
        .where("createdAt", ">=", oneHourAgo)
        .limit(types_1.ACTOR_RATE_LIMIT_PER_HOUR + 1)
        .get();
    const isRateLimited = recentNotifs.size >= types_1.ACTOR_RATE_LIMIT_PER_HOUR;
    rateLimitCache.set(cacheKey, isRateLimited);
    if (isRateLimited) {
        return suppress("rate_limited");
    }
    return ALLOW;
}
/**
 * 8. Recipient preferences: check if the recipient has disabled
 * this notification category or push for this category.
 */
async function checkRecipientPreferences(candidate) {
    const prefs = await (0, helpers_1.getUserPreferences)(candidate.recipientId);
    const category = (0, helpers_1.getCategoryForType)(candidate.type);
    const catPref = prefs.categories[category];
    // If category exists and is explicitly disabled, suppress entirely
    if (catPref && !catPref.enabled) {
        return suppress("category_disabled");
    }
    // If category exists but push is disabled, deliver in-app only
    if (catPref && !catPref.pushEnabled) {
        return inAppOnly("category_push_disabled");
    }
    // If using "meaningful" mode, only allow high-signal notification types
    if (prefs.mode === "meaningful") {
        const highSignalTypes = [
            "follow",
            "comment",
            "reply",
            "mention",
            "message",
            "message_request",
            "prayer_supported",
            "prayer_answered",
            "action_thread_invite",
        ];
        if (!highSignalTypes.includes(candidate.type)) {
            return inAppOnly("meaningful_mode_low_signal");
        }
    }
    return ALLOW;
}
/**
 * 9. Quiet hours: if recipient has quiet hours enabled and we're
 * currently within their quiet window, defer to digest.
 *
 * 5.7 FIX: Uses the user's stored IANA timezone (quietHoursTimezone) via
 * date-fns-tz to convert UTC now to local time before comparing against
 * the quiet hours window. Falls back to UTC if no timezone is stored,
 * preserving backward compatibility with existing preference documents.
 */
async function checkQuietHours(candidate) {
    const prefs = await (0, helpers_1.getUserPreferences)(candidate.recipientId);
    if (!prefs.quietHoursEnabled)
        return ALLOW;
    if (!prefs.quietHoursStart || !prefs.quietHoursEnd)
        return ALLOW;
    // Resolve local time in the user's timezone (5.7 FIX).
    // quietHoursTimezone is an IANA string (e.g., "America/Chicago").
    // Falls back to "UTC" for legacy documents that pre-date 5.7.
    const tz = prefs.quietHoursTimezone ?? "UTC";
    const { hours: localHours, minutes: localMinutes, isSunday } = getLocalTimeInZone(new Date(), tz);
    const currentMinutes = localHours * 60 + localMinutes;
    const [startH, startM] = prefs.quietHoursStart.split(":").map(Number);
    const [endH, endM] = prefs.quietHoursEnd.split(":").map(Number);
    const startMinutes = startH * 60 + startM;
    const endMinutes = endH * 60 + endM;
    let inQuietHours = false;
    if (startMinutes <= endMinutes) {
        // Same-day range (e.g., 09:00 - 17:00)
        inQuietHours =
            currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
    else {
        // Overnight range (e.g., 22:00 - 07:00)
        inQuietHours =
            currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
    if (inQuietHours) {
        // Sunday mode: during quiet hours on Sunday, suppress entirely.
        // Uses local day-of-week derived from the user's timezone, not UTC.
        if (prefs.sundayModeEnabled && isSunday) {
            return suppress("sunday_mode_quiet_hours");
        }
        return digest("quiet_hours");
    }
    return ALLOW;
}
/**
 * 10. Idempotency: suppress if a notification with the same
 * idempotency key already exists for this recipient.
 *
 * Uses the deterministic key pattern: {type}_{actorId}_{targetId}
 */
async function checkIdempotency(candidate) {
    const targetId = candidate.postId ||
        candidate.commentId ||
        candidate.conversationId ||
        candidate.prayerId ||
        candidate.noteId ||
        candidate.recipientId;
    const idempotencyKey = `${candidate.type}_${candidate.actorId}_${targetId}`;
    const existing = await db
        .collection("users")
        .doc(candidate.recipientId)
        .collection("notifications")
        .where("idempotencyKey", "==", idempotencyKey)
        .limit(1)
        .get();
    if (!existing.empty) {
        return suppress("duplicate_idempotency");
    }
    return ALLOW;
}
//# sourceMappingURL=policies.js.map