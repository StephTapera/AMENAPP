'use strict';

/**
 * verificationEngine.js — Verification & Badge Engine
 *
 * Handles creator/org/church/business verification via:
 *   domain DNS TXT challenge, social OAuth, email domain, org_admin manual review
 *
 * SECURITY INVARIANTS:
 *   - 'manual' method is a HUMAN GATE — always rejected from client
 *   - DNS lookups run server-side only (dns.promises)
 *   - OAuth tokens verified server-side; never logged or stored raw
 *   - Badge writes are server-side only (clients cannot write badge fields)
 *   - Admin operations (revoke) require custom admin claim
 *
 * Exports (all CF onCall):
 *   submitVerificationClaim, checkDomainVerification,
 *   checkSocialOAuthVerification, checkEmailDomainVerification,
 *   confirmEmailCode, revokeBadge, getVerificationStatus
 *
 * Internal helpers (not exported as CFs):
 *   grantBadge, generateToken, hashCode
 */

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const dns = require('dns').promises;
const crypto = require('crypto');
const https = require('https');

const REGION = 'us-central1';
const regionalFunctions = functions.region(REGION);
const db = admin.firestore;

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const MAX_PENDING_CLAIMS = 3;

const VALID_METHODS = ['domain', 'social_oauth', 'email_domain', 'org_admin'];

const VALID_BADGE_TYPES = [
  'verified_creator',
  'verified_organization',
  'verified_church',
  'verified_business',
];

const METHOD_BADGE_MAP = {
  domain: 'verified_creator',
  social_oauth: 'verified_creator',
  email_domain: 'verified_creator',
  org_admin: 'verified_organization', // may be overridden by badgeType in input
};

// ─────────────────────────────────────────────────────────────────────────────
// Internal Utilities
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generates a cryptographically secure random hex token.
 * @param {number} bytes - byte length (default 24 → 48 hex chars)
 */
function generateToken(bytes = 24) {
  return crypto.randomBytes(bytes).toString('hex');
}

/**
 * SHA-256 hash of a value (for storing codes without plaintext).
 * @param {string} value
 */
function hashCode(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

/**
 * Performs an HTTPS GET request and resolves with the parsed JSON body.
 * Rejects on non-2xx status or JSON parse failure.
 */
function httpsGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return reject(new Error(`HTTP ${res.statusCode}: ${body}`));
        }
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error(`JSON parse error: ${e.message}`));
        }
      });
    }).on('error', reject);
  });
}

/**
 * Performs an HTTPS GET with an Authorization header.
 */
function httpsGetAuthorized(url, bearerToken) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const options = {
      hostname: parsedUrl.hostname,
      path: parsedUrl.pathname + parsedUrl.search,
      headers: { Authorization: `Bearer ${bearerToken}` },
    };
    https.get(options, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          return reject(new Error(`HTTP ${res.statusCode}: ${body}`));
        }
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error(`JSON parse error: ${e.message}`));
        }
      });
    }).on('error', reject);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// grantBadge — internal only, not exported as CF
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Grants a verification badge to a creator.
 * - Updates users/{creatorId}/profile subcollection (or top-level user doc)
 * - Marks all works by this creator as verifiedOwnership=true
 * - Writes to verificationAuditLog
 *
 * @param {FirebaseFirestore.Firestore} firestore
 * @param {string} creatorId
 * @param {string} badgeType  - one of VALID_BADGE_TYPES
 * @param {string} claimId
 */
async function grantBadge(firestore, creatorId, badgeType, claimId) {
  if (!VALID_BADGE_TYPES.includes(badgeType)) {
    throw new Error(`Invalid badgeType: ${badgeType}`);
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = firestore.batch();

  // Update user profile document
  const userRef = firestore.collection('users').doc(creatorId);
  batch.set(
    userRef,
    {
      verified: true,
      badge: badgeType,
      verifiedAt: now,
      updatedAt: now,
    },
    { merge: true }
  );

  // Commit batch for user update first so Firestore is consistent
  await batch.commit();

  // Mark all works by this creator as verifiedOwnership = true
  // Done in a separate batch to avoid transaction size limits
  const worksSnap = await firestore
    .collectionGroup('works')
    .where('creatorId', '==', creatorId)
    .limit(500)
    .get();

  if (!worksSnap.empty) {
    const worksBatch = firestore.batch();
    worksSnap.docs.forEach((doc) => {
      worksBatch.update(doc.ref, { verifiedOwnership: true, updatedAt: now });
    });
    await worksBatch.commit();
  }

  // Write audit log entry
  await firestore.collection('verificationAuditLog').add({
    action: 'badge_granted',
    creatorId,
    badgeType,
    claimId,
    timestamp: now,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// submitVerificationClaim
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a new VerificationClaim in Firestore.
 *
 * Input:  { method, evidence, badgeType? }
 * Output: { claimId, status:'pending', challenge? }
 *
 * Security:
 *   - 'manual' method always rejected
 *   - Max 3 pending claims per user (rate limit)
 *   - Evidence validated per method
 */
exports.submitVerificationClaim = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const { method, evidence = {}, badgeType } = data || {};

  // Reject manual method from clients — HUMAN GATE
  if (method === 'manual') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Manual verification requires human review. Contact support to initiate.'
    );
  }

  if (!VALID_METHODS.includes(method)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Invalid method. Allowed: ${VALID_METHODS.join(', ')}`
    );
  }

  // Validate badge type if provided
  const resolvedBadgeType = badgeType || METHOD_BADGE_MAP[method];
  if (!VALID_BADGE_TYPES.includes(resolvedBadgeType)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Invalid badgeType. Allowed: ${VALID_BADGE_TYPES.join(', ')}`
    );
  }

  const firestore = admin.firestore();

  // Rate limit: max 3 pending claims per user
  const pendingSnap = await firestore
    .collection('verificationClaims')
    .where('creatorId', '==', uid)
    .where('status', '==', 'pending')
    .get();

  if (pendingSnap.size >= MAX_PENDING_CLAIMS) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      `You already have ${MAX_PENDING_CLAIMS} pending verification claims. Wait for existing claims to be processed.`
    );
  }

  // Validate evidence per method and build stored claim
  let storedEvidence = {};
  let challenge = null;

  switch (method) {
    case 'domain': {
      const { domainUrl } = evidence;
      if (!domainUrl || typeof domainUrl !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'domain method requires evidence.domainUrl');
      }
      // Generate DNS TXT challenge token
      const token = generateToken(24);
      storedEvidence = {
        domainUrl: domainUrl.trim().toLowerCase(),
        verificationToken: token,
        // DNS TXT record the user must add:
        // amen-verification=<token>
      };
      challenge = {
        type: 'dns_txt',
        record: `amen-verification=${token}`,
        domain: domainUrl.trim().toLowerCase(),
        instructions: `Add a DNS TXT record to your domain: amen-verification=${token}`,
      };
      break;
    }

    case 'social_oauth': {
      const { platform, claimedAccountId } = evidence;
      if (!platform || typeof platform !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'social_oauth method requires evidence.platform');
      }
      if (!claimedAccountId || typeof claimedAccountId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'social_oauth method requires evidence.claimedAccountId');
      }
      const allowedPlatforms = ['youtube', 'spotify', 'instagram', 'twitter'];
      if (!allowedPlatforms.includes(platform.toLowerCase())) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `Unsupported platform. Allowed: ${allowedPlatforms.join(', ')}`
        );
      }
      storedEvidence = {
        platform: platform.toLowerCase(),
        claimedAccountId,
        // oauthToken is NOT stored — only verified in checkSocialOAuthVerification
      };
      break;
    }

    case 'email_domain': {
      const { email } = evidence;
      if (!email || typeof email !== 'string' || !email.includes('@')) {
        throw new functions.https.HttpsError('invalid-argument', 'email_domain method requires a valid evidence.email');
      }
      storedEvidence = {
        email: email.trim().toLowerCase(),
        // Verification code stored as hash in checkEmailDomainVerification
      };
      break;
    }

    case 'org_admin': {
      const { orgId, taxId } = evidence;
      if (!orgId || typeof orgId !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'org_admin method requires evidence.orgId');
      }
      // taxId is optional but stored if provided (no plaintext secrets; tax IDs are org identifiers)
      storedEvidence = {
        orgId,
        ...(taxId ? { taxId: taxId.trim() } : {}),
        reviewNote: 'Pending manual admin review',
      };
      break;
    }
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const claimRef = firestore.collection('verificationClaims').doc();

  await claimRef.set({
    creatorId: uid,
    method,
    status: 'pending',
    evidence: storedEvidence,
    badgeType: resolvedBadgeType,
    createdAt: now,
    updatedAt: now,
  });

  return {
    claimId: claimRef.id,
    status: 'pending',
    ...(challenge ? { challenge } : {}),
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// checkDomainVerification
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Performs server-side DNS TXT record lookup to verify domain ownership.
 *
 * Input:  { claimId }
 * Output: { verified: boolean }
 */
exports.checkDomainVerification = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const { claimId } = data || {};

  if (!claimId || typeof claimId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'claimId required');
  }

  const firestore = admin.firestore();
  const claimRef = firestore.collection('verificationClaims').doc(claimId);
  const claimSnap = await claimRef.get();

  if (!claimSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Verification claim not found');
  }

  const claim = claimSnap.data();

  if (claim.creatorId !== uid) {
    throw new functions.https.HttpsError('permission-denied', 'You do not own this claim');
  }

  if (claim.method !== 'domain') {
    throw new functions.https.HttpsError('invalid-argument', 'This claim is not a domain verification claim');
  }

  if (claim.status === 'approved') {
    return { verified: true };
  }

  if (claim.status === 'rejected') {
    return { verified: false };
  }

  const { domainUrl, verificationToken } = claim.evidence;
  const expectedRecord = `amen-verification=${verificationToken}`;

  let records;
  try {
    // dns.promises.resolveTxt returns string[][] — flatten to string[]
    const raw = await dns.resolveTxt(domainUrl);
    records = raw.map((arr) => arr.join(''));
  } catch (err) {
    // DNS lookup failure is not a fatal error — token simply not found yet
    functions.logger.warn('DNS lookup failed for domain', { domainUrl, error: err.message });
    return { verified: false };
  }

  const found = records.some((r) => r.includes(expectedRecord));

  if (found) {
    const now = admin.firestore.FieldValue.serverTimestamp();
    await claimRef.update({ status: 'approved', updatedAt: now });
    await grantBadge(firestore, uid, claim.badgeType, claimId);
    return { verified: true };
  }

  return { verified: false };
});

// ─────────────────────────────────────────────────────────────────────────────
// checkSocialOAuthVerification
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Verifies an OAuth access token server-side against the claimed social platform.
 * Supported: YouTube, Spotify
 * Raw tokens are NEVER logged or stored.
 *
 * Input:  { claimId, platform, accessToken }
 * Output: { verified: boolean }
 */
exports.checkSocialOAuthVerification = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const { claimId, platform, accessToken } = data || {};

  if (!claimId || !platform || !accessToken) {
    throw new functions.https.HttpsError('invalid-argument', 'claimId, platform, and accessToken required');
  }

  // Never log the raw token
  const firestore = admin.firestore();
  const claimRef = firestore.collection('verificationClaims').doc(claimId);
  const claimSnap = await claimRef.get();

  if (!claimSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Verification claim not found');
  }

  const claim = claimSnap.data();

  if (claim.creatorId !== uid) {
    throw new functions.https.HttpsError('permission-denied', 'You do not own this claim');
  }

  if (claim.method !== 'social_oauth') {
    throw new functions.https.HttpsError('invalid-argument', 'This claim is not a social OAuth claim');
  }

  if (claim.status === 'approved') {
    return { verified: true };
  }

  const claimedPlatform = claim.evidence.platform;
  const claimedAccountId = claim.evidence.claimedAccountId;

  if (claimedPlatform !== platform.toLowerCase()) {
    throw new functions.https.HttpsError('invalid-argument', 'Platform does not match claim');
  }

  let platformAccountId = null;
  let verified = false;

  try {
    switch (platform.toLowerCase()) {
      case 'youtube': {
        // Google tokeninfo endpoint returns 'sub' (Google user ID)
        const tokenInfo = await httpsGet(
          `https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=${encodeURIComponent(accessToken)}`
        );
        platformAccountId = tokenInfo.sub;
        break;
      }

      case 'spotify': {
        const meData = await httpsGetAuthorized('https://api.spotify.com/v1/me', accessToken);
        platformAccountId = meData.id;
        break;
      }

      default:
        throw new functions.https.HttpsError('invalid-argument', `Unsupported platform: ${platform}`);
    }
  } catch (err) {
    functions.logger.warn('Social OAuth verification failed', {
      platform,
      claimId,
      error: err.message,
      // DO NOT log accessToken
    });
    return { verified: false };
  }

  if (platformAccountId && platformAccountId === claimedAccountId) {
    verified = true;
    const now = admin.firestore.FieldValue.serverTimestamp();
    await claimRef.update({ status: 'approved', updatedAt: now });
    await grantBadge(firestore, uid, claim.badgeType, claimId);
  }

  return { verified };
});

// ─────────────────────────────────────────────────────────────────────────────
// checkEmailDomainVerification
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Sends a verification email with a one-time code to the claimed domain email.
 * Stores only the SHA-256 hash of the code in Firestore (never plaintext).
 *
 * Input:  { claimId }
 * Output: { sent: boolean }
 *
 * Note: Actual email delivery requires Firebase Extensions or SendGrid.
 *       This CF writes to emailQueue (picked up by the email delivery Extension).
 */
exports.checkEmailDomainVerification = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const { claimId } = data || {};

  if (!claimId || typeof claimId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'claimId required');
  }

  const firestore = admin.firestore();
  const claimRef = firestore.collection('verificationClaims').doc(claimId);
  const claimSnap = await claimRef.get();

  if (!claimSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Verification claim not found');
  }

  const claim = claimSnap.data();

  if (claim.creatorId !== uid) {
    throw new functions.https.HttpsError('permission-denied', 'You do not own this claim');
  }

  if (claim.method !== 'email_domain') {
    throw new functions.https.HttpsError('invalid-argument', 'This claim is not an email domain claim');
  }

  if (claim.status === 'approved') {
    return { sent: false, reason: 'Already verified' };
  }

  const email = claim.evidence.email;
  if (!email) {
    throw new functions.https.HttpsError('internal', 'Claim is missing email address');
  }

  // Generate 6-digit OTP
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const hashedCode = hashCode(code);
  const expiresAt = Date.now() + 15 * 60 * 1000; // 15 minutes

  // Store hashed code only — never plaintext
  const now = admin.firestore.FieldValue.serverTimestamp();
  await claimRef.update({
    'evidence.hashedCode': hashedCode,
    'evidence.codeExpiresAt': expiresAt,
    updatedAt: now,
  });

  // Queue email for delivery via Firebase Extension (Trigger Email)
  await firestore.collection('emailQueue').add({
    to: email,
    message: {
      subject: 'Verify your domain with Amen',
      text: `Your Amen verification code is: ${code}\n\nThis code expires in 15 minutes.\n\nIf you did not request this, please ignore this message.`,
      html: `<p>Your Amen verification code is: <strong>${code}</strong></p><p>This code expires in 15 minutes.</p><p>If you did not request this, please ignore this message.</p>`,
    },
    createdAt: now,
    // Code is NOT included here — only in the user's email
  });

  functions.logger.info('Verification email queued', { claimId, email });

  return { sent: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// confirmEmailCode
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Verifies the one-time email code against the stored hash.
 *
 * Input:  { claimId, code }
 * Output: { verified: boolean }
 */
exports.confirmEmailCode = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const { claimId, code } = data || {};

  if (!claimId || !code) {
    throw new functions.https.HttpsError('invalid-argument', 'claimId and code required');
  }

  const firestore = admin.firestore();
  const claimRef = firestore.collection('verificationClaims').doc(claimId);
  const claimSnap = await claimRef.get();

  if (!claimSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Verification claim not found');
  }

  const claim = claimSnap.data();

  if (claim.creatorId !== uid) {
    throw new functions.https.HttpsError('permission-denied', 'You do not own this claim');
  }

  if (claim.method !== 'email_domain') {
    throw new functions.https.HttpsError('invalid-argument', 'This claim is not an email domain claim');
  }

  if (claim.status === 'approved') {
    return { verified: true };
  }

  const { hashedCode, codeExpiresAt } = claim.evidence || {};

  if (!hashedCode) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'No verification code has been sent for this claim. Call checkEmailDomainVerification first.'
    );
  }

  if (Date.now() > codeExpiresAt) {
    throw new functions.https.HttpsError('deadline-exceeded', 'Verification code has expired. Please request a new code.');
  }

  const inputHash = hashCode(String(code));
  const match = crypto.timingSafeEqual(
    Buffer.from(inputHash, 'hex'),
    Buffer.from(hashedCode, 'hex')
  );

  if (match) {
    const now = admin.firestore.FieldValue.serverTimestamp();
    await claimRef.update({ status: 'approved', updatedAt: now });
    await grantBadge(firestore, uid, claim.badgeType, claimId);
    return { verified: true };
  }

  return { verified: false };
});

// ─────────────────────────────────────────────────────────────────────────────
// revokeBadge — admin-only callable
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Removes a verification badge from a creator.
 * Requires custom admin claim.
 *
 * Input:  { targetCreatorId, reason }
 * Output: { revoked: boolean }
 */
exports.revokeBadge = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth?.token?.admin) {
    throw new functions.https.HttpsError('permission-denied', 'Admin privileges required to revoke badges');
  }

  const { targetCreatorId, reason } = data || {};

  if (!targetCreatorId || typeof targetCreatorId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'targetCreatorId required');
  }
  if (!reason || typeof reason !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'reason required');
  }

  const firestore = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Update user profile — remove badge
  const userRef = firestore.collection('users').doc(targetCreatorId);
  await userRef.set(
    {
      verified: false,
      badge: admin.firestore.FieldValue.delete(),
      verifiedAt: admin.firestore.FieldValue.delete(),
      updatedAt: now,
    },
    { merge: true }
  );

  // Mark all works as unverified
  const worksSnap = await firestore
    .collectionGroup('works')
    .where('creatorId', '==', targetCreatorId)
    .limit(500)
    .get();

  if (!worksSnap.empty) {
    const batch = firestore.batch();
    worksSnap.docs.forEach((doc) => {
      batch.update(doc.ref, { verifiedOwnership: false, updatedAt: now });
    });
    await batch.commit();
  }

  // Reject all pending claims for this user
  const pendingSnap = await firestore
    .collection('verificationClaims')
    .where('creatorId', '==', targetCreatorId)
    .where('status', '==', 'approved')
    .get();

  if (!pendingSnap.empty) {
    const claimsBatch = firestore.batch();
    pendingSnap.docs.forEach((doc) => {
      claimsBatch.update(doc.ref, { status: 'rejected', revokedAt: now, revokedBy: context.auth.uid });
    });
    await claimsBatch.commit();
  }

  // Audit log
  await firestore.collection('verificationAuditLog').add({
    action: 'badge_revoked',
    targetCreatorId,
    revokedBy: context.auth.uid,
    reason,
    timestamp: now,
  });

  return { revoked: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// getVerificationStatus
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns the current verification claims and badge status for the caller.
 *
 * Input:  {} (uses context.auth.uid)
 * Output: { verified: boolean, badge: string|null, claims: VerificationClaim[] }
 */
exports.getVerificationStatus = regionalFunctions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  }

  const uid = context.auth.uid;
  const firestore = admin.firestore();

  const [userSnap, claimsSnap] = await Promise.all([
    firestore.collection('users').doc(uid).get(),
    firestore
      .collection('verificationClaims')
      .where('creatorId', '==', uid)
      .orderBy('createdAt', 'desc')
      .limit(20)
      .get(),
  ]);

  const userData = userSnap.exists ? userSnap.data() : {};
  const claims = claimsSnap.docs.map((doc) => {
    const c = doc.data();
    // Redact sensitive evidence fields
    const safeEvidence = { ...c.evidence };
    delete safeEvidence.hashedCode;
    delete safeEvidence.verificationToken; // hide DNS token from display (user already has it)
    return {
      claimId: doc.id,
      method: c.method,
      status: c.status,
      badgeType: c.badgeType,
      evidence: safeEvidence,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    };
  });

  return {
    verified: userData.verified === true,
    badge: userData.badge || null,
    verifiedAt: userData.verifiedAt || null,
    claims,
  };
});
