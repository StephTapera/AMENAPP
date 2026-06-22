import {
    evaluatePostSafety,
    validateCovenantPostSafetyHandler,
} from "./validateCovenantPostSafety";
import admin from "firebase-admin";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockDoc: jest.Mocked<{
    get: jest.Mock;
    set: jest.Mock;
}> = mockAdmin.__mockDoc;

beforeEach(() => {
    jest.clearAllMocks();
    // Default rate-limit window: empty (count=0).
    mockDoc.get.mockResolvedValue({ data: () => null, exists: false });
    mockDoc.set.mockResolvedValue(undefined);
});

describe("evaluatePostSafety (P1-5)", () => {
    test("safe content is allowed", () => {
        const r = evaluatePostSafety("Reflecting on Psalm 23 this morning, what a gift.");
        expect(r.allowed).toBe(true);
        expect(r.severity).toBe("safe");
        expect(r.categories).toEqual([]);
    });

    test("empty string is blocked", () => {
        const r = evaluatePostSafety("   ");
        expect(r.allowed).toBe(false);
        expect(r.severity).toBe("block");
        expect(r.categories).toContain("empty");
    });

    test("oversized text is blocked", () => {
        const r = evaluatePostSafety("a".repeat(25_000));
        expect(r.allowed).toBe(false);
        expect(r.severity).toBe("block");
        expect(r.categories).toContain("too_long");
    });

    test("financial manipulation pattern is blocked", () => {
        const r = evaluatePostSafety(
            "God told me you need to give. Sow $300 today to unlock your blessing."
        );
        expect(r.allowed).toBe(false);
        expect(r.severity).toBe("block");
        expect(r.categories).toContain("financial_manipulation");
    });

    test("hate slur is blocked", () => {
        // Use the obfuscated form the regex still catches.
        const r = evaluatePostSafety("you f4ggot");
        expect(r.allowed).toBe(false);
        expect(r.severity).toBe("block");
        expect(r.categories).toContain("hate_speech");
    });

    test("all-caps long message gets warn (still publishable)", () => {
        const r = evaluatePostSafety(
            "THIS IS A LONG MESSAGE TYPED ENTIRELY IN UPPERCASE TO TRIGGER THE SHOUT WARNING."
        );
        expect(r.allowed).toBe(true);
        expect(r.severity).toBe("warn");
        expect(r.categories).toContain("all_caps");
    });

    test("excess punctuation gets warn", () => {
        const r = evaluatePostSafety("Is this really happening?????");
        expect(r.allowed).toBe(true);
        expect(r.severity).toBe("warn");
        expect(r.categories).toContain("excess_punctuation");
    });

    test("link density gets warn", () => {
        const r = evaluatePostSafety("https://a.com https://b.com https://c.com https://d.com");
        expect(r.allowed).toBe(true);
        expect(r.severity).toBe("warn");
        expect(r.categories).toContain("link_density");
    });
});

describe("validateCovenantPostSafetyHandler — auth/app-check (P1-5)", () => {
    test("rejects unauthenticated caller", async () => {
        await expect(
            validateCovenantPostSafetyHandler(null, true, { text: "hi" })
        ).rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("rejects missing App Check", async () => {
        await expect(
            validateCovenantPostSafetyHandler("uid-alice", false, { text: "hi" })
        ).rejects.toMatchObject({ code: "failed-precondition" });
    });

    test("rejects missing/empty text", async () => {
        await expect(
            validateCovenantPostSafetyHandler("uid-alice", true, { text: "" })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects oversized text at the boundary", async () => {
        await expect(
            validateCovenantPostSafetyHandler("uid-alice", true, { text: "a".repeat(25_000) })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("rejects invalid kind", async () => {
        await expect(
            validateCovenantPostSafetyHandler("uid-alice", true, {
                text: "ok",
                kind: "tweet" as never,
            })
        ).rejects.toMatchObject({ code: "invalid-argument" });
    });

    test("safe post passes through", async () => {
        const r = await validateCovenantPostSafetyHandler("uid-alice", true, {
            text: "Reflecting on Romans 8 this morning.",
        });
        expect(r.allowed).toBe(true);
        expect(r.severity).toBe("safe");
    });

    test("blocked post returns allowed:false", async () => {
        const r = await validateCovenantPostSafetyHandler("uid-alice", true, {
            text: "Sow $500 today to unlock your blessing",
        });
        expect(r.allowed).toBe(false);
        expect(r.severity).toBe("block");
        expect(r.categories).toContain("financial_manipulation");
    });
});
