/**
 * spacesFunctions.js
 * AMEN Spaces — Monetization callables
 * Handles: createSpaceTier, getSpaceEntitlement, processSubscription,
 *          processRefund, getPayoutSummary, hostKYCOnboarding
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

// ── createSpaceTier ──────────────────────────────────────────────────────────

exports.createSpaceTier = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, name, description, monthlyPriceCents, annualPriceCents,
          features, isFreeTier, storeKitProductId, introMonths, introPriceCents } = request.data ?? {};

  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");
  if (!name || name.length < 1 || name.length > 50) throw new HttpsError("invalid-argument", "name must be 1-50 chars.");
  if (typeof monthlyPriceCents !== "number" || monthlyPriceCents < 0) throw new HttpsError("invalid-argument", "monthlyPriceCents must be >= 0.");
  if (isFreeTier && monthlyPriceCents !== 0) throw new HttpsError("invalid-argument", "Free tier must have monthlyPriceCents = 0.");

  const existingTiers = await db.collection("spaces").doc(spaceId).collection("tiers").count().get();
  const order = (existingTiers.data()?.count ?? 0) + 1;

  const tierId = `tier_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const tierDoc = {
    id: tierId, spaceId, name, description: description ?? "",
    monthlyPriceCents, annualPriceCents: annualPriceCents ?? null,
    features: Array.isArray(features) ? features : [],
    isFreeTier: Boolean(isFreeTier), storeKitProductId: storeKitProductId ?? null,
    introMonths: introMonths ?? null, introPriceCents: introPriceCents ?? null,
    order, isActive: true, createdAt: FieldValue.serverTimestamp(),
  };

  await db.collection("spaces").doc(spaceId).collection("tiers").doc(tierId).set(tierDoc);
  return { tierId, ok: true };
});

// ── getSpaceEntitlement ──────────────────────────────────────────────────────

exports.getSpaceEntitlement = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId } = request.data ?? {};
  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");

  const entSnap = await db.collection("spaces").doc(spaceId)
    .collection("entitlements").doc(userId).get();

  if (entSnap.exists && entSnap.data()?.isActive) {
    return { entitlement: entSnap.data() };
  }

  // Check for free tier
  const freeTierQuery = await db.collection("spaces").doc(spaceId)
    .collection("tiers").where("isFreeTier", "==", true).where("isActive", "==", true).limit(1).get();

  if (!freeTierQuery.empty) {
    const freeTier = freeTierQuery.docs[0].data();
    return {
      entitlement: {
        userId, spaceId, tierId: freeTier.id,
        source: "freeTier", grantedAt: Timestamp.now(),
        expiresAt: null, isActive: true,
      }
    };
  }

  return { entitlement: null };
});

// ── processSubscription ──────────────────────────────────────────────────────

exports.processSubscription = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, tierId, storeKitTransactionId, idempotencyKey } = request.data ?? {};
  if (!spaceId || !tierId || !storeKitTransactionId) {
    throw new HttpsError("invalid-argument", "spaceId, tierId, and storeKitTransactionId are required.");
  }

  // Idempotency: if the client sends the same key twice (e.g. app killed between
  // notify and finish), return the already-written entitlement without re-writing.
  if (idempotencyKey) {
    const idemRef = db.collection("_idempotencyKeys").doc(`processSubscription_${idempotencyKey}`);
    const idemSnap = await idemRef.get();
    if (idemSnap.exists) {
      const entRef = db.collection("spaces").doc(spaceId).collection("entitlements").doc(userId);
      const entSnap = await entRef.get();
      return { ok: true, entitlement: entSnap.data() ?? null, idempotent: true };
    }
  }

  const tierSnap = await db.collection("spaces").doc(spaceId).collection("tiers").doc(tierId).get();
  if (!tierSnap.exists || !tierSnap.data()?.isActive) {
    throw new HttpsError("not-found", "Tier not found or inactive.");
  }

  const batch = db.batch();
  const entRef = db.collection("spaces").doc(spaceId).collection("entitlements").doc(userId);
  const entitlement = {
    userId, spaceId, tierId, source: "appStoreSubscription",
    grantedAt: FieldValue.serverTimestamp(), expiresAt: null,
    isActive: true, storeKitTransactionId,
  };
  batch.set(entRef, entitlement, { merge: true });

  const auditRef = db.collection("spaces").doc(spaceId).collection("auditLog").doc();
  batch.set(auditRef, {
    type: "subscription_created", userId, tierId,
    transactionId: storeKitTransactionId, ts: FieldValue.serverTimestamp(),
  });

  if (idempotencyKey) {
    const idemRef = db.collection("_idempotencyKeys").doc(`processSubscription_${idempotencyKey}`);
    batch.set(idemRef, { createdAt: FieldValue.serverTimestamp(), userId, spaceId, tierId });
  }

  await batch.commit();
  return { ok: true, entitlement };
});

// ── processRefund ────────────────────────────────────────────────────────────

exports.processRefund = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, storeKitTransactionId } = request.data ?? {};
  if (!spaceId || !storeKitTransactionId) {
    throw new HttpsError("invalid-argument", "spaceId and storeKitTransactionId are required.");
  }

  const entsQuery = await db.collection("spaces").doc(spaceId)
    .collection("entitlements")
    .where("storeKitTransactionId", "==", storeKitTransactionId).limit(1).get();

  if (entsQuery.empty) return { ok: true, entitlementRevoked: false };

  const entRef = entsQuery.docs[0].ref;
  await entRef.update({ isActive: false, revokedAt: FieldValue.serverTimestamp(), revokedReason: "refund" });

  const auditRef = db.collection("spaces").doc(spaceId).collection("auditLog").doc();
  await auditRef.set({ type: "refund_processed", userId, transactionId: storeKitTransactionId, ts: FieldValue.serverTimestamp() });

  return { ok: true, entitlementRevoked: true };
});

// ── getPayoutSummary ─────────────────────────────────────────────────────────

exports.getPayoutSummary = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, periodKey } = request.data ?? {};
  if (!spaceId || !periodKey) throw new HttpsError("invalid-argument", "spaceId and periodKey are required.");

  const spaceSnap = await db.collection("spaces").doc(spaceId).get();
  if (spaceSnap.data()?.hostUserId !== userId) {
    throw new HttpsError("permission-denied", "Only the host can view payout summaries.");
  }

  const payoutSnap = await db.collection("spaces").doc(spaceId).collection("payouts").doc(periodKey).get();
  return { payout: payoutSnap.exists ? payoutSnap.data() : null };
});

// ── hostKYCOnboarding ────────────────────────────────────────────────────────

exports.hostKYCOnboarding = onCall({ enforceAppCheck: true }, async (request) => { // requires App Check token; disable locally via FUNCTIONS_EMULATOR
  const userId = request.auth?.uid;
  if (!userId) throw new HttpsError("unauthenticated", "Must be signed in.");

  const { spaceId, hostType, displayName, email, ein } = request.data ?? {};
  if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required.");
  if (!displayName || displayName.length < 2 || displayName.length > 100) {
    throw new HttpsError("invalid-argument", "displayName must be 2-100 chars.");
  }
  if (!email || !email.includes("@")) throw new HttpsError("invalid-argument", "Valid email required.");
  if (["church", "organization", "nonprofit"].includes(hostType) && !ein) {
    throw new HttpsError("invalid-argument", "EIN is required for churches and organizations.");
  }

  await db.collection("spaces").doc(spaceId).collection("settings").doc("hostProfile").set({
    hostType, displayName, email, ein: ein ?? null,
    verificationStatus: "pending", updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, verificationStatus: "pending" };
});
