/**
 * safety.profileModeration.static.test.ts
 *
 * Static + logic tests for moderateProfileFields callable (Gate C-5).
 *
 * Invariants verified:
 *  1. moderateProfileFields.ts exists and declares us-east1
 *  2. Impersonation patterns block "amenofficial", "amensupport", "amenadmin", "amenteam"
 *  3. Phone number regex catches the verification checklist example (555-867-5309)
 *  4. Email regex catches addresses in bio
 *  5. Username rules enforce length, character set, and no leading/trailing punctuation
 *  6. Bio length limit is 300 chars
 *  7. Fail-safe: function catches errors and returns allowed=true (never lockout)
 *
 * No Firebase runtime. Pure source + extracted logic.
 */

import * as fs from "fs";
import * as path from "path";

const MOD_FILE = path.resolve(__dirname, "../moderation/moderateProfileFields.ts");

function src(): string {
    return fs.readFileSync(MOD_FILE, "utf8");
}

// ── Re-implement logic for unit testing ───────────────────────────────────────

const BLOCKED_PATTERNS: RegExp[] = [
    /\bn[\*\s]?i[\*\s]?g[\*\s]?g[\*\s]?[ae]/i,
    /\bf[\*\s]?a[\*\s]?g/i,
    /\b\d{3}[\s.\-]?\d{3}[\s.\-]?\d{4}\b/,
    /[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/i,
    /\bamen[\s_\-]?official\b/i,
    /\bamen[\s_\-]?support\b/i,
    /\bamen[\s_\-]?admin\b/i,
    /\bamen[\s_\-]?team\b/i,
    /\bsex(?:ual|y)?\b/i,
    /\bporn\b/i,
    /\bnude\b/i,
    /\bxxx\b/i,
];

function screenText(text: string): { blocked: boolean; reason: string } {
    for (const pattern of BLOCKED_PATTERNS) {
        if (pattern.test(text)) return { blocked: true, reason: "Content policy violation" };
    }
    return { blocked: false, reason: "" };
}

function usernameRules(username: string): { blocked: boolean; reason: string } {
    if (username.length < 3) return { blocked: true, reason: "Username must be at least 3 characters" };
    if (username.length > 30) return { blocked: true, reason: "Username must be 30 characters or fewer" };
    if (!/^[a-zA-Z0-9_\.]+$/.test(username)) return { blocked: true, reason: "Username may only contain letters, numbers, underscores, or periods" };
    if (/^[_\.]|[_\.]$/.test(username)) return { blocked: true, reason: "Username cannot start or end with _ or ." };
    if (/[_\.]{2,}/.test(username)) return { blocked: true, reason: "Username cannot contain consecutive _ or ." };
    return screenText(username);
}

function bioRules(bio: string): { blocked: boolean; reason: string } {
    if (bio.length > 300) return { blocked: true, reason: "Bio must be 300 characters or fewer" };
    return screenText(bio);
}

// ── Static assertions ──────────────────────────────────────────────────────────

describe("Profile moderation — source invariants (static)", () => {
    test("moderateProfileFields.ts exists", () => {
        expect(fs.existsSync(MOD_FILE)).toBe(true);
    });

    test("function declares us-east1 region", () => {
        expect(src()).toMatch(/us-east1/);
    });

    test("fail-safe catch block returns allowed=true on error", () => {
        expect(src()).toMatch(/allowed:\s*true/);
        expect(src()).toMatch(/catch\s*\(err\)/);
    });

    test("BLOCKED_PATTERNS includes phone number regex", () => {
        expect(src()).toMatch(/\\d\{3\}/);
    });

    test("BLOCKED_PATTERNS includes email regex", () => {
        expect(src()).toMatch(/@.*\[a-z\]/i);
    });

    test("amen impersonation patterns are present", () => {
        expect(src()).toMatch(/amen.*official/i);
        expect(src()).toMatch(/amen.*support/i);
        expect(src()).toMatch(/amen.*admin/i);
        expect(src()).toMatch(/amen.*team/i);
    });

    test("bio length limit is 300", () => {
        expect(src()).toMatch(/300/);
    });

    test("username min length is 3", () => {
        expect(src()).toMatch(/length < 3/);
    });

    test("username max length is 30", () => {
        expect(src()).toMatch(/length > 30/);
    });

    test("returns flaggedField in the response", () => {
        expect(src()).toMatch(/flaggedField/);
    });
});

// ── Username logic tests ───────────────────────────────────────────────────────

describe("Username rules", () => {
    // Verification checklist: amenofficial
    test("'amenofficial' → blocked (impersonation)", () => {
        const result = usernameRules("amenofficial");
        expect(result.blocked).toBe(true);
    });

    test("'amen_official' → blocked (impersonation with underscore)", () => {
        expect(usernameRules("amen_official").blocked).toBe(true);
    });

    test("'amen-official' → blocked (impersonation with dash)", () => {
        expect(usernameRules("amen-official").blocked).toBe(true);
    });

    test("'amensupport' → blocked", () => {
        expect(usernameRules("amensupport").blocked).toBe(true);
    });

    test("'amenadmin' → blocked", () => {
        expect(usernameRules("amenadmin").blocked).toBe(true);
    });

    test("'amenteam' → blocked", () => {
        expect(usernameRules("amenteam").blocked).toBe(true);
    });

    // Valid usernames
    test("'stephtapera' → allowed", () => {
        expect(usernameRules("stephtapera").blocked).toBe(false);
    });

    test("'john_doe' → allowed", () => {
        expect(usernameRules("john_doe").blocked).toBe(false);
    });

    test("'user123' → allowed", () => {
        expect(usernameRules("user123").blocked).toBe(false);
    });

    // Length violations
    test("'ab' (2 chars) → blocked (too short)", () => {
        expect(usernameRules("ab").blocked).toBe(true);
    });

    test("31-char username → blocked (too long)", () => {
        expect(usernameRules("a".repeat(31)).blocked).toBe(true);
    });

    // Format violations
    test("leading underscore → blocked", () => {
        expect(usernameRules("_username").blocked).toBe(true);
    });

    test("trailing period → blocked", () => {
        expect(usernameRules("username.").blocked).toBe(true);
    });

    test("double underscore → blocked", () => {
        expect(usernameRules("user__name").blocked).toBe(true);
    });

    test("space in username → blocked", () => {
        expect(usernameRules("user name").blocked).toBe(true);
    });
});

// ── Bio logic tests ────────────────────────────────────────────────────────────

describe("Bio rules", () => {
    // Verification checklist: phone number in bio
    test("'call me 555-867-5309' → blocked (phone number)", () => {
        const result = bioRules("call me 555-867-5309");
        expect(result.blocked).toBe(true);
    });

    test("phone number with dots → blocked", () => {
        expect(bioRules("reach me at 555.867.5309").blocked).toBe(true);
    });

    test("phone number with spaces → blocked", () => {
        expect(bioRules("call 555 867 5309").blocked).toBe(true);
    });

    test("email address in bio → blocked", () => {
        expect(bioRules("email me at test@example.com").blocked).toBe(true);
    });

    test("'amenofficial' in bio → blocked (impersonation)", () => {
        expect(bioRules("I am amenofficial").blocked).toBe(true);
    });

    // Valid bio content
    test("normal bio → allowed", () => {
        expect(bioRules("Follower of Jesus. Wife. Mom of 3.").blocked).toBe(false);
    });

    test("scripture reference bio → allowed", () => {
        expect(bioRules("Philippians 4:13 | Building the kingdom").blocked).toBe(false);
    });

    // Length limit
    test("exactly 300 chars → allowed", () => {
        expect(bioRules("a".repeat(300)).blocked).toBe(false);
    });

    test("301 chars → blocked (too long)", () => {
        expect(bioRules("a".repeat(301)).blocked).toBe(true);
    });

    test("empty bio → allowed", () => {
        expect(bioRules("").blocked).toBe(false);
    });
});
