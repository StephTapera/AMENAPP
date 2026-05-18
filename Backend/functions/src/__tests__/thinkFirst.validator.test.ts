/**
 * thinkFirst.validator.test.ts
 *
 * Phase P1-4 — unit tests for the server-side Think-First validator.
 *
 * What this proves:
 *   - Safe text is allowed.
 *   - Critical violations (sexual minors, hate, threats, self-harm) hard-block.
 *   - Harassment / scam returns requireEdit.
 *   - PII / spam / heated language returns softPrompt.
 *   - Oversized input returns requireEdit.
 *   - Non-string input returns requireEdit.
 *   - Result NEVER contains the user's original text (privacy).
 *   - Categories array contains no duplicates.
 *   - maxSeverity tracks the highest observed severity.
 *
 * The validator is a pure function with no Firebase Functions runtime
 * side effects, so this test runs under standard jest with no mocks.
 */

import {
    validateThinkFirst,
    THINK_FIRST_MAX_INPUT_CHARS,
} from "../thinkFirst/validator";

describe("validateThinkFirst — safe content", () => {
    test("allows empty string", () => {
        const r = validateThinkFirst("");
        expect(r.action).toBe("allow");
        expect(r.allowed).toBe(true);
        expect(r.categories).toEqual([]);
        expect(r.userMessage).toBe("");
    });

    test("allows ordinary prose", () => {
        const r = validateThinkFirst(
            "Sharing a verse that encouraged me today. Grateful for this community."
        );
        expect(r.action).toBe("allow");
        expect(r.allowed).toBe(true);
        expect(r.maxSeverity).toBe("info");
    });
});

describe("validateThinkFirst — critical violations block", () => {
    test("blocks sexual-minors phrases", () => {
        const r = validateThinkFirst("This post contains child sex content.");
        expect(r.action).toBe("block");
        expect(r.allowed).toBe(false);
        expect(r.maxSeverity).toBe("critical");
        expect(r.categories).toContain("sexual_minors");
    });

    test("blocks hate-speech slurs", () => {
        // Using denylist token from the validator.
        const r = validateThinkFirst("you faggot");
        expect(r.action).toBe("block");
        expect(r.categories).toContain("hate");
    });

    test("blocks explicit threats", () => {
        const r = validateThinkFirst("i will kill you");
        expect(r.action).toBe("block");
        expect(r.categories).toContain("threats");
    });

    test("blocks self-harm + surfaces 988 in userMessage", () => {
        const r = validateThinkFirst("I want to die and kill myself.");
        expect(r.action).toBe("block");
        expect(r.categories).toContain("self_harm");
        expect(r.userMessage).toMatch(/988/);
    });
});

describe("validateThinkFirst — non-critical violations", () => {
    test("requires edit for harassment", () => {
        const r = validateThinkFirst("Honestly, kys.");
        expect(r.action).toBe("requireEdit");
        expect(r.allowed).toBe(false);
        expect(r.categories).toContain("harassment");
    });

    test("requires edit for scam patterns", () => {
        const r = validateThinkFirst("Please send me bitcoin to this address");
        expect(r.action).toBe("requireEdit");
        expect(r.categories).toContain("scam");
    });

    test("soft-prompts on PII (email)", () => {
        const r = validateThinkFirst("Email me at someone@example.com please");
        expect(r.action).toBe("softPrompt");
        expect(r.allowed).toBe(true);
        expect(r.categories).toContain("pii");
    });

    test("soft-prompts on PII (phone)", () => {
        const r = validateThinkFirst("Call me at 555 123 4567 today");
        expect(r.action).toBe("softPrompt");
        expect(r.categories).toContain("pii");
    });

    test("soft-prompts on heated tone", () => {
        const r = validateThinkFirst("You're a stupid idiot, shut up.");
        expect(r.action).toBe("softPrompt");
        expect(r.categories).toContain("heated");
        expect(r.suggestedRevision).toBeDefined();
    });
});

describe("validateThinkFirst — length and type guards", () => {
    test("requireEdit on oversized input", () => {
        const huge = "a".repeat(THINK_FIRST_MAX_INPUT_CHARS + 1);
        const r = validateThinkFirst(huge);
        expect(r.action).toBe("requireEdit");
        expect(r.allowed).toBe(false);
        expect(r.userMessage).toMatch(/maximum length|shorten/i);
    });

    test("requireEdit on non-string input", () => {
        const r = validateThinkFirst(42 as unknown as string);
        expect(r.action).toBe("requireEdit");
        expect(r.allowed).toBe(false);
    });

    test("requireEdit on null input", () => {
        const r = validateThinkFirst(null as unknown as string);
        expect(r.action).toBe("requireEdit");
    });

    test("requireEdit on undefined input", () => {
        const r = validateThinkFirst(undefined as unknown as string);
        expect(r.action).toBe("requireEdit");
    });
});

describe("validateThinkFirst — privacy invariants", () => {
    test("userMessage never echoes the input verbatim", () => {
        const secret = "MY_SECRET_PRAYER_TEXT_THAT_SHOULD_NEVER_LEAK";
        const r = validateThinkFirst(secret);
        expect(r.userMessage).not.toContain(secret);
    });

    test("PII detection message does not echo the detected email", () => {
        const r = validateThinkFirst("contact me: secretive@example.com");
        expect(r.userMessage).not.toContain("secretive@example.com");
    });

    test("self-harm message does not echo the user's phrasing", () => {
        const r = validateThinkFirst("kill myself in a very specific way");
        expect(r.userMessage).not.toContain("specific way");
    });
});

describe("validateThinkFirst — result invariants", () => {
    test("categories contain no duplicates", () => {
        // Multi-PII triggers a single 'pii' violation (with grouped detail)
        // because the validator collapses PII to one violation. We still
        // want to ensure the categories list is deduped in general.
        const r = validateThinkFirst(
            "Hate test: faggot, threat: i will kill you, self-harm: i want to die"
        );
        const seen = new Set(r.categories);
        expect(seen.size).toBe(r.categories.length);
    });

    test("allowed flag matches action semantics", () => {
        for (const text of [
            "",
            "Hello",
            "Try @ me at me@ex.com",
            "You're an idiot",
            "Please send me bitcoin to this address",
            "kys",
            "you faggot",
        ]) {
            const r = validateThinkFirst(text);
            const expected =
                r.action === "allow" || r.action === "softPrompt";
            expect(r.allowed).toBe(expected);
        }
    });

    test("maxSeverity matches highest individual severity", () => {
        // Combine a heated (info) + PII (warning) + self-harm (critical).
        const r = validateThinkFirst(
            "stupid loser, email me@ex.com, i want to die"
        );
        expect(r.maxSeverity).toBe("critical");
        expect(r.action).toBe("block");
    });
});
