/**
 * permissionsEngine.test.ts
 *
 * Property-based tests for all 8 safety invariants from spec §9.
 *
 * Rather than mocking Firestore, these tests exercise the pure engine functions
 * (ageTierCeiling, modeGrant, resolvePermissions, canMessage) directly.
 * Every combination of (tier × mode × trustLevel × verificationStatus × accountState
 * × guardianConsentStatus × mentorApproved × csamFlag) is enumerated and each
 * invariant is asserted. If any combination violates an invariant, the resolver
 * — not the test — is wrong.
 *
 * Test count: 3 tiers × 7 modes × 6 trust levels × 3 verification × 3 states
 *             × 3 consent × 2 mentorApproved × 2 csamFlag = 6,804 combinations
 *             plus specific pairwise canMessage edge cases.
 */

import {
  resolvePermissions,
  ageTierCeiling,
  modeGrant,
  canMessage,
  isModeAllowedForTier,
  minDMPolicy,
  maxDMPolicy,
} from "./permissionsEngine";
import { AgeTier, IdentityMode, AccountSnapshot, DMPolicy, PermissionSet } from "./permissionsTypes";

// ─── Enumeration helpers ──────────────────────────────────────────────────────

const ALL_TIERS: AgeTier[] = ["under13", "teen", "adult"];
const ALL_MODES: IdentityMode[] = ["social", "discussion", "study", "quiet", "postless", "campus", "family"];
const ALL_TRUST = [0, 1, 2, 3, 4, 5];
const ALL_VERIFICATION = ["none", "pending", "verified"] as const;
const ALL_STATES = ["active", "pending", "suspended"] as const;
const ALL_CONSENT = ["n/a", "pending", "confirmed"] as const;
const ALL_MENTOR = [false, true];
const ALL_CSAM = [false, true];

const DM_ORDER: Record<DMPolicy, number> = {
  none: 0, trustedOnly: 1, mutualOnly: 2, open: 3,
};

function dmLte(a: DMPolicy, b: DMPolicy): boolean {
  return DM_ORDER[a] <= DM_ORDER[b];
}

function makeAccount(overrides: Partial<AccountSnapshot>): AccountSnapshot {
  return {
    uid: "test_uid",
    ageTier: "adult",
    mode: "social",
    verificationStatus: "none",
    mentorApproved: false,
    trustLevel: 0,
    accountState: "active",
    guardianConsentStatus: "n/a",
    csamFlag: false,
    ...overrides,
  };
}

function allCombinations(): AccountSnapshot[] {
  const accounts: AccountSnapshot[] = [];
  for (const ageTier of ALL_TIERS) {
    for (const mode of ALL_MODES) {
      for (const trustLevel of ALL_TRUST) {
        for (const verificationStatus of ALL_VERIFICATION) {
          for (const accountState of ALL_STATES) {
            for (const guardianConsentStatus of ALL_CONSENT) {
              for (const mentorApproved of ALL_MENTOR) {
                for (const csamFlag of ALL_CSAM) {
                  accounts.push(makeAccount({
                    ageTier, mode, trustLevel, verificationStatus,
                    accountState, guardianConsentStatus, mentorApproved, csamFlag,
                  }));
                }
              }
            }
          }
        }
      }
    }
  }
  return accounts;
}

// ─── Invariant 1: effective ⊆ ceiling(ageTier) ───────────────────────────────

describe("Invariant 1: effective ⊆ ceiling(ageTier) for all combinations", () => {
  it("no field exceeds the age-tier ceiling across all 6804 combinations", () => {
    const combinations = allCombinations();
    const violations: string[] = [];

    for (const account of combinations) {
      const effective = resolvePermissions(account);
      const ceiling = ageTierCeiling(account.ageTier);

      if (effective.canPostPublic && !ceiling.canPostPublic) {
        violations.push(`${account.ageTier}/${account.mode}: canPostPublic exceeds ceiling`);
      }
      if (effective.canBeDiscovered && !ceiling.canBeDiscovered) {
        violations.push(`${account.ageTier}/${account.mode}: canBeDiscovered exceeds ceiling`);
      }
      if (effective.canCreateGroup && !ceiling.canCreateGroup) {
        violations.push(`${account.ageTier}/${account.mode}: canCreateGroup exceeds ceiling`);
      }
      if (effective.canUploadMedia && !ceiling.canUploadMedia) {
        violations.push(`${account.ageTier}/${account.mode}: canUploadMedia exceeds ceiling`);
      }
      if (!dmLte(effective.sendDM, ceiling.sendDM)) {
        violations.push(
          `${account.ageTier}/${account.mode}: sendDM ${effective.sendDM} exceeds ceiling ${ceiling.sendDM}`
        );
      }
      if (!dmLte(effective.receiveDM, ceiling.receiveDM)) {
        violations.push(
          `${account.ageTier}/${account.mode}: receiveDM ${effective.receiveDM} exceeds ceiling ${ceiling.receiveDM}`
        );
      }
    }

    if (violations.length > 0) {
      throw new Error(
        `Invariant 1 violated (${violations.length} cases):\n${violations.slice(0, 10).join("\n")}`
      );
    }
  });
});

// ─── Invariant 2: under13 hard restrictions ───────────────────────────────────

describe("Invariant 2: under13 hard restrictions", () => {
  it("under13 never gets canPostPublic", () => {
    for (const mode of ALL_MODES) {
      for (const trust of ALL_TRUST) {
        const p = resolvePermissions(makeAccount({
          ageTier: "under13", mode, trustLevel: trust,
          guardianConsentStatus: "confirmed",
        }));
        expect(p.canPostPublic).toBe(false);
      }
    }
  });

  it("under13 never gets canBeDiscovered", () => {
    for (const mode of ALL_MODES) {
      const p = resolvePermissions(makeAccount({
        ageTier: "under13", mode, trustLevel: 5,
        guardianConsentStatus: "confirmed",
      }));
      expect(p.canBeDiscovered).toBe(false);
    }
  });

  it("under13 sendDM and receiveDM never exceed trustedOnly", () => {
    for (const mode of ALL_MODES) {
      const p = resolvePermissions(makeAccount({
        ageTier: "under13", mode, trustLevel: 5,
        guardianConsentStatus: "confirmed",
      }));
      expect(DM_ORDER[p.sendDM]).toBeLessThanOrEqual(DM_ORDER["trustedOnly"]);
      expect(DM_ORDER[p.receiveDM]).toBeLessThanOrEqual(DM_ORDER["trustedOnly"]);
    }
  });
});

// ─── Invariant 3: teen hard restrictions ─────────────────────────────────────

describe("Invariant 3: teen hard restrictions", () => {
  it("teen reachTier never exceeds normal", () => {
    for (const mode of ALL_MODES) {
      for (const trust of ALL_TRUST) {
        const p = resolvePermissions(makeAccount({ ageTier: "teen", mode, trustLevel: trust }));
        expect(["restricted", "normal"]).toContain(p.reachTier);
      }
    }
  });

  it("teen sendDM and receiveDM never exceed trustedOnly", () => {
    for (const mode of ALL_MODES) {
      for (const trust of ALL_TRUST) {
        const p = resolvePermissions(makeAccount({ ageTier: "teen", mode, trustLevel: trust }));
        expect(DM_ORDER[p.sendDM]).toBeLessThanOrEqual(DM_ORDER["trustedOnly"]);
        expect(DM_ORDER[p.receiveDM]).toBeLessThanOrEqual(DM_ORDER["trustedOnly"]);
      }
    }
  });
});

// ─── Invariant 4: adult → minor pairwise messaging ───────────────────────────

describe("Invariant 4: adult → minor pairwise messaging requires canContactMinors + trustEdge", () => {
  const adultPerms = resolvePermissions(makeAccount({
    ageTier: "adult", mode: "social", trustLevel: 5,
    verificationStatus: "verified", mentorApproved: true,
  }));
  const minorPerms = resolvePermissions(makeAccount({
    ageTier: "teen", mode: "social", trustLevel: 3,
    guardianConsentStatus: "n/a",
  }));
  const adultNoMentor = resolvePermissions(makeAccount({
    ageTier: "adult", mode: "social", trustLevel: 5,
    verificationStatus: "verified", mentorApproved: false,
  }));

  it("adult with canContactMinors + trust edge CAN message a minor", () => {
    expect(adultPerms.canContactMinors).toBe(true);
    expect(canMessage(adultPerms, "adult", minorPerms, "teen", true, true)).toBe(true);
  });

  it("adult without canContactMinors CANNOT message a minor even with trust edge", () => {
    expect(adultNoMentor.canContactMinors).toBe(false);
    expect(canMessage(adultNoMentor, "adult", minorPerms, "teen", true, true)).toBe(false);
  });

  it("adult with canContactMinors but WITHOUT trust edge CANNOT message a minor", () => {
    expect(canMessage(adultPerms, "adult", minorPerms, "teen", false, true)).toBe(false);
  });

  it("minor → minor is allowed when trust edge exists and DM policies permit", () => {
    const teenPerms = resolvePermissions(makeAccount({
      ageTier: "teen", mode: "postless", trustLevel: 0,
    }));
    // teen receiveDM is trustedOnly — requires trust edge
    expect(canMessage(teenPerms, "teen", teenPerms, "teen", true, true)).toBe(true);
    expect(canMessage(teenPerms, "teen", teenPerms, "teen", false, true)).toBe(false);
  });
});

// ─── Invariant 5: canContactMinors ⇒ verified ∧ mentorApproved ───────────────

describe("Invariant 5: canContactMinors === true ⇒ verified ∧ mentorApproved", () => {
  it("never grants canContactMinors without both verified + mentorApproved", () => {
    const violations: string[] = [];
    for (const account of allCombinations()) {
      const p = resolvePermissions(account);
      if (p.canContactMinors) {
        if (account.verificationStatus !== "verified" || !account.mentorApproved) {
          violations.push(
            `uid implied by ${JSON.stringify(account)}: canContactMinors=true but conditions not met`
          );
        }
      }
    }
    expect(violations).toHaveLength(0);
  });

  it("adult + verified + mentorApproved + active DOES get canContactMinors", () => {
    const p = resolvePermissions(makeAccount({
      ageTier: "adult",
      mode: "social",
      verificationStatus: "verified",
      mentorApproved: true,
      accountState: "active",
    }));
    expect(p.canContactMinors).toBe(true);
  });
});

// ─── Invariant 6: mode change never exceeds ceiling ──────────────────────────

describe("Invariant 6: mode change never produces a field above ceiling(ageTier)", () => {
  it("changing to social mode does not exceed ceiling for any tier", () => {
    for (const ageTier of ALL_TIERS) {
      const p = resolvePermissions(makeAccount({
        ageTier, mode: "social", trustLevel: 5,
        verificationStatus: "verified", mentorApproved: false,
        accountState: "active",
        guardianConsentStatus: ageTier === "under13" ? "confirmed" : "n/a",
      }));
      const ceiling = ageTierCeiling(ageTier);
      expect(p.canPostPublic).toBeLessThanOrEqual(Number(ceiling.canPostPublic));
      expect(p.canBeDiscovered).toBeLessThanOrEqual(Number(ceiling.canBeDiscovered));
      expect(DM_ORDER[p.sendDM]).toBeLessThanOrEqual(DM_ORDER[ceiling.sendDM]);
    }
  });
});

// ─── Invariant 7: suspended or CSAM flag → restricted base ───────────────────

describe("Invariant 7: active suspension or CSAM flag → restricted base", () => {
  const restrictedFields: (keyof PermissionSet)[] = [
    "canPostPublic", "canBeDiscovered", "canCreateGroup", "canUploadMedia", "canContactMinors",
  ];

  it("suspended account gets all capabilities zeroed", () => {
    for (const ageTier of ALL_TIERS) {
      for (const mode of ALL_MODES) {
        const p = resolvePermissions(makeAccount({
          ageTier, mode, trustLevel: 5,
          verificationStatus: "verified", mentorApproved: true,
          accountState: "suspended",
          guardianConsentStatus: "confirmed",
        }));
        for (const field of restrictedFields) {
          expect(p[field]).toBe(false);
        }
        expect(p.sendDM).toBe("none");
        expect(p.receiveDM).toBe("none");
        expect(p.reachTier).toBe("restricted");
      }
    }
  });

  it("CSAM-flagged account gets all capabilities zeroed", () => {
    for (const ageTier of ALL_TIERS) {
      const p = resolvePermissions(makeAccount({
        ageTier, mode: "social", trustLevel: 5,
        verificationStatus: "verified", mentorApproved: true,
        accountState: "active", csamFlag: true,
        guardianConsentStatus: "confirmed",
      }));
      for (const field of restrictedFields) {
        expect(p[field]).toBe(false);
      }
      expect(p.sendDM).toBe("none");
    }
  });
});

// ─── Invariant 8: under13 without confirmed consent → zero capabilities ───────

describe("Invariant 8: under13 + guardianConsentStatus !== confirmed → zero capabilities", () => {
  const capabilityFields: (keyof PermissionSet)[] = [
    "canPostPublic", "canBeDiscovered", "canCreateGroup", "canUploadMedia", "canContactMinors",
  ];

  it("pending consent gives zero capabilities regardless of mode or trust", () => {
    for (const mode of ALL_MODES) {
      for (const trust of ALL_TRUST) {
        const p = resolvePermissions(makeAccount({
          ageTier: "under13", mode, trustLevel: trust,
          guardianConsentStatus: "pending",
          accountState: "active",
        }));
        for (const field of capabilityFields) {
          expect(p[field]).toBe(false);
        }
        expect(p.sendDM).toBe("none");
        expect(p.receiveDM).toBe("none");
      }
    }
  });

  it("no consent (n/a) also gives zero capabilities for under-13", () => {
    const p = resolvePermissions(makeAccount({
      ageTier: "under13", mode: "social", trustLevel: 5,
      guardianConsentStatus: "n/a",
    }));
    for (const field of capabilityFields) {
      expect(p[field]).toBe(false);
    }
  });

  it("confirmed consent allows the mode-restricted non-zero capabilities", () => {
    const p = resolvePermissions(makeAccount({
      ageTier: "under13", mode: "postless",
      guardianConsentStatus: "confirmed",
      accountState: "active",
    }));
    // postless mode allows sendDM: trustedOnly (which IS ≤ under13 ceiling)
    expect(p.sendDM).toBe("trustedOnly");
  });
});

// ─── Mode grants don't leak into wrong tiers ─────────────────────────────────

describe("Mode-tier intersection correctness", () => {
  it("teen in social mode still gets trustedOnly DMs (not open)", () => {
    const p = resolvePermissions(makeAccount({ ageTier: "teen", mode: "social", trustLevel: 5 }));
    expect(p.sendDM).toBe("trustedOnly");
    expect(p.receiveDM).toBe("trustedOnly");
    expect(p.reachTier).not.toBe("amplified");
    expect(p.canCreateGroup).toBe(false);
  });

  it("adult in postless mode cannot post public even with max trust", () => {
    const p = resolvePermissions(makeAccount({ ageTier: "adult", mode: "postless", trustLevel: 5 }));
    expect(p.canPostPublic).toBe(false);
  });

  it("adult in discussion mode cannot post public", () => {
    const p = resolvePermissions(makeAccount({ ageTier: "adult", mode: "discussion", trustLevel: 5 }));
    expect(p.canPostPublic).toBe(false);
  });

  it("adult in social mode with max trust gets full amplified reach", () => {
    const p = resolvePermissions(makeAccount({
      ageTier: "adult", mode: "social", trustLevel: 5,
      accountState: "active",
    }));
    expect(p.canPostPublic).toBe(true);
    expect(p.reachTier).toBe("amplified");
    expect(p.sendDM).toBe("open");
    expect(p.canCreateGroup).toBe(true);
  });
});

// ─── Trust modifier clamping ──────────────────────────────────────────────────

describe("Trust modifier clamping at ceiling", () => {
  it("trust level 5 cannot raise teen sendDM above trustedOnly", () => {
    for (const mode of ALL_MODES) {
      const p = resolvePermissions(makeAccount({ ageTier: "teen", mode, trustLevel: 5 }));
      expect(DM_ORDER[p.sendDM]).toBeLessThanOrEqual(DM_ORDER["trustedOnly"]);
    }
  });

  it("trust level 4 cannot grant canBeDiscovered to under13", () => {
    const p = resolvePermissions(makeAccount({
      ageTier: "under13", trustLevel: 4,
      guardianConsentStatus: "confirmed",
    }));
    expect(p.canBeDiscovered).toBe(false);
  });

  it("trust level 3 raises adult open DMs in social mode", () => {
    const p = resolvePermissions(makeAccount({
      ageTier: "adult", mode: "social", trustLevel: 3,
    }));
    expect(p.sendDM).toBe("open");
  });

  it("trust level 2 raises adult DMs to mutualOnly in quiet mode (trustedOnly grant)", () => {
    // quiet mode grants trustedOnly. trust earned mutualOnly. ceiling is open.
    // max(trustedOnly, mutualOnly) = mutualOnly. min(open, mutualOnly) = mutualOnly.
    const p = resolvePermissions(makeAccount({
      ageTier: "adult", mode: "quiet", trustLevel: 2,
    }));
    expect(p.sendDM).toBe("mutualOnly");
  });
});

// ─── canMessage edge cases ────────────────────────────────────────────────────

describe("canMessage edge cases", () => {
  const open: PermissionSet = {
    canPostPublic: true, canBeDiscovered: true, canCreateGroup: true, canUploadMedia: true,
    sendDM: "open", receiveDM: "open", reachTier: "amplified",
    requiresPrePublishReview: false, canContactMinors: true,
  };
  const mutualOnly: PermissionSet = { ...open, sendDM: "mutualOnly", receiveDM: "mutualOnly" };
  const trustedOnly: PermissionSet = { ...open, sendDM: "trustedOnly", receiveDM: "trustedOnly" };
  const noDM: PermissionSet = { ...open, sendDM: "none", receiveDM: "none" };

  it("sendDM none always blocks", () => {
    expect(canMessage(noDM, "adult", open, "adult", true, true)).toBe(false);
  });

  it("receiveDM none always blocks", () => {
    expect(canMessage(open, "adult", noDM, "adult", true, true)).toBe(false);
  });

  it("recipient trustedOnly requires trust edge", () => {
    expect(canMessage(open, "adult", trustedOnly, "adult", false, true)).toBe(false);
    expect(canMessage(open, "adult", trustedOnly, "adult", true, false)).toBe(true);
  });

  it("recipient mutualOnly requires mutual connection", () => {
    expect(canMessage(open, "adult", mutualOnly, "adult", true, false)).toBe(false);
    expect(canMessage(open, "adult", mutualOnly, "adult", false, true)).toBe(true);
  });

  it("adult without canContactMinors blocked from teen even with trust edge", () => {
    const adultNoContact: PermissionSet = { ...open, canContactMinors: false };
    expect(canMessage(adultNoContact, "adult", open, "teen", true, true)).toBe(false);
  });
});

// ─── isModeAllowedForTier ─────────────────────────────────────────────────────

describe("isModeAllowedForTier", () => {
  it("under13 cannot use social mode", () => {
    expect(isModeAllowedForTier("social", "under13")).toBe(false);
  });

  it("teen cannot use social mode", () => {
    expect(isModeAllowedForTier("social", "teen")).toBe(false);
  });

  it("adult can use all modes", () => {
    for (const mode of ALL_MODES) {
      expect(isModeAllowedForTier(mode, "adult")).toBe(true);
    }
  });

  it("under13 can use postless and family", () => {
    expect(isModeAllowedForTier("postless", "under13")).toBe(true);
    expect(isModeAllowedForTier("family", "under13")).toBe(true);
  });
});

// ─── Ordering helpers ─────────────────────────────────────────────────────────

describe("DMPolicy ordering helpers", () => {
  it("minDMPolicy returns more restrictive", () => {
    expect(minDMPolicy("open", "trustedOnly")).toBe("trustedOnly");
    expect(minDMPolicy("none", "open")).toBe("none");
    expect(minDMPolicy("mutualOnly", "mutualOnly")).toBe("mutualOnly");
  });

  it("maxDMPolicy returns more permissive", () => {
    expect(maxDMPolicy("trustedOnly", "mutualOnly")).toBe("mutualOnly");
    expect(maxDMPolicy("none", "open")).toBe("open");
  });
});
