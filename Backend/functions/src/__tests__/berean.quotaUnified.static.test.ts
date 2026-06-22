/**
 * berean.quotaUnified.static.test.ts
 *
 * Phase P1-2 — static source assertion that the streaming and
 * non-streaming Berean proxies share a single canonical quota counter.
 *
 * Before this fix, bereanChatProxy.ts wrote `requestCount` and
 * bereanChatProxyStream.ts wrote `streamRequestCount` — a free user
 * could consume up to 2x the intended daily quota by alternating
 * between callable and streaming endpoints.
 *
 * Canonical contract:
 *   - Both proxies write to `aiUsage/{uid}/daily/{yyyyMMdd}`.
 *   - Both proxies read/write the SAME `requestCount` field for the
 *     quota arithmetic.
 *   - `lastStreamRequestAt` may exist as TELEMETRY only — not for
 *     arithmetic. Code must never `?? 0` against it as a counter.
 *
 * This is a static-source test: it reads the proxy files as text and
 * pattern-matches. No Firebase runtime is invoked.
 */

import * as fs from "fs";
import * as path from "path";

const PROXY_FILE = path.resolve(__dirname, "../bereanChatProxy.ts");
const STREAM_FILE = path.resolve(__dirname, "../bereanChatProxyStream.ts");

function read(p: string): string {
    return fs.readFileSync(p, "utf8");
}

describe("Berean unified quota counter (static)", () => {
    test("non-streaming proxy file exists", () => {
        expect(fs.existsSync(PROXY_FILE)).toBe(true);
    });

    test("streaming proxy file exists", () => {
        expect(fs.existsSync(STREAM_FILE)).toBe(true);
    });

    test("non-streaming proxy uses canonical aiUsage/{uid}/daily path", () => {
        const src = read(PROXY_FILE);
        expect(src).toMatch(
            /collection\("aiUsage"\)\.doc\([^)]*\)\.collection\("daily"\)/
        );
    });

    test("streaming proxy uses canonical aiUsage/{uid}/daily path", () => {
        const src = read(STREAM_FILE);
        expect(src).toMatch(
            /collection\("aiUsage"\)\.doc\([^)]*\)\.collection\("daily"\)/
        );
    });

    test("non-streaming proxy reads/writes `requestCount` (not streamRequestCount)", () => {
        const src = read(PROXY_FILE);
        // Must increment requestCount.
        expect(src).toMatch(/requestCount\s*:\s*current\s*\+\s*1/);
        // Must NOT increment a `streamRequestCount` field — that would
        // mean the unification has been undone.
        expect(src).not.toMatch(/streamRequestCount\s*:\s*current/);
    });

    test("streaming proxy reads/writes `requestCount` (not streamRequestCount)", () => {
        const src = read(STREAM_FILE);
        // Must increment requestCount.
        expect(src).toMatch(/requestCount\s*:\s*current\s*\+\s*1/);
        // Must NOT use streamRequestCount for arithmetic. The field
        // name may legally appear inside a comment explaining the
        // history, so we restrict the prohibition to active code.
        const codeLines = src
            .split("\n")
            .filter((line) => !line.trimStart().startsWith("//"));
        const codeOnly = codeLines.join("\n");
        expect(codeOnly).not.toMatch(/streamRequestCount\s*:\s*current/);
        expect(codeOnly).not.toMatch(/data\(\)\?\.streamRequestCount/);
    });

    test("free-tier daily limit matches across both proxies", () => {
        const proxy = read(PROXY_FILE);
        const stream = read(STREAM_FILE);
        // Both proxies must use the same ternary limit shape. The
        // canonical free quota is 15. If either side diverges, the
        // unified counter is meaningless.
        const limitPattern = /tier\s*===\s*"free"\s*\?\s*15\s*:\s*150/;
        expect(proxy).toMatch(limitPattern);
        expect(stream).toMatch(limitPattern);
    });

    test("both proxies open a Firestore transaction for the quota write", () => {
        const proxy = read(PROXY_FILE);
        const stream = read(STREAM_FILE);
        // Atomic increment under contention requires runTransaction.
        // If a future patch swaps this for a non-transactional set(),
        // the race window for free-quota bypass returns.
        expect(proxy).toMatch(/runTransaction\s*\(/);
        expect(stream).toMatch(/runTransaction\s*\(/);
    });
});
