/**
 * verification.test.ts
 *
 * Unit tests for the Amen Verification & Trust System Cloud Functions.
 * Mocks firebase-admin and firebase-functions — no network calls.
 *
 * Pattern: functions.https.onCall mock returns the handler directly,
 * so exported callables are called as fn(data, context).
 */

import * as admin from "firebase-admin";

// ─── The module under test ────────────────────────────────────────────────────
// Imported after mock setup so the module-level db/auth references pick up mocks
import {
    startIdentityVerification,
    requestOrganizationVerification,
    requestRoleVerification,
    approveRoleVerification,
    revokeRoleVerification,
    requestCreatorVerification,
    reportImpersonation,
    refreshVerificationSummary,
} from "./index";

// Also import riskEngine for direct unit tests
import { calculateRiskScore } from "./riskEngine";

// ─── Mock plumbing ────────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockDoc = mockAdmin.__mockDoc as {
    get: jest.Mock;
    set: jest.Mock;
    update: jest.Mock;
    collection: jest.Mock;
    id: string;
    __data: unknown;
};
const mockQuery = mockAdmin.__mockQuery as {
    get: jest.Mock;
    where: jest.Mock;
    orderBy: jest.Mock;
    limit: jest.Mock;
};
const mockGetUser = mockAdmin.__mockGetUser as jest.Mock;
const mockBatch = mockAdmin.__mockBatch as {
    set: jest.Mock;
    update: jest.Mock;
    delete: jest.Mock;
    commit: jest.Mock;
};

// ─── Context builders ─────────────────────────────────────────────────────────

interface ContextOptions {
    auth?: boolean;
    app?: boolean;
    uid?: string;
    isAdmin?: boolean;
}

function makeContext(options: ContextOptions = {}) {
    const uid = options.uid ?? "caller-uid";
    return {
        auth:
            options.auth === false
                ? undefined
                : {
                      uid,
                      token: {
                          uid,
                          admin: options.isAdmin === true,
                          get: (key: string, def: unknown) =>
                              key === "admin" ? options.isAdmin === true : def,
                      },
                  },
        app: options.app === false ? undefined : { appId: "test-app" },
    };
}

type V1Handler = (data: unknown, context: ReturnType<typeof makeContext>) => Promise<unknown>;

function invoke(callable: unknown, data: unknown, options: ContextOptions = {}): Promise<unknown> {
    return (callable as V1Handler)(data, makeContext(options));
}

// ─── Webhook helper ───────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-var-requires
const crypto = require("crypto");

function makeWebhookReqRes(body: Record<string, unknown>, options: { validSig?: boolean } = {}) {
    const secret = "test-webhook-secret";
    process.env.WEBHOOK_SECRET = secret;

    const sig = options.validSig === false
        ? "bad-signature"
        : crypto.createHmac("sha256", secret).update(JSON.stringify(body)).digest("hex");

    const req = {
        headers: { "x-amen-webhook-signature": sig },
        body,
    };
    const res = {
        statusCode: 0,
        body: "",
        status(code: number) { this.statusCode = code; return this; },
        send(b: string) { this.body = b; return this; },
    };
    return { req, res };
}

// ─── Setup / teardown ─────────────────────────────────────────────────────────

// Use MockKYCProvider in all tests — prevents real HTTP calls to Persona/Stripe
beforeAll(() => {
    process.env.KYC_PROVIDER = "mock";
    process.env.WEBHOOK_SECRET = "test-webhook-secret";
});

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;
    mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });
    mockDoc.set.mockResolvedValue(undefined);
    mockDoc.update.mockResolvedValue(undefined);
    mockDoc.collection.mockReturnValue({
        doc: jest.fn(() => mockDoc),
        add: jest.fn(() => Promise.resolve({ id: "mock-request-id" })),
        where: jest.fn(() => mockQuery),
        orderBy: jest.fn(() => mockQuery),
        limit: jest.fn(() => mockQuery),
        get: jest.fn(() => Promise.resolve({ docs: [], empty: true, size: 0 })),
    });
    mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });
    mockQuery.where.mockReturnValue(mockQuery);
    mockQuery.orderBy.mockReturnValue(mockQuery);
    mockQuery.limit.mockReturnValue(mockQuery);
    mockBatch.set.mockClear();
    mockBatch.update.mockClear();
    mockBatch.commit.mockResolvedValue(undefined);
    mockGetUser.mockResolvedValue({ emailVerified: true });

    // Default: runTransaction calls handler with a basic tx mock
    // (already wired in firebase-admin mock)
});

// =============================================================================
// Auth guards
// =============================================================================

describe("Auth guards — unauthenticated caller", () => {
    it("startIdentityVerification throws unauthenticated when no auth", async () => {
        await expect(invoke(startIdentityVerification, {}, { auth: false }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    it("approveRoleVerification throws unauthenticated when no auth", async () => {
        await expect(
            invoke(approveRoleVerification, {}, { auth: false })
        ).rejects.toMatchObject({ code: "unauthenticated" });
    });

    it("reportImpersonation throws unauthenticated when no auth", async () => {
        await expect(invoke(reportImpersonation, {}, { auth: false }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });
});

// =============================================================================
// App Check
// =============================================================================

describe("App Check enforcement", () => {
    it("startIdentityVerification throws failed-precondition when app == undefined", async () => {
        await expect(invoke(startIdentityVerification, {}, { app: false }))
            .rejects.toMatchObject({ code: "failed-precondition" });
    });

    it("requestRoleVerification throws failed-precondition when app == undefined", async () => {
        await expect(
            invoke(requestRoleVerification, { orgId: "org-1", role: "Pastor", scope: "full" }, { app: false })
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    it("reportImpersonation throws failed-precondition when app == undefined", async () => {
        await expect(
            invoke(reportImpersonation, { targetUid: "other-uid", reason: "Fake account" }, { app: false })
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });
});

// =============================================================================
// Input validation
// =============================================================================

describe("Input validation", () => {
    it("requestRoleVerification throws invalid-argument for unrecognised role", async () => {
        await expect(
            invoke(requestRoleVerification, {
                orgId: "org-1",
                role: "Supreme Overlord",
                scope: "full",
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("requestRoleVerification throws invalid-argument for empty role", async () => {
        await expect(
            invoke(requestRoleVerification, {
                orgId: "org-1",
                role: "",
                scope: "full",
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("reportImpersonation throws invalid-argument for empty reason", async () => {
        await expect(
            invoke(reportImpersonation, {
                targetUid: "other-uid",
                reason: "",
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("reportImpersonation throws invalid-argument when targetUid equals callerUid", async () => {
        await expect(
            invoke(reportImpersonation, {
                targetUid: "caller-uid",
                reason: "Testing self-report",
            }, { uid: "caller-uid" })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("reportImpersonation throws invalid-argument when reason exceeds 500 characters", async () => {
        await expect(
            invoke(reportImpersonation, {
                targetUid: "other-uid",
                reason: "x".repeat(501),
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("requestOrganizationVerification throws invalid-argument for malformed email", async () => {
        // Make the caller look like an org admin
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({ role: "admin" }),
        });

        await expect(
            invoke(requestOrganizationVerification, {
                orgId: "org-1",
                domainEmail: "not-an-email",
                orgName: "My Church",
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("revokeRoleVerification throws invalid-argument when reason is empty", async () => {
        // Caller is org admin
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({ role: "admin" }),
        });

        await expect(
            invoke(revokeRoleVerification, {
                targetUid: "target-user",
                orgId: "org-1",
                reason: "",
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });
});

// =============================================================================
// Business logic
// =============================================================================

describe("Business logic", () => {
    it("requestCreatorVerification throws failed-precondition when safetyStanding is 'limited'", async () => {
        // User has identity verified but bad safety standing
        let callCount = 0;
        mockDoc.get.mockImplementation(async () => {
            callCount++;
            if (callCount === 1) {
                // Rate limit doc — not exceeded
                return { exists: false, data: () => undefined };
            }
            if (callCount === 2) {
                // users/{uid} doc
                return {
                    exists: true,
                    data: () => ({
                        safetyStanding: "limited",
                        publicVerificationSummary: { safetyStanding: "limited" },
                        moderationActionCount: 0,
                        createdAt: { seconds: Math.floor((Date.now() - 60 * 24 * 60 * 60 * 1000) / 1000) },
                    }),
                };
            }
            // privateVerification/main
            return {
                exists: true,
                data: () => ({ identityVerified: true }),
            };
        });

        // Mock the transaction to not throw on rate limit
        (admin.firestore() as unknown as { runTransaction: jest.Mock }).runTransaction
            .mockImplementation(async (handler: (tx: unknown) => Promise<void>) => {
                await handler({
                    get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }),
                    set: jest.fn(),
                });
            });

        await expect(
            invoke(requestCreatorVerification, {})
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    it("requestCreatorVerification throws failed-precondition when identityVerified is false", async () => {
        let callCount = 0;
        mockDoc.get.mockImplementation(async () => {
            callCount++;
            if (callCount === 1) {
                // Rate limit doc
                return { exists: false, data: () => undefined };
            }
            if (callCount === 2) {
                // users/{uid} doc — account is active and old enough
                return {
                    exists: true,
                    data: () => ({
                        safetyStanding: "active",
                        publicVerificationSummary: { safetyStanding: "active" },
                        moderationActionCount: 0,
                        createdAt: { seconds: Math.floor((Date.now() - 60 * 24 * 60 * 60 * 1000) / 1000) },
                    }),
                };
            }
            // privateVerification/main — identity NOT verified
            return {
                exists: true,
                data: () => ({ identityVerified: false }),
            };
        });

        (admin.firestore() as unknown as { runTransaction: jest.Mock }).runTransaction
            .mockImplementation(async (handler: (tx: unknown) => Promise<void>) => {
                await handler({
                    get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }),
                    set: jest.fn(),
                });
            });

        await expect(
            invoke(requestCreatorVerification, {})
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    it("approveRoleVerification throws permission-denied when caller is not org admin", async () => {
        // Member doc exists but role is "member" not "admin"
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({ role: "member" }),
        });

        await expect(
            invoke(approveRoleVerification, {
                targetUid: "target-user",
                orgId: "org-1",
                role: "Pastor",
                scope: "full",
            })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    it("approveRoleVerification throws permission-denied when member doc does not exist", async () => {
        mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });

        await expect(
            invoke(approveRoleVerification, {
                targetUid: "target-user",
                orgId: "org-1",
                role: "Pastor",
                scope: "full",
            })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    it("revokeRoleVerification throws permission-denied when caller is not org admin", async () => {
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({ role: "member" }),
        });

        await expect(
            invoke(revokeRoleVerification, {
                targetUid: "target-user",
                orgId: "org-1",
                reason: "Violated community guidelines",
            })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    it("requestOrganizationVerification throws permission-denied when caller is not org admin", async () => {
        // Member doc does not exist and user doc has no adminOfOrgs
        mockDoc.get.mockResolvedValue({ exists: false, data: () => undefined });

        await expect(
            invoke(requestOrganizationVerification, {
                orgId: "org-1",
                domainEmail: "admin@mychurch.org",
                orgName: "My Church",
            })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });

    it("refreshVerificationSummary throws permission-denied when non-admin requests another user's summary", async () => {
        await expect(
            invoke(refreshVerificationSummary, { targetUid: "some-other-uid" }, { uid: "caller-uid", isAdmin: false })
        ).rejects.toMatchObject({ code: "permission-denied" });
    });
});

// =============================================================================
// Webhook security
// =============================================================================

describe("Webhook security", () => {
    it("handleIdentityVerificationWebhook returns 401 for invalid signature", async () => {
        // Import the webhook handler directly (it's an onRequest, not onCall)
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const { handleIdentityVerificationWebhook } = require("./index");

        const body = { event: "approved", uid: "uid-1", requestId: "req-1", providerReferenceId: "ref-1" };
        const { req, res } = makeWebhookReqRes(body, { validSig: false });

        await handleIdentityVerificationWebhook(req, res);

        expect(res.statusCode).toBe(401);
        expect(res.body).toBe("Invalid signature");
    });

    it("handleIdentityVerificationWebhook processes approved event and updates identityVerified = true", async () => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const { handleIdentityVerificationWebhook } = require("./index");

        const body = {
            event: "approved",
            uid: "uid-1",
            requestId: "req-1",
            providerReferenceId: "prov-ref-123",
            verificationLevel: "basic",
            country: "US",
            riskScore: 0.1,
            expiresAt: Date.now() + 365 * 24 * 60 * 60 * 1000,
            sessionToken: "some-token",
        };

        const { req, res } = makeWebhookReqRes(body, { validSig: true });

        // Request doc exists and has no prior providerReferenceId
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                type: "identity",
                status: "pending",
                // no providerReferenceId yet
            }),
        });

        // users/{uid} doc for publicVerificationSummary update
        mockDoc.update.mockResolvedValue(undefined);

        await handleIdentityVerificationWebhook(req, res);

        expect(res.statusCode).toBe(200);
        expect(res.body).toBe("OK");

        // Audit log was written
        expect(mockDoc.set).toHaveBeenCalled();
    });

    it("handleIdentityVerificationWebhook is idempotent on duplicate providerReferenceId", async () => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const { handleIdentityVerificationWebhook } = require("./index");

        const providerReferenceId = "prov-ref-duplicate";
        const body = {
            event: "approved",
            uid: "uid-1",
            requestId: "req-1",
            providerReferenceId,
            verificationLevel: "basic",
            country: "US",
            riskScore: 0.1,
            expiresAt: Date.now() + 365 * 24 * 60 * 60 * 1000,
            sessionToken: "some-token",
        };

        const { req, res } = makeWebhookReqRes(body, { validSig: true });

        // Simulate the request doc already having this providerReferenceId (already processed)
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                type: "identity",
                status: "approved",
                providerReferenceId, // already set — duplicate
            }),
        });

        await handleIdentityVerificationWebhook(req, res);

        expect(res.statusCode).toBe(200);
        expect(res.body).toBe("OK");

        // No state mutation should have occurred
        expect(mockDoc.update).not.toHaveBeenCalled();
    });
});

// =============================================================================
// Risk engine unit tests
// =============================================================================

describe("calculateRiskScore — risk engine", () => {
    it("returns 'low' for a clean account with no signals", async () => {
        const now = Date.now();
        // User doc: old account, no concerning fields
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: true,
                moderationActionCount: 0,
                createdAt: { seconds: Math.floor((now - 90 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });

        // Email verified in Auth
        mockGetUser.mockResolvedValue({ emailVerified: true });

        // No open impersonation reports
        mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

        const result = await calculateRiskScore("clean-uid");

        expect(result.level).toBe("low");
        expect(result.score).toBeGreaterThanOrEqual(0);
        expect(result.score).toBeLessThanOrEqual(2);
    });

    it("returns 'high' for account with > 3 moderation actions combined with other signals", async () => {
        const now = Date.now();
        // moderationActionCount > 3 = SCORE_HIGH (3 pts)
        // email not verified = SCORE_MEDIUM (2 pts)
        // phone not verified = SCORE_LOW (1 pt)
        // Total = 6 pts → "high"
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: false,     // +1
                moderationActionCount: 5, // +3
                createdAt: { seconds: Math.floor((now - 90 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });

        mockGetUser.mockResolvedValue({ emailVerified: false }); // +2
        mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

        const result = await calculateRiskScore("moderated-uid");

        expect(result.level).toBe("high");
        expect(result.signals).toContain("prior_moderation_actions_severe");
        expect(result.score).toBeGreaterThanOrEqual(6);
    });

    it("returns 'blocked' for account with > 5 verification requests in past 7 days", async () => {
        const now = Date.now();
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: true,
                moderationActionCount: 0,
                createdAt: { seconds: Math.floor((now - 90 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });

        mockGetUser.mockResolvedValue({ emailVerified: true });

        // First query = impersonation reports (empty)
        // Second query = verification requests (6 recent = > 5)
        let queryCallCount = 0;
        mockQuery.get.mockImplementation(async () => {
            queryCallCount++;
            if (queryCallCount === 1) {
                // impersonationReports — none
                return { docs: [], empty: true, size: 0 };
            }
            // verificationRequests — 6 recent
            return {
                docs: Array(6).fill({ id: "req", data: () => ({}) }),
                empty: false,
                size: 6,
            };
        });

        const result = await calculateRiskScore("spammy-uid");

        expect(result.level).toBe("blocked");
        expect(result.signals).toContain("unusual_request_volume");
    });

    it("includes email_not_verified signal for unverified accounts", async () => {
        const now = Date.now();
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: true,
                moderationActionCount: 0,
                createdAt: { seconds: Math.floor((now - 90 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });

        mockGetUser.mockResolvedValue({ emailVerified: false });
        mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

        const result = await calculateRiskScore("unverified-email-uid");

        expect(result.signals).toContain("email_not_verified");
    });

    it("includes account_age_very_new signal for accounts under 7 days old", async () => {
        const now = Date.now();
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: true,
                moderationActionCount: 0,
                createdAt: { seconds: Math.floor((now - 2 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });

        mockGetUser.mockResolvedValue({ emailVerified: true });
        mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

        const result = await calculateRiskScore("new-account-uid");

        expect(result.signals).toContain("account_age_very_new");
    });

    it("includes open_impersonation_reports signal when open reports exist", async () => {
        const now = Date.now();
        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: true,
                moderationActionCount: 0,
                createdAt: { seconds: Math.floor((now - 90 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });

        mockGetUser.mockResolvedValue({ emailVerified: true });

        let queryCallCount = 0;
        mockQuery.get.mockImplementation(async () => {
            queryCallCount++;
            if (queryCallCount === 1) {
                // impersonationReports — has open reports
                return {
                    docs: [{ id: "report-1", data: () => ({ status: "open" }) }],
                    empty: false,
                    size: 1,
                };
            }
            // verificationRequests — none
            return { docs: [], empty: true, size: 0 };
        });

        const result = await calculateRiskScore("impersonated-uid");

        expect(result.signals).toContain("open_impersonation_reports");
    });
});

// =============================================================================
// Security invariants (static checks)
// =============================================================================

describe("Security invariants", () => {
    it("startIdentityVerification does not return raw sessionToken in Firestore write", async () => {
        // The set call should NOT contain sessionToken — only sessionTokenHash
        (admin.firestore() as unknown as { runTransaction: jest.Mock }).runTransaction
            .mockImplementation(async (handler: (tx: unknown) => Promise<void>) => {
                await handler({
                    get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }),
                    set: jest.fn(),
                });
            });

        mockDoc.get.mockResolvedValue({
            exists: true,
            data: () => ({
                phoneVerified: true,
                moderationActionCount: 0,
                createdAt: { seconds: Math.floor((Date.now() - 90 * 24 * 60 * 60 * 1000) / 1000) },
            }),
        });
        mockGetUser.mockResolvedValue({ emailVerified: true });
        mockQuery.get.mockResolvedValue({ docs: [], empty: true, size: 0 });

        await invoke(startIdentityVerification, {});

        // For each call to mockDoc.set, verify sessionToken (raw) is not stored
        mockDoc.set.mock.calls.forEach((call: unknown[]) => {
            const payload = call[0] as Record<string, unknown>;
            expect(payload).not.toHaveProperty("sessionToken");
            // Hash should be present instead
            if (payload.type === "identity") {
                expect(payload).toHaveProperty("sessionTokenHash");
            }
        });
    });

    it("reportImpersonation stores reporterUid in the document (server-side only)", async () => {
        (admin.firestore() as unknown as { runTransaction: jest.Mock }).runTransaction
            .mockImplementation(async (handler: (tx: unknown) => Promise<void>) => {
                await handler({
                    get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }),
                    set: jest.fn(),
                });
            });

        await invoke(reportImpersonation, {
            targetUid: "target-uid",
            reason: "This account is impersonating me",
        }, { uid: "reporter-uid" });

        const setCall = mockBatch.set.mock.calls.find((call: unknown[]) => {
            const payload = call[1] as Record<string, unknown>;
            return payload && payload.type !== "impersonation_report" && payload.reporterUid !== undefined;
        });

        // reporterUid should be written to the document by the server
        const anySetWithReporter = mockBatch.set.mock.calls.some((call: unknown[]) => {
            const payload = call[1] as Record<string, unknown>;
            return payload && payload.reporterUid === "reporter-uid";
        });
        expect(anySetWithReporter).toBe(true);
        void setCall; // suppress unused variable warning
    });
});
