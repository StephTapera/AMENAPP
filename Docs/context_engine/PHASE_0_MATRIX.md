# Context Engine Audit — Phase 0 Matrix
**Date:** 2026-05-31  
**Agent:** Discovery Agent  
**Scope:** All 21 detection features + 4 cross-cutting systems  

---

## Risk-Ranked Summary

### 🔴 CONSENT_MISSING — Critical Risks

| # | Feature | Why Critical |
|---|---------|-------------|
| 1 | **Emotional State Awareness (#12)** | `AmenFabricConsentScope.emotionalContext` is defined in `AmenAIConsentStore.swift` but `hasFabricConsent()` is **never called anywhere** in the codebase. Emotional signals are written to Firestore (`truthEmotionAnalyses`, `PersonalSpiritualGraphService`) without any consent gate being enforced at the call site. |
| 2 | **Church Arrival / Sermon Detection (#5, #6)** | `ChurchProximityEngine` reads `CLLocationManager`, `CMMotionActivityManager`, and `EKEventStore` simultaneously. No explicit user consent modal or AMEN-specific opt-in screen exists before starting monitoring. The engine calls `requestWhenInUseAuthorization()` then immediately escalates to `requestAlwaysAuthorization()` without an AMEN-layer consent dialogue explaining the church-attendance inference purpose. |
| 3 | **Faith Rhythm Intelligence (Cross-A)** | `PersonalSpiritualGraphService` infers spiritual struggles, emotional triggers, and behavioral patterns from Berean chat content, prayer requests, and testimonies. No consent gate protects this pattern-detection. Patterns are stored in `users/{uid}/spiritualGraph/` with 90-day TTL. |
| 4 | **Volunteer Burnout (#17)** | No dedicated feature exists. However `WellnessRiskLayer` / `PersonalSpiritualGraphService` may infer burnout-adjacent patterns from content without a consent gate. |
| 5 | **Relationship Follow-Up (#16)** | `PrayerFollowThroughService` and the relationship graph in `AMENAPP/AMENAPP/AMENAPP/RelationshipGraph/` infer relationship health signals from message history. `AmenFabricConsentScope.relationshipSafety` is defined but `hasFabricConsent()` is never called. |
| 6 | **Emergency Care (#21)** | `CrisisDetectionService` + `EnhancedCrisisSupportService` detect crisis language from user content. No opt-in consent gate; crisis detection runs passively. |

### 🔴 ON_DEVICE_AI — Direct API Calls

| # | Feature | Risk |
|---|---------|------|
| 1 | **Sermon Detection / Notes (#6, #19)** | `SermonIntelligenceEngine.swift:126` calls `ClaudeService.shared.sendMessageSync()`. `ClaudeService` itself routes through `bereanChatProxy` Cloud Function (confirmed line 36: `lazy var functions = Functions.functions()`), so **not** a direct Anthropic call. However: the same engine calls `WhisperVoiceService` — need to verify whether Whisper routes through CF or calls OpenAI directly. |
| 2 | **Berean Context Detection (#18)** | `BereanVisualScriptureService` performs OCR on-device via `Vision.VNRecognizeTextRequest` (line 186) — this is legitimate on-device processing, not AI inference. The context card fetch then routes through `bereanBibleQA` CF (line 153). **On-device OCR is safe**; no direct API call. |
| 3 | **Environment Classification** | `EnvironmentContextService.swift:56` calls `classifyEnvironment` CF for ambiguous cases — properly proxied. |

### 🟡 NO_FLAG — Features Without Feature Flag Protection

| # | Feature | Status |
|---|---------|--------|
| 1 | **Church Arrival (#5)** | `ChurchAssistFeatureFlags.enableArrivalPrompts = true` — hardcoded ON in source, not behind `AMENFeatureFlags` Remote Config. No kill switch. |
| 2 | **Sermon Detection/Audio Capture (#6)** | `SermonIntelligenceEngine` has no feature flag check at invocation. `AMENFeatureFlags.sermonAudioCaptureEnabled` exists but is not checked by the engine itself. |
| 3 | **Faith Rhythm Intelligence (Cross-A)** | `PersonalSpiritualGraphService` has no feature flag at its `recordPattern()` entry point. |
| 4 | **Meeting-to-Notes (#19)** | `MeetingService.swift` in `Meetings/` — no feature flag wrapping found. |
| 5 | **Relationship Follow-Up (#16)** | No feature flag found protecting `RelationshipService`. |
| 6 | **Volunteer Burnout (#17)** | Feature is entirely missing — no flag needed but no code either. |
| 7 | **Walking Prayer (#2), Gym Mode (#3), Sleep Wind-Down (#4)** | Zero code found. No flags. |
| 8 | **Small Group Detection (#8)** | No detection code. Models define `GroupType.smallGroup` but no signal-based detection. |
| 9 | **Mission Trip Mode (#9)** | No code found. |
| 10 | **Conference Mode (#10)** | Only `EnvironmentContextService` heuristic label detection exists — no Berean mode adaptation, no flag. |

### 🟢 FULLY_WIRED (all 8 layers)

- None of the 25 features scored all 8 layers.

---

## State Count Summary

| State | Count |
|-------|-------|
| Present | 3 |
| Partial | 9 |
| Stub | 2 |
| Broken | 1 |
| Missing | 10 |

---

## Feature Matrix

> Layers: `signal` · `consent` · `proxy` · `2I` · `action` · `UI` · `flag` · `tests`  
> ✅ = present · ⚠️ = partial/weak · ❌ = missing

| # | Feature | State | signal | consent | proxy | 2I | action | UI | flag | tests | Top Risk |
|---|---------|-------|--------|---------|-------|-----|--------|-----|------|-------|----------|
| 1 | Driving / CarPlay Mode | **Partial** | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | No AMEN-layer consent modal for location during drive; STT consent via `SFSpeechRecognizer.requestAuthorization()` only at voice use |
| 2 | Walking Prayer Mode | **Missing** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 NO_FLAG, zero code |
| 3 | Gym Mode | **Missing** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 NO_FLAG, zero code |
| 4 | Sleep Wind-Down | **Missing** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 NO_FLAG, zero code (lateNightPauseEnabled flag exists but no detection engine) |
| 5 | Church Arrival | **Partial** | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | 🔴 CONSENT_MISSING: no AMEN-layer consent sheet before geofence+motion+calendar fusion; 🟡 NO_FLAG: hardcoded ON in ChurchAssistFeatureFlags |
| 6 | Sermon Detection | **Partial** | ✅ | ❌ | ✅ | ⚠️ | ✅ | ✅ | ⚠️ | ⚠️ | 🔴 CONSENT_MISSING: microphone+speech inferencing, no AMEN-layer opt-in; 🟡 NO_FLAG at engine entry |
| 7 | Campus Switching | **Stub** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 STUB_ONLY: `EnvironmentType.campus` label exists but no campus-aware Berean mode or geofence set |
| 8 | Small Group Detection | **Stub** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 STUB_ONLY: `GroupType.smallGroup` data model exists; no detection signal |
| 9 | Mission Trip Mode | **Missing** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 NO_FLAG, zero code |
| 10 | Conference Mode | **Partial** | ⚠️ | ❌ | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ | 🔴 CONSENT_MISSING: `EnvironmentContextService` classifies location (conference/campus/airport) with no consent gate; 🟡 NO_FLAG |
| 11 | Berean Study Continuation | **Partial** | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | No explicit consent gate before `AmenJourneyContinuityEngine` reads study history cross-session; `bereanPersistentMemoryEnabled` flag exists but consent UI is presence-only |
| 12 | Emotional State Awareness | **Partial** | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | 🔴 CONSENT_MISSING: `AmenFabricConsentScope.emotionalContext` defined but `hasFabricConsent()` is never called in the app; emotional data written to Firestore without enforcement |
| 13 | Travel Mode | **Partial** | ✅ | ❌ | ✅ | ⚠️ | ⚠️ | ⚠️ | ❌ | ❌ | 🔴 CONSENT_MISSING: `LocationContextService` + `EnvironmentContextService` detects international/new-city without explicit consent prompt; 🟡 NO_FLAG |
| 14 | New City Detection | **Partial** | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 🔴 CONSENT_MISSING: `LocationContextService` writes city/state to UserDefaults and infers `isNewArea` without explicit AMEN-layer opt-in; 🟡 NO_FLAG |
| 15 | Family Event Awareness | **Missing** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 NO_FLAG, zero code |
| 16 | Relationship Follow-Up | **Partial** | ⚠️ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | 🔴 CONSENT_MISSING: `RelationshipService` + `AmenJourneyContinuityEngine` infers relationship follow-up needs from prayer/content data; `AmenFabricConsentScope.relationshipSafety` never enforced |
| 17 | Volunteer Burnout | **Missing** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 NO_FLAG, zero dedicated code (adjacent signals in `PersonalSpiritualGraphService` under `SpiritualRhythm.serving` but no burnout-specific detection) |
| 18 | Berean Context Detection | **Present** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Strongest feature: on-device Vision OCR + `bereanBibleQA` CF + `bereanVisualScriptureEnabled` flag + `BereanVisualScriptureView` + tests in `BereanMultimodalSafetyTests`. PDFs not yet handled (PDF scanner not wired). |
| 19 | Meeting-to-Notes | **Partial** | ✅ | ❌ | ✅ | ⚠️ | ✅ | ✅ | ❌ | ❌ | Meeting models + Gatherings intelligence CFs exist; no `SermonIntelligenceEngine` consent gate for live audio capture; 🟡 NO_FLAG at engine entry |
| 20 | Quiet Moment | **Partial** | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ | ✅ | Signal is `LivingEntryTriggerType.quietMoment` using `lowMotion + appOpenedAfterInactivity + eveningHours` (no real motion sensor, uses app-state proxy); flag coverage inconsistent across surfaces |
| 21 | Emergency Care | **Partial** | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | 🔴 CONSENT_MISSING: `CrisisDetectionService` and `EnhancedCrisisSupportService` passively detect crisis language from all message/content streams; no opt-in consent before activation |

---

## Cross-Cutting Systems Matrix

| # | System | State | signal | consent | proxy | 2I | action | UI | flag | tests | Top Risk |
|---|--------|-------|--------|---------|-------|-----|--------|-----|------|-------|----------|
| A | Faith Rhythm Intelligence | **Partial** | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | 🔴 CONSENT_MISSING: `PersonalSpiritualGraphService` infers spiritual patterns from content passively; `AmenFabricConsentScope.wellnessSignals` never enforced; 🟡 NO_FLAG at `recordPattern()` |
| B | Spiritual Milestone Detection | **Partial** | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `AmenJourneyContinuityEngine.FormationMilestone` and `SpiritualRhythmOS` track streaks and milestones; milestone data flows through Firestore without explicit consent gate for behavioral inference |
| C | Safe Attention System | **Partial** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Well-covered: `antiDoomscrollEnabled`, `DoomscrollGuardTests`, `mediaDoomScrollGuardEnabled`, `lateNightPauseEnabled`, `HealthyModeService`; gap is no on-device motion signal for actual use-intensity |
| D | Context-Aware Berean | **Partial** | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | CarPlay: Present (flag-gated). Lock Screen/Dynamic Island: `AmenLiveActivityAttributes` + `PrayerSessionAttributes` + `BereanStudyAttributes` exist. Watch: zero code found. Siri/AppIntents: `AmenAppIntents.swift` + `AmenIntentRouter.swift` present. Spotlight: `SpotlightIndexingService` + `AmenSpotlightService` present. Share Sheet: `BereanShareSheet.swift` present. Camera/Photos → OCR: `BereanVisualScriptureService` + Vision framework present. PDFs: exporter exists (`ChurchNotesPDFExporter`) but inbound PDF OCR not found. Safari Extension: not found. |
