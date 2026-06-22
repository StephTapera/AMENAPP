/**
 * creationAI.test.ts
 * Unit tests for creation AI helpers.
 * Tests the pure JSON extraction and validation logic — no Anthropic calls.
 */

// ---------------------------------------------------------------------------
// Inline helpers matching creationAI.ts logic
// ---------------------------------------------------------------------------

function extractJsonArray(raw: string): unknown[] {
    try {
        const match = raw.match(/\[[\s\S]*?\]/);
        if (match) return JSON.parse(match[0]) as unknown[];
    } catch { /* intentional */ }
    return [];
}

function sanitizeHashtags(tags: unknown[]): string[] {
    return tags
        .filter((t): t is string => typeof t === "string" && t.length > 0 && t.length <= 50)
        .map((t) => (t.startsWith("#") ? t : `#${t}`))
        .slice(0, 8);
}

function sanitizeOutline(items: unknown[]): string[] {
    return items
        .filter((i): i is string => typeof i === "string" && i.trim().length > 0)
        .map((i) => i.trim())
        .slice(0, 6);
}

// ---------------------------------------------------------------------------
// Tests: JSON array extraction
// ---------------------------------------------------------------------------

describe("creationAI — JSON array extraction", () => {
    it("extracts clean JSON array", () => {
        const raw = '["#faith", "#prayer", "#bible"]';
        expect(extractJsonArray(raw)).toEqual(["#faith", "#prayer", "#bible"]);
    });

    it("extracts array embedded in prose", () => {
        const raw = 'Here are your hashtags: ["#grace", "#hope"]. Use them wisely.';
        expect(extractJsonArray(raw)).toEqual(["#grace", "#hope"]);
    });

    it("returns empty array for malformed JSON", () => {
        expect(extractJsonArray("{ broken json }")).toEqual([]);
    });

    it("returns empty array for empty string", () => {
        expect(extractJsonArray("")).toEqual([]);
    });
});

// ---------------------------------------------------------------------------
// Tests: Hashtag sanitisation
// ---------------------------------------------------------------------------

describe("creationAI — hashtag sanitisation", () => {
    it("adds # prefix when missing", () => {
        const result = sanitizeHashtags(["faith", "prayer"]);
        expect(result).toContain("#faith");
        expect(result).toContain("#prayer");
    });

    it("preserves # prefix when present", () => {
        const result = sanitizeHashtags(["#bible"]);
        expect(result).toContain("#bible");
        expect(result).not.toContain("##bible");
    });

    it("caps at 8 hashtags", () => {
        const input = Array.from({ length: 15 }, (_, i) => `tag${i}`);
        expect(sanitizeHashtags(input).length).toBeLessThanOrEqual(8);
    });

    it("drops non-string values", () => {
        const result = sanitizeHashtags(["valid", 42, null, undefined, "also_valid"] as unknown[]);
        expect(result).toHaveLength(2);
    });

    it("drops empty strings", () => {
        const result = sanitizeHashtags(["", "faith"]);
        expect(result).toHaveLength(1);
    });
});

// ---------------------------------------------------------------------------
// Tests: Outline sanitisation
// ---------------------------------------------------------------------------

describe("creationAI — outline sanitisation", () => {
    it("trims whitespace", () => {
        const result = sanitizeOutline(["  Introduction  ", "Main Point"]);
        expect(result[0]).toBe("Introduction");
    });

    it("caps at 6 items", () => {
        const input = Array.from({ length: 10 }, (_, i) => `Point ${i}`);
        expect(sanitizeOutline(input).length).toBeLessThanOrEqual(6);
    });

    it("drops non-strings", () => {
        const result = sanitizeOutline(["Valid point", 123, null] as unknown[]);
        expect(result).toHaveLength(1);
    });
});
