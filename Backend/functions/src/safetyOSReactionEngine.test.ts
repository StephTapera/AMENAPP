import {analyzeSafetyOSText} from "./safetyOSReactionEngine";

describe("Safety OS reaction engine", () => {
  it("returns multiple canonical triggers without raw text", () => {
    const results = analyzeSafetyOSText("Psalm 139 helped me. Please pray for me.", "comment");
    expect(results.map((item) => item.type)).toEqual(expect.arrayContaining(["scriptureReference", "prayerRequest"]));
    expect(JSON.stringify(results)).not.toContain("Psalm 139 helped me");
  });

  it("prioritizes shame tone and keeps post-anyway available", () => {
    const results = analyzeSafetyOSText("You should be ashamed of yourself. Romans 8 matters.", "comment");
    expect(results[0].type).toBe("shameTone");
    expect(results[0].shouldShowDiscernmentSheet).toBe(true);
    expect(results[0].recommendedActions).toContain("postAnyway");
  });

  it("does not expose visual or public metrics", () => {
    const results = analyzeSafetyOSText("I was lost, but God brought me back slowly.", "post");
    const serialized = JSON.stringify(results);
    expect(serialized).not.toContain("count");
    expect(serialized).not.toContain("score");
    expect(serialized).not.toContain("publicMetric");
  });
});
