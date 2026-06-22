import {
    classifyCustomer,
    runBackfill,
    emptySummary,
    ExistingMapping,
} from "./backfillStripeCustomerMapping";

describe("classifyCustomer (P1-1 backfill)", () => {
    test("no metadata.uid → skip-no-uid", () => {
        expect(classifyCustomer({ id: "cus_a", metadata: {} }, null)).toBe("skip-no-uid");
        expect(classifyCustomer({ id: "cus_a", metadata: null }, null)).toBe("skip-no-uid");
        expect(classifyCustomer({ id: "cus_a" }, null)).toBe("skip-no-uid");
    });

    test("metadata.uid present + no existing mapping → create", () => {
        expect(classifyCustomer({ id: "cus_a", metadata: { uid: "u1" } }, null)).toBe("create");
    });

    test("metadata.uid present + matching mapping → skip-existing-match (idempotent)", () => {
        const existing: ExistingMapping = { uid: "u1", provider: "stripe" };
        expect(classifyCustomer({ id: "cus_a", metadata: { uid: "u1" } }, existing)).toBe("skip-existing-match");
    });

    test("metadata.uid present + conflicting mapping → skip-existing-conflict (never overwrite)", () => {
        const existing: ExistingMapping = { uid: "u-other", provider: "stripe" };
        expect(classifyCustomer({ id: "cus_a", metadata: { uid: "u1" } }, existing)).toBe("skip-existing-conflict");
    });

    test("whitespace-only metadata.uid → skip-no-uid", () => {
        expect(classifyCustomer({ id: "cus_a", metadata: { uid: "   " } }, null)).toBe("skip-no-uid");
    });
});

describe("runBackfill (P1-1)", () => {
    async function* customers(items: Array<{ id: string; metadata?: Record<string, string> }>) {
        for (const c of items) yield c;
    }

    test("dry-run does not write but counts would-creates", async () => {
        const reads: string[] = [];
        const writes: string[] = [];
        const summary = await runBackfill({
            customers: customers([
                { id: "cus_a", metadata: { uid: "u1" } },
                { id: "cus_b", metadata: { uid: "u2" } },
            ]),
            readMapping: async (id) => { reads.push(id); return null; },
            writeMapping: async (id) => { writes.push(id); },
            dryRun: true,
        });
        expect(summary.scanned).toBe(2);
        expect(summary.created).toBe(2);
        expect(writes).toHaveLength(0);     // no writes in dry-run
        expect(reads).toEqual(["cus_a", "cus_b"]);
        expect(summary.dryRun).toBe(true);
    });

    test("creates mappings only where missing", async () => {
        const writes: Array<[string, string]> = [];
        const summary = await runBackfill({
            customers: customers([
                { id: "cus_new", metadata: { uid: "u1" } },
                { id: "cus_existing", metadata: { uid: "u2" } },
                { id: "cus_no_uid", metadata: {} },
            ]),
            readMapping: async (id) => id === "cus_existing"
                ? { uid: "u2", provider: "stripe" }
                : null,
            writeMapping: async (id, uid) => { writes.push([id, uid]); },
            dryRun: false,
        });
        expect(summary.scanned).toBe(3);
        expect(summary.created).toBe(1);
        expect(summary.skippedExistingMatch).toBe(1);
        expect(summary.skippedNoUid).toBe(1);
        expect(writes).toEqual([["cus_new", "u1"]]);
    });

    test("conflict is not overwritten — logged and skipped", async () => {
        const writes: string[] = [];
        const logs: Array<{ message: string; extra?: Record<string, unknown> }> = [];
        const summary = await runBackfill({
            customers: customers([
                { id: "cus_conflict", metadata: { uid: "u1" } },
            ]),
            readMapping: async () => ({ uid: "u-different", provider: "stripe" }),
            writeMapping: async (id) => { writes.push(id); },
            dryRun: false,
            log: (message, extra) => logs.push({ message, extra }),
        });
        expect(summary.scanned).toBe(1);
        expect(summary.created).toBe(0);
        expect(summary.skippedExistingConflict).toBe(1);
        expect(writes).toHaveLength(0);
        // The conflict event was logged with both uids so ops can investigate.
        expect(logs.some((l) => l.message === "skip_conflict")).toBe(true);
    });

    test("readMapping error increments errors and continues", async () => {
        const summary = await runBackfill({
            customers: customers([
                { id: "cus_err", metadata: { uid: "u1" } },
                { id: "cus_ok", metadata: { uid: "u2" } },
            ]),
            readMapping: async (id) => {
                if (id === "cus_err") throw new Error("boom");
                return null;
            },
            writeMapping: async () => undefined,
            dryRun: false,
        });
        expect(summary.errors).toBe(1);
        expect(summary.created).toBe(1);
    });

    test("--limit caps scanning", async () => {
        const summary = await runBackfill({
            customers: customers([
                { id: "cus_a", metadata: { uid: "u1" } },
                { id: "cus_b", metadata: { uid: "u2" } },
                { id: "cus_c", metadata: { uid: "u3" } },
            ]),
            readMapping: async () => null,
            writeMapping: async () => undefined,
            dryRun: true,
            limit: 2,
        });
        expect(summary.scanned).toBe(2);
        expect(summary.created).toBe(2);
    });

    test("emptySummary returns the expected zeroed shape", () => {
        const dry = emptySummary(true);
        expect(dry).toEqual({
            scanned: 0,
            created: 0,
            skippedExistingMatch: 0,
            skippedExistingConflict: 0,
            skippedNoUid: 0,
            errors: 0,
            dryRun: true,
        });
    });
});
