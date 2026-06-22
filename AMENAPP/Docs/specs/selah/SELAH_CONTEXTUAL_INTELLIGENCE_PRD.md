# Selah Contextual Intelligence PRD

Status: first mic-free slice implemented in `SelahContextualIntelligenceService`.

## Product Principle

Selah may interrupt only when it is consented, local-first, high-confidence, and timely. Silence is a valid product outcome. The system should prefer quiet in low-confidence, high-sensitivity, Sabbath, cooldown, and missing-permission states.

## Architecture Review

Existing AMENAPP fit:

- `AMENAPP/AMENAPP/AIIntelligence/AmenSmartContextDetectionEngine.swift` already provides local deterministic detection for text contexts. Selah should reuse this posture for ambient signals.
- `AMENAPP/AMENAPP/AIIntelligence/AmenContextDetectionBridge.swift` converts local detections into UI chips. Future Selah suggestions can get a similar bridge into Selah cards, feeds, and notification copy.
- `AMENAPP/AMENAPP/AMENAPP/SelahIntelligenceEngine.swift` already ranks Selah media and detects rest signals. The next wiring step is to feed its session state into `SelahContextualInput` from a shared target boundary.
- `AMENAPP/AMENAPP/AMENAPP/AIIntelligence/SelahMomentService.swift` owns the pause/sensory layer. Sabbath and rest outputs should route there for quiet presentation.
- `AMENAPP/AMENAPP/AMENAPP/SelahSessionShapingCard.swift` already renders good-stopping-point UX. Long-session and rest outputs should use this surface before any notification surface.
- `AMENAPP/AMENAPP/AMENAPP/Contracts/Protocols/SelahProtocols.swift` contains trust, Berean, and Aegis contracts. Generated or doctrinal Selah content must pass through these trust contracts before surfacing.

New first-slice file:

- `AMENAPP/AMENAPP/AMENAPP/AIIntelligence/SelahContextualIntelligenceService.swift`

New tests:

- `AMENAPP/AMENAPPTests/SelahContextualIntelligenceServiceTests.swift`

## Phase Map

| Phase | Goal | Features | Primary Files / Services | Permissions |
| --- | --- | --- | --- | --- |
| Phase 1: Mic-free restraint foundation | Ship local confidence, Sabbath, liturgical, and reflection gates. | 5, 13, 15, 16, 18, 19 | `SelahContextualIntelligenceService`, `SelahIntelligenceEngine`, `SelahSessionShapingCard`, `SelahScriptureReferenceParser`, `BereanTrustBadge` | None beyond app-owned state. |
| Phase 2: System signals | Add explicit OS signals without mic or sensitive health/screen APIs. | 1, 2, 6, 7, 8, 9, 12, 17 | Camera Lens/OCR, group/session sync, scripture reader, Berean verification, context bridge | Camera, Calendar, Location category, Share Sheet/Clipboard, group membership. |
| Phase 3: Consented media | Add foreground, intentional audio/photo/social flows. | 3, 4, 10, 11 | Foreground audio session, sermon/song history, Photos opt-in, prayer request ingestion | Foreground audio, Photos, social graph. |
| Phase 4: Sensitive signals | Add highest-trust interventions only after consent and policy review. | 14, 20 | Screen Time adapter, HealthKit adapter, Aegis safety review, settings audit | Screen Time, Health. |

## Feature Acceptance Criteria

| # | Feature | Acceptance Criteria |
| --- | --- | --- |
| 1 | Bulletin & Slide Capture | User initiates camera scan; OCR runs on device; verse refs open in reader; no image leaves device by default. |
| 2 | Small Group Live Sync | User joins a known group session; one navigation event updates participants; leaving the session stops sync. |
| 3 | Worship Set Builder | User explicitly starts foreground listening; recognized songs are saved with scripture anchors; listening stops on exit. |
| 4 | Sermon Memory | User consents to sermon history; related prior sermons surface with provenance; no always-listening behavior. |
| 5 | Liturgical Layer | Date/tradition changes suggestions locally; seasonal prompts never require network; user can disable. |
| 6 | Commute / CarPlay Formation | Motion or CarPlay mode switches to audio-first; no screen-dependent prompt is required while driving. |
| 7 | Travel & Place Awareness | Uses coarse place category only; offers one contextual resource; suppression prevents repeat offers. |
| 8 | Series Auto-Assembly | Recurring sermon passages create a reading plan draft; user approves before saving. |
| 9 | Copied-Verse Catch | Share Sheet/clipboard reference opens context; no clipboard polling beyond platform-allowed user action. |
| 10 | Photo-Memory Anchoring | Photos permission is explicit; anchoring happens on device first; upload/share requires a second action. |
| 11 | Prayer Request Radar | Prayer request signal comes from visible/social content; user chooses pray now; generated prayer is draft-only. |
| 12 | Group Reading Presence | Presence shows only opted-in friends/groups; capped frequency prevents notification loops. |
| 13 | Sabbath / Rest Mode | Chosen Sabbath silences non-rest Selah prompts; streaks/badges are hidden; one rest screen remains available. |
| 14 | Doomscroll Interceptor | Extended churn can trigger one off-ramp; no punitive lockout; user can disable. |
| 15 | Confidence-Gated Silence | Every suggestion has confidence; low confidence suppresses by default; suppression reason is testable. |
| 16 | Reflection-to-Action Loop | Reflection can queue one follow-up; user controls timing; no private text is logged in analytics. |
| 17 | Berean Verification Gate | AI claims pass Berean checks; unverifiable outputs are labeled, withheld, or routed to review. |
| 18 | Cross-Reference Web | Tapped verses produce a graph from known references; edges have provenance; works offline for bundled references. |
| 19 | Translation & Tradition Tuning | Translation/tradition preferences tune defaults; cross-tradition notes are labeled rather than blocked. |
| 20 | Stress-Aware Surfacing | Health permission is explicit and separate; content is never diagnostic; disable control is one tap away. |

## Service / Model Map

Core models in the first slice:

- `SelahContextualFeature`: all 20 features as stable IDs.
- `SelahContextualPermission`: permission requirements, separated from Info.plist/entitlements.
- `SelahContextualPhase`: release phase for each feature.
- `SelahContextualSettings`: user controls, granted permissions, cooldowns, Sabbath choice, interrupt tolerance.
- `SelahContextualInput`: local signal packet passed to the evaluator.
- `SelahContextualSuggestion`: UI-ready suggestion with feature, surface, title, message, scripture refs, and confidence.
- `SelahContextualEvaluation`: suggestions plus suppression reasons.

Future adapters should be thin and permission-scoped:

- `SelahCalendarSignalProvider`: calendar/group meeting signal.
- `SelahLocationCategoryProvider`: coarse place category only.
- `SelahForegroundAudioSignalProvider`: explicit service/session listening only.
- `SelahHealthSignalProvider`: HealthKit opt-in, no diagnosis.
- `SelahScreenTimeSignalProvider`: Screen Time opt-in, one off-ramp per cooldown window.

## Analytics Contract

Log interactions and suppression categories, never raw content:

- Allowed: feature ID, surface, confidence bucket, suppression reason, permission state, action key.
- Forbidden: message text, reflection text, prayer text, photo metadata, precise location, health values, sermon transcript content.

## First Slice Done

Implemented:

- Feature catalog for all 20 Selah contextual features.
- Permission and phase map in code.
- Local liturgical season suggestion for non-ordinary seasons.
- Sabbath/rest suggestion and Sabbath silence gate.
- Reflection-to-action queue suggestion.
- Confidence thresholds based on interrupt tolerance.
- Cooldown suppression by feature.
- Tests for liturgical output, Sabbath suppression, permission suppression, low-confidence silence, cooldown, and phase-one catalog.

Not yet wired:

- Shared-target bridge from `SelahIntelligenceEngine` session state into `SelahContextualEvaluation`.
- SwiftUI surfaces for the new suggestion model.
- Persistence of `SelahContextualSettings`.
- Real providers for Calendar, Camera OCR, Location category, foreground audio, Photos, Screen Time, or Health.
- Berean verification routing for generated contextual content.
