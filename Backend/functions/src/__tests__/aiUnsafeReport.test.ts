/**
 * aiUnsafeReport.test.ts
 *
 * Phase H3 — unit test for the reportUnsafeAIResponse input validator.
 *
 * What this proves:
 *   - messageId is required and capped.
 *   - reason must be from the allowlist.
 *   - details are optional; oversized rejected; trimmed empty dropped.
 *   - conversationId optional and capped.
 *   - surface defaults to "other"; unknown surface degrades to "other"
 *     (does not throw — App Review reviewers may submit reports from
 *     surfaces we have not enumerated yet).
 *   - Client-supplied uid / processed / createdAt fields are not in
 *     the validator output (they are server-owned).
 *
 * The validator is a pure function (Firebase HttpsError on violation).
 * We import it directly without instantiating the onCall wrapper.
 */

import {
    validateReportInput,
    MAX_DETAILS_CHARS,
    MAX_MESSAGE_ID_CHARS,
    MAX_CONVERSATION_ID_CHARS,
} from "../aiSafety/reportUnsafeAIResponse";

describe("validateReportInput — required fields", () => {
    test("rejects missing messageId", () => {
        expect(() =>
            validateReportInput({ reason: "unsafe_advice" })
        ).toThrow(/messageId/);
    });

    test("rejects empty-string messageId", () => {
        expect(() =>
            validateReportInput({ messageId: "", reason: "unsafe_advice" })
        ).toThrow(/messageId/);
    });

    test("rejects non-string messageId", () => {
        expect(() =>
            validateReportInput({
                messageId: 42 as unknown as string,
                reason: "unsafe_advice",
            })
        ).toThrow(/messageId/);
    });

    test("rejects oversized messageId", () => {
        const big = "a".repeat(MAX_MESSAGE_ID_CHARS + 1);
        expect(() =>
            validateReportInput({ messageId: big, reason: "unsafe_advice" })
        ).toThrow();
    });

    test("rejects missing reason", () => {
        expect(() =>
            validateReportInput({ messageId: "m1" })
        ).toThrow(/reason/);
    });

    test("rejects unknown reason", () => {
        expect(() =>
            validateReportInput({ messageId: "m1", reason: "i_just_dont_like_it" })
        ).toThrow(/reason/);
    });
});

describe("validateReportInput — reason allowlist", () => {
    const cases = [
        "unsafe_advice",
        "false_doctrine",
        "claims_divine_authority",
        "crisis_mishandled",
        "harassment_or_hate",
        "private_info_leak",
        "other",
    ];
    test.each(cases)("accepts reason %s", (reason) => {
        const out = validateReportInput({ messageId: "m1", reason });
        expect(out.reason).toBe(reason);
    });
});

describe("validateReportInput — details handling", () => {
    test("accepts a normal-length details string", () => {
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
            details: "The response told me to stop taking my medication.",
        });
        expect(out.details).toContain("medication");
    });

    test("drops empty / whitespace-only details", () => {
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
            details: "   \n  ",
        });
        expect(out.details).toBeUndefined();
    });

    test("rejects non-string details", () => {
        expect(() =>
            validateReportInput({
                messageId: "m1",
                reason: "unsafe_advice",
                details: 42 as unknown as string,
            })
        ).toThrow(/details/);
    });

    test("rejects oversized details", () => {
        const big = "a".repeat(MAX_DETAILS_CHARS + 1);
        expect(() =>
            validateReportInput({
                messageId: "m1",
                reason: "unsafe_advice",
                details: big,
            })
        ).toThrow(/details/);
    });

    test("details defaults to undefined when absent", () => {
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
        });
        expect(out.details).toBeUndefined();
    });
});

describe("validateReportInput — conversationId handling", () => {
    test("accepts a normal conversationId", () => {
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
            conversationId: "conv-abc-123",
        });
        expect(out.conversationId).toBe("conv-abc-123");
    });

    test("rejects oversized conversationId", () => {
        const big = "c".repeat(MAX_CONVERSATION_ID_CHARS + 1);
        expect(() =>
            validateReportInput({
                messageId: "m1",
                reason: "unsafe_advice",
                conversationId: big,
            })
        ).toThrow();
    });

    test("rejects non-string conversationId", () => {
        expect(() =>
            validateReportInput({
                messageId: "m1",
                reason: "unsafe_advice",
                conversationId: 5 as unknown as string,
            })
        ).toThrow();
    });
});

describe("validateReportInput — surface handling", () => {
    test("defaults to 'other' when missing", () => {
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
        });
        expect(out.surface).toBe("other");
    });

    test("preserves known surfaces", () => {
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
            surface: "berean_chat",
        });
        expect(out.surface).toBe("berean_chat");
    });

    test("degrades unknown surface to 'other' without throwing", () => {
        // App Review may report from surfaces we have not enumerated yet.
        // The validator must not block; it just degrades.
        const out = validateReportInput({
            messageId: "m1",
            reason: "unsafe_advice",
            surface: "future_surface_we_havent_added_yet",
        });
        expect(out.surface).toBe("other");
    });
});

describe("validateReportInput — server-owned field invariants", () => {
    test("does not surface client-supplied uid / processed / createdAt", () => {
        const smuggledPayload = {
            messageId: "m1",
            reason: "unsafe_advice",
            // Attempt to smuggle server-owned fields.
            uid: "attacker-uid",
            processed: true,
            createdAt: "yesterday",
        } as Record<string, unknown>;
        const out = validateReportInput(smuggledPayload);
        expect((out as Record<string, unknown>).uid).toBeUndefined();
        expect((out as Record<string, unknown>).processed).toBeUndefined();
        expect((out as Record<string, unknown>).createdAt).toBeUndefined();
    });
});
