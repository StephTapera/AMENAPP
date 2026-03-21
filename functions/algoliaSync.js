"use strict";

/**
 * algoliaSync.js
 * P1 #7: Auto-sync posts to Algolia on create/update/delete.
 * Lazy-initializes Algolia client to avoid cold-start delays.
 */

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");

// Declare Algolia secrets so Firebase injects them into process.env at runtime
const ALGOLIA_APP_ID = defineSecret("ALGOLIA_APP_ID");
const ALGOLIA_ADMIN_API_KEY = defineSecret("ALGOLIA_ADMIN_API_KEY");
const ALGOLIA_INDEX_NAME = defineSecret("ALGOLIA_INDEX_NAME");

// Lazy-initialize Algolia client to avoid cold-start delays
let algoliaIndex = null;

function getAlgoliaIndex() {
  if (!algoliaIndex) {
    const algoliasearch = require("algoliasearch");
    // Algolia credentials stored in Firebase environment / Secret Manager
    const appId = process.env.ALGOLIA_APP_ID || "";
    const apiKey = process.env.ALGOLIA_ADMIN_API_KEY || "";
    const client = algoliasearch(appId, apiKey);
    algoliaIndex = client.initIndex(process.env.ALGOLIA_INDEX_NAME || "posts");
  }
  return algoliaIndex;
}

/**
 * Triggered when a new post is created in Firestore.
 * Indexes the post in Algolia unless it is deleted or private.
 */
exports.onPostCreatedSyncAlgolia = onDocumentCreated(
  { document: "posts/{postId}", secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY, ALGOLIA_INDEX_NAME] },
  async (event) => {
    try {
      const post = event.data.data();
      if (!post || post.isDeleted || post.privacy === "private") return;

      const index = getAlgoliaIndex();
      await index.saveObject({
        objectID: event.params.postId,
        text: post.text || post.content || "",
        authorId: post.authorId || "",
        authorName: post.authorName || "",
        authorUsername: post.authorUsername || "",
        createdAt: post.createdAt?.toMillis() || Date.now(),
        amenCount: post.amenCount || 0,
        commentCount: post.commentCount || 0,
        category: post.category || "general",
      });
      console.log(`✅ Algolia: indexed post ${event.params.postId}`);
    } catch (err) {
      console.error("❌ onPostCreatedSyncAlgolia error:", err.message);
    }
  }
);

/**
 * Triggered when a post document is updated.
 * Removes from index if deleted/private; partially updates otherwise.
 */
exports.onPostUpdatedSyncAlgolia = onDocumentUpdated(
  { document: "posts/{postId}", secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY, ALGOLIA_INDEX_NAME] },
  async (event) => {
    try {
      const post = event.data.after.data();
      if (!post) return;

      const index = getAlgoliaIndex();

      if (post.isDeleted) {
        // Remove from index on soft-delete
        await index.deleteObject(event.params.postId);
        console.log(`🗑️ Algolia: removed post ${event.params.postId}`);
        return;
      }

      if (post.privacy === "private") return;

      // Partial update — only sync user-editable + counter fields
      await index.partialUpdateObject({
        objectID: event.params.postId,
        text: post.text || post.content || "",
        amenCount: post.amenCount || 0,
        commentCount: post.commentCount || 0,
      });
      console.log(`♻️ Algolia: updated post ${event.params.postId}`);
    } catch (err) {
      console.error("❌ onPostUpdatedSyncAlgolia error:", err.message);
    }
  }
);
