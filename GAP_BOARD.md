# AMEN Full-App Gap Board

Audit date: 2026-06-11  
Scope: full-app gap audit, eight lanes. Lanes 1-6 were delegated read-only; lanes 7-8 and test fallback were consolidated locally due agent thread/timeout limits.

## P0 List

| Gap | Evidence | Owner / Lane | Fix Size |
|---|---|---|---|
| Report-user control can no-op because it posts an unobserved notification. | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift:496`; auditor grep found only this occurrence of `amenReportUser`. | Connect / Safety | M |
| Profile Pray/Message actions can no-op because they post unobserved notifications. | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift:245`, `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift:253`; auditor grep found only post sites for `amenPrayForUser` and `amenOpenDM`. | Connect | M |
| Safe Zone creation stores a hard-coded Apple Park coordinate instead of current location. | `AMENAPP/AMENAPP/AMENAPP/CameraOS/Safety/SafeZoneService.swift:214` uses `CLLocation(latitude: 37.3318, longitude: -122.0312)`. | CameraOS Safety | M |
| Raw phone numbers are logged client-side. | `AMENAPP/PhoneVerificationService.swift:57` logs `Sending verification code to: \(phoneNumber)`; `AMENAPP/AuthenticationViewModel.swift:1512` logs the same class of data. | Privacy / Auth | S |
| Raw phone number is written to `/users/{uid}`, and rules raw-PII helper does not block `phoneNumber`. | `AMENAPP/PhoneVerificationService.swift:147-148`; `AMENAPP/firestore.deploy.rules:240-243` blocks `contactPhone`, `contactEmail`, `homeAddress`, `salaryAmount` but not `phoneNumber`. | Privacy / Rules | M |
| Server logging can emit full Firestore event payloads. | `AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts:774` logs `{ id: snapshot.id, data: snapshot.data() }`. | Backend / Privacy | M |
| Client-called church trust callables are deployed as stubs while real implementations live in a non-deployed mirror. | `firebase.json:46-59` deploys `Backend/functions`; deployed `Backend/functions/src/church/controllers/churchTrustCallables.ts:10-14` exports `unavailableCallable`; real implementations are in non-deployed `AMENAPP/Backend/functions/src/church/controllers/churchTrustCallables.ts:18`, `:49`, `:136`; clients call from `AMENAPP/ChurchTrustSafetyService.swift:86`, `:98`, `AMENAPP/BereanChurchGroundingService.swift:13`. | Backend Parity | L |
| Client-called Church Notes media-processing callables lack static Auth/App Check/rate-limit evidence. | Clients: `AMENAPP/AMENAPP/AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesMediaProcessingService.swift:473`, `:478`, `:483`; backend exports: `functions/churchNotesMediaPipeline.js:488`, `:532`, `:593`. | Backend / Church Notes | L |
| Deployed backend files read provider/payment secrets from env/config instead of Secret Manager. | `Backend/functions/src/ambient/summarizeAmbientContext.ts:13`, `:33`; `Backend/functions/src/generateLiveKitToken.ts:39-49`; `Backend/functions/src/livingEntries/livingEntryAI.ts:500`, `:523`; `Backend/functions/src/covenant/stripeCovenantWebhook.ts:245-246`; `Backend/functions/src/onPostCreated.ts:111`; `Backend/functions/src/deleteAlgoliaUser.ts:33`; `Backend/functions/src/algoliaSync.ts:32`. | Backend / Secrets | M |
| `textModerationEnabled` can be forced off by absent Remote Config, making moderation fail-open after fetch. | `AMENAPP/CommunicationOSRemoteConfigBridge.swift:15`, `:62`; `AMENAPP/AMENFeatureFlags.swift:2012`; `AMENAPP/PostingOSFeatureFlags.swift:8`; `AMENAPP/AIIntelligence/AmenSafetyModerationProvider.swift:168`. | Flags / Safety | M |
| Church Notes media comment says unapproved processing remains off, but defaults are on. | `AMENAPP/AMENFeatureFlags.swift:158`, `:159`, `:954`; `AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteSemanticEditorView.swift:894`. | Flags / Church Notes | M |
| Church Notes media sub-flags are not independent kill switches because alias flags can keep surfaces active. | `AMENAPP/AMENFeatureFlags.swift:1569` ORs `churchNotesAudioCaptureEnabled` with `sermonAudioCaptureEnabled` and similar aliases. | Flags / Church Notes | M |
| Local crisis keyword detection ships empty and no in-repo configurator call was found. | `AMENAPP/AIIntelligence/AmenSmartContextDetectionEngine.swift:13-16`, `:177`, `:206-210`, `:313`; `XcodeGrep configureRuntimeCrisisKeywords` found only the declaration/assignment sites. | Privacy / Safety | M |

## Consolidated Gap Board

| Gap | Evidence | Severity | Owner / Lane | Fix Size |
|---|---|---|---|---|
| Connect V2 is declared active but not mounted in real navigation. | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AGENT_LANES.md:7`; active tab 6 mounts `AmenConnectSpacesHubView()` at `AMENAPP/ContentView.swift:699`; auditor grep found no `AmenConnectV2View(` / `AmenConnectView(` call sites. | P1 | Connect | M |
| Message-style deep links route to tab 3 while Messages is tab 2. | `AMENAPP/ContentView.swift:829` maps `.conversation`, `.chat`, `.messages`, `.groupJoin`, `.prayer`, `.churchNote` to tab `3`; Messages is mounted at `AMENAPP/ContentView.swift:653`. | P1 | Navigation | S |
| Pulse action router claims `amenapp://` support, but parser rejects non-`amen` scheme. | `AMENAPP/AMENAPP/AMENAPP/AMENAPP/Pulse/PulseActionRouter.swift:31`; `AMENAPP/DeepLinkRouter.swift:87`. | P1 | Pulse / Navigation | S |
| Context Passport is claimed complete but lacks a parent mount. | `AMENAPP/ContextStore/RUNLOG.md:12`; auditor grep for `AmenPassportView` found definitions/previews/internal links, not main navigation mount. | P2 | Context Store | M |
| Passport Berean/import entries still go to stubs. | `AMENAPP/ContextStore/AmenPassportView.swift:49`; TODO/stub evidence at `AMENAPP/ContextStore/AmenPassportView.swift:220`; real `BereanInterviewView` exists at `AMENAPP/ContextStore/BereanInterviewView.swift:60`. | P2 | Context Store | M |
| Spaces “My Spaces” rows look tappable but have no route. | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift:300`; chevron at `:442`; no tap/navigation handler in row body per auditor trace. | P2 | Connect Spaces | S |
| `Use Text Chat` button in voice assistant alert has an empty/manual action. | `AMENAPP/AIIntelligence/BereanVoiceAssistantView.swift:75`. | P1 | AIIntelligence / Berean | S |
| Intelligence card actions route to a not-implemented sheet. | `AMENAPP/Intelligence/IntelligenceCardView.swift:43`, `AMENAPP/Intelligence/IntelligenceCardView.swift:367-377`. | P1 | Intelligence | M |
| Live Activity contract is stubbed with `print` only. | `AMENAPP/Intelligence/AmenLiveActivityContract.swift:148`, `AMENAPP/Intelligence/AmenLiveActivityContract.swift:181-213`. | P1 | Intelligence / Live Activity | M |
| Recurring Gifts sheet says feature is being set up. | `AMENAPP/Giving/Views/StewardshipDashboardView.swift:81`, `AMENAPP/Giving/Views/StewardshipDashboardView.swift:383-397`. | P1 | Giving | M |
| External integrations page is “Coming Soon”. | `AMENAPP/IntegrationOS/ExternalIntegrationView.swift:168-173`. | P1 | IntegrationOS | M |
| Covenant post route returns a placeholder destination. | `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantViewModel.swift:146-176`. | P1 | Covenant | M |
| Covenant advanced settings, guidelines editor, and calendar export are placeholder alerts/toasts. | `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantManageView.swift:81-84`; `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantModerationView.swift:65-68`; `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantEventsView.swift:244-248`. | P1 | Covenant | M |
| Spatial feed renders placeholder cards and logs actions instead of executing feed behavior. | `AMENAPP/SpatialHomeView.swift:195-235`; action logging at `AMENAPP/SpatialHomeView.swift:243-258`. | P1 | Spatial / Home | L |
| Covenant hub/discovery show seeded fake content. | `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCreatorHubView.swift:353-357`, `:787-803`; `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantDiscoveryView.swift:176`, `:477-489`. | P1 | Covenant | M |
| Connect live/community actions post unobserved notifications. | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/Live/AmenAIHostAssistantPanel.swift:179`, `:194`; `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/Community/AmenCommunityAIManagerView.swift:666`, `:716`; `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenKnowledgeGraphSpacesLinkView.swift:212-215`. | P1 | Connect | M |
| ONE “New Conversation” posts unobserved contact-picker notification. | `AMENAPP/AMENAPP/AMENAPP/ONE/People/Views/ONEThreadListView.swift:147`, `:161`. | P1 | ONE / People | M |
| Firestore write inventory is much broader than explicit rules coverage. | Auditor static output: `static_firestore_write_targets=749`, `rule-covered=89`, `rule_missing=660`; examples missing: `AMENAPP/AIBibleStudyExtensions.swift:74`, `AMENAPP/AIIntelligence/BereanRealtimeServices.swift:77`, `AMENAPP/AIIntelligence/BereanRealtimeSessionManager.swift:68`, `AMENAPP/AMENAPP/AMENAPP/ContentOS/ContentForwardingService.swift:51`, `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:241`; catch-all deny at `AMENAPP/firestore.deploy.rules:2599-2600`. | P1 | Rules / Data Security | L |
| Client writes to callable-owned denied drafts path. | Rules deny `/users/{uid}/drafts` at `AMENAPP/firestore.deploy.rules:401-404`; client writes/deletes at `AMENAPP/AmenDraftPersistenceService.swift:59`, `:67`. | P1 | Rules / Drafts | M |
| Sensitive AI payloads lack explicit retention/logging contract evidence. | `AMENAPP/AIIntelligence/BereanSmartNotesView.swift:268`; `AMENAPP/AIIntelligence/BereanRealtimeServices.swift:100`, `:150`; `AMENAPP/AMENAPP/AmbientOS/AmbientOSSurfaceView.swift:135`. | P1 | Privacy / AI | M |
| Index inventory is too narrow for static write surface. | `AMENAPP/firestore.indexes.json` has 21 matched indexed groups; auditor output `index_missing=728`; duplicate `enforcementHistory` index at `AMENAPP/firestore.indexes.json:35-40`, `:305-310`. | P2 | Rules / Indexes | M |
| Multiple client-called callables have no deployed backend export found. | Examples: `AMENAPP/TimestampedCommentsView.swift:246`, `AMENAPP/AmenOpportunityService.swift:218`, `AMENAPP/AMENAPP/AMENAPP/Covenant/AmenCovenantPostComposerView.swift:86`, `:89`, `AMENAPP/AmenEntitlementService.swift:166`, `AMENAPP/CloudFunctionsService.swift:86`, `:154`, `:249`, `AMENAPP/AIIntelligence/BereanSmartNotesView.swift:267`. | P1 | Backend Parity | L |
| Several deployed callables lack App Check/rate-limit evidence. | `functions/actionIntelligenceFunctions.js:277`; `functions/moderatePost.js:446`; `functions/v2triggers/v2intelligenceFunctions.js:139-145`, `:217-222`. | P1 | Backend Security | L |
| Remote kill switch is partially wired. | `AMENAPP/RemoteKillSwitch.swift:25`; `AMENAPP/ContentView.swift:612`, `:628`; auditor grep found only feed/messaging/create/maintenance gates, no `killSwitch.bereanEnabled`, `.searchEnabled`, `.notificationsEnabled` consumers. | P1 | Flags / Config | M |
| Berean extended kill switches are decorative. | Declared at `AMENAPP/AMENFeatureFlags.swift:435`; assigned at `AMENAPP/AMENFeatureFlags.swift:1786`; auditor grep found no consumers outside flag file. | P1 | Flags / Berean | M |
| `actionIntelligenceEnabled` RC key has no matching default. | `AMENAPP/AMENFeatureFlags.swift:364`; applied from `ff_action_intelligence` at `AMENAPP/AMENFeatureFlags.swift:1747`; auditor grep found no `action_intelligence_enabled` default. | P1 | Flags / Action Intelligence | S |
| Find Church 2.0 keys are applied but not registered in defaults. | `AMENAPP/AMENFeatureFlags.swift:759`, `AMENAPP/AMENFeatureFlags.swift:1988`. | P1 | Flags / Find Church | S |
| BIL manifest flags are docs-only. | `AMENAPP/Docs/Contracts/BIL/FeatureFlags.md:12`; auditor grep found BIL keys in docs only. | P1 | BIL / Flags | M |
| Translation flags have split-brain defaults. | `AMENAPP/AMENFeatureFlags.swift:130` defaults `meaningAwareTranslationEnabled` false; `AMENAPP/TranslationFeatureFlags.swift:33` defaults true; both consumed at `AMENAPP/PostCard.swift:1835` and `AMENAPP/MeaningAwareTranslationService.swift:69`. | P1 | Translation / Flags | M |
| Main feature flag file has many zero/low-reference flags. | Auditor scanner output: `AMENFeatureFlags properties: 489`, `zero_runtime_refs: 235`, `low_runtime_refs: 161`; examples include `moderationAppealsEnabled`, `bereanDeepEnabled`, `smartShareSheetEnabled`, `socialSafetyOSEnabled`. | P2 | Flags / Config | L |
| Camera OCR opens `UIImagePickerController` camera without checking source availability or explicit preflight. | `AMENAPP/AMENAPP/AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNotesPhotoOCRCaptureView.swift:130-132`, `:264-267`. | P2 | Privacy / Church Notes | S |
| Voice navigation handles explicit opt-in and on-device recognition, but the broader crisis/local-context safety detector has empty runtime config. | Positive control: `AMENAPP/AMENAPP/AMENAPP/Accessibility/AIL/Interaction/AILVoiceNavigationController.swift:8-16`, `:86-95`, `:154-157`; gap evidence in `AMENAPP/AIIntelligence/AmenSmartContextDetectionEngine.swift:177`, `:313`. | P1 | Privacy / Safety | M |
| Raw/streak-like faith metrics appear in personalization context. | `AMENAPP/AIIntelligence/BereanContextCoordinator.swift:133-136`; `AMENAPP/AIIntelligence/DailyDigestService.swift:192-195`. | P2 | Privacy / Product Safety | S |
| Raw `.glassEffect` use is mixed with project-local shims, creating platform ambiguity under iOS 17 deployment. | Target deployment `IPHONEOS_DEPLOYMENT_TARGET=17.0`; raw calls in `AMENAPP/AMENAPP/AMENAPP/SpiritualOS/ContextEngine/AmenContextBanners.swift:36`, `:87`, `:146`, `:211`; project shim exists in `AMENAPP/GlassEffectModifiers.swift:38-46`; guarded Apple wrapper exists in `AMENAPP/LiquidGlassModifiers.swift:273-291`. | P2 | UX / Platform | M |
| Duplicate “ 2” artifact exists. | `XcodeGlob **/* 2*` returned `AMENAPP/AMENAPP/ContextStore/RUNLOG 2.md`. | P2 | Build Hygiene | S |
| No JS/TS `__tests__` files found; colocated backend `.test.ts` files are suspect under the audit’s stated Jest constraint. | `XcodeGlob **/__tests__/**/*.{ts,js}` returned `0`; colocated files: `AMENAPP/AMENAPP/Backend/functions/src/securityPosture.test.ts`, `safetyOSReactionEngine.test.ts`, `berean.rateLimit.test.ts`; environment fact says Jest only runs `__tests__/`. | P1 | Tests / Backend | S |
| Xcode test plan has broad enabled Swift tests, but several P0/P1 gaps above have no named executing test coverage. | `GetTestList` returned `1862 tests (1862 enabled, 0 disabled)`; no named tests were found for raw phone logging/storage, unobserved Connect report/DM notifications, deployed church-trust stub parity, or `textModerationEnabled` absent-RC fail-open. | P1 | Verification | M |

## Auditor Appendices

### A1 Stubs & Dead Surfaces

| Severity | Evidence | Finding |
|---|---|---|
| P0 | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift:496` | Report action posts `amenReportUser`; no in-repo receiver found. |
| P0 | `AMENAPP/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift:245`, `:253` | Pray/Message actions post notifications with no observed receiver. |
| P0 | `AMENAPP/AMENAPP/AMENAPP/CameraOS/Safety/SafeZoneService.swift:214` | Add Safe Zone uses hard-coded coordinate. |
| P1 | `AMENAPP/AIIntelligence/BereanVoiceAssistantView.swift:75` | “Use Text Chat” action is empty/manual. |
| P1 | `AMENAPP/Intelligence/IntelligenceCardView.swift:43`, `:367-377` | Intelligence action sheet is not implemented. |
| P1 | `AMENAPP/Intelligence/AmenLiveActivityContract.swift:148`, `:181-213` | Live Activity bridge is stubbed. |
| P1 | `AMENAPP/Giving/Views/StewardshipDashboardView.swift:81`, `:383-397` | Recurring Gifts is placeholder copy. |
| P1 | `AMENAPP/IntegrationOS/ExternalIntegrationView.swift:168-173` | Integrations page says coming soon. |
| P1 | `AMENAPP/SpatialHomeView.swift:195-258` | Spatial feed shows placeholder card and logs actions. |
| P2 | `AMENAPP/AMENAPP/AMENAPP/AmbientOS/AmbientOSSurfaceView.swift:28-32`, `:139-145` | Backend failure loads mock ambient context. |

### A2 Wiring & Reachability

| Feature | Mounted | Proof |
|---|---|---|
| Main app root | Yes | `AMENAPP/AMENAPP/AMENAPPApp.swift:250`, `:255`; `AMENAPP/ContentView.swift:624-626`. |
| Connect Spaces Hub | Yes | `AMENAPP/ContentView.swift:699`; space deep links map tab 6 at `AMENAPP/NotificationDeepLinkRouter.swift:646`, `AMENAPP/ContentView.swift:835`. |
| Connect Redesign V2 | No | `AGENT_LANES.md:7` declares it; auditor grep found no call site. |
| DeepLinkRouter message routes | Broken | `AMENAPP/ContentView.swift:829` maps to tab 3; Messages tab is `AMENAPP/ContentView.swift:653`. |
| Pulse action deep links | Partial | `AMENAPP/AMENAPP/AMENAPP/AMENAPP/Pulse/PulseActionRouter.swift:31`; `AMENAPP/DeepLinkRouter.swift:87`. |

### A3 Backend Parity

| Codebase | Source | Evidence |
|---|---|---|
| `default` | `functions` | `firebase.json:19-33` |
| `v2triggers` | `functions/v2triggers` | `firebase.json:34-45` |
| `creator` | `Backend/functions` | `firebase.json:46-59` |
| Non-deployed mirror | `AMENAPP/Backend/functions/src` | Not referenced by `firebase.json`. |

| Callable / Area | Gap | Evidence |
|---|---|---|
| `submitChurchVerificationRequest` | Client calls deployed stub. | Client `AMENAPP/ChurchTrustSafetyService.swift:86`; deployed stub `Backend/functions/src/church/controllers/churchTrustCallables.ts:10`; mirror real function `AMENAPP/Backend/functions/src/church/controllers/churchTrustCallables.ts:18`. |
| `submitChurchProfileUpdate` | Client calls deployed stub. | Client `AMENAPP/ChurchTrustSafetyService.swift:98`; deployed stub `Backend/functions/src/church/controllers/churchTrustCallables.ts:11`; mirror real function `AMENAPP/Backend/functions/src/church/controllers/churchTrustCallables.ts:49`. |
| `generateGroundedChurchAnswer` | Client calls deployed stub. | Client `AMENAPP/BereanChurchGroundingService.swift:13`; deployed stub `Backend/functions/src/church/controllers/churchTrustCallables.ts:14`; mirror real function `AMENAPP/Backend/functions/src/church/controllers/churchTrustCallables.ts:136`. |
| `processChurchNoteImageOCR` / video / PDF | Missing Auth/App Check/rate evidence. | Client `ChurchNotesMediaProcessingService.swift:473`, `:478`, `:483`; backend `functions/churchNotesMediaPipeline.js:488`, `:532`, `:593`. |
| Secret handling | Env/config instead of Secret Manager. | `Backend/functions/src/ambient/summarizeAmbientContext.ts:13`, `:33`; `Backend/functions/src/generateLiveKitToken.ts:39-49`; `Backend/functions/src/livingEntries/livingEntryAI.ts:500`, `:523`; `Backend/functions/src/covenant/stripeCovenantWebhook.ts:245-246`. |

### A4 Rules & Data Security

| Bucket | Count / Status | Evidence |
|---|---|---|
| Static Firestore write targets | 749 | Auditor command output. |
| Explicit rule-covered write targets | 89 | Examples: `AMENAPP/firestore.deploy.rules:311`, `:482`, `:1115`, `:1338`, `:2225`. |
| Missing explicit rule match | 660 | Examples: `AMENAPP/AIBibleStudyExtensions.swift:74`, `AMENAPP/AIIntelligence/BereanRealtimeServices.swift:77`, `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift:241`. |
| Deny-by-default | Present | `AMENAPP/firestore.deploy.rules:2599-2600`. |
| Raw phone leak | Confirmed | `AMENAPP/PhoneVerificationService.swift:57`, `:147-148`; `AMENAPP/AuthenticationViewModel.swift:1512`; `AMENAPP/firestore.deploy.rules:240-243`. |
| Full payload/object logging | Confirmed risk | `AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts:774`; `Backend/functions/src/discover/discoverTelemetry.ts:4`. |

### A5 Flags & Config

| Surface | Finding | Evidence |
|---|---|---|
| Posting moderation | `textModerationEnabled` can fail open after absent RC. | `AMENAPP/CommunicationOSRemoteConfigBridge.swift:15`, `:62`; `AMENAPP/AMENFeatureFlags.swift:2012`; `AMENAPP/PostingOSFeatureFlags.swift:8`; `AMENAPP/AIIntelligence/AmenSafetyModerationProvider.swift:168`. |
| Church Notes media | Defaults on despite comment saying unapproved surfaces stay off. | `AMENAPP/AMENFeatureFlags.swift:158`, `:159`, `:954`; `AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteSemanticEditorView.swift:894`. |
| RemoteKillSwitch | Partial consumers only. | `AMENAPP/RemoteKillSwitch.swift:25`; `AMENAPP/ContentView.swift:612`, `:628`. |
| Translation | Split defaults. | `AMENAPP/AMENFeatureFlags.swift:130`; `AMENAPP/TranslationFeatureFlags.swift:33`; `AMENAPP/PostCard.swift:1835`; `AMENAPP/MeaningAwareTranslationService.swift:69`. |
| Flag inventory | 489 properties; 235 zero runtime refs; 161 low refs. | Auditor static scanner output. |

### A6 Tests & Verification Debt

| Finding | Evidence |
|---|---|
| Xcode test plan is broad and enabled. | `GetTestList`: `1862 tests (1862 enabled, 0 disabled)`. |
| No JS/TS `__tests__` files found in Xcode project tree. | `XcodeGlob **/__tests__/**/*.{ts,js}` returned `0`. |
| Colocated backend `.test.ts` files are suspect under stated Jest constraint. | `AMENAPP/AMENAPP/Backend/functions/src/securityPosture.test.ts`; `safetyOSReactionEngine.test.ts`; `berean.rateLimit.test.ts`; environment fact says Jest only runs `__tests__/`. |
| Package-local Jest config appears broader, but audit environment says current Jest only runs `__tests__/`. | `AMENAPP/Backend/functions/package.json:39-41` includes `**/__tests__/**/*.test.ts` and `**/*.test.ts`; this needs command-level reconciliation before relying on colocated tests. |
| No named executing test evidence for several P0s. | No named test in `GetTestList` for raw phone logging/storage, unobserved Connect report/DM notifications, deployed church-trust stub parity, or absent-RC moderation fail-open. |

### A7 Privacy, Consent & Safety

| Surface | Status | Evidence |
|---|---|---|
| Voice navigation | Opt-in and on-device recognition present. | `AMENAPP/AMENAPP/AMENAPP/Accessibility/AIL/Interaction/AILVoiceNavigationController.swift:8-16`, `:86-95`, `:154-157`. |
| OCR camera | Preflight gap. | `AMENAPP/AMENAPP/AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNotesPhotoOCRCaptureView.swift:130-132`, `:264-267`. |
| Crisis keyword detector | Empty config/no in-repo configurator. | `AMENAPP/AIIntelligence/AmenSmartContextDetectionEngine.swift:13-16`, `:177`, `:206-210`, `:313`. |
| Prayer-room / AI text payloads | Raw sensitive text sent to callables; retention contract not evidenced. | `AMENAPP/AIIntelligence/BereanRealtimeServices.swift:100`, `:150`; `AMENAPP/AIIntelligence/BereanSmartNotesView.swift:268`; `AMENAPP/AMENAPP/AmbientOS/AmbientOSSurfaceView.swift:135`. |
| Streak/personalization mechanics | Faith engagement streak included in AI/personalization context. | `AMENAPP/AIIntelligence/BereanContextCoordinator.swift:133-136`; `AMENAPP/AIIntelligence/DailyDigestService.swift:192-195`. |

### A8 UX Integrity & Platform

| Finding | Evidence |
|---|---|
| iOS deployment target is 17.0 while Liquid Glass calls are mixed raw/shimmed/guarded. | `GetTargetBuildSettings AMENAPP`: `IPHONEOS_DEPLOYMENT_TARGET=17.0`; raw calls in `AmenContextBanners.swift:36`, `:87`, `:146`, `:211`; custom shim in `GlassEffectModifiers.swift:38-46`; guarded wrapper in `LiquidGlassModifiers.swift:273-291`. |
| Duplicate “ 2” artifact remains. | `XcodeGlob **/* 2*` returned `AMENAPP/AMENAPP/ContextStore/RUNLOG 2.md`. |
| Accessibility/reduce-motion coverage is uneven but present on several AI surfaces. | Examples: `AMENAPP/AIIntelligence/BereanFloatingActionTray.swift:8-9`, `:46`, `:50-51`; `AMENAPP/AIIntelligence/BereanLiveTranslationBar.swift:21-22`, `:66-68`; `AMENAPP/AIIntelligence/BereanPrayerRoomView.swift:18-19`, `:250`. |

## Notes

- No build or test run was performed; this was a read-only evidence audit except for `GAP_BOARD.md` and swarm registration in `AGENT_LANES.md`.
- Auditor 6 did not return before report generation; the test section uses Xcode MCP `GetTestList` plus local project glob evidence.

## Fix Wave Closure — 2026-06-11

| Row | Gap | Evidence | Severity | Owner/Lane | Fix Size | Status |
|---|---|---|---|---|---|---|
| FW-01 | Report-user control posted an unobserved notification. | `AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift` now calls `AmenSafetyReportService.shared.submitReport(...)`; `XcodeRefreshCodeIssuesInFile` returned no issues for the Xcode path. | P0 | Connect / Safety | M | CLOSED-WITH-PROOF |
| FW-02 | Profile Pray/Message actions posted unobserved notifications. | `AMENAPP/AMENAPP/ConnectSpaces/AmenConnectProfileView.swift` now routes Pray via `DeepLinkRouter.shared.navigate(to: .prayer(...))` and Message via `.chat(...)`; `DeepLinkRouter.swift` and `ContentView.swift` now map message routes to tab 2. | P0 | Connect / Navigation | M | CLOSED-WITH-PROOF |
| FW-03 | Known unobserved NotificationCenter actions remained fleet-wide. | `XcodeGrep` for `AmenOpenDMComposer|AmenLiveChatReply|AmenLiveAcknowledge|AmenOpenVideoPlayer|AmenOpenContactPicker|amenPrayForUser|amenOpenDM|amenReportUser` returned 0 matches after direct routing/local handlers were added. | P0 | Cross-app Wiring | M | CLOSED-WITH-PROOF |
| FW-04 | Raw phone numbers were logged client-side. | `AMENAPP/PhoneVerificationService.swift` logs only `last4`; `AMENAPP/AuthenticationViewModel.swift` logs only `last4`; grep for old `Sending verification code to:` / `Verifying code:` strings returned no app matches. | P0 | Privacy / Auth | S | CLOSED-WITH-PROOF |
| FW-05 | Raw phone number was written to `/users`, and rules did not block it. | `/users` writes now set `phoneHash` + `phoneLast4` and delete `phoneNumber` in `AuthenticationViewModel.swift` and `PhoneVerificationService.swift`; `DiscoveryService.swift` and `SignInView.swift` query `phoneHash`; `AMENAPP/firestore.deploy.rules:240-243` includes `phoneNumber` in `hasRawPII()`. | P0 | Privacy / Rules | M | CLOSED-WITH-PROOF |
| FW-06 | `textModerationEnabled` could fail open when absent from Remote Config. | `AMENAPP/AMENFeatureFlags.swift:823-824` adds camelCase moderation defaults ON, and related CommunicationOS safety flags default ON. `XcodeRefreshCodeIssuesInFile` returned no issues for `AMENFeatureFlags.swift`. | P0 | Flags / Safety | M | CLOSED-WITH-PROOF |
| FW-07 | Crisis keyword detector shipped empty. | `AMENAPP/AIIntelligence/AmenSmartContextDetectionEngine.swift` now has `defaultCrisisKeywords` and resets empty runtime config to that baseline; `AMENAPPTests/ActionIntelligenceDetectorTests.swift` adds `smartContextDetectorHasCrisisBaseline`. | P0 | Privacy / Safety | M | CLOSED-WITH-PROOF |
| FW-08 | Safe Zone used the Apple Park placeholder coordinate. | Worker changed `AMENAPP/AMENAPP/CameraOS/Safety/SafeZoneService.swift`; proof: `XcodeRefreshCodeIssuesInFile` passed and grep for `37.3318`, `-122.0312`, `Apple Park`, `placeholder` returned no matches in the file. | P1 | CameraOS Safety | M | CLOSED-WITH-PROOF |
| FW-09 | Server logging emitted full payloads. | Worker changed `AMENAPP/AMENAPP/CloudFunction_NotificationRoutingPipeline.ts` and `Backend/functions/src/discover/discoverTelemetry.ts`; `npm test -- --runTestsByPath src/discover/discoverTelemetry.test.ts --runInBand` passed. | P1 | Backend / Privacy | M | CLOSED-WITH-PROOF |
| FW-10 | Church trust callables deployed as stubs. | Worker added `Backend/functions/src/church/controllers/churchTrustCallables.ts`, exports in `Backend/functions/src/index.ts`, and test `churchTrustCallables.test.ts`; `npm run build` and focused Jest passed after integration. | P1 | Backend Parity | L | CLOSED-WITH-PROOF |
| FW-11 | Church Notes media callables lacked standard callable guards. | Worker added App Check and per-user rate-limit evidence in `functions/churchNotesMediaPipeline.js`; `npx jest --testMatch '**/test/churchNotesMediaPipeline.test.js' --runInBand` passed. | P1 | Backend / Church Notes | L | CLOSED-WITH-PROOF |
| FW-12 | Church Notes media flags had default/comment and alias kill-switch gaps. | Worker added `AMENAPPTests/ChurchNotesMediaIntelligenceTests.swift`; source already had default-off media gates and alias non-resurrection in `AMENAPP/AMENFeatureFlags.swift`; worker `git diff --check` passed. | P1 | Flags / Church Notes | M | CLOSED-WITH-PROOF |
| FW-13 | Provider/payment secrets used env/config instead of Secret Manager. | Added `defineSecret` and function `secrets` options in `Backend/functions/src/ambient/summarizeAmbientContext.ts`, `generateLiveKitToken.ts`, `livingEntries/*`, `covenant/*`, `onPostCreated.ts`, `deleteAlgoliaUser.ts`, and `algoliaSync.ts`; `npm run build` in `Backend/functions` passed. Human must set `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_SERVER_URL`, `STRIPE_SECRET_KEY`, `STRIPE_COVENANT_WEBHOOK_SECRET`, `ALGOLIA_ADMIN_KEY`. | P1 | Backend / Secrets | M | CLOSED-WITH-PROOF |

### Fix Wave Verification

| Check | Result |
|---|---|
| Dead notification grep | 0 matches for the banned profile/live/contact/video notification names. |
| Swift live diagnostics | No issues for edited Connect profile, PhoneVerificationService, DiscoveryService, SignInView, crisis detector, flag defaults, zero-observer replacement files; `AuthenticationViewModel.swift` only retains unrelated pre-existing weak-capture warnings at lines 2034 and 2044. |
| Backend build | `npm run build` in `Backend/functions` passed after the Secret Manager migration. |
| Backend focused tests | `Backend/functions`: discover telemetry + church trust callable tests passed, 4 tests total. |
| Church Notes callable tests | `functions`: church notes media pipeline guard tests passed, 3 tests total. |
| Xcode full build/tests | Blocked by Xcode dependency graph/CoreSimulator errors reported by worker lanes; fast diagnostics were used for edited Swift files. |
