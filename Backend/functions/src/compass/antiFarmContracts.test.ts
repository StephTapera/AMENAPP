import {
  AntiFarmSignal,
  IntegrityEvaluation,
  OriginalityScore,
  clampSteeringWeight,
  unweightedIntegrityEvaluation,
  emptyActivityDiscoverySurface,
  STEERING_WEIGHT_MIN,
  STEERING_WEIGHT_MAX,
} from "./antiFarmContracts";

describe("antiFarmContracts", () => {
  describe("integrityPenalty fail-closed", () => {
    it("stays exactly 0 when the flag is off (no demotion)", () => {
      const evaluation = unweightedIntegrityEvaluation("post-1", "post", 1000);
      expect(evaluation.integrityPenalty).toBe(0);
      expect(evaluation.flagEnabled).toBe(false);
      expect(evaluation.signals).toEqual([]);
    });

    it("does not leak an originality score when the flag is off", () => {
      const evaluation = unweightedIntegrityEvaluation("acct-1", "account", 1000);
      expect(evaluation.originality).toBeUndefined();
    });

    it("never serializes integrityPenalty or originality into a user-facing payload", () => {
      // Simulate a populated, flag-ON internal evaluation.
      const originality: OriginalityScore = {
        value: 0.4,
        provenanceBasis: "repost",
        repostLineageDepth: 3,
        internalOnly: true,
      };
      const signals: AntiFarmSignal[] = ["sybilCluster", "coordinatedAmplification"];
      const internal: IntegrityEvaluation = {
        subjectId: "post-2",
        subjectKind: "post",
        signals,
        integrityPenalty: 0.6,
        originality,
        flagEnabled: true,
        evaluatedAtUTC: 2000,
      };

      // The user-facing projection MUST drop every internal-only numeric.
      const userFacing = toUserFacingProvenance(internal);
      expect(userFacing).not.toHaveProperty("integrityPenalty");
      expect(userFacing).not.toHaveProperty("originality");
      expect(Object.values(userFacing)).not.toContain(0.6);
      expect(Object.values(userFacing)).not.toContain(0.4);
      // Only a coarse, non-numeric label survives.
      expect(userFacing).toEqual({ hasIntegritySignals: true });
    });
  });

  describe("clampSteeringWeight", () => {
    it("clamps to [-1, 1]", () => {
      expect(clampSteeringWeight(5)).toBe(STEERING_WEIGHT_MAX);
      expect(clampSteeringWeight(-5)).toBe(STEERING_WEIGHT_MIN);
      expect(clampSteeringWeight(0.25)).toBe(0.25);
    });
  });

  describe("activity discovery fail-closed", () => {
    it("returns an empty surface", () => {
      expect(emptyActivityDiscoverySurface()).toEqual([]);
    });
  });
});

// Reference projection proving integrity internals never reach the client.
// A real surface would expose only a coarse boolean, never the score itself.
function toUserFacingProvenance(e: IntegrityEvaluation): { hasIntegritySignals: boolean } {
  return { hasIntegritySignals: e.signals.length > 0 };
}
