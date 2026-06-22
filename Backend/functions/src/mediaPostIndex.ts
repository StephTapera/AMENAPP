/**
 * mediaPostIndex.ts
 *
 * Maintains the denormalized users/{authorId}/mediaPosts/{postId} index.
 * This powers the "Photos & Videos" profile tab with cheap paginated reads
 * instead of expensive collection-group scans over all posts.
 *
 * Triggers:
 *   onMediaPostCreate  — posts/{postId} created with media → write index doc
 *   onMediaPostUpdate  — posts/{postId} updated → sync index (visibility,
 *                        moderation, attachments, media changes)
 *   onMediaPostDelete  — posts/{postId} deleted → remove index doc
 *
 * Schema written to users/{authorId}/mediaPosts/{postId}:
 *   postId          string   — mirrors document ID for client convenience
 *   authorId        string   — owner UID
 *   visibility      string   — "everyone" | "followers" | "community"
 *   mediaItems      array    — lightweight media entries (id, type, url,
 *                              thumbnailURL, aspectRatio, order)
 *   primaryThumbnailURL string  — first media item thumbnail or url
 *   primaryMediaType    string  — "image" | "video"
 *   mediaCount      number   — total media items
 *   isCarousel      boolean  — mediaCount > 1
 *   caption         string   — post content (caption), max 280 chars
 *   verseReference  string?  — attached scripture reference
 *   churchNoteId    string?  — attached church note ID
 *   isChurchShare   boolean  — whether post is a church share
 *   sharedChurchId  string?  — church ID if isChurchShare
 *   category        string   — post category
 *   createdAt       Timestamp
 *   updatedAt       Timestamp
 *   isHidden        boolean  — true when moderation removes it from grid
 *   moderationState string   — "clean" | "flagged" | "removed" | "quarantined"
 *   status          string   — "published" | "publishing" | "draft"
 */

import {
    onDocumentCreated,
    onDocumentUpdated,
    onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface MediaItemSnapshot {
    id: string;
    type: "image" | "video";
    url: string;
    thumbnailURL?: string | null;
    frameCaption?: string | null;
    featuredFrameTime?: number | null;
    isFeaturedFrame?: boolean;
    aspectRatio?: number | null;
    order: number;
    duration?: number | null;
    width?: number | null;
    height?: number | null;
}

interface MediaIndexDoc {
    postId: string;
    authorId: string;
    visibility: string;
    mediaItems: MediaItemSnapshot[];
    primaryThumbnailURL: string;
    primaryMediaType: string;
    mediaCount: number;
    isCarousel: boolean;
    caption: string;
    verseReference: string | null;
    churchNoteId: string | null;
    isChurchShare: boolean;
    sharedChurchId: string | null;
    category: string;
    createdAt: admin.firestore.Timestamp | null;
    updatedAt: admin.firestore.FieldValue;
    isHidden: boolean;
    moderationState: string;
    status: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Extracts the canonical media items array from a post document.
 * Handles both the modern `mediaItems` array (PostMediaItem schema) and the
 * legacy `imageURLs` string array for backwards compatibility.
 */
function extractMediaItems(data: admin.firestore.DocumentData): MediaItemSnapshot[] {
    // Modern schema: mediaItems array
    if (Array.isArray(data.mediaItems) && data.mediaItems.length > 0) {
        return (data.mediaItems as Record<string, unknown>[]).map((item, i) => ({
            id: (item.id as string) || `item_${i}`,
            type: (item.type as "image" | "video") || "image",
            url: (item.url as string) || "",
            thumbnailURL: (item.thumbnailURL as string) || null,
            frameCaption: ((item.frameCaptionMetadata as Record<string, unknown> | undefined)?.text as string) || (item.frameCaption as string) || null,
            featuredFrameTime: typeof item.featuredFrameTime === "number" ? item.featuredFrameTime : null,
            isFeaturedFrame: item.isFeaturedFrame === true,
            aspectRatio: typeof item.aspectRatio === "number" ? item.aspectRatio : null,
            order: typeof item.order === "number" ? item.order : i,
            duration: typeof item.duration === "number" ? item.duration : null,
            width: typeof item.width === "number" ? item.width : null,
            height: typeof item.height === "number" ? item.height : null,
        }));
    }

    // Legacy schema: imageURLs string array
    if (Array.isArray(data.imageURLs) && data.imageURLs.length > 0) {
        return (data.imageURLs as string[]).map((url, i) => ({
            id: `legacy_${i}`,
            type: "image" as const,
            url,
            thumbnailURL: url,
            aspectRatio: null,
            order: i,
            duration: null,
            width: null,
            height: null,
        }));
    }

    return [];
}

/**
 * Returns true when the post has at least one media item.
 */
function postHasMedia(data: admin.firestore.DocumentData): boolean {
    return extractMediaItems(data).length > 0;
}

/**
 * Derives the moderation state and hidden flag from post document fields.
 * Only server-managed fields (set by Cloud Functions / admin SDK) are trusted.
 */
function deriveModerationState(data: admin.firestore.DocumentData): {
    isHidden: boolean;
    moderationState: string;
} {
    const removed = data.removed === true;
    const flagged = data.flaggedForReview === true;
    const quarantined = data.quarantined === true;

    if (removed) return { isHidden: true, moderationState: "removed" };
    if (quarantined) return { isHidden: true, moderationState: "quarantined" };
    if (flagged) return { isHidden: false, moderationState: "flagged" };
    return { isHidden: false, moderationState: "clean" };
}

/**
 * Builds the index document from a raw post document snapshot.
 */
function buildIndexDoc(
    postId: string,
    data: admin.firestore.DocumentData
): MediaIndexDoc | null {
    const mediaItems = extractMediaItems(data);
    if (mediaItems.length === 0) return null;

    const sortedItems = [...mediaItems].sort((a, b) => a.order - b.order);
    const primary = sortedItems.find((item) => item.isFeaturedFrame || item.featuredFrameTime != null) ?? sortedItems[0];
    const { isHidden, moderationState } = deriveModerationState(data);

    // Caption capped at 280 chars for index storage efficiency
    const caption = typeof data.content === "string"
        ? data.content.slice(0, 280)
        : "";

    return {
        postId,
        authorId: data.authorId as string,
        visibility: (data.visibility as string) || "everyone",
        mediaItems: sortedItems,
        primaryThumbnailURL: primary.thumbnailURL || primary.url,
        primaryMediaType: primary.type,
        mediaCount: sortedItems.length,
        isCarousel: sortedItems.length > 1,
        caption,
        verseReference: (data.verseReference as string) || null,
        churchNoteId: (data.churchNoteId as string) || null,
        isChurchShare: data.isChurchShare === true,
        sharedChurchId: (data.sharedChurchId as string) || null,
        category: (data.category as string) || "general",
        createdAt: (data.createdAt as admin.firestore.Timestamp) || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        isHidden,
        moderationState,
        status: (data.status as string) || "published",
    };
}

/**
 * Returns the mediaPosts subcollection reference for a given author.
 */
function mediaPostRef(
    authorId: string,
    postId: string
): admin.firestore.DocumentReference {
    return db
        .collection("users")
        .doc(authorId)
        .collection("mediaPosts")
        .doc(postId);
}

// ---------------------------------------------------------------------------
// Trigger: Post Created
// ---------------------------------------------------------------------------

export const onMediaPostCreate = onDocumentCreated(
    "posts/{postId}",
    async (event) => {
        const postId = event.params.postId;
        const data = event.data?.data();
        if (!data) return;

        if (!postHasMedia(data)) return;

        // Only index published or publishing posts (not drafts)
        const status = (data.status as string) || "published";
        if (status === "draft") return;

        const authorId = data.authorId as string;
        if (!authorId) {
            logger.warn(`onMediaPostCreate: post ${postId} has no authorId`);
            return;
        }

        const indexDoc = buildIndexDoc(postId, data);
        if (!indexDoc) return;

        try {
            await mediaPostRef(authorId, postId).set(indexDoc);
            logger.info(`mediaPostIndex: created index for post ${postId} (author ${authorId})`);
        } catch (err) {
            logger.error(`mediaPostIndex: failed to create index for post ${postId}`, err);
        }
    }
);

// ---------------------------------------------------------------------------
// Trigger: Post Updated
// ---------------------------------------------------------------------------

export const onMediaPostUpdate = onDocumentUpdated(
    "posts/{postId}",
    async (event) => {
        const postId = event.params.postId;
        const before = event.data?.before?.data();
        const after = event.data?.after?.data();
        if (!before || !after) return;

        const authorId = after.authorId as string;
        if (!authorId) return;

        const afterHasMedia = postHasMedia(after);
        const ref = mediaPostRef(authorId, postId);

        // Post lost all media → remove from index
        if (!afterHasMedia) {
            const existing = await ref.get();
            if (existing.exists) {
                await ref.delete();
                logger.info(`mediaPostIndex: removed (no media) post ${postId}`);
            }
            return;
        }

        // Post became a draft → remove from index
        const status = (after.status as string) || "published";
        if (status === "draft") {
            const existing = await ref.get();
            if (existing.exists) {
                await ref.delete();
                logger.info(`mediaPostIndex: removed (draft) post ${postId}`);
            }
            return;
        }

        const indexDoc = buildIndexDoc(postId, after);
        if (!indexDoc) return;

        try {
            await ref.set(indexDoc, { merge: false });
            logger.info(`mediaPostIndex: updated index for post ${postId}`);
        } catch (err) {
            logger.error(`mediaPostIndex: failed to update index for post ${postId}`, err);
        }
    }
);

// ---------------------------------------------------------------------------
// Trigger: Post Deleted
// ---------------------------------------------------------------------------

export const onMediaPostDelete = onDocumentDeleted(
    "posts/{postId}",
    async (event) => {
        const postId = event.params.postId;
        const data = event.data?.data();
        if (!data) return;

        const authorId = data.authorId as string;
        if (!authorId) return;

        if (!postHasMedia(data)) return;

        try {
            await mediaPostRef(authorId, postId).delete();
            logger.info(`mediaPostIndex: deleted index for post ${postId}`);
        } catch (err) {
            // Document may already be absent — not an error worth rethrowing
            logger.warn(`mediaPostIndex: could not delete index for post ${postId}`, err);
        }
    }
);
