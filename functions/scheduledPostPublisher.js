/**
 * scheduledPostPublisher.js
 *
 * Publishes scheduled posts whose scheduledAt time has arrived.
 *
 * HOW IT WORKS:
 *   - Runs every 1 minute via Cloud Scheduler (pubsub-backed).
 *   - Queries the `scheduledPosts` collection for docs where:
 *       status == 'scheduled'  AND  scheduledAt <= now
 *   - For each matching doc (up to 50 per run):
 *       1. Copies all fields to the `posts` collection using the scheduled
 *          post's document ID as the post ID (idempotent by design).
 *       2. Sets status = 'published' and publishedAt = serverTimestamp() on
 *          both the new post and the scheduledPosts source doc.
 *   - Uses a status pre-check before each write to avoid double-publishing
 *     if a concurrent function run picks up the same doc.
 *   - Errors on individual documents are caught and logged without aborting
 *     the rest of the batch.
 *
 * DEPLOY:
 *   firebase deploy --only functions:publishScheduledPosts
 *
 * REQUIREMENTS:
 *   firebase-functions >= 4.x (v2 scheduler API)
 *   firebase-admin >= 11.x
 */

const admin = require('firebase-admin');
const functions = require('firebase-functions');
const { onSchedule } = require('firebase-functions/v2/scheduler');

// Disabled: canonical scheduled post publisher is in mlContentPipeline.js (scheduledPostPublisherML)
// exports.publishScheduledPosts = onSchedule(
//     { schedule: 'every 1 minutes', timeZone: 'UTC', region: 'us-central1' },
//     async (context) => {
//       const db = admin.firestore();
//       const now = admin.firestore.Timestamp.now();
//
//       console.log('[publishScheduledPosts] Run started at', now.toDate().toISOString());
//
//       let snap;
//       try {
//         snap = await db
//             .collection('scheduledPosts')
//             .where('scheduledAt', '<=', now)
//             .where('status', '==', 'scheduled')
//             .limit(50)
//             .get();
//       } catch (queryErr) {
//         console.error('[publishScheduledPosts] Query failed:', queryErr);
//         return;
//       }
//
//       if (snap.empty) {
//         console.log('[publishScheduledPosts] No scheduled posts due. Exiting.');
//         return;
//       }
//
//       console.log(`[publishScheduledPosts] Processing ${snap.size} post(s)...`);
//
//       let published = 0;
//       let skipped = 0;
//       let failed = 0;
//
//       for (const doc of snap.docs) {
//         const scheduledPostId = doc.id;
//
//         try {
//           const alreadyPublished = await db.runTransaction(async (tx) => {
//             const fresh = await tx.get(doc.ref);
//             if (!fresh.exists || fresh.data().status !== 'scheduled') {
//               return true;
//             }
//             tx.update(doc.ref, { status: 'publishing' });
//             return false;
//           });
//
//           if (alreadyPublished) {
//             console.log(`[publishScheduledPosts] Skipping ${scheduledPostId} — already handled.`);
//             skipped++;
//             continue;
//           }
//
//           const data = doc.data();
//           const { status, scheduledAt, createdAt, updatedAt, ...rest } = data;
//
//           const postPayload = {
//             ...rest,
//             status: 'published',
//             publishedAt: admin.firestore.FieldValue.serverTimestamp(),
//             createdAt: createdAt || scheduledAt,
//             scheduledPostId,
//           };
//
//           const batch = db.batch();
//           const postRef = db.collection('posts').doc(scheduledPostId);
//           batch.set(postRef, postPayload);
//           batch.update(doc.ref, {
//             status: 'published',
//             publishedAt: admin.firestore.FieldValue.serverTimestamp(),
//           });
//           await batch.commit();
//
//           console.log(`[publishScheduledPosts] Published post ${scheduledPostId}`);
//           published++;
//         } catch (docErr) {
//           console.error(`[publishScheduledPosts] Failed to publish ${scheduledPostId}:`, docErr);
//           try {
//             await doc.ref.update({ status: 'scheduled' });
//           } catch (rollbackErr) {
//             console.error(`[publishScheduledPosts] Rollback failed for ${scheduledPostId}:`, rollbackErr);
//           }
//           failed++;
//         }
//       }
//
//       console.log(
//           `[publishScheduledPosts] Done — published: ${published}, skipped: ${skipped}, failed: ${failed}`
//       );
//     }
// );
