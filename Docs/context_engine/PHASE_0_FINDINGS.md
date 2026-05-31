# Context Engine Audit — Phase 0 Findings
**Date:** 2026-05-31  
**Agent:** Discovery Agent  
**Legend:** P=Phase to fix (2=safety-critical, 3=location, 4=motion, 5=time/schedule, 6=content/scripture, 7=graph/care, 8=wellbeing)

---

## Feature 1: Driving / CarPlay Mode
**State: Partial**

**What exists:** Full CarPlay vertical slice in `AMENAPP/CarPlay/` (12 files). `AmenCarPlaySceneDelegate.swift` creates `BereanCarPlayCoordinator` on connect. `BereanDriveSessionService.swift` (lines 94, 129, 158, 197, 241) checks `AMENFeatureFlags.shared.bereanDriveEnabled` before any backend call. `BereanDriveSetupView.swift` provides a companion settings screen. `BereanDriveVoiceService.swift` calls `SFSpeechRecognizer.requestAuthorization()` before listening. `BereanCarPlayCoordinator.swift:384` calls `locationManager?.requestWhenInUseAuthorization()`. Tests exist: `AMENAPPTests/BereanCarPlayTests.swift`.

**What's missing / broken:** No AMEN-authored consent narrative ("Berean Drive uses your location to find nearby churches") is shown before the coordinator triggers location permission. The iOS system dialog is the only gate. `carPlayBereanEnabled` and `bereanDriveEnabled` flags both default `true` in `AMENFeatureFlags.swift:42–43` — the comment on lines 1053–1054 says "All CarPlay flags default OFF" but the in-code value is `true`. This is a direct contradiction.

**Why it's this risk level:** Location during drive is low-sensitivity (when-in-use only), but the flag default contradiction means it could ship enabled before Apple entitlement is granted.

**Recommended Phase:** Phase 3 (location signals), fix flag defaults to `false` pending entitlement approval.

---

## Feature 2: Walking Prayer Mode
**State: Missing**

**What exists:** Nothing. No files named `WalkingPrayer*`, `PrayerWalk*`, or any `CMMotionActivity` query scoped to walking-during-prayer. No feature flag. No test.

**What's missing:** All 8 layers: signal detector, consent, proxy, intelligence routing, Berean adaptation action, UI surface, flag, tests.

**Why it's this risk level:** No code means no risk today, but also no value delivered. When built, will require `CMMotionActivityManager` (motion consent) and must integrate with `ChurchProximityEngine` to avoid duplicate motion subscriptions.

**Recommended Phase:** Phase 4 (motion detection).

---

## Feature 3: Gym Mode
**State: Missing**

**What exists:** Nothing. No files, no flags, no CMMotionActivity queries that detect workout activity.

**What's missing:** All 8 layers. When built, will need `CMMotionActivity.cycling` / `.running` signals, a "Do Not Disturb spiritual content" mode, and integration with `NotificationPolicyEngine`.

**Recommended Phase:** Phase 4 (motion detection).

---

## Feature 4: Sleep Wind-Down
**State: Missing**

**What exists:** `AMENFeatureFlags.lateNightPauseEnabled = true` (line 800 of `AMENFeatureFlags.swift`). `WellnessMoodEngine.swift:166` has a memory line "Wind-down near your usual sleep window." These are cosmetic references. No detection engine, no signal integration with `UserNotifications` quiet hours, no sleep-window detector.

**What's missing:** Signal layer (time-of-day + motion inactivity), consent, Berean "wind-down prayer" mode adaptation, UI, dedicated flag at engine level.

**Why it's this risk level:** The `lateNightPauseEnabled` flag covers media sessions only, not a proactive sleep wind-down experience. Gap between flag and feature is misleading.

**Recommended Phase:** Phase 5 (time/schedule detection).

---

## Feature 5: Church Arrival
**State: Partial**

**What exists:** `ChurchProximityEngine.swift` (508 lines) — the most complete detection feature in the codebase. Fuses 6 signals: `CLCircularRegion` geofence (max 30 pts), time window (25 pts), `EKEventStore` calendar (15 pts), `CMMotionActivityManager` (15 pts), prior attendance history (10 pts), route completion (5 pts). Threshold 85 = auto-enable, 60 = suggest. `QuietModePreferenceService.swift` persists auto/ask/off preference to Firestore. `QuietModeOnboardingView.swift` exists. `ChurchAssistFeatureFlags.swift` has `enableArrivalPrompts = true`. `AMENFeatureFlags` has `churchArrivalDetection`-adjacent flags. Tests: `LivingEntryContextEngineTests.swift`, `FindChurchLivingEntryBridgeTests.swift`.

**What's missing / broken:**
1. **CONSENT_MISSING:** `ChurchProximityEngine.startMonitoring()` calls `setupLocationManager()` which immediately requests `requestAlwaysAuthorization()` without an AMEN-authored purpose explanation. No `AmenAIConsentStore` or `AmenFabricConsentScope` check.
2. **NO_FLAG:** `ChurchAssistFeatureFlags` is a static struct with hardcoded `true` defaults, not wired to `AMENFeatureFlags` Remote Config. There is no kill switch for the arrival detection engine itself.
3. `QuietModePreferenceService` defaults to `.ask` which is reasonable, but the preference isn't checked before `startMonitoring()` is called — monitoring starts regardless of `.off` preference.

**Why it's critical:** Geofence + calendar + motion fusion creates a detailed location-history pattern. Apple's App Tracking Transparency and privacy manifests require explicit disclosure of this pattern.

**Recommended Phase:** Phase 2 (safety-critical consent gate) + Phase 3 (location).

---

## Feature 6: Sermon Detection
**State: Partial**

**What exists:** `SermonIntelligenceEngine.swift` — full pipeline: STT via `WhisperVoiceService` → topic segmentation → AI structuring via `ClaudeService` (proxy-routed) → Church Notes export → nudge scheduling. `ChurchNotesSermonCaptureService.swift` and `ChurchNotesAudioEngine.swift` handle live audio. `AMENFeatureFlags.sermonAudioCaptureEnabled = true`. `ChurchNotesMediaIntelligenceTests.swift` covers some audio paths.

**What's missing / broken:**
1. **CONSENT_MISSING:** `SermonIntelligenceEngine.processAudio()` does not check `AmenAIConsentStore` or request microphone permission before calling `transcribeAudio()`. The `SFSpeechRecognizer`/`AVAudioSession` pipeline in `WhisperVoiceService` handles system permission only at session time.
2. **NO_FLAG at engine entry:** `SermonIntelligenceEngine` never checks `AMENFeatureFlags.sermonAudioCaptureEnabled` or `AMENFeatureFlags.churchNotesIntelligenceEnabled` at `processAudio()`. The flag exists but the engine ignores it.
3. **WhisperVoiceService proxy unclear:** `SermonIntelligenceEngine.swift:99` calls `WhisperVoiceService` — the `WhisperVoiceService.swift` uses `AVAudioEngine` locally (line confirmed), unclear if it calls OpenAI Whisper API directly or a Firebase CF. Needs audit.

**Why it's critical:** Microphone capture + AI transcription of religious speech without explicit consent is a significant privacy risk under GDPR/CCPA.

**Recommended Phase:** Phase 2 (consent gate), Phase 6 (content/scripture detection).

---

## Feature 7: Campus Switching
**State: Stub**

**What exists:** `EnvironmentType.campus` in `AmenCompanion/AmenCompanionModels.swift` (line 32). `EnvironmentContextService` can classify a location as `.campus` via place-name heuristics (lines 40–41). No multi-campus church data model, no geofence sets for multiple campuses, no Berean adaptation for "switching campus context."

**What's missing:** Signal (multi-campus geofence), consent, intelligence routing, Berean action for campus-switch context, dedicated UI, flag, tests.

**Recommended Phase:** Phase 3 (location signals), builds on Church Arrival engine.

---

## Feature 8: Small Group Detection
**State: Stub**

**What exists:** `AmenGroup.GroupType.smallGroup` in `AMENAPP/AMENAPP/AMENAPP/RelationshipGraph/RelationshipModels.swift` (line 43). Data model describes small groups but no signal-based detection of when a user is attending/hosting one. No time/location/calendar detection.

**What's missing:** Signal (calendar + geofence), consent, action (e.g., Berean "small group mode"), UI, flag, tests.

**Recommended Phase:** Phase 5 (time/schedule), reusing calendar correlation from `ChurchProximityEngine`.

---

## Feature 9: Mission Trip Mode
**State: Missing**

**What exists:** Nothing. No files, no models, no flags. `EnvironmentType.international` in `AmenCompanionModels.swift` provides a proximity, but no mission-trip-specific mode exists.

**What's missing:** All 8 layers. When built: multi-week international trip detection via location history, Berean adaptation for cross-cultural scripture context, translation integration, offline-resilient prayer/journaling prompts.

**Recommended Phase:** Phase 3 (location) + Phase 7 (care/community).

---

## Feature 10: Conference Mode
**State: Partial**

**What exists:** `EnvironmentContextService.swift` — heuristic detection via place name (lines 40–41): `lower.contains("convention") || lower.contains("conference") || lower.contains("expo")`. AI fallback via `classifyEnvironment` CF (line 56). `EnvironmentType.conference.surfaceAdaptation` enables `showNearbyEvents` and suppresses local recs. `AmenCompanionModels.swift` defines surface adaptation response.

**What's missing / broken:**
1. **CONSENT_MISSING:** `EnvironmentContextService.classifyEnvironment()` is called from `AmenCompanionViewModel` without a consent gate. Location is required.
2. **NO_FLAG:** No feature flag wraps `EnvironmentContextService`. No kill switch.
3. No Berean mode adaptation for "conference context" (e.g., networking prayer, session-note capture).
4. No UI surface specific to conference mode.
5. No tests for conference detection path.

**Recommended Phase:** Phase 3 (location consent), Phase 5 (schedule).

---

## Feature 11: Berean Study Continuation
**State: Partial**

**What exists:** `BereanStudyThreadService.swift` — Firestore-backed study threads with `bereanThreads` collection. `AmenJourneyContinuityEngine.swift` — publishes `continuityPrompts` (continueStudyThread, revisitVerse, resumeChurchNote) and `formationMilestones`. `AMENFeatureFlags.bereanStudyThreadsEnabled = true`. `AMENFeatureFlags.bereanPersistentMemoryEnabled = true`. Tests: `AmenJourneyContinuityEngineTests.swift`.

**What's missing:**
1. No consent gate before `AmenJourneyContinuityEngine.loadForCurrentUser()` begins reading study history across sessions. `bereanPersistentMemoryEnabled` flag gates the feature but not a consent flow.
2. No cross-device handoff signal (NSUserActivity / Handoff) — continuation is Firestore-only, not Handoff-aware.

**Why it's this risk level:** Study history reveals theological interests and doubts — sensitive spiritual data. Weak consent gap.

**Recommended Phase:** Phase 7 (spiritual graph/care).

---

## Feature 12: Emotional State Awareness
**State: Partial**

**What exists:** `TruthEmotionService.swift` — calls `analyzeTruthVsEmotion` CF, stores `TruthEmotionAnalysis` in `users/{uid}/truthEmotionAnalyses`. `AmenFabricConsentScope.emotionalContext` defined in `AmenAIConsentStore.swift` (line 55). `WellnessMoodEngine.swift` — manual mood check-in (user-initiated). `PersonalSpiritualGraphService` records `PatternType.emotionalTrigger` from content signals. `AMENFeatureFlags.emotionalContextEngineEnabled = true` (line 1002). `WellnessOnboardingSheet.swift` exists.

**What's missing / broken — CRITICAL:**
`AmenAIConsentStore.hasFabricConsent(for: .emotionalContext)` is defined at line 31 of `AmenAIConsentStore.swift` but is called **nowhere** in the codebase (confirmed by grep returning only the definition site). This means emotional state detection and storage proceeds with zero consent enforcement despite the infrastructure existing. The `WellnessOnboardingSheet` does not set this consent key.

**Why it's critical:** Emotional state data is sensitive health-adjacent data. Under GDPR Article 9 and CCPA, inferring emotional state from app behavior without explicit consent is a legal exposure.

**Recommended Phase:** Phase 2 (safety-critical) — add `hasFabricConsent(.emotionalContext)` check before writing to `TruthEmotionAnalysis` and before `recordPattern(.emotionalTrigger)`.

---

## Feature 13: Travel Mode
**State: Partial**

**What exists:** `LocationContextService.swift` — `CLLocationManager` with city/state/country tracking, `isNewArea` detection (line 73). `EnvironmentType.international` classification in `EnvironmentContextService`. `AmenCompanionModels.swift` defines `CompanionPrompt.newAreaPrompt()` for new-city detection (lines 104–113). `AmenCompanionViewModel.swift` calls `LocationContextService.requestLocationIfNeeded()`.

**What's missing:**
1. **CONSENT_MISSING:** `LocationContextService` starts updating location after `requestWhenInUseAuthorization()` — no AMEN-authored purpose dialogue explaining travel detection use.
2. **NO_FLAG:** No feature flag gates travel-mode detection or new-area prompts.
3. No Berean travel-mode adaptation (cross-cultural scripture context, timezone-aware rhythm).
4. `CompanionPrivacyManager.swift` exists but unclear if it enforces consent before companion features activate.

**Recommended Phase:** Phase 3 (location).

---

## Feature 14: New City Detection
**State: Partial**

**What exists:** `LocationContextService.swift` — `lastCityKey`/`lastStateKey` stored in `UserDefaults` (lines 17–18, 71–78). `isNewArea` computed by comparing current city to stored city. `AmenCompanionModels.CompanionPrompt.newAreaPrompt()` fires when `isNewArea = true`. `ChurchDiscoveryService` is surfaced on new area. No feature flag.

**What's missing:**
1. **CONSENT_MISSING:** New-city detection writes location history to `UserDefaults` without an AMEN consent prompt. System location permission is the only gate.
2. **NO_FLAG** at detection or prompt level.
3. No deduplication — if user re-enters a city they visited last month, the prompt may not fire correctly since `lastCity` is overwritten on each new area.

**Recommended Phase:** Phase 3 (location).

---

## Feature 15: Family Event Awareness
**State: Missing**

**What exists:** `EKEventStore` is used in `ChurchProximityEngine` for calendar correlation, but only to check for church-related events (lines 296–304). No family event classification, no family relationship graph, no family-event-triggered Berean adaptation.

**What's missing:** All 8 layers. Would require `EKEventStore` with family-event keywords, `EventKit` consent, relationship graph to identify family members.

**Recommended Phase:** Phase 7 (relationship/care graph).

---

## Feature 16: Relationship Follow-Up
**State: Partial**

**What exists:** `AMENAPP/AMENAPP/AMENAPP/RelationshipGraph/RelationshipService.swift` and `RelationshipModels.swift` — define `AmenGroup`, `AgeBand`, `RelationshipChurch`. `PrayerFollowThroughService.swift` tracks prayer follow-through. `AmenJourneyContinuityEngine` includes `ActionType.followUpPrayer`. `AMENFeatureFlags.careFollowupsEnabled = true`. `AmenFabricConsentScope.relationshipSafety` defined in `AmenAIConsentStore.swift`.

**What's missing / broken:**
1. **CONSENT_MISSING:** `AmenAIConsentStore.hasFabricConsent(for: .relationshipSafety)` never called. Relationship health inferences proceed without consent enforcement.
2. **NO_FLAG** at `RelationshipService` entry points.
3. No signal-based relationship event detection (birthday, anniversary, extended silence in DMs).
4. No dedicated UI for relationship follow-up suggestions beyond generic `careFollowupsEnabled` surfaces.

**Recommended Phase:** Phase 7 (graph/care), Phase 2 for consent gate.

---

## Feature 17: Volunteer Burnout
**State: Missing**

**What exists:** `PersonalSpiritualGraphService` has `SpiritualRhythm.serving` (line 89) which tracks volunteering activity, and `GrowthVelocity.VelocityTrend.declining` which could theoretically indicate burnout. `WellnessRiskLayer.swift` detects generic emotional distress patterns. No dedicated volunteer-burnout detection model, no `SpiritualRhythm.serving` decline alert, no Berean "volunteer rest" mode.

**What's missing:** All 8 layers for burnout-specific detection. The serving rhythm + velocity decline combination could seed a burnout signal but requires an explicit detection algorithm and consent gate.

**Recommended Phase:** Phase 8 (wellbeing), building on `PersonalSpiritualGraphService`.

---

## Feature 18: Berean Context Detection (scripture in photos/screenshots/PDFs/notes/messages)
**State: Present**

**What exists:** `BereanVisualScriptureService.swift` — on-device `VNRecognizeTextRequest` OCR (line 186), multi-language support (en-US, es-ES, pt-BR, fr-FR, de-DE), scripture reference regex parser (`detectReference()`), `bereanBibleQA` CF for context cards (line 153). `BereanVisualScriptureView.swift` — camera/photo picker UI. `AMENFeatureFlags.bereanVisualScriptureEnabled = true` (line 697). Feature is gated: line 116 checks flag before processing. Tests: `BereanMultimodalSafetyTests.swift`.

**What's missing:**
1. **PDFs:** `ChurchNotesPDFExporter.swift` exports PDFs but no inbound PDF OCR pipeline for scripture detection exists.
2. **Messages/Notes scanning:** No background scan of iMessage or Apple Notes for scripture references.
3. **Safari:** No Safari extension for in-browser scripture detection.
4. Consent for camera access flows through iOS system dialog only — no AMEN-authored purpose explanation specific to "scripture detection" use.

**Why it's the best-state feature:** Flag present, proxy used, on-device OCR (no raw image upload), UI, tests. Gaps are additive (PDFs/Safari), not blocking.

**Recommended Phase:** Phase 6 (content/scripture) for PDF inbound + Safari.

---

## Feature 19: Meeting-to-Notes
**State: Partial**

**What exists:** `AMENAPP/AMENAPP/AMENAPP/Meetings/` — `MeetingModels.swift`, `MeetingService.swift`, `LiveMeetingView.swift`, `HostGatheringSheet.swift`. Models define agenda blocks reusing Church Notes concepts (line 18: `agendaBlocks: [AgendaBlock]`). Gathering intelligence CFs in `Backend/functions/src/integrations/intelligence/`: `gatheringRecapFromVerifiedContent.ts`, `gatheringAgendaSuggestions.ts`, `gatheringFollowUps.ts`. `SermonIntelligenceEngine` can transcribe + export to Church Notes (existing path).

**What's missing:**
1. **Consent:** No microphone consent gate before live meeting transcription.
2. **NO_FLAG** at `MeetingService` entry — `amenGatheringsEnabled` flag exists but the meeting-to-notes pipeline is not specifically gated.
3. No auto-detect of "meeting has started" — user must manually initiate notes.
4. Meeting transcription integration with `SermonIntelligenceEngine` is implicit, not wired.

**Recommended Phase:** Phase 5 (time/schedule integration), Phase 2 for microphone consent.

---

## Feature 20: Quiet Moment
**State: Partial**

**What exists:** `LivingEntryTriggerType.quietMoment` (line 41 of `LivingEntryModels.swift`). `LivingEntryContextEngine.swift:96–100` evaluates `quietMoment` trigger when `lowMotion && appOpenedAfterInactivity && eveningHours && !activeTyping`. `LivingEntryService.swift:293` seeds quiet moment triggers. `FindChurchLivingEntryBridge.swift` also seeds them (lines 50, 82). Tests: `LivingEntryContextEngineTests.swift`.

**What's missing:**
1. **Signal weakness:** `lowMotion` is not real `CMMotionActivity` data — it's a boolean passed in from the call site, typically hardcoded `true` in `LivingEntryRuntimeContext.current()` (line 37). No actual accelerometer check.
2. **NO_FLAG** specifically for quiet-moment detection vs generic `livingEntries` flag.
3. Quiet-moment Berean adaptation is only a content prompt, not a full mode change.

**Recommended Phase:** Phase 4 (motion detection) to wire real CMMotionActivity.

---

## Feature 21: Emergency Care
**State: Partial**

**What exists:** `CrisisDetectionService.swift`, `EnhancedCrisisSupportService.swift`, `CrisisHistoryService.swift`. Crisis support UI in `AMENAPP/AMENAPP/Crisis/` (8 files) — `CrisisSupportView`, `CrisisBereanModule`, `CrisisGroundingModule`, `CrisisSafetyPlanModule`. `WellnessRiskLayer.swift` detects crisis patterns. `InternationalCrisisLines.swift`. `PrayerSafetyEscalationService.swift`. Feature flags: `checkInCrisisEscalationEnabled = true`, `sextortionPanicFlowEnabled = true`. Tests: `SelahAICrisisShortCircuitTests.swift`.

**What's missing:**
1. **CONSENT_MISSING:** `CrisisDetectionService` passively monitors message/content streams for crisis language without explicit user opt-in. No `AmenFabricConsentScope` gate.
2. No "Emergency Care mode" user-facing opt-in flow distinct from the general wellness onboarding. The spec calls this an opt-in feature; current implementation is passive/always-on.
3. Crisis persistence audit finding from prior session (MEMORY.md: "crisis persistence" as a critical finding) suggests crisis data may persist beyond user intent.

**Recommended Phase:** Phase 2 (safety-critical) — crisis detection can remain passive as a safety measure, but the escalation path to care resources requires explicit consent for data retention.

---

## Cross-Cutting System A: Faith Rhythm Intelligence
**State: Partial**

**What exists:** `PersonalSpiritualGraphService.swift` — tracks `SpiritualRhythm` (prayer, scripture, church attendance, fellowship, etc.) and `SpiritualStruggleCategory` from Berean chat, church notes, prayer requests, testimonies, and app behavior. Stores to `users/{uid}/spiritualGraph/` with 90-day TTL. `SpiritualRhythmOS/` (5 files) — `SpiritualRhythmOSService`, `SpiritualNotificationPolicyEngine`, settings views, streak dashboard. `CalmControl/` — rhythm streaks, notification policy. `AMENFeatureFlags.spiritualRhythmEnabled = true`. Tests: `SpiritualRhythmOSTests.swift`.

**What's missing:**
1. **CONSENT_MISSING:** `PersonalSpiritualGraphService.recordPattern()` is called without checking `AmenFabricConsentScope.wellnessSignals`. No consent gate at pattern-recording sites.
2. **NO_FLAG at `recordPattern()`** — the rhythm OS flags gate UI surfaces but not the underlying data collection.
3. No cross-device sync of rhythm data (Firestore-only, no CloudKit).

**Recommended Phase:** Phase 2 (consent gate at `recordPattern()`).

---

## Cross-Cutting System B: Spiritual Milestone Detection
**State: Partial**

**What exists:** `AmenJourneyContinuityEngine.FormationMilestone` — milestone model with `achievedAt`, `category`. `SpiritualRhythmOS` streak system with `SpiritualMomentumState` (grounded/growing/reflecting/resting). `AMENFeatureFlags` has streak-related flags. Tests: `AmenJourneyContinuityEngineTests.swift`, `SpiritualRhythmOSTests.swift`.

**What's missing:**
1. No baptism/first sermon/salvation anniversary detection — only in-app behavioral streaks.
2. No calendar-based milestone detection (e.g., "1 year since you joined").
3. No external signal integration (EKEventStore for faith milestones).
4. Milestone data flows through Firestore without consent gate for behavioral inference.

**Recommended Phase:** Phase 7 (spiritual graph).

---

## Cross-Cutting System C: Safe Attention System
**State: Partial**

**What exists:** `AMENFeatureFlags.antiDoomscrollEnabled = true`. `AMENFeatureFlags.mediaDoomScrollGuardEnabled = true`. `AMENFeatureFlags.lateNightPauseEnabled = true`. `HealthyModeService.swift`. `AmenMediaCompletionReflectionView`. `DoomscrollGuardTests.swift`. `AmenZeroDistractionTests.swift`. Feed pacing in `FeedIntelligenceService`. `SpiritualOS/MomentInterceptionService.swift`. `CalmControl` suite.

**What's missing:**
1. No on-device `CMMotionActivity` signal to infer actual engagement intensity vs passive use.
2. No integration with Apple's Screen Time / FamilyControls API for external time-limit signaling.
3. `MomentInterceptionService` (spiritual pause before posting) — no consent gate for behavioral monitoring.
4. No Live Activity for "you've been in feed for X minutes" — `AmenLiveActivityAttributes` exists but no FeedSession live activity defined.

**Recommended Phase:** Phase 4 (motion), Phase 5 (schedule/time).

---

## Cross-Cutting System D: Context-Aware Berean
**State: Partial**

**What exists (per surface):**
- **CarPlay:** Full implementation in `AMENAPP/CarPlay/` — `AmenCarPlaySceneDelegate`, templates, voice, audio services. Flag: `carPlayBereanEnabled`.
- **Lock Screen / Dynamic Island:** `AmenLiveActivityAttributes.swift` + `AmenLiveActivityManager.swift` + `AmenLiveActivityViews.swift`. `PrayerSessionAttributes` and `BereanStudyAttributes` ActivityKit types defined.
- **Apple Watch:** Zero code found. No WatchKit, no WKExtension, no Watch target.
- **Siri / App Intents:** `AmenAppIntents.swift` (StartPrayerModeIntent, AskBereanIntent, FindChurchIntent, more). `AmenIntentRouter.swift`. `AMENShortcutsProvider` referenced but in a different file.
- **Spotlight:** `SpotlightIndexingService.swift`, `AmenSpotlightService.swift`, `SpotlightView.swift` — church notes and berean content indexed.
- **Share Sheet:** `BereanShareSheet.swift` in `Sharing/`. Scripture sharing wired.
- **Camera / Photos OCR:** `BereanVisualScriptureService.swift` + `BereanVisualScriptureView.swift` — Vision-based on-device OCR.
- **PDFs (inbound):** Only `ChurchNotesPDFExporter.swift` (outbound). No inbound PDF scripture detection.
- **Safari Extension:** No code found.
- **Messages (in-app):** `SmartMessageIntelligence/` and `BereanSmartChannelHook.swift` detect scripture references in messages.

**What's missing:**
1. Apple Watch target entirely absent — no Berean companion on watchOS.
2. Safari Extension absent — no in-browser scripture detection.
3. Inbound PDF OCR absent.
4. Siri `AmenAppShortcutsProvider` removed (noted in file comment line 21: "P2 FIX: AmenAppShortcutsProvider has been REMOVED to eliminate duplicate AppShortcutsProvider"). Canonical provider in `AMENAppIntents.swift` — verify wiring.

**Recommended Phase:** Phase 6 (content/scripture) for PDF + Safari; WatchOS is a separate target scope.
