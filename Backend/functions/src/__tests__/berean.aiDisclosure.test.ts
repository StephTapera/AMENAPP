/**
 * berean.aiDisclosure.test.ts
 *
 * Phase F — unit test for the shared AI disclosure helper used by both
 * Berean proxies (streaming and non-streaming).
 *
 * What this proves:
 *   - The disclosure is prepended to every plain assistant response.
 *   - The disclosure is idempotent — applying it twice has no effect.
 *   - Case-insensitive prefix match (so a future capitalization tweak
 *     does not silently double-prepend).
 *   - Non-string input does not crash; returns the disclosure stub.
 *   - The exported constant matches the canonical disclosure line so
 *     analytics and UI strings cannot drift.
 */

import {
    AI_DISCLOSURE_LINE,
    ensureAIDisclosure,
} from "../berean/services/aiDisclosure";

describe("ensureAIDisclosure — happy path", () => {
    test("prepends the disclosure to a plain response", () => {
        const out = ensureAIDisclosure("Peace be with you.");
        expect(out.startsWith(AI_DISCLOSURE_LINE)).toBe(true);
        expect(out).toContain("Peace be with you.");
    });

    test("preserves a multi-line response after the disclosure", () => {
        const body = "Line one.\nLine two.\n\nLine four.";
        const out = ensureAIDisclosure(body);
        expect(out.endsWith(body)).toBe(true);
    });
});

describe("ensureAIDisclosure — idempotence", () => {
    test("does not re-prepend when called twice", () => {
        const once = ensureAIDisclosure("hello");
        const twice = ensureAIDisclosure(once);
        expect(twice).toBe(once);
    });

    test("does not re-prepend if the disclosure already opens the text", () => {
        const already = `${AI_DISCLOSURE_LINE}\n\nbody text`;
        const out = ensureAIDisclosure(already);
        expect(out).toBe(already);
    });

    test("does not re-prepend even with different capitalization", () => {
        const upper = AI_DISCLOSURE_LINE.toUpperCase();
        const input = `${upper}\n\nbody`;
        const out = ensureAIDisclosure(input);
        // Should leave the existing (upper-cased) disclosure in place,
        // not stack a second canonical-cased disclosure on top.
        const occurrences = out
            .toLowerCase()
            .split(AI_DISCLOSURE_LINE.slice(0, 24).toLowerCase()).length - 1;
        expect(occurrences).toBe(1);
    });
});

describe("ensureAIDisclosure — defensive", () => {
    test("non-string input returns the disclosure stub", () => {
        const out = ensureAIDisclosure(undefined as unknown as string);
        expect(out.startsWith(AI_DISCLOSURE_LINE)).toBe(true);
    });

    test("empty string yields the disclosure followed by nothing meaningful", () => {
        const out = ensureAIDisclosure("");
        expect(out.startsWith(AI_DISCLOSURE_LINE)).toBe(true);
    });
});

describe("ensureAIDisclosure — canonical line content", () => {
    test("disclosure mentions AI-generated, pastoral, medical, legal, clinical", () => {
        const lower = AI_DISCLOSURE_LINE.toLowerCase();
        expect(lower).toContain("ai-generated");
        expect(lower).toContain("pastoral");
        expect(lower).toContain("medical");
        expect(lower).toContain("legal");
        expect(lower).toContain("clinical");
    });
});
