// appealsService.js
// AMEN Governance — User appeals for automated actions.
// Every automated action that restricts, hides, or scores a user has a logged
// reason and a user-facing appeal path that reaches a human reviewer.

'use strict';

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');

// ── Submit an appeal ───────────────────────────────────────────────────────────

exports.submitAppeal = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in to appeal.');
    const uid = request.auth.uid;

    const { actionId, actionType, reason, additionalContext } = request.data;

    if (!actionId || !actionType) {
      throw new HttpsError('invalid-argument', 'actionId and actionType are required.');
    }

    // [DECISION REQUIRED]: validate that actionType is in the approved list
    const APPEALABLE_ACTIONS = [
      'post_removed', 'comment_removed', 'account_restricted',
      'berean_response_blocked', 'church_deverified', 'content_hidden',
    ]; // [DECISION REQUIRED]: confirm this list (see docs/governance/GOVERNANCE.md D-01)

    if (!APPEALABLE_ACTIONS.includes(actionType)) {
      throw new HttpsError('invalid-argument', `Action type '${actionType}' is not appealable.`);
    }

    // Rate limit: max 3 appeals per day per user
    const dayKey = new Date().toISOString().slice(0, 10);
    const rateRef = admin.firestore().doc(`users/${uid}/appealRateLimits/${dayKey}`);
    const rateSnap = await rateRef.get();
    const count = rateSnap.exists ? (rateSnap.data().count ?? 0) : 0;
    if (count >= 3) {
      throw new HttpsError('resource-exhausted', 'Maximum 3 appeals per day. Please try again tomorrow.');
    }
    await rateRef.set({ count: count + 1 }, { merge: true });

    const db = admin.firestore();
    const appealRef = await db.collection('appeals').add({
      userId: uid,
      actionId,
      actionType,
      reason: (reason ?? '').slice(0, 2000),         // cap user reason
      additionalContext: (additionalContext ?? '').slice(0, 1000),
      status: 'pending',
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedAt: null,
      reviewedBy: null,
      outcome: null,
      outcomeReason: null,
    });

    // Increment transparency log
    const monthKey = new Date().toISOString().slice(0, 7); // "YYYY-MM"
    await db.doc(`meta/automatedActionCounts/${monthKey}`).set(
      { appeals_submitted: admin.firestore.FieldValue.increment(1) },
      { merge: true }
    ).catch(() => {}); // non-blocking — never fail a user-facing call on telemetry write

    logger.info('[appeals] appeal submitted', { uid, actionId, actionType, appealId: appealRef.id });

    // [DECISION REQUIRED]: notify reviewer (Slack, email, push to moderation dashboard)
    // See docs/governance/GOVERNANCE.md D-09 for the notification channel decision.
    // await notifyReviewers(appealRef.id, actionType);

    return {
      appealId: appealRef.id,
      status: 'pending',
      message: 'Your appeal has been received and will be reviewed by our team.',
    };
  }
);

// ── Get appeal status (owner only) ────────────────────────────────────────────

exports.getAppealStatus = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');
    const uid = request.auth.uid;
    const { appealId } = request.data;
    if (!appealId) throw new HttpsError('invalid-argument', 'appealId required.');

    const snap = await admin.firestore().collection('appeals').doc(appealId).get();
    if (!snap.exists) throw new HttpsError('not-found', 'Appeal not found.');

    const data = snap.data();
    if (data.userId !== uid) throw new HttpsError('permission-denied', 'Not your appeal.');

    return {
      appealId: snap.id,
      status: data.status,
      submittedAt: data.submittedAt,
      outcome: data.outcome,
      outcomeReason: data.outcomeReason,
      reviewedAt: data.reviewedAt,
    };
  }
);

// ── HITL gate: review and act on appeal (moderator only) ──────────────────────

exports.resolveAppeal = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Must be signed in.');
    const uid = request.auth.uid;

    // Verify moderator role
    const token = request.auth.token;
    if (!token.moderator && !token.admin) {
      throw new HttpsError('permission-denied', 'Moderator role required.');
    }

    const { appealId, outcome, outcomeReason } = request.data;
    if (!appealId || !outcome) throw new HttpsError('invalid-argument', 'appealId and outcome required.');
    if (!['approved', 'denied', 'escalated'].includes(outcome)) {
      throw new HttpsError('invalid-argument', 'outcome must be approved, denied, or escalated.');
    }

    const db = admin.firestore();

    // Fetch the appeal to get the userId for notification
    const appealSnap = await db.collection('appeals').doc(appealId).get();
    if (!appealSnap.exists) throw new HttpsError('not-found', 'Appeal not found.');
    const appealData = appealSnap.data();

    await db.collection('appeals').doc(appealId).update({
      status: outcome === 'escalated' ? 'escalated' : 'resolved',
      outcome,
      outcomeReason: (outcomeReason ?? '').slice(0, 1000),
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      reviewedBy: uid,
    });

    // Increment transparency log
    const monthKey = new Date().toISOString().slice(0, 7);
    await db.doc(`meta/automatedActionCounts/${monthKey}`).set(
      { [`appeals_${outcome}`]: admin.firestore.FieldValue.increment(1) },
      { merge: true }
    ).catch(() => {});

    logger.info('[appeals] resolved', { appealId, outcome, reviewedBy: uid, userId: appealData.userId });

    // [DECISION REQUIRED]: if outcome === 'approved', automatically reverse the action
    // or queue it for reversal. This depends on the action type.
    // See docs/governance/GOVERNANCE.md D-08 for the reversal mechanism decision.
    // if (outcome === 'approved') {
    //   await reverseAction(appealData.actionId, appealData.actionType);
    // }

    // [DECISION REQUIRED]: notify the user of the appeal outcome.
    // See docs/governance/GOVERNANCE.md D-10 for approved notification copy.
    // await notifyUser(appealData.userId, appealId, outcome, outcomeReason);

    return { appealId, outcome, message: 'Appeal resolved.' };
  }
);
