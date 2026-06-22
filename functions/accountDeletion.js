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
let _rtdb = null;
const getRtdb = () => {
  if (!_rtdb) _rtdb = admin.database("https://amen-5e359-default-rtdb.firebaseio.com");
  return _rtdb;
};
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
  // Berean AI stores (P0-05): must be hard-deleted on account removal.
  'bereanMemory', 'bereanPipelineTraces', 'bereanModelLogs', 'bereanFeedback',
  // P0-10: AI/Berean conversation history stores on user doc — contain user-typed
  // prayer, personal questions, and AI responses. Must be deleted on account removal
  // (App Store 5.1.1(v) / GDPR Art.17).
  'chatHistory',        // BereanChatView.swift:254 — assistant reply log
  'bereanConversations', // BereanConversationService.swift + premiumBereanCallables.ts
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
      await getRtdb().ref(`presence/${uid}`).remove();
      await getRtdb().ref(`userOnline/${uid}`).remove();
      await getRtdb().ref(`typingIndicators/${uid}`).remove();

      // Anonymize messages sent by this user across all conversations
      // Note: Full conversation deletion is out of scope here; we scrub the text.
      // For GDPR/CCPA compliance, scrubbing is sufficient (the message happened).
      const messagesSnap = await getRtdb().ref('messages')
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
        await getRtdb().ref().update(updates);
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

      // 3g. C-13: Events and RSVPs — delete events the user created, plus their own RSVPs.
      // Events hosted by the user are deleted; their RSVPs subcollections are removed too.
      const hostedEventsSnap = await db.collection('events')
        .where('hostUserId', '==', uid)
        .get();
      for (const eventDoc of hostedEventsSnap.docs) {
        await deleteCollection(eventDoc.ref.collection('rsvps'));
        await eventDoc.ref.delete();
      }
      // RSVPs the user made to other events
      const rsvpSnap = await db.collectionGroup('rsvps')
        .where('userId', '==', uid)
        .get();
      await batchDelete(rsvpSnap.docs);

      // 3h. C-14: Church succession — transfer or archive churches where user is primary pastor.
      const ownedChurchesSnap = await db.collection('churches')
        .where('pastorUserId', '==', uid)
        .get();
      for (const churchDoc of ownedChurchesSnap.docs) {
        const churchData = churchDoc.data();
        const coPastors = churchData.coPastorIds || [];
        const remainingCoPastors = coPastors.filter(id => id !== uid);
        if (remainingCoPastors.length > 0) {
          // Transfer ownership to the first co-pastor
          await churchDoc.ref.update({
            pastorUserId: remainingCoPastors[0],
            coPastorIds: remainingCoPastors.slice(1),
            ownershipTransferredAt: admin.firestore.FieldValue.serverTimestamp(),
            previousPastorId: uid,
          });
        } else {
          // No co-pastors — archive the church
          await churchDoc.ref.update({
            status: 'pastor_departed',
            pastorUserId: admin.firestore.FieldValue.delete(),
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
            previousPastorId: uid,
          });
        }
      }
      // Remove user from any church where they are a co-pastor (not primary)
      const coPastorChurchesSnap = await db.collection('churches')
        .where('coPastorIds', 'array-contains', uid)
        .get();
      for (const churchDoc of coPastorChurchesSnap.docs) {
        await churchDoc.ref.update({
          coPastorIds: admin.firestore.FieldValue.arrayRemove(uid),
        });
      }

      // 3i. Space memberships — remove user from spaces they joined
      const spaceMemberSnap = await db.collectionGroup('members')
        .where('userId', '==', uid)
        .get();
      await batchDelete(spaceMemberSnap.docs);
      // Spaces the user owned — archive them
      const ownedSpacesSnap = await db.collection('spaces')
        .where('ownerId', '==', uid)
        .get();
      for (const spaceDoc of ownedSpacesSnap.docs) {
        await spaceDoc.ref.update({
          status: 'owner_deleted',
          archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // 3j. Berean AI top-level collections (P0-05): hard-delete pipeline traces
      // and feedback that are stored at the top level keyed by userId, not under
      // the user doc. The user-doc subcollections (bereanMemory, bereanPipelineTraces,
      // bereanModelLogs, bereanFeedback) are already covered by USER_SUBCOLLECTIONS
      // above; these calls cover any top-level counterpart collections.
      await deleteDocsWhere('bereanPipelineTraces', 'userId', uid);
      await deleteDocsWhere('bereanFeedback', 'userId', uid);

      // 3k. Berean AI snake_case top-level collections (P0-05 cascade):
      // The backend pipeline writes to snake_case collection names distinct from the
      // camelCase user-doc subcollections handled above. All four must be scrubbed.

      // berean_pipeline_traces — keyed by userId
      await deleteDocsWhere('berean_pipeline_traces', 'userId', uid);

      // berean_feedback — keyed by userId
      await deleteDocsWhere('berean_feedback', 'userId', uid);

      // berean_model_logs — may be keyed by userId OR requesterId; scrub both fields
      await deleteDocsWhere('berean_model_logs', 'userId', uid);
      await deleteDocsWhere('berean_model_logs', 'requesterId', uid);

      // berean_memory/{userId}/entries subcollection + parent document
      const bereanMemoryRef = db.collection('berean_memory').doc(uid);
      await deleteCollection(bereanMemoryRef.collection('entries'));
      await bereanMemoryRef.delete();

      // ── P0-9: aiBibleStudyConversations — root collection keyed by userId. ──────
      // Each conversation doc also has a `messages` subcollection containing the
      // user's typed queries and AI responses (App Store 5.1.1(v) / GDPR Art.17).
      // Must recursively delete messages before deleting the conversation doc.
      // BACKFILL REQUIRED: Run one-time admin script to delete aiBibleStudyConversations
      // for users already in the deletion audit log. If no audit log exists, log as P1.
      {
        let conversationsQuery = db.collection('aiBibleStudyConversations')
          .where('userId', '==', uid).limit(100);
        let conversationsSnap = await conversationsQuery.get();
        while (!conversationsSnap.empty) {
          for (const convDoc of conversationsSnap.docs) {
            // Delete the messages subcollection first (nested personal content)
            await deleteCollection(convDoc.ref.collection('messages'));
            await convDoc.ref.delete();
          }
          if (conversationsSnap.size < 100) break;
          conversationsSnap = await conversationsQuery.get();
        }
        console.log(`[accountDeletion] aiBibleStudyConversations cleared for uid=${uid}`);
      }

      // ── P0-9 (additional): realtimeSessions — root collection keyed by createdBy. ──
      // Voice/prayer realtime session records written by createRealtimeSession CF.
      // Subcollections: analyticsEvents, scriptureReferences. All must be deleted.
      // (Audit finding A13-006; field is `createdBy` and also mirrored in `ownerId`.)
      {
        let sessionsQuery = db.collection('realtimeSessions')
          .where('createdBy', '==', uid).limit(100);
        let sessionsSnap = await sessionsQuery.get();
        while (!sessionsSnap.empty) {
          for (const sessionDoc of sessionsSnap.docs) {
            await deleteCollection(sessionDoc.ref.collection('analyticsEvents'));
            await deleteCollection(sessionDoc.ref.collection('scriptureReferences'));
            await sessionDoc.ref.delete();
          }
          if (sessionsSnap.size < 100) break;
          sessionsSnap = await sessionsQuery.get();
        }
        console.log(`[accountDeletion] realtimeSessions cleared for uid=${uid}`);
      }

      // TODO(P1 — Pinecone): Delete user vectors from Pinecone index.
      // Namespace format: userId (each user's embeddings are namespaced by UID).
      // Requires PINECONE_API_KEY + PINECONE_INDEX_NAME env vars.
      // When available, call: pineconeIndex.delete1({ deleteAll: true, namespace: uid })
      // Tracked as P1 because Pinecone is not yet provisioned for production
      // (see Backend/functions/src/berean/bereanMemory.ts:435).

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
