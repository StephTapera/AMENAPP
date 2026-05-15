import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

// saveCovenantTierStripePriceId
//
// Callable function invoked by iOS AmenCovenantTierSetupSheet.
// Allows the covenant creator to attach a pre-configured Stripe Price ID
// to a specific tier. The Price ID must already exist in Stripe — this
// function only stores the reference; it does NOT create Stripe products.

interface SaveTierPriceInput {
    covenantId: string;
    tierId: string;
    stripePriceId: string;
}

const STRIPE_PRICE_ID_RE = /^price_[A-Za-z0-9]+$/;

export const saveCovenantTierStripePriceId = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        // ── 1. Auth ────────────────────────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;

        // ── 2. Input validation ────────────────────────────────────────────────
        const { covenantId, tierId, stripePriceId } =
            (request.data ?? {}) as Partial<SaveTierPriceInput>;

        if (typeof covenantId !== "string" || !covenantId.trim()) {
            throw new HttpsError("invalid-argument", "covenantId is required.");
        }
        if (typeof tierId !== "string" || !tierId.trim()) {
            throw new HttpsError("invalid-argument", "tierId is required.");
        }
        if (typeof stripePriceId !== "string" || !stripePriceId.trim()) {
            throw new HttpsError("invalid-argument", "stripePriceId is required.");
        }
        if (!STRIPE_PRICE_ID_RE.test(stripePriceId.trim())) {
            throw new HttpsError(
                "invalid-argument",
                "stripePriceId must start with 'price_' and contain only alphanumeric characters."
            );
        }

        const db = admin.firestore();

        // ── 3. Verify caller is the covenant creator ───────────────────────────
        const covenantRef = db.collection("covenants").doc(covenantId.trim());
        const covenantSnap = await covenantRef.get();

        if (!covenantSnap.exists) {
            throw new HttpsError("not-found", "Community not found.");
        }
        const covenantData = covenantSnap.data()!;
        if (covenantData.creatorId !== uid) {
            throw new HttpsError(
                "permission-denied",
                "Only the community creator can configure payment tiers."
            );
        }

        // ── 4. Patch the matching tier inside the tiers array ─────────────────
        const tiers: Array<Record<string, unknown>> = Array.isArray(covenantData.tiers)
            ? (covenantData.tiers as Array<Record<string, unknown>>)
            : [];

        const tierIndex = tiers.findIndex((t) => t["id"] === tierId.trim());
        if (tierIndex === -1) {
            throw new HttpsError("not-found", `Tier '${tierId}' not found in this community.`);
        }

        const updatedTiers = tiers.map((t, i) =>
            i === tierIndex
                ? { ...t, stripePriceId: stripePriceId.trim() }
                : t
        );

        await covenantRef.update({
            tiers: updatedTiers,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        logger.info("[saveCovenantTierStripePriceId] Tier price configured", {
            covenantId, tierId, uid,
        });

        return { success: true };
    }
);
