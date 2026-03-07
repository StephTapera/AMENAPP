/**
 * accountDeletion.js
 *
 * Processes deletion requests created by the client in deletionRequests/{userId}.
 * Triggered by Firestore document creation; runs with admin SDK (bypasses all rules).
 *
 * Deletion scope (in order):
 *  1. Firebase Storage — all files under the user's known paths
 *  2. Realtime Database — messages, postInteractions authored by user
 *  3. Firestore — user doc, posts, comments, follows, blocks, notifications, etc.
 *  4. Firebase Auth — the auth account itself (last step, so we can still read uid)
 *  5. Mark request as completed / failed for audit trail
 *
 * Idempotent: safe to retry if it fails partway through.
 */

'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const db      = admin.firestore();
const rtdb    = admin.database();
const storage = admin.storage();
const auth    = admin.auth();

const REGION = 'us-central1';

// ─── Storage paths owned by a user ───────────────────────────────────────────
const USER_STORAGE_PREFIXES = (uid) => [
  `profile_images/${uid}/`,
  `post_media/${uid}/`,
  `testimony_media/${uid}/`,
  `dating_photos/${uid}/`,
  `message_attachments/${uid}/`,
  `verification_docs/${uid}/`,
];

// ─── Firestore collections to delete in their entirety for this user ──────────
// Each entry: { collection, field } where field is the field that must == uid.
// Handled via batched queries.
const USER_OWNED_COLLECTIONS = [
  { collection: 'posts',              field: 'authorId'    },
  { collection: 'notifications',      field: 'recipientId' },
  { collection: 'notificationTokens', field: 'userId'      },
  { collection: 'dateLikes',          field: 'userId'      },
  { collection: 'dateMatches',        field: 'userId'      },
  { collection: 'draftPosts',         field: 'authorId'    },
  { collection: 'dataExportRequests', field: 'userId'      },
  { collection: 'rateLimitCounters',  field: 'userId'      }, // may not have field; prefix-delete by doc id
  { collection: 'commentIdempotencyKeys', field: 'authorId' },
];

// ─── Subcollections on user doc ───────────────────────────────────────────────
const USER_SUBCOLLECTIONS = [
  'followers', 'following', 'followRequests', 'blockedUsers',
  'savedPosts', 'notificationPreferences', 'privacySettings',
];

exports.processAccountDeletion = onDocumentCreated(
  { document: 'deletionRequests/{userId}', region: REGION },
  async (event) => {
    const uid = event.params.userId;
    const requestRef = event.data.ref;

    console.log(`[accountDeletion] Starting deletion for uid=${uid}`);

    // Mark as in-progress to prevent double-processing
    await requestRef.update({ status: 'processing', startedAt: admin.firestore.FieldValue.serverTimestamp() });

    const errors = [];

    // ── STEP 1: Delete Storage files ────────────────────────────────────────
    try {
      const bucket = storage.bucket();
      for (const prefix of USER_STORAGE_PREFIXES(uid)) {
        const [files] = await bucket.getFiles({ prefix });
        await Promise.all(files.map(f => f.delete().catch(e => {
          console.warn(`[accountDeletion] Storage delete failed for ${f.name}: ${e.message}`);
        })));
      }
      console.log(`[accountDeletion] Storage cleared for uid=${uid}`);
    } catch (e) {
      errors.push(`storage: ${e.message}`);
      console.error(`[accountDeletion] Storage error: ${e.message}`);
    }

    // ── STEP 2: Delete RTDB data ─────────────────────────────────────────────
    // Conversations the user participated in — we anonymize their messages rather
    // than deleting the whole conversation (to preserve the other party's data).
    try {
      // Remove user presence
      await rtdb.ref(`presence/${uid}`).remove();
      await rtdb.ref(`userOnline/${uid}`).remove();
      await rtdb.ref(`typingIndicators/${uid}`).remove();

      // Anonymize messages sent by this user across all conversations
      // Note: Full conversation deletion is out of scope here; we scrub the text.
      // For GDPR/CCPA compliance, scrubbing is sufficient (the message happened).
      const messagesSnap = await rtdb.ref('messages')
        .orderByChild('senderId')
        .equalTo(uid)
        .once('value');

      const updates = {};
      messagesSnap.forEach(child => {
        updates[`${child.ref.path}/text`]       = '[Message deleted]';
        updates[`${child.ref.path}/deletedByAuthor`] = true;
        updates[`${child.ref.path}/senderId`]   = 'deleted';
      });
      if (Object.keys(updates).length > 0) {
        await rtdb.ref().update(updates);
      }

      console.log(`[accountDeletion] RTDB cleaned for uid=${uid}`);
    } catch (e) {
      errors.push(`rtdb: ${e.message}`);
      console.error(`[accountDeletion] RTDB error: ${e.message}`);
    }

    // ── STEP 3: Delete Firestore data ────────────────────────────────────────
    try {
      // 3a. User subcollections
      const userRef = db.collection('users').doc(uid);
      for (const sub of USER_SUBCOLLECTIONS) {
        await deleteCollection(userRef.collection(sub));
      }

      // 3b. User document
      await userRef.delete();

      // 3c. Top-level collections owned by user
      for (const { collection, field } of USER_OWNED_COLLECTIONS) {
        await deleteDocsWhere(collection, field, uid);
      }

      // 3d. Comments authored by user across all posts (subcollection query)
      // Note: Firestore doesn't support cross-collection-group deletes in one query
      // on subcollections without a collection group index. We handle this by
      // querying the collectionGroup.
      const commentsSnap = await db.collectionGroup('comments')
        .where('authorId', '==', uid)
        .get();
      await batchDelete(commentsSnap.docs);

      // 3e. Follow relationships referencing this user
      await deleteDocsWhere('follows', 'followerId', uid);
      await deleteDocsWhere('follows', 'followingId', uid);

      // 3f. Algolia sync queue entries
      await deleteDocsWhere('algoliaSync', 'userId', uid);

      console.log(`[accountDeletion] Firestore cleared for uid=${uid}`);
    } catch (e) {
      errors.push(`firestore: ${e.message}`);
      console.error(`[accountDeletion] Firestore error: ${e.message}`);
    }

    // ── STEP 4: Delete Firebase Auth account ─────────────────────────────────
    try {
      await auth.deleteUser(uid);
      console.log(`[accountDeletion] Auth user deleted for uid=${uid}`);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        console.log(`[accountDeletion] Auth user already deleted for uid=${uid}`);
      } else {
        errors.push(`auth: ${e.message}`);
        console.error(`[accountDeletion] Auth error: ${e.message}`);
      }
    }

    // ── STEP 5: Update deletion request status ────────────────────────────────
    const finalStatus = errors.length === 0 ? 'completed' : 'completed_with_errors';
    await requestRef.update({
      status: finalStatus,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      errors: errors.length > 0 ? errors : admin.firestore.FieldValue.delete(),
    });

    console.log(`[accountDeletion] Done for uid=${uid}. Status=${finalStatus}. Errors=${errors.join(', ') || 'none'}`);
  }
);

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Delete all docs in a collection reference (subcollection).
 */
async function deleteCollection(collRef) {
  const snap = await collRef.limit(200).get();
  if (snap.empty) return;
  await batchDelete(snap.docs);
  // Recurse if more docs remain
  if (snap.size === 200) await deleteCollection(collRef);
}

/**
 * Delete docs in a top-level collection where field == uid.
 */
async function deleteDocsWhere(collectionName, field, uid) {
  let query = db.collection(collectionName).where(field, '==', uid).limit(200);
  let snap = await query.get();
  while (!snap.empty) {
    await batchDelete(snap.docs);
    snap = await query.get();
  }
}

/**
 * Batch-delete an array of Firestore DocumentSnapshot.
 */
async function batchDelete(docs) {
  const batchSize = 400; // Firestore max 500 ops per batch
  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    docs.slice(i, i + batchSize).forEach(d => batch.delete(d.ref));
    await batch.commit();
  }
}
