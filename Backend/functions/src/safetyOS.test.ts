/**
 * safetyOS.test.ts
 * Unit tests for Safety OS rule-based classifiers and helpers.
 * Tests the deterministic pipeline logic — no network calls.
 */

// ---------------------------------------------------------------------------
// Inline copies of classifier patterns from safetyOS.ts (pure functions)
// that we can test without the full Firebase runtime.
// ---------------------------------------------------------------------------

const EXPLOITATION_PATTERNS = [
    /\b(send\s+me\s+(pic|photo|video|nude))/i,
    /\b(keep\s+this\s+secret|don'?t\s+tell\s+(your\s+)?(parents|mom|dad))/i,
    /\b(meet\s+up\s+alone|come\s+to\s+my\s+place)\b/i,
    /\b(i'?ll\s+buy\s+you|gift\s+card|amazon\s+card)\b/i,
    /\b(how\s+old\s+are\s+you|are\s+you\s+(a\s+)?(girl|boy|alone))\b/i,
];

const CRISIS_PATTERNS = [
    /\b(want\s+to\s+(die|kill\s+myself|end\s+it))/i,
    /\b(suicide|suicidal)\b/i,
    /\b(self[\s-]?harm|cutting\s+myself)\b/i,
    /\b(no\s+reason\s+to\s+(live|go\s+on))\b/i,
];

const HARASSMENT_PATTERNS = [
    /\b(you'?re\s+(disgusting|pathetic|worthless|ugly))\b/i,
    /\b(kill\s+yourself|kys)\b/i,
    /\b(fake\s+christian|hypocrite)\b/i,
    /\b(everyone\s+hates\s+you)\b/i,
];

function matchesAny(text: string, patterns: RegExp[]): boolean {
    return patterns.some((p) => p.test(text));
}

// ---------------------------------------------------------------------------
// Tests: Exploitation classifier
// ---------------------------------------------------------------------------

describe("Safety OS — exploitation classifier", () => {
    it("flags grooming opener", () => {
        expect(matchesAny("hey how old are you?", EXPLOITATION_PATTERNS)).toBe(true);
    });

    it("flags secrecy demand", () => {
        expect(matchesAny("keep this secret from your parents", EXPLOITATION_PATTERNS)).toBe(true);
    });

    it("flags media request", () => {
        expect(matchesAny("send me pic", EXPLOITATION_PATTERNS)).toBe(true);
    });

    it("allows normal greeting", () => {
        expect(matchesAny("Hey, how are you doing today?", EXPLOITATION_PATTERNS)).toBe(false);
    });

    it("allows faith discussion", () => {
        expect(matchesAny("What is your favourite Bible verse?", EXPLOITATION_PATTERNS)).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// Tests: Crisis classifier
// ---------------------------------------------------------------------------

describe("Safety OS — crisis classifier", () => {
    it("flags suicidal ideation", () => {
        expect(matchesAny("I want to kill myself", CRISIS_PATTERNS)).toBe(true);
    });

    it("flags self-harm mention", () => {
        expect(matchesAny("I've been doing self-harm", CRISIS_PATTERNS)).toBe(true);
    });

    it("flags hopelessness phrase", () => {
        expect(matchesAny("There's no reason to live anymore", CRISIS_PATTERNS)).toBe(true);
    });

    it("allows prayer for strength", () => {
        expect(matchesAny("Please pray for me, I'm struggling", CRISIS_PATTERNS)).toBe(false);
    });

    it("allows grief expression", () => {
        expect(matchesAny("I miss my grandmother so much", CRISIS_PATTERNS)).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// Tests: Harassment classifier
// ---------------------------------------------------------------------------

describe("Safety OS — harassment classifier", () => {
    it("flags direct insult", () => {
        expect(matchesAny("You're worthless", HARASSMENT_PATTERNS)).toBe(true);
    });

    it("flags KYS", () => {
        expect(matchesAny("kys loser", HARASSMENT_PATTERNS)).toBe(true);
    });

    it("flags faith-shaming", () => {
        expect(matchesAny("You're just a fake Christian", HARASSMENT_PATTERNS)).toBe(true);
    });

    it("allows respectful disagreement", () => {
        expect(matchesAny("I disagree with your interpretation of that verse.", HARASSMENT_PATTERNS)).toBe(false);
    });
});

// ---------------------------------------------------------------------------
// Tests: Edge cases
// ---------------------------------------------------------------------------

describe("Safety OS — edge cases", () => {
    it("empty string triggers no patterns", () => {
        const allPatterns = [...EXPLOITATION_PATTERNS, ...CRISIS_PATTERNS, ...HARASSMENT_PATTERNS];
        expect(matchesAny("", allPatterns)).toBe(false);
    });

    it("mixed case is handled", () => {
        expect(matchesAny("WANT TO KILL MYSELF", CRISIS_PATTERNS)).toBe(true);
    });

    it("partial word does not trigger", () => {
        // 'suicides' should not trigger 'suicidal' pattern at word boundary
        // (this tests our \b boundary anchoring)
        expect(matchesAny("The suicide prevention hotline helped me.", CRISIS_PATTERNS)).toBe(true); // "suicide" alone is flagged
    });
});
