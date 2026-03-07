/**
 * ENHANCED Comment Notification Function with Threads-Style Grouping
 *
 * REPLACE the onCommentCreate function in pushNotifications.js with this version
 * to enable "X and Y others commented" aggregation.
 *
 * This matches the pattern used for onAmenCreate (lines 510-631).
 */

// ============================================================================
// ENHANCED COMMENT NOTIFICATIONS WITH AGGREGATION
// ============================================================================

exports.onCommentCreateGrouped = onDocumentCreated(
    {document: "posts/{postId}/comments/{commentId}"},
    async (event) => {
      const {postId} = event.params;
      const commentData = event.data.data();

      try {
        // Get post to find the author
        const postDoc = await db.collection("posts").doc(postId).get();
        const postData = postDoc.data();

        if (!postData) {
          console.log("⚠️ Post not found");
          return null;
        }

        const postAuthorId = postData.authorId || postData.userId;
        const commentAuthorId = commentData.userId || commentData.authorId;

        // ✅ SELF-ACTION SUPPRESSION: Don't notify if user comments on their own post
        if (postAuthorId === commentAuthorId) {
          console.log("🔕 Suppressing self-action: user commented on own post");
          return null;
        }

        // ✅ BLOCK/PRIVACY RULES: Check if user has blocked commenter
        const blockDoc = await db.collection("users")
            .doc(postAuthorId)
            .collection("blocked")
            .doc(commentAuthorId)
            .get();

        if (blockDoc.exists) {
          console.log("🚫 Blocking comment notification: user has blocked commenter");
          return null;
        }

        // Check if commenter has blocked post author
        const blockedByDoc = await db.collection("users")
            .doc(commentAuthorId)
            .collection("blocked")
            .doc(postAuthorId)
            .get();

        if (blockedByDoc.exists) {
          console.log("🚫 Blocking comment notification: commenter has blocked post author");
          return null;
        }

        // Get commenter's profile
        const commenterDoc = await db.collection("users").doc(commentAuthorId).get();
        const commenterData = commenterDoc.data();
        const commenterName = commenterData?.displayName ||
                              commenterData?.username ||
                              "Someone";

        const actorProfileImageURL = commenterData?.profileImageURL ||
                                     commenterData?.profilePictureURL ||
                                     "";

        // ✅ THREADS-STYLE GROUPING: Use grouped notification per post
        // This aggregates all comments on a post into "X and Y others commented"
        const groupedNotificationId = `comment_group_${postId}`;
        const notificationRef = db.collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .doc(groupedNotificationId);

        const existingNotif = await notificationRef.get();

        if (existingNotif.exists) {
          // ✅ UPDATE EXISTING GROUPED NOTIFICATION
          const existingData = existingNotif.data();
          const actors = existingData.actors || [];

          // Check if this user is already in the actors list
          const userExists = actors.some(actor => actor.id === commentAuthorId);

          if (!userExists) {
            // Add new actor to the beginning (most recent first)
            actors.unshift({
              id: commentAuthorId,
              name: commenterName,
              username: commenterData?.username || "",
              profileImageURL: actorProfileImageURL,
            });

            await notificationRef.update({
              actors: actors,
              actorCount: actors.length,
              actorId: commentAuthorId, // Most recent actor
              actorName: commenterName,
              actorUsername: commenterData?.username || "",
              actorProfileImageURL: actorProfileImageURL,
              commentText: commentData.text || commentData.content || "",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              read: false, // Mark as unread when new activity occurs
            });

            console.log(`✅ Updated grouped comment notification (${actors.length} commenters)`);
          } else {
            // User already commented - just update timestamp
            await notificationRef.update({
              commentText: commentData.text || commentData.content || "",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              read: false,
            });

            console.log(`✅ Updated existing comment from same user`);
          }
        } else {
          // ✅ CREATE NEW GROUPED NOTIFICATION
          const notification = {
            type: "comment",
            actorId: commentAuthorId,
            actorName: commenterName,
            actorUsername: commenterData?.username || "",
            actorProfileImageURL: actorProfileImageURL,
            postId: postId,
            commentText: commentData.text || commentData.content || "",
            userId: postAuthorId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            // Threads-style grouping fields
            actors: [{
              id: commentAuthorId,
              name: commenterName,
              username: commenterData?.username || "",
              profileImageURL: actorProfileImageURL,
            }],
            actorCount: 1,
          };

          await notificationRef.set(notification);
          console.log(`✅ Created new grouped comment notification`);
        }

        // ✅ PREFERENCE CHECK: Only send push if enabled
        await sendPushNotificationToUser(
            postAuthorId,
            "New Comment",
            `${commenterName} commented on your post`,
            {
              type: "comment",
              actorId: commentAuthorId,
              postId: postId,
            },
            "comment", // Notification type for preference check
        );

        return null;
      } catch (error) {
        console.error("❌ Error in onCommentCreateGrouped:", error);
        return null;
      }
    },
);

// ============================================================================
// COMMENT DELETION HANDLER (removes from grouped notification)
// ============================================================================

exports.onCommentDelete = onDocumentDeleted(
    {document: "posts/{postId}/comments/{commentId}"},
    async (event) => {
      const {postId} = event.params;
      const commentData = event.data.data();

      try {
        // Get post author
        const postDoc = await db.collection("posts").doc(postId).get();
        const postData = postDoc.data();

        if (!postData) return null;

        const postAuthorId = postData.authorId || postData.userId;
        const commentAuthorId = commentData.userId || commentData.authorId;

        // ✅ THREADS-STYLE GROUPING: Remove user from grouped notification
        const groupedNotificationId = `comment_group_${postId}`;
        const notificationRef = db.collection("users")
            .doc(postAuthorId)
            .collection("notifications")
            .doc(groupedNotificationId);

        const existingNotif = await notificationRef.get();

        if (existingNotif.exists) {
          const existingData = existingNotif.data();
          const actors = existingData.actors || [];

          // Remove this user from actors list
          const updatedActors = actors.filter(actor => actor.id !== commentAuthorId);

          if (updatedActors.length === 0) {
            // No more actors - delete the notification
            await notificationRef.delete();
            console.log(`✅ Deleted grouped comment notification (no more commenters)`);
          } else {
            // Update with remaining actors
            const mostRecentActor = updatedActors[0];
            await notificationRef.update({
              actors: updatedActors,
              actorCount: updatedActors.length,
              actorId: mostRecentActor.id,
              actorName: mostRecentActor.name,
              actorUsername: mostRecentActor.username || "",
              actorProfileImageURL: mostRecentActor.profileImageURL || "",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ Updated grouped comment notification (${updatedActors.length} commenters remaining)`);
          }
        }

        console.log(`✅ Processed comment deletion for ${postAuthorId}`);

        return null;
      } catch (error) {
        console.error("❌ Error in onCommentDelete:", error);
        return null;
      }
    },
);

/**
 * DEPLOYMENT INSTRUCTIONS:
 *
 * 1. Replace the onCommentCreate function in pushNotifications.js with onCommentCreateGrouped
 * 2. Add the onCommentDelete handler
 * 3. Update index.js exports:
 *    - exports.onCommentCreate = onCommentCreateGrouped;
 *    - exports.onCommentDelete = onCommentDelete;
 * 4. Deploy: firebase deploy --only functions
 *
 * RESULT: Comments will now group like "Alex and 3 others commented on your post"
 */
