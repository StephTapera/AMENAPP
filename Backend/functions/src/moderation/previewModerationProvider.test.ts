import { moderatePreviewText } from "./previewModerationProvider";

describe("previewModerationProvider", () => {
    test("blocks kys variants", () => {
        expect(moderatePreviewText({ text: "kys" }).passed).toBe(false);
        expect(moderatePreviewText({ text: "k y s" }).passed).toBe(false);
        expect(moderatePreviewText({ text: "k.y.s" }).passed).toBe(false);
    });

    test("blocks kill yourself obfuscations", () => {
        expect(moderatePreviewText({ text: "k1ll yourself" }).passed).toBe(false);
        expect(moderatePreviewText({ text: "killll yourself" }).passed).toBe(false);
    });

    test("blocks obfuscated spam links", () => {
        expect(moderatePreviewText({ text: "visit hxxp://bad.site" }).passed).toBe(false);
        expect(moderatePreviewText({ text: "spam dot com now" }).passed).toBe(false);
    });

    test("blocks sexual explicit and violent threat", () => {
        expect(moderatePreviewText({ text: "this is explicit sexual content" }).passed).toBe(false);
        expect(moderatePreviewText({ text: "I will kill you tonight" }).passed).toBe(false);
    });

    test("blocks slur bypass placeholder", () => {
        expect(moderatePreviewText({ text: "n!gg3r" }).passed).toBe(false);
    });

    test("allows safe pastoral and biblical language in non-abusive context", () => {
        expect(moderatePreviewText({ text: "We are walking through grief and lament together in Christ." }).passed).toBe(true);
        expect(moderatePreviewText({ text: "Repentance and grace are central to the gospel." }).passed).toBe(true);
    });

    test("uncertain moderation suppresses candidate", () => {
        const result = moderatePreviewText({ text: "a" });
        expect(result.passed).toBe(false);
        expect(result.rejectionReason).toContain("pending_or_uncertain");
    });

    test("invalid input fails closed", () => {
        const result = moderatePreviewText(undefined as never);
        expect(result.passed).toBe(false);
        expect(result.rejectionReason).toBe("unknown_moderation_state");
    });
});
