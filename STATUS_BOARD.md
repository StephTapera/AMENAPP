# AMEN STATUS BOARD
**Last generated:** 2026-06-11 | **HEAD:** 5525cf6e | **Branch:** safety-hardening  
**Refreshed by:** `findChurch2(close)` lane — regenerate this file whenever any lane reports.  
**Canonical deploy stack:** `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` (Steps 0–10e) · `RUN_ME.sh` (wrapper script)

---

## SECTION 5 — SCOREBOARD HEADER *(read this first)*

| Metric | Value |
|---|---|
| **Last green build** | `5525cf6e` — 2026-06-11T06:15 -07:00 (Xcode MCP BuildProject, 0 errors) |
| **Tests passing** | 1857 / 1857 compile (9 notRun — simulator; 0 failed) |
| **P0 open** | **0** (GAP_BOARD_CLOSED.md sealed) |
| **P1 open** | **0** |
| **P2 open** | **0** |
| **Deploys completed** | 0 of 10 steps (nothing has been deployed to production) |
| **Deploys pending** | 10 steps in STAGE3_DEPLOY_PACKAGE_2026-06-11.md |
| **DECISION_DOC_SAFETY answered** | 0 of 8 GROUP-A items · 0 of 16 GROUP-B items · 0 of 11 GROUP-C items |
| **Lanes DONE** | Connect V2, Find Church 2.0, Safety P0, Music Content Layer, Smart Composer, Gap Audit |
| **Lanes in-flight** | Onboarding/Auth, Church Notes, Berean LLM, AIL, Note Share Viewer, ONE audit |
| **Screenshots owed** | All surfaces (no simulator deployed) |

---

## SECTION 1 — FEATURES & SYSTEMS

### CONNECT V2 (5 Waves)

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| V2 shell + glass union bar | Connect redesign | 🟢 DONE-AWAITING-CAPTURE | `3f84df7e` | STEP5_PROOF_BUNDLE §4 | ConnectOfflineQueueTests (5/5) | `connect_layout_v2_enabled` (false) | ❌ No — Step 1 | Screenshots |
| Unified Catch Up / ⓘ chip | Connect redesign | 🟢 DONE-AWAITING-CAPTURE | `3f84df7e` | STEP5_PROOF_BUNDLE §4 | — | `connect_polish_v2_enabled` (false) | ❌ No | Screenshots |
| ConnectEmptyStateView | Connect redesign | 🟢 DONE-AWAITING-CAPTURE | `3f84df7e` | STEP5_PROOF_BUNDLE §4 | — | `connect_empty_states_enabled` (false) | ❌ No | Screenshots |
| Smart Berean pill | Connect redesign | 🟢 DONE-AWAITING-CAPTURE | `3f84df7e` | STEP5_PROOF_BUNDLE §4 | — | `connect_smart_berean_enabled` (false) | ❌ No — bereanQuestion CF | Screenshots + CF deploy |
| Offline draft queue | Connect redesign | 🟢 DONE-AWAITING-CAPTURE | `3f84df7e` + `4526d792` | STEP5_PROOF_BUNDLE §4 | ConnectOfflineQueueTests | `connect_offline_queue_enabled` (false) | ❌ No — Step 3 | Firestore TTL console step |
| C-2 AI disclosure string | Connect redesign | ✅ DONE-PROVEN | `3f84df7e` — `AmenConnectView.swift:194,682` | STEP5_PROOF_BUNDLE §4 | — | none (unconditional) | N/A | — |
| C-1 bottom inset 115pt | Connect redesign | ✅ DONE-PROVEN | `3f84df7e` — `AmenConnectV2View.swift:101` | STEP5_PROOF_BUNDLE §4 | — | `connect_layout_v2_enabled` | N/A (client-only) | — |
| one_relayMoment forwardAllowed | Connect/ONE | ✅ DONE-PROVEN | `3f84df7e` — `oneRelayMoment.ts:44-50` | STEP5_PROOF_BUNDLE §4 | — | always-on | ❌ No — Step 4 | Deploy |
| ConnectBadgeStore feed | Connect redesign | ✅ DONE-PROVEN | `4526d792` — `AmenConnectService.swift:56-63` | GAP_BOARD_CLOSED | — | `connect_smart_berean_enabled` | N/A (client) | — |

### SAFETY (P0 Wave 3 + A3 Callables)

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| A3 safety callables (5: evaluateDmRisk, reportDmAbuse, contentSafetyScreen, analyzeRelationshipRisk, assessDogpileRisk) | Safety P0 | 🟢 DONE-AWAITING-CAPTURE | `4526d792` — `a3Callables.ts` | GAP_BOARD_CLOSED | — | always-on, fail-closed | ❌ No — Step 2 | Deploy + bait-transcript runner |
| Age-tier vocabulary + minor search exclusion | Safety P0 | 🟢 DONE-AWAITING-CAPTURE | Safety W3 commits | `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md` | 11/11 ageTier.test.js | always-on | ❌ No — Step 1 | Deploy |
| CSAM fail-loud + NCMEC stub | Safety P0 | ⏸ PARKED-ON-GATE (NCMEC registration, A-01) | Safety W3 commits | `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md` | — | `NCMEC_SUBMISSION_ENABLED=false` | ❌ No | Legal: NCMEC registration |
| Minor DM youth gate (isMinorSafeDM) | Safety P0 | 🟢 DONE-AWAITING-CAPTURE | `AGENT_LANES.md:Rules Warning Triage` | AGENT_LANES.md rules triage | rules tests confirmed | always-on | ❌ No — Step 1 (rules) | Rules deploy |
| Guardian link + isGuardianApprovedContact fail-closed | Safety P0 | ⏸ PARKED-ON-GATE (B-13 product decision) | Written (fail-open) | — | — | always-on | ❌ No | Decision A-03/B-13 first |
| processConnectQueuedDraft CF | Safety P0/Connect | 🟢 DONE-AWAITING-CAPTURE | `4526d792` — `processConnectQueuedDraft.ts` | GAP_BOARD_CLOSED | ConnectOfflineQueueTests | `connect_offline_queue_enabled` | ❌ No — Step 3 | Deploy + TTL console |
| Context System W3-5 bait-transcript | Safety | 🧍 HUMAN-PENDING (run bait-transcript against live CFs) | — | — | — | — | ❌ No — Step 8 | Human runs bait-transcript runner after CFs deployed |
| W3-12 deployed-storage check | Safety | 🧍 HUMAN-PENDING (Firebase console verify) | — | — | — | — | — | Human checks console |
| Storage quarantine + MIME controls | Safety | 🟢 DONE-AWAITING-CAPTURE | Safety W3 commits | `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md` | — | always-on | ❌ No | Storage rules deploy |
| safetyAuditLog / legalHolds / escalation | Safety | 🟢 DONE-AWAITING-CAPTURE | `a3059025` | — | — | always-on | ❌ No — fold into Step 1 | Rules deploy; legalReviewer claim: B-12 |
| Moderation jailbreak fix + NCMEC stub | Safety | ✅ DONE-PROVEN | `c34f7975` | — | — | always-on | ❌ No | Rules deploy |
| submitSafetyReport CF | Safety | 🟢 DONE-AWAITING-CAPTURE | `e58395c6` | — | — | always-on | ❌ No | Deploy |

### MUSIC CONTENT LAYER

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| 14 Swift files (MusicContentLayer) | MusicContentLayer | ✅ DONE-PROVEN | `900c1638` | AGENT_LANES.md §MusicContentLayer | — | `ff_music_content_layer` (false) | N/A | Xcode target membership (manual human step) |
| Stage-3 CF registry + dual-gate | MusicContentLayer | ✅ DONE-PROVEN | `718b3c86` | `WIRING_CERT.md` (MusicContentLayer) | — | — | N/A | AMENFeatureFlags System 40 block (human hotspot) |
| Firestore rules for MusicContentLayer collections | MusicContentLayer | ⏸ PARKED-ON-GATE (B-10 decision — collections not yet enumerated) | — | — | — | — | ❌ No | Decision B-10 then rules |

### FIND CHURCH 2.0

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| Contracts (ChurchObject, GatheringObject, MatchExplanation, SeekerProfile, AvailabilityStatus) | FindChurch2 | ✅ DONE-PROVEN | `4352e88f` — `FindChurch2Contracts.swift` | `docs/find-church/WIRING_CERT.md` | `FindChurch2ContractsTests` 17 tests | N/A (shared) | N/A | — |
| 10 findChurch2_* feature flags | FindChurch2 | ✅ DONE-PROVEN | `4352e88f` — `AMENFeatureFlags.swift` | `docs/find-church/WIRING_CERT.md` | — | all false | ❌ No — Step 10c | RC upload |
| Firestore rules (gatherings, seekerProfiles, visitPlans, claimRequests) | FindChurch2 | ✅ DONE-PROVEN | `4352e88f` — `firestore.rules` | `docs/find-church/WIRING_CERT.md` | — | always-on | ❌ No — Step 10a/Step 1 | Rules deploy |
| AvailabilityStatus service + ingestion CF | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `144be72b` + pre-existing | `docs/find-church/WIRING_CERT.md` | FindChurch2ContractsTests | `findChurch2_availability` (false) | ❌ No — Step 10b | GOOGLE_PLACES_API_KEY + CF deploy |
| Gatherings service + search extension | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `144be72b` + pre-existing | `docs/find-church/WIRING_CERT.md` | — | `findChurch2_gatherings` (false) | ❌ No — rules first | Rules deploy (10a) |
| Media detection CF (YouTube/podcast/livestream) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `144be72b` | `docs/find-church/WIRING_CERT.md` | — | `findChurch2_availability` (false) | ❌ No — Step 10b | CF deploy |
| 3-phase Liquid Glass onboarding | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `04a89d01` — `FindChurch2OnboardingView.swift` | `docs/find-church/WIRING_CERT.md §Surface 1` | — | `findChurch2_onboarding` (false) | N/A (client-only) | Mounting in FindChurchView + screenshots |
| SeekerProfile Tier-P service | FindChurch2 | ✅ DONE-PROVEN | `04a89d01` — `FindChurch2SeekerProfileService.swift:78` | `docs/find-church/WIRING_CERT.md §Tier-P` | — | `findChurch2_onboarding` (false) | ❌ No — seekerProfiles rules | Rules deploy (10a) |
| MatchExplanation badge + "Why this church?" | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `04a89d01` — `FindChurch2MatchBadgeView.swift` | `docs/find-church/WIRING_CERT.md §Surface 3` | — | `findChurch2_matchExplain` (false) | N/A (client-only) | Mounting + screenshots |
| Find My People mode (life-stage picker) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `04a89d01` — `FindChurch2FindMyPeopleView.swift` | `docs/find-church/WIRING_CERT.md` | — | `findChurch2_gatherings` (false) | N/A (client-only) | Mounting + screenshots |
| Smart Church Card (5 intent variants) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `04a89d01` — `FindChurch2SmartChurchCard.swift` | `docs/find-church/WIRING_CERT.md §Surface 2` | — | `findChurch2_matchExplain` (false) | N/A (client-only) | Replace EnhancedChurchCard in FindChurchView |
| Discovery agent foundation | FindChurch2 | ✅ DONE-PROVEN | `04a89d01` — `FindChurch2SeekerProfileService.swift` (discoveryAgentEnabled default OFF) | `docs/find-church/WIRING_CERT.md` | — | `findChurch2_onboarding` + `discoveryAgentEnabled=false` | N/A | Privacy policy update |
| Visit Planner (EventKit + UNNotifications + Firestore) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `359d560f` — `FindChurch2VisitPlannerService.swift` | `docs/find-church/WIRING_CERT.md §Surface 4` | — | `findChurch2_visitPlanner` (false) | ❌ No — visitPlans rules | Rules deploy (10a) + screenshots |
| Church Notes post-visit integration | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `359d560f` — `startPostVisitReflection()` | `docs/find-church/WIRING_CERT.md §Surface 4` | — | `findChurch2_visitPlanner` (false) | N/A (wires to existing churchNotes) | Screenshots |
| AI Concierge (local-only, no fabrication) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `359d560f` — `FindChurch2ConciergeView.swift` | `docs/find-church/WIRING_CERT.md §Surface 5` | — | `findChurch2_concierge` (false) | N/A (local only) | Mounting + screenshots |
| Claim flow (unclaimed → pending → verified) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `6b1321aa` — `FindChurch2ClaimView.swift` | `docs/find-church/WIRING_CERT.md §Surface 6` | — | `findChurch2_claimPortal` (false) | ❌ No — claimRequests rules | Rules deploy (10a) + screenshots |
| Admin portal in-app v1 | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `6b1321aa` — `FindChurch2AdminPortalView.swift` | `docs/find-church/WIRING_CERT.md §Surface 7` | — | `findChurch2_claimPortal` (false) | N/A (client-only writes) | Screenshots |
| Trust signals on profiles | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | `6b1321aa` — `FindChurch2TrustSignalsView.swift` | `docs/find-church/WIRING_CERT.md` | — | `findChurch2_trustSignals` (false) | N/A | Mounting + screenshots |
| Premium church tools (Stripe paywall scaffold) | FindChurch2 | ⏭ DEFERRED | `6b1321aa` — `FindChurch2AdminPortalView.swift` (non-tappable overlay) | — | — | N/A | N/A | [DEFERRED: Stripe requires business/legal decision — D-09 in `docs/find-church/DECISIONS.md`] |
| UI system refresh (header, pills, map/list, card→profile) | FindChurch2 | 🟢 DONE-AWAITING-CAPTURE | pre-existing + `c358840f` | `docs/find-church/WIRING_CERT.md §Surface 8,9` | — | `findChurch2_designRefresh` (false) | N/A | Wire into FindChurchView + screenshots |
| Phoenix metro corpus seed | FindChurch2 | 🧍 HUMAN-PENDING (call ingestChurchesFromGooglePlaces after CF deploy) | Step 10d in STAGE3 | — | — | — | ❌ No — Step 10d | After 10b CFs + GOOGLE_PLACES_API_KEY set |

### ONE PRIVATE SOCIAL OS

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| one_relayMoment (forwardAllowed server gate) | ONE audit | ✅ DONE-PROVEN | `oneRelayMoment.ts:44-50` | STEP5_PROOF_BUNDLE §4 | — | always-on | ❌ No — Step 4 | Deploy |
| one_sendMoment, one_expireMoment, one_verifyEntitlement, one_activateLegacy | ONE | 🟢 DONE-AWAITING-CAPTURE | Backend/functions/src/one/ | — | — | `one_*` flags (false) | ❌ No — Step 4 | Deploy |
| Firestore rules: one_reach client no-write, one_evidence client no-read | ONE | ⏸ PARKED-ON-GATE (CONTRACTS.md §14 rules draft) | Draft in CONTRACTS.md | — | — | — | ❌ No | Rules PR from ONE lane |

### SPIRITUAL OS (Phase 2/3)

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| 27 SpiritualOS callables | Spiritual OS | 🟢 DONE-AWAITING-CAPTURE | `Backend/functions/src/spiritualOS` — all 27 in index.ts | GAP_BOARD_CLOSED | — | `spiritualOS_*` flags | ❌ No — Step 5 | Deploy |
| Phase 2 Swift views (10 surfaces) | Spiritual OS | 🟢 DONE-AWAITING-CAPTURE | Prior commits | GAP_BOARD_CLOSED | — | `spiritualOS_*` flags | N/A | Firestore rules deploy (Step 1) |

### CONTEXT SYSTEM

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| W0–W2 (manual entry, Berean interview, universal import) | Context lane | 🔧 IN-FLIGHT | Committed per AGENT_LANES.md | — | ContextStoreAdversarialTests | `context_*` flags (false) | ❌ No | Step 8 bait-transcript, W3-5 surfaces |
| W3–W5 (matching, export, QR) | Context lane | ⏸ PARKED-ON-GATE (Step 8 bait-transcript runner required) | — | — | — | `context_*` flags (false) | ❌ No | Bait-transcript runner + human decision |

### ACTION INTELLIGENCE

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| Action thread detection + CF | Action Intel | ✅ DONE-PROVEN | `AGENT_LANES.md:Action Intel` — `actionIntelligence.ts:index.ts:92` | AGENT_LANES.md | ActionIntelligenceDetectorTests, NotePillTests | `action_threads_enabled` (true) | ❌ No — index.ts export exists | TS build green; deploy in next batch |

### AIL — Accessibility Intelligence Layer

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| 22 AIL Swift files landed | AIL | ✅ DONE-PROVEN | `bd6d68f8` — auto via PBXFileSystemSynchronizedRootGroup | AGENT_LANES.md §AIL | — | `accessibility_intelligence_enabled` (false) | N/A | — |
| 7 mounting points committed (Settings, comment, Spaces, Church Notes, notifications, DM, media) | AIL | ✅ DONE-PROVEN | `bd6d68f8` | AGENT_LANES.md §AIL | — | `accessibilityIntelligenceEnabled` | N/A | — |
| PostDetail/Settings/ContentView AIL hunks | AIL | 🔧 IN-FLIGHT | Mixed with other lanes' uncommitted work | — | — | `accessibilityIntelligenceEnabled` | N/A | Isolate + commit |
| ailTransform CF | AIL | 🔴 BLOCKED (CF not deployed — fails open to original) | Stub | — | — | — | ❌ No | CF deploy; fails open safely |
| Reply-with-Care + Cooldown pre-send | AIL | 🔧 IN-FLIGHT | Proposal-only in lane | — | — | `accessibilityIntelligenceEnabled` | N/A | Implementation |
| Live-room captions | AIL | ⏸ PARKED-ON-GATE (audio pipeline + SpeechProvider) | Deferred per AGENT_LANES.md | — | — | — | — | Audio pipeline prerequisite |

### SMART COMPOSER

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| Smart Composer review gate | Smart Composer | ✅ DONE-PROVEN | `7bec341f` | `audit/runtime-evidence/smart-composer/SMART_COMPOSER_WIRING_CERT_2026_06_10.md` | — | `action_intelligence_enabled` (false) | N/A | Screenshots blocked (no real Firebase test user on sim) |

### NOTE SHARE VIEWER

| Feature | Lane | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| Note Share deep link + viewer | NoteShare | ⏸ PARKED-ON-GATE (build failures unrelated) | Wave 1 committed | — | — | `feature_note_share_viewer` (false) | N/A | Build clean → screenshots (shared-note, revoked, share sheet) |

---

## SECTION 2 — HUMAN CHECKLIST

**Execute in order. Never skip. Never mark ☑ without verifiable evidence.**  
**Full commands:** `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` · `RUN_ME.sh` (wrapper)  
**Prerequisite:** Answer all GROUP-A items in `DECISION_DOC_SAFETY.md` before any deploy.

```
DECISION_DOC_SAFETY.md (MUST COMPLETE FIRST)
☐ A-01  NCMEC registration — engage counsel, obtain ESP ID + API key → store in Secret Manager
☐ A-02  Minimum age floor — choose 13/16/18; confirm EU launch plan
☐ A-03  Guardian consent model — choose read-only / active approve-deny / emergency-only
☐ A-04  Designate Safety Officer — name, contact, UID; mint legalReviewer custom claim
☐ A-05  Age verification method — choose self-attest / carrier signal / third-party vendor
☐ A-06  Canonical Firestore rules file — confirm firestore.rules (root) vs firestore.deploy.rules;
          update firebase.json; run dry-run; reconcile both files
☐ A-07  Storage rules status — dry-run; confirm post_media/chat_videos/profile_images paths added
☐ A-08  CSAM detection pipeline — confirm live, test with known hash, document call chain
```

```
DEPLOY STACK (STAGE3_DEPLOY_PACKAGE_2026-06-11.md)
☐ Step 0   git log HEAD == 5525cf6e; firebase projects:list == amen-5e359
☐ Step 1   Recovery redeploys:
              firebase deploy --only firestore:rules             (includes FC2 rules — 10a folded in)
              firebase deploy --only functions:syncAgeTierClaim
              firebase deploy --only functions:antiHarassmentEnforcement
              firebase deploy --only functions:commentModerationEnforcement
            + storage rules (after A-07 verdict)
☐ Step 2   Pepper rotation:
              openssl rand -hex 32 (new pepper)
              firebase functions:config:set auth.pepper="<value>"
              firebase deploy --only functions:hashPhone,functions:verifyPhone,functions:checkPhoneExists
☐ Step 3   Stage-3 CFs:
            ☐ A3 safety (5): evaluateDmRisk, reportDmAbuse, contentSafetyScreen,
                              analyzeRelationshipRisk, assessDogpileRisk
☐ Step 4   Connect queue: processConnectQueuedDraft
            + Firestore console: connect_idempotency TTL policy on processedAt (7 days)
☐ Step 5   ONE CFs: one_relayMoment, one_sendMoment, one_expireMoment,
                     one_verifyEntitlement, one_activateLegacy
☐ Step 6   Spiritual OS CFs (27):
              detectUnsentThoughtRisk, saveUnsentThought, resolveUnsentThought,
              analyzeScriptureDrift, generateBalancingScripture, dismissDriftSignal,
              detectSilencePatterns, resurfaceAvoidedItem, markSilenceSignalResolved,
              updateRelationalGravity, classifyRelationshipState, generateReconciliationPrompt,
              evaluateMomentRisk, logMomentInterception, updateMomentLearning,
              createReflectionPrompt, savePostActionReflection, updateUserGrowthPattern,
              analyzeTruthVsEmotion, scoreWeightOfWords, generateGracefulRewrite,
              aggregateDiscernmentSignals, generateCommunityDiscernmentSummary,
              calculateEternalWeight, updateEternalWeightAfterReflection,
              generateMeaningPrompt, createWalkWithChristPathFromPattern
☐ Step 7   Remote Config — upload 15 keys (5 connect_* + 10 findChurch2_*, all false):
              connect_layout_v2_enabled · connect_polish_v2_enabled · connect_empty_states_enabled
              connect_smart_berean_enabled · connect_offline_queue_enabled
              findChurch2_onboarding · findChurch2_matchExplain · findChurch2_gatherings
              findChurch2_visitPlanner · findChurch2_claimPortal · findChurch2_concierge
              findChurch2_mapHybrid · findChurch2_availability · findChurch2_trustSignals
              findChurch2_designRefresh
☐ Step 8   Bait-transcript runner (after A3 callables live):
              Call contentSafetyScreen, assessDogpileRisk, evaluateDmRisk with synthetic bait.
              All must fail-closed. Review bait_transcript_results_*.txt — all must PASS.
☐ Step 9   W3-12 console check: verify Firestore rules from safety-hardening are live;
              age-tier custom claims sync running without errors in Functions log
☐ Step 10a  (folded into Step 1 — firestore.rules already includes FC2 collections)
☐ Step 10b  Find Church 2.0 CFs:
              firebase functions:config:set places.api_key="YOUR_KEY"
              firebase deploy --only functions:ingestChurchesFromGooglePlaces,
                functions:computeAvailabilityStatus,functions:scheduleAvailabilityRefresh,
                functions:detectChurchMedia
☐ Step 10c  RC keys uploaded as part of Step 7 above (already included)
☐ Step 10d  Seed Phoenix metro corpus:
              Call ingestChurchesFromGooglePlaces with { location: {lat:33.4484, lng:-112.0740}, radiusMeters:50000 }
☐ Smoke checklist (10 items per RUN_ME.md §Smoke checklist):
              ☐ evaluateDmRisk cold-start clean
              ☐ one_relayMoment forwardAllowed=false returns permission-denied
              ☐ processConnectQueuedDraft idempotency dedup working
              ☐ iOS 26 sim: flip connect_layout_v2_enabled → glass bar renders
              ☐ iOS 17 sim: same flag → fallback matte bar renders
              ☐ FC2: flip findChurch2_matchExplain → MatchExplanation badge visible
              ☐ FC2: flip findChurch2_concierge → concierge appears on church profile
              ☐ All bait-transcript results: PASS
              ☐ CSAM detection confirmed end-to-end (A-08)
              ☐ Safety Officer claim minted (A-04)
☐ DECISION_DOC_SAFETY GROUP-B (16 items) answered before App Store submission
☐ RULES_RECONCILIATION_VERDICT.md: GREEN verdict before storage rules deploy
```

---

## SECTION 3 — FLAG REGISTRY

| Flag | Default | Precondition | Precondition status | Safe to flip? |
|---|---|---|---|---|
| `connect_layout_v2_enabled` | false | processConnectQueuedDraft deployed; iOS 26 device tested | ❌ CF not deployed | **N — deploy Step 3+4 first** |
| `connect_polish_v2_enabled` | false | connect_layout_v2 already ON | ❌ Depends on above | **N** |
| `connect_empty_states_enabled` | false | connect_layout_v2 already ON | ❌ Depends on above | **N** |
| `connect_smart_berean_enabled` | false | bereanQuestion CF live; connect_layout_v2 ON | ❌ CF not deployed | **N** |
| `connect_offline_queue_enabled` | false | processConnectQueuedDraft deployed + TTL policy | ❌ CF not deployed | **N** |
| `one_*` (any) | false | ALL one_* CFs deployed; one_relayMoment forwardAllowed verified | ❌ Not deployed | **N — deploy Step 5 first** |
| `spiritualOS_*` (any) | false | All 27 Step 5 CFs deployed and ACTIVE in console | ❌ Not deployed | **N — deploy Step 6 first** |
| `findChurch2_onboarding` | false | seekerProfiles/ rules live; privacy policy updated | ❌ Rules not deployed | **N** |
| `findChurch2_matchExplain` | false | No CF dependency | ✅ Client-only | **Y after RC uploaded (Step 7)** |
| `findChurch2_gatherings` | false | gatherings/ Firestore rules live | ❌ Rules not deployed | **N** |
| `findChurch2_visitPlanner` | false | seekerProfiles/ + visitPlans/ rules live; EventKit plist confirmed | ❌ Rules not deployed | **N** |
| `findChurch2_claimPortal` | false | claimRequests/ rules live; Aegis review queue handler live | ❌ Rules not deployed | **N** |
| `findChurch2_concierge` | false | No CF dependency (local-only) | ✅ Client-only | **Y after RC uploaded (Step 7)** |
| `findChurch2_mapHybrid` | false | No CF dependency | ✅ Client-only | **Y after RC uploaded (Step 7)** |
| `findChurch2_availability` | false | computeAvailabilityStatus + scheduleAvailabilityRefresh deployed | ❌ CFs not deployed | **N — Step 10b first** |
| `findChurch2_trustSignals` | false | No CF dependency | ✅ Client-only | **Y after RC uploaded (Step 7)** |
| `findChurch2_designRefresh` | false | findChurch2_matchExplain already ON; smallest + largest device tested | Partially (matchExplain can flip) | **Y after matchExplain ON + device tested** |
| `findChurch2_*` (all others) | false | See preconditions above | Varies | **See above** |
| `context_system_enabled` | false | Step 8 bait-transcript runner PASS | ❌ Not completed | **N** |
| `context_manual_entry_enabled` | false | context_system_enabled ON | ❌ Depends | **N** |
| `context_berean_interview_enabled` | false | context_system_enabled ON | ❌ Depends | **N** |
| `context_universal_import_enabled` | false | context_system_enabled ON | ❌ Depends | **N** |
| `context_matching_enabled` | false | Bait-transcript PASS + W4 validation | ❌ | **N** |
| `accessibility_intelligence_enabled` | false | ailTransform CF deployed | ❌ CF not deployed | **N** |
| `feature_note_share_viewer` | false | Build clean; simctl screenshots posted | 🔴 Build blocked | **N** |
| `action_intelligence_enabled` | false | No CF dependency (client-gates) | ✅ | **Y after RC key added** |
| `ff_music_content_layer` | false | Xcode target membership confirmed (human step) | ❌ Manual step pending | **N — Xcode step first** |
| `amen_pulse_enabled` | false | FirebaseAI iOS-27 SDK error resolved | ❌ SDK error present | **N** |
| `NCMEC_SUBMISSION_ENABLED` | false | NCMEC registration complete (A-01); ESP ID + API key in Secret Manager | ❌ Legal step required | **N — NEVER until A-01 resolved** |

---

## SECTION 4 — RISKS & OPEN DECISIONS

*Source: `DECISION_DOC_SAFETY.md`. Grouped per directive.*

### GROUP A — ANSWER NOW (blocks safety branch deploy)

| # | Question | Recommended default | Status |
|---|---|---|---|
| A-01 | NCMEC CyberTipline Registration — has counsel been engaged? `NCMEC_SUBMISSION_ENABLED` is false; must stay false until registered. Criminal liability under 18 U.S.C. § 2258A if skipped. | Engage counsel immediately. Never deploy NCMEC pipeline until registered + ESP ID in Secret Manager. | ❌ **UNANSWERED** |
| A-02 | Minimum age floor — 13 (COPPA US) or 16 (GDPR-K EU)? | 13 if US-only launch. 16 if EU included. | ❌ **UNANSWERED** |
| A-03 | Guardian / parental consent for ages 13–15? `isGuardianApprovedContact()` currently returns `true` (fail-open). | Require verifiable consent; invert to fail-closed. Model: active approve/deny. | ❌ **UNANSWERED** |
| A-04 | Who is the designated Safety Officer? `legalReviewer` claim referenced but not minted. | Appoint before any beta. Mint claim in CF token flow immediately. | ❌ **UNANSWERED** |
| A-05 | Age verification method beyond self-attestation? | Self-attestation + phone carrier for 16+; third-party vendor for 13–15. | ❌ **UNANSWERED** |
| A-06 | Which Firestore rules file is deployed? `firebase.json` may point to wrong file. `firestore.rules` vs `firestore.deploy.rules` have diverged. | Run dry-run to confirm; reconcile into single canonical file. | ❌ **UNANSWERED** |
| A-07 | Storage rules deployment status? `post_media`, `chat_videos`, `profile_images` paths absent. | Dry-run; add all missing paths before deploy. | ❌ **UNANSWERED** |
| A-08 | Is CSAM detection pipeline actually live and producing detection events? | Confirm end-to-end with test hash. Document call chain. | ❌ **UNANSWERED** |

### GROUP B — BEFORE APP STORE LAUNCH

| # | Question | Recommended default | Status |
|---|---|---|---|
| B-01 | Pastor/leader DMs to minors — allowed? | Guardian-visible thread required; auto-notify on first message. | ❌ **UNANSWERED** |
| B-02 | Paid org moderation bypass — any exemption? | NO. Paid status never grants moderation bypass. | ❌ **UNANSWERED** |
| B-03 | Minor discoverability in Algolia / people search? | Not discoverable by strangers. Audit all sync paths. | ❌ **UNANSWERED** |
| B-04 | Anonymous prayer requests — allowed? | Allowed with rate limit + server-side moderation. Crisis routing always enabled. | ❌ **UNANSWERED** |
| B-05 | Moderation appeal response SLA? | 5 business days standard; 24h suspension appeals. | ❌ **UNANSWERED** |
| B-06 | Data retention policy (moderation reports, audit logs, NCMEC filings, legal holds)? | Moderation: 3yr. Audit: 5yr. NCMEC: indefinite. Legal: indefinite. Enable Firestore TTL in console. | ❌ **UNANSWERED** |
| B-07 | Minors in adult-led Spaces/Sanctuaries? | Guardian approval required for non-church spaces. | ❌ **UNANSWERED** |
| B-08 | Self-harm and crisis content protocol? | Block + 988 inline + pastoral notify + audit log + preserve (no delete). | ❌ **UNANSWERED** |
| B-09 | Unauthenticated reads of public posts (OPEN-5)? | Make deliberate choice: CF proxy (strips PII for SEO) OR gate behind auth. | ❌ **UNANSWERED** |
| B-10 | MusicContentLayer Firestore rules coverage? Enumerate all collections written; add rules. | Default-deny any path not covered. | ❌ **UNANSWERED** |
| B-11 | moderationQueue end-to-end iOS client test? silent `try?` calls may be silently failing. | Manual test from real device before deploy. Route creates through CF callable. | ❌ **UNANSWERED** |
| B-12 | `legalReviewer` custom claim definition? Referenced in rules but not minted anywhere. | Define in CF token-minting before deploying legalHolds rule. | ❌ **UNANSWERED** |
| B-13 | Guardian approval scope (OPEN-2) — `isGuardianApprovedContact()` fail-open. | Invert to fail-closed. Implement guardianLinkRequests CF. | ❌ **UNANSWERED** |
| B-14 | Berean AI access policy for minors? No confirmed age gate on Berean callables. | Spiritual guidance: all ages. Counseling-adjacent: 16+ or guardian visibility. Crisis: always enabled. | ❌ **UNANSWERED** |
| B-15 | Prayer request indexing in Algolia? | Never index. Server-side search only within church/sanctuary. Anonymous: no index at all. | ❌ **UNANSWERED** |
| B-16 | `chat_videos` Storage path write access — no rule exists. | CF callable validates participants + MIME + size before write. | ❌ **UNANSWERED** |

### GROUP C — LATER (post-launch, non-blocking)

| # | Question | Recommended default |
|---|---|---|
| C-01 | E2EE recovery keys — Stripe model vs platform escrow vs user-held? | User-held BIP-39 mnemonic with iCloud Keychain backup option. |
| C-02 | Stripe integration for church premium / monetization? | DEFERRED (business/legal decision). Scaffold wired, non-tappable. |
| C-03 | App Store privacy nutrition label — all data categories declared? | Audit against current feature set before submission. |
| C-04 | GDPR Data Subject Rights (right to erasure, portability) — implemented? | Stub exists; full pipeline needed before EU launch. |
| C-05 | App Check enforcement — currently emulator-exempt. When to enforce in prod? | After all CFs verified in prod; never in emulator/CI. |
| C-06 | Rate limits on Berean AI — currently uncapped per-user? | 100 requests/day for free tier; enforce server-side. |
| C-07 | Background check policy for church staff claiming profiles? | Required for VerificationTier.manual (Aegis review queue). |
| C-08 | Accessibility audit — WCAG 2.1 AA compliance? | Schedule after AIL flag is ON and surfaces are screenshot-verified. |
| C-09 | TestFlight / external beta — which users, what scope? | Internal-only first; external after DECISION_DOC_SAFETY GROUP-B complete. |
| C-10 | Push notification content — any PII in notification payload? | Sanitize all push payloads; use notification service extension for media-only. |
| C-11 | Berean LLM TS build — `npm run build` green? | Human: run in Backend/functions. ~24 TS errors pending. |

---

*STATUS_BOARD.md — refresh on every lane report. Commit with `docs(status-board): refresh [timestamp] [sha]`*
