# HUMAN-GATED — report-only items (red line: do NOT auto-fix)

These were surfaced statically but fall on the wrong side of a RED LINE. Report only;
a human owns the fix and any verification.

## DEL-01 — Account deletion: currentUser handling
- **File:** `AccountDeletionService.swift:~116`
- **Red line:** auth security / account-recovery / E2EE.
- **Observation:** `Auth.auth().currentUser?.delete()` — explorer flagged a possible crash if the
  session is invalid at delete time. Optional chaining means it likely no-ops rather than crashes,
  but the deletion/teardown ordering and the "what if currentUser is nil" path should be reviewed
  by a human, since it sits in the account-deletion/auth-security domain.
- **Recommended human action:** review the deletion sequence; ensure graceful handling (and correct
  data-teardown order) when `currentUser` is nil / token expired. Do not let an agent edit this path.

## SET-02 — Delete Account navigation + re-auth sheet
- **File:** `SettingsView.swift:~170-174` → `DeleteAccountView`
- **Red line:** auth security.
- **Observation:** Nav wiring looks correct; the re-auth sheet is the security control (EXPECTED).
  Flagged only so a human confirms the re-auth sheet always presents before any deletion call.
- **Recommended human action:** human verification during the eventual emulator run; no agent edit.

---

## Wave-0 environment blockers (also human-gated) — see qa/RUN_LEDGER.md
1. App→emulator wiring absent (companion §2).
2. CSAM/NCMEC + Aegis outbound not stubbed for emulator (companion §0) — keep blocking ON.
3. `storage:9199` missing from `firebase.json` emulators block.
4. No `./emulator-seed` data.
5. Default Firebase project = `amen-5e359` (prod).
