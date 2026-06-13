"use strict";
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
exports.userAccountDeletionCascade = void 0;
const functions = __importStar(require("firebase-functions"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
const ALGOLIA_APP_ID = "182SCN7O9S";
// ─── Callable ─────────────────────────────────────────────────────────────────
exports.userAccountDeletionCascade = (0, https_1.onCall)(async (request) => {
    const _data = request.data;
    const data = _data;
    const context = { auth: request.auth, app: request.app };
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Must be signed in");
    }
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    const userId = context.auth.uid;
    functions.logger.info(`[userAccountDeletionCascade] Starting for user ${userId}`);
    // ── Phase 1: Mark as deleting ────────────────────────────────────────
    // Prevents new content writes during cascade.
    await db.collection("users").doc(userId).set({ status: "deleting", deletionStartedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
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
    // ── Phase 7c: P0-9 — aiBibleStudyConversations (root collection) ────────
    // Contains user-typed Bible study queries and AI responses keyed by userId.
    // Each conversation doc also has a `messages` subcollection.
    // App Store 5.1.1(v) / GDPR Art.17.
    // BACKFILL REQUIRED: Run one-time admin script to delete aiBibleStudyConversations
    // for users already in the deletion audit log. If no audit log exists, log as P1.
    await deleteAiBibleStudyConversations(userId);
    // ── Phase 7d: P0-9 — realtimeSessions (root collection) ─────────────────
    // Voice/prayer realtime session records written by createRealtimeSession CF.
    // Subcollections: analyticsEvents, scriptureReferences.
    // Field is `createdBy` (audit finding A13-006).
    await deleteRealtimeSessions(userId);
    // TODO(P1 — Pinecone): Delete user vectors from Pinecone index.
    // Namespace format: userId (embeddings are namespaced by UID).
    // Requires PINECONE_API_KEY + PINECONE_INDEX_NAME env vars.
    // When available, call: pineconeIndex.delete1({ deleteAll: true, namespace: userId })
    // Tracked as P1 because Pinecone is not yet provisioned for production
    // (see Backend/functions/src/berean/bereanMemory.ts:435).
    // ── Phase 8: Delete Firebase Auth account ────────────────────────────
    try {
        await admin.auth().deleteUser(userId);
    }
    catch (err) {
        const code = err.code;
        if (code !== "auth/user-not-found") {
            functions.logger.error(`[userAccountDeletionCascade] Auth deletion failed for ${userId}:`, err);
            // Non-fatal for the overall cascade — Firestore doc will still be deleted.
        }
    }
    // ── Phase 9: Delete Firestore user document ───────────────────────────
    await db.collection("users").doc(userId).delete();
    functions.logger.info(`[userAccountDeletionCascade] Complete for ${userId}. ` +
        `posts=${deletedPosts + deletedPostsLegacy}, comments=${deletedComments}, ` +
        `follows=${deletedFollows}, saved=${deletedSaved}`);
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
async function deleteUserCollection(collection, field, userId) {
    let total = 0;
    while (true) {
        const snap = await db
            .collection(collection)
            .where(field, "==", userId)
            .limit(500)
            .get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        total += snap.size;
        if (snap.size < 500)
            break;
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
async function cleanupConversations(userId) {
    let startAfter = null;
    while (true) {
        let query = db
            .collection("conversations")
            .where("participantIds", "array-contains", userId)
            .limit(100);
        if (startAfter)
            query = query.startAfter(startAfter);
        const snap = await query.get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => {
            const participants = doc.data().participantIds ?? [];
            if (participants.length <= 2) {
                // 1:1 DM — delete the conversation document entirely.
                batch.delete(doc.ref);
            }
            else {
                // Group — remove user from participants list.
                batch.update(doc.ref, {
                    participantIds: admin.firestore.FieldValue.arrayRemove(userId),
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        });
        await batch.commit();
        if (snap.size < 100)
            break;
        startAfter = snap.docs[snap.docs.length - 1];
    }
}
/**
 * Removes the user's Algolia records from "users" index.
 * Post records are deleted by postDeletionCascade (called for each post).
 */
async function removeUserFromAlgolia(userId) {
    try {
        const apiKey = process.env.ALGOLIA_ADMIN_KEY ?? "";
        if (!apiKey) {
            functions.logger.warn(`[userAccountDeletionCascade] ALGOLIA_ADMIN_KEY not set — skipping Algolia removal`);
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
            functions.logger.warn(`[userAccountDeletionCascade] Algolia delete returned ${response.status} for user ${userId}`);
        }
    }
    catch (err) {
        functions.logger.warn(`[userAccountDeletionCascade] Algolia removal failed for user ${userId}:`, err);
    }
}
/**
 * Deletes all known subcollections from the user document.
 * Each subcollection is paginated to handle large data sets.
 */
async function deleteUserSubcollections(userId) {
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
        // P0-10: AI/Berean conversation stores — contain user-typed prayer, personal
        // questions, and AI responses. Must be deleted on account removal.
        // App Store 5.1.1(v) / GDPR Art.17.
        // BACKFILL REQUIRED: Run one-time admin script to delete chatHistory and
        // bereanConversations for users in the deletion audit log. If no audit log
        // exists, log this as P1 follow-up.
        "chatHistory", // BereanChatView.swift:254 — AI assistant reply log
        "bereanConversations", // BereanConversationService.swift + premiumBereanCallables.ts
    ];
    await Promise.allSettled(subcollections.map((sub) => deleteSubcollection(userId, sub)));
}
async function deleteSubcollection(userId, subcollection) {
    const ref = db.collection("users").doc(userId).collection(subcollection);
    while (true) {
        const snap = await ref.limit(500).get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        if (snap.size < 500)
            break;
    }
}
/**
 * Drains all documents from an arbitrary collection reference (by ref, not path).
 * Used for nested subcollections on root-collection documents.
 */
async function drainCollectionRef(ref) {
    while (true) {
        const snap = await ref.limit(500).get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        if (snap.size < 500)
            break;
    }
}
/**
 * P0-9: Deletes all aiBibleStudyConversations documents for a user, including
 * their `messages` subcollection (user-typed queries + AI responses).
 * Root collection keyed by the `userId` field.
 */
async function deleteAiBibleStudyConversations(userId) {
    while (true) {
        const snap = await db
            .collection("aiBibleStudyConversations")
            .where("userId", "==", userId)
            .limit(100)
            .get();
        if (snap.empty)
            break;
        for (const convDoc of snap.docs) {
            // Delete messages subcollection before the conversation doc
            await drainCollectionRef(convDoc.ref.collection("messages"));
            await convDoc.ref.delete();
        }
        if (snap.size < 100)
            break;
    }
}
/**
 * P0-9 (A13-006): Deletes all realtimeSessions documents created by a user,
 * including `analyticsEvents` and `scriptureReferences` subcollections.
 * Root collection keyed by the `createdBy` field.
 */
async function deleteRealtimeSessions(userId) {
    while (true) {
        const snap = await db
            .collection("realtimeSessions")
            .where("createdBy", "==", userId)
            .limit(100)
            .get();
        if (snap.empty)
            break;
        for (const sessionDoc of snap.docs) {
            await drainCollectionRef(sessionDoc.ref.collection("analyticsEvents"));
            await drainCollectionRef(sessionDoc.ref.collection("scriptureReferences"));
            await sessionDoc.ref.delete();
        }
        if (snap.size < 100)
            break;
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
async function deleteEventRsvpsForUser(userId) {
    // The RSVP document ID is the user's UID, and the userId field is also
    // stored on the document for querying.
    const rsvpsQuery = db
        .collectionGroup("rsvps")
        .where("userId", "==", userId)
        .limit(400);
    while (true) {
        const snap = await rsvpsQuery.get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        if (snap.size < 400)
            break;
    }
}
//# sourceMappingURL=userAccountDeletionCascade.js.map