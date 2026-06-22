/**
 * functions/intelligence/tests/formation.test.js
 *
 * AMEN Living Intelligence — Formation Invariant Tests
 *
 * Covers all 7 formation invariants:
 *   FI-1  Briefs are finite (MAX_CARDS_PER_BRIEF = 7)
 *   FI-2  DEVELOPING cards demoted — never first after ranking
 *   FI-3  No spectacle counters on any card
 *   FI-4  Geo is coarse-only
 *   FI-5  Politics filter restricts actions to allowed rungs
 *   FI-6  assertCard throws for no backingEntity
 *   FI-6b assertCard throws for backingEntity.verified === false
 *   FI-6c assertCard throws for GLOBAL card with no source
 *   FI-6d assertCard throws for empty rankReasons
 *   FI-6e assertCard throws for summary.length > 3
 */

"use strict";

const {
  assertCard,
  enforceDigestCadence,
  enforceBriefCap,
  stripSpectacleCounters,
  enforceGeo,
  enforcePoliticsFilter,
  assertLoopClosure,
  MAX_CARDS_PER_BRIEF,
} = require('../formationGovernor');
const { ACTION_RUNG, TRUTH_LEVEL } = require('../contracts');

// ─── Fixtures ─────────────────────────────────────────────────────────────────

/** Minimal valid IntelligenceCard for testing */
function makeCard(overrides = {}) {
  const now = Date.now();
  return {
    id: 'test_card_1',
    tier: 'LOCAL',
    title: 'Community Food Drive',
    summary: ['Local church needs volunteers'],
    backingEntity: {
      kind: 'CHURCH',
      id: 'church_abc123',
      verified: true,
    },
    truthLevel: TRUTH_LEVEL.CHURCH_CONFIRMED,
    actions: [
      {
        rung: ACTION_RUNG.SHOW_UP,
        label: 'Sign up to help',
        handler: 'rsvpToChurchEvent',
        target: 'event_xyz',
      },
    ],
    rankScore: 72,
    rankReasons: ['Your church', 'Seasonally relevant'],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    createdAt: now,
    expiresAt: now + 3600 * 1000,
    ...overrides,
  };
}

/**
 * Build an array of N valid cards, each with a unique id.
 * If developingAt indices are provided, those positions get DEVELOPING truthLevel.
 */
function makeCards(count, developingAt = []) {
  const now = Date.now();
  return Array.from({ length: count }, (_, i) => ({
    id: `card_${i}`,
    tier: 'LOCAL',
    title: `Card ${i}`,
    summary: [`Summary for card ${i}`],
    backingEntity: {
      kind: 'CHURCH',
      id: `church_${i}`,
      verified: true,
    },
    truthLevel: developingAt.includes(i) ? TRUTH_LEVEL.DEVELOPING : TRUTH_LEVEL.CHURCH_CONFIRMED,
    actions: [
      {
        rung: ACTION_RUNG.PRAY,
        label: 'Pray',
        handler: 'recordIntelligenceAction',
        target: `entity_${i}`,
      },
    ],
    rankScore: 80 - i,   // descending scores so order is deterministic
    rankReasons: ['Relevant to your community'],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    createdAt: now,
    expiresAt: now + 3600 * 1000,
  }));
}

// ─── Test Suite ───────────────────────────────────────────────────────────────

describe('Formation Invariant Tests — FI-1 through FI-7', () => {

  // ── FI-1: Brief is finite ──────────────────────────────────────────────────

  describe('FI-1: Brief is finite (MAX_CARDS_PER_BRIEF)', () => {
    test('enforceBriefCap returns at most MAX_CARDS_PER_BRIEF cards when given more', () => {
      const cards = makeCards(15);
      const result = enforceBriefCap(cards);
      expect(result.length).toBeLessThanOrEqual(MAX_CARDS_PER_BRIEF);
      expect(result.length).toBe(MAX_CARDS_PER_BRIEF);
    });

    test('enforceBriefCap returns all cards when given fewer than cap', () => {
      const cards = makeCards(3);
      const result = enforceBriefCap(cards);
      expect(result.length).toBe(3);
    });

    test('enforceBriefCap returns empty array for empty input', () => {
      expect(enforceBriefCap([])).toEqual([]);
    });

    test('MAX_CARDS_PER_BRIEF equals 7', () => {
      expect(MAX_CARDS_PER_BRIEF).toBe(7);
    });
  });

  // ── FI-2: DEVELOPING cards demoted ────────────────────────────────────────

  describe('FI-2: DEVELOPING cards are never first after enforceBriefCap', () => {
    test('DEVELOPING card at index 0 is demoted behind non-DEVELOPING cards', () => {
      // All cards except the last 3 are DEVELOPING
      const cards = makeCards(5, [0, 1]);  // first two have DEVELOPING
      const result = enforceBriefCap(cards);

      // After cap, first card should be non-DEVELOPING
      expect(result[0].truthLevel).not.toBe(TRUTH_LEVEL.DEVELOPING);
    });

    test('When all cards are DEVELOPING, they are still returned but in original order', () => {
      const cards = makeCards(3, [0, 1, 2]);
      const result = enforceBriefCap(cards);
      expect(result.length).toBe(3);
      // All are DEVELOPING — they should all still be present
      result.forEach((c) => expect(c.truthLevel).toBe(TRUTH_LEVEL.DEVELOPING));
    });

    test('Mixed: non-DEVELOPING cards come before DEVELOPING in result', () => {
      // Cards at positions 2 and 4 are DEVELOPING; rest are confirmed
      const cards = makeCards(6, [2, 4]);
      const result = enforceBriefCap(cards);

      // Find the last non-DEVELOPING and the first DEVELOPING in result
      let lastNonDev = -1;
      let firstDev = result.length;

      for (let i = 0; i < result.length; i++) {
        if (result[i].truthLevel !== TRUTH_LEVEL.DEVELOPING) lastNonDev = i;
        else if (firstDev === result.length) firstDev = i;
      }

      // If there are both non-DEVELOPING and DEVELOPING, all non-DEVELOPING come first
      if (lastNonDev !== -1 && firstDev < result.length) {
        expect(lastNonDev).toBeLessThan(firstDev);
      }
    });
  });

  // ── FI-3: No spectacle counters ────────────────────────────────────────────

  describe('FI-3: stripSpectacleCounters removes all engagement counter fields', () => {
    test('removes prayingCount from card', () => {
      const card = makeCard({ prayingCount: 42 });
      const cleaned = stripSpectacleCounters(card);
      expect(cleaned.prayingCount).toBeUndefined();
    });

    test('removes viewCount from card', () => {
      const card = makeCard({ viewCount: 1000 });
      const cleaned = stripSpectacleCounters(card);
      expect(cleaned.viewCount).toBeUndefined();
    });

    test('removes likeCount, shareCount, commentCount, reactionCount', () => {
      const card = makeCard({
        likeCount: 10,
        shareCount: 5,
        commentCount: 3,
        reactionCount: 7,
      });
      const cleaned = stripSpectacleCounters(card);
      expect(cleaned.likeCount).toBeUndefined();
      expect(cleaned.shareCount).toBeUndefined();
      expect(cleaned.commentCount).toBeUndefined();
      expect(cleaned.reactionCount).toBeUndefined();
    });

    test('does not modify other fields', () => {
      const card = makeCard({ title: 'Test Title', prayingCount: 5 });
      const cleaned = stripSpectacleCounters(card);
      expect(cleaned.title).toBe('Test Title');
    });

    test('removes spectacle counters from backingEntity', () => {
      const card = makeCard({
        backingEntity: {
          kind: 'CHURCH',
          id: 'church_1',
          verified: true,
          followerCount: 5000,
        },
      });
      const cleaned = stripSpectacleCounters(card);
      expect(cleaned.backingEntity.followerCount).toBeUndefined();
      expect(cleaned.backingEntity.kind).toBe('CHURCH');
    });

    test('does not mutate the original card', () => {
      const card = makeCard({ prayingCount: 99 });
      stripSpectacleCounters(card);
      expect(card.prayingCount).toBe(99);
    });
  });

  // ── FI-4: Geo enforcement ──────────────────────────────────────────────────

  describe('FI-4: enforceGeo produces coarse-only coordinates', () => {
    test('rounds precise coordinates to 2 decimal places', () => {
      const card = makeCard({
        geo: { lat: 37.774929, lng: -122.419416, coarse: false },
      });
      const result = enforceGeo(card);
      expect(result.geo.lat).toBe(37.77);
      expect(result.geo.lng).toBe(-122.42);
    });

    test('sets coarse: true on geo field', () => {
      const card = makeCard({
        geo: { lat: 37.774929, lng: -122.419416, coarse: false },
      });
      const result = enforceGeo(card);
      expect(result.geo.coarse).toBe(true);
    });

    test('strips extra fields from geo (keeping only lat, lng, coarse)', () => {
      const card = makeCard({
        geo: {
          lat: 40.7128,
          lng: -74.0060,
          coarse: false,
          altitude: 10,
          accuracy: 5,
          address: '123 Main St',
        },
      });
      const result = enforceGeo(card);
      expect(Object.keys(result.geo)).toEqual(['lat', 'lng', 'coarse']);
    });

    test('strips geo entirely when lat/lng are invalid', () => {
      const card = makeCard({
        geo: { lat: 'invalid', lng: 'bad', coarse: false },
      });
      const result = enforceGeo(card);
      expect(result.geo).toBeUndefined();
    });

    test('returns card unchanged when geo is absent', () => {
      const card = makeCard();
      const result = enforceGeo(card);
      expect(result.geo).toBeUndefined();
    });

    test('assertCard throws if geo.coarse is not true', () => {
      const now = Date.now();
      const card = makeCard({
        geo: { lat: 37.77, lng: -122.42, coarse: false },
      });
      expect(() => assertCard(card)).toThrow(/coarse/);
    });

    test('assertCard passes for card with coarse geo', () => {
      const card = makeCard({
        geo: { lat: 37.77, lng: -122.42, coarse: true },
      });
      expect(() => assertCard(card)).not.toThrow();
    });
  });

  // ── FI-5: Politics filter ──────────────────────────────────────────────────

  describe('FI-5: enforcePoliticsFilter restricts actions on political content', () => {
    test('removes non-allowed rungs when title contains "election"', () => {
      const card = makeCard({
        title: 'Local election update: how to pray',
        actions: [
          { rung: ACTION_RUNG.NOTICE, label: 'Notice', handler: 'noop', target: 't1' },
          { rung: ACTION_RUNG.PRAY,   label: 'Pray',   handler: 'noop', target: 't1' },
          { rung: ACTION_RUNG.LEARN,  label: 'Learn',  handler: 'noop', target: 't1' },
          { rung: ACTION_RUNG.GIVE,   label: 'Give',   handler: 'noop', target: 't1' },
          { rung: ACTION_RUNG.START,  label: 'Start',  handler: 'noop', target: 't1' },
        ],
      });
      const result = enforcePoliticsFilter(card);
      const rungs = result.actions.map((a) => a.rung);
      expect(rungs).not.toContain(ACTION_RUNG.NOTICE);
      expect(rungs).not.toContain(ACTION_RUNG.LEARN);
      expect(rungs).not.toContain(ACTION_RUNG.START);
      expect(rungs).toContain(ACTION_RUNG.PRAY);
      expect(rungs).toContain(ACTION_RUNG.GIVE);
    });

    test('removes non-allowed rungs when summary contains "partisan"', () => {
      const card = makeCard({
        title: 'Community Update',
        summary: ['This debate has become partisan in nature'],
        actions: [
          { rung: ACTION_RUNG.NOTICE,  label: 'Notice',  handler: 'noop', target: 't' },
          { rung: ACTION_RUNG.DISCUSS, label: 'Discuss', handler: 'noop', target: 't' },
          { rung: ACTION_RUNG.SHOW_UP, label: 'Show Up', handler: 'noop', target: 't' },
        ],
      });
      const result = enforcePoliticsFilter(card);
      const rungs = result.actions.map((a) => a.rung);
      expect(rungs).not.toContain(ACTION_RUNG.NOTICE);
      expect(rungs).toContain(ACTION_RUNG.DISCUSS);
      expect(rungs).toContain(ACTION_RUNG.SHOW_UP);
    });

    test('does not filter non-political cards', () => {
      const card = makeCard({
        title: 'Community Harvest Festival',
        actions: [
          { rung: ACTION_RUNG.NOTICE,  label: 'Notice',  handler: 'noop', target: 't' },
          { rung: ACTION_RUNG.SHOW_UP, label: 'Show Up', handler: 'noop', target: 't' },
          { rung: ACTION_RUNG.START,   label: 'Start',   handler: 'noop', target: 't' },
        ],
      });
      const result = enforcePoliticsFilter(card);
      expect(result.actions.length).toBe(3);
    });

    test('treats "vote" as a politics keyword', () => {
      const card = makeCard({
        title: 'How to vote as a Christian',
        actions: [
          { rung: ACTION_RUNG.NOTICE, label: 'Notice', handler: 'noop', target: 't' },
          { rung: ACTION_RUNG.PRAY,   label: 'Pray',   handler: 'noop', target: 't' },
        ],
      });
      const result = enforcePoliticsFilter(card);
      expect(result.actions.some((a) => a.rung === ACTION_RUNG.NOTICE)).toBe(false);
      expect(result.actions.some((a) => a.rung === ACTION_RUNG.PRAY)).toBe(true);
    });
  });

  // ── FI-6: assertCard backingEntity invariants ───────────────────────────────

  describe('FI-6: assertCard throws for missing or unverified backingEntity', () => {
    test('throws when backingEntity is absent', () => {
      const card = makeCard();
      delete card.backingEntity;
      expect(() => assertCard(card)).toThrow(/backingEntity/i);
    });

    test('throws when backingEntity is null', () => {
      const card = makeCard({ backingEntity: null });
      expect(() => assertCard(card)).toThrow(/backingEntity/i);
    });

    test('throws when backingEntity.verified is false', () => {
      const card = makeCard({
        backingEntity: { kind: 'CHURCH', id: 'church_1', verified: false },
      });
      expect(() => assertCard(card)).toThrow(/verified/i);
    });

    test('throws when backingEntity.verified is undefined', () => {
      const card = makeCard({
        backingEntity: { kind: 'CHURCH', id: 'church_1' },
      });
      expect(() => assertCard(card)).toThrow(/verified/i);
    });

    test('passes for valid backingEntity', () => {
      const card = makeCard();
      expect(() => assertCard(card)).not.toThrow();
    });
  });

  // ── FI-6c: GLOBAL card source requirement ──────────────────────────────────

  describe('FI-6c: assertCard throws for GLOBAL card with no source', () => {
    test('throws for GLOBAL card with no source field', () => {
      const card = makeCard({ tier: 'GLOBAL' });
      delete card.source;
      expect(() => assertCard(card)).toThrow(/source/i);
    });

    test('throws for GLOBAL card with empty source string', () => {
      const card = makeCard({ tier: 'GLOBAL', source: '' });
      expect(() => assertCard(card)).toThrow(/source/i);
    });

    test('passes for GLOBAL card with valid source', () => {
      const card = makeCard({
        tier: 'GLOBAL',
        source: 'Reuters',
      });
      expect(() => assertCard(card)).not.toThrow();
    });

    test('non-GLOBAL card does not require source', () => {
      const card = makeCard({ tier: 'LOCAL' });
      delete card.source;
      expect(() => assertCard(card)).not.toThrow();
    });
  });

  // ── FI-6d: rankReasons required ────────────────────────────────────────────

  describe('FI-6d: assertCard throws for empty rankReasons', () => {
    test('throws when rankReasons is empty array', () => {
      const card = makeCard({ rankReasons: [] });
      expect(() => assertCard(card)).toThrow(/rankReasons/i);
    });

    test('throws when rankReasons is missing', () => {
      const card = makeCard();
      delete card.rankReasons;
      expect(() => assertCard(card)).toThrow(/rankReasons/i);
    });

    test('throws when rankReasons is not an array', () => {
      const card = makeCard({ rankReasons: 'some string' });
      expect(() => assertCard(card)).toThrow(/rankReasons/i);
    });

    test('passes when rankReasons has at least one entry', () => {
      const card = makeCard({ rankReasons: ['Your church'] });
      expect(() => assertCard(card)).not.toThrow();
    });
  });

  // ── FI-6e: summary.length <= 3 ─────────────────────────────────────────────

  describe('FI-6e: assertCard throws for summary.length > 3', () => {
    test('throws when summary has 4 bullets', () => {
      const card = makeCard({
        summary: ['Bullet 1', 'Bullet 2', 'Bullet 3', 'Bullet 4'],
      });
      expect(() => assertCard(card)).toThrow(/summary/i);
    });

    test('passes for summary with 3 bullets', () => {
      const card = makeCard({
        summary: ['Bullet 1', 'Bullet 2', 'Bullet 3'],
      });
      expect(() => assertCard(card)).not.toThrow();
    });

    test('passes for summary with 1 bullet', () => {
      const card = makeCard({ summary: ['Single bullet'] });
      expect(() => assertCard(card)).not.toThrow();
    });

    test('throws when summary is not an array', () => {
      const card = makeCard({ summary: 'Not an array' });
      expect(() => assertCard(card)).toThrow(/summary/i);
    });
  });

  // ── Additional invariants ─────────────────────────────────────────────────

  describe('Additional: assertCard — actions, formation, timestamps, DEVELOPING rank', () => {
    test('throws when actions is empty', () => {
      const card = makeCard({ actions: [] });
      expect(() => assertCard(card)).toThrow(/actions/i);
    });

    test('throws when formation.finite is not true', () => {
      const card = makeCard({
        formation: { finite: false, spectacleCounters: false },
      });
      expect(() => assertCard(card)).toThrow(/finite/i);
    });

    test('throws when formation.spectacleCounters is true', () => {
      const card = makeCard({
        formation: { finite: true, spectacleCounters: true },
      });
      expect(() => assertCard(card)).toThrow(/spectacle/i);
    });

    test('throws when expiresAt <= createdAt', () => {
      const now = Date.now();
      const card = makeCard({ createdAt: now, expiresAt: now });
      expect(() => assertCard(card)).toThrow(/expiresAt/i);
    });

    test('throws when DEVELOPING card has rankScore > 80', () => {
      const card = makeCard({
        truthLevel: TRUTH_LEVEL.DEVELOPING,
        rankScore: 81,
      });
      expect(() => assertCard(card)).toThrow(/DEVELOPING/i);
    });

    test('passes when DEVELOPING card has rankScore exactly 80', () => {
      const card = makeCard({
        truthLevel: TRUTH_LEVEL.DEVELOPING,
        rankScore: 80,
      });
      expect(() => assertCard(card)).not.toThrow();
    });
  });

  // ── assertLoopClosure ─────────────────────────────────────────────────────

  describe('assertLoopClosure: loop resolution tracking', () => {
    test('returns empty resolved/unresolved for no prior actions', () => {
      const cards = makeCards(3);
      const result = assertLoopClosure(cards, []);
      expect(result.resolved).toEqual([]);
      expect(result.unresolved).toEqual([]);
    });

    test('marks prior action as resolved when card has matching loopParentId', () => {
      const cards = makeCards(3);
      // Add loop parent to first card
      cards[0].formation.loopParentId = 'prior_action_abc';
      const result = assertLoopClosure(cards, ['prior_action_abc']);
      expect(result.resolved).toContain('prior_action_abc');
      expect(result.unresolved).not.toContain('prior_action_abc');
    });

    test('marks prior action as unresolved when no card references it', () => {
      const cards = makeCards(3);
      const result = assertLoopClosure(cards, ['prior_action_xyz']);
      expect(result.unresolved).toContain('prior_action_xyz');
    });
  });

});
