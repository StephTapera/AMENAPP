/**
 * intelligence.formationGovernor.test.ts
 *
 * Verifier-Agent: CHECK 5 — Formation Governor Invariants
 *
 * Tests all 7 FORMATION_INVARIANTS from contracts.ts:
 *   1. FINITE_BRIEF            — enforceCardCap truncates to MAX_CARDS_PER_BRIEF (7)
 *   2. DIGEST_CADENCE_MAX_PER_DAY — constant must equal 2
 *   3. NO_SPECTACLE_COUNTERS   — hasSpectacleCounters returns false for a valid card
 *   4. DEVELOPING_NEVER_TOP    — isDevelopingTopRanked catches the violation
 *   5. POLITICS_ROUTE_ONLY     — isPoliticsRoutedCorrectly enforces PRAY/SHOW_UP/GIVE only
 *   6. LOOP_CLOSING_REQUIRED   — validateBrief flags cards without rankReasons (proxy check)
 *   7. COARSE_GEO_ONLY         — geo without coarse:true fails validation
 *
 * Plus:
 *   - validateBrief([]) is valid
 *   - enforceCardCap places DEVELOPING cards last
 *   - validateBrief catches a DEVELOPING card at position 0
 *
 * NOTE: This project uses Jest (not Vitest). The task requested a Vitest file;
 * the tests are written using Jest so they run with the existing test runner.
 * The test structure is identical to how Vitest describe/test/expect works.
 */

import {
  enforceCardCap,
  isDevelopingTopRanked,
  isPoliticsRoutedCorrectly,
  hasSpectacleCounters,
  validateBrief,
} from "../intelligence/formationGovernor";

import {
  IntelligenceCard,
  FORMATION_INVARIANTS,
  MAX_CARDS_PER_BRIEF,
} from "../intelligence/contracts";

// ─── Card factory ─────────────────────────────────────────────────────────────

function makeCard(overrides: Partial<IntelligenceCard> = {}): IntelligenceCard {
  return {
    id: "test_card",
    tier: "COMMUNITY",
    title: "Test Card",
    summary: ["Bullet 1", "Bullet 2"],
    backingEntity: { kind: "CHURCH", id: "church_abc", verified: true },
    truthLevel: "VERIFIED",
    actions: [
      { rung: "PRAY", label: "Pray", handler: "action.addToPrayer", target: "target_1" },
    ],
    rankScore: 50,
    rankReasons: ["Community activity"],
    formation: {
      finite: true,
      spectacleCounters: false,
    },
    createdAt: Date.now() - 60_000,
    expiresAt: Date.now() + 86_400_000,
    ...overrides,
  };
}

function makeDevelopingCard(id = "developing_card"): IntelligenceCard {
  return makeCard({
    id,
    truthLevel: "DEVELOPING",
    tier: "GLOBAL",
    source: "Reuters",
    actions: [
      { rung: "PRAY", label: "Pray", handler: "action.addToPrayer", target: "target_dev" },
    ],
  });
}

function makeGlobalPoliticsCard(
  id = "politics_card",
  extraActions: IntelligenceCard["actions"] = []
): IntelligenceCard {
  return makeCard({
    id,
    tier: "GLOBAL",
    source: "Contested: worldnews",
    actions: [
      { rung: "PRAY",    label: "Pray",    handler: "action.addToPrayer", target: id },
      { rung: "SHOW_UP", label: "Show Up", handler: "action.volunteer",   target: id },
      { rung: "GIVE",    label: "Give",    handler: "action.giveToNeed",  target: id },
      ...extraActions,
    ],
  });
}

// ─── 1. FINITE_BRIEF: enforceCardCap truncates to MAX_CARDS_PER_BRIEF (7) ─────

describe("INVARIANT 1: FINITE_BRIEF — enforceCardCap", () => {
  test("MAX_CARDS_PER_BRIEF constant is 7", () => {
    expect(MAX_CARDS_PER_BRIEF).toBe(7);
  });

  test("truncates a list of 10 cards to 7", () => {
    const cards = Array.from({ length: 10 }, (_, i) => makeCard({ id: `card_${i}` }));
    const result = enforceCardCap(cards);
    expect(result).toHaveLength(MAX_CARDS_PER_BRIEF);
  });

  test("returns all cards untouched when count is exactly 7", () => {
    const cards = Array.from({ length: 7 }, (_, i) => makeCard({ id: `card_${i}` }));
    const result = enforceCardCap(cards);
    expect(result).toHaveLength(7);
  });

  test("returns all cards untouched when count is under 7", () => {
    const cards = Array.from({ length: 4 }, (_, i) => makeCard({ id: `card_${i}` }));
    const result = enforceCardCap(cards);
    expect(result).toHaveLength(4);
  });

  test("returns empty array for empty input", () => {
    expect(enforceCardCap([])).toHaveLength(0);
  });
});

// ─── 2. DIGEST_CADENCE_MAX_PER_DAY constant ───────────────────────────────────

describe("INVARIANT 2: DIGEST_CADENCE_MAX_PER_DAY constant", () => {
  test("DIGEST_CADENCE_MAX_PER_DAY is 2", () => {
    expect(FORMATION_INVARIANTS.DIGEST_CADENCE_MAX_PER_DAY).toBe(2);
  });
});

// ─── 3. NO_SPECTACLE_COUNTERS ─────────────────────────────────────────────────

describe("INVARIANT 3: NO_SPECTACLE_COUNTERS — hasSpectacleCounters", () => {
  test("returns false for a valid card (spectacleCounters: false)", () => {
    const card = makeCard();
    expect(hasSpectacleCounters(card)).toBe(false);
  });

  test("returns true when spectacleCounters is coerced to true at runtime", () => {
    // The contract types spectacleCounters as literal false; this tests runtime violation detection.
    const card = makeCard({
      formation: {
        finite: true,
        // Cast to trigger the runtime check
        spectacleCounters: true as unknown as false,
      },
    });
    expect(hasSpectacleCounters(card)).toBe(true);
  });

  test("validateBrief catches a card where spectacleCounters is true at runtime", () => {
    const card = makeCard({
      id: "spectacle_violator",
      formation: {
        finite: true,
        spectacleCounters: true as unknown as false,
      },
    });
    const { valid, violations } = validateBrief([card]);
    expect(valid).toBe(false);
    expect(violations.some((v) => v.includes("NO_SPECTACLE_COUNTERS"))).toBe(true);
  });
});

// ─── 4. DEVELOPING_NEVER_TOP ──────────────────────────────────────────────────

describe("INVARIANT 4: DEVELOPING_NEVER_TOP", () => {
  test("isDevelopingTopRanked returns true when DEVELOPING is first (violation detected)", () => {
    const developing = makeDevelopingCard("dev_first");
    const normal = makeCard({ id: "normal_1" });
    expect(isDevelopingTopRanked([developing, normal])).toBe(true);
  });

  test("isDevelopingTopRanked returns false when DEVELOPING is last", () => {
    const normal1 = makeCard({ id: "normal_1" });
    const normal2 = makeCard({ id: "normal_2" });
    const developing = makeDevelopingCard("dev_last");
    expect(isDevelopingTopRanked([normal1, normal2, developing])).toBe(false);
  });

  test("isDevelopingTopRanked returns false for an empty list", () => {
    expect(isDevelopingTopRanked([])).toBe(false);
  });

  test("isDevelopingTopRanked returns false when first card is VERIFIED", () => {
    const verified = makeCard({ id: "verified_card", truthLevel: "VERIFIED" });
    const developing = makeDevelopingCard();
    expect(isDevelopingTopRanked([verified, developing])).toBe(false);
  });

  test("validateBrief returns a DEVELOPING_NEVER_TOP violation when DEVELOPING card is at position 0", () => {
    const developing = makeDevelopingCard("dev_top");
    const normal = makeCard({ id: "normal_behind" });
    const { valid, violations } = validateBrief([developing, normal]);
    expect(valid).toBe(false);
    expect(violations.some((v) => v.includes("DEVELOPING_NEVER_TOP"))).toBe(true);
  });

  test("enforceCardCap places DEVELOPING cards last (not first)", () => {
    const developing = makeDevelopingCard("dev_card");
    const normal1 = makeCard({ id: "normal_a" });
    const normal2 = makeCard({ id: "normal_b" });

    // Put developing first in input — enforceCardCap must push it to the end
    const result = enforceCardCap([developing, normal1, normal2]);
    expect(result[result.length - 1].truthLevel).toBe("DEVELOPING");
    expect(result[0].truthLevel).not.toBe("DEVELOPING");
  });
});

// ─── 5. POLITICS_ROUTE_ONLY ───────────────────────────────────────────────────

describe("INVARIANT 5: POLITICS_ROUTE_ONLY", () => {
  test("POLITICS_ROUTE_ONLY constant lists PRAY, SHOW_UP, GIVE", () => {
    expect(FORMATION_INVARIANTS.POLITICS_ROUTE_ONLY).toEqual(
      expect.arrayContaining(["PRAY", "SHOW_UP", "GIVE"])
    );
    expect(FORMATION_INVARIANTS.POLITICS_ROUTE_ONLY).toHaveLength(3);
  });

  test("isPoliticsRoutedCorrectly returns false for a GLOBAL contested card with a LEARN action", () => {
    const card = makeGlobalPoliticsCard("politics_learn", [
      { rung: "LEARN", label: "Learn More", handler: "action.openStudy", target: "target" },
    ]);
    // The card has LEARN which is not in the allowed set, and source contains "contested"
    expect(isPoliticsRoutedCorrectly(card)).toBe(false);
  });

  test("isPoliticsRoutedCorrectly returns true for a GLOBAL card with only PRAY/SHOW_UP/GIVE", () => {
    const card = makeGlobalPoliticsCard("politics_ok");
    // Source "Contested: worldnews" triggers isPoliticsCard; actions are all allowed
    expect(isPoliticsRoutedCorrectly(card)).toBe(true);
  });

  test("validateBrief flags GLOBAL card with LEARN action (POLITICS_ROUTE_ONLY violation)", () => {
    const card = makeGlobalPoliticsCard("politics_violator", [
      { rung: "LEARN", label: "Learn More", handler: "action.openStudy", target: "t" },
    ]);
    const { valid, violations } = validateBrief([card]);
    expect(valid).toBe(false);
    expect(violations.some((v) => v.includes("POLITICS_ROUTE_ONLY"))).toBe(true);
  });

  test("isPoliticsRoutedCorrectly returns true for a non-GLOBAL card (rule does not apply)", () => {
    const communityCard = makeCard({
      id: "community_card",
      tier: "COMMUNITY",
      actions: [
        { rung: "LEARN", label: "Learn More", handler: "action.openStudy", target: "t" },
      ],
    });
    expect(isPoliticsRoutedCorrectly(communityCard)).toBe(true);
  });
});

// ─── 6. LOOP_CLOSING_REQUIRED ─────────────────────────────────────────────────

describe("INVARIANT 6: LOOP_CLOSING_REQUIRED", () => {
  /**
   * The formationGovernor implements loop_closing as a rankReasons check:
   * every card must have non-empty rankReasons (the proxy for explaining why it surfaced,
   * which is the loop-closing contract). This is documented in the source code.
   */
  test("LOOP_CLOSING_REQUIRED constant is true in FORMATION_INVARIANTS", () => {
    expect(FORMATION_INVARIANTS.LOOP_CLOSING_REQUIRED).toBe(true);
  });

  test("validateBrief flags a card with empty rankReasons (loop_closing proxy violation)", () => {
    const card = makeCard({ id: "no_rank_reasons", rankReasons: [] });
    const { valid, violations } = validateBrief([card]);
    expect(valid).toBe(false);
    expect(violations.some((v) => v.includes("LOOP_CLOSING_REQUIRED"))).toBe(true);
  });

  test("validateBrief passes a card that has rankReasons populated", () => {
    const card = makeCard({
      id: "has_rank_reasons",
      rankReasons: ["From your church", "Active this week"],
    });
    const { violations } = validateBrief([card]);
    expect(violations.filter((v) => v.includes("LOOP_CLOSING_REQUIRED"))).toHaveLength(0);
  });
});

// ─── 7. COARSE_GEO_ONLY ───────────────────────────────────────────────────────

describe("INVARIANT 7: COARSE_GEO_ONLY", () => {
  test("COARSE_GEO_ONLY constant is true in FORMATION_INVARIANTS", () => {
    expect(FORMATION_INVARIANTS.COARSE_GEO_ONLY).toBe(true);
  });

  test("validateBrief passes a card with no geo field", () => {
    const card = makeCard({ id: "no_geo", geo: undefined });
    const { violations } = validateBrief([card]);
    expect(violations.filter((v) => v.includes("COARSE_GEO_ONLY"))).toHaveLength(0);
  });

  test("validateBrief passes a card with geo.coarse = true", () => {
    const card = makeCard({
      id: "coarse_geo",
      geo: { lat: 40.7, lng: -74.0, coarse: true },
    });
    const { violations } = validateBrief([card]);
    expect(violations.filter((v) => v.includes("COARSE_GEO_ONLY"))).toHaveLength(0);
  });

  test("validateBrief flags a card with geo where coarse is missing/false", () => {
    const card = makeCard({
      id: "precise_geo",
      // Cast to bypass TypeScript's literal type — simulates a runtime violation
      geo: { lat: 40.7128, lng: -74.006, coarse: false } as unknown as { lat: number; lng: number; coarse: true },
    });
    const { valid, violations } = validateBrief([card]);
    expect(valid).toBe(false);
    expect(violations.some((v) => v.includes("COARSE_GEO_ONLY"))).toBe(true);
  });
});

// ─── Additional assertions ─────────────────────────────────────────────────────

describe("validateBrief — additional assertions", () => {
  test("validateBrief([]) returns { valid: true, violations: [] } for an empty brief", () => {
    const result = validateBrief([]);
    expect(result.valid).toBe(true);
    expect(result.violations).toHaveLength(0);
  });

  test("validateBrief passes a single well-formed card", () => {
    const card = makeCard({ id: "well_formed" });
    const { valid, violations } = validateBrief([card]);
    expect(valid).toBe(true);
    expect(violations).toHaveLength(0);
  });

  test("validateBrief catches more than MAX_CARDS_PER_BRIEF cards (FINITE_BRIEF)", () => {
    const cards = Array.from({ length: 8 }, (_, i) => makeCard({ id: `card_${i}` }));
    const { valid, violations } = validateBrief(cards);
    expect(valid).toBe(false);
    expect(violations.some((v) => v.includes("FINITE_BRIEF"))).toBe(true);
  });

  test("validateBrief catches multiple violations in a single call", () => {
    const badCard = makeCard({
      id: "multi_violator",
      rankReasons: [],
      formation: {
        finite: true,
        spectacleCounters: true as unknown as false,
      },
    });
    const developingFirst = makeDevelopingCard("dev_top_multi");
    const { valid, violations } = validateBrief([developingFirst, badCard]);

    expect(valid).toBe(false);
    expect(violations.length).toBeGreaterThanOrEqual(3); // DEVELOPING_NEVER_TOP + NO_SPECTACLE_COUNTERS + LOOP_CLOSING_REQUIRED
    expect(violations.some((v) => v.includes("DEVELOPING_NEVER_TOP"))).toBe(true);
    expect(violations.some((v) => v.includes("NO_SPECTACLE_COUNTERS"))).toBe(true);
    expect(violations.some((v) => v.includes("LOOP_CLOSING_REQUIRED"))).toBe(true);
  });
});
