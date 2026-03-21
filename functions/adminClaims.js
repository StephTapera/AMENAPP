/**
 * adminClaims.js
 * Server-side admin role management via Firebase Custom Claims.
 *
 * Replaces Firestore-field-based admin checks (isAdmin: true on user doc)
 * with JWT-level claims that are:
 *   1. Not writable by clients (unlike Firestore fields)
 *   2. Available in every security rule as request.auth.token.admin
 *   3. Not billed as extra Firestore reads (unlike get(users/uid).isAdmin)
 *
 * Usage in Firestore rules:
 *   function isAdmin() { return request.auth.token.admin == true; }
 */

'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const REGION = 'us-central1';

// ─────────────────────────────────────────────────────────────────────────────
// grantAdminRole — callable by existing admins only
// ─────────────────────────────────────────────────────────────────────────────
exports.grantAdminRole = onCall({ region: REGION, enforceAppCheck: true }, async (req) => {
  // Only admins can grant admin roles
  if (!req.auth?.token?.admin) {
    throw new HttpsError('permission-denied', 'Only admins can grant admin roles');
  }

  const { targetUid } = req.data;
  if (!targetUid || typeof targetUid !== 'string') {
    throw new HttpsError('invalid-argument', 'targetUid required');
  }

  await admin.auth().setCustomUserClaims(targetUid, { admin: true });

  // Also mark in Firestore for display purposes (non-authoritative)
  await admin.firestore().collection('users').doc(targetUid).update({
    isAdmin: true,
    adminGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
    adminGrantedBy: req.auth.uid,
  });

  console.log(`[adminClaims] Granted admin to ${targetUid} by ${req.auth.uid}`);
  return { success: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// revokeAdminRole — callable by existing admins only
// ─────────────────────────────────────────────────────────────────────────────
exports.revokeAdminRole = onCall({ region: REGION, enforceAppCheck: true }, async (req) => {
  if (!req.auth?.token?.admin) {
    throw new HttpsError('permission-denied', 'Only admins can revoke admin roles');
  }

  const { targetUid } = req.data;
  if (!targetUid || typeof targetUid !== 'string') {
    throw new HttpsError('invalid-argument', 'targetUid required');
  }

  // Prevent self-revocation
  if (targetUid === req.auth.uid) {
    throw new HttpsError('invalid-argument', 'Admins cannot revoke their own admin role');
  }

  await admin.auth().setCustomUserClaims(targetUid, { admin: false });

  await admin.firestore().collection('users').doc(targetUid).update({
    isAdmin: false,
    adminRevokedAt: admin.firestore.FieldValue.serverTimestamp(),
    adminRevokedBy: req.auth.uid,
  });

  console.log(`[adminClaims] Revoked admin from ${targetUid} by ${req.auth.uid}`);
  return { success: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// bootstrapFirstAdmin — one-time setup, restricted to ADMIN_UIDS env var
// ─────────────────────────────────────────────────────────────────────────────
exports.bootstrapFirstAdmin = onCall({ region: REGION, enforceAppCheck: false }, async (req) => {
  const callerUid = req.auth?.uid;
  if (!callerUid) throw new HttpsError('unauthenticated', 'Must be authenticated');

  const adminUids = (process.env.ADMIN_UIDS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (!adminUids.includes(callerUid)) {
    throw new HttpsError('permission-denied', 'Not in ADMIN_UIDS bootstrap list');
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
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');

exports.onUserAdminFlagChanged = onDocumentUpdated(
  { document: 'users/{userId}', region: REGION },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Only act when isAdmin field changes
    if (before?.isAdmin === after?.isAdmin) return null;

    const userId = event.params.userId;
    const isAdmin = after?.isAdmin === true;

    try {
      await admin.auth().setCustomUserClaims(userId, { admin: isAdmin });
      console.log(`[adminClaims] Synced Custom Claim admin=${isAdmin} for ${userId}`);
    } catch (err) {
      console.error(`[adminClaims] Failed to sync claim for ${userId}:`, err);
    }
    return null;
  }
);
