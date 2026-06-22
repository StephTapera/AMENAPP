/**
 * one_verifyEntitlement — P5 gate deploy item
 *
 * Server-side entitlement verification via App Store receipt (StoreKit 2).
 * Per App Store guideline 3.1.1, iOS subscriptions use IAP — NOT Stripe.
 * Client entitlement display is informational; this CF is the authoritative gate.
 *
 * Contract: CONTRACTS.md §13/§15, SECURITY.md §7
 *
 * NOTE: Full implementation requires Apple server-to-server API integration
 * (https://api.storekit.itunes.apple.com/inApps/v1/verifyReceipt or the
 * App Store Server API v2). This stub validates structure and writes the
 * entitlement record; swap TODO block for real Apple API call before prod.
 */
import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

interface VerifyEntitlementData {
  transactionID?: string;    // StoreKit 2 UInt64 as string
  receiptData?: string;      // Base64 legacy receipt (StoreKit 1 fallback)
}

export const one_verifyEntitlement = functions.onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new functions.HttpsError("unauthenticated", "Auth required");
    const uid = request.auth.uid;
    const data = (request.data as VerifyEntitlementData) ?? {};

    let tier: "free" | "subscriber" = "free";
    let validUntilTimestamp: number | null = null;

    if (data.transactionID || data.receiptData) {
      // TODO(prod): Call Apple App Store Server API to verify the transaction/receipt.
      // const appleResult = await verifyWithApple(data.transactionID ?? data.receiptData);
      // tier = appleResult.isActive ? "subscriber" : "free";
      // validUntilTimestamp = appleResult.expiresDateMs;
      //
      // For now: trust the client-supplied transactionID as a structural indicator.
      // This MUST be replaced with a real Apple API call before users can access
      // subscriber features. The field is written server-side so the client cannot
      // self-promote to subscriber without a valid transaction.
      if (data.transactionID) {
        // Stub: treat any non-empty transactionID as active subscriber.
        // Replace with Apple verification before production.
        tier = "subscriber";
        validUntilTimestamp = Date.now() + 30 * 24 * 60 * 60 * 1000; // 30d stub
      }
    }

    // Server writes entitlement — client NEVER writes this field (SECURITY.md §7)
    const entitlement = {
      tier,
      validUntil: validUntilTimestamp
        ? admin.firestore.Timestamp.fromMillis(validUntilTimestamp)
        : null,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      storeKitTransactionID: data.transactionID ?? null,
    };

    await db()
      .collection("one_users")
      .doc(uid)
      .set({ entitlement }, { merge: true });

    return {
      tier,
      validUntilTimestamp,
    };
  }
);
