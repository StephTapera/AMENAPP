# Berean Voice OS — Wave 0 (Contracts & Recon)

**Status: ⛔ FREEZE GATE — awaiting human reconciliation & freeze of §4. Do NOT start Wave 1.**

Wave 0 reconciled the proposed §4 contracts against the **real** AMEN codebase
(8-agent recon, read-only). The headline finding: **a substantial Berean voice +
realtime layer already exists.** Most of §4 is REUSE/EXTEND, not greenfield. The
proposal also contains several **breaking naming collisions** that only a human
can resolve. Nothing was edited — these are review artifacts.

## What this package contains

| File | Purpose |
|---|---|
| `WAVE0_FREEZE_PROPOSAL.md` | The freeze table: every §4 symbol → REUSE / EXTEND / RENAME / BUILD-NEW, with the real existing equivalent. The reconciled Swift/TS contracts. Reuse map + genuinely-new work list. **This is the thing the human freezes.** |
| `WAVE0_FIRESTORE_RULES_SKELETON.md` | Proposed `match` blocks for the 7 collections, anchored to existing rule patterns + line numbers. Not yet written into `firestore.rules`. |
| `WAVE0_FLAGS_AND_PINECONE.md` | Flag registration plan (canonical `AMENFeatureFlags`) + Pinecone namespace conventions. |
| `DECISION_RECORDS.md` | DR-001 (pipeline-first transport) + DR-002 (realtime provider) in the 13-point format, with live-confirmed API/pricing research. |
| `OPEN_HUMAN_DECISIONS.md` | The §12 decisions that BLOCK the freeze. Surface, do not guess. |

## The five things a human must decide before Wave 1 (summary)

1. **`BereanVoiceMode` merge** — an enum of that exact name already exists with
   different cases (`conversation, prayer, churchNotes, discovery, wellness`).
   The proposed 8-case set is a breaking redefinition. Ratify the mapping.
2. **Retire `SafetyVerdict`** — the real type is `AmenModerationResult` +
   `AmenModerationSeverity`. It already has every field. Freeze the existing name.
3. **`prayerJournal` collision** — `users/{uid}/prayerJournal` already exists as
   owner-writable. The proposed encrypted CF-write-only one contradicts it.
   Rename (proposed `voicePrayerJournal`) or reconcile ACLs.
4. **Transport reality** — AI voice realtime is **WebSocket**, not WebRTC.
   WebRTC/LiveKit is group-rooms-only today (but reusable as a bridge). Freeze the
   abstraction, pick the provider separately (DR-002).
5. **Privacy/E2EE blockers** — `ConsentManifest`, `VoiceSessionContext`, encrypted
   `prayer-memory`, and the encrypted prayer journal all depend on the open
   PRIV-005 consent gate and the E2EE-account-recovery decision. They **cannot be
   frozen** until those land.

## Constraints honored this wave

- No `firestore.rules` / `AMENFeatureFlags.swift` / Swift contract edits (freeze pending).
- No `project.pbxproj` edits; no new Swift files (these are docs only).
- No builds run, no flags flipped, no functions deployed.
- All proposed new functions targeted to `us-east1`; `voicePrayer.js`'s hardcoded
  `us-central1` flagged as a pattern NOT to copy.
