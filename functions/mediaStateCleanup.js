/**
 * Media State Cleanup Cloud Function (System 12)
 *
 * Scheduled daily: deletes completed media resume states >7 days old,
 * and all states >30 days old regardless of completion.
 *
 * Collection: users/{userId}/mediaResumeState/{stateId}
 */

const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

exports.cleanupMediaResumeState = onSchedule(
    {schedule: "0 3 * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      console.log("🧹 Cleaning up media resume states...");

      try {
        const now = new Date();
        const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

        let deletedCount = 0;

        // Query all users (paginated to avoid memory issues)
        const usersSnap = await db.collection("users")
            .select() // Only need IDs, not data
            .limit(500)
            .get();

        for (const userDoc of usersSnap.docs) {
          const userId = userDoc.id;
          const stateRef = db.collection("users").doc(userId)
              .collection("mediaResumeState");

          // 1. Delete completed states older than 7 days
          const completedOldSnap = await stateRef
              .where("completed", "==", true)
              .where("lastPlayedAt", "<=",
                  admin.firestore.Timestamp.fromDate(sevenDaysAgo))
              .limit(100)
              .get();

          // 2. Delete all states older than 30 days
          const veryOldSnap = await stateRef
              .where("lastPlayedAt", "<=",
                  admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
              .limit(100)
              .get();

          // Merge doc refs (avoid double-deleting)
          const docsToDelete = new Map();
          for (const doc of completedOldSnap.docs) {
            docsToDelete.set(doc.id, doc.ref);
          }
          for (const doc of veryOldSnap.docs) {
            docsToDelete.set(doc.id, doc.ref);
          }

          if (docsToDelete.size === 0) continue;

          // Batch delete
          const batch = db.batch();
          for (const ref of docsToDelete.values()) {
            batch.delete(ref);
            deletedCount++;
          }
          await batch.commit();
        }

        console.log(`✅ Cleaned up ${deletedCount} expired media resume state(s)`);
      } catch (error) {
        console.error("❌ Error in cleanupMediaResumeState:", error);
      }
    },
);
