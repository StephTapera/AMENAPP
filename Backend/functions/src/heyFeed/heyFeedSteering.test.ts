// heyFeed/heyFeedSteering.test.ts
// Wave 0 contract invariants for HeyFeed v2 steering. Pure-function tests — no Firestore, no network.

import {
  STEER_CLAMP,
  clampSteering,
  effectiveRiskThreshold,
  failClosedFloorVerdict,
  isFloorTargetForbidden,
  SAFETY_FLOOR_CATEGORIES,
  SafetyFloorCategory,
  SteeringTarget,
} from "./heyFeedSteering";

describe("HeyFeed v2 steering clamp", () => {
  it("clamp constant is exactly 0.35", () => {
    expect(STEER_CLAMP).toBe(0.35);
  });

  it("clamps positive boosts to +STEER_CLAMP", () => {
    expect(clampSteering(0.9)).toBe(0.35);
    expect(clampSteering(0.35)).toBe(0.35);
  });

  it("clamps negative demotions to -STEER_CLAMP", () => {
    expect(clampSteering(-0.9)).toBe(-0.35);
    expect(clampSteering(-0.35)).toBe(-0.35);
  });

  it("passes through values within the band unchanged", () => {
    expect(clampSteering(0.1)).toBeCloseTo(0.1);
    expect(clampSteering(-0.2)).toBeCloseTo(-0.2);
    expect(clampSteering(0)).toBe(0);
  });
});

describe("SafetyFloor is non-overridable", () => {
  it("a user threshold may only make the feed STRICTER, never laxer", () => {
    const ceiling = 0.3;
    // User asks for a laxer threshold (0.9) — floor wins (0.3).
    expect(effectiveRiskThreshold(0.9, ceiling)).toBe(0.3);
    // User asks for a stricter threshold (0.1) — user choice honored (0.1).
    expect(effectiveRiskThreshold(0.1, ceiling)).toBe(0.1);
    // Equal — unchanged.
    expect(effectiveRiskThreshold(0.3, ceiling)).toBe(0.3);
  });

  it("isFloorTargetForbidden is true for every floor category", () => {
    for (const category of SAFETY_FLOOR_CATEGORIES) {
      const target: SteeringTarget = {
        id: category,
        type: "topic",
        label: category,
      };
      expect(isFloorTargetForbidden(target)).toBe(true);
    }
  });

  it("does not forbid an ordinary, non-floor steering target", () => {
    const benign: SteeringTarget = {
      id: "testimonies",
      type: "topic",
      label: "Testimonies",
    };
    expect(isFloorTargetForbidden(benign)).toBe(false);
  });

  it("catches floor categories embedded in a target label", () => {
    const sneaky: SteeringTarget = {
      id: "edgy",
      type: "tone",
      label: "More violence please",
    };
    expect(isFloorTargetForbidden(sneaky)).toBe(true);
  });
});

describe("fail-closed verdict", () => {
  it("an unevaluable post is never allowed", () => {
    const verdict = failClosedFloorVerdict("post_123");
    expect(verdict.allowed).toBe(false);
    expect(verdict.isMinorShielded).toBe(false);
    expect(verdict.reasons).toContain("unevaluable");
    expect(verdict.postId).toBe("post_123");
  });
});

describe("floor category coverage", () => {
  it("includes childSafety and csam at the front of the frozen list", () => {
    const categories: SafetyFloorCategory[] = [...SAFETY_FLOOR_CATEGORIES];
    expect(categories).toContain("childSafety");
    expect(categories).toContain("csam");
    expect(Object.isFrozen(SAFETY_FLOOR_CATEGORIES)).toBe(true);
  });
});
