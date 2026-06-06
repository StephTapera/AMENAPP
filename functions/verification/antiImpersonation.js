'use strict';

/**
 * antiImpersonation.js — Anti-Impersonation & Unofficial Catalog Protection
 *
 * Handles:
 *   - Impersonation reports with auto-flag at 3+ reports
 *   - Unofficial catalog labeling for unverified creators / unowned works
 *   - Name conflict detection for verified creators
 *   - Org admin transfer (HUMAN GATE — requires confirmed: true)
 *
 * SECURITY INVARIANTS:
 *   - Anti-impersonation reports are stored and flagged; NO auto-bans
 *   - transferOrgAdmin is a HUMAN GATE: requires explicit confirmed: true
 *   - Name conflict check is string similarity only (not semantic NLP)
 *   - Org admin custom claim changes use Firebase Admin SDK (server-side only)
 *
 * Exports (all CF onCall):
 *   reportImpersonation, checkCreatorProtection, transferOrgAdmin
 *
 * Internal utilities (not exported as CFs):
 *   getUnofficialCatalogLabel
 */

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

const REGION = 'us-central1';
const regionalFunctions = functions.region(REGION);

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/** Number of reports that triggers auto-flag for admin review. */
const AUTO_FLAG_THRESHOLD = 3;

/** Unofficial catalog label text — matches iOS UI contract. */
const UNOFFICIAL_LABEL_TEXT =
  'Unofficial catalog – content sourced from public data, not officially managed by this creator';

/** Minimum normalized Levenshtein similarity ratio to flag a name conflict. */
const NAME_CONFLICT_SIMILARITY_THRESHOLD = 0.85;

// ─────────────────────────────────────────────────────────────────────────────
// Internal Utilities
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Normalizes a display name for comparison:
 *   - lowercased
 *   - unicode NFD decomposed
 *   - non-alphanumeric chars (except spaces) stripped
 *   - multi-space collapsed
 */
function normalizeName(name) {
  return String(name)
    .normalize('NFD')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Computes the Levenshtein edit distance between two strings.
 * Uses iterative two-row approach (O(n*m) time, O(n) space).
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
function levenshtein(a, b) {
  const la = a.length;
  const lb = b.length;
  if (la === 0) return lb;
  if (lb === 0) return la;

  let prev = Array.from({ length: lb + 1 }, (_, i) => i);
  let curr = new Array(lb + 1);

  for (let i = 1; i <= la; i++) {
    curr[0] = i;
    for (let j = 1; j <= lb; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, curr] = [curr, prev];
  }

  return prev[lb];
}

/**
 * Returns a similarity ratio in [0, 1] between two strings.
 * 1.0 = identical, 0.0 = completely different.
 *
 * @param {string} a
 * @param {string} b
 * @returns {number}
 */
function similarityRatio(a, b) {
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1.0;
  const dist = levenshtein(a, b);
  return 1 - dist / maxLen;
}

// ─────────────────────────────────────────────────────────────────────────────
// getUnofficialCatalogLabel — internal utility (exported for module re-use)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Determines whether an "Unofficial catalog" label should be shown.
 *
 * Logic:
 *   - If creator has no verified badge → show label on ALL works
 *   - If a specific work has verifiedOwnership === false → show label on that work
 *   - If creator is verified AND work is verifiedOwnership === true → no label
 *
 * @param {{ creatorVerified: boolean, works: Array<{id: string, verifiedOwnership: boolean}> }} params
 * @returns {{ showUnofficialLabel: boolean, labelText: string, perWork: Record<string, boolean> }}
 */
function getUnofficialCatalogLabel({ creatorVerified, works = [] }) {
  const perWork = {};

  if (!creatorVerified) {
    // All works are unofficial if creator is not verified
    for (const work of works) {
      perWork[work.id] = true;
    }
    return {
      showUnofficialLabel: true,
      labelText: UNOFFICIAL_LABEL_TEXT,
      perWork,
    };
  }

  // Creator is verified — check individual work ownership
  let anyUnofficial = false;
  for (const work of works) {
    const unofficial = work.verifiedOwnership !== true;
    perWork[work.id] = unofficial;
    if (unofficial) anyUnofficial = true;
  }

  return {
    showUnofficialLabel: anyUnofficial,
    labelText: UNOFFICIAL_LABEL_TEXT,
    perWork,
  };
}

// Export utility for use by other modules without CF overhead
exports.getUnofficialCatalogLabel = getUnofficialCatalogLabel;

// ─────────────────────────────────────────────────────────────────────────────
// reportImpersonation
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates an impersonation report in Firestore.
 * Auto-flags for admin review when 3+ reports exist for the same target creator.
 *
 * Input:  { targetCreatorId, reporterNote }
 * Output: { reportId }
 *
 * Security:
 *   - No auto-bans. Flagging only — human admins decide next steps.
 *   - Reporter identity stored (context.auth.uid) for abuse prevention.
 */
exports.reportImpersonation = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const reporterId = context.auth.uid;
  const { targetCreatorId, reporterNote } = data || {};

  if (!targetCreatorId || typeof targetCreatorId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'targetCreatorId required');
  }

  // Sanitize reporterNote — max 1000 chars
  const sanitizedNote = typeof reporterNote === 'string'
    ? reporterNote.slice(0, 1000)
    : '';

  // Prevent self-reporting
  if (reporterId === targetCreatorId) {
    throw new functions.https.HttpsError('invalid-argument', 'You cannot report yourself for impersonation');
  }

  const firestore = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Check if this reporter has already filed against this creator (deduplicate)
  const existingSnap = await firestore
    .collection('impersonationReports')
    .where('targetCreatorId', '==', targetCreatorId)
    .where('reporterId', '==', reporterId)
    .limit(1)
    .get();

  if (!existingSnap.empty) {
    // Return the existing report ID rather than creating a duplicate
    return { reportId: existingSnap.docs[0].id, duplicate: true };
  }

  // Create the report
  const reportRef = firestore.collection('impersonationReports').doc();
  await reportRef.set({
    targetCreatorId,
    reporterId,
    reporterNote: sanitizedNote,
    status: 'open',
    createdAt: now,
    updatedAt: now,
  });

  // Count total open reports for this creator to determine if auto-flag threshold is met
  const totalReportsSnap = await firestore
    .collection('impersonationReports')
    .where('targetCreatorId', '==', targetCreatorId)
    .where('status', '==', 'open')
    .get();

  if (totalReportsSnap.size >= AUTO_FLAG_THRESHOLD) {
    // Flag the target creator for admin review
    // NO automatic suspension or ban — humans decide
    const targetUserRef = firestore.collection('users').doc(targetCreatorId);
    await targetUserRef.set(
      {
        flaggedForImpersonationReview: true,
        impersonationReportCount: totalReportsSnap.size,
        impersonationFlaggedAt: now,
      },
      { merge: true }
    );

    // Create an admin task
    await firestore.collection('adminReviewQueue').add({
      type: 'impersonation_review',
      targetCreatorId,
      reportCount: totalReportsSnap.size,
      flaggedAt: now,
      status: 'pending',
      priority: 'high',
    });

    functions.logger.warn('Impersonation auto-flag threshold reached', {
      targetCreatorId,
      reportCount: totalReportsSnap.size,
    });
  }

  return { reportId: reportRef.id };
});

// ─────────────────────────────────────────────────────────────────────────────
// checkCreatorProtection
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Checks whether an unverified creator's displayName conflicts with a verified creator's name.
 * Uses exact match + near-exact string similarity (Levenshtein), NOT semantic NLP.
 *
 * Input:  { creatorId, displayName }
 * Output: { nameConflict: boolean, conflictingCreatorId?: string, similarity?: number }
 *
 * Called during profile creation/edit to surface potential impersonation attempts.
 */
exports.checkCreatorProtection = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const requestingUid = context.auth.uid;
  const { creatorId, displayName } = data || {};

  if (!creatorId || typeof creatorId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'creatorId required');
  }
  if (!displayName || typeof displayName !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'displayName required');
  }

  // Security: only the creator themselves or an admin can call this
  if (requestingUid !== creatorId && !context.auth.token?.admin) {
    throw new functions.https.HttpsError('permission-denied', 'You may only check protection for your own account');
  }

  const firestore = admin.firestore();
  const normalizedInput = normalizeName(displayName);

  // Query verified users — fetch in pages (limit 200 for cold check; not a full-table scan)
  // Production improvement: maintain a dedicated verified-names index collection
  const verifiedSnap = await firestore
    .collection('users')
    .where('verified', '==', true)
    .select('displayName', 'badge')
    .limit(200)
    .get();

  let bestMatch = null;
  let bestSimilarity = 0;

  for (const doc of verifiedSnap.docs) {
    // Skip comparison against the creator themselves
    if (doc.id === creatorId) continue;

    const otherName = doc.data().displayName;
    if (!otherName) continue;

    const normalizedOther = normalizeName(otherName);
    const sim = similarityRatio(normalizedInput, normalizedOther);

    if (sim > bestSimilarity) {
      bestSimilarity = sim;
      bestMatch = doc.id;
    }
  }

  const conflict = bestSimilarity >= NAME_CONFLICT_SIMILARITY_THRESHOLD;

  return {
    nameConflict: conflict,
    ...(conflict ? { conflictingCreatorId: bestMatch, similarity: Math.round(bestSimilarity * 100) / 100 } : {}),
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// transferOrgAdmin — HUMAN GATE
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Transfers org admin role from the current caller to a new user.
 *
 * HUMAN GATE: caller must explicitly pass { confirmed: true }.
 * Without this flag the operation is rejected, forcing deliberate action.
 *
 * Requirements:
 *   - Caller must have org_admin custom claim for the target orgId
 *   - newAdminId must be a valid, existing Firebase Auth user
 *   - Logs the full transfer audit trail
 *
 * Input:  { orgId, newAdminId, confirmed }
 * Output: { transferred: boolean }
 */
exports.transferOrgAdmin = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const currentAdminUid = context.auth.uid;
  const { orgId, newAdminId, confirmed } = data || {};

  // HUMAN GATE — must explicitly confirm
  if (confirmed !== true) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Admin transfer requires explicit confirmation. Pass { confirmed: true } to proceed. This action cannot be undone.'
    );
  }

  if (!orgId || typeof orgId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'orgId required');
  }
  if (!newAdminId || typeof newAdminId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'newAdminId required');
  }
  if (newAdminId === currentAdminUid) {
    throw new functions.https.HttpsError('invalid-argument', 'newAdminId must be different from the current admin');
  }

  // Verify caller has org_admin claim for this org
  const callerClaims = context.auth.token;
  const callerOrgAdminOrgs = callerClaims.orgAdmin || [];

  const hasOrgAdminClaim =
    callerClaims.admin === true || // platform admin bypasses
    (Array.isArray(callerOrgAdminOrgs) && callerOrgAdminOrgs.includes(orgId));

  if (!hasOrgAdminClaim) {
    throw new functions.https.HttpsError(
      'permission-denied',
      `You do not have org_admin rights for organization ${orgId}`
    );
  }

  const firestore = admin.firestore();

  // Verify the organization exists
  const orgRef = firestore.collection('organizations').doc(orgId);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) {
    throw new functions.https.HttpsError('not-found', `Organization ${orgId} not found`);
  }

  // Verify new admin is a valid existing Firebase Auth user
  let newAdminRecord;
  try {
    newAdminRecord = await admin.auth().getUser(newAdminId);
  } catch (err) {
    throw new functions.https.HttpsError('not-found', `User ${newAdminId} not found in Firebase Auth`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();

  // Update Firestore org admins subcollection
  const adminsRef = orgRef.collection('admins');
  const newAdminRef = adminsRef.doc(newAdminId);
  const oldAdminRef = adminsRef.doc(currentAdminUid);

  const firestoreBatch = firestore.batch();

  // Add new admin record
  firestoreBatch.set(newAdminRef, {
    uid: newAdminId,
    email: newAdminRecord.email || null,
    grantedAt: now,
    grantedBy: currentAdminUid,
    role: 'org_admin',
  });

  // Remove old admin from active org admins (keep record for audit)
  firestoreBatch.update(oldAdminRef, {
    removedAt: now,
    removedBy: currentAdminUid,
    transferredTo: newAdminId,
    active: false,
  });

  await firestoreBatch.commit();

  // Update Firebase custom claims — server-side only
  // Grant new admin their org claim
  const newAdminCurrentClaims = newAdminRecord.customClaims || {};
  const newAdminOrgs = Array.isArray(newAdminCurrentClaims.orgAdmin)
    ? newAdminCurrentClaims.orgAdmin
    : [];
  if (!newAdminOrgs.includes(orgId)) {
    newAdminOrgs.push(orgId);
  }
  await admin.auth().setCustomUserClaims(newAdminId, {
    ...newAdminCurrentClaims,
    orgAdmin: newAdminOrgs,
  });

  // Revoke current admin's org claim for this org
  const currentAdminRecord = await admin.auth().getUser(currentAdminUid);
  const currentClaims = currentAdminRecord.customClaims || {};
  const currentOrgList = Array.isArray(currentClaims.orgAdmin) ? currentClaims.orgAdmin : [];
  const updatedOrgList = currentOrgList.filter((o) => o !== orgId);
  await admin.auth().setCustomUserClaims(currentAdminUid, {
    ...currentClaims,
    orgAdmin: updatedOrgList,
  });

  // Audit log
  await firestore.collection('verificationAuditLog').add({
    action: 'org_admin_transferred',
    orgId,
    fromUid: currentAdminUid,
    toUid: newAdminId,
    toEmail: newAdminRecord.email || null,
    timestamp: now,
  });

  functions.logger.info('Org admin transferred', {
    orgId,
    from: currentAdminUid,
    to: newAdminId,
  });

  return { transferred: true };
});
