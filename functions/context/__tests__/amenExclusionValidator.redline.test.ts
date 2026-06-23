/**
 * amenExclusionValidator.redline.test.ts — Wave 6 red lines for export boundary.
 *
 * Asserts that crisis-path data and spiritual-performance metrics can never leave
 * the account in a portable .amen file (RED LINES crisis_data_export,
 * spiritual_surveillance, spiritual_scoring). Pure — no emulator needed.
 */

import { validateNoExcludedContent } from "../amenExclusionValidator";

describe("export red lines — crisis data is sacred", () => {
  it("rejects a payload carrying crisis-path data", () => {
    const r = validateNoExcludedContent({ facets: [{ key: "x", safetyPlan: "step 1..." }] });
    expect(r.ok).toBe(false);
    expect(r.violations.join(" ")).toMatch(/crisis_data_export/);
  });

  it("rejects crisis risk scores and trusted contacts", () => {
    expect(validateNoExcludedContent({ crisisScore: 0.9 }).ok).toBe(false);
    expect(validateNoExcludedContent({ trustedContacts: ["a"] }).ok).toBe(false);
  });
});

describe("export red lines — no spiritual surveillance / scoring", () => {
  it("rejects spiritual-performance metrics", () => {
    expect(validateNoExcludedContent({ prayerFrequency: 7 }).ok).toBe(false);
    expect(validateNoExcludedContent({ pietyScore: 88 }).ok).toBe(false);
    expect(validateNoExcludedContent({ attendanceStreak: 12 }).ok).toBe(false);
  });

  it("does NOT false-positive on a legitimate facet that merely mentions prayer", () => {
    const r = validateNoExcludedContent({
      facets: [{ key: "interests", label: "I value prayer and study", value: { kind: "text", payload: "prayer" } }],
    });
    expect(r.ok).toBe(true);
  });
});
