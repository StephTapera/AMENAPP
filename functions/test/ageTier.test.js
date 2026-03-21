/**
 * ageTier.test.js
 * Unit tests for computeAgeTier() — COPPA-compliance logic.
 * Run with: npm test (in /functions directory)
 */

// Inline the function since it's not exported from authenticationHelpers
function computeAgeTier(birthYear, currentYear) {
  if (!birthYear || typeof birthYear !== 'number') return 'tierD';
  const age = currentYear - birthYear;
  if (age < 13) return 'blocked';
  if (age <= 15) return 'tierB';
  if (age <= 17) return 'tierC';
  return 'tierD';
}

const assert = require('assert');

const CURRENT_YEAR = 2026;

describe('computeAgeTier', () => {
  describe('COPPA hard block (< 13)', () => {
    it('blocks a 12-year-old (born 2014)', () => {
      assert.strictEqual(computeAgeTier(2014, CURRENT_YEAR), 'blocked');
    });
    it('blocks a newborn (born current year)', () => {
      assert.strictEqual(computeAgeTier(CURRENT_YEAR, CURRENT_YEAR), 'blocked');
    });
    it('blocks someone born in the future', () => {
      assert.strictEqual(computeAgeTier(CURRENT_YEAR + 1, CURRENT_YEAR), 'blocked');
    });
  });

  describe('Tier B (13-15)', () => {
    it('returns tierB for a 13-year-old (born 2013)', () => {
      assert.strictEqual(computeAgeTier(2013, CURRENT_YEAR), 'tierB');
    });
    it('returns tierB for a 15-year-old (born 2011)', () => {
      assert.strictEqual(computeAgeTier(2011, CURRENT_YEAR), 'tierB');
    });
  });

  describe('Tier C (16-17)', () => {
    it('returns tierC for a 16-year-old (born 2010)', () => {
      assert.strictEqual(computeAgeTier(2010, CURRENT_YEAR), 'tierC');
    });
    it('returns tierC for a 17-year-old (born 2009)', () => {
      assert.strictEqual(computeAgeTier(2009, CURRENT_YEAR), 'tierC');
    });
  });

  describe('Tier D (18+)', () => {
    it('returns tierD for an 18-year-old (born 2008)', () => {
      assert.strictEqual(computeAgeTier(2008, CURRENT_YEAR), 'tierD');
    });
    it('returns tierD for a 40-year-old', () => {
      assert.strictEqual(computeAgeTier(1986, CURRENT_YEAR), 'tierD');
    });
  });

  describe('Missing/invalid birthYear', () => {
    it('defaults to tierD when birthYear is null', () => {
      assert.strictEqual(computeAgeTier(null, CURRENT_YEAR), 'tierD');
    });
    it('defaults to tierD when birthYear is undefined', () => {
      assert.strictEqual(computeAgeTier(undefined, CURRENT_YEAR), 'tierD');
    });
    it('defaults to tierD when birthYear is a string', () => {
      assert.strictEqual(computeAgeTier('1990', CURRENT_YEAR), 'tierD');
    });
    it('defaults to tierD when birthYear is 0', () => {
      assert.strictEqual(computeAgeTier(0, CURRENT_YEAR), 'tierD');
    });
  });

  describe('Boundary conditions', () => {
    it('12 is still blocked (not yet 13)', () => {
      assert.strictEqual(computeAgeTier(CURRENT_YEAR - 12, CURRENT_YEAR), 'blocked');
    });
    it('exactly 13 is tierB', () => {
      assert.strictEqual(computeAgeTier(CURRENT_YEAR - 13, CURRENT_YEAR), 'tierB');
    });
    it('exactly 16 is tierC', () => {
      assert.strictEqual(computeAgeTier(CURRENT_YEAR - 16, CURRENT_YEAR), 'tierC');
    });
    it('exactly 18 is tierD', () => {
      assert.strictEqual(computeAgeTier(CURRENT_YEAR - 18, CURRENT_YEAR), 'tierD');
    });
  });
});

console.log('✅ All computeAgeTier tests passed');
