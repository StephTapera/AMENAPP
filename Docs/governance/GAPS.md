# Governance — Gaps & Risks Register

Honest ledger of what is **bound and enforced** vs. what is **specified but still
open**. Nothing here is silently claimed as done.

## Resolved (was: open items requiring a human decision)

All three open items were decided and closed end-to-end. History kept for audit.

| ID | Item | Decision & how it is now enforced |
|----|------|------------------------------------|
| G-1 | **`prayerStreak` (BereanPrayer)** | **KEPT — verdict recorded.** Review found it already meets invariant 1: the count is hidden (`vanityMetricsAlwaysHidden`), the UI reads "Your prayer rhythm" (never a number or "don't break your streak"), it is private/never-compared, and there are no streak-tied notifications. The decision is now codified as a `REVIEWED_PERMITTED` entry in `scripts/governance/no-spiritual-scoring-render.mjs`, emitted on every CI run — the durable record (invariant 8), not a dangling doc note. |
| G-2 | **Crisis field-level encryption-at-rest** | **CLOSED — red line `crisis_data_unencrypted` enforced.** `SafetyPlanStore` now AES-GCM encrypts the safety plan with a device-local Keychain key (`CrisisSafetyPlanCipher`), migrates any legacy plaintext blob and strips it, and **fails closed** — if encryption is unavailable it holds the plan in memory rather than persisting plaintext. Covered by `CrisisSafetyPlanEncryptionTests` (round-trip, tamper, encrypted-persist, migration). |
| G-3 | **`genkit/` ungoverned prompt** | **CLOSED — governed.** The hard-coded three-line prompt in `genkit/berean-flows.ts` and `genkit/src/index.ts` is replaced by the canonical clauses (grounding / Companion Boundary / epistemic honesty + authority hierarchy) mirrored in `genkit/governed-prompt.ts`. Every theological flow now routes through `governed()`. Marked as the source-of-truth mirror of `Backend/functions/src/berean/prompts/systemPrompt.ts`. |

## Bound & enforced (this branch)

- Constitution v1.1.0: Companion Boundary + Red Lines + Founder Rulings; fail-closed backfill at load.
- GUARDIAN policy-as-code: purpose firewall, conformance verdict, red-line deny, HITL chokepoint, grounding, immutable rulings.
- Berean pipeline: `guardBereanEmission` wired into `stageFinalResponse` (outward handoff + recorded verdicts).
- Berean system prompt: grounding + Companion Boundary + epistemic-honesty clauses on every mode.
- Export boundary: crisis-path + spiritual-surveillance keys hard-rejected by `amenExclusionValidator`.
- Flag schema: `safety_critical` default-OFF + sign-off gate (TS registry + Swift mirror).
- Crisis at-rest encryption: `SafetyPlanStore` AES-GCM + device-local Keychain, fail-closed (red line `crisis_data_unencrypted`).
- genkit deployment: governed via `genkit/governed-prompt.ts` mirror (no ungoverned theological emission path).
- Tests: 33 TS red-line/readiness assertions green; render-audit clean; Swift suite authored (HUMAN-PENDING target membership).

## Build / validation status

- **TypeScript:** `tsc --strict` clean on all governance modules; **33 jest assertions green**
  (29 core red-line/readiness + 4 export-boundary).
- **Render audit:** `scripts/governance/no-spiritual-scoring-render.mjs` exits 0.
- **Swift:** authored to compile; **HUMAN-PENDING** — the Xcode workspace is the main tree, not
  this worktree, and `GovernanceRedLineTests.swift` needs AMENAPPTests target membership.
