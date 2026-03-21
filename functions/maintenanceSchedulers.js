/**
 * maintenanceSchedulers.js
 *
 * Scheduled maintenance Cloud Functions:
 *
 *  1. prayerRequestsTTL         — Daily: delete prayer requests older than 12 months (GDPR)
 *  2. firestoreBackup           — Daily: export Firestore to Cloud Storage
 *  3. backfillUserCommentIndex  — One-time: populate userCommentIndex from existing RTDB data
 *  4. cleanupOrphanedRTDB       — Weekly: remove postInteractions nodes for deleted Firestore posts
 */

'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { Firestore } = require('@google-cloud/firestore');

const db = admin.firestore();

let _rtdb = null;
const getRtdb = () => {
  if (!_rtdb) _rtdb = admin.database('https://amen-5e359-default-rtdb.firebaseio.com');
  return _rtdb;
};

// ─────────────────────────────────────────────────────────────────────────────
// 1. PRAYER REQUESTS TTL — delete prayers older than 12 months (GDPR compliance)
// Runs daily at 3:00 AM UTC. Processes in batches of 200.
// ─────────────────────────────────────────────────────────────────────────────
exports.prayerRequestsTTL = onSchedule(
  {
    schedule: '0 3 * * *',  // daily at 3 AM UTC
    region: 'us-central1',
    timeoutSeconds: 540,
  },
  async () => {
    const twelveMonthsAgo = new Date();
    twelveMonthsAgo.setMonth(twelveMonthsAgo.getMonth() - 12);
    const cutoff = admin.firestore.Timestamp.fromDate(twelveMonthsAgo);

    let deleted = 0;
    let hasMore = true;

    while (hasMore) {
      const snap = await db.collection('prayerRequests')
        .where('createdAt', '<', cutoff)
        .limit(200)
        .get();

      if (snap.empty) {
        hasMore = false;
        break;
      }

      const batch = db.batch();
      snap.docs.forEach(doc => batch.deleteDocument(doc.ref));
      await batch.commit();
      deleted += snap.docs.length;

      hasMore = snap.docs.length === 200;
    }

    // Also clean up RTDB prayerRequests older than 12 months
    try {
      const rtdbSnap = await getRtdb().ref('prayerRequests')
        .orderByChild('createdAt')
        .endAt(twelveMonthsAgo.getTime())
        .once('value');

      const deletePromises = [];
      rtdbSnap.forEach(child => {
        deletePromises.push(getRtdb().ref(`prayerRequests/${child.key}`).remove());
      });
      await Promise.all(deletePromises);
    } catch (err) {
      console.error('[prayerRequestsTTL] RTDB cleanup failed (non-fatal):', err);
    }

    console.log(`[prayerRequestsTTL] Deleted ${deleted} prayer requests older than 12 months`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. FIRESTORE BACKUP — daily export to Cloud Storage
// Runs daily at 2:00 AM UTC.
// Requires: set FIRESTORE_BACKUP_BUCKET env var (e.g. "gs://amen-backups")
// ─────────────────────────────────────────────────────────────────────────────
exports.firestoreBackup = onSchedule(
  {
    schedule: '0 2 * * *',  // daily at 2 AM UTC
    region: 'us-central1',
    timeoutSeconds: 540,
  },
  async () => {
    const projectId = process.env.GCLOUD_PROJECT || 'amen-5e359';
    const bucket = process.env.FIRESTORE_BACKUP_BUCKET || `gs://${projectId}-backups`;
    const timestamp = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const outputUriPrefix = `${bucket}/firestore/${timestamp}`;

    try {
      const client = new Firestore({ projectId });
      // Use the Firestore admin export endpoint
      const response = await admin.firestore().listCollections();
      const collectionIds = (await Promise.all(response.map(c => c.id))).filter(Boolean);

      // Trigger export via Google Cloud Firestore Export API
      const exportUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default):exportDocuments`;
      const token = await admin.credential.applicationDefault().getAccessToken();

      const fetch = require('node-fetch');
      const res = await fetch(exportUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ outputUriPrefix, collectionIds }),
      });

      if (!res.ok) {
        throw new Error(`Export API returned ${res.status}: ${await res.text()}`);
      }

      const operation = await res.json();
      console.log(`[firestoreBackup] Export started: ${outputUriPrefix}`, operation.name);
    } catch (err) {
      console.error('[firestoreBackup] Export failed:', err);
      throw err; // Rethrow so Cloud Functions retries
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. BACKFILL USER COMMENT INDEX
// One-time callable function to populate userCommentIndex from existing RTDB data.
// Run from Firebase console. Admin-only.
// ─────────────────────────────────────────────────────────────────────────────
exports.backfillUserCommentIndex = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: false,
    timeoutSeconds: 540,
  },
  async (req) => {
    const callerUid = req.auth?.uid;
    if (!callerUid) throw new HttpsError('unauthenticated', 'Must be authenticated');

    const adminUids = (process.env.ADMIN_UIDS || '').split(',').map(s => s.trim()).filter(Boolean);
    if (!adminUids.includes(callerUid)) {
      throw new HttpsError('permission-denied', 'Admin only');
    }

    const postInteractionsSnap = await getRtdb().ref('postInteractions').once('value');
    if (!postInteractionsSnap.exists()) {
      return { indexed: 0, message: 'No postInteractions data found' };
    }

    let indexed = 0;
    const writes = [];

    postInteractionsSnap.forEach(postSnap => {
      const postId = postSnap.key;
      const commentsNode = postSnap.child('comments');
      if (!commentsNode.exists()) return;

      commentsNode.forEach(commentSnap => {
        const commentId = commentSnap.key;
        const authorId = commentSnap.child('authorId').val() || commentSnap.child('userId').val();
        const createdAt = commentSnap.child('createdAt').val() || commentSnap.child('timestamp').val() || Date.now();

        if (authorId) {
          writes.push(
            getRtdb()
              .ref(`userCommentIndex/${authorId}/${commentId}`)
              .set({ postId, createdAt })
          );
          indexed++;
        }
      });
    });

    // Process in batches of 500 to avoid hitting RTDB write limits
    const BATCH = 500;
    for (let i = 0; i < writes.length; i += BATCH) {
      await Promise.all(writes.slice(i, i + BATCH));
    }

    console.log(`[backfillUserCommentIndex] Indexed ${indexed} comments`);
    return { success: true, indexed };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 4. CLEANUP ORPHANED RTDB POSTS
// Weekly: remove postInteractions/{postId} nodes where Firestore post no longer exists.
// ─────────────────────────────────────────────────────────────────────────────
exports.cleanupOrphanedRTDB = onSchedule(
  {
    schedule: '0 4 * * 0',  // weekly on Sunday at 4 AM UTC
    region: 'us-central1',
    timeoutSeconds: 540,
  },
  async () => {
    const postInteractionsSnap = await getRtdb().ref('postInteractions').once('value');
    if (!postInteractionsSnap.exists()) return;

    const postIds = [];
    postInteractionsSnap.forEach(child => postIds.push(child.key));

    let removed = 0;
    const BATCH = 100;

    for (let i = 0; i < postIds.length; i += BATCH) {
      const batch = postIds.slice(i, i + BATCH);
      const checks = await Promise.all(
        batch.map(id => db.collection('posts').doc(id).get().then(s => ({ id, exists: s.exists })))
      );
      const toDelete = checks.filter(c => !c.exists).map(c => c.id);
      await Promise.all(toDelete.map(id => getRtdb().ref(`postInteractions/${id}`).remove()));
      removed += toDelete.length;
    }

    console.log(`[cleanupOrphanedRTDB] Removed ${removed} orphaned postInteractions nodes`);
  }
);
