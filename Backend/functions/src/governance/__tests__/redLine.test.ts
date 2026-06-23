/**
 * redLine.test.ts — The Red-Line Suite (Wave 6, invariant 9 + all).
 *
 * Each assertion is a build-failing red line. If any of these fail, the build is
 * NOT eligible for submission. The suite is pure (no I/O, no emulator) so it runs
 * in every CI pass.
 */

import {
  RED_LINES,
  FlagGovernanceSpec,
  ProposedConsequentialAction,
  CitationGrounding,
  FounderRulingPolicy,
} from "../contracts";
import {
  matchedEngagementStems,
  evaluateFlagPurpose,
  evaluateFlagDefaultState,
  canEnableFlag,
  assertNoRedLineOverride,
  conformanceVerdict,
  assessCompanionBoundary,
  enforceGrounding,
  assertFounderRulingsImmutable,
} from "../policyEngine";
import {
  authorizeConsequentialAction,
  requiresHumanDecision,
} from "../humanInLoop";
import { auditFlagRegistry, SAFETY_CRITICAL_FLAGS, CSAM_CLASS_FLAGS } from "../flagRegistry";

const V = "test-1.1.0";

// ── Invariant 1 — Formation over engagement (purpose firewall) ───────────────
describe("INV1 purpose firewall", () => {
  it("REJECTS a flag whose purpose is to grow engagement metrics", () => {
    const spec: FlagGovernanceSpec = {
      key: "infinite_scroll_v2",
      tag: "standard",
      defaultEnabled: false,
      statedPurpose: "Increase session length and boost retention via an engagement loop.",
    };
    expect(matchedEngagementStems(spec.statedPurpose).length).toBeGreaterThan(0);
    expect(evaluateFlagPurpose(spec, V).status).toBe("blocked");
  });

  it("PASSES a service-oriented flag", () => {
    const spec: FlagGovernanceSpec = {
      key: "scripture_lookup",
      tag: "standard",
      defaultEnabled: false,
      statedPurpose: "Let users look up a Bible passage faster.",
    };
    expect(evaluateFlagPurpose(spec, V).status).toBe("pass");
  });
});

// ── Invariant 2 — Constitutional conformance verdict ─────────────────────────
describe("INV2 conformance verdict", () => {
  it("records the Constitution version on every verdict", () => {
    const v = conformanceVerdict(true, false, V, []);
    expect(v.constitutionVersion).toBe(V);
    expect(v.status).toBe("pass");
  });
  it("blocks when review fails and is not degraded", () => {
    expect(conformanceVerdict(false, false, V, ["scripture"]).status).toBe("blocked");
  });
  it("degrades when review fails but degradation is allowed", () => {
    expect(conformanceVerdict(false, true, V, []).status).toBe("degraded");
  });
});

// ── Invariant 3 — Companion Boundary (parasocial / idolatry) ─────────────────
describe("INV3 companion boundary", () => {
  it("flags dependence language and requires an outward handoff", () => {
    const a = assessCompanionBoundary("I'm always here for you — just keep talking to me.");
    expect(a.withinBoundary).toBe(false);
    expect(a.outwardHandoffRequired).toBe(true);
    expect(a.violations).toContain("fosters_dependence");
  });
  it("flags accepting confession/worship", () => {
    expect(assessCompanionBoundary("You can confess to me and I will forgive you.").withinBoundary).toBe(false);
  });
  it("flags mediator positioning", () => {
    expect(assessCompanionBoundary("I am your bridge to God.").withinBoundary).toBe(false);
  });
  it("passes warm-but-outward text", () => {
    const a = assessCompanionBoundary("That sounds heavy — please bring this to God and to your pastor.");
    expect(a.withinBoundary).toBe(true);
  });
  it("honors the prohibited-phrase list (fail-closed)", () => {
    expect(assessCompanionBoundary("you don't need anyone else", ["you don't need anyone else"]).withinBoundary).toBe(false);
  });
});

// ── Invariant 4 — Red lines, non-overridable ─────────────────────────────────
describe("INV4 red lines", () => {
  it("declares all seven canonical red lines, none overridable", () => {
    const ids = RED_LINES.map((r) => r.id).sort();
    expect(ids).toEqual(
      [
        "crisis_data_export",
        "crisis_data_unencrypted",
        "csam",
        "ecclesial_impersonation",
        "minor_sexualization",
        "spiritual_scoring",
        "spiritual_surveillance",
      ].sort()
    );
    expect(RED_LINES.every((r) => r.overridable === false)).toBe(true);
  });
  it("blocks a flag that tries to override a red line", () => {
    const spec: FlagGovernanceSpec = {
      key: "disable_csam",
      tag: "standard",
      defaultEnabled: false,
      statedPurpose: "Override csam scanning to reduce false positives.",
    };
    expect(assertNoRedLineOverride(spec, V).status).toBe("blocked");
  });
});

// ── Invariant 5 — Intelligence proposes, people decide (HITL) ────────────────
describe("INV5 human-in-the-loop chokepoint", () => {
  const base: ProposedConsequentialAction<{ uid: string }> = {
    kind: "account_ban",
    proposedBy: "ai",
    payload: { uid: "u1" },
    summary: "AI proposes banning u1",
  };

  it("REFUSES an AI-proposed action with no human approval", () => {
    const r = authorizeConsequentialAction(base);
    expect(r.authorized).toBe(false);
  });

  it("REFUSES when the human rejected", () => {
    const r = authorizeConsequentialAction({
      ...base,
      approval: { approver: "mod1", approvedAtISO: "2026-06-20T00:00:00Z", decision: "reject", rationale: "no" },
    });
    expect(r.authorized).toBe(false);
  });

  it("AUTHORIZES only with a complete approve, and execute runs the mutation", () => {
    const r = authorizeConsequentialAction({
      ...base,
      approval: { approver: "mod1", approvedAtISO: "2026-06-20T00:00:00Z", decision: "approve", rationale: "policy X" },
    });
    expect(r.authorized).toBe(true);
    if (r.authorized) {
      let ran = false;
      const out = r.execute((p) => {
        ran = true;
        return p.uid;
      });
      expect(ran).toBe(true);
      expect(out).toBe("u1");
    }
  });

  it("there is NO executor on the unauthorized branch (type + runtime)", () => {
    const r = authorizeConsequentialAction(base);
    // @ts-expect-error — execute does not exist on the refused branch
    expect(r.execute).toBeUndefined();
  });

  it("every consequential kind requires a human decision", () => {
    expect(requiresHumanDecision("minor_data_mutation")).toBe(true);
    expect(requiresHumanDecision("spiritually_binding_ruling")).toBe(true);
  });
});

// ── Invariant 6 — Gated capability (default-OFF + sign-off) ───────────────────
describe("INV6 safety-critical flags", () => {
  it("registry audit is clean (all default-OFF, none enable-able)", () => {
    expect(auditFlagRegistry(V)).toEqual({ ok: true, problems: [] });
  });

  it("a safety_critical flag shipping default-ON is blocked", () => {
    const bad: FlagGovernanceSpec = {
      key: "x",
      tag: "safety_critical",
      defaultEnabled: true,
      statedPurpose: "child safety",
    };
    expect(evaluateFlagDefaultState(bad, V).status).toBe("blocked");
  });

  it("cannot enable a safety_critical flag without a complete sign-off", () => {
    const spec = SAFETY_CRITICAL_FLAGS.find((f) => f.key === "connect_live_rooms_enabled")!;
    expect(canEnableFlag(spec).allowed).toBe(false);
  });

  it("CSAM-class flags require a non-engineer reviewer even with a sign-off", () => {
    const csam = SAFETY_CRITICAL_FLAGS.find((f) => f.key === "csam_hash_scan_enabled")!;
    const withEngineerOnly: FlagGovernanceSpec = {
      ...csam,
      signOff: {
        approver: "eng1",
        approvedAtISO: "2026-06-20T00:00:00Z",
        basis: "tested",
        nonEngineerReviewer: false,
      },
    };
    expect(canEnableFlag(withEngineerOnly, { requireNonEngineerReviewer: CSAM_CLASS_FLAGS.has(csam.key) }).allowed).toBe(false);
  });
});

// ── Invariant 7 — No fabricated Scripture (grounding fail-closed) ────────────
describe("INV7 grounding", () => {
  it("strips unverifiable citations and keeps verified ones", () => {
    const cites: CitationGrounding[] = [
      { reference: "John 3:16", status: "verified", sourceId: "canon:john" },
      { reference: "Hezekiah 4:12", status: "unverifiable" },
    ];
    const r = enforceGrounding(cites, V);
    expect(r.assertable.map((c) => c.reference)).toEqual(["John 3:16"]);
    expect(r.stripped.map((c) => c.reference)).toEqual(["Hezekiah 4:12"]);
    expect(r.verdict.status).toBe("degraded");
  });
});

// ── Invariant 8 — Founder rulings immutable ──────────────────────────────────
describe("INV8 immutable founder rulings", () => {
  const good: FounderRulingPolicy = {
    id: "FR-1",
    ruling: "no spiritual surveillance",
    codifiedAtISO: "2026-06-20T00:00:00Z",
    immutable: true,
    amendments: [],
  };
  it("passes intact rulings", () => {
    expect(assertFounderRulingsImmutable([good], V).status).toBe("pass");
  });
  it("blocks a ruling not marked immutable", () => {
    const bad = { ...good, immutable: false } as unknown as FounderRulingPolicy;
    expect(assertFounderRulingsImmutable([bad], V).status).toBe("blocked");
  });
  it("blocks an amendment missing change-control fields", () => {
    const bad: FounderRulingPolicy = {
      ...good,
      amendments: [{ amendedAtISO: "x", amendedBy: "", reason: "", fromVersion: "1", toVersion: "2" }],
    };
    expect(assertFounderRulingsImmutable([bad], V).status).toBe("blocked");
  });
});
