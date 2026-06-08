/**
 * notifications/counts.ts
 *
 * Unread/unseen count management for the notification inbox.
 * Provides atomic increment/decrement operations and callable
 * functions for marking notifications as seen/opened.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Unseen Count Operations ────────────────────────────────────────

/**
 * Atomically increments the unseen notification count for a user and returns
 * the post-increment value. Using a transaction eliminates the badge race
 * condition under concurrent notifications (e.g. viral post fan-out): each
 * invocation gets a unique, monotonically increasing badge number instead of
 * all reading the same pre-increment value.
 */
export async function incrementUnseenCount(userId: string): Promise<number> {
    const stateRef = db
        .collection("users")
        .doc(userId)
        .collection("notificationState")
        .doc("inbox");

    return db.runTransaction(async (transaction) => {
        const doc = await transaction.get(stateRef);
        const current: number = doc.exists ? (doc.data()?.unseenCount ?? 0) : 0;
        const newCount = current + 1;
        transaction.set(
            stateRef,
            {
                unseenCount: newCount,
                lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
        );
        return newCount;
    });
}

/**
 * Atomically decrements the unseen count by a specified amount.
 * Ensures count never goes below 0.
 */
export async function decrementUnseenCount(
    userId: string,
    amount: number
): Promise<void> {
    if (amount <= 0) return;

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
        transaction.set(
            stateRef,
            {
                unseenCount: newCount,
                lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
        );
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
export const markNotificationsSeen = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
        if (!context.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Must be signed in"
            );
        }

        const userId = context.auth.uid;
        const notificationIds: string[] = data.notificationIds;

        if (
            !Array.isArray(notificationIds) ||
            notificationIds.length === 0
        ) {
            throw new HttpsError(
                "invalid-argument",
                "notificationIds must be a non-empty array"
            );
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
            if (!doc.exists) continue;

            const docData = doc.data();
            if (!docData) continue;

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
            .set(
                {
                    lastSeenAt:
                        admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
            );

        return { markedCount };
    }
);

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
export const markNotificationOpened = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
        if (!context.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Must be signed in"
            );
        }

        const userId = context.auth.uid;
        const notificationId: string = data.notificationId;

        if (!notificationId || typeof notificationId !== "string") {
            throw new HttpsError(
                "invalid-argument",
                "notificationId must be a string"
            );
        }

        const docRef = db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .doc(notificationId);

        const doc = await docRef.get();
        if (!doc.exists) {
            throw new HttpsError(
                "not-found",
                "Notification not found"
            );
        }

        const docData = doc.data();
        if (!docData) {
            throw new HttpsError(
                "not-found",
                "Notification data missing"
            );
        }

        // Verify ownership
        if (docData.userId !== userId) {
            throw new HttpsError(
                "permission-denied",
                "Not your notification"
            );
        }

        const updateData: Record<string, unknown> = {
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
            .set(
                {
                    lastOpenedAt:
                        admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true }
            );

        return { success: true };
    }
);

// ─── Callable: Mark Notification Dismissed ──────────────────────────

/**
 * Callable function: markNotificationDismissed
 *
 * Called when the user swipes to dismiss a notification.
 *
 * Input: { notificationId: string }
 * Output: { success: boolean }
 */
export const markNotificationDismissed = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
        if (!context.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Must be signed in"
            );
        }

        const userId = context.auth.uid;
        const notificationId: string = data.notificationId;

        if (!notificationId || typeof notificationId !== "string") {
            throw new HttpsError(
                "invalid-argument",
                "notificationId must be a string"
            );
        }

        const docRef = db
            .collection("users")
            .doc(userId)
            .collection("notifications")
            .doc(notificationId);

        const doc = await docRef.get();
        if (!doc.exists) {
            throw new HttpsError(
                "not-found",
                "Notification not found"
            );
        }

        if (doc.data()?.userId !== userId) {
            throw new HttpsError(
                "permission-denied",
                "Not your notification"
            );
        }

        await docRef.update({
            dismissedAt: admin.firestore.FieldValue.serverTimestamp(),
            read: true,
        });

        return { success: true };
    }
);

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
export const reconcileNotificationCount = onCall(async (request) => {
    const data = request.data as any;
    const _data = data;
    const context = { auth: request.auth, app: request.app };
        if (!context.auth) {
            throw new HttpsError(
                "unauthenticated",
                "Must be signed in"
            );
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
                .set(
                    {
                        unseenCount: actualCount,
                        lastReconciledAt:
                            admin.firestore.FieldValue.serverTimestamp(),
                        lastUpdatedAt:
                            admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                );
        }

        return { previousCount, actualCount, corrected };
    }
);
