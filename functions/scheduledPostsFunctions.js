/**
 * scheduledPostsFunctions.js
 * Publishes scheduled posts when their scheduledFor time has passed.
 *
 * Runs every 5 minutes. Queries scheduled_posts where status="pending"
 * and scheduledFor <= now, then creates the real post in the posts
 * collection and marks the scheduled doc as "published".
 */

const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const db = () => admin.firestore();

const executeScheduledPosts = onSchedule(
    {schedule: "*/5 * * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const now = admin.firestore.Timestamp.now();

      try {
        const pendingSnap = await db()
            .collection("scheduled_posts")
            .where("status", "==", "pending")
            .where("scheduledFor", "<=", now)
            .limit(50) // Process in batches to avoid timeout
            .get();

        if (pendingSnap.empty) return;

        console.log(`Publishing ${pendingSnap.size} scheduled post(s)...`);

        let published = 0;

        for (const doc of pendingSnap.docs) {
          const data = doc.data();

          try {
            // Get author info for denormalized fields
            const authorDoc = await db().collection("users").doc(data.authorId).get();
            const authorData = authorDoc.data() || {};

            // Create the real post
            const postData = {
              content: data.content || "",
              category: data.category || "openTable",
              topicTag: data.topicTag || null,
              allowComments: data.allowComments !== false,
              commentPermissions: data.commentPermissions || "everyone",
              linkURL: data.linkURL || null,
              imageURLs: data.imageURLs || null,
              userId: data.authorId,
              authorId: data.authorId,
              authorName: authorData.displayName || "Unknown",
              authorUsername: authorData.username || null,
              authorProfileImageURL: authorData.profileImageURL || null,
              visibility: data.visibility || "everyone",
              amenCount: 0,
              lightbulbCount: 0,
              commentCount: 0,
              repostCount: 0,
              isRepost: false,
              createdAt: data.scheduledFor, // Use scheduled time as creation time
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              scheduledPostId: doc.id, // Reference back to scheduled doc
            };

            // Add verse data if present
            if (data.verseReference) {
              postData.verseReference = data.verseReference;
              postData.verseText = data.verseText || null;
              postData.linkPreviewType = "verse";
            }

            await db().collection("posts").add(postData);

            // Mark as published
            await doc.ref.update({
              status: "published",
              publishedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            published++;
          } catch (postError) {
            console.error(`Failed to publish scheduled post ${doc.id}:`, postError);
            await doc.ref.update({
              status: "failed",
              failedAt: admin.firestore.FieldValue.serverTimestamp(),
              failureReason: postError.message,
            });
          }
        }

        console.log(`Published ${published}/${pendingSnap.size} scheduled post(s)`);
      } catch (error) {
        console.error("Error in executeScheduledPosts:", error);
      }
    },
);

module.exports = {executeScheduledPosts};
