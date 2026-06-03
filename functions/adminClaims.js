/**
 * adminClaims.js — v1 Cloud Functions (avoids Cloud Run quota)
 * Server-side admin role management via Firebase Custom Claims.
 *
 * Usage in Firestore rules:
 *   function isAdmin() { return request.auth.token.admin == true; }
 */

'use strict';

const functions = require('firebase-functions');
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

  await admin.auth().setCustomUserClaims(targetUid, { admin: true });

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

  await admin.auth().setCustomUserClaims(targetUid, { admin: false });

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

  console.log(`[adminClaims] Revoked admin from ${targetUid} by ${context.auth.uid}`);
  return { success: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// bootstrapFirstAdmin — one-time setup, restricted to ADMIN_UIDS env var
// ─────────────────────────────────────────────────────────────────────────────
exports.bootstrapFirstAdmin = regionalFunctions.https.onCall(async (data, context) => {
  const callerUid = context.auth?.uid;
  if (!callerUid) throw new functions.https.HttpsError('unauthenticated', 'Must be authenticated');

  const adminUids = (process.env.ADMIN_UIDS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (!adminUids.includes(callerUid)) {
    throw new functions.https.HttpsError('permission-denied', 'Not in ADMIN_UIDS bootstrap list');
  }

  await admin.auth().setCustomUserClaims(callerUid, { admin: true });
  await admin.firestore().collection('users').doc(callerUid).update({
    isAdmin: true,
    adminBootstrappedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

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
      await admin.auth().setCustomUserClaims(userId, { admin: isAdmin });
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
        await admin.auth().setCustomUserClaims(targetUid, { admin: false });
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
