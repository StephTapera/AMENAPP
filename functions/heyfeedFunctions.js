'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
// onHeyFeedRequestCreated
// Fires when a new doc is written to heyfeed_requests/{requestId}.
// Validates required fields, sends pastoral care alerts if needed,
// stamps processedAt, and increments heyFeedRequestCount on the post.
// ---------------------------------------------------------------------------
exports.onHeyFeedRequestCreated = onDocumentCreated(
  {
    document: 'heyfeed_requests/{requestId}',
    region: 'us-central1',
  },
  async (event) => {
    const db = admin.firestore();
    const snap = event.data;
    if (!snap) {
      console.error('onHeyFeedRequestCreated: no snapshot data');
      return;
    }

    const requestId = event.params.requestId;
    const data = snap.data();

    // Validate required fields
    const requiredFields = ['postId', 'authorId', 'requestType', 'isActive'];
    for (const field of requiredFields) {
      if (data[field] === undefined || data[field] === null) {
        console.error(
          `onHeyFeedRequestCreated: missing required field "${field}" on request ${requestId}`
        );
        return;
      }
    }

    const { postId, authorId, requestType } = data;
    const batch = db.batch();

    // If requestType is "care" or "crisis", alert the pastoral team
    if (requestType === 'care' || requestType === 'crisis') {
      const alertRef = db
        .collection('notifications')
        .doc('pastoral_team')
        .collection('alerts')
        .doc(requestId);

      batch.set(alertRef, {
        type: 'pastoral_care_alert',
        requestId,
        postId,
        authorId,
        requestType,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });

      console.log(
        `onHeyFeedRequestCreated: pastoral care alert queued for request ${requestId} (type: ${requestType})`
      );
    }

    // Stamp processedAt on the request doc
    const requestRef = db.collection('heyfeed_requests').doc(requestId);
    batch.update(requestRef, {
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Increment heyFeedRequestCount on the post if it exists
    const postRef = db.collection('posts').doc(postId);
    const postSnap = await postRef.get();
    if (postSnap.exists) {
      await postRef.update({
        heyFeedRequestCount: admin.firestore.FieldValue.increment(1),
      });
      console.log(
        `onHeyFeedRequestCreated: incremented heyFeedRequestCount on post ${postId}`
      );
    } else {
      console.warn(
        `onHeyFeedRequestCreated: post ${postId} not found, skipping count increment`
      );
    }

    console.log(
      `onHeyFeedRequestCreated: finished processing request ${requestId}`
    );
  }
);

// ---------------------------------------------------------------------------
// computeHeyFeedResonance
// onCall (authenticated). Aggregates resonance docs for a given requestId,
// computes a weighted score, and writes the result back to the request doc.
// ---------------------------------------------------------------------------
exports.computeHeyFeedResonance = onCall(
  { region: 'us-central1', enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();

    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be signed in to compute resonance.'
      );
    }

    const { requestId, postId } = request.data || {};

    if (!requestId || typeof requestId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'A valid requestId string is required.'
      );
    }

    if (!postId || typeof postId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'A valid postId string is required.'
      );
    }

    // Resonance type weights
    const weights = {
      praying: 0.06,
      standing: 0.05,
      witnessed: 0.04,
      helped: 0.05,
      encouraged: 0.03,
    };

    // Aggregate resonance docs for this requestId
    const resonanceSnap = await db
      .collection('heyfeed_resonance')
      .where('requestId', '==', requestId)
      .get();

    const resonanceCounts = {
      praying: 0,
      standing: 0,
      witnessed: 0,
      helped: 0,
      encouraged: 0,
    };

    resonanceSnap.forEach((doc) => {
      const type = doc.data().type;
      if (type && resonanceCounts[type] !== undefined) {
        resonanceCounts[type] += 1;
      }
    });

    const resonanceCount = resonanceSnap.size;

    // Compute weighted score, capped at 1.0
    let rawScore = 0;
    for (const [type, count] of Object.entries(resonanceCounts)) {
      rawScore += count * (weights[type] || 0);
    }
    const resonanceScore = Math.min(rawScore, 1.0);

    // Write results back to the request doc
    const requestRef = db.collection('heyfeed_requests').doc(requestId);
    await requestRef.update({
      resonanceScore,
      resonanceCount,
      resonanceCounts,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `computeHeyFeedResonance: requestId=${requestId} score=${resonanceScore} count=${resonanceCount}`
    );

    return { success: true, resonanceScore, resonanceCount };
  }
);

// ---------------------------------------------------------------------------
// cleanupExpiredHeyFeedRequests
// Runs every 6 hours. Marks expired requests inactive, and permanently
// deletes requests older than 30 days.
// ---------------------------------------------------------------------------
exports.cleanupExpiredHeyFeedRequests = onSchedule(
  { schedule: '0 */6 * * *', region: 'us-central1', timeZone: 'UTC' },
  async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(
      now.toMillis() - 30 * 24 * 60 * 60 * 1000
    );

    const MAX_BATCH = 400;

    // --- 1. Mark expired-but-active requests as inactive ---
    const expiredSnap = await db
      .collection('heyfeed_requests')
      .where('expiresAt', '<', now)
      .where('isActive', '==', true)
      .get();

    let expiredCount = 0;
    let batch = db.batch();
    let opsInBatch = 0;

    for (const doc of expiredSnap.docs) {
      batch.update(doc.ref, { isActive: false });
      opsInBatch++;
      expiredCount++;

      if (opsInBatch >= MAX_BATCH) {
        await batch.commit();
        batch = db.batch();
        opsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    // --- 2. Permanently delete requests older than 30 days ---
    const oldSnap = await db
      .collection('heyfeed_requests')
      .where('createdAt', '<', thirtyDaysAgo)
      .get();

    let deletedCount = 0;
    batch = db.batch();
    opsInBatch = 0;

    for (const doc of oldSnap.docs) {
      batch.delete(doc.ref);
      opsInBatch++;
      deletedCount++;

      if (opsInBatch >= MAX_BATCH) {
        await batch.commit();
        batch = db.batch();
        opsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    console.log(
      `cleanupExpiredHeyFeedRequests: marked ${expiredCount} expired, deleted ${deletedCount} old requests`
    );
  }
);

// ---------------------------------------------------------------------------
// detectPastoralCareSignals
// Runs daily at 6 AM UTC. Finds unacknowledged high-urgency pastoral care
// signals and writes alert notifications for the pastoral team.
// ---------------------------------------------------------------------------
exports.detectPastoralCareSignals = onSchedule(
  { schedule: '0 6 * * *', region: 'us-central1', timeZone: 'UTC' },
  async () => {
    const db = admin.firestore();

    const signalsSnap = await db
      .collection('pastoral_care_signals')
      .where('isAcknowledged', '==', false)
      .where('urgencyScore', '>=', 0.7)
      .get();

    if (signalsSnap.empty) {
      console.log('detectPastoralCareSignals: no high-urgency signals found');
      return;
    }

    const MAX_BATCH = 400;
    let batch = db.batch();
    let opsInBatch = 0;
    let alertCount = 0;

    for (const doc of signalsSnap.docs) {
      const signal = doc.data();
      const signalId = doc.id;

      const alertRef = db
        .collection('notifications')
        .doc('pastoral_alerts')
        .collection('signals')
        .doc(signalId);

      batch.set(
        alertRef,
        {
          ...signal,
          signalId,
          notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      opsInBatch++;
      alertCount++;

      console.log(
        `detectPastoralCareSignals: signal ${signalId} postId=${signal.postId} urgencyScore=${signal.urgencyScore}`
      );

      if (opsInBatch >= MAX_BATCH) {
        await batch.commit();
        batch = db.batch();
        opsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    console.log(
      `detectPastoralCareSignals: wrote ${alertCount} pastoral care alert(s)`
    );

    return alertCount;
  }
);

// ---------------------------------------------------------------------------
// acknowledgeHeyFeedSignal
// onCall (authenticated, admin-only). Marks a pastoral_care_signal as
// acknowledged. Caller must be listed in ADMIN_UIDS env var.
// ---------------------------------------------------------------------------
exports.acknowledgeHeyFeedSignal = onCall(
  { region: 'us-central1', enforceAppCheck: false },
  async (request) => {
    const db = admin.firestore();

    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be signed in to acknowledge a signal.'
      );
    }

    const uid = request.auth.uid;

    // Admin check — ADMIN_UIDS is a comma-separated env var
    const adminUids = (process.env.ADMIN_UIDS || '')
      .split(',')
      .map((id) => id.trim())
      .filter(Boolean);

    if (!adminUids.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Only admins can acknowledge pastoral care signals.'
      );
    }

    const { signalId } = request.data || {};

    if (!signalId || typeof signalId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'A valid signalId string is required.'
      );
    }

    const signalRef = db.collection('pastoral_care_signals').doc(signalId);
    const signalSnap = await signalRef.get();

    if (!signalSnap.exists) {
      throw new HttpsError(
        'not-found',
        `No pastoral_care_signal found with id ${signalId}.`
      );
    }

    await signalRef.update({
      isAcknowledged: true,
      acknowledgedBy: uid,
      acknowledgedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(
      `acknowledgeHeyFeedSignal: signal ${signalId} acknowledged by ${uid}`
    );

    return { success: true };
  }
);
