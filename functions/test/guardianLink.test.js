/**
 * guardianLink.test.js
 * Unit tests for the guardian email-verification helpers (finding #44).
 *
 * Tests the pure internals (OTP generation, hashing, email validation) exported
 * via guardianLink._internal. The onCall/onDocumentCreated handlers require the
 * Firebase emulator for integration testing (see SAFETY_RUNBOOK §14) and are
 * covered by the bait-transcript runner, not here.
 */
const { _internal } = require("../guardianLink");
const { sha256, generateOTP, isValidEmail } = _internal;

describe("guardianLink helpers", () => {
  describe("generateOTP", () => {
    it("always returns a 6-digit numeric string", () => {
      for (let i = 0; i < 200; i++) {
        const otp = generateOTP();
        expect(otp).toMatch(/^\d{6}$/);
        expect(otp.length).toBe(6);
      }
    });

    it("zero-pads small values to 6 digits", () => {
      // Statistically over 200 runs we will hit at least one value < 100000;
      // every result must still be length 6.
      const otps = Array.from({ length: 200 }, () => generateOTP());
      expect(otps.every((o) => o.length === 6)).toBe(true);
    });
  });

  describe("sha256", () => {
    it("produces a stable 64-char hex digest", () => {
      const digest = sha256("123456");
      expect(digest).toMatch(/^[0-9a-f]{64}$/);
      // Deterministic — same input → same output.
      expect(sha256("123456")).toBe(digest);
    });

    it("different inputs produce different digests", () => {
      expect(sha256("123456")).not.toBe(sha256("123457"));
    });

    it("never returns the raw OTP (I-GUARDIAN-2: hash stored, not raw)", () => {
      const otp = "428913";
      expect(sha256(otp)).not.toContain(otp);
    });
  });

  describe("isValidEmail", () => {
    it("accepts well-formed addresses", () => {
      expect(isValidEmail("parent@example.com")).toBe(true);
      expect(isValidEmail("a.b+tag@sub.domain.org")).toBe(true);
    });

    it("rejects malformed addresses", () => {
      expect(isValidEmail("")).toBe(false);
      expect(isValidEmail("no-at-sign")).toBe(false);
      expect(isValidEmail("missing@domain")).toBe(false);
      expect(isValidEmail("@nodomain.com")).toBe(false);
      expect(isValidEmail("spaces in@email.com")).toBe(false);
    });

    it("rejects non-string input (fail-closed)", () => {
      expect(isValidEmail(null)).toBe(false);
      expect(isValidEmail(undefined)).toBe(false);
      expect(isValidEmail(12345)).toBe(false);
    });
  });
});
