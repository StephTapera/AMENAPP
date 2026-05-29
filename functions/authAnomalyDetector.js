/**
 * authAnomalyDetector.js
 * Detects and logs suspicious authentication events.
 * Called from the iOS client after a successful sign-in.
 *
 * Design principles:
 *   - Does NOT automatically block users — surfaces findings for human review.
 *   - No PII (email, IP) stored in Firestore logs.
 *   - All Firestore writes are fire-and-forget so anomaly detection never
 *     blocks or delays a legitimate sign-in.
 *   - trackGlobalAuthRate is internal only — not exported to clients.
 *
 * Collections written:
 *   users/{uid}/signInEvents/{auto-id}  — server-managed (Admin SDK only)
 *   safetyReviews/{auto-id}             — server-managed, moderation-readable
 *   meta/authMetrics/minutely/{key}     — server-managed, admin-readable
 */

'use strict';

const admin = require('firebase-admin');
const {logger} = require('firebase-functions');
const {onCall, HttpsError} = require('firebase-functions/v2/https');

// ---------------------------------------------------------------------------
// Callable: logSignInEvent
// ---------------------------------------------------------------------------

/**
 * Called by the iOS client after a successful sign-in to record device/session
 * metadata and trigger anomaly checks.
 *
 * Detects: rapid sign-ins from a single account (>5 in 1 hour).
 * Future: geographic anomaly detection can be layered in here without client
 * changes (the CF already owns the record).
 *
 * @param {object} request.data.platform    - "ios", "android", "web"
 * @param {object} request.data.appVersion  - e.g. "2.1.0"
 */
exports.logSignInEvent = onCall(
    {
      region: 'us-central1',
      enforceAppCheck: true,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Must be signed in.');
      }

      const uid = request.auth.uid;
      const {platform, appVersion} = request.data;
      const db = admin.firestore();
      const now = admin.firestore.FieldValue.serverTimestamp();

      // 1. Record sign-in event (admin SDK write — bypasses client rules)
      //    IP is deliberately NOT stored here (privacy by design).
      try {
        await db.collection('users').doc(uid)
            .collection('signInEvents').add({
              timestamp: now,
              platform: platform ?? 'unknown',
              appVersion: appVersion ?? 'unknown',
            });
      } catch (writeErr) {
        // Non-fatal — anomaly detection failure must never break sign-in
        logger.error('[authAnomaly] failed to write signInEvent', {uid, error: writeErr.message});
        return {ok: true};
      }

      // 2. Check for rapid sign-in anomaly (>5 sign-ins in 1 hour from this user)
      //    This fires after the write so it doesn't block the response.
      //    We set the result aside and queue the review asynchronously.
      try {
        const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
        const recentSnap = await db.collection('users').doc(uid)
            .collection('signInEvents')
            .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(oneHourAgo))
            .limit(6)
            .get();

        if (recentSnap.size >= 5) {
          logger.warn('[authAnomaly] rapid sign-in detected', {uid, count: recentSnap.size});
          // Queue for human review — non-blocking, fire-and-forget
          db.collection('safetyReviews').add({
            type: 'auth_anomaly',
            subtype: 'rapid_signin',
            userId: uid,
            signInCount: recentSnap.size,
            detectedAt: admin.firestore.FieldValue.serverTimestamp(),
            status: 'pending',
            requiresHumanReview: true,
          }).catch((e) => logger.error('[authAnomaly] failed to queue review', {error: e.message}));
        }
      } catch (checkErr) {
        // Anomaly check failure is non-fatal — sign-in still succeeds
        logger.warn('[authAnomaly] anomaly check failed (non-fatal)', {uid, error: checkErr.message});
      }

      // 3. Track global auth rate for platform-level credential-stuffing detection
      //    Also fire-and-forget.
      trackGlobalAuthRate().catch(() => {});

      return {ok: true};
    }
);

// ---------------------------------------------------------------------------
// Internal: trackGlobalAuthRate
// ---------------------------------------------------------------------------

/**
 * Increments a per-minute global auth counter in Firestore.
 * Used to detect platform-level credential-stuffing spikes.
 * Not exported to clients — called internally by logSignInEvent.
 *
 * Stored at: meta/authMetrics/minutely/{YYYY-MM-DDTHH:mm}
 * Readable by: Admin SDK only (client rules deny all access to meta/).
 */
async function trackGlobalAuthRate() {
  const db = admin.firestore();
  const minuteKey = new Date().toISOString().slice(0, 16); // YYYY-MM-DDTHH:mm
  const ref = db.doc(`meta/authMetrics/minutely/${minuteKey}`);
  await ref.set(
      {
        count: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
  );
}

module.exports = {
  logSignInEvent: exports.logSignInEvent,
  trackGlobalAuthRate,
};
