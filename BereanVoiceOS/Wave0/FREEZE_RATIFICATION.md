# Wave 0 — Freeze Ratification (human, 2026-06-17)

## Decisions

| # | Decision | Ruling | Status |
|---|---|---|---|
| D1 | `SafetyVerdict` | **RETIRE → reuse `AmenModerationResult`.** Callable returns the real moderation result. | ✅ FROZEN |
| D2 | `BereanVoiceMode` | **EXTEND additively** — no breaking redefinition. Keep existing cases canonical; map the proposed 8-case set onto them (per `WAVE0_FREEZE_PROPOSAL.md §2`). | ✅ FROZEN |
| D3 | `prayerJournal` | **New encrypted collection `voicePrayerJournal`** with its own rules; do NOT overload existing `prayerJournal` ACLs. *Provisional — re-confirm if D5 changes the encryption shape.* | ✅ FROZEN (provisional) |
| D4 | Transport / provider + LiveKit reuse | **RESERVED — founder.** Deciding axis is privacy/retention + child-safety (where minors' spoken prayers go), not latency/cost. | ⛔ OPEN |
| D5 | PRIV-005 / E2EE (`ConsentManifest`, `VoiceSessionContext`, encrypted `prayer-memory`) | **RESERVED — product + legal + values.** Same standing E2EE/privacy blocker carried across the project. | ⛔ OPEN |

## What the open decisions block

- **D4 blocks:** Path B (realtime) wave; any new mint topology choice; `DecisionRecord` cost figures (UNVERIFIED pricing).
- **D5 blocks:** `ConsentManifest`, `VoiceSessionContext`, encrypted `prayer-memory` namespace, the encrypted `voicePrayerJournal` design (rules skeleton stays drafted, not shipped).

The D1–D3 surfaces and all REUSE/EXTEND items **not** gated by D4/D5 are frozen and buildable. Voice waves that depend on D4/D5 wait.

## Launch coupling decision (gatekeeper)

**Voice is decoupled from the App Store submission.** Ship the existing app with the
voice surface behind its flag (`berean_voice_enabled` = OFF). Bring voice online as a
**fast-follow** once D4/D5 land and the kill switch is verified. This keeps the
end-of-month date off the slow human/legal long-pole (provider, E2EE, consent).

## Separate P1 — DONE (independent of the freeze)

**Migrated `BereanVoiceFeatureFlags.swift` to honor Remote Config so the voice kill
switch works.** Previously every flag returned `true` unconditionally, so production
voice could only be disabled via an App Store update — a NO-GO for a voice surface
minors can reach.

Changes (fast diagnostics: 0 new issues):
- `AMENAPP/AMENFeatureFlags.swift` — registered 5 RC-backed sub-flags (`@Published`
  default OFF + RC defaults + refresh hydration): `berean_voice_duplex`,
  `berean_voice_interrupt`, `berean_voice_mode_empathy`, `berean_voice_mode_church`,
  `berean_voice_mode_prayer`.
- `AMENAPP/BereanVoiceFeatureFlags.swift` — rewritten as a thin `@MainActor` façade
  over `AMENFeatureFlags.shared`; sub-flags additionally gated by the master so none
  can be live while voice is killed. Call-site API unchanged (`BereanVoiceViewModel`,
  `BereanLiveVoiceView` compile clean).

Net effect: flipping `berean_voice_enabled` (or any sub-flag) in Remote Config now
actually takes effect at runtime. Default state remains OFF — voice ships dark.

> **Build-broker:** ready for canonical human build. Per-file Xcode diagnostics are
> clean on all four touched/dependent files; full build is the human's to run.

## Next

Per the build prompt: §4 is **partially frozen** (D1–D3). Do **not** start Wave 1
voice transport until D4/D5 are decided — those determine the transport, consent,
and encryption shapes Wave 1 would build on. The non-voice app proceeds to
submission independently with voice flag OFF.
