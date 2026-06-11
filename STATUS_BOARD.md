# STATUS BOARD

Generated: 2026-06-11 09:02:51 MST
Workspace HEAD at refresh: `12d149ea`
Evidence bundle HEADs cited: `4526d792` where proof bundles were generated before this refresh
Refresh commit: pending

Sources: `AGENT_LANES.md`, `GAP_BOARD_CLOSED.md`, `STEP5_PROOF_BUNDLE_2026-06-11.md`, `STAGE3_DEPLOY_PACKAGE_2026-06-11.md`, `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md`, `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md`, `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md`, `DECISION_DOC_SAFETY.md`, `AMENAPP/ContextStore/RUNLOG.md`, `AMENAPP/MusicContentLayer/WIRING_CERT.md`, `Docs/find-church/WIRING_CERT.md`, `src/features/connectedIntelligence.RUNLOG.md`.

## SECTION 5 - SCOREBOARD HEADER

| Metric | Current |
|---|---|
| Tests passing/total | `1848/1857 executable discovered`, `9 notRun`, `0 failed` from `STEP5_PROOF_BUNDLE_2026-06-11.md` |
| P0/P1/P2 open counts | `0/0/0` from `GAP_BOARD_CLOSED.md`; safety follow-ons still list `5 OPEN + 3 HUMAN-DECISION` in `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` |
| Lanes DONE vs total | `7/16` board rows are `✅ DONE-PROVEN`; remaining rows are human-pending, in-flight, parked, blocked, or deferred |
| Deploys completed vs pending | `0/14` human checklist items have deploy/console proof in this workspace |
| Last green build sha+time | `4526d792` at `2026-06-11T06:15:18 -07:00`; current workspace HEAD is `12d149ea` and has not been rebuilt in this harness |

## SECTION 1 - FEATURES & SYSTEMS

| Feature | Lane/Swarm | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| Gap Audit + P0 Fix Wave 1 | Gap Audit + P0 Fix Wave 1 | ✅ DONE-PROVEN | `9bbfe47f`, `7af3204b`, `248df4ac`, `41bdf467` in `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md` | Deploy package: `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md` | Firestore emulator `18/18`; functions Jest `84/84` | No runtime flag; deploy package only | No | Human deploy: pepper secret, Firestore rules, index, 3 phone functions |
| Safety Wave 3 package | Safety hardening | 🧍 HUMAN-PENDING (Group A safety decisions + NCMEC/Storage/rules verification) | Prepared in `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md` | Consolidated package: `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | `ageTier.test.js` `11/11`; Xcode diagnostics pass; focused Swift tests blocked by simulator wall | Safety flags already listed in Step 5 proof; production enablement gated | No | Answer `DECISION_DOC_SAFETY.md` Group A, legalReviewer claim, NCMEC registration, Storage/rules console verification |
| Safety A3 callables | Safety P0 Wave 3 | ✅ DONE-PROVEN | `STEP5_PROOF_BUNDLE_2026-06-11.md` at `4526d792` | Stage-3 package Step 2: `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` | Build proof `0 errors`; A3 callable fail-closed wiring cited in Step 5 proof | Safety callables gated by App Check/Auth/rate limit, no client flip | No | Deploy `evaluateDmRisk`, `reportDmAbuse`, `contentSafetyScreen`, `analyzeRelationshipRisk`, `assessDogpileRisk`; verify active |
| Connect V2 UI polish and gates | Connect lane | ✅ DONE-PROVEN | `STEP5_PROOF_BUNDLE_2026-06-11.md` at `4526d792` | Cert index in `STEP5_PROOF_BUNDLE_2026-06-11.md` | `ConnectOfflineQueueTests` `5` tests; build proof `0 errors`, `0 failures` | `connect_layout_v2_enabled=false`, `connect_polish_v2_enabled=false`, `connect_empty_states_enabled=false`, `connect_smart_berean_enabled=false` | No | Human deploy Step 3/6; in-app capture owed |
| Connect offline queue callable | Connect lane | ✅ DONE-PROVEN | `Backend/functions/src/connectQueue/processConnectQueuedDraft.ts` cited in Step 5 proof | Stage-3 package Step 3 | Idempotency and callable-owned write proof cited in `STEP5_PROOF_BUNDLE_2026-06-11.md` | `connect_offline_queue_enabled=false` | No | Deploy callable; enable TTL on `connect_idempotency.processedAt`; smoke test |
| ONE private social OS callables | ONE lane | ✅ DONE-PROVEN | `one_relayMoment` forwardAllowed rejection closed in `GAP_BOARD_CLOSED.md`; Stage-3 Step 4 lists 5 functions | Stage-3 package Step 4 | Build proof included in Step 5 proof; specific relay rejection proof in `GAP_BOARD_CLOSED.md` | ONE flags not safe until all `one_*` CFs active | No | Deploy `one_relayMoment`, `one_sendMoment`, `one_expireMoment`, `one_verifyEntitlement`, `one_activateLegacy`; smoke forwardAllowed rejection |
| Spiritual OS callable batch | Spiritual OS lane | ✅ DONE-PROVEN | `GAP_BOARD_CLOSED.md` closes Phase 2/3 and confirms 10 surfaces build; Stage-3 Step 5 lists 27 CFs | Stage-3 package Step 5 | Build proof `4526d792`; `GAP_BOARD_CLOSED.md` says Swift views exist/build | `spiritualOS_*` flags stay off until all 27 CFs active | No | Deploy 27 CFs; verify ACTIVE before any flag flip |
| Context System | Context System | ✅ DONE-PROVEN | `AMENAPP/ContextStore/RUNLOG.md` waves 0-5 complete | Runlog: `AMENAPP/ContextStore/RUNLOG.md` | `node --check` green per runlog; adversarial tests cited in handoff evidence | Context flags stay off until Stage-3 CFs/rules are live | No | Live bait transcript runner; `extractContextFacets` Stage-3 deploy; emulator harness still owed |
| Connected Intelligence | Connected Intelligence | ⏸ PARKED-ON-GATE (OAuth secrets + deploy + native host registration) | `src/features/connectedIntelligence.RUNLOG.md` C1 phases 0-3 | Runlog: `src/features/connectedIntelligence.RUNLOG.md` | `tsc` `0 errors`; grep-lint clean | Connector and AIL flags default OFF | No | OAuth secrets, callable deploy, native host registration, E2E |
| Find Church 2.0 | Find Church lane | 🔧 IN-FLIGHT | `Docs/find-church/WIRING_CERT.md` lists surfaces and Tier-P invariant evidence | Cert: `Docs/find-church/WIRING_CERT.md`; deploy Step 10a-10e | Tier-P evidence lines cited in cert; screenshots owed | `findChurch2_*` all false | No | Places key, Phoenix seed, 4 CF deploys, RC keys, screenshots/capture |
| Music Content Layer | Music Content Layer | ⏭ DEFERRED (Stage-3 backend and flag registration) | `AMENAPP/MusicContentLayer/WIRING_CERT.md` | Cert: `AMENAPP/MusicContentLayer/WIRING_CERT.md` | `26` `@Test` functions; MusicContentLayer build green in cert | `ff_music_content_layer=false`; `musicContentLayerEnabled` addition still human/implementation step | No | Stage-3 CFs `getMusicPulseItems`, `joinListeningRoom`; flag add; deferred persistence and integration items |
| Smart Composer surfaces | Smart Composer lane | 🟢 DONE-AWAITING-CAPTURE (screenshots owed) | Commit `7bec341f` cited in `AGENT_LANES.md` | Runtime cert status in `AGENT_LANES.md` | `BuildProject` green and `RunProject` launched per lane entry | Composer flags default OFF | N/A | Auth runtime capture blocked by erased shared simulator with no real Firebase session |
| Action Intelligence | Action Intelligence lane | 🔧 IN-FLIGHT | Active lane in `AGENT_LANES.md`; TS green evidence cited there | Lane report in `AGENT_LANES.md` | TS compile green per lane entry | Action Intelligence flags default OFF | No | Continue lane-specific service/UI/callable wiring |
| AIL / Accessibility Intelligence | AIL lane | ⏸ PARKED-ON-GATE (ailTransform deploy + flags) | `src/features/connectedIntelligence.RUNLOG.md` says `ailTransform` joined Stage-3 batch | Runlog: `src/features/connectedIntelligence.RUNLOG.md` | Runlog compile proof only | AIL flags default OFF | No | Deploy `ailTransform`, add/verify all registry flags, focused UI verification |
| Note Share Viewer | Note Share lane | 🔴 BLOCKED (runtime simulator/build blockers) | Active blocker in `AGENT_LANES.md` | None sufficient for DONE | No capture proof | Feature flag OFF | N/A | Resolve runtime blocker before cert can be trusted |
| Church Notes Smart Objects | Church Notes swarm | 🔴 BLOCKED (active Church Notes owner owns `**/ChurchNotes/**`) | Contracts exist per user prompt; this lane must not duplicate ownership | No current cert in this board | No current board proof | `churchNotesSmartObjectsEnabled=false`; sub-flags default OFF | No | Existing owner must land or release lane before another agent touches `ChurchNotes/**` |

## SECTION 2 - HUMAN CHECKLIST

- ☐ Step 0 verify HEAD/project - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 0
- ☐ Step 1 recovery redeploys (7 fns) - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 1 plus `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md`
- ☐ pepper rotation + 3 phone fns - `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md` required deploy steps
- ☐ Step 2 safety wave 3 - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 2
- ☐ Step 3 connect queue - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 3
- ☐ Step 4 ONE CFs - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 4
- ☐ Step 5 Spiritual OS CFs (27) - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 5
- ☐ Step 6 RC keys - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 6
- ☐ Step 8 bait-transcript runner - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 8
- ☐ Step 9 W3-12 console check - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 9
- ☐ Step 10a-d Find Church, including Places key + Phoenix seed - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` Step 10
- ☐ smoke checklist - `STAGE3_DEPLOY_PACKAGE_2026-06-11.md` smoke checklist
- ☐ DECISION_DOC_SAFETY answers - `DECISION_DOC_SAFETY.md` Group A
- ☐ rules reconciliation verdict reviewed - `DECISION_DOC_SAFETY.md` A-06 and `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md`

## SECTION 3 - FLAG REGISTRY

| Flag | Default | Preconditions | Precondition status | Safe to flip? |
|---|---|---|---|---|
| `connect_layout_v2_enabled` | `false` | `processConnectQueuedDraft` deployed; iOS 26 tested | Pending deploy/capture | N |
| `connect_polish_v2_enabled` | `false` | Layout v2 reviewed in app; screenshots/capture | Pending capture | N |
| `connect_empty_states_enabled` | `false` | Layout v2 reviewed; empty-state smoke | Pending capture | N |
| `connect_smart_berean_enabled` | `false` | `bereanQuestion` live; layout v2 already on | Pending live function proof | N |
| `connect_offline_queue_enabled` | `false` | `processConnectQueuedDraft` deployed; TTL set | Pending deploy/TTL | N |
| `moderationV2Enabled` | `true` | Existing safety stack and audit path | Listed true in Step 5 proof; production console state not proven here | N |
| `imageModerationEnabled` | `true` | CSAM/image moderation live status verified | A-08 pending | N |
| `dmEnhancedScanningEnabled` | `true` | A3 callables deployed and App Check enforced | Pending Step 2 deploy | N |
| `bereanEntitlementEnforcementEnabled` | `true` | Entitlement callable deployed and rules verified | Not proven in this refresh | N |
| `checkInCrisisEscalationEnabled` | `true` | Crisis escalation call chain verified | Pending safety decisions/live proof | N |
| `findChurch2_onboarding` | `false` | RC key added; in-app onboarding capture; privacy reviewed | Pending Step 10/RC/capture | N |
| `findChurch2_matchExplain` | `false` | RC key added; explanation sheet capture | Pending Step 10/RC/capture | N |
| `findChurch2_gatherings` | `false` | Rules Step 10a; gatherings data path verified | Pending rules deploy | N |
| `findChurch2_visitPlanner` | `false` | Rules Step 10a; visit plan writes verified | Pending rules deploy | N |
| `findChurch2_claimPortal` | `false` | Rules Step 10a; claim request flow verified | Pending rules deploy/capture | N |
| `findChurch2_concierge` | `false` | Concierge callable/AI review; privacy clamp | Pending implementation proof | N |
| `findChurch2_mapHybrid` | `false` | Places key; Phoenix seed; map/list capture | Pending key/seed/capture | N |
| `findChurch2_availability` | `false` | `computeAvailabilityStatus` and scheduler deployed | Pending Step 10b | N |
| `findChurch2_trustSignals` | `false` | Media/trust signal callable deployed and verified | Pending Step 10b | N |
| `findChurch2_designRefresh` | `false` | In-app design review capture | Pending capture | N |
| `ff_music_content_layer` | `false` | Feature flag registered in app; Stage-3 CFs live | Deferred in cert | N |
| `churchNotesSmartObjectsEnabled` | `false` | Church Notes owner lane lands contracts, detection, renderer, rules, tests | Blocked by lane ownership | N |
| `smartObjects.detectionOnDevice` | `false` | On-device detector tests and Tier-P isolation proof | Blocked by lane ownership | N |
| `smartObjects.detectionServer` | `false` | Callables/triggers, App Check, rules, emulator tests | Blocked by lane ownership | N |
| `smartObjects.cardVariants` | `false` | Real SwiftUI variants and accessibility/capture proof | Blocked by lane ownership | N |
| `smartObjects.expandedView` | `false` | Expanded view + dock wired/captured | Blocked by lane ownership | N |
| `smartObjects.composer` | `false` | Composer E2E and Tier-P zero-server-object proof | Blocked by lane ownership | N |
| `smartObjects.comments` | `false` | SmartCommentBar and moderation tests | Blocked by lane ownership | N |
| `smartObjects.personalization` | `false` | ContextStore-only wiring and explainer toggles | Blocked by lane ownership | N |
| `smartObjects.premiumGenerators` | `false` | Server-side entitlement checks and matrix tests | Blocked by lane ownership | N |
| `smartObjects.churchPremium` | `false` | Church tier checks and branded card cert | Blocked by lane ownership | N |
| `smartObjects.givingIntegration` | `false` | Stripe business/legal decision | Deferred by spec | N |
| Connected Intelligence connector flags | `false` | OAuth secrets, callable deploy, native host registration, E2E | Parked on gate | N |
| AIL accessibility flags | `false` | `ailTransform` deployed and UI verification complete | Parked on gate | N |

## SECTION 4 - RISKS & OPEN DECISIONS

### ANSWER-NOW

| ID | Question | Recommended default |
|---|---|---|
| A-01 | NCMEC CyberTipline registration | Engage counsel; keep live NCMEC HTTP submission disabled until ESP ID/API key are issued and stored in Secret Manager |
| A-02 | Minimum age floor | `13` for US-only launch; `16` if EU launch is included or undecided |
| A-03 | Guardian / parental consent for ages 13-15 | Require verifiable consent; fail closed when no guardian approval exists |
| A-04 | Designated safety officer | Appoint before beta; mint `legalReviewer` Firebase custom claim |
| A-05 | Age verification method | Self-attestation plus phone signal for 16+; third-party age verification vendor for ages 13-15 |
| A-06 | Which Firestore rules file is production | Reconcile to one canonical rules file and dry-run before deploy |
| A-07 | Storage rules deployment status | Verify live Storage rules or deploy reviewed hardened package; add missing upload paths first |
| A-08 | CSAM detection pipeline live status | Confirm end-to-end hash/ML detection with test hash before public launch |

### BEFORE-LAUNCH

| ID | Question | Recommended default |
|---|---|---|
| B-01 | Pastor / leader DMs to minors | Guardian-visible thread required |
| B-02 | Paid orgs and moderation bypass | Paid status never bypasses moderation |
| B-03 | Minor discoverability in search and people index | Minors are not discoverable by strangers; audit Algolia sync paths |
| B-04 | Anonymous prayer requests | Allowed with rate limiting, mandatory moderation, hidden display identity, server-side legal identity retention |
| B-05 | Moderation appeal response SLA | 5 business days standard; 24 hours for suspension appeals |
| B-06 | Data retention policy | Moderation 3 years; audit logs 5 years; NCMEC/legal holds indefinitely; enable TTL policies |
| B-07 | Minors in adult-led sanctuaries/spaces | Guardian approval for adult-led spaces outside registered church |
| B-08 | Self-harm and crisis content protocol | Block public posting, show 988 resources, preserve record, private pastoral route where configured |
| B-09 | Unauthenticated read of public posts | Gate reads behind auth unless a CF proxy strips PII for SEO |
| B-10 | MusicContentLayer Firestore rules coverage | Keep flag OFF until rules paths are explicitly covered and reviewed |
| B-11 | moderationQueue end-to-end iOS client test | Require client E2E before launch |
| B-12 | `legalReviewer` custom claim definition | Define and mint server-side before safety deploy |
| B-13 | Guardian approval scope | Fail closed; require approval for DMs/spaces involving minors |
| B-14 | Berean AI access policy for minors | Restrict and log minor access; apply crisis escalation |
| B-15 | Prayer request indexing and search policy | Do not index private/sensitive prayers; anonymous display must retain server moderation identity |
| B-16 | `chat_videos` Storage path write access | Add explicit Storage rules before deploying hardened Storage |
| B-17 | `moderateUploadedImage` CDN caching window | Fail closed; avoid serving unmoderated media from CDN cache |
| B-18 | Direct client writes to comments collection | Prefer callable-owned moderation writes or rules-enforced pending state |
| B-19 | `one_users/witnesses` enforcement CF | Keep ONE flags OFF until callable enforcement is deployed |
| B-20 | `/users/{userId}` minor status exposure | Minimize exposed minor fields; use claims/derived server checks |
| B-21 | App Check project-level enforcement | Enforce after callables deployed and smoke-tested |
| B-22 | Stripe webhook canonical file | Select one canonical webhook; migrate secret handling/idempotency before enabling payments |
| B-23 | `safeMessagingGateway.js` direct write bypass | Route writes through moderated callable path only |
| B-24 | RBAC Firestore path consistency | Normalize org/church role paths; enforce server-side |
| B-25 | `backfillUsernameLookup` admin claim guard | Require admin claim and audit log for backfill |

### LATER

| ID | Question | Recommended default |
|---|---|---|
| C-01 | Moderation team staffing model | Assign dedicated safety ownership before public scale |
| C-02 | Human vs AI review ratio | Use AI triage only; require human review for CSAM, minors, legal holds, suspensions |

Additional later backlog exists in `DECISION_DOC_SAFETY.md` C-03 through C-15 and remains tracked there until the answer-now and before-launch items are closed.

### OTHER PRODUCT/LEGAL DECISIONS

| Decision | Recommended default |
|---|---|
| Stripe model | Keep all giving/payment integration flags OFF; do not implement payment flow until webhook canonical file, idempotency, business model, and legal review are complete |
| E2EE recovery | Default to user-controlled recovery with no plaintext server recovery; document irrecoverable-loss UX before launch |
| NCMEC registration | Treat as hard blocker for any live NCMEC submission; keep `NCMEC_SUBMISSION_ENABLED=false` until counsel completes registration |
