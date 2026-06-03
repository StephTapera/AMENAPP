/**
 * adminModerationFunctions.js
 * Admin-only Cloud Functions for crisis alert queue management.
 *
 * H-23 fix: surfaces crisisAlert items at the top of the moderation queue.
 *
 * Collections queried:
 *   moderatorAlerts  — written by handleCriticalCrisis() in aiModeration.js
 *                      (type: "critical_crisis", urgencyLevel: "critical")
 *   pastoralAlerts   — written by mlContentPipeline.js and mlCommunityIntelligence.js
 *                      (severity: "high" | "medium", status: "unreviewed")
 *
 * Auth model: caller must have admin: true, superAdmin: true, or moderator: true
 * custom claim (set via adminClaims.js grantAdminRole / custom claim tooling).
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const REGION = 'us-central1';

// Valid resolution types for crisis alerts.
const VALID_RESOLUTIONS = [
  'safe',
  'contacted_user',
  'escalated_to_counselor',
  'false_positive',
  'referred_988',
];

// ─────────────────────────────────────────────────────────────────────────────
// Shared auth helper: verify admin or moderator custom claim.
// We read from the Auth record (getUser) rather than trusting the JWT token
// alone, to pick up moderator claims that were granted after the current
// session started.
// ─────────────────────────────────────────────────────────────────────────────
async function requireModerator(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const userRecord = await admin.auth().getUser(request.auth.uid);
  const claims = userRecord.customClaims ?? {};
  if (!claims.admin && !claims.superAdmin && !claims.moderator) {
    throw new HttpsError('permission-denied', 'Moderator or admin role required.');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// getCrisisAlertQueue — admin-only
// Returns all active (unresolved) crisis alerts ordered by urgency then time.
// Designed to be polled by the admin panel on a 30-second interval.
//
// Data sources (merged and re-sorted in memory):
//   1. moderatorAlerts where type == "critical_crisis" and resolved != true
//   2. pastoralAlerts  where severity in ["high"] and status == "unreviewed"
//
// Request data:
//   limit (number, default 50, max 100) — total items to return
// ─────────────────────────────────────────────────────────────────────────────
exports.getCrisisAlertQueue = onCall(
  {
    enforceAppCheck: false, // admin tool — protected by role check below
    region: REGION,
    timeoutSeconds: 30,
  },
  async (request) => {
    await requireModerator(request);

    const db = admin.firestore();
    const limit = Math.min(Number(request.data?.limit) || 50, 100);

    // ── 1. moderatorAlerts: critical_crisis items ──────────────────────────
    // These are written by handleCriticalCrisis() in aiModeration.js.
    // They do not have a 'resolved' field by default; resolveAlert() adds it.
    let moderatorAlertsSnap;
    try {
      moderatorAlertsSnap = await db.collection('moderatorAlerts')
        .where('type', '==', 'critical_crisis')
        .where('resolved', '==', false)
        .orderBy('timestamp', 'desc')
        .limit(limit)
        .get();
    } catch (_) {
      // 'resolved' field may not exist on older docs — fall back to unfiltered query.
      // We filter in memory below.
      moderatorAlertsSnap = await db.collection('moderatorAlerts')
        .where('type', '==', 'critical_crisis')
        .orderBy('timestamp', 'desc')
        .limit(limit)
        .get();
    }

    const moderatorAlertDocs = moderatorAlertsSnap.docs
      .filter(doc => doc.data().resolved !== true)
      .map(doc => {
        const d = doc.data();
        return {
          id: doc.id,
          source: 'moderatorAlerts',
          surface: d.surface ?? 'unknown',
          userId: d.userId ?? null,
          crisisTypes: d.crisisTypes ?? [],
          urgencyLevel: d.urgencyLevel ?? 'critical',
          contentSnippet: d.contentSnippet ?? null,
          createdAt: d.timestamp?.toMillis?.() ?? null,
          resolved: d.resolved ?? false,
          // Normalised fields for the panel
          crisisAlert: true,
          type: d.type,
        };
      });

    // ── 2. pastoralAlerts: high-severity unreviewed items ─────────────────
    // Written by mlContentPipeline.js when hasCrisisKeyword is detected.
    const pastoralSnap = await db.collection('pastoralAlerts')
      .where('status', '==', 'unreviewed')
      .where('severity', 'in', ['high', 'critical'])
      .orderBy('detectedAt', 'desc')
      .limit(limit)
      .get();

    const pastoralDocs = pastoralSnap.docs.map(doc => {
      const d = doc.data();
      return {
        id: doc.id,
        source: 'pastoralAlerts',
        surface: d.surface ?? 'prayer',
        userId: d.userId ?? d.authorId ?? null,
        crisisTypes: d.signals ?? [],
        urgencyLevel: d.severity === 'critical' ? 'critical' : 'high',
        contentSnippet: d.contentSnippet ?? null,
        createdAt: d.detectedAt?.toMillis?.() ?? null,
        resolved: false,
        crisisAlert: true,
        type: d.type ?? 'pre_incident_pattern',
      };
    });

    // ── 3. Merge + sort by urgency (critical first) then time (newest first) ─
    const URGENCY_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };
    const all = [...moderatorAlertDocs, ...pastoralDocs]
      .sort((a, b) => {
        const urgencyDiff =
          (URGENCY_ORDER[a.urgencyLevel] ?? 99) -
          (URGENCY_ORDER[b.urgencyLevel] ?? 99);
        if (urgencyDiff !== 0) return urgencyDiff;
        return (b.createdAt ?? 0) - (a.createdAt ?? 0);
      })
      .slice(0, limit);

    return { alerts: all, count: all.length };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// resolveAlert — admin-only
// Marks a crisis alert as reviewed and resolved.
//
// Request data:
//   alertId    (string, required) — Firestore document ID
//   source     (string, required) — "moderatorAlerts" | "pastoralAlerts"
//   resolution (string, required) — one of VALID_RESOLUTIONS
//   notes      (string, optional) — free-text resolution notes
// ─────────────────────────────────────────────────────────────────────────────
exports.resolveAlert = onCall(
  {
    enforceAppCheck: false,
    region: REGION,
    timeoutSeconds: 30,
  },
  async (request) => {
    await requireModerator(request);

    const { alertId, source, resolution, notes } = request.data ?? {};

    if (!alertId || typeof alertId !== 'string') {
      throw new HttpsError('invalid-argument', 'alertId (string) required.');
    }
    if (!resolution || !VALID_RESOLUTIONS.includes(resolution)) {
      throw new HttpsError(
        'invalid-argument',
        `resolution must be one of: ${VALID_RESOLUTIONS.join(', ')}.`
      );
    }

    const ALLOWED_SOURCES = ['moderatorAlerts', 'pastoralAlerts'];
    const collectionName = ALLOWED_SOURCES.includes(source) ? source : 'moderatorAlerts';

    const db = admin.firestore();
    const docRef = db.collection(collectionName).doc(alertId);
    const snap = await docRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', `Alert ${alertId} not found in ${collectionName}.`);
    }

    const resolvedAt = admin.firestore.Timestamp.now();
    await docRef.update({
      resolved: true,
      resolvedBy: request.auth.uid,
      resolvedAt,
      resolution,
      resolutionNotes: notes ?? '',
      // Normalise status field for both collections
      status: 'resolved',
    });

    // Audit trail
    await db.collection('adminClaimLog').add({
      action: 'resolve_crisis_alert',
      alertId,
      collection: collectionName,
      resolution,
      resolvedBy: request.auth.uid,
      resolvedAt,
      notes: notes ?? '',
    });

    console.log(
      `[adminModeration] ${request.auth.uid} resolved ${collectionName}/${alertId} as ${resolution}`
    );
    return { success: true };
  }
);
