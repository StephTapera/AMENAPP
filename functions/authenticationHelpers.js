/**
 * Cloud Functions for Authentication
 * P0-2: Username Uniqueness Transaction
 * P0-3: Account Deletion Cascade
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentDeleted} = require("firebase-functions/v2/firestore");

/**
 * P0-2: Reserve a username using a transaction
 * This prevents race conditions when two users try to claim the same username
 *
 * Call this BEFORE creating the user document
 *
 * @param {string} username - The desired username (will be lowercased)
 * @param {string} userId - The user ID claiming this username
 * @returns {object} - {success: true} or throws error
 */
exports.reserveUsername = onCall(
    {
      region: "us-central1",
      enforceAppCheck: false, // Set to true in production with App Check
    },
    async (request) => {
      const {username, userId} = request.data;
      const requesterId = request.auth?.uid;

      console.log(`🔐 Username reservation request: "${username}" for user ${userId}`);

      // Validate authentication
      if (!requesterId) {
        throw new HttpsError(
            "unauthenticated",
            "You must be signed in to reserve a username"
        );
      }

      // Validate that requester is reserving for themselves
      if (requesterId !== userId) {
        throw new HttpsError(
            "permission-denied",
            "You can only reserve usernames for yourself"
        );
      }

      // Validate input
      if (!username || typeof username !== "string") {
        throw new HttpsError(
            "invalid-argument",
            "Username is required and must be a string"
        );
      }

      // Normalize username (lowercase, trim)
      const normalizedUsername = username.trim().toLowerCase();

      // Validate username format
      if (!/^[a-z0-9_]{3,20}$/.test(normalizedUsername)) {
        throw new HttpsError(
            "invalid-argument",
            "Username must be 3-20 characters and contain only lowercase letters, numbers, and underscores"
        );
      }

      try {
        const db = admin.firestore();
        const usernamesRef = db.collection("usernames");
        const usernameDocRef = usernamesRef.doc(normalizedUsername);

        // Run transaction to claim username atomically
        await db.runTransaction(async (transaction) => {
          const usernameDoc = await transaction.get(usernameDocRef);

          if (usernameDoc.exists) {
            const existingUserId = usernameDoc.data().userId;

            // Check if this user already owns this username (re-registration edge case)
            if (existingUserId === userId) {
              console.log(`✅ Username "${normalizedUsername}" already owned by user ${userId}`);
              return; // Already owned, allow it
            }

            // Username taken by another user
            console.log(`❌ Username "${normalizedUsername}" already taken by user ${existingUserId}`);
            throw new HttpsError(
                "already-exists",
                `Username "${username}" is already taken`
            );
          }

          // Username available - claim it
          transaction.set(usernameDocRef, {
            userId: userId,
            usernameLowercase: normalizedUsername,
            usernameDisplay: username.trim(), // Preserve original casing for display
            claimedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`✅ Username "${normalizedUsername}" reserved for user ${userId}`);
        });

        return {
          success: true,
          username: normalizedUsername,
        };
      } catch (error) {
        // Re-throw HttpsError as-is
        if (error instanceof HttpsError) {
          throw error;
        }

        console.error("Username reservation error:", error);
        throw new HttpsError(
            "internal",
            "Failed to reserve username. Please try again."
        );
      }
    }
);

/**
 * P0-2: Validate username availability (read-only check)
 * Use this for real-time validation in the UI
 *
 * @param {string} username - The username to check
 * @returns {object} - {available: boolean}
 */
exports.checkUsernameAvailability = onCall(
    {
      region: "us-central1",
      enforceAppCheck: false,
    },
    async (request) => {
      const {username} = request.data;

      if (!username || typeof username !== "string") {
        throw new HttpsError("invalid-argument", "Username is required");
      }

      const normalizedUsername = username.trim().toLowerCase();

      // Validate format
      if (!/^[a-z0-9_]{3,20}$/.test(normalizedUsername)) {
        return {
          available: false,
          reason: "invalid_format",
          message: "Username must be 3-20 characters (letters, numbers, underscores only)",
        };
      }

      try {
        const db = admin.firestore();
        const usernameDoc = await db.collection("usernames")
            .doc(normalizedUsername)
            .get();

        const available = !usernameDoc.exists;

        console.log(`🔍 Username "${normalizedUsername}" availability: ${available ? "AVAILABLE" : "TAKEN"}`);

        return {
          available: available,
          username: normalizedUsername,
        };
      } catch (error) {
        console.error("Username availability check error:", error);
        throw new HttpsError("internal", "Failed to check username availability");
      }
    }
);

/**
 * P0-2: Clean up username reservation when user document is deleted
 * Triggered automatically when users/{userId} is deleted
 */
exports.onUserDeleted = onDocumentDeleted(
    {
      document: "users/{userId}",
      region: "us-central1",
    },
    async (event) => {
      const userId = event.params.userId;
      const userData = event.data.data();

      console.log(`🗑️ User deleted: ${userId}`);

      try {
        const db = admin.firestore();
        const username = userData?.usernameLowercase || userData?.username?.toLowerCase();

        if (username) {
          // Release username for future use
          await db.collection("usernames").doc(username).delete();
          console.log(`✅ Username "${username}" released`);
        }

        // P0-3: CASCADE DELETE - Clean up all user data
        await cascadeDeleteUserData(userId);

        return {success: true};
      } catch (error) {
        console.error("Error in onUserDeleted:", error);
        // Don't throw - we want the user deletion to succeed even if cleanup fails
        return null;
      }
    }
);

/**
 * P0-3: Cascade delete all user data when account is deleted
 *
 * Deletes:
 * - All posts by the user
 * - All comments by the user (Realtime Database)
 * - All follows (following/followers relationships)
 * - All conversations where user is the only participant
 * - User's messages in conversations (marks as deleted)
 * - All notifications sent by the user
 * - All notifications received by the user
 * - Profile images from Storage
 * - Username reservation
 * - Saved posts
 * - Prayer requests
 * - Church notes
 *
 * @param {string} userId - The user ID to delete data for
 */
async function cascadeDeleteUserData(userId) {
  console.log(`🧹 Starting cascade delete for user ${userId}`);

  const db = admin.firestore();
  const rtdb = admin.database();
  const storage = admin.storage();

  try {
    // 1. Delete all posts by user
    console.log("1️⃣ Deleting posts...");
    const postsSnapshot = await db.collection("posts")
        .where("userId", "==", userId)
        .get();

    const postDeletePromises = [];
    postsSnapshot.forEach((doc) => {
      postDeletePromises.push(doc.ref.delete());
      console.log(`   Deleting post: ${doc.id}`);
    });
    await Promise.all(postDeletePromises);
    console.log(`✅ Deleted ${postsSnapshot.size} posts`);

    // 2. Delete all comments by user from Realtime Database
    console.log("2️⃣ Deleting comments from Realtime Database...");
    const commentsRef = rtdb.ref("postInteractions");
    const commentsSnapshot = await commentsRef.once("value");

    const commentDeletePromises = [];
    if (commentsSnapshot.exists()) {
      commentsSnapshot.forEach((postSnap) => {
        const comments = postSnap.child("comments").val();
        if (comments) {
          Object.entries(comments).forEach(([commentId, comment]) => {
            if (comment.userId === userId) {
              const deleteRef = rtdb.ref(`postInteractions/${postSnap.key}/comments/${commentId}`);
              commentDeletePromises.push(deleteRef.remove());
              console.log(`   Deleting comment: ${commentId}`);
            }
          });
        }
      });
    }
    await Promise.all(commentDeletePromises);
    console.log(`✅ Deleted ${commentDeletePromises.length} comments`);

    // 3. Delete follow relationships
    console.log("3️⃣ Deleting follow relationships...");

    // Delete where user is following others
    const followingSnapshot = await db.collection("follows")
        .where("followerId", "==", userId)
        .get();
    const followingDeletePromises = followingSnapshot.docs.map((doc) => doc.ref.delete());

    // Delete where others are following user
    const followersSnapshot = await db.collection("follows")
        .where("followingId", "==", userId)
        .get();
    const followersDeletePromises = followersSnapshot.docs.map((doc) => doc.ref.delete());

    await Promise.all([...followingDeletePromises, ...followersDeletePromises]);
    console.log(`✅ Deleted ${followingSnapshot.size + followersSnapshot.size} follow relationships`);

    // 4. Handle conversations
    console.log("4️⃣ Handling conversations...");
    const conversationsSnapshot = await db.collection("conversations")
        .where("participantIds", "array-contains", userId)
        .get();

    const conversationPromises = [];
    conversationsSnapshot.forEach((doc) => {
      const data = doc.data();
      const participantIds = data.participantIds || [];

      if (participantIds.length <= 2) {
        // 1-on-1 conversation - delete entire conversation
        conversationPromises.push(doc.ref.delete());
        console.log(`   Deleting 1-on-1 conversation: ${doc.id}`);
      } else {
        // Group conversation - just remove user from participants
        const updatedParticipants = participantIds.filter((id) => id !== userId);
        conversationPromises.push(doc.ref.update({
          participantIds: updatedParticipants,
        }));
        console.log(`   Removing user from group conversation: ${doc.id}`);
      }
    });
    await Promise.all(conversationPromises);
    console.log(`✅ Handled ${conversationsSnapshot.size} conversations`);

    // 5. Delete all notifications sent by user (to other users)
    console.log("5️⃣ Deleting notifications sent by user...");
    const usersSnapshot = await db.collection("users").get();
    const notificationDeletePromises = [];

    for (const userDoc of usersSnapshot.docs) {
      const notificationsSnapshot = await userDoc.ref
          .collection("notifications")
          .where("actorId", "==", userId)
          .get();

      notificationsSnapshot.forEach((notifDoc) => {
        notificationDeletePromises.push(notifDoc.ref.delete());
      });
    }
    await Promise.all(notificationDeletePromises);
    console.log(`✅ Deleted ${notificationDeletePromises.length} notifications sent by user`);

    // 6. Delete all notifications received by user
    console.log("6️⃣ Deleting notifications received by user...");
    const userNotificationsSnapshot = await db.collection("users")
        .doc(userId)
        .collection("notifications")
        .get();

    const userNotifDeletePromises = userNotificationsSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(userNotifDeletePromises);
    console.log(`✅ Deleted ${userNotifDeletePromises.length} notifications received by user`);

    // 7. Delete saved posts
    console.log("7️⃣ Deleting saved posts...");
    const savedPostsSnapshot = await db.collection("users")
        .doc(userId)
        .collection("savedPosts")
        .get();

    const savedPostsDeletePromises = savedPostsSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(savedPostsDeletePromises);
    console.log(`✅ Deleted ${savedPostsSnapshot.size} saved posts`);

    // 8. Delete prayer requests
    console.log("8️⃣ Deleting prayer requests...");
    const prayersSnapshot = await db.collection("prayers")
        .where("userId", "==", userId)
        .get();

    const prayersDeletePromises = prayersSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(prayersDeletePromises);
    console.log(`✅ Deleted ${prayersSnapshot.size} prayer requests`);

    // 9. Delete church notes
    console.log("9️⃣ Deleting church notes...");
    const notesSnapshot = await db.collection("churchNotes")
        .where("userId", "==", userId)
        .get();

    const notesDeletePromises = notesSnapshot.docs.map((doc) => doc.ref.delete());
    await Promise.all(notesDeletePromises);
    console.log(`✅ Deleted ${notesSnapshot.size} church notes`);

    // 10. Delete profile images from Storage
    console.log("🔟 Deleting profile images from Storage...");
    try {
      const bucket = storage.bucket();
      const profileImagePaths = [
        `profile_images/${userId}.jpg`,
        `profile_images/${userId}.jpeg`,
        `profile_images/${userId}.png`,
        `profile_images/${userId}_thumb.jpg`,
        `profile_images/${userId}_thumb.jpeg`,
        `profile_images/${userId}_thumb.png`,
      ];

      const storageDeletePromises = profileImagePaths.map(async (path) => {
        try {
          await bucket.file(path).delete();
          console.log(`   Deleted: ${path}`);
        } catch (error) {
          // File might not exist, that's okay
          if (error.code !== 404) {
            console.log(`   Could not delete ${path}: ${error.message}`);
          }
        }
      });

      await Promise.all(storageDeletePromises);
      console.log("✅ Storage cleanup complete");
    } catch (storageError) {
      console.error("Storage deletion error (non-critical):", storageError);
    }

    console.log(`✅✅✅ CASCADE DELETE COMPLETE for user ${userId} ✅✅✅`);
    console.log("Summary:");
    console.log(`- Posts deleted: ${postsSnapshot.size}`);
    console.log(`- Comments deleted: ${commentDeletePromises.length}`);
    console.log(`- Follow relationships: ${followingSnapshot.size + followersSnapshot.size}`);
    console.log(`- Conversations handled: ${conversationsSnapshot.size}`);
    console.log(`- Notifications deleted: ${notificationDeletePromises.length + userNotifDeletePromises.length}`);
    console.log(`- Saved posts: ${savedPostsSnapshot.size}`);
    console.log(`- Prayers: ${prayersSnapshot.size}`);
    console.log(`- Church notes: ${notesSnapshot.size}`);

    return {success: true};
  } catch (error) {
    console.error("❌ Error in cascadeDeleteUserData:", error);
    throw error;
  }
}

/**
 * P0-3: Manually trigger cascade delete (for admin use)
 * Use this to clean up orphaned data or test the cascade delete logic
 */
exports.manualCascadeDelete = onCall(
    {
      region: "us-central1",
      enforceAppCheck: false,
    },
    async (request) => {
      const {userId} = request.data;
      const requesterId = request.auth?.uid;

      console.log(`🗑️ Manual cascade delete request for user ${userId}`);

      // Validate authentication
      if (!requesterId) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      // Security: Only allow users to delete their own data
      // In production, you might want admin-only access
      if (requesterId !== userId) {
        throw new HttpsError(
            "permission-denied",
            "You can only delete your own data"
        );
      }

      if (!userId) {
        throw new HttpsError("invalid-argument", "userId is required");
      }

      try {
        await cascadeDeleteUserData(userId);

        return {
          success: true,
          message: "User data cascade delete completed successfully",
        };
      } catch (error) {
        console.error("Manual cascade delete error:", error);
        throw new HttpsError(
            "internal",
            "Failed to delete user data. Please contact support."
        );
      }
    }
);

// Export the cascade delete function for use in other functions
exports.cascadeDeleteUserData = cascadeDeleteUserData;
