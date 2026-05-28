"use strict";
// createSpaceCheckoutSession.ts
// AMEN Spaces — Cloud Function: Create Stripe Checkout Session for a paid Space
//
// Callable: { spaceId: string }
//
// Flow:
//   1. Validate caller is authenticated.
//   2. Validate space exists, has accessPolicy != "free", and has priceConfig.
//   3. Reject if caller already has an active/grace entitlement.
//   4. Resolve the owning community's stripeConnectAccountId.
//   5. Create a Stripe Checkout Session (one-time) or Subscription (recurring)
//      against the Connect account.
//   6. Metadata MUST include amenUserId + amenSpaceId for webhook routing.
//   7. Returns { checkoutURL: string }.
//
// Entitlement write:
//   The webhook handler (stripeWebhookEntitlement.ts) writes the entitlement
//   when Stripe fires invoice.payment_succeeded. Client NEVER writes entitlements.
//
// Hard constraints:
//   - Money never crosses a community Link — owning community's Connect account only.
//   - Metadata MUST include amenUserId and amenSpaceId.
//   - No hard-delete of any document.
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createSpaceCheckoutSession = void 0;
const logger = __importStar(require("firebase-functions/logger"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const stripe_1 = __importDefault(require("stripe"));
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
// Stripe is initialized lazily so the secret is resolved at runtime.
// Set via: firebase functions:secrets:set STRIPE_SECRET_KEY
let stripeClient = null;
function getStripe() {
    if (!stripeClient) {
        const key = process.env.STRIPE_SECRET_KEY;
        if (!key) {
            throw new https_1.HttpsError("failed-precondition", "Stripe secret key is not configured.");
        }
        stripeClient = new stripe_1.default(key, { apiVersion: "2025-02-24.acacia" });
    }
    return stripeClient;
}
// The callback URL deep-links back into the AMEN app.
// iOS registers `amen://` as a custom URL scheme (see Info.plist).
const SUCCESS_URL = "https://amenapp.com/spaces/checkout-complete?spaceId={SPACE_ID}";
const CANCEL_URL = "https://amenapp.com/spaces/checkout-cancel?spaceId={SPACE_ID}";
// MARK: - Callable
exports.createSpaceCheckoutSession = (0, https_1.onCall)({
    enforceAppCheck: true,
    secrets: ["STRIPE_SECRET_KEY"],
}, async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const { spaceId } = request.data;
    if (!spaceId || typeof spaceId !== "string" || spaceId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "spaceId is required.");
    }
    // ── 1. Resolve space ──────────────────────────────────────────────────────
    const spaceDoc = await db.collection("spaces").doc(spaceId).get();
    if (!spaceDoc.exists) {
        throw new https_1.HttpsError("not-found", `Space ${spaceId} not found.`);
    }
    const spaceData = spaceDoc.data();
    const accessPolicy = spaceData.accessPolicy ?? "free";
    const priceConfig = spaceData.priceConfig ?? null;
    const communityId = spaceData.communityId ?? "";
    if (accessPolicy === "free") {
        throw new https_1.HttpsError("invalid-argument", "This Space is free — no purchase required.");
    }
    if (!priceConfig || !priceConfig.amountCents || !priceConfig.currency) {
        throw new https_1.HttpsError("failed-precondition", "This Space does not have a price configured.");
    }
    if (!communityId) {
        throw new https_1.HttpsError("internal", "Space is missing communityId.");
    }
    // ── 2. Check existing entitlement ─────────────────────────────────────────
    const entitlementId = `${callerUid}_${spaceId}`;
    const entitlementDoc = await db
        .collection("entitlements")
        .doc(entitlementId)
        .get();
    if (entitlementDoc.exists) {
        const status = entitlementDoc.data()?.status;
        if (status === "active" || status === "grace") {
            throw new https_1.HttpsError("already-exists", "You already have access to this Space.");
        }
    }
    // ── 3. Resolve community's Stripe Connect account ────────────────────────
    const communityDoc = await db
        .collection("amenCommunities")
        .doc(communityId)
        .get();
    if (!communityDoc.exists) {
        throw new https_1.HttpsError("not-found", `Community ${communityId} not found.`);
    }
    const stripeConnectAccountId = communityDoc.data()?.stripeConnectAccountId;
    if (!stripeConnectAccountId) {
        throw new https_1.HttpsError("failed-precondition", "This community has not set up Stripe Connect. The owner must enable paid Spaces first.");
    }
    // ── 4. Create Stripe Checkout Session ────────────────────────────────────
    const stripe = getStripe();
    const successURL = SUCCESS_URL.replace("{SPACE_ID}", spaceId);
    const cancelURL = CANCEL_URL.replace("{SPACE_ID}", spaceId);
    // Shared metadata required by the webhook handler (stripeWebhookEntitlement.ts)
    // MUST include amenUserId and amenSpaceId for status routing.
    const stripeMetadata = {
        amenUserId: callerUid,
        amenSpaceId: spaceId,
    };
    let checkoutURL;
    if (accessPolicy === "recurring" && priceConfig.interval) {
        // ── Recurring: create Checkout Session in subscription mode ────────────
        // Create or reuse a Stripe Price object for this Space's product.
        // In production, the Space's priceId should be stored in Firestore to avoid
        // creating duplicate Price objects on every session. For v1 we create inline.
        const session = await stripe.checkout.sessions.create({
            mode: "subscription",
            line_items: [
                {
                    price_data: {
                        currency: priceConfig.currency.toLowerCase(),
                        unit_amount: priceConfig.amountCents,
                        recurring: {
                            interval: priceConfig.interval || "month",
                        },
                        product_data: {
                            name: spaceData.title ?? "Community Space",
                            metadata: stripeMetadata,
                        },
                    },
                    quantity: 1,
                },
            ],
            subscription_data: {
                metadata: stripeMetadata,
            },
            metadata: stripeMetadata,
            success_url: successURL,
            cancel_url: cancelURL,
        }, {
            stripeAccount: stripeConnectAccountId,
        });
        if (!session.url) {
            throw new https_1.HttpsError("internal", "Stripe did not return a checkout URL.");
        }
        checkoutURL = session.url;
        logger.info(`[createSpaceCheckoutSession] Created recurring session: spaceId=${spaceId} user=${callerUid} sessionId=${session.id}`);
    }
    else {
        // ── One-time: create Checkout Session in payment mode ──────────────────
        const session = await stripe.checkout.sessions.create({
            mode: "payment",
            line_items: [
                {
                    price_data: {
                        currency: priceConfig.currency.toLowerCase(),
                        unit_amount: priceConfig.amountCents,
                        product_data: {
                            name: spaceData.title ?? "Community Space",
                            metadata: stripeMetadata,
                        },
                    },
                    quantity: 1,
                },
            ],
            payment_intent_data: {
                metadata: stripeMetadata,
            },
            metadata: stripeMetadata,
            success_url: successURL,
            cancel_url: cancelURL,
        }, {
            stripeAccount: stripeConnectAccountId,
        });
        if (!session.url) {
            throw new https_1.HttpsError("internal", "Stripe did not return a checkout URL.");
        }
        checkoutURL = session.url;
        logger.info(`[createSpaceCheckoutSession] Created one-time session: spaceId=${spaceId} user=${callerUid} sessionId=${session.id}`);
    }
    return { checkoutURL };
});
