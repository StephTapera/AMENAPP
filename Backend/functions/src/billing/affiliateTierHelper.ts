import * as admin from "firebase-admin";

export type AffiliateEntitlementTier = "free" | "creator_pro" | "creator_studio" | "organization";

export async function getEntitlementTierForAffiliate(uid: string): Promise<AffiliateEntitlementTier> {
  const snap = await admin.firestore().collection("userSubscriptions").doc(uid).get();
  const data = snap.data() ?? {};
  const tier = data.creatorTier ?? data.tier ?? data.plan ?? "free";
  const allowed: AffiliateEntitlementTier[] = ["free", "creator_pro", "creator_studio", "organization"];
  return allowed.includes(tier as AffiliateEntitlementTier) ? (tier as AffiliateEntitlementTier) : "free";
}
