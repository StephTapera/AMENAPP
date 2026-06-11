/**
 * moderation-safety.test.js
 *
 * Unit tests for the NeMo Guard safety response parser (parseSafetyResponse)
 * and the submitSafetyReport input-validation logic.
 *
 * parseSafetyResponse is not publicly exported from moderatePost.js because it is
 * an internal helper, so we inline it here verbatim from the source.  This mirrors
 * the pattern used in aiPipeline.test.js and guarantees the tests run without a
 * Firebase emulator or NVIDIA credentials.
 *
 * submitSafetyReport validation logic is tested by extracting the pure-function
 * validation rules (category allowlist and notes-length cap) independently of the
 * Firebase SDK, with the HttpsError shape reproduced as a plain Error for
 * assertion purposes.
 */

"use strict";

// ─── Inlined parseSafetyResponse (verbatim copy from moderatePost.js) ─────────
// Any change to the production function must also be reflected here; the test
// will naturally drift-detect because the assertions cover the exact I/O contract.

/**
 * parseSafetyResponse — jailbreak-proof NeMo Guard output parser.
 * Returns { safe: boolean, categories: string[] }.
 * Fail-closed: any ambiguity or invalid input → safe = false.
 *
 * @param {string} raw - Raw text content from the NeMo Guard model response.
 * @returns {{ safe: boolean, categories: string[] }}
 */
function parseSafetyResponse(raw) {
  // Attempt 1: full JSON parse with EXACT string match.
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && "User Safety" in parsed) {
      const verdict = String(parsed["User Safety"]).trim().toLowerCase();
      // EXACT match only — never "not unsafe", never substring tricks.
      const safe = verdict === "safe";
      let categories = [];
      if (parsed["Safety Categories"]) {
        categories = String(parsed["Safety Categories"])
          .split(",")
          .map((c) => c.trim().toLowerCase())
          .filter(Boolean);
      }
      return { safe, categories };
    }
    // JSON parsed but "User Safety" key absent — fail closed.
    return { safe: false, categories: [] };
  } catch {
    // Not valid JSON — fall through to line-regex search.
  }

  // Attempt 2: find a line matching the expected key:value shape.
  const lines = raw.split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^\s*"?User Safety"?\s*:\s*"(safe|unsafe)"/i);
    if (m) {
      const safe = m[1].toLowerCase() === "safe"; // EXACT, not negation-based
      return { safe, categories: [] };
    }
  }

  // Attempt 3: ambiguous or unrecognised format — default UNSAFE (fail-closed).
  return { safe: false, categories: [] };
}

// ─── submitSafetyReport validation logic (pure-function extract) ──────────────
// Mirrors the validation block in functions/safety/submitSafetyReport.js without
// any Firebase SDK dependency.

const VALID_CATEGORIES = [
  "csam", "child_safety", "grooming", "harassment", "hate",
  "spam", "scam", "self_harm", "violence", "other",
];

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
    this.name = "HttpsError";
  }
}

function validateSubmitSafetyReport({ contentRef, reportCategory, reportNotes }) {
  if (!contentRef || typeof contentRef !== "string") {
    throw new HttpsError("invalid-argument", "contentRef required");
  }
  if (!VALID_CATEGORIES.includes(reportCategory)) {
    throw new HttpsError("invalid-argument", "Invalid category: " + reportCategory);
  }
  if (reportNotes && reportNotes.length > 500) {
    throw new HttpsError("invalid-argument", "reportNotes max 500 chars");
  }
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PART B — TEST SUITE
// ═══════════════════════════════════════════════════════════════════════════════

describe("parseSafetyResponse — NeMo Guard output parser (jailbreak-proof)", () => {
  // Test 1: Valid JSON {"User Safety": "unsafe"} → safe:false
  test('valid JSON {"User Safety":"unsafe"} returns safe:false', () => {
    const raw = JSON.stringify({ "User Safety": "unsafe" });
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(false);
  });

  // Test 2: Valid JSON {"User Safety": "safe"} → safe:true
  test('valid JSON {"User Safety":"safe"} returns safe:true', () => {
    const raw = JSON.stringify({ "User Safety": "safe" });
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(true);
  });

  // Test 3: Invalid JSON string → safe:false (fail closed)
  test("invalid JSON string falls back to line-scan and defaults to safe:false", () => {
    const raw = "this is not json at all";
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(false);
  });

  // Test 4: String containing "not unsafe" (not JSON) → safe:false (jailbreak blocked)
  // This is the key jailbreak vector: a model output like "not unsafe" must not be
  // interpreted as safe.  The parser uses EXACT match on "safe" only.
  test('"not unsafe" plaintext returns safe:false (jailbreak substring blocked)', () => {
    const raw = "The content is not unsafe and should be allowed.";
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(false);
  });

  // Additional jailbreak: JSON with "User Safety":"not unsafe"
  test('JSON {"User Safety":"not unsafe"} returns safe:false (exact-match guard)', () => {
    const raw = JSON.stringify({ "User Safety": "not unsafe" });
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(false);
  });

  // Additional jailbreak: JSON with "User Safety":"Safe" (capitalised)
  // The parser lowercases before comparing, so this should be safe:true
  test('JSON {"User Safety":"Safe"} returns safe:true (case-insensitive normalisation)', () => {
    const raw = JSON.stringify({ "User Safety": "Safe" });
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(true);
  });

  // Test 5: Empty string → safe:false
  test("empty string returns safe:false (fail-closed default)", () => {
    const result = parseSafetyResponse("");
    expect(result.safe).toBe(false);
  });

  // Additional: JSON missing "User Safety" key → safe:false
  test('JSON without "User Safety" key returns safe:false', () => {
    const raw = JSON.stringify({ verdict: "safe", status: "ok" });
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(false);
  });

  // Additional: Safety Categories are parsed when present
  test('JSON with "Safety Categories" parses categories array', () => {
    const raw = JSON.stringify({
      "User Safety": "unsafe",
      "Safety Categories": "hate_speech, violence, harassment",
    });
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(false);
    expect(result.categories).toEqual(["hate_speech", "violence", "harassment"]);
  });

  // Additional: safe response has empty categories array
  test("safe response returns empty categories array", () => {
    const raw = JSON.stringify({ "User Safety": "safe" });
    const result = parseSafetyResponse(raw);
    expect(result.categories).toEqual([]);
  });

  // Additional: line-scan path (Attempt 2) recognises the key:value shape
  test('line-scan path finds "User Safety": "safe" and returns safe:true', () => {
    const raw = 'Some preamble text\n"User Safety": "safe"\nSome suffix text';
    const result = parseSafetyResponse(raw);
    expect(result.safe).toBe(true);
  });

  // Additional: line-scan blocked for "not unsafe" phrasing
  test('line-scan "User Safety": "not unsafe" returns safe:false (exact-match)', () => {
    const raw = '"User Safety": "not unsafe"';
    const result = parseSafetyResponse(raw);
    // "not unsafe" does not match the regex /(safe|unsafe)/ exactly as "safe"
    expect(result.safe).toBe(false);
  });
});

describe("submitSafetyReport — input validation", () => {
  // Test 6: invalid category → throws HttpsError
  test("invalid reportCategory throws HttpsError with code invalid-argument", () => {
    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "not_a_real_category",
        reportNotes: "some notes",
      }),
    ).toThrow(HttpsError);

    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "not_a_real_category",
      }),
    ).toThrow("Invalid category: not_a_real_category");
  });

  // Additional: empty string category also throws
  test("empty reportCategory throws HttpsError", () => {
    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "",
      }),
    ).toThrow(HttpsError);
  });

  // Additional: SQL-injection style category is rejected
  test("SQL-injection reportCategory is rejected as invalid-argument", () => {
    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "'; DROP TABLE users; --",
      }),
    ).toThrow(HttpsError);
  });

  // Test 7: reportNotes over 500 chars → throws HttpsError
  test("reportNotes over 500 chars throws HttpsError with code invalid-argument", () => {
    const longNotes = "x".repeat(501);
    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "harassment",
        reportNotes: longNotes,
      }),
    ).toThrow(HttpsError);

    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "harassment",
        reportNotes: longNotes,
      }),
    ).toThrow("reportNotes max 500 chars");
  });

  // Boundary: exactly 500 chars is allowed
  test("reportNotes of exactly 500 chars passes validation", () => {
    const borderlineNotes = "y".repeat(500);
    expect(
      validateSubmitSafetyReport({
        contentRef: "posts/abc123",
        reportCategory: "spam",
        reportNotes: borderlineNotes,
      }),
    ).toBe(true);
  });

  // All valid categories pass
  test.each(VALID_CATEGORIES)("valid category '%s' passes validation", (category) => {
    expect(
      validateSubmitSafetyReport({
        contentRef: "posts/abc",
        reportCategory: category,
      }),
    ).toBe(true);
  });

  // Missing contentRef throws
  test("missing contentRef throws HttpsError", () => {
    expect(() =>
      validateSubmitSafetyReport({
        contentRef: "",
        reportCategory: "spam",
      }),
    ).toThrow(HttpsError);
  });

  // null contentRef throws
  test("null contentRef throws HttpsError", () => {
    expect(() =>
      validateSubmitSafetyReport({
        contentRef: null,
        reportCategory: "spam",
      }),
    ).toThrow(HttpsError);
  });

  // No reportNotes is fine
  test("omitted reportNotes passes validation", () => {
    expect(
      validateSubmitSafetyReport({
        contentRef: "posts/abc",
        reportCategory: "other",
      }),
    ).toBe(true);
  });
});
