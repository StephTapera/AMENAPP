// TODO(gate: HUMAN-MACHINE) — MIGRATE_TO_V2: still using Gen1 runWith() pattern; migration requires re-deploy + smoke-test
/**
 * adminClaims.js — v1 Cloud Functions (avoids Cloud Run quota)
 * Server-side admin role management via Firebase Custom Claims.
 *
 * Usage in Firestore rules:
 *   function isAdmin() { return request.auth.token.admin == true; }
 */

'use strict';

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

const REGION = 'us-central1';
const regionalFunctions = functions.region(REGION);

// ─────────────────────────────────────────────────────────────────────────────
// grantAdminRole — callable by existing admins only
// ─────────────────────────────────────────────────────────────────────────────
exports.grantAdminRole = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth?.token?.admin) {
    throw new functions.https.HttpsError('permission-denied', 'Only admins can grant admin roles');
  }

  const { targetUid } = data;
  if (!targetUid || typeof targetUid !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'targetUid required');
  }

  // SECURITY FIX (MEDIUM 2026-06-11): Read existing claims before overwriting so
  // other claims (ageTier, moderator, orgAdmin) are not silently wiped.
  const existingUser = await admin.auth().getUser(targetUid);
  const existingClaims = existingUser.customClaims || {};
  await admin.auth().setCustomUserClaims(targetUid, { ...existingClaims, admin: true });

  await admin.firestore().collection('users').doc(targetUid).update({
    isAdmin: true,
    adminGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
    adminGrantedBy: context.auth.uid,
  });

  await admin.firestore().collection('adminClaimLog').add({
    targetUid,
    grantedBy: context.auth.uid,
    action: 'grant_admin',
    claimExpiry: admin.firestore.Timestamp.fromMillis(Date.now() + 90 * 24 * 60 * 60 * 1000),
    grantedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // SECURITY FIX (HIGH 2026-06-11): Revoke refresh tokens so the new admin claim
  // takes effect immediately rather than waiting up to 60 min for token expiry.
  await admin.auth().revokeRefreshTokens(targetUid);

  console.log(`[adminClaims] Granted admin to ${targetUid} by ${context.auth.uid}`);
  return { success: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// revokeAdminRole — callable by existing admins only
// ─────────────────────────────────────────────────────────────────────────────
exports.revokeAdminRole = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth?.token?.admin) {
    throw new functions.https.HttpsError('permission-denied', 'Only admins can revoke admin roles');
  }

  const { targetUid } = data;
  if (!targetUid || typeof targetUid !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'targetUid required');
  }

  if (targetUid === context.auth.uid) {
    throw new functions.https.HttpsError('invalid-argument', 'Admins cannot revoke their own admin role');
  }

  // SECURITY FIX (MEDIUM 2026-06-11): Read existing claims before overwriting so
  // other claims (ageTier, moderator, orgAdmin) are not silently wiped.
  const existingRevokeUser = await admin.auth().getUser(targetUid);
  const existingRevokeClaims = existingRevokeUser.customClaims || {};
  await admin.auth().setCustomUserClaims(targetUid, { ...existingRevokeClaims, admin: false });

  await admin.firestore().collection('users').doc(targetUid).update({
    isAdmin: false,
    adminRevokedAt: admin.firestore.FieldValue.serverTimestamp(),
    adminRevokedBy: context.auth.uid,
  });

  await admin.firestore().collection('adminClaimLog').add({
    targetUid,
    revokedBy: context.auth.uid,
    action: 'revoke_admin',
    claimExpiry: admin.firestore.Timestamp.fromMillis(Date.now() + 90 * 24 * 60 * 60 * 1000),
    revokedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // SECURITY FIX (HIGH 2026-06-11): Revoke refresh tokens CRITICAL for revoke path —
  // a just-revoked admin retains privilege for up to 60 minutes without this.
  await admin.auth().revokeRefreshTokens(targetUid);

  console.log(`[adminClaims] Revoked admin from ${targetUid} by ${context.auth.uid}`);
  return { success: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// bootstrapFirstAdmin — one-time setup, restricted to ADMIN_UIDS env var
// ─────────────────────────────────────────────────────────────────────────────
exports.bootstrapFirstAdmin = regionalFunctions.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');

  // SECURITY FIX (MEDIUM 2026-06-11): Fail closed if ADMIN_UIDS is unset or empty —
  // an empty list previously silently rejected everyone with a generic permission-denied
  // making misconfiguration hard to diagnose. Now we throw a distinct error to surface
  // the configuration gap immediately.
  const adminUidsRaw = process.env.ADMIN_UIDS;
  if (!adminUidsRaw || !adminUidsRaw.trim()) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'ADMIN_UIDS environment variable is not configured. Set it in Firebase Function config before bootstrapping.'
    );
  }
  const adminUids = adminUidsRaw.split(',').map(s => s.trim()).filter(Boolean);
  if (!adminUids.includes(callerUid)) {
    throw new functions.https.HttpsError('permission-denied', 'Not in ADMIN_UIDS bootstrap list');
  }

  // SECURITY FIX (LOW 2026-06-11): Read existing claims before overwriting.
  const bootstrapUser = await admin.auth().getUser(callerUid);
  const bootstrapExistingClaims = bootstrapUser.customClaims || {};
  await admin.auth().setCustomUserClaims(callerUid, { ...bootstrapExistingClaims, admin: true });
  await admin.firestore().collection('users').doc(callerUid).update({
    isAdmin: true,
    adminBootstrappedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // SECURITY FIX (LOW 2026-06-11): Revoke refresh tokens so the new admin claim takes
  // effect immediately. Without this, the bootstrapped admin may not see the claim
  // reflected until the session token expires. grantAdminRole already does this.
  await admin.auth().revokeRefreshTokens(callerUid);

  console.log(`[adminClaims] Bootstrapped admin: ${callerUid}`);
  return { success: true, message: 'Admin claim set. Force-refresh token to take effect.' };
});

// ─────────────────────────────────────────────────────────────────────────────
// onUserAdminFlagChanged — sync Custom Claim when isAdmin Firestore field changes
// (Covers direct Firestore writes by existing admin SDK code during migration)
// ─────────────────────────────────────────────────────────────────────────────
exports.onUserAdminFlagChanged = regionalFunctions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before?.isAdmin === after?.isAdmin) return null;

    const userId = context.params.userId;
    const isAdmin = after?.isAdmin === true;

    try {
      // SECURITY FIX (HIGH 2026-06-11): Read existing claims before overwriting so
      // a direct Firestore write to users/{uid}.isAdmin (e.g. migration script) does
      // not silently wipe the user's ageTier, orgAdmin, and moderator claims.
      const existingUserRecord = await admin.auth().getUser(userId);
      const existingClaims = existingUserRecord.customClaims || {};
      await admin.auth().setCustomUserClaims(userId, { ...existingClaims, admin: isAdmin });
      console.log(`[adminClaims] Synced Custom Claim admin=${isAdmin} for ${userId}`);
    } catch (err) {
      console.error(`[adminClaims] Failed to sync claim for ${userId}:`, err);
    }
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// auditAdminClaims — scheduled daily to revoke expired admin claims (L-02)
// ─────────────────────────────────────────────────────────────────────────────
exports.auditAdminClaims = regionalFunctions.pubsub
  .schedule('every 24 hours')
  .onRun(async (_context) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    let snap;
    try {
      snap = await db.collection('adminClaimLog')
        .where('claimExpiry', '<', now)
        .where('action', '==', 'grant_admin')
        .get();
    } catch (err) {
      console.error('[AdminClaims] auditAdminClaims query failed:', err);
      return;
    }

    for (const doc of snap.docs) {
      const { targetUid } = doc.data();
      try {
        // SECURITY FIX (MEDIUM 2026-06-11): Read existing claims before overwriting so
        // other claims (ageTier, moderator, orgAdmin) are not silently wiped.
        const auditUser = await admin.auth().getUser(targetUid);
        const auditExistingClaims = auditUser.customClaims || {};
        await admin.auth().setCustomUserClaims(targetUid, { ...auditExistingClaims, admin: false });
        console.warn(`[AdminClaims] Expired admin claim revoked for ${targetUid}`);
        await doc.ref.update({
          revokedAt: admin.firestore.FieldValue.serverTimestamp(),
          autoRevoked: true,
        });
      } catch (err) {
        console.error(`[AdminClaims] Failed to revoke expired claim for ${targetUid}:`, err);
      }
    }
  });
