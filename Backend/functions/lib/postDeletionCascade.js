"use strict";
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
exports.postDeletionCascade = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const admin = __importStar(require("firebase-admin"));
const db = admin.firestore();
// Must match onPostCreated.ts and deleteAlgoliaUser.ts
const ALGOLIA_APP_ID = "182SCN7O9S";
const ALGOLIA_WRITE_KEY_SECRET = "ALGOLIA_ADMIN_KEY";
// ─── Trigger ─────────────────────────────────────────────────────────────────
exports.postDeletionCascade = (0, firestore_1.onDocumentDeleted)("posts/{postId}", async (event) => {
    const postId = event.params.postId;
    const snap = event.data;
    const data = snap?.data();
    v2_1.logger.info(`[postDeletionCascade] Starting cascade for post ${postId}`);
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
    v2_1.logger.info(`[postDeletionCascade] Cascade complete for post ${postId}`);
});
// ─── Helpers ─────────────────────────────────────────────────────────────────
/**
 * Batch-deletes all documents in `collection` where `field == value`.
 * Pages through 500 at a time to stay within Firestore batch write limits.
 */
async function deleteCollectionWhere(collection, field, value) {
    let deleted = 0;
    while (true) {
        const snap = await db
            .collection(collection)
            .where(field, "==", value)
            .limit(500)
            .get();
        if (snap.empty)
            break;
        const batch = db.batch();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
        deleted += snap.size;
        if (snap.size < 500)
            break;
    }
    v2_1.logger.info(`[postDeletionCascade] Deleted ${deleted} docs from ${collection} for postId=${value}`);
}
/**
 * Removes the post from every user's feed via collection group query on
 * the "posts" subcollection inside "userFeeds/{userId}/posts/{postId}".
 */
async function deleteFeedItems(postId) {
    // Feed items are stored as userFeeds/{userId}/posts/{postId}.
    // A collection group query lets us find all of them without knowing the userIds.
    const snap = await db
        .collectionGroup("posts")
        .where("postId", "==", postId)
        .limit(500)
        .get();
    if (snap.empty)
        return;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    v2_1.logger.info(`[postDeletionCascade] Deleted ${snap.size} feed items for postId=${postId}`);
}
/**
 * Removes the post document from Algolia so it no longer appears in search.
 */
async function removeFromAlgolia(postId) {
    try {
        const apiKey = process.env.ALGOLIA_ADMIN_KEY
            ?? (await Promise.resolve().then(() => __importStar(require("firebase-functions"))).then((f) => f.config().algolia?.admin_key));
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
            v2_1.logger.warn(`[postDeletionCascade] Algolia delete returned ${response.status} for post ${postId}`);
        }
    }
    catch (err) {
        // Non-fatal: Algolia record may already be absent or index may not exist yet.
        v2_1.logger.warn(`[postDeletionCascade] Algolia removal failed for post ${postId}:`, err);
    }
}
/**
 * Deletes all Storage objects referenced by a post's media URLs.
 * Accepts gs:// URIs or https://firebasestorage.googleapis.com/... URLs.
 */
async function deleteStorageMedia(mediaURLs) {
    if (!mediaURLs || mediaURLs.length === 0)
        return;
    const bucket = admin.storage().bucket();
    await Promise.allSettled(mediaURLs.map(async (url) => {
        try {
            let filePath;
            if (url.startsWith("gs://")) {
                // gs://bucket-name/path/to/file
                filePath = url.replace(/^gs:\/\/[^/]+\//, "");
            }
            else {
                // https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encoded-path}?...
                const match = url.match(/\/o\/([^?]+)/);
                if (!match)
                    return;
                filePath = decodeURIComponent(match[1]);
            }
            await bucket.file(filePath).delete({ ignoreNotFound: true });
            v2_1.logger.info(`[postDeletionCascade] Deleted storage file: ${filePath}`);
        }
        catch (err) {
            v2_1.logger.warn(`[postDeletionCascade] Failed to delete media ${url}:`, err);
        }
    }));
}
//# sourceMappingURL=postDeletionCascade.js.map