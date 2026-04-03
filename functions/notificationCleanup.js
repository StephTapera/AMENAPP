/**
 * notificationCleanup.js
 *
 * Scheduled Cloud Function that prunes stale notifications from Firestore.
 *
 * Policy:
 *   - Read notifications older than 90 days are deleted
 *   - Unread notifications older than 180 days are deleted (very stale)
 *   - Each user's notification subcollection is capped at 500 documents
 *     (oldest removed first) to prevent unbounded growth
 *
 * Schedule: runs daily at 3 AM UTC (off-peak)
 */

const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const REGION = "us-central1";
const READ_TTL_DAYS = 90;
const UNREAD_TTL_DAYS = 180;
const MAX_NOTIFS_PER_USER = 500;
const BATCH_SIZE = 400;

exports.cleanupStaleNotifications = onSchedule(
    {
      schedule: "0 3 * * *", // 3 AM UTC daily
      timeZone: "UTC",
      region: REGION,
      memory: "512MiB",
      timeoutSeconds: 540,
    },
    async () => {
      const db = admin.firestore();
      const now = Date.now();
      const readCutoff = admin.firestore.Timestamp.fromMillis(
          now - READ_TTL_DAYS * 24 * 60 * 60 * 1000,
      );
      const unreadCutoff = admin.firestore.Timestamp.fromMillis(
          now - UNREAD_TTL_DAYS * 24 * 60 * 60 * 1000,
      );

      console.log(`[notificationCleanup] Starting. Cutoffs: read=${READ_TTL_DAYS}d, unread=${UNREAD_TTL_DAYS}d`);

      let totalDeleted = 0;
      let usersProcessed = 0;

      // Paginate through all users
      let lastUserDoc = null;

      do {
        let userQuery = db.collection("users").limit(50);
        if (lastUserDoc) userQuery = userQuery.startAfter(lastUserDoc);

        const usersSnap = await userQuery.get();
        if (usersSnap.empty) break;

        // Process each user's notifications concurrently (capped at 50 users/batch)
        await Promise.all(usersSnap.docs.map(async (userDoc) => {
          const uid = userDoc.id;
          const notifsRef = db.collection(`users/${uid}/notifications`);

          // 1. Delete read notifications older than READ_TTL_DAYS
          const readStale = await notifsRef
              .where("read", "==", true)
              .where("createdAt", "<", readCutoff)
              .limit(BATCH_SIZE)
              .get();

          // 2. Delete unread notifications older than UNREAD_TTL_DAYS
          const unreadStale = await notifsRef
              .where("read", "==", false)
              .where("createdAt", "<", unreadCutoff)
              .limit(BATCH_SIZE)
              .get();

          const toDelete = [...readStale.docs, ...unreadStale.docs];

          if (toDelete.length > 0) {
            const batch = db.batch();
            toDelete.forEach((doc) => batch.delete(doc.ref));
            await batch.commit();
            totalDeleted += toDelete.length;
          }

          // 3. Cap per-user notification count at MAX_NOTIFS_PER_USER
          const countSnap = await notifsRef
              .orderBy("createdAt", "desc")
              .limit(MAX_NOTIFS_PER_USER + BATCH_SIZE)
              .get();

          if (countSnap.size > MAX_NOTIFS_PER_USER) {
            const overflow = countSnap.docs.slice(MAX_NOTIFS_PER_USER);
            if (overflow.length > 0) {
              const overflowBatch = db.batch();
              overflow.forEach((doc) => overflowBatch.delete(doc.ref));
              await overflowBatch.commit();
              totalDeleted += overflow.length;
            }
          }
        }));

        usersProcessed += usersSnap.size;
        lastUserDoc = usersSnap.docs[usersSnap.docs.length - 1];
        console.log(`[notificationCleanup] Processed ${usersProcessed} users, deleted ${totalDeleted} notifications so far`);
      } while (lastUserDoc);

      console.log(`[notificationCleanup] Complete. Users=${usersProcessed}, Deleted=${totalDeleted}`);
    },
);
