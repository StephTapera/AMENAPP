/**
 * Cloud Functions for Church Notes Sharing
 * P0-4: Server-side share permission validation
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

/**
 * Share a church note with specific users
 * Validates ownership before allowing share
 */
exports.shareChurchNote = onCall(
    {
      region: "us-central1",
      enforceAppCheck: false, // Set to true in production with App Check
    },
    async (request) => {
      const {noteId, recipientUserIds} = request.data;
      const shareerId = request.auth?.uid;

      console.log(`📤 Share request for note ${noteId} from user ${shareerId}`);

      // Validate authentication
      if (!shareerId) {
        throw new HttpsError(
            "unauthenticated",
            "You must be signed in to share notes"
        );
      }

      // Validate input
      if (!noteId || !Array.isArray(recipientUserIds) || recipientUserIds.length === 0) {
        throw new HttpsError(
            "invalid-argument",
            "Invalid noteId or recipient list"
        );
      }

      // Rate limiting: max 20 shares per minute
      const rateLimitKey = `share_note:${shareerId}`;
      const rateLimitRef = admin.database().ref(`rateLimits/${rateLimitKey}`);

      try {
        const snapshot = await rateLimitRef.once("value");
        const count = snapshot.val() || 0;

        if (count >= 20) {
          throw new HttpsError(
              "resource-exhausted",
              "Too many share requests. Please wait a moment."
          );
        }

        // Increment and expire after 60 seconds
        await rateLimitRef.set(count + 1);
        await rateLimitRef.onDisconnect().remove();
        setTimeout(() => rateLimitRef.remove(), 60000);
      } catch (error) {
        console.error("Rate limit check failed:", error);
      }

      try {
        const db = admin.firestore();
        const noteRef = db.collection("churchNotes").doc(noteId);
        const noteDoc = await noteRef.get();

        // Validate note exists
        if (!noteDoc.exists) {
          throw new HttpsError(
              "not-found",
              "Note not found"
          );
        }

        const noteData = noteDoc.data();

        // Validate ownership - only note owner can share
        if (noteData.userId !== shareerId) {
          console.log(`⚠️ Unauthorized share attempt: note owner=${noteData.userId}, requester=${shareerId}`);
          throw new HttpsError(
              "permission-denied",
              "You can only share your own notes"
          );
        }

        // Validate recipients exist and aren't blocked
        const validRecipients = [];
        for (const recipientId of recipientUserIds) {
          const userDoc = await db.collection("users").doc(recipientId).get();

          if (!userDoc.exists) {
            console.log(`⚠️ Skipping non-existent user: ${recipientId}`);
            continue;
          }

          // Check if sharer is blocked by recipient
          const blockDoc = await db.collection("blocks")
              .where("blockerId", "==", recipientId)
              .where("blockedUserId", "==", shareerId)
              .limit(1)
              .get();

          if (!blockDoc.empty) {
            console.log(`⚠️ Skipping blocked user: ${recipientId}`);
            continue;
          }

          validRecipients.push(recipientId);
        }

        if (validRecipients.length === 0) {
          throw new HttpsError(
              "failed-precondition",
              "No valid recipients found"
          );
        }

        // Update note with shared users (use union to prevent duplicates)
        await noteRef.update({
          sharedWith: admin.firestore.FieldValue.arrayUnion(...validRecipients),
          permission: "shared",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`✅ Note ${noteId} shared with ${validRecipients.length} users`);

        // Send notifications to recipients
        const sharerDoc = await db.collection("users").doc(shareerId).get();
        const sharerData = sharerDoc.data();
        const sharerName = sharerData?.displayName || "Someone";
        const noteTitle = noteData.title || "Untitled Note";

        for (const recipientId of validRecipients) {
          // Create notification
          await db.collection("users")
              .doc(recipientId)
              .collection("notifications")
              .add({
                type: "church_note_shared",
                actorId: shareerId,
                actorName: sharerName,
                actorUsername: sharerData?.username || "",
                actorProfileImageURL: sharerData?.profileImageURL || "",
                noteId: noteId,
                noteTitle: noteTitle,
                userId: recipientId,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });

          // Send push notification
          const recipientDoc = await db.collection("users").doc(recipientId).get();
          const fcmToken = recipientDoc.data()?.fcmToken;

          if (fcmToken) {
            try {
              await admin.messaging().send({
                notification: {
                  title: "Church Note Shared",
                  body: `${sharerName} shared "${noteTitle}" with you`,
                },
                data: {
                  type: "church_note_shared",
                  actorId: shareerId,
                  noteId: noteId,
                },
                token: fcmToken,
              });
              console.log(`✅ Push notification sent to ${recipientId}`);
            } catch (pushError) {
              console.error(`Failed to send push to ${recipientId}:`, pushError);
            }
          }
        }

        return {
          success: true,
          sharedWithCount: validRecipients.length,
          sharedWith: validRecipients,
        };
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }

        console.error("Share note error:", error);
        throw new HttpsError(
            "internal",
            "Failed to share note. Please try again."
        );
      }
    }
);

/**
 * Revoke share access for a church note
 */
exports.revokeChurchNoteShare = onCall(
    {
      region: "us-central1",
      enforceAppCheck: false,
    },
    async (request) => {
      const {noteId, userIds} = request.data;
      const ownerId = request.auth?.uid;

      if (!ownerId) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      if (!noteId || !Array.isArray(userIds)) {
        throw new HttpsError("invalid-argument", "Invalid parameters");
      }

      try {
        const db = admin.firestore();
        const noteRef = db.collection("churchNotes").doc(noteId);
        const noteDoc = await noteRef.get();

        if (!noteDoc.exists) {
          throw new HttpsError("not-found", "Note not found");
        }

        const noteData = noteDoc.data();

        // Validate ownership
        if (noteData.userId !== ownerId) {
          throw new HttpsError(
              "permission-denied",
              "You can only revoke access to your own notes"
          );
        }

        // Remove users from sharedWith array
        await noteRef.update({
          sharedWith: admin.firestore.FieldValue.arrayRemove(...userIds),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // If no users remain, set permission back to private
        const updatedDoc = await noteRef.get();
        const updatedSharedWith = updatedDoc.data().sharedWith || [];

        if (updatedSharedWith.length === 0) {
          await noteRef.update({
            permission: "private",
          });
        }

        console.log(`✅ Revoked access to note ${noteId} for ${userIds.length} users`);

        return {
          success: true,
          revokedCount: userIds.length,
        };
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }

        console.error("Revoke share error:", error);
        throw new HttpsError("internal", "Failed to revoke access");
      }
    }
);

/**
 * Generate a shareable link for a church note
 */
exports.generateChurchNoteShareLink = onCall(
    {
      region: "us-central1",
      enforceAppCheck: false,
    },
    async (request) => {
      const {noteId} = request.data;
      const userId = request.auth?.uid;

      if (!userId) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      if (!noteId) {
        throw new HttpsError("invalid-argument", "Note ID required");
      }

      try {
        const db = admin.firestore();
        const noteRef = db.collection("churchNotes").doc(noteId);
        const noteDoc = await noteRef.get();

        if (!noteDoc.exists) {
          throw new HttpsError("not-found", "Note not found");
        }

        const noteData = noteDoc.data();

        // Validate ownership
        if (noteData.userId !== userId) {
          throw new HttpsError(
              "permission-denied",
              "You can only create share links for your own notes"
          );
        }

        // Generate or return existing share link ID
        let shareLinkId = noteData.shareLinkId;

        if (!shareLinkId) {
          shareLinkId = admin.firestore().collection("_").doc().id; // Generate unique ID
          await noteRef.update({
            shareLinkId: shareLinkId,
            permission: "shared", // Make it shareable
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        const shareUrl = `https://amenapp.com/notes/${shareLinkId}`;

        console.log(`✅ Generated share link for note ${noteId}: ${shareUrl}`);

        return {
          success: true,
          shareUrl: shareUrl,
          shareLinkId: shareLinkId,
        };
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }

        console.error("Generate share link error:", error);
        throw new HttpsError("internal", "Failed to generate share link");
      }
    }
);
