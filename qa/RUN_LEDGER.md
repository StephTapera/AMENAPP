# AMEN — Autonomous QA Sweep · RUN LEDGER

**Date:** 2026-06-17
**Orchestrator:** Claude (Opus 4.8)
**Wave:** 0 — Environment + contract freeze (sequential)
**Verdict:** ⛔ **NO-GO — STOPPED AT WAVE 0 GATE.** No agents spawned. App never launched. Nothing pointed at any Firebase project.

---

## Why stopped

The sweep may run **only** against Firebase emulators, never production. The app has
**no emulator wiring**, the default Firebase project is **production**, and the
**CSAM/NCMEC + Aegis outbound is not stubbed** for the emulator. Each of these is an
independent hard STOP under the prompt's RED LINES. Proceeding would risk live writes
to prod and/or filing **real NCMEC/Aegis reports from synthetic test traffic** — the
single most serious red line.

Adding the emulator wiring and the NCMEC outbound suppression are **human-owned** steps
(companion checklist §0 and §2). I did not add them: stubbing/altering a child-safety
control to make a run possible is itself a red line, even when the change is the
"correct" emulator suppression. These must be done and verified by a human.

---

## Detection results

| Wave-0 check | Required | Found | Status |
|---|---|---|---|
| `firebase.json` emulators block | auth, firestore, functions, storage, ui | auth:9099, firestore:8080, functions:5001, ui:4000 — **storage:9199 MISSING** | ⚠️ Partial |
| Default Firebase project | emulator / dedicated test project | `.firebaserc` default = **`amen-5e359` (PROD)** | ⛔ Blocker |
| App→emulator wiring | `useEmulator(...)` + `-useFirebaseEmulator` launch arg in launch path | **Zero matches** in any Swift source; absent from `AMENAPPApp.swift` & `AppDelegate.swift` | ⛔ Blocker |
| CSAM/NCMEC + Aegis outbound stub | `FUNCTIONS_EMULATOR` guard suppressing real report, blocking still ON | **No guard** in `functions/ncmecReporter.js` or `functions/moderation/cyberTiplineInterface.js` | ⛔ Blocker (human-gated) |
| Seed data | `emulator-seed/` present | **Absent** | ⛔ Blocker |
| UI driver | idb / simctl / **existing** UITest target (no pbxproj edit) | ✅ Existing target `AMENAPPUITests/` (FullAppSmoke, HomeFeed, Berean, Payments, Accessibility, Phase34…) | ✅ Available |
| Build toolchain | Xcode scheme + builder | ✅ `AMENAPP` scheme + xcode-tools MCP `BuildProject` | ✅ Available |

---

## Blockers → required human actions (all must be true before re-running)

1. **App→emulator wiring (companion §2).** Add, at the very top of the launch path
   immediately after `FirebaseApp.configure()` and before any Firestore access, the
   `#if DEBUG` + `-useFirebaseEmulator` block pointing Auth/Firestore/Functions/Storage
   at `127.0.0.1`. Add `-useFirebaseEmulator` to the Run scheme arguments.
   *Done when:* an app write appears in the Firestore emulator, not prod.

2. **CSAM/NCMEC + Aegis outbound stub (companion §0).** In `ncmecReporter.js` and the
   moderation/CSAM functions, guard the real report/escalation send behind
   `if (process.env.FUNCTIONS_EMULATOR === 'true') { /* skip real send */ }` —
   **keep blocking/fail-closed ON.** *Done when:* a test "bad content" post is still
   rejected, but no real report leaves.

3. **Storage emulator** — add the `storage: { port: 9199, host: "127.0.0.1" }` entry to
   the `emulators` block in `firebase.json`.

4. **Seed data (companion §4)** — create `./emulator-seed` with test users + a few posts
   (Emulator UI + `--export-on-exit`, or a `firebase-admin` script).

5. **Bring emulators up (companion §1)** —
   `firebase emulators:start --only auth,firestore,functions,storage --import=./emulator-seed --export-on-exit=./emulator-seed`,
   confirm UI at http://127.0.0.1:4000.

When all of the above are true (companion checklist §7 GO/NO-GO), re-run the prompt.
Wave 0 will then freeze `qa/FLOW_CONTRACT.md` and Waves 1–3 can proceed.

---

## Wave 0 progress (safe, no app run)

- ✅ `qa/FLOW_CONTRACT.md` **frozen** — 15 flows mapped from code (entry points, controls,
  expected success/error), safety-blocked outcomes tagged `[EXPECTED-BLOCK]`. Derived from
  read-only analysis; no app launched, no Firebase project contacted.
- ⛔ Waves 1–3 (drive Simulator, repair, report) remain **NO-GO** pending the 5 human
  actions above. The existing `AMENAPPUITests/` target is the intended UI driver once unblocked.

## What was NOT done (by design)

- No QA branch created, no commits.
- No agents/explorers/fixers spawned.
- App never built or launched; no Firebase project contacted.
- No code edited — specifically, **no** emulator wiring or NCMEC stub added (human-gated).
