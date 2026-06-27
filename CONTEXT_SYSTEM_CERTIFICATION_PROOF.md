# Context System — Certification Proof Chain

**Verdict (2026-06-27): `CONTEXT SYSTEM CERTIFICATION BLOCKED`**

Safe surfaces remain live; the system is **not** release-certified. The three human-controlled
proof artifacts do not yet exist, and a flag regression contradicting the lock was found and
corrected (see Finding C-1). This file records evidence; it does **not** upgrade the lock.

Governing record: [`CONTEXT_SYSTEM_RELEASE_GATE.md`](CONTEXT_SYSTEM_RELEASE_GATE.md).

---

## Phase 1 — Tree & lock state

| Item | Expected | Actual | Status | Evidence |
|---|---|---|---|---|
| Branch | — | `feature/liquid-glass-hero` | — | `git branch --show-current` |
| Working tree quiet | clean | **67 changed files, 10+ concurrent agents editing app code** | ❌ NOT QUIET | `git status --short` |
| Lock wording present | exact string | present (lines 3, 104) | ✅ | `grep` CONTEXT_SYSTEM_RELEASE_GATE.md |
| Lock names both LLM flags as must-stay-OFF | yes | yes (line 11) | ✅ | same |
| `context_universal_import_enabled` OFF | OFF | **was ON in code → corrected to OFF** | ⚠️→✅ | Finding C-1 |
| `context_berean_interview_enabled` OFF | OFF | **was ON in code → corrected to OFF** | ⚠️→✅ | Finding C-1 |
| Safe-surface flags may be ON | ON allowed | ON (system/manual/matching/export/qr) | ✅ | `AMENFeatureFlags.swift` |

### Finding C-1 (CRITICAL) — LLM flags defaulted ON, contradicting the lock

The canonical, git-tracked `AMENAPP/AMENFeatureFlags.swift` had **both** untrusted-LLM-input
flags set to `true` in two places:

- Stored-property initial values (lines ~423 / ~425): `= true`
- `buildDefaults` fallback dictionary (lines ~1682 / ~1683): `true`

These flags gate the live LLM paths via `guard flags.context…Enabled else { … }` in
`BereanMigrationService` (line 122), `ContextExtractionService` (line 200), and four UI entry
points (`AmenPassportView`, `BereanInterviewView`, `MigrationPromptView`, `ContextImportView`).
With the flag `true`, those guards **pass** and the untrusted-LLM paths are **OPEN** — a
fail-open on exactly the paths the lock requires to stay OFF until Proof #3.

**Root cause (commit timeline):**

| Commit | Time (2026-06-27) | Effect |
|---|---|---|
| `b1eced4f` "Enable Ambient OS and mark live" | 01:51 | swept Context LLM flags ON (blast radius; msg is about Ambient OS) |
| `2cc03cba` LOCK Context System release gate | 02:50 | lock says these two stay OFF |
| `f0f344d2` finalize lock-of-record | 03:35 | lock is the latest governing decision |

The lock was authored **after** the inadvertent flip but the code defaults were never corrected.

**Correction applied (lock-enforcing, fail-closed):** both flags set to `false` in both
locations, with inline comments referencing the lock. Safe-surface flags left ON per the lock.
This flips nothing ON and does not certify; it restores the lock-required OFF state.
Note: effective runtime value is the Remote Config console value when reachable; this change
guarantees fail-**closed** behavior on first launch / offline / fetch-failure.

---

## Phase 2 — Already-closed evidence (verified present)

| Closed item | Required evidence | Status | Evidence |
|---|---|---|---|
| Account-deletion purge | `deleteContextStore()` Phase 7e | ✅ | `Backend/functions/src/userAccountDeletionCascade.ts:128,407`; commit `e133efca` |
| Privacy manifest | `OtherUserContent` + `SensitiveInfo`, `Tracking=false` | ✅ | `AMENAPP/PrivacyInfo.xcprivacy` — both types present, all entries `Tracking:false` |
| Camera permission | paste-token QR only, no `AVCaptureSession` in context path | ✅ | only non-context camera files (`SingleCamCaptureService`, `WitnessCameraViewModel`, `ONELiquidCameraView`); no `NSCameraUsageDescription` tied to context |

---

## Phase 3 — Proof #1: Quiet-tree full archive

**Result: `Proof #1 BLOCKED — tree is not quiet.`**

- Tree status: 67 modified/staged/untracked files, many app `.swift` files with `MM` (staged + working-tree) state.
- Concurrent agents: 10+ actively editing app files (Connect, ResourcesGlass, ComposeIntelligence, Spiritual OS, composer, music, tab bar, …).
- Archive command: **not run** — the rules forbid archiving from a dirty or contested tree.
- Archive log: none.
- Archive artifact: none.

Fixed proof order means Proofs #2 and #3 cannot proceed until #1 produces a clean archive on a quiet tree.

---

## Phase 4 — Proof #2: ASC privacy nutrition-label questionnaire

**Result: `Proof #2 BLOCKED — ASC privacy questionnaire not completed.`**
Gated behind Proof #1; requires human ASC web access. Manifest side is ready
(`OtherUserContent`, `SensitiveInfo`, `Tracking=false` all present) for the eventual match.

---

## Phase 5 — Proof #3: On-device App-Check-valid live bait test

**Result: `Proof #3 BLOCKED — on-device App-Check-valid live bait test not completed.`**
Gated behind Proofs #1–#2; requires a signed-in device session with a valid App Check token
against the deployed `extractContextFacets`. Headless `AMENAPPTests/ContextRedTeamTests.swift`
covers only the denylist/C59 layer and is supplemental, not a substitute.

---

## Phase 6 — Flag decision

**Option A — keep LLM flags OFF.**

- `context_universal_import_enabled`: **OFF** (corrected to fail-closed)
- `context_berean_interview_enabled`: **OFF** (corrected to fail-closed)
- Why OFF: all three certification proofs are BLOCKED; the lock requires OFF until they pass.
- Additional proof required: quiet-tree archive → ASC questionnaire → on-device live bait test.
- Owner / next action: human release engineer to run Proofs #1–#3 on a quiet tree.

No flag was enabled. Rule #1 (do not flip ON) honored.

---

## Phase 7 — Cross-file reconciliation

- `CONTEXT_SYSTEM_RELEASE_GATE.md`: unchanged — remains the lock of record; code now matches it.
- `CONTEXT_SYSTEM_CERTIFICATION_PROOF.md`: this file (new).
- `ASC_PRIVACY_CONTEXT_ALIGNMENT.md` / `CONTEXT_LIVE_BAIT_TEST_RESULTS.md`: not created — their proofs are BLOCKED (no artifacts to record yet).
- `GO_NO_GO.md` / `READINESS_AUDIT.md` / `AGENT_LANES.md` / `QA_RESULTS.md`: not modified in this pass (contested tree; no contradiction introduced).

**Status statement (Rule 1 — proofs missing):**
*Context System is safe-surface live, but not release-certified. This file is the lock of record.*

---

## Required final statement

Context System remains safe-surface live, but not release-certified. Do not flip
`context_universal_import_enabled` or `context_berean_interview_enabled` until quiet-tree
archive, ASC privacy questionnaire alignment, and on-device App-Check-valid live bait testing
all pass with real artifacts.
