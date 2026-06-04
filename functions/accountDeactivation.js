/**
 * accountDeactivation.js
 *
 * Three Cloud Functions for the deactivation lifecycle:
 *
 * 1. onAccountDeactivated  — Firestore trigger on users/{uid}.isDeactivated = true
 *    • Disables the Firebase Auth account so the user can't sign in while deactivated
 *    • Hides the user from Algolia search index
 *
 * 2. onAccountReactivated  — Firestore trigger on users/{uid}.isDeactivated deleted
 *    • Re-enables the Firebase Auth account
 *    • Restores the user in Algolia search index
 *
 * 3. purgeExpiredDeactivations — Scheduled daily
 *    • Finds users whose deactivationExpiresAt has passed
 *    • Moves them to a deletionRequests document (picked up by accountDeletion.js)
 *
 * All functions are idempotent and safe to retry.
 */
// TODO: USE_DEFINE_SECRET — migrate this secret to defineSecret() for Functions v2


'use strict';

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule }        = require('firebase-functions/v2/scheduler');
const admin                 = require('firebase-admin');

// Admin SDK is initialized in index.js — do not call initializeApp() here.
const db   = admin.firestore();
const auth = admin.auth();

// ─────────────────────────────────────────────────────────────────────────────
// 1. onAccountDeactivated
//    Triggers when users/{uid} is updated and isDeactivated flips to true.
// ─────────────────────────────────────────────────────────────────────────────
exports.onAccountDeactivated = onDocumentUpdated(
  { document: 'users/{uid}', region: 'us-central1' },
  async (event) => {
    const before = event.data.before.data() || {};
    const after  = event.data.after.data()  || {};
    const uid    = event.params.uid;

    // Only act when isDeactivated transitions false → true
    if (before.isDeactivated === after.isDeactivated) return null;
    if (!after.isDeactivated) return null;

    console.log(`[accountDeactivation] Deactivating auth account for uid=${uid}`);

    try {
      // Disable Firebase Auth account (prevents sign-in while deactivated)
      await auth.updateUser(uid, { disabled: true });
      console.log(`[accountDeactivation] Auth account disabled for uid=${uid}`);
    } catch (err) {
      console.error(`[accountDeactivation] Failed to disable auth for uid=${uid}:`, err);
    }

    // Optionally remove from Algolia if configured
    try {
      const algoliaIndexName = process.env.ALGOLIA_USERS_INDEX || 'users';
      // Algolia sync: mark as not_in_discovery so it's excluded from search
      // The full Algolia remove is handled by algoliaSync.js user listener.
      // We just update the document so that listener fires next.
      await db.collection('users').doc(uid).update({
        'algoliaHideFromSearch': true
      });
    } catch (err) {
      // Non-critical — Algolia sync may not be configured in all environments
      console.warn(`[accountDeactivation] Algolia hide skipped for uid=${uid}:`, err.message);
    }

    return null;
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. onAccountReactivated
//    Triggers when users/{uid} is updated and isDeactivated flips false/deleted.
// ─────────────────────────────────────────────────────────────────────────────
exports.onAccountReactivated = onDocumentUpdated(
  { document: 'users/{uid}', region: 'us-central1' },
  async (event) => {
    const before = event.data.before.data() || {};
    const after  = event.data.after.data()  || {};
    const uid    = event.params.uid;

    // Only act when isDeactivated transitions true → false/absent
    const wasDeactivated = before.isDeactivated === true;
    const isNowActive    = !after.isDeactivated;
    if (!wasDeactivated || !isNowActive) return null;

    console.log(`[accountDeactivation] Reactivating auth account for uid=${uid}`);

    try {
      await auth.updateUser(uid, { disabled: false });
      console.log(`[accountDeactivation] Auth account re-enabled for uid=${uid}`);
    } catch (err) {
      console.error(`[accountDeactivation] Failed to re-enable auth for uid=${uid}:`, err);
    }

    // Restore Algolia visibility
    try {
      await db.collection('users').doc(uid).update({
        'algoliaHideFromSearch': admin.firestore.FieldValue.delete()
      });
    } catch (err) {
      console.warn(`[accountDeactivation] Algolia restore skipped for uid=${uid}:`, err.message);
    }

    return null;
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. purgeExpiredDeactivations
//    Runs daily at 03:00 UTC. Finds expired deactivations and queues permanent deletion.
// ─────────────────────────────────────────────────────────────────────────────
exports.purgeExpiredDeactivations = onSchedule(
  { schedule: '0 3 * * *', region: 'us-central1', timeZone: 'UTC' },
  async (_context) => {
    const now = admin.firestore.Timestamp.now();

    console.log('[accountDeactivation] Checking for expired deactivations...');

    const snapshot = await db
      .collection('users')
      .where('isDeactivated', '==', true)
      .where('deactivationExpiresAt', '<=', now)
      .limit(100)  // Process in batches to avoid function timeout
      .get();

    if (snapshot.empty) {
      console.log('[accountDeactivation] No expired deactivations found.');
      return;
    }

    console.log(`[accountDeactivation] Found ${snapshot.size} expired accounts — queuing deletion.`);

    const batch = db.batch();

    for (const doc of snapshot.docs) {
      const uid = doc.id;

      // Queue for permanent deletion (accountDeletion.js watches this collection)
      const deletionRef = db.collection('deletionRequests').doc(uid);
      batch.set(deletionRef, {
        userId:      uid,
        requestedAt: now,
        reason:      'deactivation_expired',
        status:      'pending'
      }, { merge: true });
    }

    await batch.commit();
    console.log(`[accountDeactivation] Queued ${snapshot.size} accounts for permanent deletion.`);
  }
);
