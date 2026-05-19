import { buildGentleRegretCopy, calculateIntentGravityScore } from "./livingEntryScoring";
import { evaluateContext } from "./livingEntryContext";
import { classifyWithFallback, heuristicClassification } from "./livingEntryAI";

describe("living entry scoring", () => {
  it("clamps gravity scores", () => {
    const score = calculateIntentGravityScore({
      neglectAgeScore: 10,
      spiritualWeight: 10,
      dueSoonScore: 10,
      churchContextScore: 10,
      reflectionNeedScore: 10,
      regretRisk: 10,
    });
    expect(score).toBe(1);
  });

  it("suppresses non-urgent work on sunday mode", () => {
    const work = calculateIntentGravityScore({ intent: "work", isSunday: true, isDue: false, dueSoonScore: 0.2 });
    const church = calculateIntentGravityScore({ intent: "churchVisit", isSunday: true, isDue: false, churchContextScore: 0.9 });
    expect(church).toBeGreaterThan(work);
  });

  it("does not generate shame copy", () => {
    const copy = buildGentleRegretCopy(0.8).toLowerCase();
    expect(copy).not.toContain("always");
    expect(copy).not.toContain("ignore");
  });
});

describe("living entry context", () => {
  it("raises church entries near church", () => {
    const result = evaluateContext({
      churchId: "church-1",
      nearbyChurchId: "church-1",
      priorityScore: 0.6,
      gravityScore: 0.6,
      spiritualWeight: 0.8,
    });
    expect(result.reasons).toContain("Near church");
    expect(result.surfaceScore).toBeGreaterThan(0.5);
  });
});

describe("living entry ai", () => {
  it("returns safe enum values", async () => {
    const result = heuristicClassification({ title: "Pray for wisdom after church" });
    expect(["note", "reminder", "churchNote", "sermonInsight", "prayer", "followUp", "reflection", "task"]).toContain(result.type);
    expect(["spiritualGrowth", "churchVisit", "sermonReflection", "prayerCare", "relationship", "work", "rest", "personal", "unknown"]).toContain(result.intent);
  });

  it("falls back when primary provider fails", async () => {
    const result = await classifyWithFallback(
      { title: "Sunday visit reminder" },
      async () => { throw new Error("openai down"); },
      async () => heuristicClassification({ title: "Sunday visit reminder" })
    );
    expect(result.provider).toBe("heuristic");
  });
});
