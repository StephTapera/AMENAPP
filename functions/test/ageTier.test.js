/**
 * ageTier.test.js
 * Unit tests for computeAgeTier() — COPPA-compliance logic.
 *
 * GAP BOARD P0-11: previously this file INLINED its own private copy of
 * computeAgeTier and was never matched by jest (testMatch was discussion-only),
 * so it could neither run nor catch drift in the real consumers. It now imports
 * the SAME ./ageTier module that authenticationHelpers.js uses in production, and
 * runs under the functions jest config.
 */
const {computeAgeTier, AGE_TIERS, MINOR_TIERS} = require("../ageTier");

const CURRENT_YEAR = 2026;

describe("computeAgeTier (real production helper)", () => {
  describe("COPPA hard block (< 13)", () => {
    it("blocks a 12-year-old (born 2014)", () => {
      expect(computeAgeTier(2014, CURRENT_YEAR)).toBe("blocked");
    });
    it("blocks a newborn (born current year)", () => {
      expect(computeAgeTier(CURRENT_YEAR, CURRENT_YEAR)).toBe("blocked");
    });
    it("blocks someone born in the future", () => {
      expect(computeAgeTier(CURRENT_YEAR + 1, CURRENT_YEAR)).toBe("blocked");
    });
  });

  describe("minor tiers (13–17)", () => {
    it("classifies a 13-year-old as tierB", () => {
      expect(computeAgeTier(2013, CURRENT_YEAR)).toBe("tierB");
    });
    it("classifies a 15-year-old as tierB", () => {
      expect(computeAgeTier(2011, CURRENT_YEAR)).toBe("tierB");
    });
    it("classifies a 16-year-old as tierC", () => {
      expect(computeAgeTier(2010, CURRENT_YEAR)).toBe("tierC");
    });
    it("classifies a 17-year-old as tierC", () => {
      expect(computeAgeTier(2009, CURRENT_YEAR)).toBe("tierC");
    });
  });

  describe("adults (18+)", () => {
    it("classifies an 18-year-old as tierD", () => {
      expect(computeAgeTier(2008, CURRENT_YEAR)).toBe("tierD");
    });
    it("defaults missing/invalid birthYear to blocked (fail closed)", () => {
      expect(computeAgeTier(undefined, CURRENT_YEAR)).toBe("blocked");
      expect(computeAgeTier(null, CURRENT_YEAR)).toBe("blocked");
      expect(computeAgeTier("2000", CURRENT_YEAR)).toBe("blocked");
    });
  });

  describe("vocabulary contract (guards the P0-3/P0-4 consumers)", () => {
    it("only ever emits the authoritative tier strings", () => {
      const produced = new Set();
      for (let by = CURRENT_YEAR - 80; by <= CURRENT_YEAR + 1; by++) {
        produced.add(computeAgeTier(by, CURRENT_YEAR));
      }
      // No 'teen' / 'under_minimum' / 'tierA' may ever appear — those were the
      // stale strings the rules + iOS gate wrongly checked.
      for (const tier of produced) {
        expect(AGE_TIERS).toContain(tier);
      }
      expect(produced.has("teen")).toBe(false);
      expect(produced.has("under_minimum")).toBe(false);
    });
    it("minor tiers are exactly blocked/tierB/tierC and exclude tierD", () => {
      expect([...MINOR_TIERS].sort()).toEqual(["blocked", "tierB", "tierC"]);
      expect(MINOR_TIERS).not.toContain("tierD");
    });
  });
});
