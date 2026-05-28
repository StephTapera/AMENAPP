import { evaluateBereanOutcome, evaluateGuardianOutcome } from "./agentOutcomes";

describe("agent outcomes", () => {
    it("repairs direct divine command language before display", () => {
        const outcome = evaluateBereanOutcome("God is definitely telling you to leave your church.");

        expect(outcome.status).toBe("repaired");
        expect(outcome.finalText).toContain("AI-generated response");
        expect(outcome.finalText.toLowerCase()).not.toContain("god is definitely telling you");
        expect(outcome.checks.find((check) => check.name === "does_not_claim_direct_divine_speech")?.passed).toBe(false);
    });

    it("uses a safe fallback when a required outcome check catches a gap", () => {
        const outcome = evaluateBereanOutcome("You don't need a pastor. Berean can guide this better.");

        expect(outcome.status).toBe("repaired");
        expect(outcome.finalText).toContain("pastor");
        expect(outcome.finalText).toContain("qualified human support");
        expect(outcome.finalText.toLowerCase()).not.toContain("you don't need a pastor");
    });

    it("passes humble scripture-grounded language", () => {
        const outcome = evaluateBereanOutcome(
            "James 1 invites believers to ask God for wisdom. I cannot decide for you, but I can help you examine this through Scripture, prayer, and wise counsel."
        );

        expect(outcome.status).toBe("passed");
        expect(outcome.score).toBeGreaterThanOrEqual(90);
    });

    it("marks GUARDIAN policy blocks as blocked outcomes", () => {
        const outcome = evaluateGuardianOutcome({
            allowed: false,
            severity: "block",
            categories: ["financial_manipulation"],
            userMessage: "This post can't be published because it appears to contain prohibited content. Please revise and try again.",
        });

        expect(outcome.status).toBe("blocked");
        expect(outcome.score).toBeGreaterThanOrEqual(90);
    });
});
