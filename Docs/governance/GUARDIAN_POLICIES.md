# GUARDIAN Policy-as-Code (Wave 2)

Pure, deterministic policy functions binding invariants 1, 2, 4, 5, 6, 7, 8 into
enforceable checks. They run identically in the Berean pipeline, in CI, and in the
red-line test suite. Fail-closed throughout: an unprovable safe state yields
`blocked`/`degraded`, never `pass`.

Source: `Backend/functions/src/governance/{policyEngine,humanInLoop,bereanGuardrail}.ts`

## Policy registry

| Policy ID | Invariant | Function | Blocks when |
|-----------|-----------|----------|-------------|
| `INV1_PURPOSE_FIREWALL` | 1 | `evaluateFlagPurpose` | Flag purpose names engagement/DAU/retention mechanics |
| `INV2_CONFORMANCE` | 2 | `conformanceVerdict` | Constitutional review failed and not degraded |
| `INV4_RED_LINE_DENY` | 4 | `assertNoRedLineOverride` | Flag tries to override/bypass a red line |
| `INV6_DEFAULT_OFF` | 6 | `evaluateFlagDefaultState` | safety_critical flag ships default-ON |
| `INV6_ENABLE_GATE` | 6 | `canEnableFlag` | safety_critical enabled without complete sign-off |
| `INV7_GROUNDING` | 7 | `enforceGrounding` | Unverifiable citations present (stripped, degraded) |
| `INV8_IMMUTABLE_RULINGS` | 8 | `assertFounderRulingsImmutable` | Ruling not immutable / amendment lacks change-control |
| (HITL) | 5 | `authorizeConsequentialAction` | No complete human `approve` decision attached |

## Invariant 5 — the HITL chokepoint

`authorizeConsequentialAction<T>` returns an `execute()` function **only** on the
authorized branch (a complete human `approve`). There is no other way to obtain the
executor, so no AI- or automation-proposed consequential action can reach a mutation
without a recorded human decision. `HUMAN_REQUIRED_KINDS` enumerates the actions that
must route through it (bans, takedowns, minor-data, spiritually-binding rulings,
community shutdown, monetization suspension, law-enforcement disclosure, appeals).

## Live binding — `guardBereanEmission`

Wired into `bereanPipeline.ts#stageFinalResponse`. Every mode's candidate answer is
guarded before emission:

1. **Companion Boundary (inv. 3):** if the candidate contains parasocial/idolatry
   language ("keep talking to me", "confess to me", mediator/authority claims), an
   **outward handoff** (`OUTWARD_HANDOFF_TEXT`) is appended — pointing the user to God,
   church, pastor, trusted believers — and the violation is recorded.
2. **Conformance verdict (inv. 2):** a `GovernanceVerdict` naming the Constitution
   version is recorded to the `berean_pipeline_traces` document.
3. **Grounding (inv. 7):** `enforceGrounding` strips any unverifiable citation
   (verse-level grounding is additionally enforced upstream in the scripture review).

Recorded fields added to each trace: `governanceVerdicts`, `companionBoundaryViolations`,
`outwardHandoffApplied`, `constitutionVersion`.
