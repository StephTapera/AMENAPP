# AMEN — Full-App Gap Board

**Run:** 8-auditor read-only swarm (wf_4ee05706-9d5), 2026-06-10 · **Auditors:** A1 Stubs · A2 Wiring · A3 Backend · A4 Rules · A5 Flags · A6 Tests · A7 Privacy · A8 UX · **Findings:** 86 (11 P0 · 50 P1 · 25 P2) · **Method:** Grep/Glob/Read only; every row carries file:line or command-output proof. Nothing was edited, fixed, or deployed.

> **Scope discipline:** This board is the audit's single permitted write. Fixes are dispatched FROM here by owners after human review — no auditor touched product code. FirebaseAI/FirebaseAILogic unlink was NOT diagnosed (per environment facts).

> **⚠️ ACTIVE-SWARMS collision note:** `AGENT_LANES.md` now carries an ACTIVE SWARMS registry listing a row `Gap Audit | (prior session) | — | —` with empty branch/status. This run is read-only and already complete; it produced **no destructive writes** and cannot collide with a prior audit. Flagging for the human per the registry rule rather than discarding completed evidence.

---

## ❗ P0 LIST (security / privacy / safety / crash — verbatim, read first)

| # | P0 gap | Evidence | Owner / lane | Fix |
|---|---|---|---|---|
| P0-1 | **Every DM is denied by deployed rules — field-name mismatch.** Client writes/reads `conversations` with `participantIds` (195 refs); `firestore.rules` gates conversations + messages entirely on `participantUids`, which is never populated → `uid in []` → all conversation create/read/list + message read/create DENIED. User taps Send / opens Messages → permission-denied. | `firestore.rules:1042,1049,1061,1072-1073,1081` (`participantUids`); `MessagingImplementation.swift:265` writes `participantIds`; `firestore.indexes.json:300` also indexes `participantIds` (rules disagree with indexes) | Messaging / Trust&Safety (rules C5 §2r) | S |
| P0-2 | **Plaintext phone numbers (Tier-P PII) written to Cloud Logging + used as Firestore doc IDs.** Full E.164 numbers logged in 6 statements and used as document paths — retained, broadly readable, PII in the path. | `functions/phoneAuthRateLimit.js:60,84,164,231,252,305` (`console.warn(... ${phoneNumber} ...)`); PII-as-doc-id `:48,236,295` (`.doc(phoneNumber)`) | Auth/Security lane | S |
| P0-3 | **COPPA minor gate is DEAD — rules check tier strings the system never emits.** `firestore.rules isMinor()` keys on `ageTier ∈ ['teen','under_minimum']`; the only producer (`computeAgeTier`) emits `blocked/tierB/tierC/tierD`. So `isMinor()`/`isUnderMinimum()` are always false → a 13-year-old gets full adult Firestore access on every gate (public-post confirm, prayer privacy, external discover, space church-verify, job listings, actionIntents). | `firestore.rules:85-92` vs `functions/authenticationHelpers.js:886-893`; `Backend/functions/src/syncAgeTierClaim.ts:38`; note `isMinorAccount()` at `firestore.rules:196` correctly lists tierB/tierC — proving the value set is known | age-gating lane (rules + functions auth) | S |
| P0-4 | **iOS DM COPPA gate also dead via same mismatch.** Client blocks minor DMs only when `ageTier == "under_minimum" || "minor"` — neither value is ever produced → minors can initiate DMs client-side; server fallback dead per P0-3. | `AMENSecureMessagingService.swift:400-406` | messaging lane | S |
| P0-5 | **Default-on background location + motion + calendar with no consent gate.** `ChurchProximityEngine` sets `allowsBackgroundLocationUpdates=true`, auto-escalates to Always auth the instant a screen appears, and auto-starts CoreMotion + EKEventStore calendar correlation. Trigger is merely viewing the Get Ready screen — no opt-in precondition. QuietMode sheet exists but is not required. | `ChurchProximityEngine.swift:224,234-235,164-165`; `GetReadyViewModel.swift:773-777,943` (onAppear → startMonitoring, no consent guard) | Get Ready / Quiet Mode lane | M |
| P0-6 | **Auto-promotion of unverified users to adult.** `AgeAssuranceService.migrateExistingUserToAdult` promotes any user with a missing age doc to adult on launch — synthetic DOB 25y ago, writes `ageTier:'tierD'`, zero verification. Server write is correctly rejected by `ageTierUnchanged()`, but the in-memory tier is still set to `.adult`, unlocking client-side adult gating for the session (client/server disagreement). | `AgeAssuranceService.swift:60-65,128-169`; `firestore.rules:303-307` (blocks the write) | age-assurance lane | M |
| P0-7 | **Emergency kill-switch system is decorative.** `RemoteKillSwitch` computes `feed/berean/messaging/createPost/search/notifications/maintenance` + the H-33 Berean SLO Firestore auto-disable, but the only property read anywhere is `isAppVersionValid`. Staff flipping `kill_berean_enabled=false` or the SLO CF writing `status:degraded` changes nothing — features stay fully live. Claims an emergency shutoff that does not exist. | `RemoteKillSwitch.swift:25-33,91-95`; only consumers `AMENAPPApp.swift:54,273` (version check only) | RemoteKillSwitch / AMENAPPApp | M |
| P0-8 | **Backend application-logic jest suite is RED and run by no CI.** 31/58 suites fail, 261/907 tests fail (project's own VERIFICATION_SUITE.md). `ios-ci.yml` only runs `npm test` in `functions/` (discussion-only); `ci.yml` lint-functions does an acorn syntax-parse, no jest; no workflow runs `Backend/functions`. 261 failing tests invisible; "verified" claims fail their own suites. | `VERIFICATION_SUITE.md:77-99`; `ci.yml:88-106`; `ios-ci.yml:101-107` | Backend (Covenant/ChurchNotes/Messaging/Media/Security) | L |
| P0-9 | **Firestore security rules are exercised by NO CI job.** `Backend/rules-tests` is the only emulator rules suite; no workflow references `rules-tests`/`emulators:exec`/`firebase emulators`. DM minor-safety, noteShare visibility, account-lifecycle rule regressions can merge with zero gating. | `Backend/rules-tests/package.json`; grep `.github/workflows/` → no matches | Backend/Security CI | M |
| P0-10 | **Sensitive collections have ZERO emulator rules coverage.** `crisisEscalations, userSafetyRecords, age_verification_events, connectorTokens, contextFacets/Snapshots, aiReports, humanReviewQueue, moderationQueue, banAppeals, scheduledActions, prayerRequests, user_trust` all have rule blocks but no test references any — crisis/COPPA/moderation/OAuth-token paths unverified (20 suites cover ~127 collections). | `firestore.rules:1294,1332,2374,2397`; `grep Backend/rules-tests/` → 0 files each | Backend/Security | L |
| P0-11 | **COPPA age-tier unit test is dormant AND tests a forked copy.** `functions/test/ageTier.test.js` is never matched (`testMatch=['**/src/discussion/**/*.test.ts']`), inlines a private `computeAgeTier` copy instead of importing production, and only asserts `blocked/tierB/tierC` — it could never catch the dead-gate mismatch (P0-3). The COPPA "verification" is a dead surface. *(A6 rated P0 / A7 rated P1; re-verified: the dead gate is the P0 violation, the dormant forked test is the verification debt that hid it.)* | `functions/package.json` testMatch; `functions/test/ageTier.test.js:1-15` | Auth/Safety + functions CI lane | S |

**P0 theme:** two independent COPPA/minor failures (rules tier-strings P0-3/4, auto-adult P0-6), a total DM outage (P0-1), a privacy leak (P0-2), a fake emergency-stop (P0-7), an unconsented background-sensing default (P0-5), and a verification vacuum (P0-8/9/10/11) where the suites that would have caught all of the above never run.

---

## Severity rollup

| Auditor | P0 | P1 | P2 | Total |
|---|---|---|---|---|
| A1 Stubs & dead surfaces | 0 | 11 | 2 | 13 |
| A2 Wiring & reachability | 0 | 6 | 2 | 8 |
| A3 Backend parity | 0 | 12 | 1 | 13 |
| A4 Rules & data security | 2 | 7 | 2 | 11 |
| A5 Flags & config | 1 | 9 | 4 | 14 |
| A6 Tests & verification debt | 4 | 9 | 6 | 19 |
| A7 Privacy, consent & safety | 4 | 2 | 2 | 8 |
| A8 UX integrity & platform | 0 | 2 | 4 | 6 |
| **Deduped board total** | **11** | **50** | **25** | **86** |

---

## 🔒 SAFETY GATES THAT MUST STAY ON (do NOT blanket-flip — from A5)

Any "turn flags on/off" sweep must exclude these. Flipping them OFF disables safety:

`aegis_pre_post_review_enabled`, `dm_risk_firewall_enabled`, `suspicious_relationship_detector_enabled`, `trusted_contact_escalation_enabled`, `theological_guardrails_enabled`, `ai_media_disclosure_enabled`, `claim_source_requirement_enabled`, `mercy_mode_replies_enabled`, `dogpile_detection_enabled`, `media_generated_metadata_approval_required`, `per_media_caption_moderation_enabled`, `voice_comment_transcript_required`, `amen_ai_usage_labels_required`, `ai_usage_label_pill_enabled`, `berean_theology_boundary_enabled`, `berean_entitlement_enforcement_enabled`.

**Inverted gate (true = BLOCK):** `church_notes_processing_kill_switch` — leave at its safe value; do not naively set true with the rest.

---

## P1 — feature lies to the user (50)

### A1 · Stubs & dead surfaces
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| Discover tab fabricates content in RELEASE — empty API key forces mock YouTube/news fallback, NOT DEBUG-gated; users always see fake "Sunday Sermon" items | `AMENDiscoveryView.swift:2478,2484,2490,2502,2505-2510,2517,2521-2540`; `ContentView.swift:634` | Discover / AMEN FLOW | M |
| Tapping any post in a Covenant → dead "Coming soon" placeholder | `AmenCovenantViewModel.swift:146-148,168-184` | Covenant / Communities | M |
| @username and #hashtag nav destinations render only "coming soon" text — every mention/hashtag tap dead-ends | `ProfileView.swift:6556-6557,6741,6771` | Profile / Social Graph | M |
| BereanDebateView "enabled" content is fake — static title + one-line description, no input/generation/output | `BereanDebateView.swift:25-36`; `BereanOSHubView.swift:134` | Berean OS | M |
| BereanPerspectiveView "enabled" content is fake — static description only | `BereanPerspectiveView.swift:25-36`; `BereanOSHubView.swift:126` | Berean OS | M |
| IntegrationOS advertises Transport + Broadcast tiles → bare `Text("Transport")`/`Text("Messaging")` placeholders | `ExternalIntegrationView.swift:157,163` (desc :71-78) | Integration OS | M |
| Studio "Resume" button only pops a Coming-Soon alert | `AmenStudioResourcesView.swift:260-266` | Studio | S |
| Covenant "Settings" + Moderation "Edit Guidelines" are dead Coming-Soon alert buttons | `AmenCovenantManageView.swift:81-85`; `AmenCovenantModerationView.swift:65-69` | Covenant / Communities | S |
| Messages video-call affordance only shows "Video Calls Coming Soon" alert | `LiquidGlassMessagesView.swift:136-140` | Messaging / CommunicationOS | S |
| Giving "Browse More Nonprofits" button only sets showComingSoon | `GivingNonprofitsSection.swift:323-324,343` | Giving | S |
| `DiscoverFeedService.loadNews/loadVideos` return empty arrays in RELEASE (mock only under DEBUG) | `DiscoverFeedService.swift:157-174` | Discover / AMEN FLOW | M |

### A2 · Wiring & reachability
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| **Two-router split:** `DeepLinkRouter.activeRoute`/`selectedTab` have ZERO consumers — every `DeepLinkRouter.navigate(to:)` mutates dead state; visible nav is driven only by `NotificationDeepLinkRouter` | grep `router.activeRoute`/`$selectedTab` → none; `DeepLinkRouter.swift:208,211-244`; `NotificationDeepLinkRouter.swift:584,699-701` | DeepLinkRouter / nav core | M |
| Amen Pulse card action pills navigate nowhere — `PulseActionRouter` → dead `DeepLinkRouter.navigate`; only http(s) cards work (contradicts commit 8dcc9264) | `AmenPulseSurfaceView.swift:379`; `PulseActionRouter.swift:45-48`; `DeepLinkRouter.swift:211-244` | claude — Pulse routing | M |
| `amen://space/{id}` routes nowhere — working router has no `space` case → defaults to Notifications tab; handoff never done | `NotificationDeepLinkRouter.swift:444-552`; grep `AmenConnectSpacesHubView` → none; `DeepLinkRouter.swift:239` | Spaces lane | M |
| `amen://event/{id}` routes nowhere — no `event` case; dead router marks INTERIM; handoff never done | `NotificationDeepLinkRouter.swift:444-552`; `DeepLinkRouter.swift:240-243`; grep `ResourcesView` → none | Church-surface lane | M |
| `AmenConnectView` orphaned — full 14-room Connect hub never instantiated | grep `AmenConnectView()` → only internal subviews; `AmenConnectView.swift:24` | ConnectSpaces / Connect lane | M |
| Spaces (tab 6) unreachable from tab bar AND from any working deep link — discoverability dead end for a paid surface | `AMENTabBar.swift:105`; only entries `AmenDiscoveryRailsView.swift:116,119`, `SabbathModeRouting.swift:140` | Spaces lane / nav core | M |

### A3 · Backend parity (client calls with no live backend)
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| **Safety callables have NO backend** — `evaluateDmRisk`, `reportDmAbuse`, `contentSafetyScreen`, `analyzeRelationshipRisk` throw NOT_FOUND; user believes a safety check ran | `DmRiskFirewallService.swift:38,61`; `SafetyServiceImpl.swift:79`; `SuspiciousRelationshipDetectorService.swift:42`; backend grep → none | Safety OS / DM firewall | M |
| `assessDogpileRisk` has no backend — pile-on gate inert | `DogpileDetectionService.swift:38` | Safety OS | S |
| `validateTheologicalContent` has no backend — server guardrail never runs | `TheologicalGuardrailsService.swift:38` | Berean/Guardrails | S |
| Studio AI callables defined but exported from no index → dormant: `studioGenerateContent`, `generateStudioImage`, `exportToPDF`, `studioJournalPrompt` | `amenStudioAI.js:111,169`; `studioImageGeneration.js:35`; `studioExport.js:22`; not in any index | Studio lane | S |
| `synapticCreate` defined, exported nowhere → dormant | `synapticFunctions.js:111`; `SynapticStudioView.swift:197` | Studio/Synaptic | S |
| `vibeMatch`/`digestBrain`/`spiritGraph` not exported → dormant (clients still call live) | `aiPromptFeatures.js:55,100,150`; `PeopleDiscoveryView`/`ProfileView`/`SpiritGraphModifier.swift:97` | AI prompt-features | S |
| `creatorOSGenerate` has no backend | `CreatorOSComposer.swift:256` | CreatorOS | S |
| Berean voice `bereanVoiceProxy`+`ttsProxy` have no backend (whisperProxy exists) | `BereanVoiceViewModel.swift:308,364` | Berean voice | M |
| `contentRouteSuggest` has no backend (`routeContentAction` is a different contract) | `ContentRouterImpl.swift:114` | RouterOS | S |
| Intelligence Seam `resolveSpaceTitle`/`searchCrossSources`/`searchKnowledgeGraph`/`bereanQuestion` have no backend | `AmenIntelligenceSeamService.swift:29,77,96,123`; `AmenSpacesHeroCardSection.swift` | ConnectSpaces / Intelligence Seam | M |
| Covenant `createCovenantMessage/Post`, `rsvpCovenantEvent`, `deleteCovenantMessage` no backend; UniversalLink callables only in stale duplicate tree; `computeDiscussionHealth` missing (`analyzeDiscussionHealth` is real) | `AmenCovenant*View.swift`; `AmenUniversalLinkIntelligenceService.swift:24,39`; `SmartEngagementSignalService.swift` | Covenant + smartAttachments | M |
| Name mismatch: client calls `processGiving`; backend only has `processGivingCharge` → payment path silently fails | `GivingInAppSheet.swift:418`; `Backend/.../processGivingCharge.ts:40` | Giving / payments | S |

### A4 · Rules & data security
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| `whisperUsage` has no rule → catch-all denies; voice quota silently never persists (`try?` swallows) | `WhisperVoiceService.swift:370`; rules grep → 0 | WhisperVoiceService / rules | S |
| `helixNodes` has no rule → destructive delete button rejected silently, node remains | `HelixNodeDetailSheets.swift:225,344` | HelixNode / rules | S |
| `notificationBatches`/`scheduledBatches`/`userNotificationPreferences` no rules → entire client batching feature dead | `SmartNotificationService.swift:154,196-198,217,230` | SmartNotificationService / rules | S |
| `users/{uid}/creatorScenes` excluded from CI-6 wildcard allow-list → Creator scene editing denied | `CreatorSceneService.swift:31-49`; `firestore.rules:2433-2437` | CreatorSceneService / rules | S |
| `users/{uid}/bereanMemory` read has no rule → memory UI permanently empty (writes go via callable) | `BereanMemoryService.swift:44-49` | BereanMemoryService / rules | S |
| Duplicate `/church_pulse/{churchId}` match — second block allows any signed-in user; OR-widening defeats the member gate (privacy regression) | `firestore.rules:1592` vs `:1654` | Living Intelligence / rules | S |
| birthYear + derived ageTier (minor-determining) logged to Cloud Logging | `authenticationHelpers.js:939`; `authHelpersV1.js:115` (+` 2.js:115`) | Age Assurance lane | S |

### A5 · Flags & config
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| `RemoteKillSwitch` never registers RC defaults → on a successful fetch with keys absent, all kill flags read false (fail-closed-by-absence); masked today only because nothing consumes them | `RemoteKillSwitch.swift:46-67,117-141` | RemoteKillSwitch | S |
| `socialSafetyOSEnabled`/`safetyOSEnabled` master switches gate nothing | `AMENFeatureFlags.swift:390,599,1685,1562`; grep → no consumers | Social Safety OS | M |
| `minorSafetyModeEnabled`/`sextortionPanicFlowEnabled`/`victimShieldEnabled` named safety flags have no consumer | `AMENFeatureFlags.swift:397,398,405,1692,1693,1700` | Social Safety OS | M |
| 14 wellbeing/transparency safety flags (thinkFirstGuard, algorithmTransparency, feedBoundary, etc.) defined/applied but no consumer | `AMENFeatureFlags.swift:391-415`; grep | Social Safety OS | L |
| CommunicationOS + PostingOS flags never receive RC — bridge `applyRemoteConfig` never called; flags pinned to ON default, can't be killed | `CommunicationOSRemoteConfigBridge.swift:12,52-57`; `PostingOSFeatureFlags.swift:8-10` | CommunicationOS / PostingOS | S |
| `SupportFeatureFlags` comment "default off / server-driven" but service hardwires `.phase1` (4 flags ON) | `SupportFeatureFlags.swift:6,47-49`; `FeatureFlagServicing.swift:16` | SupportIntelligence | M |
| `TranslationFeatureFlags` default contradicts comment — `gcpBackendEnabled` init false ("no CF deployed") but RC default `true` → routes to undeployed CF | `TranslationFeatureFlags.swift:26,83,99,136` | TranslationFeatureFlags | S |
| `CommunityOSFeatureFlags` header says "default false" but every flag defaults true (15 flags ON in prod) | `CommunityOSFeatureFlags.swift:5,37,78,101` | CommunityOS flags | S |
| Suggested-rail int RC keys read but unregistered → first fetch zeroes safe defaults (card limit 0 = rail empty) | `AMENFeatureFlags.swift:102-105,1431-1434` | Suggested Follows | S |

### A6 · Tests & verification debt
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| `ios-ci.yml` builds against `AMENAPP.xcworkspace` which does not exist → entire iOS build-and-test job is a no-op; 108-file XCTest suite never runs | `ios-ci.yml:25,54,59,69`; no `.xcworkspace` in repo | iOS CI | S |
| 15 UI-test files (AMENAPPUITests + " 2") belong to NO target — `AMENAPPUITests` appears 0× in pbxproj; every UI test is dead | `project.pbxproj` grep → 0; dirs exist with 15 files | iOS test infra | M |
| 11 `functions/` jest files dormant (testMatch = discussion-only), incl. shipped `connectorFetch` CF test | `functions/package.json`; `functions/{test,tests,intelligence/tests}` | Backend (functions) | M |
| `functions/v2triggers` codebase has empty package.json → zero runnable tests for Gen-2 triggers | `functions/v2triggers/package.json` | Backend (v2triggers) | M |
| 6 XCTest files inside the app-target synced folder compile into the app, never run as tests (3 also duplicated at root) | `project.pbxproj:497-503,535-543` | iOS test infra | S |
| "Aegis OS … 145 tests" claim has no Aegis-named test anywhere | MEMORY.md; grep `*Tests.swift`/`*.test.ts` → none | Aegis OS lane | M |
| "awaken 37 dormant suites" (7d6a534e) touched only `Backend/functions/package.json`; functions/ 11 remain dormant — framing misleads | `git show 7d6a534e`; `VERIFICATION_SUITE.md:106` | Backend (functions) | S |
| Whole 108-file iOS XCTest suite hosted by app target → cannot run while app build blocked; "X/X passing" unverifiable now | `project.pbxproj:1430-1433,1465` | iOS build/test | L |
| ConnectSpaces "5/7 PASS + 2 EXPECTED-RED" masks a `spaces/{spaceId}/files` rule that was never written → member file read/upload unverified | `VERIFICATION_SUITE.md:15,20-23` | ConnectSpaces/Spaces | S |

### A7 · Privacy & doctrine
| Gap | Evidence | Owner | Fix |
|---|---|---|---|
| **Visible streak mechanic** — Berean memory-verse card renders "🔥 N-day streak" + increments streakDay per completion; violates app-wide no-streaks doctrine (Pulse guilt-lint forbids `\bstreak\b`) | `BereanFormationCardViews.swift:441`; `BereanDailyFormationFeedView.swift:95-103` | Berean Daily Formation | S |
| COPPA test dormant + tests a forked inline copy (verification debt behind P0-3/4) | `functions/package.json`; `functions/test/ageTier.test.js:7-15` | functions test/CI lane | S |

---

## P2 — polish / coverage (25)

| Gap | Evidence | Auditor | Owner | Fix |
|---|---|---|---|---|
| `LiquidGlassMessagesView` orphaned + loads mock chats un-gated; dead code in binary | `LiquidGlassMessagesView.swift:134,331-338,1028` | A1 | Messaging | S |
| `TransformMatrix.config/supportedIntents/audienceCeiling` are `fatalError` Phase-0 stubs (no callers yet) | `Contracts/stubs/AmenTransform.swift:382,388,395` | A1 | Transform Engine | M |
| Two "Pulse" surfaces (AmenPulseView "Notifications" tab 4 vs AmenPulseSurfaceView tab 7) — wiring/label hazard | `ContentView.swift:664-666,690-706` | A2 | Pulse / Intelligence | S |
| `SmartShareSystem` emits `amen://post` via DeepLinkRouter whose own navigate is dead; only NotificationDeepLinkRouter rescues; space/event links would default-misroute | `SmartShareSystem.swift:239`; `DeepLinkRouter.swift:342-349` | A2 | nav core | S |
| Pervasive ` 2.js`/` 2.ts` shadow files re-declare same exports → deploy collision / non-deterministic parity | `v2entry 2.js:41-49`; `communityAI 2.ts`; `noteShare 2.ts` | A3 | Backend deploy hygiene | M |
| `firestore.indexes.json` indexes `participantIds` while rules gate `participantUids` — reconcile both files with P0-1 | `firestore.indexes.json:300`; `firestore.rules:1042` | A4 | Messaging | S |
| Three competing `firestore.indexes.json` (root deployed; Backend/ + AMENAPP/ stale) → index drift risk | `firebase.json:12`; Glob | A4 | Build/Infra | S |
| `allFlagKeys` advertises `smartThreadMiniSummaryEnabled`/`nvidiaSafetyProviderEnabled` with no backing property | `CommunicationOSRemoteConfigBridge.swift:73-74` | A5 | CommunicationOS flags | S |
| 7 RC keys applied with no registered default (community_os_enabled, ff_action_intelligence, 5 berean kill switches) — safe-by-absence, undocumented | `AMENFeatureFlags.swift:1681,1720-1724,1872` | A5 | AMENFeatureFlags | S |
| VertexAI reads `vertex_ai_project_id`/`vertex_ai_model_endpoint` with no default → empty config, no error surfaced | `VertexAIPersonalizationService.swift:77,82` | A5 | VertexAI Personalization | S |
| Translation per-surface flags (churchNotes/resourceDescription) hardcoded true, no kill switch | `TranslationFeatureFlags.swift:44-45,75-76,97-156` | A5 | TranslationFeatureFlags | S |
| Rules-suite run commands are bespoke manual NODE_PATH invocations; no single `npm test`; "fold step not done" | `VERIFICATION_SUITE.md:45-59` | A6 | Backend/Security CI | M |
| `aiPipeline.test 2.js` byte-identical dormant duplicate; ` 2` jest configs exist | `functions/test/aiPipeline.test*.js` | A6 | Backend (functions) | S |
| Only guaranteed iOS test is `XCTAssertTrue(true)` smoke → false-green risk if others silently drop | `XCTestSmokeDiscoveryTests.swift` | A6 | iOS test infra | S |
| `ci.yml` triggers only on main; feature/* branches get no CI → "verified on branch" has no CI corroboration | `ci.yml:3-7`; `ios-ci.yml:15-19` | A6 | CI | S |
| Committed compiled `Backend/functions/lib/__tests__` mirrors → coverage double-count / drift noise | `find __tests__`; testPathIgnorePatterns | A6 | Backend build hygiene | S |
| Always-location usage string doesn't disclose the motion+calendar fusion ChurchProximityEngine performs (App Store privacy gap, compounds P0-5) | `project.pbxproj:1697` vs `ChurchProximityEngine.swift:164-165` | A7 | Get Ready / Info.plist | S |
| CommunityWeeklyRecap shows 0-100 health score + red/green delta "pts this week" — velocity framing; doctrine review (aggregate, not per-user) | `CommunityWeeklyRecapView.swift:223-243` | A7 | Community Intelligence OS | S |
| Amen Pulse surface has no dark-mode adaptation — hardcoded light chrome; `colorScheme` declared but unused | `AmenPulseSurfaceView.swift:108,126,195,234,238` | A8 | Pulse | M |
| PulsePrefsView light-only, clashes with system Form chrome in dark mode | `PulsePrefsView.swift:35,134,137,149,213-221` | A8 | Pulse | S |
| Entire Pulse module ignores Dynamic Type — fixed `.font(.system(size:))`, never uses `systemScaled` | `AmenPulseSurfaceView.swift:191,194,233`; `PulseHeroCardView.swift:99-113` | A8 | Pulse | M |
| Misleading "iOS 26 native glass" comments where custom shim is used; branch keyed on `reduceTransparency` not `#available` | `BereanFloatingActionTray.swift:17,29,32`; `ONENavigationShell.swift:3,67` | A8 | DesignSystem/LiquidGlass | S |
| Two competing glass abstractions (always-on shim vs `#available(iOS 26)` real glass) → inconsistent rendering, no sanctioned primitive | `GlassEffectModifiers.swift:15,38`; `LiquidGlassModifiers.swift:276`; `AdaptiveGlassContainer.swift:40-46` | A8 | DesignSystem/LiquidGlass | M |
| Pulse hero per-press scale bounce not reduce-motion guarded (card morph is) | `PulseHeroCardView.swift:48,81-82` | A8 | Pulse | S |
| `gcpBackendEnabled` fragile RC default duplicate-listed (see A5 P1) — tracked above | — | A5 | — | — |

---

## Dedupe & conflict resolution

- **ageTier COPPA test dormancy** — reported by A6 (P0) and A7 (P1). Re-verified, not averaged: the **dead minor gate** (P0-3/P0-4) is the violation and stays P0; the **dormant forked test** (P0-11 / A7) is the verification debt that let it ship — kept as a distinct row, flagged P0 for visibility because it is the named "COPPA-compliance" verification that does not run.
- **`conversations` rules block** — A4's DM-denial (P0-1, `participantIds`/`participantUids`) and A7's minor-DM gate (P0-4, tier strings) sit in the **same rule + same client service**. Fix together in one rules/indexes/client pass or they will re-break each other.
- **RemoteKillSwitch** — A5 raised both "decorative" (P0-7) and "fail-closed-by-absence defaults" (P1). Same subsystem, two distinct defects; both kept.
- **` 2`-suffixed duplicates** — surfaced independently by A3 (backend exports), A6 (tests/configs), A8 (confirmed none in the iOS Swift build). Merged: duplicates are a backend deploy-hygiene problem only; iOS is clean.
- **ageTier/birthYear logging** — A4 (P1, birthYear) and A4 (P0, phone) are distinct PII fields; the phone leak is P0 (broader exposure + PII-in-path), birthYear is P1.

---

## Suggested fix-wave dispatch (from this board, after human review)

1. **Wave S-1 (P0, all size S, highest leverage):** P0-1 DM field, P0-3/P0-4 tier strings, P0-2 phone-log redaction, P0-11 test wiring. Four small diffs close a DM outage, both COPPA holes, and a PII leak.
2. **Wave S-2 (P0, M/L):** P0-5 consent gate, P0-6 auto-adult, P0-7 kill-switch consumers, P0-8/9/10 CI + emulator coverage.
3. **Wave P1-backend:** A3 missing-callable cluster (safety callables first), A4 missing rules cluster.
4. **Wave P1-flags:** A5 dead safety flags + bridge wiring + default/comment contradictions.
5. **Wave P1-nav:** A2 two-router consolidation (unblocks Pulse cards, Spaces/event deep links).
6. **Wave P2:** Pulse dark-mode/Dynamic-Type, glass-primitive consolidation, ` 2` duplicate sweep, doctrine reviews.

*Owners pull their rows; no fix lands without the human signing off on the P0 list first.*
