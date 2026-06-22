/**
 * berean.streamingSafety.static.test.ts
 *
 * Phase F — static-source assertions that the streaming Berean proxy
 * never emits provider chunks to the client before they have been:
 *
 *   1. assembled in full (`responseText`),
 *   2. validated via `validateRawTextOutput`, and
 *   3. wrapped with the canonical AI disclosure.
 *
 * A future refactor that re-introduces a `res.write(...)` carrying raw
 * `responseText` deltas — i.e. streaming raw provider output to the
 * client — would silently regress streaming safety. This test locks
 * that invariant in place via whole-file invariants instead of fragile
 * TS block parsing.
 *
 * Pure source-reading test, no Firebase runtime.
 */

import * as fs from "fs";
import * as path from "path";

const STREAM_FILE = path.resolve(__dirname, "../bereanChatProxyStream.ts");

function src(): string {
    return fs.readFileSync(STREAM_FILE, "utf8");
}

describe("Berean streaming safety (static)", () => {
    test("streaming proxy file exists", () => {
        expect(fs.existsSync(STREAM_FILE)).toBe(true);
    });

    test("accumulates provider deltas into responseText", () => {
        // The buffered-then-emit pattern requires a `responseText += text`
        // accumulator. If this disappears, deltas are likely being
        // streamed straight through.
        expect(src()).toMatch(/responseText\s*\+=\s*text/);
    });

    test("validates the assembled response with validateRawTextOutput", () => {
        expect(src()).toMatch(/validateRawTextOutput\s*\(\s*responseText\s*\)/);
    });

    test("applies ensureAIDisclosure before emitting", () => {
        expect(src()).toMatch(/ensureAIDisclosure\s*\(/);
    });

    test("client write uses safeText (validated + disclosed), not raw responseText", () => {
        const code = src();
        // The validated-and-disclosed value must be what the client receives.
        expect(code).toMatch(/delta\s*:\s*safeText/);
        // The raw provider accumulator must NEVER be sent to the client.
        expect(code).not.toMatch(/delta\s*:\s*responseText/);
    });

    test("terminal SSE event advertises aiDisclosureApplied:true", () => {
        expect(src()).toMatch(/aiDisclosureApplied\s*:\s*true/);
    });

    test("terminal SSE event includes a safetyStatus field", () => {
        expect(src()).toMatch(/safetyStatus\s*:/);
    });

    test("crisis short-circuit appears before the Anthropic fetch in source", () => {
        const code = src();
        const crisisIdx = code.indexOf("CRISIS_SAFE_RESPONSE");
        const fetchIdx = code.indexOf("https://api.anthropic.com/v1/messages");
        expect(crisisIdx).toBeGreaterThan(-1);
        expect(fetchIdx).toBeGreaterThan(-1);
        expect(crisisIdx).toBeLessThan(fetchIdx);
    });

    test("App Check token verification precedes the Anthropic fetch", () => {
        const code = src();
        const appCheckIdx = code.indexOf("appCheck().verifyToken");
        const fetchIdx = code.indexOf("https://api.anthropic.com/v1/messages");
        expect(appCheckIdx).toBeGreaterThan(-1);
        expect(appCheckIdx).toBeLessThan(fetchIdx);
    });

    test("quota transaction precedes the Anthropic fetch", () => {
        const code = src();
        const quotaIdx = code.indexOf("runTransaction");
        const fetchIdx = code.indexOf("https://api.anthropic.com/v1/messages");
        expect(quotaIdx).toBeGreaterThan(-1);
        expect(quotaIdx).toBeLessThan(fetchIdx);
    });
});
