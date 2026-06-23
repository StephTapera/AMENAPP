# AMEN Governance Hardening — Formation-First Safety Doctrine

This directory binds **nine governance invariants** into AMEN's *existing* systems
(the AMEN Constitution, GUARDIAN/Aegis, the Berean pipeline, PRIVACY-CORE, and the
feature-flag registry). It does **not** introduce a parallel safety stack.

Branch: `feature/governance-hardening` (isolated worktree, fast-forward merge once reviewed).
Doctrine honored: contracts-first waves, flags default **OFF** and **fail-closed**,
TypeScript as source of truth with Swift mirror, no `.pbxproj` hand-edits,
commit-per-wave with the hash as evidence, three-strikes stop rule.

## The nine invariants → where they bind

| # | Invariant | Binds in | Primary artifact |
|---|-----------|----------|------------------|
| 1 | Formation over engagement | flag registry, ranking, notifications | purpose firewall in `governance/policyEngine.ts`; CI vanity-counter assertion |
| 2 | Constitution grounded in durable sources | GUARDIAN, Berean system prompt | conformance verdict on every mode |
| 3 | Companion Boundary (parasocial/idolatry) | Berean system prompt, GUARDIAN Guard mode, crisis path | boundary clauses + devotion-detection rule + outward handoff |
| 4 | Red lines in code | PRIVACY-CORE, GUARDIAN, export boundary | `RED_LINES` deny-list + red-line test suite |
| 5 | Intelligence proposes, people decide (HITL) | moderation, Connect, Berean actions | `ProposedConsequentialAction` + `authorize()` boundary |
| 6 | Gated capability (default-OFF + sign-off) | feature-flag schema, GUARDIAN | `FlagGovernanceSpec` + sign-off record |
| 7 | No fabricated Scripture (the Berean test) | Berean, RAG, citation rendering | `CitationGrounding` fail-closed grounding contract |
| 8 | Checks-and-balances over founder discretion | GUARDIAN (durable record), Constitution | `FounderRulingPolicy` immutable + amendment log |
| 9 | Standing pre-release safety audit | release process | re-runnable readiness checklist |

## Operating principle

Every invariant is **fail-closed**: if the system cannot *prove* the safe state, it
defaults to the restrictive state. New flags ship OFF. Unverifiable Scripture is not
asserted. No AI-only path reaches an irreversible mutation.

## Wave ledger (commit hash = evidence)

| Wave | Scope | Status | Commit |
|------|-------|--------|--------|
| 0 | Governance contracts freeze | done | `c793ad33` |
| 1 | Constitution deltas (inv. 3,4,8) | done | `42647b6b` |
| 2 | GUARDIAN policy-as-code (inv. 1,2,4,5,6,7,8) | done | `9ed000a2` |
| 3 | Berean system-prompt clauses (inv. 2,3,7) | done | `4af2d01b` |
| 4 | PRIVACY-CORE / data-export boundary (inv. 4) | done | `985b20ad` |
| 5 | Feature-flag safety_critical schema (inv. 6) | done | `fbffc716` |
| 6 | Red-line test suite + readiness gate (inv. 9 + all) | done | `4d42352d` |
| 7 | Final output docs + merge readiness | done | _(this commit)_ |

Validation: `tsc --strict` clean on all governance modules; **33 jest assertions green**
(29 core + 4 export-boundary); render audit exits 0. Swift build **HUMAN-PENDING** (the
Xcode workspace is the main tree, not this worktree).

## Out of scope (deliberately dropped)

Defense/Pentagon dynamics, offensive-cyber material, SaaS/market analysis, geopolitics,
and nation-state access tiering **do not apply to AMEN** and are not imported. AMEN is a
faith-and-community platform; the only transfer is the governance spine above.
