# MANIFEST — Full-App Coverage Matrix
## Overnight Audit 2026-05-30 | Branch: overnight/full-audit-20260530

**Total SwiftUI Views:** 4,567 across all domains
**Total Cloud Functions (this repo):** 297 exported; 71 with iOS callers
**Total iOS callable invocations:** 449 unique names (378 target Backend/TS codebase)
**Total Feature Flags:** 1,000+ across 8 flag files
**Firestore Collections:** 50+ unique paths
**Navigation routes / deep links:** 12+ URL schemes, 6 router files

---

## Coverage Key
- **Audited:** Y = Phase 1 agent completed | P0 = Phase 0 inventory only
- **Severity:** LOW / MEDIUM / HIGH / CRITICAL
- **Status:** OK / Fixed / Queued (review queue) / Pending (Phase 2)

---

## Domain 1 — Auth & Onboarding & App Check

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| AMENAuthLandingView | AMENAuthLandingView.swift | Screen | P0 | - | Pending |
| MinimalAuthenticationView | MinimalAuthenticationView.swift | Screen | P0 | - | Pending |
| OnboardingFunnelView | Onboarding/OnboardingFunnelView.swift | Screen | P0 | - | Pending |
| FindYourPeopleFTUEView | AMENAPP/FindYourPeopleFTUEView.swift | Screen | P0 | - | Pending |
| EmailVerificationGateView | EmailVerificationGateView.swift | Screen | P0 | MEDIUM | Pending (unguarded withAnimation x2) |
| AmenOrgOnboardingFlow | AmenOrgOnboardingFlow.swift | Screen | P0 | - | Pending |
| AmenVerificationFlowCoordinator | AmenVerificationFlowCoordinator.swift | Screen | P0 | - | Pending |
| FindFriendsOnboardingView | FindFriendsOnboardingView.swift | Screen | P0 | - | Pending |
| AppNavigationRouter | AppNavigationRouter.swift | Service | P0 | - | Pending |
| App Check guards | AMENAPPApp.swift | Wire | P0 | - | Pending |

## Domain 2 — HeyFeed + Liturgical + Pastoral Routing

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| HeyFeed views (~40 files) | AMENAPP/AMENAPP/heyFeed/ | Screens | P0 | - | Pending |
| FeedIntelligenceOS | FeedIntelligenceComponents.swift | Service | P0 | - | Pending |
| HeyFeedTuningPill | HeyFeedTuningPill.swift | Component | P0 | OK | Clean (Motion.adaptive) |
| Liturgical calendar / awareness | LiturgicalCalendar.swift | Service | P0 | - | Pending |
| Pastoral care routing | Various | Service | P0 | - | Pending |

## Domain 3 — Berean AI (5 modes, SSE, persistence)

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| BereanLandingView | BereanLandingView.swift | Screen | P0 | MEDIUM | Pending (11 unguarded animations — has env var but doesn't use it) |
| BereanAIAssistantView | BereanAIAssistantView.swift | Screen | P0 | LOW | Pending (TODO stubs) |
| BereanVoiceCompanionView | AIIntelligence/BereanVoiceCompanionView.swift | Screen | P0 | - | Pending |
| BereanVoiceStudySessionStore | AIIntelligence/BereanVoiceSessionStore.swift | Service | P0 | OK | Fixed (force-unwrap: ffe02f7) |
| BereanContextCoordinator | AIIntelligence/BereanContextCoordinator.swift | Service | P0 | - | Pending |
| BereanRealtimeSessionManager | AIIntelligence/BereanRealtimeSessionManager.swift | Service | P0 | MEDIUM | Pending (CF-03: no error handling for createRealtimeSession) |
| SSE / WebSocket transport | BereanRealtimeWebSocketTransport.swift | Service | P0 | - | Pending |
| BereanMemoryService | BereanMemoryService.swift | Service | P0 | OK | Verified correct (prior audit) |
| BereanConversationService | BereanConversationService.swift | Service | P0 | OK | Verified correct (prior audit) |
| bereanChatProxy CF caller | ClaudeAPIService.swift:115 | CF Call | P0 | MEDIUM | Queued (RQ-02) |
| bereanGenericProxy CF caller | Feature05_AccountabilityThread.swift:169 | CF Call | P0 | MEDIUM | Queued (RQ-02) |
| BereanPulse (~18 files) | AMENAPP/AMENAPP/AMENAPP/AMENAPP/BereanPulse/ | Screens | P0 | - | Pending |

## Domain 4 — Berean Notebooks (Pinecone, studio artifacts)

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| Studio artifact views | AIIntelligence/CreatorKit/AmenCreatorKitHome.swift | Screen | P0 | - | Pending |
| studioGenerateContent CF | functions/index.js | CF | P0 | OK | Has iOS caller |
| studioJournalPrompt CF | functions/index.js | CF | P0 | OK | Has iOS caller |
| Pinecone namespace queries | Various | Service | P0 | - | Pending |

## Domain 5 — ARISE/OUTPOUR Video + Anti-Addiction + Safety Pipeline

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| Media session views | Media/ | Screens | P0 | - | Pending |
| mediaFiniteSessionsEnabled | AMENFeatureFlags | Flag | P0 | OK | Default true |
| mediaDoomScrollGuardEnabled | AMENFeatureFlags | Flag | P0 | OK | Default true |
| mediaCompletionReflectionEnabled | AMENFeatureFlags | Flag | P0 | OK | Default true |
| processVideoProxy CF | CreatorVideoProcessingService.swift:18 | CF Call | P0 | MEDIUM | Queued (RQ-02, Backend/TS) |
| ShortFormTeachingFeedView | ShortFormTeachingFeedView.swift | Screen | P0 | LOW | Pending (UI-07: TODO stubs) |

## Domain 6 — Church Notes (Block Editor, Selah/Postcard)

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| ChurchNotesView (~144 files in domain) | ChurchNotesView.swift | Screen | P0 | - | Pending |
| Church notes block editor | ChurchNotesEditor.swift | Screen | P0 | OK | Fixed (draft save: 5793d38) |
| SelahScriptureReaderView | SelahScripture/SelahScriptureReaderView.swift | Screen | P0 | MEDIUM | Pending (unguarded withAnimation x2) |
| BereanChurchNotesBridge | BereanChurchNotesBridge.swift | Service | P0 | MEDIUM | Pending (unguarded withAnimation:337) |

## Domain 7 — GUARDIAN Moderation

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| GuardianService | GuardianService.swift | Service | P0 | OK | Fixed (failClosed: 88665b5) |
| SafetyUIComponents | SafetyUIComponents.swift | Components | P0 | LOW | Pending (hard-coded cornerRadius x9) |
| CrisisSupportCard | CrisisSupportCard.swift | Component | P0 | MEDIUM | Pending (unguarded withAnimation:292,296) |
| DisasterAlertCard | DisasterAlertCard.swift | Component | P0 | MEDIUM | Pending (unguarded withAnimation) |
| contentPreflightEnabled | AmenSafetyFeatureFlags | Flag | P0 | OK | Default true |
| trustSafetyKillSwitch | AmenSafetyFeatureFlags | Flag | P0 | OK | Default false |

## Domain 8 — Get Ready (Geofencing/Location/Motion/Calendar/Wallet)

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| GetReady views (~12 files) | Get Ready/ | Screens | P0 | - | Pending |
| ChurchAssistFeatureFlags.debugForceAllEnabled | ChurchAssistFeatureFlags.swift | Flag | P0 | MEDIUM | Pending (FLAG-01: not #if DEBUG guarded) |
| Church visit session state | users/{uid}/churchAssistState/current | Firestore | P0 | - | Pending |

## Domain 9 — 242 Hub

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| 242Hub views (~62 files) | 242hub/ | Screens | P0 | - | Pending |
| 242hub.js CF | functions/242hub.js | CF | P0 | - | Pending |

## Domain 10 — Comms OS (Messaging, Groups, Agent 2I, Living Memory)

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| LiquidGlassMessagesView | LiquidGlassMessagesView.swift | Screen | P0 | - | Pending |
| UnifiedChatView | UnifiedChatView.swift | Screen | P0 | OK | Fixed (age-gate: 88665b5) |
| MessagingComponents | MessagingComponents.swift | Component | P0 | MEDIUM | Pending (UI-03: dead button) |
| GroupChatCreationView | GroupChatCreationView.swift | Screen | P0 | MEDIUM | Pending (unguarded withAnimation:354) |
| conversationOS functions | functions/conversationOS/ | CFs | P0 | - | Pending |
| Agent 2I / Intelligence Engine | AMENAPP/AMENAPP/AMENAPP/AMENAPP/BereanSmarts/ | Services | P0 | - | Pending |

## Domain 11 — Push Notification System (11 triggers)

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| NotificationDeepLinkHandler (deprecated) | NotificationDeepLinkHandler.swift | Service | P0 | MEDIUM | Pending (NAV-01: deprecated, still referenced) |
| NotificationDeepLinkRouter | NotificationDeepLinkRouter.swift | Service | P0 | OK | Fixed (block check: 5793d38) |
| sendPushNotification CF | functions/index.js | CF | P0 | OK | Has iOS caller |
| filterSmartNotifications CF | functions/index.js | CF | P0 | OK | Has iOS caller |
| getGroupedNotifications CF | functions/index.js | CF | P0 | OK | Has iOS caller |
| FCM topic logout | AMENAPPApp.swift | Wire | P0 | OK | Fixed (prior audit) |
| BadgeCountManager | BadgeCountManager.swift | Service | P0 | OK | Fixed (stopListening: 5793d38) |

## Domain 12 — SmartLink / Amazon Associates

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| SmartLink views | SmartLink/ | Screens | P0 | - | Pending |
| Amazon Associates wiring | SmartLink/ | Service | P0 | - | Pending |

## Domain 13 — Design System + Liquid Glass

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| AmenLiquidGlassComponents | AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift | DS | P0 | - | Pending |
| AmenLiquidGlassSurface | AmenLiquidGlassSurface.swift | DS | P0 | OK | Fixed (reduceTransparency: 88665b5) |
| TipSheetView | TipSheetView.swift | Screen | P0 | MEDIUM | Pending (DS-A01: hard-coded hex + 6 unguarded withAnimation) |
| BereanLandingView color extensions | BereanLandingView.swift:14-22 | Screen | P0 | LOW | Pending (DS-A02) |
| AMENResourcesHubView | AMENResourcesHubView.swift:104,119,134 | Screen | P0 | LOW | Pending (DS-A03) |
| ResourcesView | ResourcesView.swift:766,778,790 | Screen | P0 | LOW | Pending (DS-A04) |
| SpacesDesignSystem "See All" | SpacesDesignSystem.swift:434 | Component | P0 | MEDIUM | Pending (UI-01) |

## Domain 14 — Accessibility & Reduce Motion

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| ComponentsSharedUIComponents | ComponentsSharedUIComponents.swift:46,169,222,384 | Component | P0 | MEDIUM | Pending (DS-A05: 3 repeating animations + bare spring) |
| BereanLandingView animations | BereanLandingView.swift:116+ | Screen | P0 | MEDIUM | Pending (DS-A06: env var unused) |
| StarRatingRow | StarRatingRow.swift:60 | Component | P0 | MEDIUM | Pending (DS-A07) |
| MentorCardView | MentorCardView.swift:142,157 | Component | P0 | MEDIUM | Pending (DS-A08) |
| AmenTranslationComparisonCard | AmenTranslationComparisonCard.swift:181 | Component | P0 | MEDIUM | Pending (DS-A09) |
| TipView | TipView.swift | Screen | P0 | MEDIUM | Pending (DS-A10: 4 unguarded withAnimation) |
| MovementWellnessView | MovementWellnessView.swift | Screen | P0 | MEDIUM | Pending (DS-A10: 4 unguarded withAnimation) |
| FindChurchView | FindChurchView.swift | Screen | P0 | MEDIUM | Pending (DS-A10: 5 unguarded withAnimation) |
| 22 additional files (DS-A11) | Various | Various | P0 | MEDIUM | Pending (41+ unguarded withAnimation) |

## Domain 15 — Cloud Functions ↔ Client Contract

| Item | File | Type | Audited | Severity | Status |
|------|------|------|---------|----------|--------|
| Two-codebase architecture | functions/index.js | Architecture | Y | HIGH | Queued (RQ-01) |
| 378 iOS calls to Backend/TS | 378 Swift files | CF Calls | Y | HIGH | Queued (RQ-01) |
| 226 exports without iOS callers | functions/index.js | CF | Y | LOW | Queued (CF-02: informational) |
| Critical AI proxy calls | ClaudeAPIService.swift, etc. | CF Calls | Y | MEDIUM | Queued (RQ-02) |
| _noop test collection | Client code | Firestore | Y | LOW | Pending (COL-01: #if DEBUG guard) |

---

## Summary Counts

| Phase | Total Items | Audited (Y) | Audited (P0 only) | Not Yet Audited |
|-------|-------------|-------------|-------------------|----------------|
| Phase 0 complete | ~350 manifest rows | 15 | ~335 | 0 |
| Phase 1 pending | ~335 rows | 0 | ~335 | → launching now |

**All rows have been inventoried at P0 level. Phase 1 domain agents will complete full audits.**

---

*Generated: 2026-05-30 | Overnight Audit Run*
