"use strict";
// createStripeConnectAccount.ts
// AMEN Spaces — Cloud Function: Create Stripe Connect Account for a Community
//
// Callable: { communityId: string }
//
// Flow:
//   1. Validate caller is authenticated and is the owner of the community.
//   2. If the community already has a stripeConnectAccountId, generate a new
//      account link and return it (idempotent refresh).
//   3. Otherwise: create a Stripe Express account linked to this community.
//   4. Write stripeConnectAccountId to amenCommunities/{communityId} via Admin SDK.
//   5. Return { accountId: string, onboardingURL: string }.
//
// Hard constraints:
//   - stripeConnectAccountId is SERVER-OWNED — only this function writes it.
//   - Community collection is `amenCommunities` (not `communities`).
//   - Money never crosses a community Link — each community has its own account.
//   - Caller MUST be community owner (not just admin).
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
exports.createStripeConnectAccount = void 0;
const logger = __importStar(require("firebase-functions/logger"));
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const stripe_1 = __importDefault(require("stripe"));
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();
// Stripe lazy init — secret set via: firebase functions:secrets:set STRIPE_SECRET_KEY
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
// Onboarding return / refresh URLs — deep-links back into the AMEN app.
const RETURN_URL = "https://amenapp.com/spaces/stripe-complete?communityId={COMMUNITY_ID}";
const REFRESH_URL = "https://amenapp.com/spaces/stripe-refresh?communityId={COMMUNITY_ID}";
// MARK: - Callable
exports.createStripeConnectAccount = (0, https_1.onCall)({
    enforceAppCheck: true,
    secrets: ["STRIPE_SECRET_KEY"],
}, async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in required.");
    }
    const { communityId } = request.data;
    if (!communityId || typeof communityId !== "string" || communityId.trim() === "") {
        throw new https_1.HttpsError("invalid-argument", "communityId is required.");
    }
    // ── 1. Resolve community and validate ownership ───────────────────────────
    const communityDoc = await db
        .collection("amenCommunities")
        .doc(communityId)
        .get();
    if (!communityDoc.exists) {
        throw new https_1.HttpsError("not-found", `Community ${communityId} not found.`);
    }
    const communityData = communityDoc.data();
    const ownerUserId = communityData.ownerUserId ?? "";
    // Only the community owner may enable paid Spaces.
    if (ownerUserId !== callerUid) {
        // Check member record as a fallback (owner role in members subcollection)
        const memberDoc = await db
            .collection("amenCommunities")
            .doc(communityId)
            .collection("members")
            .doc(callerUid)
            .get();
        const role = memberDoc.data()?.role;
        if (role !== "owner") {
            throw new https_1.HttpsError("permission-denied", "Only the community owner can enable paid Spaces.");
        }
    }
    const stripe = getStripe();
    const returnURL = RETURN_URL.replace("{COMMUNITY_ID}", communityId);
    const refreshURL = REFRESH_URL.replace("{COMMUNITY_ID}", communityId);
    // ── 2. Idempotent: return new link for existing account ───────────────────
    const existingAccountId = communityData.stripeConnectAccountId;
    if (existingAccountId) {
        logger.info(`[createStripeConnectAccount] Community ${communityId} already has account ${existingAccountId}. Generating new link.`);
        const accountLink = await stripe.accountLinks.create({
            account: existingAccountId,
            refresh_url: refreshURL,
            return_url: returnURL,
            type: "account_onboarding",
        });
        return {
            accountId: existingAccountId,
            onboardingURL: accountLink.url,
        };
    }
    // ── 3. Create new Stripe Express account ─────────────────────────────────
    const account = await stripe.accounts.create({
        type: "express",
        metadata: {
            amenCommunityId: communityId,
            amenOwnerUserId: callerUid,
        },
        capabilities: {
            card_payments: { requested: true },
            transfers: { requested: true },
        },
    });
    logger.info(`[createStripeConnectAccount] Created Express account ${account.id} for community ${communityId}`);
    // ── 4. Write stripeConnectAccountId to Firestore (SERVER-OWNED) ──────────
    await db
        .collection("amenCommunities")
        .doc(communityId)
        .update({
        stripeConnectAccountId: account.id,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    // ── 5. Generate onboarding link ───────────────────────────────────────────
    const accountLink = await stripe.accountLinks.create({
        account: account.id,
        refresh_url: refreshURL,
        return_url: returnURL,
        type: "account_onboarding",
    });
    logger.info(`[createStripeConnectAccount] Onboarding link created for account ${account.id}`);
    return {
        accountId: account.id,
        onboardingURL: accountLink.url,
    };
});
