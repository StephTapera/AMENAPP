// contracts/guardianPrePublish.test.ts
// Feature C · GUARDIAN PrePublish — contract invariants (PP-I2, PP-I3, fail-closed).
// These assertions freeze the chain ordering + the unconditional child-safety hook.

import {
  PREPUBLISH_HOOK_ORDER,
  GUARDIAN_PREPUBLISH_FLAG_KEY,
  failClosedVerdict,
  reduceDecisions,
  mayCommit,
  decisionSeverity,
  HookDecision,
} from "./guardianPrePublish";

describe("PREPUBLISH_HOOK_ORDER (PP-I2/PP-I3)", () => {
  it("places childSafetyHash at index 0 and never flag-gates it", () => {
    expect(PREPUBLISH_HOOK_ORDER[0].kind).toBe("childSafetyHash");
    expect(PREPUBLISH_HOOK_ORDER[0].order).toBe(0);
    expect(PREPUBLISH_HOOK_ORDER[0].flagGated).toBe(false);
  });

  it("freezes the exact order: childSafetyHash, toxicity, claimScriptureContext, provenanceStamp", () => {
    expect(PREPUBLISH_HOOK_ORDER.map((h) => h.kind)).toEqual([
      "childSafetyHash",
      "toxicity",
      "claimScriptureContext",
      "provenanceStamp",
    ]);
  });

  it("declares order indices 0..3 contiguously and monotonically", () => {
    PREPUBLISH_HOOK_ORDER.forEach((h, i) => {
      expect(h.order).toBe(i);
    });
  });

  it("flag-gates only hooks 1–3 (child-safety is always-on)", () => {
    const gated = PREPUBLISH_HOOK_ORDER.filter((h) => h.flagGated).map((h) => h.kind);
    expect(gated).toEqual(["toxicity", "claimScriptureContext", "provenanceStamp"]);
  });
});

describe("failClosedVerdict (PP-I3/PP-I4)", () => {
  it("never returns proceed for any hook kind or reason", () => {
    for (const h of PREPUBLISH_HOOK_ORDER) {
      const v = failClosedVerdict(h.kind, "providerError", "test");
      expect(v.decision).not.toBe("proceed");
      expect(v.decision).not.toBe("stampOnly");
      expect(v.requiresHumanReview).toBe(true);
    }
  });

  it("fails child-safety to a hard blockCommit (no screener => block)", () => {
    const v = failClosedVerdict("childSafetyHash", "noScreener", "CameraChildSafetyService");
    expect(v.decision).toBe("blockCommit");
    expect(v.categories).toContain("child_safety");
  });

  it("fails hooks 1–3 to holdForReview, not block, not proceed", () => {
    for (const kind of ["toxicity", "claimScriptureContext", "provenanceStamp"] as const) {
      expect(failClosedVerdict(kind, "providerError", "test").decision).toBe("holdForReview");
    }
  });
});

describe("most-severe reducer (chain semantics)", () => {
  it("ranks blockCommit > holdForReview > stampOnly > proceed > shadowObserve", () => {
    const order: HookDecision[] = [
      "blockCommit",
      "holdForReview",
      "stampOnly",
      "proceed",
      "shadowObserve",
    ];
    for (let i = 0; i < order.length - 1; i++) {
      expect(decisionSeverity(order[i])).toBeGreaterThan(decisionSeverity(order[i + 1]));
    }
  });

  it("any blockCommit wins regardless of position", () => {
    expect(reduceDecisions(["proceed", "stampOnly", "blockCommit", "proceed"])).toBe("blockCommit");
  });

  it("holdForReview wins over stampOnly/proceed", () => {
    expect(reduceDecisions(["proceed", "holdForReview", "stampOnly"])).toBe("holdForReview");
  });

  it("a clean chain reduces to proceed", () => {
    expect(reduceDecisions(["proceed", "proceed"])).toBe("proceed");
  });

  it("shadowObserve never escalates above proceed", () => {
    expect(reduceDecisions(["proceed", "shadowObserve"])).toBe("proceed");
    expect(reduceDecisions(["shadowObserve"])).toBe("shadowObserve");
  });
});

describe("mayCommit gate", () => {
  it("permits commit only for proceed or stampOnly", () => {
    expect(mayCommit("proceed")).toBe(true);
    expect(mayCommit("stampOnly")).toBe(true);
    expect(mayCommit("holdForReview")).toBe(false);
    expect(mayCommit("blockCommit")).toBe(false);
    expect(mayCommit("shadowObserve")).toBe(false);
  });
});

describe("Remote Config flag key", () => {
  it("uses the spec RC key", () => {
    expect(GUARDIAN_PREPUBLISH_FLAG_KEY).toBe("guardian_pre_publish_enabled");
  });
});
