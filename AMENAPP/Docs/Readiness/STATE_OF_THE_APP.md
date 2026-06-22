# State of the App — Release Train Snapshot

**Branch:** app-store-readiness-overnight
**HEAD SHA:** 4bb2ffdd9955f113f4b723fbc901743c7ab9af83
**Build:** HUMAN-PENDING (BIL stubs must be excluded by Steph first; duplicate pbxproj entries for AmenPrivacyEngine.swift, AmenAudienceSimulatorView.swift, ResourcesContentView.swift must be resolved before archive)

---

## Feature Status

| Feature | Module | Committed | Wired | Flag | Default | Train |
|---------|--------|-----------|-------|------|---------|-------|
| Onboarding V2 | Auth/Onboarding | ✅ YES | ✅ ContentView/AppDelegate | `ff_onboarding_v2` | true | IN-TRAIN |
| Smart Account Resume | Auth | ✅ YES | ✅ AppDelegate | `smart_account_resume_enabled` | true | IN-TRAIN |
| Feed Ranking V2 | Feed | ✅ YES | ✅ HomeView | `feed_ranking_v2_enabled` | true | IN-TRAIN |
| Anti-Doomscroll | Feed | ✅ YES | ✅ FeedSessionPacingService | `anti_doomscroll_enabled` | true | IN-TRAIN |
| Feed Session Pacing | Feed | ✅ YES | ✅ FeedSessionPacingService | `feed_session_pacing_enabled` | true | IN-TRAIN |
| Feed Reflection Prompts | Feed | ✅ YES | ✅ HomeView | `feed_reflection_prompts_enabled` | true | IN-TRAIN |
| Posts Liquid Glass | Feed/Posts | ✅ YES | ✅ PostCard | `posts_liquid_glass_enabled` | true | IN-TRAIN |
| Healthy Media Checkpoints | Media | ✅ YES | ✅ ImmersiveMediaSession | `healthy_media_checkpoints_enabled` | true | IN-TRAIN |
| Media Wellbeing Controls | Media | ✅ YES | ✅ MediaPlayerView | `media_wellbeing_controls_enabled` | true | IN-TRAIN |
| Late Night Pause | Media | ✅ YES | ✅ MediaSessionManager | `late_night_pause_enabled` | true | IN-TRAIN |
| Hide Vanity Metrics | Feed/Posts | ✅ YES | ✅ PostCard | `hide_vanity_metrics_default` | true | IN-TRAIN |
| Media Low Bandwidth Mode | Media | ✅ YES | ✅ MediaSessionManager | `media_low_bandwidth_mode_enabled` | true | IN-TRAIN |
| Profile V2 | Profile | ✅ YES | ✅ ProfileView | `profile_v2_enabled` | true | IN-TRAIN |
| Selah Pause | Selah | ✅ YES | ✅ SelahView | `selah_pause_enabled` | true | IN-TRAIN |
| Emotional Check-In | Selah | ✅ YES | ✅ SelahView | `emotional_check_in_enabled` | true | IN-TRAIN |
| Healthy Use Dashboard | Wellbeing | ✅ YES | ✅ Settings/Profile | `healthy_use_dashboard_enabled` | true | IN-TRAIN |
| Why Seeing This | Feed | ✅ YES | ✅ PostCard | `why_seeing_this_enabled` | true | IN-TRAIN |
| Find a Church | Discovery | ✅ YES | ✅ DiscoverView | `find_a_church_enabled` | true | IN-TRAIN |
| Smart Share Sheet | Composer | ✅ YES | ✅ CreatePostView | `smart_share_sheet_enabled` | true | IN-TRAIN |
| Music Attachment | Composer | ✅ YES | ✅ CreatePostView | `music_attachment_enabled` | true | IN-TRAIN |
| Smart Attachments | Composer | ✅ YES | ✅ CreatePostView | `smart_attachments_enabled` | true | IN-TRAIN |
| Translation Smart Pill | Composer/Feed | ✅ YES | ✅ PostCard | `translation_smart_pill_enabled` | true | IN-TRAIN |
| Connect Hub | Connect | ✅ YES | ✅ AmenConnectView | `connect_hub_enabled` | true | IN-TRAIN |
| Connect For You Menu | Connect | ✅ YES | ✅ AmenConnectView | `connect_you_menu_enabled` | true | IN-TRAIN |
| Messaging Liquid Glass | Messaging | ✅ YES | ✅ MessagingView | `messaging_liquid_glass_animations_enabled` | true | IN-TRAIN |
| Messaging Typing Indicator | Messaging | ✅ YES | ✅ MessagingView | `messaging_typing_indicator_enabled` | true | IN-TRAIN |
| Message Request Intelligence | Messaging/Safety | ✅ YES | ✅ MessagingView | `message_request_intelligence_enabled` | true | IN-TRAIN |
| Mutual Context Row | Connect | ✅ YES | ✅ AmenConnectProfileView | `mutual_context_row_enabled` | true | IN-TRAIN |
| Trust Explainer | Trust | ✅ YES | ✅ ProfileView | `trust_explainer_enabled` | true | IN-TRAIN |
| Moderation V2 | Safety | ✅ YES | ✅ Backend (moderatePost.js) | `moderation_v2_enabled` | true | IN-TRAIN |
| Image Moderation | Safety | ✅ YES | ✅ Backend | `image_moderation_enabled` | true | IN-TRAIN |
| DM Enhanced Scanning | Safety | ✅ YES | ✅ Backend | `dm_enhanced_scanning_enabled` | true | IN-TRAIN |
| Trust Scoring | Safety | ✅ YES | ✅ Backend | `trust_scoring_enabled` | true | IN-TRAIN |
| Social Safety OS | Safety | ✅ YES | ✅ Backend | `social_safety_os_enabled` | true | IN-TRAIN |
| Minor Safety Mode | Safety | ✅ YES | ✅ AmenChildSafetyService | `minor_safety_mode_enabled` | true | IN-TRAIN |
| DM Risk Firewall | Safety | ✅ YES | ✅ Backend | `dm_risk_firewall_enabled` | true | IN-TRAIN |
| Sextortion Panic Flow | Safety | ✅ YES | ✅ SafetyOSView | `sextortion_panic_flow_enabled` | true | IN-TRAIN |
| Dogpile Detection | Safety | ✅ YES | ✅ Backend | `dogpile_detection_enabled` | true | IN-TRAIN |
| Theological Guardrails | Safety/Berean | ✅ YES | ✅ BereanChatProxy | `theological_guardrails_enabled` | true | IN-TRAIN |
| Aegis Pre/Post Review | Safety | ✅ YES | ✅ CreatePostView | `aegis_pre_post_review_enabled` | true | IN-TRAIN |
| AI Usage Labels | Safety/AI | ✅ YES | ✅ PostCard | `amen_ai_usage_labels_required` | true | IN-TRAIN |
| AI Disclosure Pill | Safety/AI | ✅ YES | ✅ PostCard | `ai_usage_label_pill_enabled` | true | IN-TRAIN |
| Church Notes Intelligence | Church Notes | ✅ YES | ✅ ChurchNotesView | `church_notes_intelligence_enabled` | true | IN-TRAIN |
| Sermon Summary Generation | Church Notes | ✅ YES | ✅ ChurchNotesView | `sermon_summary_generation_enabled` | true | IN-TRAIN |
| Scripture Detection | Church Notes/Berean | ✅ YES | ✅ ChurchNotesView | `scripture_detection_enabled` | true | IN-TRAIN |
| Amen Daily Digest | Home | ✅ YES | ✅ HomeView | `amen_daily_digest_enabled` | true | IN-TRAIN |
| Amen Discover | Discovery | ✅ YES | ✅ DiscoverView | `amen_discover_enabled` | true | IN-TRAIN |
| Amen Discover Liquid Glass | Discovery | ✅ YES | ✅ DiscoverView | `amen_discover_liquid_glass_enabled` | true | IN-TRAIN |
| Selah Scripture Actions | Selah | ✅ YES | ✅ SelahView | `selah_scripture_actions_enabled` | true | IN-TRAIN |
| Church Study Companion | Church | ✅ YES | ✅ ChurchView | `church_study_companion_enabled` | true | IN-TRAIN |
| Selah Media OS | Selah | ✅ YES | ✅ SelahView | `selah_media_os_enabled` | true | IN-TRAIN |
| Adaptive Glass V2 | Design System | ✅ YES | ✅ HomeView/AdaptiveTopBar | `adaptive_glass_v2_enabled` | true | IN-TRAIN |
| Studio | Creator | ✅ YES | ✅ StudioView | `studio_enabled` | true | IN-TRAIN |
| Studio Monetization | Creator | ✅ YES | ✅ StudioView | `studio_monetization_enabled` | true | IN-TRAIN |
| Knowledge Graph | Intelligence | ✅ YES | ✅ Backend | `knowledge_graph_enabled` | true | IN-TRAIN |
| Mentorship | Community | ✅ YES | ✅ ProfileView | `mentorship_enabled` | true | IN-TRAIN |
| Trust Signals | Trust | ✅ YES | ✅ ProfileView/PostCard | `trust_signals_enabled` | true | IN-TRAIN |
| Suggested Follows Rail | Feed | ✅ YES | ✅ HomeView | `suggested_follows_enabled` | true | IN-TRAIN |
| Discussion Modes | Community | ✅ YES | ✅ DiscussionView | `discussion_modes_enabled` | true | IN-TRAIN |
| Discussion Health | Community | ✅ YES | ✅ DiscussionView | `discussion_health_enabled` | true | IN-TRAIN |
| Media Filter Pills | Media | ✅ YES | ✅ MediaBrowserView | `media_filter_pills_enabled` | true | IN-TRAIN |
| Media Detail View | Media | ✅ YES | ✅ MediaBrowserView | `media_detail_view_enabled` | true | IN-TRAIN |
| Connect Layout V2 (W1) | Connect | ✅ YES | ✅ AmenConnectView gate | `connect_layout_v2_enabled` | false | NEXT-TRAIN |
| Connect Polish V2 (W2) | Connect | ✅ YES | ✅ AmenConnectV2View | `connect_polish_v2_enabled` | false | NEXT-TRAIN |
| Connect Empty States (W3) | Connect | ✅ YES | ✅ AmenConnectV2View | `connect_empty_states_enabled` | false | NEXT-TRAIN |
| Connect Smart Berean (W4) | Connect | ✅ YES | ✅ ConnectSmartBereanBar | `connect_smart_berean_enabled` | false | NEXT-TRAIN |
| Connect Offline Queue (W5) | Connect | ✅ YES | ✅ ConnectOfflineQueue | `connect_offline_queue_enabled` | false | NEXT-TRAIN |
| Connect Discovery Engine | Connect/Discovery | ✅ YES | ✅ ConnectDiscoveryView | `connect_discovery_enabled` | false | NEXT-TRAIN |
| Selah Stories | Selah | ✅ YES | ❌ No active entry point | `selah_stories_enabled` | false | NEXT-TRAIN |
| Immersive Media Sessions | Media | ✅ YES | ❌ Flag-gated only | `immersive_media_sessions_enabled` | false | NEXT-TRAIN |
| Feed Intelligence | Feed | ✅ YES | ❌ Flag-gated only | `feed_intelligence_enabled` | false | NEXT-TRAIN |
| Action Intelligence | Composer | ✅ YES | ❌ Flag-gated only | `ff_action_intelligence` | false | NEXT-TRAIN |
| Berean Island | Berean | ✅ YES | ❌ Flag-gated only | `berean_island` | false | NEXT-TRAIN |
| Berean Agent Surface | Berean | ✅ YES | ❌ Flag-gated only | `berean_agent_surface` | false | NEXT-TRAIN |
| Berean RAG | Berean/AI | ✅ YES | ❌ Flag-gated only | `berean_rag_enabled` | false | NEXT-TRAIN |
| Berean Conversation Memory | Berean/AI | ✅ YES | ❌ Flag-gated only | `berean_conversation_memory_enabled` | false | NEXT-TRAIN |
| Berean Multilingual Layer | Berean/AI | ✅ YES | ❌ Flag-gated only | `bereanMultilingualLayer` | false | NEXT-TRAIN |
| Berean Safety Classifier | Berean/Safety | ✅ YES | ❌ Kill-switched off | `berean_safety_classifier_enabled` | false | NEXT-TRAIN |
| Church Notes Audio Capture | Church Notes | ✅ YES | ❌ Flag-gated only | `church_notes_audio_capture_enabled` | false | NEXT-TRAIN |
| Church Notes Photo OCR | Church Notes | ✅ YES | ❌ Flag-gated only | `church_notes_photo_ocr_enabled` | false | NEXT-TRAIN |
| Amen Pulse | Home | ✅ YES | ✅ ContentView tab 7 | `amen_pulse_enabled` | false | NEXT-TRAIN |
| Capabilities Core | Berean/AI | ✅ YES | ❌ Flag-gated only | `capabilities_core` | false | NEXT-TRAIN |
| Prayer OS Capability | Berean/AI | ✅ YES | ❌ Flag-gated only | `prayer_os` | false | NEXT-TRAIN |
| Scripture Intelligence | Berean/AI | ✅ YES | ❌ Flag-gated only | `scripture_intelligence` | false | NEXT-TRAIN |
| Ambient OS | Design System | ✅ YES | ❌ Flag-gated only | `ambient_os_enabled` | false | NEXT-TRAIN |
| Liquid Glass System (full) | Design System | ✅ YES | ❌ Flag-gated only | `liquid_glass_system_enabled` | false | NEXT-TRAIN |
| Community OS | Community | ✅ YES | ❌ Flag-gated only | `community_os_enabled` | false | NEXT-TRAIN |
| Conversation OS | Messaging | ✅ YES | ❌ Flag-gated only | `conversation_os_enabled` | false | NEXT-TRAIN |
| Context Intelligence OS | AI | ✅ YES | ❌ Contracts only; Wave 2 in progress | `context_system_enabled` | false | NEXT-TRAIN |
| NIS Detection Layer | AI | ✅ YES | ❌ Flag-gated only (true in DEBUG) | `nis_detection_layer` | false | NEXT-TRAIN |
| Accessibility Intelligence Layer | Accessibility | ✅ YES | ❌ Flag-gated only | `accessibility_intelligence_enabled` | false | NEXT-TRAIN |
| Camera OS | Camera | ✅ YES | ❌ Flag-gated only | `camera_os_enabled` | false | NEXT-TRAIN |
| Composer Adaptive Rail | Composer | ✅ YES | ❌ Flag-gated only | `composer_adaptive_rail` | false | NEXT-TRAIN |
| Live Activity Prayer | Composer | ✅ YES | ❌ Flag-gated only | `live_activity_prayer_request_enabled` | false | NEXT-TRAIN |
| Sanctuary Core | Messaging | ✅ YES | ❌ Flag-gated only | `sanctuary_core` | false | NEXT-TRAIN |
| Threshold (moderation) | Safety | ✅ YES | ✅ ThresholdView (static flag) | `threshold_enabled` | false | HUMAN-BLOCKER |
| NCMEC CyberTipline wire | Safety/Legal | ❌ STUB ONLY | ❌ Not wired | n/a | n/a | HUMAN-BLOCKER |
| Restore Purchases (IAP) | Monetization | ❌ NO | ❌ Missing from all paywall screens | n/a | n/a | HUMAN-BLOCKER |
| Stripe IAP Classification | Monetization | ❌ TBD | ❌ Awaiting legal decision | n/a | n/a | HUMAN-BLOCKER |
| App Store Connect Record | Submission | ❌ NO | ❌ APP_STORE_APP_ID = 0000000000 | n/a | n/a | HUMAN-BLOCKER |
| Privacy Policy Live URL | Legal | ❌ NO | ❌ Static text only | n/a | n/a | HUMAN-BLOCKER |
| Google Re-Auth on Delete | Auth | ❌ NO | ❌ Static text, no GIDSignIn flow | n/a | n/a | HUMAN-BLOCKER |
| 30-day Deletion Purge Job | Privacy | ❌ NO | ❌ No server purge job confirmed | n/a | n/a | HUMAN-BLOCKER |

---

## R1 Safety Status

| ID | Item | Status | Owner |
|----|------|--------|-------|
| R1-A1 | Minor guardian approval: fail-open → fail-closed in AmenChildSafetyService.guardianApprovalRequired | FIXED (SHA 847404f1) | Agent |
| R1-A2 | BTN-001: Spaces join/paywall bypass — entitlement gate added to SpacesViewModel.toggleJoin() | FIXED (SHA 229e288e) | Agent |
| R1-A3 | BTN-003: VisitConfirmationBanner double-submit — isConfirming guard + ProgressView added | FIXED (SHA fdc1b332) | Agent |
| R1-A4 | BTN-004: GivingImpactView PDF sheet no dismiss button — NavigationStack + Done toolbar added | FIXED (SHA 15b75d9f) | Agent |
| R1-A5 | ATT/Analytics: Analytics disabled before ATT prompt; enabled only on .authorized | FIXED (SHA 5c5922b6) | Agent |
| R1-A6 | SEC-006: ITSAppUsesNonExemptEncryption — confirmed CryptoKit-only; export compliance comment added | FIXED (SHA 139eda99) | Agent |
| R1-A7 | pbxproj duplicate symbols (AmenPrivacyEngine, AmenAudienceSimulatorView, ResourcesContentView) | ALREADY_FIXED — no duplicates found | Agent |
| R1-A8 | A11Y-003: LiquidGlass animations ignore Reduce Motion — @Environment reduceMotion guard added in 3 toolbar files | FIXED (SHA b9ce1e23) | Agent |
| C1 | CSAM: escalateChildSafety import crash on every user-filed report | FIXED (SHA b3ebad3f) — 6 call sites present in moderatePost.js | Agent |
| C2 | CSAM: image path had no legalHold or NCMEC escalation | FIXED (SHA dce7c6cb, d96ef1e5) — fileNCMECReport called 7× in moderatePost.js | Agent |
| C2b | CSAM: image-only DM vision gate absent | FIXED (SHA c615f06a) — IMAGE_CSAM_CATEGORIES_UGC present 3× in moderateUGC.js | Agent |
| C3 | CSAM: duplicate moderateContent export shadow | FIXED — only 1 export named exactly exports.moderateContent in functions/index.js | Agent |
| C4 | Entitlement spoof: client-supplied transactionId trusted | FIXED (SHA 1aab001f) — server-side verification committed; iOS TrustCenterAuditLogStore missing C4 log entry (audit log gap, not a security gap) | Agent / Human verify |
| SAFE-002 | Report+Block absent from SpaceCardView, PrayerRoomView, AmenPrayerFeedView | OPEN | Human (UX decision) |
| SAFE-010 | Minor guardian approval fail-open fallback (original) | FIXED via R1-A1 | Agent |
| AUTH-004 | Google re-auth on account deletion: static text only, no GIDSignIn flow | OPEN | Human |
| AUTH-006 | Terms/Privacy URLs must serve live legal documents | OPEN | Human/Legal |
| AUTH-013 | 30-day deletion disclosure: server purge job unconfirmed | OPEN | Human |
| R-P12-01 | Restore Purchases missing from all paywall screens | OPEN | Human (UX decision required first) |
| R-P12-02 | Stripe IAP for in-app digital subscriptions: Guideline 3.1.1 violation risk | OPEN | Legal/Product (Option A/B/C decision) |
| A11Y-002 | LiquidGlassModifiers: no Reduce Transparency fallback in 5 glass styles | OPEN | Agent (next pass) |
| BTN-002 | 26 AdaptiveComposer card buttons are silent empty stubs | OPEN | Agent/Human |
| P5-Y2 / P0-2 | NCMEC CyberTipline not wired; securityLaunchReadiness.test.ts will fail | OPEN — LEGAL GATE | Legal |
| P5-R1 | CSAM go-live: NCMEC ESP registration + legal process decision | OPEN — LEGAL GATE | Legal |
| P10-R1 | Firebase Analytics tracking classification | OPEN — LEGAL/POLICY GATE | Legal/Product |

---

## Launch Blocker Register

1. **NCMEC ESP registration — HUMAN/LEGAL**: Written legal sign-off on 18 USC 2258A, NCMEC registration in writing, NCMEC_API_KEY + NCMEC_ENDPOINT in Cloud Secret Manager, and a non-engineering deploy reviewer are all required before the CyberTipline callable goes live. P0-2 in HUMAN_GATE_QUEUE.md.

2. **CSAM_HASH_LOOKUP credentials — HUMAN/LEGAL**: P5-R1. NCMEC PhotoDNA or equivalent vendor agreement must be signed before the hash-lookup path is activated. Stub exists at `cloud-functions/` (quarantined). No agent may move this forward.

3. **P0_CLOSURE.md all green — CURRENT STATUS: DOES NOT EXIST**. 16 P0-class items remain open. 4 of those are legal gates that cannot be cleared by engineering. The App Store submission verdict per GO_NO_GO.md and READINESS_AUDIT.md is: **NO-GO**. P0_CLOSURE.md must be created and signed off by Steph before any submission attempt.

4. **us-central1 quota resolution — HUMAN (GCP)**: us-central1 is at 999/1000 Cloud Run services (CLAUDE.md). 522 dead services are identified in docs/FUNCTION_INVENTORY.md but deletion requires human approval. All new CF deploys must go to us-east1 and be entered in the Interim Region Table. Blocking any new default-codebase CF from going live until quota is reclaimed or services are deleted.

5. **Privacy policy live on website — HUMAN**: AUTH-006 is open. The Terms and Privacy URLs in the app must resolve to live, approved legal documents before App Store submission. Currently static text only.

6. **App Store Connect app record — HUMAN**: APP_STORE_APP_ID = 0000000000 in AMENAPP/Config.xcconfig (line 46). Transporter will reject an IPA with a non-existent App ID. Steph must create the app record in App Store Connect and update Config.xcconfig before any archive upload.

7. **Google re-auth on account deletion — HUMAN**: AUTH-004. The account deletion flow shows static text instead of calling GIDSignIn re-authentication. Must be wired before submission (App Store Guideline 5.1.1).

8. **Restore Purchases button — HUMAN (UX decision)**: R-P12-01 / P0-5. All 5 paywall screens are missing a Restore Purchases button. UX pattern decision must be made before engineering implements. App Store Guideline 3.1.1 requires this.

9. **Stripe IAP classification — HUMAN/LEGAL**: R-P12-02 / P0-6. Stripe is currently used for in-app digital subscriptions. Must choose Option A (remove Stripe, use StoreKit only), Option B (Stripe for physical-goods/external-only), or Option C (legal memo confirming exemption). Legal and Product must decide before any code change.

10. **deleteUserAccount CF deploy to us-east1 — HUMAN**: P0-3. Code exists; deploy is pending. Must go to us-east1 per quota doctrine and must be entered in the Interim Region Table.

11. **Firebase API key rotation + git untracking — HUMAN**: S-001/R-001. AIzaSy... key committed to GoogleService-Info.plist since commit 01adf60c. Requires rotation in Firebase Console, updating GoogleService-Info.plist, adding to .gitignore, and completing verification steps V-001 through V-006.

12. **PrivacyInfo.xcprivacy target membership — HUMAN**: File exists at AMENAPP/PrivacyInfo.xcprivacy but has no PBXFileReference or Copy Bundle Resources entry in project.pbxproj. App Store validation will block submission. Must be added via Xcode target membership.

13. **pbxproj deduplication audit — HUMAN**: 5 duplicate Swift basenames noted (AmenPrivacyEngine.swift, AmenAudienceSimulatorView.swift, ResourcesContentView.swift confirmed; BIL stubs currently off-disk in pbxproj). Steph must run a clean archive build in Xcode IDE and confirm 0 linker errors before submission.

14. **Demo credentials for App Store review — HUMAN**: P0-4. No reviewer demo-credential path exists. App Store review team requires a working test account path. Code and Xcode scheme for demo mode must be created.

---

## Flag-Flip Order (post-submission, before public launch)

Flip these Remote Config keys in the order listed. Each flip requires a smoke-test run on a staging build before proceeding to the next group. Do not flip more than one group per day.

**Group 0 — Safety infrastructure (flip first, no user-visible change):**
1. `berean_safety_classifier_enabled` — run BereanSafety test suite; confirm zero false-positive block rate in staging
2. `berean_safety_layer` — confirm Berean chat safety rails active; spot-check 10 theological queries
3. `threshold_enabled` + `threshold_prediction_enabled` — run ThresholdContracts tests; confirm moderation queue not flooded

**Group 1 — Berean AI core (flip after Group 0 passes 24h):**
4. `berean_rag_enabled` — verify scripture citation provenance in responses
5. `berean_source_grounding_enabled` — confirm source cards rendering
6. `berean_conversation_memory_enabled` — verify memory consent gate fires on first use
7. `berean_source_attribution_enabled` — confirm attribution pills visible
8. `berean_streaming_response_enabled` — load-test streaming endpoint; confirm no token leaks
9. `berean_entitlement_enforcement_enabled` — confirm free-tier cap fires correctly; test Amen+ bypass

**Group 2 — Connect V2 waves (flip after Group 1 passes 48h):**
10. `connect_layout_v2_enabled` — smoke: tab 6 renders AmenConnectV2RootView; legacy path still accessible via RC rollback
11. `connect_polish_v2_enabled` — smoke: CatchUp panel visible; ConnectStrings disclosure present
12. `connect_empty_states_enabled` — smoke: empty rail states render without crash
13. `connect_smart_berean_enabled` — smoke: Berean pill appears on scroll; contextual suggestions load
14. `connect_offline_queue_enabled` — smoke: airplane mode + reconnect flushes draft queue

**Group 3 — Connect Discovery (flip after Group 2 passes 48h):**
15. `connect_discovery_enabled` — smoke: Discovery tab renders feed
16. `connect_discovery_hero` — smoke: hero card loads with formation ranking
17. `connect_discovery_pills` + `connect_discovery_search` + `connect_discovery_preview` — smoke together: pills filter, search returns results, preview peek works
18. `connect_discovery_calm_cap` — smoke: CalmCap fires after configured session length
19. `connect_discovery_adaptive_background` + `connect_discovery_dynamic_island` — cosmetic; smoke: no crash on older devices

**Group 4 — Immersive Media & Composer (flip after Group 3 passes 48h):**
20. `immersive_media_sessions_enabled` — smoke: session boundary fires; no infinite scroll past limit
21. `immersive_feed_enabled` + `continuation_feed_enabled` — smoke: swipe-to-continue works; reflection prompt fires
22. `composer_adaptive_rail` — smoke: DockedCreationRail renders; tool routing correct
23. `composer_floating_pill` + `composer_orb` + `composer_intent_engine` + `composer_smart_cards` — smoke: no duplicate composer entry points
24. `ff_action_intelligence` — smoke: action suggestions appear; no PII leakage in suggestion text

**Group 5 — Berean Island + Capabilities (flip after Group 4 passes 48h):**
25. `berean_island` — smoke: Island overlay renders; proactive nudges disabled until next flag
26. `capabilities_core` + `capability_picker` — smoke: @ picker appears; routes correctly to Prayer OS / Scripture Intelligence
27. `prayer_os` + `scripture_intelligence` + `verse_lookup_inline` — smoke: verse detected; prayer card surfaces
28. `berean_island_proactive` — smoke: proactive suggestions rate-limited; no spam in quiet sessions
29. `write_with_berean` — smoke: co-creation flow surfaces from composer; AI disclosure visible

**Group 6 — Advanced AI features (flip after Group 5 passes 72h + safety team sign-off):**
30. `berean_agent_surface` + `berean_agent_permissions` + `berean_agent_composer` + `berean_agent_plugins` + `berean_agent_workspaces` — smoke: plugin registry loads; no unapproved plugin access
31. `amen_realtime_voice_enabled` — smoke: voice session ends on app background; no open mic after session
32. `amen_live_captions_enabled` — smoke: captions render in real time; no PII stored
33. `amen_translation_enabled` — smoke: translation appears; original preserved; no silent re-translation of user words
34. `berean_multilingual_layer` (all sub-flags) — smoke: non-English query returns correct language response; licensed translations gated

**Group 7 — Community OS + Conversation OS (flip after legal review of AI-moderated community spaces):**
35. `community_os_enabled` + `community_os_discussion_enabled` — smoke: community hub renders
36. `conversation_os_enabled` + `conversation_summaries_enabled` + `catch_up_recaps_enabled` — smoke: summaries don't surface sensitive message content to wrong parties
37. `sanctuary_core` + all sanctuary sub-flags — smoke: ministry room safety rules enforced; Aegis gate active

**Group 8 — Context Intelligence OS (flip only after Context Engine passes privacy audit):**
38. `context_system_enabled` — smoke: consent sheet fires before any context is read
39. `context_manual_entry_enabled` + `context_berean_interview_enabled` — smoke: no context stored before explicit user action
40. `nis_detection_layer` + `nis_birth_context` (NIS flags) — smoke: NIS objects visible only to owning user; no cross-user leakage

**Kill switches (these stay false; flip only in incident response):**
- `berean_safety_classifier_kill_switch` — flips OFF the classifier if false-positive storm detected
- `berean_memory_kill_switch` — flips OFF all memory writes if privacy incident declared
- `berean_context_bridge_kill_switch` — isolates context bridge if injection attack detected
- `amen_realtime_voice_kill_switch` — kills voice immediately if open-mic incident reported
- `church_notes_processing_kill_switch` — halts all Church Notes AI pipelines

---

*Generated 2026-06-16. Next review checkpoint: before any TestFlight external build or App Store submission attempt.*
