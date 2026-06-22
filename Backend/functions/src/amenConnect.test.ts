import admin from "firebase-admin";
import StripeConstructor from "stripe";
import {
    collectAuthorizedAIContext,
    createConnectStripeCheckoutSession,
    handleConnectStripeEvent,
    runConnectAI,
} from "./amenConnect";

type StripeClient = InstanceType<typeof StripeConstructor>;
type StripeCheckoutSession = {
    id: string;
    object: "checkout.session";
    mode: string;
    subscription?: string;
    customer?: string;
    metadata?: Record<string, string>;
};
type StripeEvent = {
    id: string;
    object: "event";
    type: string;
    data: { object: unknown };
};

const mockAdmin = admin as unknown as {
    __mockDoc: {
        get: jest.Mock;
        set: jest.Mock;
        collection: jest.Mock;
        id: string;
        __data: unknown;
    };
    __mockQuery: {
        get: jest.Mock;
    };
    __mockGetUser: jest.Mock;
};

const mockDoc = mockAdmin.__mockDoc;
const mockQuery = mockAdmin.__mockQuery;
const mockGetUser = mockAdmin.__mockGetUser;
const mockSessionsCreate: jest.Mock = (StripeConstructor as unknown as { __mockSessionsCreate: jest.Mock }).__mockSessionsCreate;

function makeDb() {
    return admin.firestore();
}

beforeAll(() => {
    process.env.STRIPE_SECRET_KEY = "sk_test_connect";
});

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;
    mockDoc.get.mockResolvedValue({ exists: true, data: () => mockDoc.__data });
    mockDoc.set.mockResolvedValue(undefined);
    mockGetUser.mockResolvedValue({ email: "connect@example.com" });
    mockSessionsCreate.mockResolvedValue({ id: "cs_connect_123", url: "https://checkout.stripe.com/pay/cs_connect_123" });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true });
});

describe("Amen Connect Stripe provider wiring", () => {
    test("creates Stripe subscription checkout with Connect tier metadata and no access grant", async () => {
        mockDoc.__data = {
            moderationStatus: "approved",
            stripePriceId: "price_connect_tier",
        };

        const result = await createConnectStripeCheckoutSession(
            "uid-member",
            { creatorId: "creator-1", tierId: "tier-pro" },
            "tier",
            "subscribeToConnectTier",
            "subscription"
        );

        expect(result).toMatchObject({
            checkoutUrl: "https://checkout.stripe.com/pay/cs_connect_123",
            paymentState: "checkout_created",
            accessGranted: false,
        });

        const createArg = mockSessionsCreate.mock.calls[0][0] as {
            mode: string;
            subscription_data?: { metadata?: Record<string, string> };
            metadata?: Record<string, string>;
        };
        expect(createArg.mode).toBe("subscription");
        expect(createArg.subscription_data?.metadata).toMatchObject({
            connectKind: "tier",
            creatorId: "creator-1",
            targetId: "tier-pro",
            userId: "uid-member",
        });
        expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
            paymentState: "checkout_created",
            accessGranted: false,
            provider: "stripe",
        }));
    });

    test("webhook writes server-owned membership state for active subscription", async () => {
        const stripe = {
            subscriptions: {
                retrieve: jest.fn().mockResolvedValue({
                    id: "sub_connect_123",
                    status: "active",
                    customer: "cus_connect",
                    metadata: {
                        connectKind: "tier",
                        creatorId: "creator-1",
                        targetId: "tier-pro",
                        userId: "uid-member",
                        connectPaymentId: "payment-1",
                    },
                }),
            },
        };

        await handleConnectStripeEvent({
            id: "evt_connect",
            object: "event",
            type: "checkout.session.completed",
            data: {
                object: {
                    id: "cs_connect_123",
                    object: "checkout.session",
                    mode: "subscription",
                    subscription: "sub_connect_123",
                    customer: "cus_connect",
                    metadata: {
                        connectKind: "tier",
                        creatorId: "creator-1",
                        targetId: "tier-pro",
                        userId: "uid-member",
                        connectPaymentId: "payment-1",
                    },
                } as StripeCheckoutSession,
            },
        } as StripeEvent, makeDb(), stripe as unknown as Pick<StripeClient, "subscriptions">);

        expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
            membershipStatus: "active",
            accessGranted: true,
            source: "stripe_subscription",
            stripeSubscriptionId: "sub_connect_123",
        }), { merge: true });
    });

    test("webhook writes server-owned product purchase state for completed payment", async () => {
        await handleConnectStripeEvent({
            id: "evt_connect",
            object: "event",
            type: "checkout.session.completed",
            data: {
                object: {
                    id: "cs_product_123",
                    object: "checkout.session",
                    mode: "payment",
                    metadata: {
                        connectKind: "product",
                        creatorId: "creator-1",
                        targetId: "product-1",
                        userId: "uid-member",
                        connectPaymentId: "payment-product",
                    },
                } as StripeCheckoutSession,
            },
        } as StripeEvent, makeDb(), { subscriptions: { retrieve: jest.fn() } } as unknown as Pick<StripeClient, "subscriptions">);

        expect(mockDoc.set).toHaveBeenCalledWith(expect.objectContaining({
            purchaseState: "active",
            accessGranted: true,
            source: "stripe_checkout",
            stripeCheckoutSessionId: "cs_product_123",
        }), { merge: true });
    });
});

describe("Amen Connect Anthropic AI provider wiring", () => {
    test("authorized AI context excludes deleted, AI-excluded, confidential, youth, and paid messages", async () => {
        mockQuery.get.mockResolvedValue({
            docs: [
                { data: () => ({ senderId: "u1", body: "visible update" }) },
                { data: () => ({ senderId: "u2", body: "deleted secret", deletedAt: {} }) },
                { data: () => ({ senderId: "u3", body: "excluded secret", aiExcluded: true }) },
                { data: () => ({ senderId: "u4", body: "confidential secret", visibility: "confidential" }) },
                { data: () => ({ senderId: "u5", body: "youth secret", visibility: "youthProtected" }) },
                { data: () => ({ senderId: "u6", body: "paid secret", requiredTierId: "tier-pro" }) },
            ],
            empty: false,
        });

        const context = await collectAuthorizedAIContext("uid-member", "summarizeConnectChannel", {
            spaceId: "space-1",
            channelId: "general",
        });

        expect(context).toContain("visible update");
        expect(context).not.toContain("deleted secret");
        expect(context).not.toContain("excluded secret");
        expect(context).not.toContain("confidential secret");
        expect(context).not.toContain("youth secret");
        expect(context).not.toContain("paid secret");
    });

    test("provider failure returns safe internal error instead of fake output", async () => {
        const originalFetch = global.fetch;
        global.fetch = jest.fn().mockResolvedValue({ ok: false, status: 503 }) as unknown as typeof fetch;

        await expect(runConnectAI("generateConnectCatchUp", "authorized content"))
            .rejects.toMatchObject({ code: "internal" });

        global.fetch = originalFetch;
    });
});
