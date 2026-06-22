/**
 * postDeletionCascade.ts
 *
 * CRITICAL: Cascade cleanup when a post is deleted.
 *
 * WHY THIS EXISTS:
 *   Deleting a post document from the client leaves orphaned data across
 *   multiple collections — comments, reactions, reposts, saved posts, feed
 *   items, and Storage media. Orphaned comments/reactions are still queryable
 *   (leaking deleted content to the API surface) and orphaned Storage objects
 *   accumulate billing cost indefinitely.
 *
 * WHAT THIS DOES on posts/{postId} deletion:
 *   1. Batch-deletes all comments referencing the post
 *   2. Batch-deletes all amens/reactions referencing the post
 *   3. Batch-deletes all reposts referencing the post
 *   4. Batch-deletes all savedPost records referencing the post
 *   5. Batch-deletes feed items in userFeeds subcollections (collection group)
 *   6. Removes the post from Algolia search index
 *   7. Deletes all associated Storage media files
 *
 * Each batch operation pages through results (≤500 per Firestore batch) to
 * handle posts with large engagement counts without hitting write limits.
 */

import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

// Must match onPostCreated.ts and deleteAlgoliaUser.ts
const ALGOLIA_APP_ID = "182SCN7O9S";
const ALGOLIA_WRITE_KEY_SECRET = "ALGOLIA_ADMIN_KEY";

// ─── Trigger ─────────────────────────────────────────────────────────────────

export const postDeletionCascade = onDocumentDeleted("posts/{postId}", async (event) => {
    const postId = event.params.postId;
    const snap = event.data;
    const data = snap?.data();

    logger.info(`[postDeletionCascade] Starting cascade for post ${postId}`);

    await Promise.allSettled([
        deleteCollectionWhere("comments", "postId", postId),
        deleteCollectionWhere("amens", "postId", postId),
        deleteCollectionWhere("reactions", "postId", postId),
        deleteCollectionWhere("reposts", "postId", postId),
        deleteCollectionWhere("savedPosts", "postId", postId),
        deleteFeedItems(postId),
        removeFromAlgolia(postId),
        deleteStorageMedia(data?.mediaURLs ?? []),
    ]);

    logger.info(`[postDeletionCascade] Cascade complete for post ${postId}`);
});

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Batch-deletes all documents in `collection` where `field == value`.
 * Pages through 500 at a time to stay within Firestore batch write limits.
 */
async function deleteCollectionWhere(
    collection: string,
    field: string,
    value: string
): Promise<void> {
    let deleted = 0;
    while (true) {
        const snap = await db
            .collection(collection)
            .where(field, "==", value)
            .limit(500)
            .get();

        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted += snap.size;

        if (snap.size < 500) break;
    }
    logger.info(
        `[postDeletionCascade] Deleted ${deleted} docs from ${collection} for postId=${value}`
    );
}

/**
 * Removes the post from every user's feed via collection group query on
 * the "posts" subcollection inside "userFeeds/{userId}/posts/{postId}".
 */
async function deleteFeedItems(postId: string): Promise<void> {
    // Feed items are stored as userFeeds/{userId}/posts/{postId}.
    // A collection group query lets us find all of them without knowing the userIds.
    const snap = await db
        .collectionGroup("posts")
        .where("postId", "==", postId)
        .limit(500)
        .get();

    if (snap.empty) return;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    logger.info(
        `[postDeletionCascade] Deleted ${snap.size} feed items for postId=${postId}`
    );
}

/**
 * Removes the post document from Algolia so it no longer appears in search.
 */
async function removeFromAlgolia(postId: string): Promise<void> {
    try {
        const apiKey = process.env.ALGOLIA_ADMIN_KEY
            ?? (await import("firebase-functions").then((f) =>
                f.config().algolia?.admin_key
            ));

        const key = apiKey ?? ALGOLIA_WRITE_KEY_SECRET;
        const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/posts/${encodeURIComponent(postId)}`;

        const response = await fetch(url, {
            method: "DELETE",
            headers: {
                "X-Algolia-Application-Id": ALGOLIA_APP_ID,
                "X-Algolia-API-Key": key,
            },
        });

        if (!response.ok && response.status !== 404) {
            logger.warn(
                `[postDeletionCascade] Algolia delete returned ${response.status} for post ${postId}`
            );
        }
    } catch (err) {
        // Non-fatal: Algolia record may already be absent or index may not exist yet.
        logger.warn(
            `[postDeletionCascade] Algolia removal failed for post ${postId}:`,
            err
        );
    }
}

/**
 * Deletes all Storage objects referenced by a post's media URLs.
 * Accepts gs:// URIs or https://firebasestorage.googleapis.com/... URLs.
 */
async function deleteStorageMedia(mediaURLs: string[]): Promise<void> {
    if (!mediaURLs || mediaURLs.length === 0) return;

    const bucket = admin.storage().bucket();

    await Promise.allSettled(
        mediaURLs.map(async (url: string) => {
            try {
                let filePath: string;

                if (url.startsWith("gs://")) {
                    // gs://bucket-name/path/to/file
                    filePath = url.replace(/^gs:\/\/[^/]+\//, "");
                } else {
                    // https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encoded-path}?...
                    const match = url.match(/\/o\/([^?]+)/);
                    if (!match) return;
                    filePath = decodeURIComponent(match[1]);
                }

                await bucket.file(filePath).delete({ ignoreNotFound: true });
                logger.info(
                    `[postDeletionCascade] Deleted storage file: ${filePath}`
                );
            } catch (err) {
                logger.warn(
                    `[postDeletionCascade] Failed to delete media ${url}:`,
                    err
                );
            }
        })
    );
}
