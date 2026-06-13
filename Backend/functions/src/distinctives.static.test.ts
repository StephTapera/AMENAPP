import * as fs from "fs";
import * as path from "path";

const source = fs.readFileSync(path.join(__dirname, "distinctives.ts"), "utf8");

describe("AMEN Distinctives backend contracts", () => {
  it("enforces App Check on all callable distinctives functions", () => {
    const callableNames = [
      "resurfacePrayers",
      "inviteWitness",
      "acceptCovenant",
      "witnessCheckIn",
      "liturgicalContextProvider",
      "generateDailyOffice",
    ];

    for (const name of callableNames) {
      const start = source.indexOf(`export const ${name} = onCall(`);
      expect(start).toBeGreaterThanOrEqual(0);
      const end = source.indexOf("async", start);
      expect(source.slice(start, end)).toContain("enforceAppCheck: true");
      expect(source.slice(start, end)).toContain("region: REGION");
    }
  });

  it("keeps feature flags and kill switches present", () => {
    for (const flag of [
      "ff_prayer_ledger",
      "ff_test_everything",
      "ff_witnessed_commitments",
      "ff_daily_office",
      "ff_liturgical_pacing",
    ]) {
      expect(source).toContain(flag);
    }

    for (const killSwitch of [
      "kill_resurface_prayers",
      "kill_ground_claim",
      "kill_invite_witness",
      "kill_accept_covenant",
      "kill_witness_check_in",
      "kill_generate_daily_office",
      "kill_liturgical_context_provider",
    ]) {
      expect(source).toContain(killSwitch);
    }
  });

  it("keeps Grace Mechanics free of streak counters in backend code", () => {
    expect(source).not.toMatch(/streak\s*:/i);
    expect(source).not.toMatch(/count\s*:/i);
  });
});
