/**
 * scheduledMaintenance.ts
 *
 * Scheduled housekeeping functions that run on a recurring basis to
 * reconcile counters, prune stale data, and clean up orphaned records.
 *
 * Functions exported:
 *   badgeReconciliation       — daily: corrects drift between unseenCount and actual
 *   followCountReconciliation — weekly: corrects followerCount/followingCount drift
 *   commentCountReconciliation— weekly: corrects commentCount on posts
 *   staleConversationCleanup  — daily: deletes fully-deleted conversations with no participants
 *   rateLimitWindowCleanup    — daily: purges expired rateLimitCounters docs
 *   staleTokenPruning         — weekly: removes FCM tokens marked invalid >30 days ago
 *   fcmQueueCleanup           — daily: purges delivered/failed FCM queue entries
 *   expiredDraftCleanup       — daily: deletes drafts older than 90 days
 *   staleFollowRequestCleanup  — daily: deletes follow requests older than 30 days
 *   usernameChangeCooldownRelease — daily: re-enables username changes after 30-day cooldown
 */

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Badge Reconciliation (daily) ────────────────────────────────────────────

/**
 * Counts actual unseen notifications for each active user and corrects
 * the unseenCount in users/{uid}/notificationState/inbox.
 *
 * Processes users in pages of 200 to avoid memory exhaustion.
 * Skips users whose count is already accurate (no write if no drift).
 */
export const badgeReconciliation = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[badgeReconciliation] Starting daily badge reconciliation");

        let processed = 0;
        let corrected = 0;
        let lastDoc: admin.firestore.DocumentSnapshot | null = null;

        while (true) {
            let query = db.collection("users").limit(200);
            if (lastDoc) query = query.startAfter(lastDoc);

            const userSnap = await query.get();
            if (userSnap.empty) break;

            await Promise.allSettled(
                userSnap.docs.map(async (userDoc) => {
                    const userId = userDoc.id;
                    try {
                        const [stateDoc, unseenSnap] = await Promise.all([
                            db.collection("users").doc(userId)
                                .collection("notificationState").doc("inbox").get(),
                            db.collection("users").doc(userId)
                                .collection("notifications")
                                .where("seenAt", "==", null)
                                .where("dismissedAt", "==", null)
                                .limit(500)
                                .get(),
                        ]);

                        const storedCount: number = stateDoc.exists
                            ? (stateDoc.data()?.unseenCount ?? 0)
                            : 0;
                        const actualCount = unseenSnap.size;

                        if (storedCount !== actualCount) {
                            await db.collection("users").doc(userId)
                                .collection("notificationState").doc("inbox")
                                .set(
                                    {
                                        unseenCount: actualCount,
                                        lastReconciledAt: admin.firestore.FieldValue.serverTimestamp(),
                                        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
                                    },
                                    { merge: true }
                                );
                            corrected++;
                        }
                        processed++;
                    } catch (err) {
                        functions.logger.warn(
                            `[badgeReconciliation] Failed for user ${userId}:`, err
                        );
                    }
                })
            );

            lastDoc = userSnap.docs[userSnap.docs.length - 1];
            if (userSnap.size < 200) break;
        }

        functions.logger.info(
            `[badgeReconciliation] Done — processed: ${processed}, corrected: ${corrected}`
        );
    });

// ─── Follow Count Reconciliation (weekly) ────────────────────────────────────

/**
 * Recounts actual follow edges and corrects followersCount/followingCount
 * on user documents. Runs weekly as follow count drift is low-urgency.
 */
export const followCountReconciliation = functions.pubsub
    .schedule("every 168 hours") // weekly
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[followCountReconciliation] Starting weekly follow count reconciliation");

        let processed = 0;
        let corrected = 0;
        let lastDoc: admin.firestore.DocumentSnapshot | null = null;

        while (true) {
            let query = db.collection("users").limit(100);
            if (lastDoc) query = query.startAfter(lastDoc);

            const userSnap = await query.get();
            if (userSnap.empty) break;

            await Promise.allSettled(
                userSnap.docs.map(async (userDoc) => {
                    const userId = userDoc.id;
                    try {
                        const [followerSnap, followingSnap] = await Promise.all([
                            db.collection("follows")
                                .where("followingId", "==", userId)
                                .limit(10_000)
                                .get(),
                            db.collection("follows")
                                .where("followerId", "==", userId)
                                .limit(10_000)
                                .get(),
                        ]);

                        const actualFollowers = followerSnap.size;
                        const actualFollowing = followingSnap.size;
                        const stored = userDoc.data();

                        if (
                            stored?.followersCount !== actualFollowers ||
                            stored?.followingCount !== actualFollowing
                        ) {
                            await db.collection("users").doc(userId).update({
                                followersCount: actualFollowers,
                                followingCount: actualFollowing,
                                countsReconciledAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                            corrected++;
                        }
                        processed++;
                    } catch (err) {
                        functions.logger.warn(
                            `[followCountReconciliation] Failed for user ${userId}:`, err
                        );
                    }
                })
            );

            lastDoc = userSnap.docs[userSnap.docs.length - 1];
            if (userSnap.size < 100) break;
        }

        functions.logger.info(
            `[followCountReconciliation] Done — processed: ${processed}, corrected: ${corrected}`
        );
    });

// ─── Comment Count Reconciliation (weekly) ───────────────────────────────────

/**
 * Recounts actual comments for posts where commentCount may have drifted.
 * Only processes posts created/updated in the last 14 days to bound the query.
 */
export const commentCountReconciliation = functions.pubsub
    .schedule("every 168 hours") // weekly
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[commentCountReconciliation] Starting weekly comment count reconciliation");

        const fourteenDaysAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 14 * 24 * 60 * 60 * 1000
        );

        const postSnap = await db.collection("posts")
            .where("createdAt", ">=", fourteenDaysAgo)
            .limit(500)
            .get();

        let corrected = 0;
        await Promise.allSettled(
            postSnap.docs.map(async (postDoc) => {
                const postId = postDoc.id;
                try {
                    const commentSnap = await db.collection("comments")
                        .where("postId", "==", postId)
                        .limit(10_000)
                        .get();

                    const actualCount = commentSnap.size;
                    if (postDoc.data().commentCount !== actualCount) {
                        await postDoc.ref.update({ commentCount: actualCount });
                        corrected++;
                    }
                } catch (err) {
                    functions.logger.warn(
                        `[commentCountReconciliation] Failed for post ${postId}:`, err
                    );
                }
            })
        );

        functions.logger.info(
            `[commentCountReconciliation] Done — checked: ${postSnap.size}, corrected: ${corrected}`
        );
    });

// ─── Stale Conversation Cleanup (daily) ──────────────────────────────────────

/**
 * Deletes conversation documents that have zero participants remaining.
 * This happens after account deletion removes the last participant.
 */
export const staleConversationCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[staleConversationCleanup] Starting");

        const snap = await db.collection("conversations")
            .where("participantIds", "==", [])
            .limit(500)
            .get();

        if (snap.empty) {
            functions.logger.info("[staleConversationCleanup] No stale conversations found");
            return;
        }

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();

        functions.logger.info(
            `[staleConversationCleanup] Deleted ${snap.size} empty conversations`
        );
    });

// ─── Rate Limit Window Cleanup (daily) ───────────────────────────────────────

/**
 * Purges expired rateLimitCounters documents. The rate limit window is typically
 * 1 hour; documents older than 2 hours are safe to delete.
 */
export const rateLimitWindowCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[rateLimitWindowCleanup] Starting");

        const twoHoursAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 2 * 60 * 60 * 1000
        );

        let total = 0;
        while (true) {
            const snap = await db.collection("rateLimitCounters")
                .where("windowStart", "<=", twoHoursAgo)
                .limit(500)
                .get();

            if (snap.empty) break;

            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            total += snap.size;

            if (snap.size < 500) break;
        }

        functions.logger.info(
            `[rateLimitWindowCleanup] Deleted ${total} expired rate limit counters`
        );
    });

// ─── Stale Token Pruning (weekly) ────────────────────────────────────────────

/**
 * Removes FCM device tokens that were marked invalid more than 30 days ago.
 * Uses a collection group query across all users' `deviceTokens` subcollections.
 */
export const staleTokenPruning = functions.pubsub
    .schedule("every 168 hours") // weekly
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[staleTokenPruning] Starting weekly token pruning");

        const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 30 * 24 * 60 * 60 * 1000
        );

        let total = 0;
        while (true) {
            const snap = await db.collectionGroup("deviceTokens")
                .where("isValid", "==", false)
                .where("invalidatedAt", "<=", thirtyDaysAgo)
                .limit(500)
                .get();

            if (snap.empty) break;

            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            total += snap.size;

            if (snap.size < 500) break;
        }

        functions.logger.info(
            `[staleTokenPruning] Pruned ${total} stale device tokens`
        );
    });

// ─── FCM Queue Cleanup (daily) ───────────────────────────────────────────────

/**
 * Purges delivered or failed quiet-hours digest queue entries older than 3 days.
 */
export const fcmQueueCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[fcmQueueCleanup] Starting");

        const threeDaysAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 3 * 24 * 60 * 60 * 1000
        );

        let total = 0;
        for (const status of ["delivered", "failed"]) {
            while (true) {
                const snap = await db.collection("quietHoursDigestQueue")
                    .where("status", "==", status)
                    .where("enqueuedAt", "<=", threeDaysAgo)
                    .limit(500)
                    .get();

                if (snap.empty) break;

                const batch = db.batch();
                snap.docs.forEach((doc) => batch.delete(doc.ref));
                await batch.commit();
                total += snap.size;

                if (snap.size < 500) break;
            }
        }

        functions.logger.info(`[fcmQueueCleanup] Purged ${total} stale FCM queue entries`);
    });

// ─── Expired Draft Cleanup (daily) ───────────────────────────────────────────

/**
 * Deletes post drafts older than 90 days from the creationDrafts collection.
 */
export const expiredDraftCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[expiredDraftCleanup] Starting");

        const ninetyDaysAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 90 * 24 * 60 * 60 * 1000
        );

        let total = 0;
        while (true) {
            const snap = await db.collection("creationDrafts")
                .where("updatedAt", "<=", ninetyDaysAgo)
                .limit(500)
                .get();

            if (snap.empty) break;

            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            total += snap.size;

            if (snap.size < 500) break;
        }

        functions.logger.info(`[expiredDraftCleanup] Deleted ${total} expired drafts`);
    });

// ─── OTP Requests Cleanup (daily) ────────────────────────────────────────────

/**
 * Purges used or expired OTP request documents from the otpRequests collection.
 * OTPs expire after 10 minutes; used ones are marked immediately. Either way,
 * documents older than 1 hour are safe to delete.
 * Item-3 FIX: Prevents unbounded growth of the otpRequests collection.
 */
export const otpRequestsCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[otpRequestsCleanup] Starting");

        const oneHourAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 60 * 60 * 1000
        );

        let total = 0;
        while (true) {
            const snap = await db.collection("otpRequests")
                .where("createdAt", "<=", oneHourAgo)
                .limit(500)
                .get();

            if (snap.empty) break;

            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            total += snap.size;

            if (snap.size < 500) break;
        }

        functions.logger.info(`[otpRequestsCleanup] Deleted ${total} expired/used OTP requests`);
    });

// ─── Stale Follow Request Cleanup (daily) ────────────────────────────────────

/**
 * Deletes pending follow requests older than 30 days.
 * Uses a collection group query across all users' `followRequests` subcollections.
 */
export const staleFollowRequestCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[staleFollowRequestCleanup] Starting");

        const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
            Date.now() - 30 * 24 * 60 * 60 * 1000
        );

        let total = 0;
        while (true) {
            const snap = await db.collectionGroup("followRequests")
                .where("status", "==", "pending")
                .where("createdAt", "<=", thirtyDaysAgo)
                .limit(500)
                .get();

            if (snap.empty) break;

            const batch = db.batch();
            snap.docs.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            total += snap.size;

            if (snap.size < 500) break;
        }

        functions.logger.info(
            `[staleFollowRequestCleanup] Deleted ${total} stale follow requests`
        );
    });

// ─── Username Change Cooldown Release (daily) ─────────────────────────────────

/**
 * Section-13 FIX: Re-enables username changes for users whose 30-day cooldown has expired.
 * Pairs with the trackUsernameChange Firestore trigger in usernameChangeTracking.ts.
 */
export const usernameChangeCooldownRelease = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[usernameChangeCooldownRelease] Starting");

        const now = admin.firestore.Timestamp.now();
        let total = 0;

        while (true) {
            const snap = await db.collection("userSafetyRecords")
                .where("canChangeUsername", "==", false)
                .where("usernameChangeCooldownUntil", "<=", now)
                .limit(500)
                .get();

            if (snap.empty) break;

            const batch = db.batch();
            snap.docs.forEach((doc) => {
                batch.update(doc.ref, {
                    canChangeUsername: true,
                    cooldownReleasedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            });
            await batch.commit();
            total += snap.size;

            if (snap.size < 500) break;
        }

        functions.logger.info(
            `[usernameChangeCooldownRelease] Re-enabled username changes for ${total} users`
        );
    });

// ─── Orphaned Media Cleanup (daily) ────────────────────────────────────────────

/**
 * Item-35 FIX: Deletes orphaned Storage files under post_media/ that were
 * uploaded more than 48 hours ago but never linked to a published post.
 *
 * Storage path convention (see mediaScanning.ts):
 *   post_media/{uid}/{uploadGroupId}/{filename}
 *
 * A file is "orphaned" when no Firestore post document exists with the matching
 * uploadGroupId. This happens when a user picks media but abandons the composer
 * before completing the post, leaving files in Storage indefinitely.
 *
 * The 48-hour grace period allows slow uploads and draft posts to complete
 * before any file is considered orphaned.
 *
 * Cost note: this function paginates through Storage in batches of 1,000 files
 * and fires one Firestore read per unique uploadGroupId (cached per run).
 * For large buckets this should still complete within the 9-minute CF timeout.
 */
export const orphanedMediaCleanup = functions.pubsub
    .schedule("every 24 hours")
    .timeZone("UTC")
    .onRun(async () => {
        functions.logger.info("[orphanedMediaCleanup] Starting");

        const cutoff = Date.now() - 48 * 60 * 60 * 1000; // 48 hours ago
        const bucket = admin.storage().bucket();

        let totalDeleted = 0;
        let pageToken: string | undefined;

        // Cache uploadGroupId lookups within this run to avoid duplicate reads.
        const groupIdCache = new Map<string, boolean>(); // groupId → hasPost

        do {
            const [files, , nextQuery] = await bucket.getFiles({
                prefix: "post_media/",
                maxResults: 1000,
                pageToken,
            });
            pageToken = (nextQuery as Record<string, string> | undefined)?.pageToken;

            for (const file of files) {
                // Only process files older than the cutoff.
                const createdMs = new Date(file.metadata.timeCreated as string).getTime();
                if (isNaN(createdMs) || createdMs > cutoff) continue;

                // Path: post_media/{uid}/{uploadGroupId}/{filename}
                const parts = file.name.split("/");
                if (parts.length < 4) continue;
                const uploadGroupId = parts[2];

                // Check cache first.
                let hasPost = groupIdCache.get(uploadGroupId);
                if (hasPost === undefined) {
                    const snap = await db.collection("posts")
                        .where("uploadGroupId", "==", uploadGroupId)
                        .limit(1)
                        .get();
                    hasPost = !snap.empty;
                    groupIdCache.set(uploadGroupId, hasPost);
                }

                if (!hasPost) {
                    try {
                        await file.delete();
                        totalDeleted++;
                        functions.logger.info(
                            `[orphanedMediaCleanup] Deleted orphaned file: ${file.name}`
                        );
                    } catch (err) {
                        functions.logger.warn(
                            `[orphanedMediaCleanup] Failed to delete ${file.name}:`, err
                        );
                    }
                }
            }
        } while (pageToken);

        functions.logger.info(
            `[orphanedMediaCleanup] Deleted ${totalDeleted} orphaned media files`
        );
    });
