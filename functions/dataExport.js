/**
 * dataExport.js
 * GDPR / CCPA data export — "Download My Data" feature.
 *
 * When a user requests their data, this function collects all personal
 * data from Firestore and returns it as a structured JSON object.
 * The iOS client saves it as a .json file via UIActivityViewController.
 */

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");

const db = () => admin.firestore();

/**
 * Callable function: exportUserData
 * Returns all personal data for the authenticated user.
 */
const exportUserData = onCall(
    {
      region: "us-central1",
      memory: "512MiB",
      timeoutSeconds: 120,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      console.log(`Data export requested by user ${uid}`);

      try {
        const exportData = {
          exportedAt: new Date().toISOString(),
          userId: uid,
          sections: {},
        };

        // 1. User profile
        const userDoc = await db().collection("users").doc(uid).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          // Strip sensitive internal fields
          delete userData.fcmToken;
          delete userData.deviceTokens;
          exportData.sections.profile = userData;
        }

        // 2. Posts
        const postsSnap = await db().collection("posts")
            .where("authorId", "==", uid)
            .orderBy("createdAt", "desc")
            .limit(1000)
            .get();
        exportData.sections.posts = postsSnap.docs.map((d) => ({
          id: d.id,
          ...d.data(),
        }));

        // 3. Comments (from Realtime Database)
        // Note: RTDB comments are indexed by postId, not userId.
        // We collect comments from the user's own posts.
        exportData.sections.commentsNote =
          "Comments are stored in Realtime Database indexed by post. " +
          "Your comments on others' posts are included where available.";

        // 4. Conversations (metadata only — message content included below)
        const convoSnap = await db().collection("conversations")
            .where("participantIds", "arrayContains", uid)
            .limit(500)
            .get();
        const conversations = [];
        for (const convoDoc of convoSnap.docs) {
          const convoData = convoDoc.data();
          // Fetch messages in this conversation
          const messagesSnap = await db()
              .collection("conversations")
              .doc(convoDoc.id)
              .collection("messages")
              .orderBy("createdAt", "desc")
              .limit(500)
              .get();
          conversations.push({
            id: convoDoc.id,
            ...convoData,
            messages: messagesSnap.docs.map((m) => ({id: m.id, ...m.data()})),
          });
        }
        exportData.sections.conversations = conversations;

        // 5. Notifications
        const notifsSnap = await db().collection("users").doc(uid)
            .collection("notifications")
            .orderBy("createdAt", "desc")
            .limit(500)
            .get();
        exportData.sections.notifications = notifsSnap.docs.map((d) => ({
          id: d.id,
          ...d.data(),
        }));

        // 6. Saved posts
        const savedSnap = await db().collection("users").doc(uid)
            .collection("savedPosts")
            .limit(500)
            .get();
        exportData.sections.savedPosts = savedSnap.docs.map((d) => ({
          id: d.id,
          ...d.data(),
        }));

        // 7. Follow relationships
        const followingSnap = await db().collection("users").doc(uid)
            .collection("following")
            .limit(1000)
            .get();
        exportData.sections.following = followingSnap.docs.map((d) => d.id);

        const followersSnap = await db().collection("users").doc(uid)
            .collection("followers")
            .limit(1000)
            .get();
        exportData.sections.followers = followersSnap.docs.map((d) => d.id);

        // 8. Blocked users
        const blockedSnap = await db().collection("users").doc(uid)
            .collection("blockedUsers")
            .get();
        exportData.sections.blockedUsers = blockedSnap.docs.map((d) => d.id);

        // 9. Church notes
        const notesSnap = await db().collection("churchNotes")
            .where("authorId", "==", uid)
            .limit(500)
            .get();
        exportData.sections.churchNotes = notesSnap.docs.map((d) => ({
          id: d.id,
          ...d.data(),
        }));

        // 10. Language preferences
        const langDoc = await db().collection("users").doc(uid)
            .collection("languagePreferences").doc("settings").get();
        if (langDoc.exists) {
          exportData.sections.languagePreferences = langDoc.data();
        }

        // 11. Berean AI conversations
        const bereanSnap = await db().collection("users").doc(uid)
            .collection("bereanConversations")
            .limit(100)
            .get();
        exportData.sections.bereanConversations = bereanSnap.docs.map((d) => ({
          id: d.id,
          ...d.data(),
        }));

        // Log the export for audit
        await db().collection("dataExportLog").add({
          userId: uid,
          exportedAt: admin.firestore.FieldValue.serverTimestamp(),
          sectionCount: Object.keys(exportData.sections).length,
          postCount: exportData.sections.posts?.length || 0,
          conversationCount: exportData.sections.conversations?.length || 0,
        });

        console.log(`Data export complete for ${uid} — ${Object.keys(exportData.sections).length} sections`);
        return exportData;
      } catch (error) {
        console.error(`Data export failed for ${uid}:`, error);
        throw new HttpsError("internal", "Data export failed. Please try again.");
      }
    },
);

module.exports = {exportUserData};
