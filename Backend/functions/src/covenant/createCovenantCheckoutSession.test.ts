import admin from "firebase-admin";
import Stripe from "stripe";
import { createCovenantCheckoutSessionHandler } from "./createCovenantCheckoutSession";

// ── Mock plumbing ─────────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockDoc: jest.Mocked<{
    get: jest.Mock;
    set: jest.Mock;
    update: jest.Mock;
    collection: jest.Mock;
    id: string;
    __data: unknown;
}> = mockAdmin.__mockDoc;
const mockGetUser: jest.Mock = mockAdmin.__mockGetUser;

// Stable reference to the checkout.sessions.create mock exposed by __mocks__/stripe.js
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockSessionsCreate: jest.Mock = (Stripe as any).__mockSessionsCreate;

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeCovenantData(
    overrides: Record<string, unknown> = {}
): Record<string, unknown> {
    return {
        creatorId: "uid-creator",
        name: "Test Covenant",
        tiers: [
            {
                id: "tier-gold",
                name: "Gold",
                price: 9.99,
                stripePriceId: "price_abc123",
            },
            {
                id: "tier-free",
                name: "Free",
                price: 0,
                // intentionally no stripePriceId
            },
        ],
        ...overrides,
    };
}

// ── Setup ──────────────────────────────────────────────────────────────────────

beforeAll(() => {
    process.env.STRIPE_SECRET_KEY = "sk_test_mock";
});

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;

    // Default: covenant doc exists with a paid tier and a free tier.
    mockDoc.get.mockResolvedValue({
        exists: true,
        data: () => makeCovenantData(),
    });

    // Default: auth().getUser resolves with an email.
    mockGetUser.mockResolvedValue({ email: "test@example.com" });

    // Default: Stripe session create succeeds.
    mockSessionsCreate.mockResolvedValue({
        id: "cs_test_123",
        url: "https://checkout.stripe.com/pay/cs_test_123",
    });
});

// ── Tests ──────────────────────────────────────────────────────────────────────

describe("createCovenantCheckoutSessionHandler", () => {

    test("rejects unauthenticated caller", async () => {
        await expect(
            createCovenantCheckoutSessionHandler(null, { covenantId: "cov-1", tierId: "tier-gold" })
        ).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing covenantId", async () => {
        await expect(
            createCovenantCheckoutSessionHandler("uid-user", { tierId: "tier-gold" })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects missing tierId", async () => {
        await expect(
            createCovenantCheckoutSessionHandler("uid-user", { covenantId: "cov-1" })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects tier with no stripePriceId — does not call Stripe", async () => {
        await expect(
            createCovenantCheckoutSessionHandler("uid-user", { covenantId: "cov-1", tierId: "tier-free" })
        ).rejects.toMatchObject({ code: "failed-precondition" });
        expect(mockSessionsCreate).not.toHaveBeenCalled();
    });

    test("propagates Stripe session creation failure as internal HttpsError", async () => {
        mockSessionsCreate.mockRejectedValueOnce(new Error("stripe network error"));
        await expect(
            createCovenantCheckoutSessionHandler("uid-user", { covenantId: "cov-1", tierId: "tier-gold" })
        ).rejects.toMatchObject({ code: "internal" });
    });

    test("success path returns checkoutUrl from Stripe session", async () => {
        const result = await createCovenantCheckoutSessionHandler("uid-user", {
            covenantId: "cov-1",
            tierId: "tier-gold",
        });
        expect(result).toHaveProperty("checkoutUrl", "https://checkout.stripe.com/pay/cs_test_123");
    });

    test("subscription_data.metadata includes covenantId and userId", async () => {
        await createCovenantCheckoutSessionHandler("uid-user", {
            covenantId: "cov-1",
            tierId: "tier-gold",
        });
        const createArg = mockSessionsCreate.mock.calls[0][0] as Record<string, unknown>;
        const subData = createArg["subscription_data"] as { metadata: Record<string, string> };
        expect(subData.metadata).toMatchObject({
            covenantId: "cov-1",
            userId: "uid-user",
        });
    });

    test("session-level metadata also includes covenantId and userId", async () => {
        await createCovenantCheckoutSessionHandler("uid-user", {
            covenantId: "cov-1",
            tierId: "tier-gold",
        });
        const createArg = mockSessionsCreate.mock.calls[0][0] as Record<string, unknown>;
        const sessionMeta = createArg["metadata"] as Record<string, string>;
        expect(sessionMeta).toMatchObject({
            covenantId: "cov-1",
            userId: "uid-user",
        });
    });
});
