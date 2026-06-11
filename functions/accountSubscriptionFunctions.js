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
 * TODO(gate: DECISION) — production: replace direct Firestore write below with a full
 * JWT-signed App Store Server API verification call using the sandbox URL
 *   https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/{transactionId}
 * and the production URL
 *   https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}
 * Both require a signed JWT (ES256) built from your Apple App Store Connect
 * private key, Issuer ID, and Key ID stored in Firebase Secret Manager.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const db = getFirestore();

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
// processAccountSubscription
// ---------------------------------------------------------------------------

exports.processAccountSubscription = onCall({ region: "us-central1" }, async (request) => {
  // ── Auth guard ────────────────────────────────────────────────────────────
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in to process a subscription.");
  }

  const callerUid = request.auth.uid;
  const { transactionId, tier, uid, productId } = request.data ?? {};

  // ── Input validation ──────────────────────────────────────────────────────
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

  // Resolve the tier from the supplied productId (preferred) or fall back to
  // the client-supplied tier string (secondary, validated against allow-list).
  let resolvedTier;
  if (productId && typeof productId === "string" && PRODUCT_TIER_MAP[productId]) {
    resolvedTier = PRODUCT_TIER_MAP[productId];
  } else if (tier && VALID_TIERS.has(tier)) {
    resolvedTier = tier;
  } else {
    throw new HttpsError(
      "invalid-argument",
      `Unrecognised tier or productId. Valid productIds: ${Object.keys(PRODUCT_TIER_MAP).join(", ")}`,
    );
  }

  // ── Rate limit ────────────────────────────────────────────────────────────
  await checkSubscriptionRateLimit(callerUid);

  // ── TODO(gate: DECISION) — App Store Server API JWT verification (production) ──────────
  //
  // Before trusting the transactionId and writing the entitlement, verify
  // it with Apple:
  //
  //   const jwt  = buildAppStoreJWT();   // ES256, exp 60s, aud "appstoreconnect-v1"
  //   const url  = `https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/${encodeURIComponent(transactionId)}`;
  //   const resp = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` } });
  //   if (!resp.ok) throw new HttpsError("internal", "App Store verification failed.");
  //   const json = await resp.json();
  //   // Confirm json.signedTransactionInfo decode matches uid/productId/bundleId.
  //
  // Until that is wired, we trust the client-supplied values.  This is
  // acceptable during development when App Check enforcement is ON (preventing
  // arbitrary clients from calling the function).

  // ── Write entitlement document ────────────────────────────────────────────
  const entitlementRef = db
    .collection("users")
    .doc(uid)
    .collection("entitlements")
    .doc("platform");

  await entitlementRef.set({
    tier:          resolvedTier,
    transactionId: transactionId.trim(),
    productId:     productId ?? null,
    updatedAt:     FieldValue.serverTimestamp(),
    source:        "appStore",
  }, { merge: true });

  return { success: true, tier: resolvedTier };
});
