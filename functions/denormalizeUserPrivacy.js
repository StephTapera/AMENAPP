/**
 * denormalizeUserPrivacy.js
 *
 * When a user toggles isPrivate/isPrivateAccount on their user doc,
 * update all their posts with authorIsPrivate: true/false so Firestore
 * security rules can evaluate privacy without a cross-document get().
 *
 * This eliminates the extra billable Firestore read per document
 * in the callerCanReadPost() rule function.
 */

'use strict';

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const db = admin.firestore();
const REGION = 'us-central1';

exports.onUserPrivacyChanged = onDocumentUpdated(
  { document: 'users/{userId}', region: REGION },
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    // Detect privacy toggle (either field, both handled the same)
    const wasPrivate = before?.isPrivate === true || before?.isPrivateAccount === true;
    const isPrivate  = after?.isPrivate  === true || after?.isPrivateAccount  === true;

    if (wasPrivate === isPrivate) return null; // no change

    const userId = event.params.userId;
    console.log(`[denormalizeUserPrivacy] userId=${userId} isPrivate: ${wasPrivate} → ${isPrivate}`);

    // Update all posts by this author in batches of 500
    let lastDoc = null;
    let updated = 0;

    do {
      let query = db.collection('posts')
        .where('authorId', '==', userId)
        .limit(500);

      if (lastDoc) query = query.startAfter(lastDoc);

      const snap = await query.get();
      if (snap.empty) break;

      const batch = db.batch();
      snap.docs.forEach(doc => {
        batch.update(doc.ref, {
          authorIsPrivate: isPrivate,
          authorPrivacyUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      await batch.commit();
      updated += snap.docs.length;
      lastDoc = snap.docs.length === 500 ? snap.docs[snap.docs.length - 1] : null;
    } while (lastDoc);

    console.log(`[denormalizeUserPrivacy] Updated ${updated} posts for user ${userId}`);
    return null;
  }
);
