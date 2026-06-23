# Standing Pre-Release Readiness Gate (Wave 6, Invariant 9)

A **re-runnable** gate that must pass clean before a build is eligible for submission.
Run it before every release — it is not a one-time event.

## What it composes

1. **Red-line suite** — `Backend/functions/src/governance/__tests__/redLine.test.ts`
   (29 assertions across invariants 1–8).
2. **Flag-state audit** — `auditFlagRegistry()` via `readinessGate.test.ts`
   (every safety-critical flag default-OFF + un-enableable without sign-off).
3. **Export boundary** — `functions/context/__tests__/amenExclusionValidator.redline.test.ts`
   (crisis + spiritual-surveillance keys rejected).
4. **Render audit** — `scripts/governance/no-spiritual-scoring-render.mjs`
   (no spiritual-scoring field rendered in Swift).
5. **Five NO-GO blockers** — encoded in `readinessGate.test.ts#NO_GO_BLOCKERS`;
   `isSubmissionEligible` is false while any remains unresolved.

## How to run

```sh
# 1. Core governance red-line + readiness suites
cd Backend/functions && npx jest src/governance/__tests__

# 2. Export-boundary red lines
cd functions && npx jest context/__tests__/amenExclusionValidator.redline.test.ts

# 3. Spiritual-scoring render audit
node scripts/governance/no-spiritual-scoring-render.mjs AMENAPP

# 4. Swift red-line suite (Xcode, on the quiet tree)
#    RunSomeTests → GovernanceRedLineTests   (HUMAN-PENDING: needs target membership)
```

## Current verdict

- TS suites: **GREEN** (33 assertions).
- Render audit: **GREEN**.
- Swift suite: **HUMAN-PENDING** (authored; worktree cannot drive Xcode).
- **Submission eligibility: NO-GO** — **4** NO-GO blockers unresolved (was 5).

### Blocker status (verified against live code)

| ID | State | What remains |
|----|-------|--------------|
| P10-Y1 | ✅ **RESOLVED** | ATT prompt wired (`AppDelegate.swift`) + `NSUserTrackingUsageDescription` in pbxproj. |
| FR-3 | 🟡 code-complete | Swift suite must run GREEN on the quiet tree (build HUMAN-PENDING). Commit `18eee8cf`. |
| P10-R1 | 🟡 code-side done | DPO/legal must classify analytics in the App Store privacy questionnaire. |
| P5-Y2 | 🔴 legal/federal | ESP + NCMEC registration before any reporting path is wired. |
| P5-R1 | 🔴 **red line** | CSAM hash-provider contract + legal sign-off + non-engineer review. `csam_hash_scan_enabled` stays OFF. **Never a DIY build.** |

P5-Y2 and P5-R1 are gated by the non-overridable `csam` red line and **cannot be
resolved in code** — that is by design (invariants 4, 6, 8).
