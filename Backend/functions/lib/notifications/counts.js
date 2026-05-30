"use strict";
/**
 * notifications/counts.ts
 *
 * Unread/unseen count management for the notification inbox.
 * Provides atomic increment/decrement operations and callable
 * functions for marking notifications as seen/opened.
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
exports.reconcileNotificationCount = exports.markNotificationDismissed = exports.markNotificationOpened = exports.markNotificationsSeen = void 0;
exports.incrementUnseenCount = incrementUnseenCount;
exports.decrementUnseenCount = decrementUnseenCount;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// ─── Unseen Count Operations ────────────────────────────────────────
/**
 * Atomically increments the unseen notification count for a user and returns
 * the post-increment value. Using a transaction eliminates the badge race
 * condition under concurrent notifications (e.g. viral post fan-out): each
 * invocation gets a unique, monotonically increasing badge number instead of
 * all reading the same pre-increment value.
 */
async function incrementUnseenCount(userId) {
    const stateRef = db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox");
    return db.runTransaction(async (transaction) => {
        const doc = await transaction.get(stateRef);
        const current = doc.exists ? (doc.data()?.unseenCount ?? 0) : 0;
        const newCount = current + 1;
        transaction.set(stateRef, {
            unseenCount: newCount,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return newCount;
    });
}
/**
 * Atomically decrements the unseen count by a specified amount.
 * Ensures count never goes below 0.
 */
async function decrementUnseenCount(userId, amount) {
    if (amount <= 0)
        return;
    const stateRef = db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox");
    await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(stateRef);
        const currentCount = doc.exists
            ? doc.data()?.unseenCount || 0
            : 0;
        const newCount = Math.max(0, currentCount - amount);
        transaction.set(stateRef, {
            unseenCount: newCount,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
// ─── Callable: Mark Notifications Seen ──────────────────────────────
/**
 * Callable function: markNotificationsSeen
 *
 * Called when notification rows become visible in the viewport.
 * Sets `seenAt` on each notification and decrements unseen count.
 *
 * Input: { notificationIds: string[] }
 * Output: { markedCount: number }
 */
exports.markNotificationsSeen = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const userId = context.auth.uid;
    const notificationIds = data.notificationIds;
    if (!Array.isArray(notificationIds) ||
        notificationIds.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "notificationIds must be a non-empty array");
    }
    // Cap batch size to prevent abuse
    const MAX_BATCH = 50;
    const ids = notificationIds.slice(0, MAX_BATCH);
    const batch = db.batch();
    let markedCount = 0;
    for (const notifId of ids) {
        const docRef = db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .doc(notifId);
        const doc = await docRef.get();
        if (!doc.exists)
            continue;
        const docData = doc.data();
        if (!docData)
            continue;
        // Only mark if not already seen
        if (!docData.seenAt) {
            batch.update(docRef, {
                seenAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            markedCount++;
        }
    }
    if (markedCount > 0) {
        await batch.commit();
        await decrementUnseenCount(userId, markedCount);
    }
    // Update last seen timestamp
    await db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox")
        .set({
        lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { markedCount };
});
// ─── Callable: Mark Notification Opened ─────────────────────────────
/**
 * Callable function: markNotificationOpened
 *
 * Called when the user taps a notification row.
 * Sets `openedAt` and `read` on the notification.
 *
 * Input: { notificationId: string }
 * Output: { success: boolean }
 */
exports.markNotificationOpened = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const userId = context.auth.uid;
    const notificationId = data.notificationId;
    if (!notificationId || typeof notificationId !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "notificationId must be a string");
    }
    const docRef = db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .doc(notificationId);
    const doc = await docRef.get();
    if (!doc.exists) {
        throw new functions.https.HttpsError("not-found", "Notification not found");
    }
    const docData = doc.data();
    if (!docData) {
        throw new functions.https.HttpsError("not-found", "Notification data missing");
    }
    // Verify ownership
    if (docData.userId !== userId) {
        throw new functions.https.HttpsError("permission-denied", "Not your notification");
    }
    const updateData = {
        read: true,
        openedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    // Also set seenAt if not already set
    if (!docData.seenAt) {
        updateData.seenAt =
            admin.firestore.FieldValue.serverTimestamp();
    }
    await docRef.update(updateData);
    // Update last opened timestamp
    await db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox")
        .set({
        lastOpenedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { success: true };
});
// ─── Callable: Mark Notification Dismissed ──────────────────────────
/**
 * Callable function: markNotificationDismissed
 *
 * Called when the user swipes to dismiss a notification.
 *
 * Input: { notificationId: string }
 * Output: { success: boolean }
 */
exports.markNotificationDismissed = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const userId = context.auth.uid;
    const notificationId = data.notificationId;
    if (!notificationId || typeof notificationId !== "string") {
        throw new functions.https.HttpsError("invalid-argument", "notificationId must be a string");
    }
    const docRef = db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .doc(notificationId);
    const doc = await docRef.get();
    if (!doc.exists) {
        throw new functions.https.HttpsError("not-found", "Notification not found");
    }
    if (doc.data()?.userId !== userId) {
        throw new functions.https.HttpsError("permission-denied", "Not your notification");
    }
    await docRef.update({
        dismissedAt: admin.firestore.FieldValue.serverTimestamp(),
        read: true,
    });
    return { success: true };
});
// ─── Callable: Reconcile Unread Count ───────────────────────────────
/**
 * Callable function: reconcileNotificationCount
 *
 * Recounts actual unseen notifications and corrects the counter.
 * Called by the client when it suspects badge drift.
 *
 * Input: {} (no args)
 * Output: { previousCount: number, actualCount: number, corrected: boolean }
 */
exports.reconcileNotificationCount = functions.https.onCall(async (_data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Must be signed in");
    }
    if (context.app == undefined) {
        throw new functions.https.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const userId = context.auth.uid;
    // Get the current stored count
    const stateDoc = await db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox")
        .get();
    const previousCount = stateDoc.exists
        ? stateDoc.data()?.unseenCount || 0
        : 0;
    // Count actual unseen notifications
    const unseenSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("notifications")
        .where("seenAt", "==", null)
        .where("dismissedAt", "==", null)
        .limit(500)
        .get();
    const actualCount = unseenSnapshot.size;
    const corrected = previousCount !== actualCount;
    if (corrected) {
        await db
            .collection("users")
            .doc(userId)
            .collection("notificationState")
            .doc("inbox")
            .set({
            unseenCount: actualCount,
            lastReconciledAt: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    return { previousCount, actualCount, corrected };
});
//# sourceMappingURL=counts.js.map