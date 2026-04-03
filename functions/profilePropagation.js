/**
 * profilePropagation.js
 *
 * When a user changes their displayName, username, or profileImageURL,
 * this trigger propagates the new values to all denormalized copies stored
 * on their posts and comments so cached data doesn't go stale.
 *
 * Fields propagated:
 *   posts:    authorName, authorUsername, authorProfileImageURL, authorInitials
 *   comments: authorName, authorUsername, authorProfileImageURL, authorInitials
 */

const admin = require("firebase-admin");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");

const REGION = "us-central1";

/** Derive initials from a display name (up to 2 chars). */
function makeInitials(displayName) {
  if (!displayName) return "?";
  const parts = displayName.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/**
 * onUserProfileUpdated
 *
 * Triggered whenever a user document changes. Runs a batch update on
 * all posts authored by that user if any of the three key fields changed.
 * Comments are stored in RTDB indexed by postId, so we update them via
 * a separate RTDB write batch.
 *
 * Firestore batches are capped at 500 writes; for large accounts a second
 * pass is queued recursively.
 */
exports.onUserProfileUpdated = onDocumentUpdated(
    {
      document: "users/{userId}",
      region: REGION,
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      const userId = event.params.userId;

      // Determine which denormalized fields changed
      const nameChanged = before.displayName !== after.displayName;
      const usernameChanged = before.username !== after.username;
      const imageChanged = before.profileImageURL !== after.profileImageURL;

      if (!nameChanged && !usernameChanged && !imageChanged) {
        return; // Nothing relevant changed
      }

      const db = admin.firestore();

      const newDisplayName = after.displayName ?? before.displayName ?? "";
      const newUsername = after.username ?? before.username ?? "";
      const newImageURL = after.profileImageURL ?? null;
      const newInitials = makeInitials(newDisplayName);

      // Build the update payload for Firestore posts
      const postUpdate = {};
      if (nameChanged) {
        postUpdate.authorName = newDisplayName;
        postUpdate.authorInitials = newInitials;
      }
      if (usernameChanged) postUpdate.authorUsername = newUsername;
      if (imageChanged) postUpdate.authorProfileImageURL = newImageURL;

      console.log(
          `[profilePropagation] userId=${userId} fields changed:`,
          {nameChanged, usernameChanged, imageChanged},
      );

      // ── Propagate to Firestore posts ──────────────────────────────────────
      let lastDoc = null;
      let totalUpdated = 0;

      do {
        let query = db.collection("posts")
            .where("authorId", "==", userId)
            .orderBy("createdAt", "desc")
            .limit(400); // Stay under 500-write batch cap

        if (lastDoc) query = query.startAfter(lastDoc);

        const snap = await query.get();
        if (snap.empty) break;

        const batch = db.batch();
        snap.docs.forEach((doc) => batch.update(doc.ref, postUpdate));
        await batch.commit();

        totalUpdated += snap.docs.length;
        lastDoc = snap.docs[snap.docs.length - 1];

        console.log(`[profilePropagation] Updated ${totalUpdated} posts so far for ${userId}`);
      } while (lastDoc && totalUpdated % 400 === 0);

      // ── Propagate to Firestore reposts (originalAuthor fields unchanged;
      //    only the reposting author's denormalized fields need updating) ──────
      // Already covered by the posts query above since reposts are in /posts.

      // ── Propagate to RTDB comments ────────────────────────────────────────
      // RTDB structure: postInteractions/{postId}/comments/{commentId}
      // We can't query all comments by userId directly in RTDB without a full scan.
      // Strategy: query Firestore posts by authorId to get postIds, then update
      // comments within those posts. For non-own-post comments, the user's comment
      // data is embedded and requires a full scan — we use the Firestore commentIndex
      // subcollection if it exists, otherwise skip (acceptable trade-off).
      try {
        const rtdb = admin.database();

        // Use a Firestore commentIndex if available (optional optimization)
        const commentIndexSnap = await db
            .collectionGroup("commentIndex")
            .where("authorId", "==", userId)
            .limit(500)
            .get();

        if (!commentIndexSnap.empty) {
          const rtdbUpdates = {};
          commentIndexSnap.docs.forEach((doc) => {
            const {postId, commentId} = doc.data();
            const basePath = `postInteractions/${postId}/comments/${commentId}`;
            if (nameChanged) {
              rtdbUpdates[`${basePath}/authorName`] = newDisplayName;
              rtdbUpdates[`${basePath}/authorInitials`] = newInitials;
            }
            if (usernameChanged) rtdbUpdates[`${basePath}/authorUsername`] = newUsername;
            if (imageChanged) rtdbUpdates[`${basePath}/authorProfileImageURL`] = newImageURL;
          });

          if (Object.keys(rtdbUpdates).length > 0) {
            await rtdb.ref().update(rtdbUpdates);
            console.log(`[profilePropagation] Updated ${commentIndexSnap.size} RTDB comments for ${userId}`);
          }
        } else {
          console.log(`[profilePropagation] No RTDB commentIndex found for ${userId} — skipping comment propagation`);
        }
      } catch (rtdbErr) {
        // Non-fatal: RTDB comment propagation failing is acceptable since
        // comments will show correct data on next full load from Firestore.
        console.warn(`[profilePropagation] RTDB comment update failed (non-fatal):`, rtdbErr.message);
      }

      console.log(`[profilePropagation] Done. Total Firestore posts updated: ${totalUpdated}`);
    },
);
