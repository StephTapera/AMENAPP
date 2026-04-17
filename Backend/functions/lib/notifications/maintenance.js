"use strict";
/**
 * notifications/maintenance.ts
 *
 * Scheduled background jobs for notification system health.
 * Handles count reconciliation, stale group closure,
 * old notification archival, invalid token cleanup, and push retry.
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
exports.retryFailedPush = exports.cleanupInvalidTokens = exports.closeStaleGroups = exports.cleanupOldNotifications = exports.reconcileUnreadCounts = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const types_1 = require("./types");
const db = admin.firestore();
// ─── Reconcile Unread Counts ────────────────────────────────────────
/**
 * Every 6 hours: recount actual unseen notifications for all users
 * with a notificationState doc and fix any drift.
 *
 * This catches edge cases where increments/decrements were lost
 * due to transient failures or race conditions.
 */
exports.reconcileUnreadCounts = functions.pubsub
    .schedule("every 6 hours")
    .onRun(async () => {
    const stateQuery = await db
        .collectionGroup("notificationState")
        .limit(500)
        .get();
    let correctedCount = 0;
    for (const stateDoc of stateQuery.docs) {
        // Extract userId from path: users/{userId}/notificationState/inbox
        const pathParts = stateDoc.ref.path.split("/");
        const userId = pathParts[1];
        if (!userId)
            continue;
        const storedCount = stateDoc.data()?.unseenCount || 0;
        // Count actual unseen notifications
        const unseenSnap = await db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .where("seenAt", "==", null)
            .where("dismissedAt", "==", null)
            .limit(500)
            .get();
        const actualCount = unseenSnap.size;
        if (storedCount !== actualCount) {
            await stateDoc.ref.update({
                unseenCount: actualCount,
                lastReconciledAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            correctedCount++;
        }
    }
    console.log(`Reconcile unread counts: corrected ${correctedCount} users`);
});
// ─── Cleanup Old Notifications ──────────────────────────────────────
/**
 * Daily: archive notifications older than NOTIFICATION_RETENTION_DAYS.
 * Deletes in batches to avoid timeout.
 */
exports.cleanupOldNotifications = functions.pubsub
    .schedule("every 24 hours")
    .onRun(async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - types_1.NOTIFICATION_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    // Process users with notification state docs
    const stateQuery = await db
        .collectionGroup("notificationState")
        .limit(200)
        .get();
    let totalDeleted = 0;
    for (const stateDoc of stateQuery.docs) {
        const pathParts = stateDoc.ref.path.split("/");
        const userId = pathParts[1];
        if (!userId)
            continue;
        const oldNotifs = await db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .where("createdAt", "<", cutoff)
            .limit(100)
            .get();
        if (oldNotifs.empty)
            continue;
        const batch = db.batch();
        for (const doc of oldNotifs.docs) {
            batch.delete(doc.ref);
        }
        await batch.commit();
        totalDeleted += oldNotifs.size;
    }
    console.log(`Cleanup old notifications: deleted ${totalDeleted} notifications`);
});
// ─── Close Stale Groups ────────────────────────────────────────────
/**
 * Every 2 hours: mark aggregation groups past their window as closed.
 * This prevents very old groups from accumulating actors indefinitely.
 *
 * "Closing" a group = removing the groupId so new events create a fresh group.
 * This is optional — it just keeps groups tidy.
 */
exports.closeStaleGroups = functions.pubsub
    .schedule("every 2 hours")
    .onRun(async () => {
    const windowCutoff = admin.firestore.Timestamp.fromMillis(Date.now() - types_1.GROUPING_WINDOW_MS * 2 // 2x window for safety margin
    );
    // Find grouped notifications older than the window
    const stateQuery = await db
        .collectionGroup("notificationState")
        .limit(200)
        .get();
    let closedCount = 0;
    for (const stateDoc of stateQuery.docs) {
        const pathParts = stateDoc.ref.path.split("/");
        const userId = pathParts[1];
        if (!userId)
            continue;
        const staleGroups = await db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .where("groupId", "!=", null)
            .where("createdAt", "<", windowCutoff)
            .limit(50)
            .get();
        if (staleGroups.empty)
            continue;
        const batch = db.batch();
        for (const doc of staleGroups.docs) {
            // Mark as closed by nullifying groupId
            // New events will create a fresh group
            batch.update(doc.ref, {
                groupId: null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        }
        await batch.commit();
        closedCount += staleGroups.size;
    }
    console.log(`Close stale groups: closed ${closedCount} groups`);
});
// ─── Cleanup Invalid Tokens ────────────────────────────────────────
/**
 * Daily: remove device tokens that have been marked as invalid.
 * These tokens were disabled by sendPush when FCM returned
 * registration-token-not-registered errors.
 */
exports.cleanupInvalidTokens = functions.pubsub
    .schedule("every 24 hours")
    .onRun(async () => {
    // Query for disabled tokens across all users
    const invalidTokens = await db
        .collectionGroup("deviceTokens")
        .where("enabled", "==", false)
        .limit(500)
        .get();
    if (invalidTokens.empty) {
        console.log("Cleanup invalid tokens: no invalid tokens found");
        return;
    }
    const batch = db.batch();
    for (const doc of invalidTokens.docs) {
        batch.delete(doc.ref);
    }
    await batch.commit();
    console.log(`Cleanup invalid tokens: removed ${invalidTokens.size} tokens`);
});
// ─── Retry Failed Push ─────────────────────────────────────────────
/**
 * Every 30 minutes: retry push notifications that failed to deliver.
 * Only retries notifications created within the last 2 hours that
 * have pushDelivered === false and are not dismissed.
 */
exports.retryFailedPush = functions.pubsub
    .schedule("every 30 minutes")
    .onRun(async () => {
    const twoHoursAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 2 * 60 * 60 * 1000);
    const stateQuery = await db
        .collectionGroup("notificationState")
        .limit(200)
        .get();
    let retriedCount = 0;
    for (const stateDoc of stateQuery.docs) {
        const pathParts = stateDoc.ref.path.split("/");
        const userId = pathParts[1];
        if (!userId)
            continue;
        const failedPush = await db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .where("pushDelivered", "==", false)
            .where("dismissedAt", "==", null)
            .where("createdAt", ">=", twoHoursAgo)
            .limit(10)
            .get();
        if (failedPush.empty)
            continue;
        // Import sendPush dynamically to avoid circular deps
        const { sendPushNotification } = await Promise.resolve().then(() => __importStar(require("./sendPush")));
        for (const doc of failedPush.docs) {
            try {
                await sendPushNotification(doc.data(), doc.id);
                retriedCount++;
            }
            catch (error) {
                console.error(`Retry push failed for ${doc.id}:`, error);
            }
        }
    }
    console.log(`Retry failed push: retried ${retriedCount} notifications`);
});
//# sourceMappingURL=maintenance.js.map