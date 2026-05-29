/**
 * deleteBereanHistory.ts
 *
 * Callable: deleteBereanHistory
 *
 * Gives users the GDPR/CCPA right-to-erasure over their Berean AI history
 * WITHOUT requiring full account deletion.
 *
 * Collections erased:
 *   /berean_conversations  (userId == uid)
 *   /berean_messages       (conversationId in user's conversation set)
 *   /users/{uid}/bereanMemory
 *   /users/{uid}/bereanInsights
 *   /users/{uid}/bereanSessions  (if present)
 *
 * Design notes:
 *   - berean_messages have no direct userId field; they are linked through
 *     conversationId. We therefore fetch all conversation IDs first, then
 *     delete messages in batches per conversation.
 *   - All deletes are fire-and-forget batched writes — no partial rollback.
 *     Re-calling after a partial failure is safe (idempotent).
 *   - Logged to bereanAuditEvents for compliance evidence.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = "us-central1";
const BATCH_SIZE = 500;

// ── Helpers ───────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

async function batchDeleteQuery(
    query: admin.firestore.Query
): Promise<number> {
    let total = 0;
    while (true) {
        const snap = await query.limit(BATCH_SIZE).get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        total += snap.size;
        if (snap.size < BATCH_SIZE) break;
    }
    return total;
}

async function batchDeleteSubcollection(
    userId: string,
    subcollection: string
): Promise<number> {
    const ref = db.collection("users").doc(userId).collection(subcollection);
    let total = 0;
    while (true) {
        const snap = await ref.limit(BATCH_SIZE).get();
        if (snap.empty) break;
        const batch = db.batch();
        snap.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        total += snap.size;
        if (snap.size < BATCH_SIZE) break;
    }
    return total;
}

/**
 * Fetches all berean_conversation IDs for a user, then batch-deletes
 * all berean_messages whose conversationId is in that set.
 */
async function deleteMessagesForUser(userId: string): Promise<number> {
    // Step 1: collect all conversationIds owned by this user.
    const convSnap = await db
        .collection("berean_conversations")
        .where("userId", "==", userId)
        .select() // fetch only doc IDs
        .get();

    if (convSnap.empty) return 0;

    const convIds = convSnap.docs.map((d) => d.id);
    let total = 0;

    // Firestore `in` query supports max 30 values per clause.
    for (let i = 0; i < convIds.length; i += 30) {
        const chunk = convIds.slice(i, i + 30);
        total += await batchDeleteQuery(
            db.collection("berean_messages").where("conversationId", "in", chunk)
        );
    }

    return total;
}

// ── Callable ──────────────────────────────────────────────────────────────────

export const deleteBereanHistory = onCall(
    { region: REGION, enforceAppCheck: true },
    async (request: CallableRequest) => {
        const userId = requireAuth(request);

        logger.info("[deleteBereanHistory] Starting for user", { userId });

        // 1. Delete messages first (requires conversation IDs).
        const deletedMessages = await deleteMessagesForUser(userId);

        // 2. Delete conversations.
        const deletedConversations = await batchDeleteQuery(
            db.collection("berean_conversations").where("userId", "==", userId)
        );

        // 3. Delete subcollections from the user document.
        const [deletedMemory, deletedInsights, deletedSessions] = await Promise.all([
            batchDeleteSubcollection(userId, "bereanMemory"),
            batchDeleteSubcollection(userId, "bereanInsights"),
            batchDeleteSubcollection(userId, "bereanSessions"),
        ]);

        // 4. Compliance audit log.
        await db.collection("bereanAuditEvents").add({
            userId,
            action: "delete_all_berean_history",
            deletedConversations,
            deletedMessages,
            deletedMemory,
            deletedInsights,
            deletedSessions,
            requestedAt: FieldValue.serverTimestamp(),
        });

        logger.info("[deleteBereanHistory] Complete", {
            userId,
            deletedConversations,
            deletedMessages,
            deletedMemory,
            deletedInsights,
            deletedSessions,
        });

        return {
            success: true,
            deletedConversations,
            deletedMessages,
            deletedMemory,
            deletedInsights,
            deletedSessions,
        };
    }
);
