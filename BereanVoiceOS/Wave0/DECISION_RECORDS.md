# Wave 0 — Decision Records

Live-confirmed research (recon agent reached the web). Where a number could not be
officially verified it is marked **UNVERIFIED** and routed to a human (see
`OPEN_HUMAN_DECISIONS.md`).

---

## DR-001 — Pipeline transport is the default; realtime is a later, flag-gated optimization

- **Problem.** Voice needs a transport. Realtime speech-to-speech is seductive (low latency, natural barge-in) but is the hardest to moderate and the most expensive.
- **Root cause.** A second, speech-native reasoning path would bypass the audited Berean text core and bill audio in *and* out per token, growing every turn.
- **Risk.** Unmoderated realtime path = safety regression; uncapped airtime = cost blowout; both violate the anti-addiction/free-at-every-tier posture.
- **Proposed solution.** Ship **Path A (pipeline)** first: Apple on-device STT → existing Berean streaming core → on-device TTS, with every turn streamed to `bereanVoiceIngestTurn` (GUARDIAN). Gate **Path B (realtime)** behind `berean_voice_transport_realtime` (default OFF) for a later wave.
- **Technical architecture.** Reuse `BereanRealtimeWebSocketTransport` (WS) for the realtime channel; reuse `createRealtimeSession` mint + `persistRealtimeTranscriptChunk` + `BereanLiveTranscriptService`. Pipeline reuses the **existing text reasoning path verbatim** — no new brain.
- **UI impact.** Voice state surfaces through the already-frozen `BereanActivityAttributes`/`BereanPhase` Live Activity and `VoiceOrb`/`BereanOrbState`. No new ambient layer.
- **Backend impact.** One new orchestration callable (`bereanVoiceIngestTurn`, us-east1); mint/persist/moderate/verify all already exist.
- **Security impact.** Pipeline inherits all constitutional + GUARDIAN guardrails because it routes through the audited core. Moderation is path-independent — realtime gets **no** pass.
- **Scaling impact.** Pipeline caps per-request cost to a single text-LLM turn; realtime scales with total airtime.
- **Cost impact.** Hybrid pipeline with Apple on-device STT + system-voice TTS = **$0 audio**, only the text LLM call bills. Strong fit for free-at-every-tier.
- **Priority.** P0 (Wave 1). **Effort.** Medium — wiring/protocol extraction over existing parts. **Dependencies.** Apple Speech (on-device STT + `AVSpeechSynthesizer`), existing Berean streaming core.

---

## DR-002 — Freeze the transport *abstraction*; the realtime provider is a human decision

- **Problem.** §3.1 Path B assumes "client → provider via WebRTC with ephemeral tokens." Reality and the provider landscape don't match that single shape.
- **Root cause.** AI voice realtime in this repo is **WebSocket** (`URLSessionWebSocketTask`, Bearer token, max-4-retry backoff). WebRTC/LiveKit exists but is **group-rooms-only** today.
- **Risk.** Hardcoding a provider/transport now locks cost and latency before product has chosen; copying `voicePrayer.js`'s us-central1 region would hit the 999/1000 quota wall.
- **Proposed solution.** Freeze a **transport protocol** (mint → connect → stream turns → degrade), not a provider. Decide provider in `OPEN_HUMAN_DECISIONS.md` #1–#3.
- **Technical architecture / research (live-confirmed):**

  | | OpenAI gpt-realtime | Google Gemini Live (`gemini-3.1-flash-live-preview`) | Apple on-device (pipeline) |
  |---|---|---|---|
  | Transport | WebRTC + WebSocket + SIP | **WebSocket only** (WebRTC via partner bridge) | n/a (local) |
  | Ephemeral tokens | Yes, first-class (server mints `client_secret`) | Yes (v1alpha, client-to-server WS) | n/a |
  | Audio in / out | **$32 / $64** per 1M tok | **$3 / $12** per 1M tok | **$0** (system voices) |
  | Session limits | — | 15 min audio-only (use context resumption) | unlimited on-device |
  | Notes | premium audio, sub-300ms | ~10–30× cheaper audio; needs WS proxy/bridge | free, offline, default-safe |

- **UI impact.** None at freeze (abstraction only).
- **Backend impact.** If **LiveKit** is chosen as the WebRTC bridge, `generateLiveKitToken` (2h JWT mint) + `AmenLivekitLiveRoomProvider` are **already in the repo** — the WebRTC client transport + ephemeral-mint are effectively solved, de-risking a WS-only provider like Gemini.
- **Security impact.** Server mints short-lived tokens; long-lived provider key never leaves the server (already the pattern in `createRealtimeSession`). Set a safety-identifier on the mint call.
- **Scaling / Cost impact.** Provider choice swings audio cost ~10–30×; one cited comparison: ~$165/mo (Gemini) vs ~$8,400/mo (OpenAI) at 100k min/mo. **Pricing for `gpt-realtime-mini` was NOT in official results — UNVERIFIED.**
- **Priority.** P1 (blocks Path B wave, not Wave 1). **Effort.** Low to freeze the abstraction. **Dependencies.** Human provider + LiveKit-reuse decisions; official pricing confirmation.

### Apple on-device speech (for the pipeline leg)
- **STT:** `SFSpeechRecognizer` (`requiresOnDeviceRecognition`, iOS 13+, retains Custom Vocabulary) **or** `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26+, faster, long-form; not backward-compatible — keep `SFSpeechRecognizer` for iOS ≤18).
- **TTS:** `AVSpeechSynthesizer` system voices — fully offline, no entitlement, $0. **Personal Voice** is on-device but **Apple-restricts it to AAC/accessibility** — using it for a general voice assistant is an App-Review risk (legal call needed).
