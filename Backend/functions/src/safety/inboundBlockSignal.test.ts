/**
 * inboundBlockSignal.test.ts — unit tests for the "blocked by multiple people"
 * advisory signal (T&S Remediation item 21 follow-on).
 *
 * Pins the privacy + safety contracts:
 *   - Ships dark: with the flag OFF the callable returns enabled:false and never
 *     touches Firestore.
 *   - Returns ONLY a coarse bucket — never the raw count or blocker identities.
 *   - Bucketing crosses to "elevated" exactly at the threshold.
 *   - Self-target and unauthenticated callers get no warning.
 *   - Fail-OPEN: a count failure yields no warning (advisory, never a gate).
 */

const mockCountGet = jest.fn();
const mockCount = jest.fn(() => ({ get: mockCountGet }));
const mockWhere = jest.fn(() => ({ count: mockCount }));
const mockCollection = jest.fn(() => ({ where: mockWhere }));

jest.mock("firebase-admin", () => ({
    firestore: jest.fn(() => ({ collection: mockCollection })),
}));

jest.mock("firebase-functions/v2/https", () => {
    class HttpsError extends Error {
        code: string;
        constructor(code: string, message: string) {
            super(message);
            this.code = code;
        }
    }
    return {
        HttpsError,
        onCall: jest.fn((options: unknown, handler: unknown) => ({ options, run: handler })),
    };
});

type Mod = typeof import("./inboundBlockSignal");
type Callable = { options: { enforceAppCheck?: boolean }; run: (r: Record<string, unknown>) => Promise<unknown> };

function load(enabled: boolean, threshold?: number): Mod {
    jest.resetModules();
    if (enabled) process.env.INBOUND_BLOCK_WARNING_ENABLED = "true";
    else delete process.env.INBOUND_BLOCK_WARNING_ENABLED;
    if (threshold != null) process.env.INBOUND_BLOCK_WARNING_THRESHOLD = String(threshold);
    else delete process.env.INBOUND_BLOCK_WARNING_THRESHOLD;
    let mod: Mod | undefined;
    jest.isolateModules(() => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        mod = require("./inboundBlockSignal");
    });
    return mod as Mod;
}

function countResolves(n: number) {
    mockCountGet.mockResolvedValue({ data: () => ({ count: n }) });
}

beforeEach(() => {
    jest.clearAllMocks();
    countResolves(0);
});

describe("bucketInboundBlocks", () => {
    it("is 'none' below threshold and 'elevated' at/above it", () => {
        const { bucketInboundBlocks } = load(true, 3);
        expect(bucketInboundBlocks(0, 3)).toBe("none");
        expect(bucketInboundBlocks(2, 3)).toBe("none");
        expect(bucketInboundBlocks(3, 3)).toBe("elevated");
        expect(bucketInboundBlocks(9, 3)).toBe("elevated");
    });
});

describe("evaluateInboundBlockSignal", () => {
    it("returns elevated + shouldWarn at the threshold", async () => {
        const mod = load(true, 3);
        countResolves(4);
        const sig = await mod.evaluateInboundBlockSignal("target-1");
        expect(sig.signal).toBe("elevated");
        expect(sig.shouldWarn).toBe(true);
        expect(mockWhere).toHaveBeenCalledWith("blockedId", "==", "target-1");
    });

    it("returns none below the threshold", async () => {
        const mod = load(true, 3);
        countResolves(2);
        const sig = await mod.evaluateInboundBlockSignal("target-2");
        expect(sig.signal).toBe("none");
        expect(sig.shouldWarn).toBe(false);
    });

    it("fails OPEN (no warning) when the count query throws", async () => {
        const mod = load(true, 3);
        mockCountGet.mockRejectedValue(new Error("aggregation unavailable"));
        const sig = await mod.evaluateInboundBlockSignal("target-3");
        expect(sig.shouldWarn).toBe(false);
        expect(sig.signal).toBe("none");
        expect(sig.enabled).toBe(true);
    });
});

describe("getInboundBlockSignal callable", () => {
    it("enforces App Check", () => {
        const mod = load(true);
        const callable = mod.getInboundBlockSignal as unknown as Callable;
        expect(callable.options.enforceAppCheck).toBe(true);
    });

    it("ships dark: with the flag OFF it returns enabled:false and never queries", async () => {
        const mod = load(false);
        const callable = mod.getInboundBlockSignal as unknown as Callable;
        const result = (await callable.run({
            auth: { uid: "caller-1" },
            data: { targetUid: "target-1" },
        })) as Record<string, unknown>;
        expect(result.enabled).toBe(false);
        expect(result.shouldWarn).toBe(false);
        expect(mockCollection).not.toHaveBeenCalled();
    });

    it("rejects unauthenticated callers", async () => {
        const mod = load(true);
        const callable = mod.getInboundBlockSignal as unknown as Callable;
        await expect(callable.run({ data: { targetUid: "t" } })).rejects.toMatchObject({
            code: "unauthenticated",
        });
    });

    it("requires a targetUid when enabled", async () => {
        const mod = load(true);
        const callable = mod.getInboundBlockSignal as unknown as Callable;
        await expect(
            callable.run({ auth: { uid: "caller-1" }, data: {} })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    it("never warns on a self-target and never queries for it", async () => {
        const mod = load(true);
        const callable = mod.getInboundBlockSignal as unknown as Callable;
        const result = (await callable.run({
            auth: { uid: "me" },
            data: { targetUid: "me" },
        })) as Record<string, unknown>;
        expect(result.shouldWarn).toBe(false);
        expect(mockCollection).not.toHaveBeenCalled();
    });

    it("returns only a coarse bucket — no raw count or identities leak", async () => {
        const mod = load(true, 3);
        countResolves(11);
        const callable = mod.getInboundBlockSignal as unknown as Callable;
        const result = (await callable.run({
            auth: { uid: "caller-1" },
            data: { targetUid: "target-9" },
        })) as Record<string, unknown>;

        expect(result).toEqual({
            enabled: true,
            signal: "elevated",
            shouldWarn: true,
            threshold: 3,
        });
        // No field carries the raw count (11) or any blocker UID.
        expect(JSON.stringify(result)).not.toContain("11");
    });
});
