# Wave 0 — Open Human Decisions (BLOCK the freeze; do NOT guess)

These must be resolved by a human before the relevant part of §4 can be frozen and
the corresponding wave can start. Grouped by what they block.

## A. Naming / contract collisions — block the freeze itself

1. **`BereanVoiceMode` merge ratification.** An enum of that exact name already
   exists with different cases (`conversation, prayer, churchNotes, discovery,
   wellness`) and overlaps `BereanRealtimeSessionType`. Approve the proposed 8-case
   merge + primitive bindings in `WAVE0_FREEZE_PROPOSAL.md §2`, or amend. This is a
   **breaking** enum change — every call site migrates. *Blocks: §4.1 mode freeze, all mode waves.*

2. **Retire `SafetyVerdict` → `AmenModerationResult`.** Confirm the new callable
   returns the existing `AmenModerationResult`/`AmenModerationSeverity` (it already
   has every field) rather than a new verdict type. *Blocks: §4.2 freeze.*

3. **`prayerJournal` collision.** `users/{uid}/prayerJournal` already exists as
   owner-writable (rules ~2476/2806). Pick `voicePrayerJournal` (recommended) or
   reconcile the ACL models. *Blocks: §4.3 prayer rule + Wave 4.*

## B. Transport / provider / cost (DR-002) — block Path B (realtime) wave

4. **Provider choice.** OpenAI gpt-realtime (native WebRTC, premium audio) vs
   Google Gemini Live (WS-only, ~10–30× cheaper, needs a WebRTC bridge) vs fully
   on-device pipeline ($0/min). Depends on latency bar, budget, and the
   free-at-every-tier mandate.

5. **Realtime vs pipeline architecture.** Commit to a single speech-to-speech model,
   or the hybrid (Apple on-device STT + text LLM + on-device TTS). DR-001 recommends
   **pipeline first**; confirm.

6. **LiveKit reuse.** Route Berean Voice media through the **existing** LiveKit +
   `generateLiveKitToken` WebRTC infra (reuses proven transport + mint, enables
   WS-only providers) vs connect directly to a provider's native WebRTC. Determines
   whether any new mint callable is even needed (current lean: none — reuse
   `createRealtimeSession`/`generateLiveKitToken`).

7. **TTS source.** `AVSpeechSynthesizer` system voices (free/offline/default-safe)
   vs Personal Voice (on-device but **Apple-restricted to AAC/accessibility** —
   App-Review/legal call) vs cloud/realtime-model TTS (cost + privacy zone).

8. **Pricing confirmation.** `gpt-realtime-mini` per-1M rates were **NOT** in
   official results (UNVERIFIED); Gemini figures came partly from third-party blogs.
   Confirm official numbers before any `DecisionRecord` cost figure is locked.

## C. Privacy / encryption — block consent + sensitive-memory design

9. **Privacy zone / consent placement (PRIV-005).** Which privacy data-zone voice
   audio + transcripts fall into, and whether realtime audio **leaving the device**
   is compatible with the frozen Privacy Core Contract (encrypted-at-rest,
   MEDIA-GATE fail-closed) and the PRIV-005 Berean AI consent gate. *Blocks:
   `ConsentManifest`, `VoiceSessionContext`.*

10. **E2EE account-recovery.** If `prayer-memory` / voice prayer journal are
    encrypted-at-rest per account, decide the recovery model (app-layer E2EE +
    recovery codes vs server-side KMS vs no encryption). The standing AMEN E2EE
    blocker — prayer-journal encryption **cannot get ahead of it**. *Blocks: §4.4
    `prayer-memory`, §4.3 encrypted journal.*

## D. Safety / legal posture — confirm before capture ships

11. **Recording-consent legal posture** (Sermon/Group): confirm the per-jurisdiction
    policy to enforce (two-party-consent, venue policy) before Wave 5/7 capture ships.

12. **Diarization approach** (Group): on-device vs server, and the accuracy/consent
    tradeoff. Attribution errors must be human-correctable, never silently asserted.

13. **Monetization.** Any paid voice gating must reconcile with the standing Stripe
    donation-model decision before wiring.

---

### Highest-priority drift to close regardless of the above
`BereanVoiceFeatureFlags.swift` hardcodes all voice flags to `true` (DEBUG
override), bypassing Remote Config kill switches. Until migrated into canonical
`AMENFeatureFlags`, production voice features **cannot be remotely killed.** Fix in
Wave 1 before any flag is flipped.
