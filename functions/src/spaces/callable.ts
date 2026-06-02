// callable.ts — Spaces monetization callable Cloud Functions

import * as functions from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

// ── Interfaces ────────────────────────────────────────────────────────────────

interface CreateSpaceTierInput {
  spaceId: string;
  name: string;
  description: string;
  monthlyPriceCents: number;
  annualPriceCents?: number;
  features: string[];
  isFreeTier: boolean;
  storeKitProductId?: string;
  introMonths?: number;
  introPriceCents?: number;
}

interface GetSpaceEntitlementInput {
  spaceId: string;
}

interface ProcessSubscriptionInput {
  spaceId: string;
  tierId: string;
  storeKitTransactionId: string;
}

interface ProcessRefundInput {
  spaceId: string;
  storeKitTransactionId: string;
}

interface GetPayoutSummaryInput {
  spaceId: string;
  periodKey: string;
}

interface HostKYCOnboardingInput {
  spaceId: string;
  hostType: string;
  displayName: string;
  email: string;
  ein?: string;
}

interface SpaceTierDoc {
  id: string;
  spaceId: string;
  name: string;
  description: string;
  monthlyPriceCents: number;
  annualPriceCents: number | null;
  features: string[];
  isFreeTier: boolean;
  isActive: boolean;
  order: number;
  storeKitProductId: string | null;
  introMonths: number | null;
  introPriceCents: number | null;
  createdAt: FirebaseFirestore.FieldValue;
}

interface SpaceEntitlement {
  userId: string;
  spaceId: string;
  tierId: string;
  source: string;
  grantedAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp | string;
  isActive: boolean;
  storeKitTransactionId: string | null;
}

// ── createSpaceTier ───────────────────────────────────────────────────────────

export const createSpaceTier = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as CreateSpaceTierInput;

    const spaceId = String(data?.spaceId ?? "").trim();
    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");

    const name = String(data?.name ?? "").trim();
    if (!name || name.length < 1 || name.length > 50) {
      throw new functions.HttpsError("invalid-argument", "name must be 1–50 characters.");
    }

    const description = String(data?.description ?? "").trim();
    const monthlyPriceCents = Number(data?.monthlyPriceCents ?? -1);
    if (!Number.isInteger(monthlyPriceCents) || monthlyPriceCents < 0) {
      throw new functions.HttpsError("invalid-argument", "monthlyPriceCents must be a non-negative integer.");
    }

    const isFreeTier = Boolean(data?.isFreeTier);
    if (isFreeTier && monthlyPriceCents !== 0) {
      throw new functions.HttpsError("invalid-argument", "Free tier must have monthlyPriceCents = 0.");
    }

    const features = Array.isArray(data?.features) ? (data.features as string[]) : [];

    // Count existing tiers to determine order
    const tiersSnap = await db.collection("spaces").doc(spaceId).collection("tiers").get();
    const order = tiersSnap.size + 1;

    const tierId = db.collection("spaces").doc(spaceId).collection("tiers").doc().id;

    const tierDoc: SpaceTierDoc = {
      id: tierId,
      spaceId,
      name,
      description,
      monthlyPriceCents,
      annualPriceCents: data?.annualPriceCents != null ? Number(data.annualPriceCents) : null,
      features,
      isFreeTier,
      isActive: true,
      order,
      storeKitProductId: data?.storeKitProductId ? String(data.storeKitProductId) : null,
      introMonths: data?.introMonths != null ? Number(data.introMonths) : null,
      introPriceCents: data?.introPriceCents != null ? Number(data.introPriceCents) : null,
      createdAt: FieldValue.serverTimestamp(),
    };

    await db.collection("spaces").doc(spaceId).collection("tiers").doc(tierId).set(tierDoc);
    logger.info(`createSpaceTier: tierId=${tierId} spaceId=${spaceId} by userId=${userId}`);

    return { tierId, ok: true };
  }
);

// ── getSpaceEntitlement ───────────────────────────────────────────────────────

export const getSpaceEntitlement = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as GetSpaceEntitlementInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");

    // Check for an existing entitlement doc
    const entitlementRef = db
      .collection("spaces").doc(spaceId)
      .collection("entitlements").doc(userId);
    const entitlementSnap = await entitlementRef.get();

    if (entitlementSnap.exists) {
      const doc = entitlementSnap.data() as SpaceEntitlement;
      if (doc.isActive === true) {
        return { entitlement: doc };
      }
    }

    // No active entitlement — check for a free tier
    const freeTierSnap = await db
      .collection("spaces").doc(spaceId)
      .collection("tiers")
      .where("isFreeTier", "==", true)
      .where("isActive", "==", true)
      .limit(1)
      .get();

    if (!freeTierSnap.empty) {
      const freeTier = freeTierSnap.docs[0];
      const syntheticEntitlement: SpaceEntitlement = {
        userId,
        spaceId,
        tierId: freeTier.id,
        source: "free_tier",
        grantedAt: "synthetic",
        isActive: true,
        storeKitTransactionId: null,
      };
      return { entitlement: syntheticEntitlement };
    }

    return { entitlement: null };
  }
);

// ── processSubscription ───────────────────────────────────────────────────────

export const processSubscription = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ProcessSubscriptionInput;

    const spaceId = String(data?.spaceId ?? "").trim();
    const tierId = String(data?.tierId ?? "").trim();
    const storeKitTransactionId = String(data?.storeKitTransactionId ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!tierId) throw new functions.HttpsError("invalid-argument", "tierId is required.");
    if (!storeKitTransactionId) {
      throw new functions.HttpsError("invalid-argument", "storeKitTransactionId is required.");
    }

    // Look up the tier
    const tierRef = db.collection("spaces").doc(spaceId).collection("tiers").doc(tierId);
    const tierSnap = await tierRef.get();
    if (!tierSnap.exists || tierSnap.data()?.isActive !== true) {
      throw new functions.HttpsError("not-found", "Tier not found or inactive.");
    }

    const entitlementData: SpaceEntitlement = {
      userId,
      spaceId,
      tierId,
      source: "appStoreSubscription",
      grantedAt: FieldValue.serverTimestamp(),
      isActive: true,
      storeKitTransactionId,
    };

    const entitlementRef = db
      .collection("spaces").doc(spaceId)
      .collection("entitlements").doc(userId);

    const auditRef = db
      .collection("spaces").doc(spaceId)
      .collection("auditLog").doc();

    const batch = db.batch();
    batch.set(entitlementRef, entitlementData);
    batch.set(auditRef, {
      type: "subscription_created",
      userId,
      tierId,
      transactionId: storeKitTransactionId,
      ts: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    logger.info(`processSubscription: userId=${userId} spaceId=${spaceId} tierId=${tierId}`);
    return { ok: true, entitlement: entitlementData };
  }
);

// ── processRefund ─────────────────────────────────────────────────────────────

export const processRefund = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as ProcessRefundInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    const storeKitTransactionId = String(data?.storeKitTransactionId ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!storeKitTransactionId) {
      throw new functions.HttpsError("invalid-argument", "storeKitTransactionId is required.");
    }

    // Find the entitlement matching the transaction
    const entitlementsSnap = await db
      .collection("spaces").doc(spaceId)
      .collection("entitlements")
      .where("storeKitTransactionId", "==", storeKitTransactionId)
      .limit(1)
      .get();

    if (entitlementsSnap.empty) {
      return { ok: true, entitlementRevoked: false };
    }

    const entitlementDoc = entitlementsSnap.docs[0];
    const auditRef = db
      .collection("spaces").doc(spaceId)
      .collection("auditLog").doc();

    const batch = db.batch();
    batch.update(entitlementDoc.ref, {
      isActive: false,
      revokedAt: FieldValue.serverTimestamp(),
      revokedReason: "refund",
    });
    batch.set(auditRef, {
      type: "subscription_refunded",
      userId: entitlementDoc.data().userId,
      tierId: entitlementDoc.data().tierId,
      transactionId: storeKitTransactionId,
      revokedByUserId: userId,
      ts: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    logger.info(`processRefund: transactionId=${storeKitTransactionId} spaceId=${spaceId}`);
    return { ok: true, entitlementRevoked: true };
  }
);

// ── getPayoutSummary ──────────────────────────────────────────────────────────

export const getPayoutSummary = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as GetPayoutSummaryInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    const periodKey = String(data?.periodKey ?? "").trim();

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!periodKey) throw new functions.HttpsError("invalid-argument", "periodKey is required.");

    // Verify caller is the space host
    const spaceSnap = await db.collection("spaces").doc(spaceId).get();
    if (!spaceSnap.exists) {
      throw new functions.HttpsError("not-found", "Space not found.");
    }
    const spaceData = spaceSnap.data() as { hostUserId?: string };
    if (spaceData?.hostUserId !== userId) {
      throw new functions.HttpsError("permission-denied", "Only the space host may view payout summaries.");
    }

    const payoutSnap = await db
      .collection("spaces").doc(spaceId)
      .collection("payouts").doc(periodKey)
      .get();

    if (!payoutSnap.exists) {
      return { payout: null };
    }

    return { payout: payoutSnap.data() };
  }
);

// ── hostKYCOnboarding ─────────────────────────────────────────────────────────

export const hostKYCOnboarding = functions.onCall(
  { enforceAppCheck: false },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new functions.HttpsError("unauthenticated", "Must be signed in.");

    const data = request.data as HostKYCOnboardingInput;
    const spaceId = String(data?.spaceId ?? "").trim();
    const hostType = String(data?.hostType ?? "").trim();
    const displayName = String(data?.displayName ?? "").trim();
    const email = String(data?.email ?? "").trim();
    const ein = data?.ein ? String(data.ein).trim() : undefined;

    if (!spaceId) throw new functions.HttpsError("invalid-argument", "spaceId is required.");
    if (!hostType) throw new functions.HttpsError("invalid-argument", "hostType is required.");

    if (displayName.length < 2 || displayName.length > 100) {
      throw new functions.HttpsError("invalid-argument", "displayName must be 2–100 characters.");
    }
    if (!email.includes("@")) {
      throw new functions.HttpsError("invalid-argument", "A valid email address is required.");
    }

    const orgHostTypes = ["church", "organization", "nonprofit"];
    if (orgHostTypes.includes(hostType) && !ein) {
      throw new functions.HttpsError(
        "invalid-argument",
        `EIN is required for hostType "${hostType}".`
      );
    }

    await db
      .collection("spaces").doc(spaceId)
      .collection("hostProfile").doc("profile")
      .set(
        {
          hostType,
          displayName,
          email,
          ein: ein ?? null,
          verificationStatus: "pending",
          submittedByUserId: userId,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

    logger.info(`hostKYCOnboarding: spaceId=${spaceId} hostType=${hostType} userId=${userId}`);
    return { ok: true, verificationStatus: "pending" };
  }
);
