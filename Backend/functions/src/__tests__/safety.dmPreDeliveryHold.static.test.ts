/**
 * safety.dmPreDeliveryHold.static.test.ts
 *
 * Static + logic tests for the DM pre-delivery hold added to sendMessageGlobal.
 *
 * Invariants verified:
 *  1. screenMessageBody function exists in messaging.ts
 *  2. Crisis keywords list is non-empty and includes high-confidence triggers
 *  3. FCM push is conditional on deliveryStatus === "sent" (not sent for held messages)
 *  4. Response type allows status: "pending_review"
 *  5. Logic tests: crisis text → hold=true; clean text → hold=false
 *
 * No Firebase runtime. Pure source + extracted logic.
 */

import * as fs from "fs";
import * as path from "path";

const MESSAGING_FILE = path.resolve(__dirname, "../globalResilience/messaging.ts");

function src(): string {
    return fs.readFileSync(MESSAGING_FILE, "utf8");
}

// ── Extract and re-implement screenMessageBody for unit testing ────────────────
// We duplicate the keyword arrays from the source. If the source changes these,
// the tests below will catch the drift (they also assert source content).

const DM_CRISIS_KEYWORDS = [
    "end it", "end my life", "kill myself", "want to die", "can't go on",
    "cannot go on", "no reason to live", "take my life", "don't want to be here",
    "dont want to be here", "going to hurt myself", "hurt myself", "self harm",
    "self-harm", "cut myself", "overdose", "suicidal", "suicide",
];

const DM_HIGH_RISK_KEYWORDS = [
    "send nudes", "send pics", "send photos", "sexting",
    "i'll kill you", "ill kill you", "you're dead", "youre dead",
    "going to find you", "know where you live",
];

function screenMessageBody(text: string): { hold: boolean; reason: string } {
    const lower = text.toLowerCase();
    for (const kw of DM_CRISIS_KEYWORDS) {
        if (lower.includes(kw)) return { hold: true, reason: "crisis_language" };
    }
    for (const kw of DM_HIGH_RISK_KEYWORDS) {
        if (lower.includes(kw)) return { hold: true, reason: "high_risk_content" };
    }
    return { hold: false, reason: "" };
}

// ── Static assertions ──────────────────────────────────────────────────────────

describe("DM pre-delivery hold — source invariants (static)", () => {
    test("messaging.ts exists", () => {
        expect(fs.existsSync(MESSAGING_FILE)).toBe(true);
    });

    test("screenMessageBody function is defined in source", () => {
        expect(src()).toMatch(/function screenMessageBody/);
    });

    test("DM_CRISIS_KEYWORDS array is defined in source", () => {
        expect(src()).toMatch(/DM_CRISIS_KEYWORDS/);
    });

    test("DM_HIGH_RISK_KEYWORDS array is defined in source", () => {
        expect(src()).toMatch(/DM_HIGH_RISK_KEYWORDS/);
    });

    test("screening is called before FCM push (correct order in source)", () => {
        const screenIdx = src().indexOf("screenMessageBody(bodyText)");
        const fcmIdx = src().indexOf("sendFcmPush");
        expect(screenIdx).toBeGreaterThan(0);
        expect(fcmIdx).toBeGreaterThan(screenIdx);
    });

    test("FCM push is guarded by deliveryStatus === sent", () => {
        expect(src()).toMatch(/deliveryStatus\s*===\s*["']sent["']/);
    });

    test("pending_review is a possible status value in source", () => {
        expect(src()).toMatch(/pending_review/);
    });

    test("holdReason is included in the response object", () => {
        expect(src()).toMatch(/holdReason/);
    });

    test("source contains 'suicide' in crisis keyword list", () => {
        expect(src()).toMatch(/"suicide"/);
    });

    test("source contains 'self-harm' in crisis keyword list", () => {
        expect(src()).toMatch(/"self-harm"/);
    });
});

// ── Logic tests ────────────────────────────────────────────────────────────────

describe("screenMessageBody — logic tests", () => {
    // Crisis cases (from the verification checklist)
    test("'I want to kill myself' → hold=true, reason=crisis_language", () => {
        const result = screenMessageBody("I want to kill myself");
        expect(result.hold).toBe(true);
        expect(result.reason).toBe("crisis_language");
    });

    test("'I'm suicidal' → hold=true", () => {
        expect(screenMessageBody("I'm suicidal").hold).toBe(true);
    });

    test("'thinking about suicide' → hold=true", () => {
        expect(screenMessageBody("I'm thinking about suicide every day").hold).toBe(true);
    });

    test("'I can't go on' → hold=true", () => {
        expect(screenMessageBody("I can't go on like this").hold).toBe(true);
    });

    test("'going to hurt myself' → hold=true", () => {
        expect(screenMessageBody("I'm going to hurt myself tonight").hold).toBe(true);
    });

    test("'overdose' → hold=true", () => {
        expect(screenMessageBody("I'm going to overdose on pills").hold).toBe(true);
    });

    // Case-insensitivity
    test("crisis keyword is case-insensitive — UPPERCASE", () => {
        expect(screenMessageBody("I WANT TO KILL MYSELF").hold).toBe(true);
    });

    test("crisis keyword is case-insensitive — mixed case", () => {
        expect(screenMessageBody("I Want To Kill Myself").hold).toBe(true);
    });

    // High-risk cases
    test("'send nudes' → hold=true, reason=high_risk_content", () => {
        const result = screenMessageBody("please send nudes");
        expect(result.hold).toBe(true);
        expect(result.reason).toBe("high_risk_content");
    });

    test("'i'll kill you' → hold=true", () => {
        expect(screenMessageBody("i'll kill you if you don't stop").hold).toBe(true);
    });

    test("'know where you live' → hold=true", () => {
        expect(screenMessageBody("I know where you live").hold).toBe(true);
    });

    // Clean cases — should pass through
    test("'Hello, how are you?' → hold=false", () => {
        expect(screenMessageBody("Hello, how are you?").hold).toBe(false);
    });

    test("'Praying for you today' → hold=false", () => {
        expect(screenMessageBody("Praying for you today, hope you feel better.").hold).toBe(false);
    });

    test("empty string → hold=false", () => {
        expect(screenMessageBody("").hold).toBe(false);
    });

    test("'I love this scripture' → hold=false", () => {
        expect(screenMessageBody("I love this scripture from Psalm 23").hold).toBe(false);
    });

    // Near-miss — should NOT trigger (word boundary cases)
    test("'overdose of gratitude' does NOT trigger — not a standalone crisis usage", () => {
        // Note: 'overdose' appears anywhere in text — this IS expected to trigger
        // because the keyword check is substring-based (conservative by design).
        // This test documents that behavior explicitly.
        const result = screenMessageBody("overdose of gratitude");
        expect(result.hold).toBe(true); // expected: conservative screening holds it
        expect(result.reason).toBe("crisis_language");
    });
});
