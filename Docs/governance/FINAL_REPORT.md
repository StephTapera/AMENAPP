# AMEN Governance Hardening — Final Report

Branch `feature/governance-hardening` (isolated worktree). Nine formation-first
invariants bound into AMEN's existing systems across 8 commits. This report collects the
remaining required deliverables; the per-area docs in this directory carry the detail.

## 1. Feature map (where each invariant binds)

| Inv | Bound in (file) | Commit |
|-----|-----------------|--------|
| 1 Formation>engagement | `policyEngine.ts#evaluateFlagPurpose`; `no-spiritual-scoring-render.mjs` | 9ed000a2, 4d42352d |
| 2 Durable grounding | `constitutionalConfig.ts`; `systemPrompt.ts#GROUNDING_CLAUSE`; `policyEngine.ts#conformanceVerdict` | 42647b6b, 4af2d01b, 9ed000a2 |
| 3 Companion Boundary | Constitution `companionBoundary`; `COMPANION_BOUNDARY_CLAUSE`; `assessCompanionBoundary` + pipeline handoff | 42647b6b, 4af2d01b, 9ed000a2 |
| 4 Red lines | `contracts.ts#RED_LINES`; `amenExclusionValidator.ts`; render audit | c793ad33, 985b20ad, 4d42352d |
| 5 HITL | `humanInLoop.ts#authorizeConsequentialAction` | 9ed000a2 |
| 6 Gated capability | `flagRegistry.ts`; `AMENFeatureFlagGovernance` | fbffc716 |
| 7 No fabricated Scripture | `EPISTEMIC_HONESTY_CLAUSE`; `enforceGrounding` | 4af2d01b, 9ed000a2 |
| 8 Checks & balances | Constitution `founderRulings`; `assertFounderRulingsImmutable` | 42647b6b, 9ed000a2 |
| 9 Standing audit | `readinessGate.test.ts`; `READINESS_GATE.md` | 4d42352d |

## 2. Backend schema / migration plan

- **Firestore `berean_constitution/v1`**: re-seed from `DEFAULT_CONSTITUTION` (now v1.1.0)
  to persist the three new articles. **No migration required** in the interim — the loader
  fail-closed-backfills missing articles, so the red lines/boundary are always live.
- **Firestore `berean_pipeline_traces/{traceId}`**: now also writes `governanceVerdicts`,
  `companionBoundaryViolations`, `outwardHandoffApplied`, `constitutionVersion` (additive;
  no schema migration of existing docs).
- No user-document migrations. No index changes.

## 3. API / route surface touched

| Callable / module | Codebase | Change |
|-------------------|----------|--------|
| `bereanPipeline` (onCall) | Backend/functions | `stageFinalResponse` routes through `guardBereanEmission` |
| `exportAmenFile` (onCall) | functions (default) | exclusion validator extended (crisis + surveillance) |
| `governance/*` | Backend/functions | new pure modules (no new HTTP endpoints) |

## 4. Frontend component / surface list (iOS)

| File | Change |
|------|--------|
| `BereanConstitutionalConfig.swift` | v1.1.0 mirror + boundary/red-line/ruling helpers |
| `AMENFeatureFlags.swift` | `AMENFeatureFlagGovernance` fail-closed sign-off gate |
| `GovernanceRedLineTests.swift` | Swift Testing suite (HUMAN-PENDING target membership) |

## 5. AI Constitution policy file

`Backend/functions/src/berean/constitutionalConfig.ts` (v1.1.0) + `CONSTITUTION_DELTAS.md`.

## 6. Moderation severity matrix

| Sev | Name | Action | AI may act alone? |
|-----|------|--------|-------------------|
| 0 | Safe | none | n/a |
| 1 | Low | soft nudge / edit suggestion | yes (advisory only) |
| 2 | Medium | visibility reduction / label / queue | yes (reversible only) |
| 3 | High | temp restriction + human queue + evidence preserve | **no** — proposes via HITL |
| 4 | Critical | T&S escalation / crisis / child-safety / legal | **no** — HITL + red-line path |

Enforced by `humanInLoop.ts`: every Sev-3/4 consequential action (`HUMAN_REQUIRED_KINDS`)
can only execute through a recorded human `approve`. No AI-only path reaches an
irreversible mutation.

## 7. Privacy / security threat model (governance scope)

| Threat | Mitigation |
|--------|-----------|
| Engagement-maximizing flag slips in | purpose firewall rejects; CI fails |
| safety_critical flag ships ON / enabled silently | default-OFF schema + sign-off gate; CI fails default-ON |
| AI auto-bans / auto-takedowns | HITL chokepoint; no executor without human approve |
| Berean becomes object of attachment | Companion Boundary (prompt + GUARDIAN handoff + Constitution) |
| Fabricated Scripture asserted | grounding fail-closed strips unverifiable citations |
| Crisis data leaks to export/analytics/training | export validator hard-rejects crisis keys |
| Spiritual surveillance / scoring | scoring fields rejected at export + render audit; founder rulings immutable |
| Stale Firestore drops a red line | loader fail-closed backfill |
| Founder ruling quietly reversed | immutability check + amendment change-control |

## 8. Test plan & 11. QA report

- **TS:** `tsc --strict` clean on all governance modules.
- **Jest:** 33 assertions green — 29 core red-line/readiness (`redLine.test.ts`,
  `readinessGate.test.ts`) + 4 export-boundary (`amenExclusionValidator.redline.test.ts`).
- **Render audit:** `no-spiritual-scoring-render.mjs` exits 0.
- **Swift:** `GovernanceRedLineTests.swift` authored; **HUMAN-PENDING** (worktree can't
  drive Xcode; needs AMENAPPTests target membership).

## 9. Rollout plan

1. Fast-forward merge `feature/governance-hardening` onto the target branch (additive;
   designed conflict-light).
2. Add `GovernanceRedLineTests.swift` to the AMENAPPTests target; run the Swift suite on
   the quiet tree (clears the HUMAN-PENDING gate).
3. Re-seed `berean_constitution/v1` from v1.1.0 (optional — backfill covers interim).
4. Wire the four CI steps from `READINESS_GATE.md` into the pre-submission pipeline.
5. All new flags stay OFF; safety_critical flags stay un-enableable until a signed-off PR.
6. Rollback: revert the merge commit — all changes are additive and flag-free at runtime
   except the pipeline guardrail (which only ever appends an outward handoff / strips
   unverifiable citations, never blocks a previously-passing answer).

## 12. Gaps & risks

See `GAPS.md`. **All three G-items (G-1/G-2/G-3) are now closed** (commit `18eee8cf`).
G-2 closed NO-GO blocker `FR-3` in code (build-verification pending).

Submission eligibility remains **NO-GO**, now **4 blockers** (was 5): P10-Y1 (ATT) is
resolved against live code; FR-3 is code-complete pending the Swift suite; P10-R1 awaits a
DPO/legal classification; **P5-Y2 and P5-R1 are red-line-protected legal/federal gates that
cannot be resolved in code** (ESP/NCMEC registration, hash-provider contract, written legal
sign-off, non-engineer review). See `READINESS_GATE.md` for the per-blocker table.
