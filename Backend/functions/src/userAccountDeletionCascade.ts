/**
 * userAccountDeletionCascade.ts
 *
 * CRITICAL: Full account deletion cascade (App Store Guideline 5.1.1).
 *
 * WHY THIS EXISTS:
 *   Apple requires that users can delete their account from within the app.
 *   The existing AccountDeletionService deletes the Firestore user document
 *   and the Firebase Auth account, but leaves behind all posts, comments,
 *   follows, conversations, saved posts, and Storage files. This violates
 *   the user's right to erasure and leaks orphaned data indefinitely.
 *
 * WHAT THIS DOES (callable: userAccountDeletionCascade):
 *   Phase 1 — Mark account as deleting (immediate, blocks new content)
 *   Phase 2 — Delete all posts (postDeletionCascade trigger handles sub-cleanup)
 *   Phase 3 — Delete comments, savedPosts, follows, follow requests authored by user
 *   Phase 4 — Remove user from shared conversations (or delete DM-only convos)
 *   Phase 5 — Remove Algolia user record
 *   Phase 6 — Delete all user subcollection data
 *   Phase 7 — Delete Firebase Auth account
 *   Phase 8 — Delete Firestore user document
 *
 * IMPORTANT NOTES:
 *   - Deleting posts triggers postDeletionCascade for each post (Firestore trigger),
 *     so their comments/reactions/feed items are cleaned up asynchronously.
 *   - This function does NOT delete Storage profile photos by default — the client
 *     should call Storage delete before calling this function if that is desired.
 *   - The operation is idempotent: re-calling after partial failure is safe.
 *   - Large accounts (thousands of posts) may hit the 540-second function timeout.
 *     For large accounts, consider a background queue (write a "deleteQueue" doc and
 *     process in batches via a scheduled function). For typical accounts this is fine.
 *
 * Input:  {} (no arguments — uses caller's auth UID)
 * Output: { success: boolean, deletedPosts: number, deletedFollows: number }
 */

import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();
const ALGOLIA_APP_ID = "182SCN7O9S";

// ─── Callable ─────────────────────────────────────────────────────────────────

export const userAccountDeletionCascade = onCall(async (request) => {
    const _data = request.data as any;
    const data = _data;
    const context = { auth: request.auth, app: request.app };
        if (!context.auth) {
            throw new HttpsError("unauthenticated", "Must be signed in");
        }

        if (context.app == undefined) {
            throw new HttpsError(
                "failed-precondition",
                "The function must be called from an App Check verified app."
            );
        }

        const userId = context.auth.uid;

        functions.logger.info(`[userAccountDeletionCascade] Starting for user ${userId}`);

        // ── Phase 1: Mark as deleting ────────────────────────────────────────
        // Prevents new content writes during cascade.
        await db.collection("users").doc(userId).set(
            { status: "deleting", deletionStartedAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true }
        );

        // ── Phase 2: Delete all posts ────────────────────────────────────────
        // Each deletion triggers postDeletionCascade asynchronously.
        const deletedPosts = await deleteUserCollection("posts", "authorId", userId);
        // Also check legacy `userId` field on posts
        const deletedPostsLegacy = await deleteUserCollection("posts", "userId", userId);

        // ── Phase 3: Delete comments, savedPosts, reposts, amens authored by user
        const [deletedComments, deletedSaved, deletedReposts, deletedAmens] = await Promise.all([
            deleteUserCollection("comments", "authorId", userId),
            deleteUserCollection("savedPosts", "userId", userId),
            deleteUserCollection("reposts", "userId", userId),
            deleteUserCollection("amens", "userId", userId),
        ]);

        // ── Phase 4: Delete follows ──────────────────────────────────────────
        const [deletedFollowingEdges, deletedFollowerEdges] = await Promise.all([
            deleteUserCollection("follows", "followerId", userId),
            deleteUserCollection("follows", "followingId", userId),
        ]);
        const deletedFollows = deletedFollowingEdges + deletedFollowerEdges;

        // ── Phase 5: Remove from or delete shared conversations ──────────────
        await cleanupConversations(userId);

        // ── Phase 6: Remove from Algolia ─────────────────────────────────────
        await removeUserFromAlgolia(userId);

        // ── Phase 7: Delete user subcollections ──────────────────────────────
        await deleteUserSubcollections(userId);

        // ── Phase 7b: Delete event RSVPs authored by this user ───────────────
        // amenEvents/{eventId}/rsvps/{uid} documents are keyed on the user's UID.
        // A collection-group query finds all of them regardless of which event they
        // belong to, then deletes them in pages to avoid orphaning stale RSVP data.
        await deleteEventRsvpsForUser(userId);

        // ── Phase 8: Delete Firebase Auth account ────────────────────────────
        try {
            await admin.auth().deleteUser(userId);
        } catch (err: unknown) {
            const code = (err as { code?: string }).code;
            if (code !== "auth/user-not-found") {
                functions.logger.error(
                    `[userAccountDeletionCascade] Auth deletion failed for ${userId}:`,
                    err
                );
                // Non-fatal for the overall cascade — Firestore doc will still be deleted.
            }
        }

        // ── Phase 9: Delete Firestore user document ───────────────────────────
        await db.collection("users").doc(userId).delete();

        functions.logger.info(
            `[userAccountDeletionCascade] Complete for ${userId}. ` +
            `posts=${deletedPosts + deletedPostsLegacy}, comments=${deletedComments}, ` +
            `follows=${deletedFollows}, saved=${deletedSaved}`
        );

        return {
            success: true,
            deletedPosts: deletedPosts + deletedPostsLegacy,
            deletedComments,
            deletedFollows,
            deletedSaved: deletedSaved + deletedReposts + deletedAmens,
        };
    });

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Batch-deletes all documents in `collection` where `field == userId`.
 * Returns the count of deleted documents.
 */
async function deleteUserCollection(
    collection: string,
    field: string,
    userId: string
): Promise<number> {
    let total = 0;
    while (true) {
        const snap = await db
            .collection(collection)
            .where(field, "==", userId)
            .limit(500)
            .get();

        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        total += snap.size;

        if (snap.size < 500) break;
    }
    return total;
}

/**
 * For each conversation the user participates in:
 *   - If it is a 1:1 DM (exactly 2 participants), delete the whole conversation doc.
 *   - If it is a group conversation (3+ participants), remove the user from participantIds.
 *
 * Messages are left in place for moderation audit purposes. A separate scheduled
 * cleanup can purge messages from fully-deleted conversations.
 */
async function cleanupConversations(userId: string): Promise<void> {
    let startAfter: admin.firestore.DocumentSnapshot | null = null;

    while (true) {
        let query = db
            .collection("conversations")
            .where("participantIds", "array-contains", userId)
            .limit(100);

        if (startAfter) query = query.startAfter(startAfter);

        const snap = await query.get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => {
            const participants: string[] = doc.data().participantIds ?? [];
            if (participants.length <= 2) {
                // 1:1 DM — delete the conversation document entirely.
                batch.delete(doc.ref);
            } else {
                // Group — remove user from participants list.
                batch.update(doc.ref, {
                    participantIds: admin.firestore.FieldValue.arrayRemove(userId),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });
        await batch.commit();

        if (snap.size < 100) break;
        startAfter = snap.docs[snap.docs.length - 1];
    }
}

/**
 * Removes the user's Algolia records from "users" index.
 * Post records are deleted by postDeletionCascade (called for each post).
 */
async function removeUserFromAlgolia(userId: string): Promise<void> {
    try {
        const apiKey = process.env.ALGOLIA_ADMIN_KEY ?? "";
        if (!apiKey) {
            functions.logger.warn(
                `[userAccountDeletionCascade] ALGOLIA_ADMIN_KEY not set — skipping Algolia removal`
            );
            return;
        }

        const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/users/${encodeURIComponent(userId)}`;
        const response = await fetch(url, {
            method: "DELETE",
            headers: {
                "X-Algolia-Application-Id": ALGOLIA_APP_ID,
                "X-Algolia-API-Key": apiKey,
            },
        });

        if (!response.ok && response.status !== 404) {
            functions.logger.warn(
                `[userAccountDeletionCascade] Algolia delete returned ${response.status} for user ${userId}`
            );
        }
    } catch (err) {
        functions.logger.warn(
            `[userAccountDeletionCascade] Algolia removal failed for user ${userId}:`,
            err
        );
    }
}

/**
 * Deletes all known subcollections from the user document.
 * Each subcollection is paginated to handle large data sets.
 */
async function deleteUserSubcollections(userId: string): Promise<void> {
    const subcollections = [
        "notifications",
        "notificationState",
        "blockedUsers",
        "mutedUsers",
        "followRequests",
        "agentInsights",
        "agentRecommendations",
        "executionLogs",
        "trustEvents",
        "trustSnapshots",
        "churchInteractions",
        "churchFollowUps",
        "bereanSessions",
        "prayerRequests",
        "churchNotes",
        "deviceTokens",
    ];

    await Promise.allSettled(
        subcollections.map((sub) => deleteSubcollection(userId, sub))
    );
}

async function deleteSubcollection(
    userId: string,
    subcollection: string
): Promise<void> {
    const ref = db.collection("users").doc(userId).collection(subcollection);
    while (true) {
        const snap = await ref.limit(500).get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();

        if (snap.size < 500) break;
    }
}

/**
 * Deletes all RSVP documents the user has left inside any amenEvent.
 *
 * Each RSVP is stored at amenEvents/{eventId}/rsvps/{userId}, so the
 * document ID equals the user's UID. A collection-group query on "rsvps"
 * filtered by "userId" field finds every one of them, regardless of which
 * event they belong to, without requiring a full scan of all events.
 *
 * This ensures no orphan RSVP documents remain after account deletion.
 */
async function deleteEventRsvpsForUser(userId: string): Promise<void> {
    // The RSVP document ID is the user's UID, and the userId field is also
    // stored on the document for querying.
    const rsvpsQuery = db
        .collectionGroup("rsvps")
        .where("userId", "==", userId)
        .limit(400);

    while (true) {
        const snap = await rsvpsQuery.get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();

        if (snap.size < 400) break;
    }
}
