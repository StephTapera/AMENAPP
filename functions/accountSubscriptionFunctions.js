/**
 * accountSubscriptionFunctions.js
 * AMEN App — StoreKit subscription entitlement processing
 *
 * processAccountSubscription — callable: records App Store subscription entitlement
 *   after a successful StoreKit transaction.  iOS calls this immediately after
 *   Transaction.finish() with the transactionId and the resolved tier.
 *
 * Product ID → AmenAccountTier mapping:
 *   com.amenapp.subscription.amenplus.monthly   → amenPlus
 *   com.amenapp.subscription.amenpro.monthly    → amenPro
 *   com.amenapp.subscription.creatorpro.monthly → creatorPro
 *   com.amenapp.subscription.churchpro.monthly  → churchPro
 *
 * Auth:   required (uid must match request.auth.uid)
 * Rate:   max 10 calls per minute per user
 * Writes: users/{uid}/entitlements/platform
 *
 * Required secrets (set via `firebase functions:secrets:set`):
 *   APPLE_ASC_PRIVATE_KEY — ES256 .p8 private-key PEM from App Store Connect
 *   APPLE_ASC_KEY_ID      — 10-char App Store Connect API Key ID
 *   APPLE_ASC_ISSUER_ID   — UUID Issuer ID from App Store Connect
 *
 * Required env var (set in Firebase project config or Secret Manager):
 *   APPLE_BUNDLE_ID       — app bundle ID (e.g. tapera.AMENAPP)
 *
 * Security: the transactionId is verified server-side via the App Store Server
 * API before any entitlement is written.  The client-supplied tier/productId are
 * only used for pre-validation; the authoritative values come from Apple.
 */

"use strict";

const { onCall, HttpsError }   = require("firebase-functions/v2/https");
const { defineSecret }         = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const crypto                   = require("crypto");

const db = getFirestore();

// ---------------------------------------------------------------------------
// Secrets — injected by Cloud Functions at runtime via Secret Manager
// ---------------------------------------------------------------------------

const APPLE_ASC_PRIVATE_KEY = defineSecret("APPLE_ASC_PRIVATE_KEY");
const APPLE_ASC_KEY_ID      = defineSecret("APPLE_ASC_KEY_ID");
const APPLE_ASC_ISSUER_ID   = defineSecret("APPLE_ASC_ISSUER_ID");

// ---------------------------------------------------------------------------
// Product ID → tier raw value mapping
// ---------------------------------------------------------------------------

const PRODUCT_TIER_MAP = {
  "com.amenapp.subscription.amenplus.monthly":   "amenPlus",
  "com.amenapp.subscription.amenpro.monthly":    "amenPro",
  "com.amenapp.subscription.creatorpro.monthly": "creatorPro",
  "com.amenapp.subscription.churchpro.monthly":  "churchPro",
};

// All valid tier values (used to validate client-supplied tier field).
const VALID_TIERS = new Set(Object.values(PRODUCT_TIER_MAP));

// ---------------------------------------------------------------------------
// Rate-limit helper — max maxCalls per windowSecs using a Firestore counter doc.
// Uses a simple fixed-window approach; same pattern as rateLimiter.js.
// ---------------------------------------------------------------------------

async function checkSubscriptionRateLimit(uid) {
  const MAX_CALLS   = 10;
  const WINDOW_SECS = 60;

  const docId = `${uid}_processAccountSubscription`;
  const ref   = db.collection("rateLimits").doc(docId);
  const now   = Date.now();
  const windowMs = WINDOW_SECS * 1000;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);

    if (!snap.exists) {
      tx.set(ref, {
        uid,
        action: "processAccountSubscription",
        count: 1,
        windowStart: new Date(now),
        expiresAt: new Date(now + windowMs),
      });
      return;
    }

    const data = snap.data();
    const windowStart = data.windowStart.toMillis
      ? data.windowStart.toMillis()
      : data.windowStart.getTime();

    if (now - windowStart > windowMs) {
      // Window expired — reset
      tx.update(ref, {
        count: 1,
        windowStart: new Date(now),
        expiresAt: new Date(now + windowMs),
      });
      return;
    }

    if (data.count >= MAX_CALLS) {
      throw new HttpsError(
        "resource-exhausted",
        "Rate limit exceeded. Max 10 subscription verifications per minute.",
      );
    }

    tx.update(ref, { count: FieldValue.increment(1) });
  });
}

// ---------------------------------------------------------------------------
// buildAppStoreJWT
// Constructs an ES256 JWT for authenticating against the App Store Server API.
// Audience must be "appstoreconnect-v1"; exp is capped at 60 seconds per
// Apple's documentation.
// ---------------------------------------------------------------------------

function buildAppStoreJWT() {
  const privateKeyPem = APPLE_ASC_PRIVATE_KEY.value();
  const keyId         = APPLE_ASC_KEY_ID.value();
  const issuerId      = APPLE_ASC_ISSUER_ID.value();

  if (!privateKeyPem || !keyId || !issuerId) {
    throw new HttpsError(
      "failed-precondition",
      "App Store Connect credentials are not configured. Deploy requires APPLE_ASC_PRIVATE_KEY, APPLE_ASC_KEY_ID, and APPLE_ASC_ISSUER_ID in Secret Manager.",
    );
  }

  const now = Math.floor(Date.now() / 1000);

  const header = Buffer.from(
    JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })
  ).toString("base64url");

  const payload = Buffer.from(
    JSON.stringify({
      iss: issuerId,
      iat: now,
      exp: now + 60,          // Max 60 s — Apple requirement
      aud: "appstoreconnect-v1",
      bid: process.env.APPLE_BUNDLE_ID || "tapera.AMENAPP",
    })
  ).toString("base64url");

  const signingInput = `${header}.${payload}`;
  const sign = crypto.createSign("SHA256");
  sign.update(signingInput);

  // dsaEncoding: "ieee-p1363" produces the raw r||s format required for JWT
  const signature = sign
    .sign({ key: privateKeyPem, dsaEncoding: "ieee-p1363" })
    .toString("base64url");

  return `${signingInput}.${signature}`;
}

// ---------------------------------------------------------------------------
// verifyAppStoreTransaction
// Calls the App Store Server API to retrieve and verify the signed transaction.
// Returns the decoded payload from Apple's JWS-signed transaction info.
//
// The transaction info is a JWS compact serialisation signed by Apple's
// certificate chain.  For server-side verification we decode the payload
// directly (the CA chain validation is not required for the field values —
// Apple's API already authenticated the request via our JWT).  If deeper
// chain validation is needed in future, use the `jose` library already
// present in node_modules.
// ---------------------------------------------------------------------------

async function verifyAppStoreTransaction(transactionId) {
  const jwt = buildAppStoreJWT();

  // Attempt production first; fall back to sandbox for TestFlight / development.
  const endpoints = [
    `https://api.storekit.itunes.apple.com/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
    `https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/${encodeURIComponent(transactionId)}`,
  ];

  let lastError;
  for (const url of endpoints) {
    let resp;
    try {
      resp = await fetch(url, {
        headers: { Authorization: `Bearer ${jwt}` },
      });
    } catch (err) {
      lastError = err;
      continue;
    }

    if (resp.status === 200) {
      const json = await resp.json();
      // signedTransactionInfo is a JWS compact token: header.payload.sig
      const jws = json.signedTransactionInfo;
      if (!jws || typeof jws !== "string") {
        throw new HttpsError("internal", "Apple returned an unexpected response (missing signedTransactionInfo).");
      }
      // Decode the payload (middle segment of the JWS compact serialisation).
      const parts = jws.split(".");
      if (parts.length !== 3) {
        throw new HttpsError("internal", "Malformed signedTransactionInfo from Apple.");
      }
      try {
        const decoded = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
        return decoded;
      } catch {
        throw new HttpsError("internal", "Failed to parse signedTransactionInfo payload.");
      }
    }

    if (resp.status === 404) {
      // Transaction not found on this environment — try sandbox
      lastError = new HttpsError("not-found", `Transaction ${transactionId} not found on App Store.`);
      continue;
    }

    // Any other non-200 from Apple is treated as a hard failure.
    throw new HttpsError(
      "internal",
      `App Store Server API returned status ${resp.status} for transaction verification.`,
    );
  }

  // Both endpoints failed
  if (lastError instanceof HttpsError) throw lastError;
  throw new HttpsError("internal", "App Store transaction verification failed: network error.");
}

// ---------------------------------------------------------------------------
// processAccountSubscription
// ---------------------------------------------------------------------------

exports.processAccountSubscription = onCall(
  {
    region:  "us-central1",
    secrets: [APPLE_ASC_PRIVATE_KEY, APPLE_ASC_KEY_ID, APPLE_ASC_ISSUER_ID],
  },
  async (request) => {
    // ── Auth guard ──────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in to process a subscription.");
    }

    const callerUid = request.auth.uid;
    const { transactionId, tier, uid, productId } = request.data ?? {};

    // ── Input validation ────────────────────────────────────────────────────
    if (!transactionId || typeof transactionId !== "string" || transactionId.trim() === "") {
      throw new HttpsError("invalid-argument", "transactionId is required.");
    }
    if (!uid || typeof uid !== "string") {
      throw new HttpsError("invalid-argument", "uid is required.");
    }

    // UID must match the authenticated caller — prevents one user from writing
    // an entitlement to another user's document.
    if (uid !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "uid does not match the authenticated user.",
      );
    }

    // Resolve the claimed tier from the supplied productId (preferred) or fall
    // back to the client-supplied tier string (secondary, validated against
    // allow-list).  This is the *claimed* tier; the authoritative tier comes
    // from Apple below.
    let claimedTier;
    if (productId && typeof productId === "string" && PRODUCT_TIER_MAP[productId]) {
      claimedTier = PRODUCT_TIER_MAP[productId];
    } else if (tier && VALID_TIERS.has(tier)) {
      claimedTier = tier;
    } else {
      throw new HttpsError(
        "invalid-argument",
        `Unrecognised tier or productId. Valid productIds: ${Object.keys(PRODUCT_TIER_MAP).join(", ")}`,
      );
    }

    // ── Rate limit ──────────────────────────────────────────────────────────
    await checkSubscriptionRateLimit(callerUid);

    // ── App Store Server API verification ───────────────────────────────────
    // Verify the transactionId with Apple before trusting any client-supplied
    // value.  verifyAppStoreTransaction throws HttpsError on any failure.
    let txInfo;
    try {
      txInfo = await verifyAppStoreTransaction(transactionId.trim());
    } catch (err) {
      // Re-throw HttpsError as-is; wrap unexpected errors.
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "App Store transaction verification failed.");
    }

    // ── Cross-validate Apple's response against the client-supplied values ──
    const expectedBundleId = process.env.APPLE_BUNDLE_ID || "tapera.AMENAPP";
    if (txInfo.bundleId !== expectedBundleId) {
      throw new HttpsError(
        "permission-denied",
        "Transaction bundleId does not match this application.",
      );
    }

    // Authoritative productId comes from Apple's signed transaction.
    const appleProductId   = txInfo.productId;
    const authorizedTier   = PRODUCT_TIER_MAP[appleProductId];

    if (!authorizedTier) {
      throw new HttpsError(
        "permission-denied",
        `Transaction product '${appleProductId}' is not a recognised AMEN subscription product.`,
      );
    }

    // The tier Apple asserts must match what the client claimed.  This catches
    // clients that fabricate a higher tier using a real lower-tier transactionId.
    if (authorizedTier !== claimedTier) {
      throw new HttpsError(
        "permission-denied",
        "Transaction tier does not match the claimed tier.",
      );
    }

    // ── Write entitlement document ──────────────────────────────────────────
    // All values written are derived from Apple's signed response, not client
    // input.  transactionId.trim() is safe to store for audit purposes.
    const entitlementRef = db
      .collection("users")
      .doc(uid)
      .collection("entitlements")
      .doc("platform");

    await entitlementRef.set({
      tier:               authorizedTier,
      transactionId:      transactionId.trim(),
      productId:          appleProductId,
      appleOriginalTxId:  txInfo.originalTransactionId ?? null,
      appleExpiresDate:   txInfo.expiresDate           ?? null,
      updatedAt:          FieldValue.serverTimestamp(),
      source:             "appStore",
      verifiedByApple:    true,
    }, { merge: true });

    return { success: true, tier: authorizedTier };
  }
);
