import { writeMemberIndex, handleStripeEvent } from "./stripeCovenantWebhook";
import admin from "firebase-admin";
import Stripe from "stripe";

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

// Stripe subscriptions mock — injected into handleStripeEvent as third argument
const mockStripeSubscriptions = {
    retrieve: jest.fn(),
};

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeDb() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return admin.firestore() as any;
}

function makeSubscriptionEvent(
    type: "customer.subscription.created" | "customer.subscription.updated" | "customer.subscription.deleted",
    overrides: Partial<Stripe.Subscription> = {}
): Stripe.Event {
    return {
        id: "evt_test",
        object: "event",
        type,
        data: {
            object: {
                id: "sub_123",
                object: "subscription",
                status: "active",
                customer: "cus_abc",
                metadata: { covenantId: "cov-1", userId: "uid-alice" },
                ...overrides,
            } as Stripe.Subscription,
        },
    } as Stripe.Event;
}

function makeCheckoutSessionEvent(
    sessionOverrides: Partial<Stripe.Checkout.Session> = {}
): Stripe.Event {
    return {
        id: "evt_test",
        object: "event",
        type: "checkout.session.completed",
        data: {
            object: {
                id: "cs_test",
                object: "checkout.session",
                mode: "subscription",
                subscription: "sub_123",
                customer: "cus_abc",
                metadata: {},
                ...sessionOverrides,
            } as Stripe.Checkout.Session,
        },
    } as Stripe.Event;
}

// ── Setup ──────────────────────────────────────────────────────────────────────

beforeAll(() => {
    // writeMemberIndex calls FieldValue.serverTimestamp — add it if missing.
    (admin.firestore.FieldValue as unknown as Record<string, unknown>).serverTimestamp =
        jest.fn(() => ({ _type: "serverTimestamp" }));
    (admin.firestore.FieldValue as unknown as Record<string, unknown>).increment =
        jest.fn((n: number) => ({ _type: "increment", n }));
});

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;
    mockDoc.get.mockResolvedValue({ data: () => null, exists: false });
    mockDoc.set.mockResolvedValue(undefined);
    mockDoc.update.mockResolvedValue(undefined);
    mockStripeSubscriptions.retrieve.mockResolvedValue({
        id: "sub_123",
        status: "active",
        customer: "cus_abc",
        metadata: { covenantId: "cov-1", userId: "uid-alice" },
    } as unknown as Stripe.Subscription);
});

// ── writeMemberIndex ──────────────────────────────────────────────────────────

describe("writeMemberIndex", () => {

    test("writes member index with active status on first activation", async () => {
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-alice",
            stripeStatus: "active",
            stripeCustomerId: "cus_abc",
            stripeSubscriptionId: "sub_123",
        });
        expect(mockDoc.set).toHaveBeenCalledTimes(1);
        const [, data, options] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>, unknown];
        expect(data).toMatchObject({
            userId: "uid-alice",
            covenantId: "cov-1",
            status: "active",
            role: "member",
            source: "stripe_subscription",
            stripeCustomerId: "cus_abc",
            stripeSubscriptionId: "sub_123",
        });
        expect(data.activatedAt).toBeDefined();    // new activation stamps activatedAt
        expect(data.indexedAt).toBeDefined();
        expect(data.updatedAt).toBeDefined();
        expect(options).toEqual({ merge: true });
    });

    test("repeated webhook is idempotent — merge:true prevents data loss", async () => {
        // Simulate doc already exists and is active
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ status: "active", role: "member" }),
            exists: true,
        });
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-alice",
            stripeStatus: "active",
            stripeCustomerId: "cus_abc",
            stripeSubscriptionId: "sub_123",
        });
        expect(mockDoc.set).toHaveBeenCalledTimes(1);
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        // No re-stamp of activatedAt when already active
        expect(data.activatedAt).toBeUndefined();
        expect(data.status).toBe("active");
    });

    test("preserves existing creator/admin role — never downgraded", async () => {
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ status: "active", role: "admin" }),
            exists: true,
        });
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-admin",
            stripeStatus: "active",
            stripeCustomerId: "cus_xyz",
            stripeSubscriptionId: "sub_999",
        });
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.role).toBe("admin");  // not overwritten with "member"
    });

    test("cancelled subscription sets status to cancelled, does not delete doc", async () => {
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ status: "active", role: "member" }),
            exists: true,
        });
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-alice",
            stripeStatus: "canceled",
            stripeCustomerId: "cus_abc",
            stripeSubscriptionId: "sub_123",
        });
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.status).toBe("cancelled");
        expect(data.activatedAt).toBeUndefined();
    });

    test("trialing subscription grants access and stamps activatedAt", async () => {
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-bob",
            stripeStatus: "trialing",
            stripeCustomerId: "cus_bob",
            stripeSubscriptionId: "sub_bob",
        });
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.status).toBe("trialing");
        expect(data.activatedAt).toBeDefined();
    });

    test("incomplete/unpaid status is skipped — no write occurs", async () => {
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-alice",
            stripeStatus: "incomplete",
            stripeCustomerId: "cus_abc",
            stripeSubscriptionId: "sub_123",
        });
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("reactivation after cancellation re-stamps activatedAt", async () => {
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ status: "cancelled", role: "member" }),
            exists: true,
        });
        await writeMemberIndex({
            db: makeDb(),
            covenantId: "cov-1",
            userId: "uid-alice",
            stripeStatus: "active",
            stripeCustomerId: "cus_abc",
            stripeSubscriptionId: "sub_new",
        });
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.status).toBe("active");
        expect(data.activatedAt).toBeDefined(); // reactivation re-stamps
    });
});

// ── handleStripeEvent ─────────────────────────────────────────────────────────

describe("handleStripeEvent", () => {

    test("customer.subscription.created writes member index", async () => {
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await handleStripeEvent(
            makeSubscriptionEvent("customer.subscription.created"),
            makeDb(),
            mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
        );
        expect(mockDoc.set).toHaveBeenCalledTimes(1);
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data).toMatchObject({
            userId: "uid-alice",
            covenantId: "cov-1",
            status: "active",
            source: "stripe_subscription",
        });
    });

    test("customer.subscription.updated updates existing member index", async () => {
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ status: "active", role: "member" }),
            exists: true,
        });
        await handleStripeEvent(
            makeSubscriptionEvent("customer.subscription.updated"),
            makeDb(),
            mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
        );
        expect(mockDoc.set).toHaveBeenCalledTimes(1);
    });

    test("customer.subscription.deleted marks member cancelled", async () => {
        await handleStripeEvent(
            makeSubscriptionEvent("customer.subscription.deleted", { status: "canceled" as Stripe.Subscription.Status }),
            makeDb(),
            mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
        );
        expect(mockDoc.set).toHaveBeenCalledTimes(1);
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.status).toBe("cancelled");
    });

    test("checkout.session.completed retrieves subscription and writes index", async () => {
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await handleStripeEvent(
            makeCheckoutSessionEvent(),
            makeDb(),
            mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
        );
        expect(mockStripeSubscriptions.retrieve).toHaveBeenCalledWith("sub_123");
        expect(mockDoc.set).toHaveBeenCalledTimes(1);
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.userId).toBe("uid-alice");
        expect(data.covenantId).toBe("cov-1");
    });

    test("missing covenantId in metadata — skips write without throwing", async () => {
        await expect(
            handleStripeEvent(
                makeSubscriptionEvent("customer.subscription.created", { metadata: { userId: "uid-alice" } }),
                makeDb(),
                mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
            )
        ).resolves.toBeUndefined();
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("missing userId in metadata — skips write without throwing", async () => {
        await expect(
            handleStripeEvent(
                makeSubscriptionEvent("customer.subscription.created", { metadata: { covenantId: "cov-1" } }),
                makeDb(),
                mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
            )
        ).resolves.toBeUndefined();
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("empty metadata — skips write without throwing", async () => {
        await expect(
            handleStripeEvent(
                makeSubscriptionEvent("customer.subscription.created", { metadata: {} }),
                makeDb(),
                mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
            )
        ).resolves.toBeUndefined();
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("unhandled event type — resolves cleanly without writing", async () => {
        const unknownEvent = { type: "payment_intent.succeeded", data: { object: {} } } as Stripe.Event;
        await expect(
            handleStripeEvent(unknownEvent, makeDb(), mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">)
        ).resolves.toBeUndefined();
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("checkout session with non-subscription mode is skipped", async () => {
        await handleStripeEvent(
            makeCheckoutSessionEvent({ mode: "payment" }),
            makeDb(),
            mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
        );
        expect(mockStripeSubscriptions.retrieve).not.toHaveBeenCalled();
        expect(mockDoc.set).not.toHaveBeenCalled();
    });

    test("canceled subscription in subscription.updated does not grant access", async () => {
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ status: "active", role: "member" }),
            exists: true,
        });
        await handleStripeEvent(
            makeSubscriptionEvent("customer.subscription.updated", { status: "canceled" as Stripe.Subscription.Status }),
            makeDb(),
            mockStripeSubscriptions as unknown as Pick<Stripe, "subscriptions">
        );
        const [, data] = mockDoc.set.mock.calls[0] as [unknown, Record<string, unknown>];
        expect(data.status).toBe("cancelled");
        expect(data.activatedAt).toBeUndefined();
    });
});
