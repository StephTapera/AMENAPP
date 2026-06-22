# Wave 0 — Freeze Proposal (reconciled against real code)

> **PENDING HUMAN FREEZE.** Names below are reconciled with the actual codebase but
> are not authoritative until a human ratifies them. Recommendation key:
> **REUSE** (use as-is) · **EXTEND** (additive change to existing symbol) ·
> **RENAME-TO-EXISTING** (proposal name → real name) · **BUILD-NEW** (genuinely missing).

## 1. Freeze table

### 1.1 Swift session contract (§4.1)

| Proposed | Rec | Final name to freeze | Existing file | Note |
|---|---|---|---|---|
| `protocol BereanVoiceSession` (state, statePublisher, activeMode, start/interrupt/sendText/switchMode/pause/resume/end) | **EXTEND** | `BereanVoiceSession` protocol, **extracted from** the two existing concrete classes | `BereanVoiceViewModel.swift` (app-layer) + `AIIntelligence/BereanVoiceSessionManager.swift` (realtime) | No protocol exists. Two `@MainActor` classes already implement the lifecycle under **different method names** (`startSession(mode:)`, `pauseSession()`, `resumeSession()`, `handleBargein()`; `sendText`/`switchMode` absent). Extract a protocol that **unifies the dual session paths**. |
| `enum BereanVoiceState { idle, connecting, listening, thinking, speaking(turnId), interrupted, degraded(reason), ended }` | **EXTEND** | `BereanVoiceState` | `BereanVoiceModels.swift` | Exists: `idle, listening, thinking, speaking, paused, interrupted, error`. Additive migration: add `connecting`, `ended`; associate `turnId` with `speaking`; migrate `error` → `degraded(VoiceDegradeReason)`; **keep** `paused`. |
| `enum VoiceDegradeReason { network, providerUnavailable, costCeiling, safetyHold, deviceUnsupported }` | **BUILD-NEW** | `VoiceDegradeReason` | co-locate in `BereanVoiceModels.swift` | No structured reason today (`error` is a `String`). Existing `BereanVoiceError` cases (`networkError, sessionExpired, safetyInterrupt`) **map into** this, don't duplicate. |
| `enum BereanVoiceMode { ask, study, prayer, sermon, walk, group, creator, decision }` | **EXTEND** ⚠️ | `BereanVoiceMode` (merged) — **RESOLVE vs `BereanRealtimeSessionType`** | `BereanVoiceModels.swift` | **BREAKING CONFLICT.** Same name already exists with different cases (`conversation, prayer, churchNotes, discovery, wellness`) and overlaps `BereanRealtimeSessionType` (`sermonTranslation, livePrayerRoom, voiceAssistant, smartNotes, multilingualConversation`) which already maps to constitutional modes. **Human must ratify the merge** — see §2. |
| `struct VoiceSessionContext { uid, orgId?, entryPoint, consent }` | **BUILD-NEW** 🔒 | `VoiceSessionContext` | new, alongside `BereanRealtimeModels.swift` | Missing. Blocked on `ConsentManifest` + PRIV-005. |
| `ConsentManifest` | **BUILD-NEW** 🔒 | `ConsentManifest` — **ROUTE TO PRIVACY OWNER** | none in voice layer | No such type. Age-gating exists (`AgeAssuranceService.minorUserBlocked`) but no consent manifest. Must reconcile with the frozen Privacy Core Contract + PRIV-005 before freeze. |

### 1.2 Safety verdict & callables (§4.2)

| Proposed | Rec | Final name to freeze | Existing file | Note |
|---|---|---|---|---|
| `SafetyVerdict` (ingest return type) | **REUSE** ⚠️ | `AmenModerationResult` | `AIIntelligence/AmenSafetyModerationProvider.swift` | **Retire `SafetyVerdict`.** `AmenModerationResult` already has `allowed, severity, categories, userMessage, crisisEscalated, crisisResources, decisionId`. |
| `SafetyVerdict.severity` | **REUSE** | `AmenModerationSeverity` (`safe, warn, review, block, uncertain`) | same | `uncertain` = fail-closed sentinel for guard surfaces. Voice passes `mode:.guard`. |
| `bereanVoiceMintSession` callable | **REUSE** | `createRealtimeSession` (CF) + `BereanRealtimeSessionManager.createSession()` | `functions: createRealtimeSession`; `BereanRealtimeSessionManager.swift` | Full mint path exists: returns `BereanRealtimeClientSecret` (sessionId, token, expiresAt, providerSessionId, model, endpoint); age-gate Gate 1; refresh −15s before expiry. **Do not** add a new mint callable. (If LiveKit chosen → `generateLiveKitToken` already mints 2h JWTs.) |
| `bereanVoiceIngestTurn` callable → SafetyVerdict | **BUILD-NEW** | `bereanVoiceIngestTurn` | new TS in `Backend/functions/src/berean/` (creator codebase), **us-east1** | New orchestration that **composes** existing `moderateRealtimeTranscript` + `persistRealtimeTranscriptChunk` + `verifyScriptureText`; iOS calls `AmenSafetyModerationCoordinator.moderate(text:context:.message,mode:.guard)`. Returns `AmenModerationResult` JSON. **Must** register in `Backend/functions/src/index.ts`. |
| `bereanVoiceOrchestrate` (Formation engine) | **BUILD-NEW** | Formation orchestrate callable | new (creator codebase) | One of the 3 genuinely-new pieces. Routes generative turns through the **existing** `BereanConstitutionalReviewGate.shared` + `BereanConstitutionalPipeline`. Gate against `.build` mode for realtime. |
| Realtime transport (proposal: WebRTC via provider) | **REUSE** ⚠️ | `BereanRealtimeWebSocketTransport` (AI voice) + `AmenLivekitLiveRoomProvider` (group media, if chosen) | `BereanRealtimeWebSocketTransport.swift` + `ConnectSpaces/Live/AmenLivekitLiveRoomProvider.swift` | **CONTRACT-DRIFT:** AI voice is **WebSocket**, not WebRTC. Freeze the transport **abstraction**, not a provider (DR-002). |

### 1.3 Decision artifact (§4.6)

| Proposed | Rec | Final name | Compose from | Note |
|---|---|---|---|---|
| `DecisionRecord` | **BUILD-NEW** | `DecisionRecord` (aggregator) | `EpistemicDeclaration` + `BereanPipelineResponse` + `AmenModerationResult` + `bereanPipelineTraces` | All constituent fields are real. Aggregate them; **invent no new fields**. Any cost figure inside it is **UNVERIFIED** until pricing is confirmed (DR-002). |

### 1.4 GlassKit / Berean Island (§2.2)

| Proposed | Rec | Final name | Existing file | Note |
|---|---|---|---|---|
| Live Activity voice phases | **REUSE** | `BereanActivityAttributes` + `BereanPhase` (extend `ContentState` if needed) | `BereanActivityAttributes.swift` + `AMENWidgetExtension/BereanLiveActivityWidget.swift` | Frozen ActivityKit contract already wired. **Do not** create a parallel `VoiceActivityAttributes`. `BereanPhase.error` lacks a message field — add one if voice needs it. |
| Voice orb / glass tokens | **REUSE** | `BereanSurfaceContracts.BereanOrbState` + `VoiceOrb` + `AmenTheme.Colors` | `DesignSystem/BereanGlass/VoiceOrb.swift` + `BereanSurfaceContracts.swift` + `AmenTheme.swift` | `BereanOrbState` (idle/listening/discerning/praying/summarizing) frozen (BRS-W0-GATE), maps 1:1. Route color through `AmenTheme.Colors` + BAS tokens. No new orb/token work. |

Collections (§4.3), flags (§4.5), Pinecone namespaces (§4.4): see
`WAVE0_FIRESTORE_RULES_SKELETON.md` and `WAVE0_FLAGS_AND_PINECONE.md`.

---

## 2. The one blocking enum decision — `BereanVoiceMode` merge

The proposal's 8 modes are **experiences**; the core's 5 constitutional modes
(`ask/discern/build/guard/reflect`) are the **reasoning primitives**, and they are
**real executable symbols** (`BereanConstitutionalMode`), already mapped from
session types via `defaultMode(for sessionType:)`. The freeze must (a) ratify the
voice-mode set and (b) bind each voice mode to a primitive. Proposed reconciliation
for human sign-off:

| Voice mode (proposed) | Existing case it absorbs | Composes primitive(s) | Realtime session type |
|---|---|---|---|
| `ask` | `conversation`, `discovery` | Ask | `voiceAssistant` |
| `study` | `wellness` (re-scope) | Ask + Discern | `voiceAssistant` |
| `prayer` | `prayer` (keep) | Reflect + Guard | `livePrayerRoom` |
| `sermon` | `churchNotes` | Build + Ask | `sermonTranslation` / `smartNotes` |
| `walk` | — (new) | Ask / Reflect | `voiceAssistant` |
| `group` | — (new) | Build + Guard | `livePrayerRoom` (multi) |
| `creator` | — (new) | Build | `smartNotes` |
| `decision` | — (new) | Discern (formal `DecisionRecord`) | `voiceAssistant` |

⚠️ This renames/removes existing cases (`conversation, churchNotes, discovery,
wellness`) — every call site of the current `BereanVoiceMode` and
`BereanRealtimeSessionType` must be migrated. **Do not redefine silently.**

---

## 3. Genuinely-new work (Wave 1+, after freeze)

The proposal's "remove sprawl" mandate holds: only these are new.

1. **`bereanVoiceIngestTurn`** — TS orchestration (us-east1) composing existing moderation/persist/verify callables; returns `AmenModerationResult`.
2. **Formation engine** — orchestrate callable + iOS service, routed through `BereanConstitutionalReviewGate.shared`; flag `berean_voice_formation_engine`.
3. **Decision-formatter** — `DecisionRecord` aggregator (no invented fields).
4. **Creator-pipeline adapter** — bridge voice output into the creator pipeline.
5. `VoiceSessionContext` + `ConsentManifest` (🔒 PRIV-005 first).
6. `VoiceDegradeReason` + `BereanVoiceState` migration (add `connecting`/`ended`/`turnId`, `error`→`degraded`).
7. `BereanVoiceSession` protocol extraction (unify the two session classes).
8. Pinecone namespaces `formation-memory`, `prayer-memory` (🔒 encryption-blocked), `study-project`, `org-memory` — single-namespace + metadata-filter convention; extend `RAG_NAMESPACES`; update `accountDeletion` purge.
9. Firestore rule blocks (see rules skeleton).
10. Flag migrations into canonical `AMENFeatureFlags` + Remote Config.
11. `docs/FUNCTION_INVENTORY.md` Interim Region Table entry for new us-east1 callables.
12. Optional `bereanVoiceKillSwitch` for emergency rollback.

---

## 4. Reuse map (handler → existing symbol)

| Handler / role | Existing symbol | File |
|---|---|---|
| mintSession | `createRealtimeSession` CF + `BereanRealtimeSessionManager.createSession()` | `BereanRealtimeSessionManager.swift` |
| endSession | `endRealtimeSession` CF + `.endCurrentSession()` | same |
| ingestTurn moderation (iOS) | `AmenSafetyModerationCoordinator.moderate(text:context:mode:)` | `AmenSafetyModerationProvider.swift` |
| transcript moderation CF | `moderateRealtimeTranscript` + `BereanRealtimeModerationService.validateTranscript()` | `BereanRealtimeServices.swift` |
| transcript persistence | `persistRealtimeTranscriptChunk` + `.persistTranscriptChunk()` | `BereanRealtimeWebSocketTransport.swift` |
| scripture verification (G-1) | `verifyScriptureText` + `ScriptureReferenceValidator.verifyWithAPIPipeline()` | `ScriptureReferenceValidator.swift` |
| constitutional review (ALL generative turns) | `BereanConstitutionalReviewGate.shared` (actor) + `BereanConstitutionalPipeline` | `BereanConstitutionalIntelligence.swift` + `BereanConstitutionalPipeline.swift` |
| voice→mode mapping | `BereanConstitutionalMode.defaultMode(for sessionType:)` | `BereanConstitutionalIntelligence.swift` |
| crisis pre-screen | `CrisisDetectionService.hasLocalCrisisSignal(in:)` + `WellnessRiskService.evaluateAndIntervene()` | `CrisisDetectionService.swift` + `WellnessRiskLayer.swift` |
| CSAM/NCMEC prep (human-gated OPEN-4) | `AmenChildSafetyService.prepareCSAMEscalation()` → `/moderationQueue` | `CommunityOS/ChildSafety/AmenChildSafetyService.swift` |
| safety verdict type | `AmenModerationResult` + `AmenModerationSeverity` | `AmenSafetyModerationProvider.swift` |
| realtime transport (AI voice) | `BereanRealtimeWebSocketTransport` | `BereanRealtimeWebSocketTransport.swift` |
| WebRTC bridge / mint (if LiveKit chosen) | `AmenLivekitLiveRoomProvider` + `generateLiveKitToken` | `ConnectSpaces/Live/AmenLivekitLiveRoomProvider.swift` + `Backend/functions/src/generateLiveKitToken.ts` |
| caption/transcript streaming listener | `BereanLiveTranscriptService` + `BereanCaptionChunk` | `BereanRealtimeServices.swift` + `BereanRealtimeModels.swift` |
| Pinecone client | `pineconeUpsert/Query/Delete` + `openaiEmbed` | `functions/mlClients.js` |
| namespace routing | `RAG_NAMESPACES` map | `functions/amenAIFeatures.js` |
| iOS memory CRUD | `BereanMemoryService` + `bereanMemory` CF | `BereanMemoryService.swift` + `Backend/functions/src/berean/bereanMemory.ts` |
| voice UI orb + state | `VoiceOrb` + `BereanSurfaceContracts.BereanOrbState` | `DesignSystem/BereanGlass/VoiceOrb.swift` |
| Live Activity / Dynamic Island | `BereanActivityAttributes` + `BereanPhase` + `BereanLiveActivityWidget` | `BereanActivityAttributes.swift` + `AMENWidgetExtension/` |
| master flag gate | `AMENFeatureFlags.bereanVoiceEnabled` (`berean_voice_enabled`) | `AMENFeatureFlags.swift` |

---

## 5. Reconciled contract sketches (frozen-pending-human)

These reflect **reality** (existing names, `@MainActor` + `@Published` + async
methods — the house pattern — not the proposal's `Combine AnyPublisher`). They are
the freeze targets, annotated with deltas.

```swift
// EXTEND existing BereanVoiceState (BereanVoiceModels.swift)
// Adds: connecting, ended; turnId on speaking; error -> degraded(reason). Keeps paused.
public enum BereanVoiceState: Equatable {
    case idle
    case connecting                       // NEW
    case listening
    case thinking
    case speaking(turnId: String)         // CHANGED: was bare `speaking`
    case paused                           // KEEP (proposal omitted; pause/resume are real)
    case interrupted
    case degraded(reason: VoiceDegradeReason)  // CHANGED: replaces `error(String)`
    case ended                            // NEW
}

// BUILD-NEW (co-located). BereanVoiceError cases map INTO this; do not duplicate.
public enum VoiceDegradeReason: String, Codable {
    case network, providerUnavailable, costCeiling, safetyHold, deviceUnsupported
}

// EXTEND/MERGE — ⚠️ BREAKING. Requires §2 human ratification before adopting.
// Existing cases: conversation, prayer, churchNotes, discovery, wellness.
public enum BereanVoiceMode: String, CaseIterable, Codable {
    case ask, study, prayer, sermon, walk, group, creator, decision
}

// EXTRACT protocol over BereanVoiceViewModel + BereanVoiceSessionManager.
// NOTE house style: state is @Published, methods async. Decide @Published vs
// AsyncStream for statePublisher — do NOT introduce a third pattern.
public protocol BereanVoiceSession: AnyObject {
    var state: BereanVoiceState { get }
    var activeMode: BereanVoiceMode { get }
    func start(mode: BereanVoiceMode, context: VoiceSessionContext) async throws
    func interrupt() async              // existing impl: handleBargein()
    func sendText(_ text: String) async throws   // NEW capability
    func switchMode(_ mode: BereanVoiceMode) async throws  // NEW capability
    func pause() async                 // existing impl: pauseSession()
    func resume() async                // existing impl: resumeSession()
    func end() async                   // existing impl: stopSession()/endSession()
}
```

```typescript
// REUSE — mint stays createRealtimeSession (do NOT add bereanVoiceMintSession).
// BUILD-NEW — bereanVoiceIngestTurn composes existing callables, returns AmenModerationResult JSON.
export const bereanVoiceIngestTurn = onCall({ region: "us-east1" }, async (req) => {
  // { sessionId, turn: { role, text, ts, clientTurnId } }
  // -> moderateRealtimeTranscript (mode:"guard") + verifyScriptureText + persistRealtimeTranscriptChunk
  // -> { accepted, safetyVerdict: AmenModerationResult, action: "continue"|"degrade"|"handoff" }
  // fail-closed: severity == uncertain/block -> action != "continue"; CSAM -> prepareCSAMEscalation (never auto-file)
});
```

`DecisionRecord` = aggregator over `EpistemicDeclaration` (verifiedFacts /
assumptions / unknowns) + `BereanPipelineResponse` (traceId / confidence /
trustScore / reviewVerdict / isVerified) + `AmenModerationResult` (decisionId /
severity / crisisEscalated). No new fields; cost figures UNVERIFIED.
