/**
 * reviewWorkflow.js
 * Cloud Functions implementing the Work review state machine.
 *
 * State machine:
 *   imported → draft → review → approved → published
 *
 * Client transitions: imported→draft, draft→review
 * CF-only transitions: review→approved, approved→published (human gate)
 * Revert: published→approved (unpublish)
 * Soft delete: any state → sets deletedAt
 *
 * All functions require Firebase Auth (context.auth).
 */

'use strict';

const admin = require('firebase-admin');
const functions = require('firebase-functions');

const db = () => admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ─── State Machine Rules ──────────────────────────────────────────────────────

const CLIENT_TRANSITIONS = {
  imported: 'draft',
  draft: 'review',
};

const CF_TRANSITIONS = {
  review: 'approved',
  approved: 'published',
};

const REVERT_TRANSITIONS = {
  published: 'approved',
};

// States from which you cannot return to draft/imported once published
const LOCKED_FORWARD_STATES = new Set(['published', 'approved']);

/**
 * Fetch a work document and verify it belongs to the caller.
 * Throws HttpsError on not-found, deleted, or ownership mismatch.
 */
async function requireOwnWork(workId, uid) {
  const ref = db().collection('works').doc(workId);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', `Work "${workId}" not found.`);
  }

  const data = snap.data();
  if (data.deletedAt !== null) {
    throw new functions.https.HttpsError('not-found', `Work "${workId}" has been deleted.`);
  }
  if (data.creatorId !== uid) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'You do not own this work.'
    );
  }

  return { ref, data };
}

/**
 * Check if the caller has the Firebase custom claim 'admin: true'.
 */
function isAdmin(context) {
  return !!(context.auth && context.auth.token && context.auth.token.admin === true);
}

// ─── advanceWorkReviewState ───────────────────────────────────────────────────

/**
 * Client-callable: advance a work from imported→draft or draft→review.
 * data: { workId: string }
 */
exports.advanceWorkReviewState = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { workId } = data || {};
  if (!workId) {
    throw new functions.https.HttpsError('invalid-argument', 'workId is required.');
  }

  const { ref, data: work } = await requireOwnWork(workId, context.auth.uid);
  const currentState = work.reviewState;
  const nextState = CLIENT_TRANSITIONS[currentState];

  if (!nextState) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Cannot advance from state "${currentState}" as a client. ` +
      `Client transitions are: imported→draft, draft→review.`
    );
  }

  await ref.update({
    reviewState: nextState,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, previousState: currentState, reviewState: nextState };
});

// ─── approveWork ─────────────────────────────────────────────────────────────

/**
 * CF-callable: move a work from review→approved.
 * Caller must be the work's creatorId OR an admin.
 * data: { workId: string }
 */
exports.approveWork = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { workId } = data || {};
  if (!workId) {
    throw new functions.https.HttpsError('invalid-argument', 'workId is required.');
  }

  const uid = context.auth.uid;
  const ref = db().collection('works').doc(workId);
  const snap = await ref.get();

  if (!snap.exists || snap.data().deletedAt !== null) {
    throw new functions.https.HttpsError('not-found', `Work "${workId}" not found.`);
  }

  const work = snap.data();

  // Only creator or admin may approve
  if (work.creatorId !== uid && !isAdmin(context)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only the creator or an admin can approve this work.'
    );
  }

  if (work.reviewState !== 'review') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Work must be in "review" state to approve. Current state: "${work.reviewState}".`
    );
  }

  await ref.update({
    reviewState: 'approved',
    approvedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, reviewState: 'approved' };
});

// ─── publishWork ─────────────────────────────────────────────────────────────

/**
 * CF-callable: human-gate publish step. Move approved→published.
 * Only the creator may publish. Sets visibility to 'public' (or caller-specified).
 * data: { workId: string, visibility?: 'public'|'community'|'unlisted' }
 */
exports.publishWork = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { workId, visibility } = data || {};
  if (!workId) {
    throw new functions.https.HttpsError('invalid-argument', 'workId is required.');
  }

  const VALID_VISIBILITIES = new Set(['public', 'community', 'unlisted']);
  const resolvedVisibility = visibility || 'public';
  if (!VALID_VISIBILITIES.has(resolvedVisibility)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `visibility must be one of: ${[...VALID_VISIBILITIES].join(', ')}.`
    );
  }

  const { ref, data: work } = await requireOwnWork(workId, context.auth.uid);

  if (work.reviewState !== 'approved') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Work must be in "approved" state to publish. Current state: "${work.reviewState}".`
    );
  }

  await ref.update({
    reviewState: 'published',
    visibility: resolvedVisibility,
    publishedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, reviewState: 'published', visibility: resolvedVisibility };
});

// ─── unpublishWork ────────────────────────────────────────────────────────────

/**
 * CF-callable: revert published→approved.
 * Only the creator may unpublish. Visibility resets to 'private'.
 * data: { workId: string }
 */
exports.unpublishWork = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { workId } = data || {};
  if (!workId) {
    throw new functions.https.HttpsError('invalid-argument', 'workId is required.');
  }

  const { ref, data: work } = await requireOwnWork(workId, context.auth.uid);

  if (work.reviewState !== 'published') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Work must be in "published" state to unpublish. Current state: "${work.reviewState}".`
    );
  }

  await ref.update({
    reviewState: 'approved',
    visibility: 'private',
    publishedAt: null,
    unpublishedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, reviewState: 'approved', visibility: 'private' };
});

// ─── softDeleteWork ───────────────────────────────────────────────────────────

/**
 * CF-callable: soft-delete a work (sets deletedAt). Never hard-deletes.
 * Creator or admin only. Works in any state.
 * data: { workId: string }
 */
exports.softDeleteWork = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { workId } = data || {};
  if (!workId) {
    throw new functions.https.HttpsError('invalid-argument', 'workId is required.');
  }

  const uid = context.auth.uid;
  const ref = db().collection('works').doc(workId);
  const snap = await ref.get();

  if (!snap.exists) {
    throw new functions.https.HttpsError('not-found', `Work "${workId}" not found.`);
  }

  const work = snap.data();
  if (work.deletedAt !== null) {
    // Already deleted — idempotent
    return { workId, deletedAt: work.deletedAt };
  }

  if (work.creatorId !== uid && !isAdmin(context)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only the creator or an admin can delete this work.'
    );
  }

  await ref.update({
    deletedAt: FieldValue.serverTimestamp(),
    // Unpublish if currently published
    ...(work.reviewState === 'published' ? { reviewState: 'approved', visibility: 'private', publishedAt: null } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { workId, deleted: true };
});

// ─── bulkAdvanceState ─────────────────────────────────────────────────────────

/**
 * CF-callable: batch advance up to 50 works at once (client transitions only).
 * data: { workIds: string[] }
 * Returns per-work results.
 */
exports.bulkAdvanceState = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const { workIds } = data || {};
  if (!Array.isArray(workIds) || workIds.length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'workIds must be a non-empty array.');
  }
  if (workIds.length > 50) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `bulkAdvanceState supports up to 50 works per call. Got ${workIds.length}.`
    );
  }

  const uid = context.auth.uid;
  const results = [];

  // Process sequentially to stay within Firestore write budget
  for (const workId of workIds) {
    try {
      const ref = db().collection('works').doc(workId);
      const snap = await ref.get();

      if (!snap.exists || snap.data().deletedAt !== null) {
        results.push({ workId, success: false, error: 'not_found' });
        continue;
      }

      const work = snap.data();
      if (work.creatorId !== uid) {
        results.push({ workId, success: false, error: 'permission_denied' });
        continue;
      }

      const nextState = CLIENT_TRANSITIONS[work.reviewState];
      if (!nextState) {
        results.push({
          workId,
          success: false,
          error: `no_client_transition_from_${work.reviewState}`,
        });
        continue;
      }

      await ref.update({
        reviewState: nextState,
        updatedAt: FieldValue.serverTimestamp(),
      });

      results.push({ workId, success: true, previousState: work.reviewState, reviewState: nextState });
    } catch (err) {
      results.push({ workId, success: false, error: err.message });
    }
  }

  return { results };
});
