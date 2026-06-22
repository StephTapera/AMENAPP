# Bug Review — Working-Tree Changes (2026-06-17)

Scope: the uncommitted changes on branch `cert/creator-role-self-write-clean-2026-06-17`.

Reviewed files:
- `AMENAPP/BereanOS/BereanMultilingualContracts.swift` (modified)
- `AMENAPP/DesignSystem/BereanLight/BereanLightTokens.swift` (modified)
- `Backend/functions/src/submitReport.ts` (modified)
- `BereanHomeView.swift` → `BereanStudyHubView.swift` (rename only)
- `ProfileSessionStoreTests.swift`, `ReauthGateTests.swift` (deleted)

---

## 🔴 FIXED — Evidence preservation silently lost on retry (`submitReport.ts`)

**Status: fixed in this session (batch refactor applied).**

### The bug
The new Tier-1 block added 5 additional sequential, non-transactional Firestore
writes (`moderationQueue`, `moderationCases`, `trustSafetyEvents`, `evidenceVault`,
`ncmecReadiness`) after the main `userReports` write. This interacted badly with
the 24h dedup guard at the top of the function:

1. First call commits `userReports/{reportId}` with `submittedAt = now`.
2. A later write (e.g. `evidenceVault.set()`) hits a transient error → function rejects.
3. Client retries.
4. `isDuplicateReport()` finds the already-committed `userReports` doc → returns
   `{ reportId: "duplicate_suppressed" }` and exits early.
5. The `moderationCase`, `evidenceVault` (legal hold), and `ncmecReadiness`
   records are **never created**, and no retry can create them for 24h.

For a child-safety / sextortion evidence-preservation path, a transient failure
permanently dropped the exact artifacts the block exists to guarantee.

Secondary issue: `moderationQueue` and `trustSafetyEvents` used `.add()`
(non-deterministic IDs), so any retry that *did* get past dedup would duplicate them.

### The fix
All severe-report records are now committed in a single `WriteBatch` →
all-or-nothing. Doc IDs are deterministic (`reportId`), so a retry either finds a
complete record set or cleanly re-creates it. Logging moved to after
`batch.commit()`. No behavior change to the optional `blockImmediately` write
(kept separate; idempotent `merge`).

### Human follow-up
- [ ] `npm run build` / `tsc` clean for the `creator` codebase locally.
- [ ] Deploy: `firebase deploy --only functions:creator:submitReport` from repo
      root (see CLAUDE.md Firebase rules — do NOT use untargeted deploy).
- [ ] Confirm Firestore rules deny client writes to the new collections
      (`moderationCases`, `trustSafetyEvents`, `evidenceVault`, `ncmecReadiness`)
      so only this Cloud Function can create them.
- [ ] All NCMEC/CyberTip gating still depends on the 4-part federal legal gate —
      `automatedCyberTipSubmitted` and `hashScanEnabled` MUST stay `false`.

---

## 🟢 CLEAN — `ScriptureRef` → `MultilingualScriptureRef` rename (`BereanMultilingualContracts.swift`)

No bug. The rename resolves a real duplicate-type conflict with
`struct ScriptureRef` at `AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift:179`.
`MultilingualScriptureRef` is now fully self-contained — every reference within
the contract file was updated, and no file outside this one referenced the old
type. The `case guard` → `` case `guard` `` change is also correct (escaping a
reserved keyword).

**No action required.**

---

## 🟢 CLEAN — `BereanReaderType` font tokens (`BereanLightTokens.swift`)

No bug. The new `enum BereanReaderType` aliases existing, valid `BereanType`
members (`displayTitle`, `sectionHeader`, `bodyReading`). It is a single
declaration (no redeclaration), and it satisfies usages already present in 7
Berean view files (Reader, Notes, Listening, Prayer, StudyHub, ReaderCard,
WordGlowLoader).

**No action required.**

---

## 🟡 MINOR — verify deleted tests were intentional

`ProfileSessionStoreTests.swift` and `ReauthGateTests.swift` are staged for
deletion. Not a code bug, but confirm this is intentional (e.g. the code under
test was removed/renamed) and not an accidental loss of coverage for the
reauth/session lanes.

- [ ] Confirm deletion is intentional.

---

## Summary

| Item | Severity | Status |
|------|----------|--------|
| Evidence preservation lost on retry (submitReport.ts) | 🔴 High | Fixed (batch) — needs deploy |
| ScriptureRef rename | 🟢 None | Clean |
| BereanReaderType tokens | 🟢 None | Clean |
| Deleted reauth/session tests | 🟡 Minor | Confirm intent |
