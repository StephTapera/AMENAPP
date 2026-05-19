import admin from "firebase-admin";
import { setCommunitySavedHandler } from "./setCommunitySaved";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockDoc: jest.Mocked<{
    get: jest.Mock;
    set: jest.Mock;
    delete: jest.Mock;
    update: jest.Mock;
}> = mockAdmin.__mockDoc;

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.get.mockResolvedValue({ data: () => null, exists: false });
    mockDoc.set.mockResolvedValue(undefined);
    mockDoc.delete.mockResolvedValue(undefined);
});

function db() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return admin.firestore() as any;
}

// The rate-limit util also calls mockDoc.set under the same mock instance.
// Filter set calls to those that look like a savedCommunities write so
// assertions are not polluted by rate-limit window increments.
function savedSetCalls(): Array<Record<string, unknown>> {
    return (mockDoc.set.mock.calls as Array<[Record<string, unknown>, unknown?]>)
        .map(([payload]) => payload)
        .filter((p) => p && typeof p === "object"
            && "communityType" in p
            && "communityId" in p);
}

// Helper: prime rate-limit window reads so they fall through (count=0).
// rateLimit.enforceRateLimit issues TWO Promise.all transactions, each doing
// one tx.get(ref). With the default mock returning {exists:false,data:()=>null}
// this is already a "count=0" view, but we explicitly queue them to keep test
// intent obvious and to avoid the visibility-doc prime being consumed by a
// rate-limit get.
function primeRateLimitWindows(): void {
    mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
    mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
}

describe("setCommunitySavedHandler (P1-Phase-F)", () => {
    test("rejects unauthenticated caller", async () => {
        await expect(
            setCommunitySavedHandler(null, true, {
                communityType: "covenant",
                communityId: "cov-1",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing App Check", async () => {
        await expect(
            setCommunitySavedHandler("uid-alice", false, {
                communityType: "covenant",
                communityId: "cov-1",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    test("rejects unknown communityType", async () => {
        await expect(
            setCommunitySavedHandler("uid-alice", true, {
                communityType: "discord" as never,
                communityId: "cov-1",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects empty communityId", async () => {
        await expect(
            setCommunitySavedHandler("uid-alice", true, {
                communityType: "covenant",
                communityId: "   ",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects when community does not exist", async () => {
        primeRateLimitWindows();
        // visibility check sees exists:false
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await expect(
            setCommunitySavedHandler("uid-alice", true, {
                communityType: "covenant",
                communityId: "missing",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "not-found" });
        // No savedCommunities write occurred (rate-limit writes are filtered).
        expect(savedSetCalls()).toHaveLength(0);
    });

    test("saves a public covenant successfully", async () => {
        primeRateLimitWindows();
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ title: "Test Cov", isPublic: true }),
            exists: true,
        });
        const result = await setCommunitySavedHandler("uid-alice", true, {
            communityType: "covenant",
            communityId: "cov-1",
            saved: true,
        }, db());
        expect(result.saved).toBe(true);
        expect(result.communityKey).toBe("covenant_cov-1");
        const saved = savedSetCalls();
        expect(saved).toHaveLength(1);
        expect(saved[0]).toMatchObject({
            communityId: "cov-1",
            communityType: "covenant",
            saved: true,
            visibilitySnapshot: "public",
        });
    });

    test("rejects saving a private covenant the caller is not a member of", async () => {
        primeRateLimitWindows();
        // First get: covenant doc itself with isPublic:false
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ title: "Private Cov", isPublic: false }),
            exists: true,
        });
        // Second get: member doc — does not exist
        mockDoc.get.mockResolvedValueOnce({ data: () => null, exists: false });
        await expect(
            setCommunitySavedHandler("uid-alice", true, {
                communityType: "covenant",
                communityId: "cov-private",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "not-found" });
        expect(savedSetCalls()).toHaveLength(0);
    });

    test("unsave is idempotent — deletes the saved doc", async () => {
        primeRateLimitWindows();
        // visibility check resolves visible
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ title: "Test Cov", isPublic: true }),
            exists: true,
        });
        const result = await setCommunitySavedHandler("uid-alice", true, {
            communityType: "covenant",
            communityId: "cov-1",
            saved: false,
        }, db());
        expect(result.saved).toBe(false);
        expect(mockDoc.delete).toHaveBeenCalledTimes(1);
    });

    test("public hub is saveable; private hub is not", async () => {
        // Public hub
        primeRateLimitWindows();
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ title: "Hub A", privacyLevel: "public" }),
            exists: true,
        });
        const okPublic = await setCommunitySavedHandler("uid-alice", true, {
            communityType: "hub",
            communityId: "hub-pub",
            saved: true,
        }, db());
        expect(okPublic.saved).toBe(true);

        // Private hub
        primeRateLimitWindows();
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ title: "Hub B", privacyLevel: "private" }),
            exists: true,
        });
        await expect(
            setCommunitySavedHandler("uid-alice", true, {
                communityType: "hub",
                communityId: "hub-priv",
                saved: true,
            }, db())
        ).rejects.toMatchObject({ code: "not-found" });
    });

    test("composite saved key uses type prefix to avoid id collisions", async () => {
        primeRateLimitWindows();
        mockDoc.get.mockResolvedValueOnce({
            data: () => ({ title: "Hub C", privacyLevel: "public" }),
            exists: true,
        });
        const r = await setCommunitySavedHandler("uid-alice", true, {
            communityType: "hub",
            communityId: "hub-1",
            saved: true,
        }, db());
        expect(r.communityKey).toBe("hub_hub-1");
    });
});
