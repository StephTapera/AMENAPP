/**
 * algoliaSync.ts
 *
 * Keeps the Algolia "posts" index in sync with Firestore.
 *
 * WHY THIS EXISTS:
 *   onPostCreated.ts indexes new posts on creation. However, there is no
 *   corresponding update/delete sync. When a post is edited (content, privacy,
 *   status), the Algolia record becomes stale. When a post is deleted, the record
 *   lingers in the search index indefinitely — surfacing deleted content.
 *
 * Functions:
 *   algoliaPostUpdateSync — onUpdate trigger on posts/{postId}: patches changed fields
 *   algoliaPostDeleteSync — onDelete trigger on posts/{postId}: removes from index
 *
 * NOTE: Post deletion also calls removeFromAlgolia inside postDeletionCascade.
 * This function is an independent belt-and-suspenders handler for cases where the
 * post document is deleted directly (not through the app's deletion flow).
 */

import {
    onDocumentDeleted,
    onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";

const ALGOLIA_APP_ID = "182SCN7O9S";
const algoliaAdminKey = defineSecret("ALGOLIA_ADMIN_KEY");

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function algoliaRequest(
    method: string,
    path: string,
    apiKey: string,
    body?: unknown
): Promise<void> {
    if (!apiKey) {
        logger.warn("[algoliaSync] ALGOLIA_ADMIN_KEY not set — skipping");
        return;
    }

    const url = `https://${ALGOLIA_APP_ID}-dsn.algolia.net/1/indexes/${path}`;
    const response = await fetch(url, {
        method,
        headers: {
            "Content-Type": "application/json",
            "X-Algolia-Application-Id": ALGOLIA_APP_ID,
            "X-Algolia-API-Key": apiKey,
        },
        body: body ? JSON.stringify(body) : undefined,
    });

    if (!response.ok && response.status !== 404) {
        logger.warn(
            `[algoliaSync] ${method} ${path} returned ${response.status}`
        );
    }
}

// ─── Post Update Sync ─────────────────────────────────────────────────────────

/**
 * Patches the Algolia record when a post document is updated.
 * Only syncs fields that are search-relevant to minimize Algolia write units.
 */
export const algoliaPostUpdateSync = onDocumentUpdated(
    { document: "posts/{postId}", secrets: [algoliaAdminKey] },
    async (event) => {
        const postId = event.params.postId;
        const after = event.data?.after.data();
        const before = event.data?.before.data();

        if (!after) return;

        const searchFields = ["content", "text", "visibility", "status", "searchKeywords", "authorId"];
        const changed = searchFields.some((f) => JSON.stringify(before?.[f]) !== JSON.stringify(after[f]));
        if (!changed) return;

        const apiKey = algoliaAdminKey.value();

        if (after.status === "deleted" || after.status === "held" || after.visibility === "deleted") {
            await algoliaRequest("DELETE", `posts/${encodeURIComponent(postId)}`, apiKey);
            logger.info(`[algoliaSync] Removed hidden/deleted post ${postId} from Algolia`);
            return;
        }

        const record = {
            objectID: postId,
            content: after.content ?? after.text ?? "",
            authorId: after.authorId ?? after.userId ?? "",
            visibility: after.visibility ?? "public",
            status: after.status ?? "published",
            searchKeywords: after.searchKeywords ?? [],
            updatedAt: after.updatedAt?.toMillis?.() ?? Date.now(),
        };

        await algoliaRequest("PUT", `posts/${encodeURIComponent(postId)}`, apiKey, record);
        logger.info(`[algoliaSync] Updated Algolia record for post ${postId}`);
    }
);

// ─── Post Delete Sync ─────────────────────────────────────────────────────────

/**
 * Removes the post record from Algolia when the Firestore document is deleted.
 * Belt-and-suspenders alongside postDeletionCascade's Algolia removal.
 */
export const algoliaPostDeleteSync = onDocumentDeleted(
    { document: "posts/{postId}", secrets: [algoliaAdminKey] },
    async (event) => {
        const postId = event.params.postId;
        await algoliaRequest("DELETE", `posts/${encodeURIComponent(postId)}`, algoliaAdminKey.value());
        logger.info(`[algoliaSync] Removed deleted post ${postId} from Algolia`);
    }
);
