/**
 * restModeEvaluator.test.ts
 * Unit tests for the pure helper functions inside restModeEvaluator.ts.
 * All logic is inlined here so tests run without Firebase or admin SDK.
 */

// ---------------------------------------------------------------------------
// Inline copies of pure helpers from restModeEvaluator.ts
// ---------------------------------------------------------------------------

function parseMins(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

function isWithinWindow(nowMinutes: number, start: string, end: string): boolean {
  const s = parseMins(start);
  const e = parseMins(end);
  return s <= e
    ? nowMinutes >= s && nowMinutes <= e
    : nowMinutes >= s || nowMinutes <= e; // overnight window
}

// Inline copy of LABEL_REQUIRED_TYPES from resolvePostAILabel
const LABEL_REQUIRED_TYPES = new Set([
  "draft_generation",
  "tone_rewrite_major",
  "translation",
  "safety_rewrite",
  "sermon_notes_summary",
]);

function resolveLabelSync(aiUseTypes: string[]): {
  primaryLabel: string | null;
  disclosureRequired: boolean;
} {
  const types = aiUseTypes ?? [];
  if (types.length === 0) return { primaryLabel: null, disclosureRequired: false };

  let label: string | null = null;
  if (types.includes("draft_generation") || types.includes("tone_rewrite_major")) {
    label = "ai_assisted_post";
  } else if (types.includes("translation")) {
    label = "translated_with_ai";
  } else if (types.includes("tone_rewrite_minor")) {
    label = "ai_assisted_tone";
  } else if (types.includes("safety_rewrite")) {
    label = "edited_for_safety";
  } else if (types.includes("sermon_notes_summary")) {
    label = "notes_summarized";
  } else if (types.includes("prayer_generation")) {
    label = "prayer_assisted";
  } else if (types.includes("scripture_suggestion")) {
    label = "scripture_suggested";
  } else if (types.includes("berean_insert")) {
    label = "berean_assisted";
  } else if (types.includes("tone_check")) {
    label = "tone_checked";
  } else if (types.includes("alt_text_generation")) {
    label = "alt_text_assisted";
  }

  const disclosureRequired = types.some((t) => LABEL_REQUIRED_TYPES.has(t));
  return { primaryLabel: label, disclosureRequired };
}

// ---------------------------------------------------------------------------
// Tests: parseMins
// ---------------------------------------------------------------------------

describe("parseMins", () => {
  it("parses midnight", () => {
    expect(parseMins("00:00")).toBe(0);
  });

  it("parses noon", () => {
    expect(parseMins("12:00")).toBe(720);
  });

  it("parses end of day", () => {
    expect(parseMins("23:59")).toBe(1439);
  });

  it("parses 9am", () => {
    expect(parseMins("09:00")).toBe(540);
  });

  it("parses 6:30pm", () => {
    expect(parseMins("18:30")).toBe(1110);
  });

  it("parses minutes-only component", () => {
    expect(parseMins("00:45")).toBe(45);
  });
});

// ---------------------------------------------------------------------------
// Tests: isWithinWindow — same-day window
// ---------------------------------------------------------------------------

describe("isWithinWindow — same-day", () => {
  it("includes time at start boundary", () => {
    expect(isWithinWindow(540, "09:00", "17:00")).toBe(true); // exactly 9am
  });

  it("includes time at end boundary", () => {
    expect(isWithinWindow(1020, "09:00", "17:00")).toBe(true); // exactly 5pm
  });

  it("includes midday", () => {
    expect(isWithinWindow(720, "09:00", "17:00")).toBe(true);
  });

  it("excludes time before window", () => {
    expect(isWithinWindow(480, "09:00", "17:00")).toBe(false); // 8am
  });

  it("excludes time after window", () => {
    expect(isWithinWindow(1080, "09:00", "17:00")).toBe(false); // 6pm
  });

  it("single-minute window matches", () => {
    expect(isWithinWindow(720, "12:00", "12:00")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Tests: isWithinWindow — overnight window
// ---------------------------------------------------------------------------

describe("isWithinWindow — overnight", () => {
  it("includes time after midnight when window straddles midnight", () => {
    // 22:00 → 06:00: 1am is inside
    expect(isWithinWindow(60, "22:00", "06:00")).toBe(true);
  });

  it("includes time before midnight for overnight window", () => {
    // 10pm is inside 22:00→06:00
    expect(isWithinWindow(1320, "22:00", "06:00")).toBe(true);
  });

  it("excludes midday for overnight window", () => {
    // Noon is outside 22:00→06:00
    expect(isWithinWindow(720, "22:00", "06:00")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Tests: Sunday rest mode window helpers
// ---------------------------------------------------------------------------

describe("Sunday rest mode window", () => {
  const SUNDAY_START = "07:00";
  const SUNDAY_END = "22:00";

  it("morning worship time is active", () => {
    expect(isWithinWindow(parseMins("10:30"), SUNDAY_START, SUNDAY_END)).toBe(true);
  });

  it("midnight is outside window", () => {
    expect(isWithinWindow(0, SUNDAY_START, SUNDAY_END)).toBe(false);
  });

  it("late evening is inside window", () => {
    expect(isWithinWindow(parseMins("21:59"), SUNDAY_START, SUNDAY_END)).toBe(true);
  });

  it("start of window is included", () => {
    expect(isWithinWindow(parseMins("07:00"), SUNDAY_START, SUNDAY_END)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Tests: resolvePostAILabel (pure resolution logic)
// ---------------------------------------------------------------------------

describe("resolvePostAILabel — label resolution", () => {
  it("returns null for empty types", () => {
    const { primaryLabel } = resolveLabelSync([]);
    expect(primaryLabel).toBeNull();
  });

  it("assigns ai_assisted_post for draft_generation", () => {
    const { primaryLabel } = resolveLabelSync(["draft_generation"]);
    expect(primaryLabel).toBe("ai_assisted_post");
  });

  it("assigns ai_assisted_post for tone_rewrite_major", () => {
    const { primaryLabel } = resolveLabelSync(["tone_rewrite_major"]);
    expect(primaryLabel).toBe("ai_assisted_post");
  });

  it("draft_generation takes priority over translation", () => {
    const { primaryLabel } = resolveLabelSync(["translation", "draft_generation"]);
    expect(primaryLabel).toBe("ai_assisted_post");
  });

  it("assigns translated_with_ai for translation only", () => {
    const { primaryLabel } = resolveLabelSync(["translation"]);
    expect(primaryLabel).toBe("translated_with_ai");
  });

  it("assigns notes_summarized for sermon_notes_summary", () => {
    const { primaryLabel } = resolveLabelSync(["sermon_notes_summary"]);
    expect(primaryLabel).toBe("notes_summarized");
  });

  it("assigns prayer_assisted for prayer_generation", () => {
    const { primaryLabel } = resolveLabelSync(["prayer_generation"]);
    expect(primaryLabel).toBe("prayer_assisted");
  });

  it("assigns berean_assisted for berean_insert", () => {
    const { primaryLabel } = resolveLabelSync(["berean_insert"]);
    expect(primaryLabel).toBe("berean_assisted");
  });

  it("assigns tone_checked for tone_check only", () => {
    const { primaryLabel } = resolveLabelSync(["tone_check"]);
    expect(primaryLabel).toBe("tone_checked");
  });

  it("assigns alt_text_assisted for alt_text_generation", () => {
    const { primaryLabel } = resolveLabelSync(["alt_text_generation"]);
    expect(primaryLabel).toBe("alt_text_assisted");
  });
});

describe("resolvePostAILabel — disclosure requirement", () => {
  it("requires disclosure for draft_generation", () => {
    const { disclosureRequired } = resolveLabelSync(["draft_generation"]);
    expect(disclosureRequired).toBe(true);
  });

  it("requires disclosure for translation", () => {
    const { disclosureRequired } = resolveLabelSync(["translation"]);
    expect(disclosureRequired).toBe(true);
  });

  it("requires disclosure for safety_rewrite", () => {
    const { disclosureRequired } = resolveLabelSync(["safety_rewrite"]);
    expect(disclosureRequired).toBe(true);
  });

  it("does not require disclosure for tone_check only", () => {
    const { disclosureRequired } = resolveLabelSync(["tone_check"]);
    expect(disclosureRequired).toBe(false);
  });

  it("does not require disclosure for scripture_suggestion only", () => {
    const { disclosureRequired } = resolveLabelSync(["scripture_suggestion"]);
    expect(disclosureRequired).toBe(false);
  });

  it("does not require disclosure for berean_insert only", () => {
    const { disclosureRequired } = resolveLabelSync(["berean_insert"]);
    expect(disclosureRequired).toBe(false);
  });

  it("requires disclosure when mixed types include required", () => {
    const { disclosureRequired } = resolveLabelSync(["tone_check", "sermon_notes_summary"]);
    expect(disclosureRequired).toBe(true);
  });
});
