# STATUS BOARD

Generated: 2026-06-20 17:34:35 CDT (current verification refresh)
**Updated:** 2026-06-20 17:34:35 CDT — verification HEAD: `ab354db1`
Evidence bundle HEADs cited below remain historical where noted; current full-stack evidence is anchored to `ab354db1`.

Sources: `AGENT_LANES.md`, `GAP_BOARD_CLOSED.md`, `STEP5_PROOF_BUNDLE_2026-06-11.md`, `STAGE3_DEPLOY_PACKAGE_2026-06-11.md`, `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md`, `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md`, `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md`, `DECISION_DOC_SAFETY.md`, `AMENAPP/ContextStore/RUNLOG.md`, `AMENAPP/MusicContentLayer/WIRING_CERT.md`, `Docs/find-church/WIRING_CERT.md`, `src/features/connectedIntelligence.RUNLOG.md`.

## SECTION 5 - SCOREBOARD HEADER

| Metric | Current |
|---|---|
| Tests passing/total | NOT FULL-STACK CERTIFIED @ `ab354db1`: Backend/functions TypeScript/build green; Backend/functions Jest `1228/1228`; Firestore rules `305/305`; Storage/trust/creator `54 passed, 1 intentional skip`; RTDB `4/4`; iOS duplicate `AMENFeatureFlags` source error fixed; iOS app build/test compile remain BLOCKED by sandboxed SwiftPM diagnostics-cache writes under `~/Library/Caches` plus CoreSimulator warnings. See `FULL_STACK_BUILD_CERTIFICATION.md`. |
| P0/P1/P2 open counts | Certification blockers: `1 P0` iOS build/test compile blocker; safety follow-ons remain explicit rows below: `5` machine-work rows and `3` human-decision rows |
| Lanes DONE vs total | `7/24` board rows are `✅ DONE-PROVEN`; remaining rows are human-pending, in-flight, parked, blocked, or deferred |
| Deploys completed vs pending | `0/16` human checklist items have deploy/console proof in this workspace |
| Last green build sha+time | No current iOS green at `ab354db1`. Last historical iOS app MCP green remains `4f044d91` at `2026-06-11T16:02:06-07:00`; it does not certify current HEAD. |
| Full-stack merge gate | RED @ `ab354db1`: Layer 3/4/5 green; Layer 1/2 blocked. No double-green repeat. |

## SECTION 1 - FEATURES & SYSTEMS

| Feature | Lane/Swarm | Status | Built | Wired/Cert | Tests | Flag (default) | Backend deployed? | Remaining |
|---|---|---|---|---|---|---|---|---|
| Full-stack certification @ `ab354db1` | Certification lane | 🔴 BLOCKED (iOS build/test compile) | Backend/functions + rules compile/test green; duplicate `AMENFeatureFlags 2.swift` removed; iOS build not certified | `FULL_STACK_BUILD_CERTIFICATION.md` current attempt | Backend Jest `1228/1228`; Firestore rules `305/305`; Storage/trust/creator `54 passed, 1 intentional skip`; RTDB `4/4`; iOS blocked by SwiftPM sandbox cache denial | N/A | No deploys performed | Run unsandboxed canonical Layer 1 clean build + Layer 2 build-for-testing in capable Xcode/human shell; then repeat Layer 1 for double-green |
| Gap Audit + P0 Fix Wave 1 | Gap Audit + P0 Fix Wave 1 | ✅ DONE-PROVEN | `9bbfe47f`, `7af3204b`, `248df4ac`, `41bdf467` in `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md` | Deploy package: `RULES_DEPLOY_PACKAGE_P0_2026-06-10.md` | Firestore emulator `18/18`; functions Jest `84/84` | No runtime flag; deploy package only | No | Human deploy: pepper secret, Firestore rules, index, 3 phone functions |
| Safety Wave 3 package | Safety hardening | 🧍 HUMAN-PENDING (Group A safety decisions + NCMEC/Storage/rules verification) | Prepared in `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md` | Consolidated package: `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | `ageTier.test.js` `11/11`; Xcode diagnostics pass; focused Swift tests blocked by simulator wall | Safety flags already listed in Step 5 proof; production enablement gated | No | Answer `DECISION_DOC_SAFETY.md` Group A, legalReviewer claim, NCMEC registration, Storage/rules console verification |
| NCMEC registration and live submission | Safety/legal | 🧍 HUMAN-PENDING (A-01 counsel/registration) | Queue-only per `DECISION_DOC_SAFETY.md` and `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | Decision links: `DECISION_DOC_SAFETY.md` A-01, deploy finding #10 | Not testable until counsel/credentials exist | `NCMEC_SUBMISSION_ENABLED=false` | No | Engage counsel, obtain ESP ID/API key, store secrets; do not enable live HTTP submission |
| NCMEC credential placeholders | Safety/legal | 🧍 HUMAN-PENDING (A-01 Secret Manager credentials) | Placeholder gap tracked in `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` finding #33 | Decision links: `DECISION_DOC_SAFETY.md` A-01 | Not testable until credentials exist | `NCMEC_SUBMISSION_ENABLED=false` | No | Replace `TODO_ESP_ID` / `TODO_ESP_API_KEY` only after registration |
| Age verification and COPPA vendor | Safety/legal | 🧍 HUMAN-PENDING (A-02/A-05 age policy/vendor) | Decision required in `DECISION_DOC_SAFETY.md` A-02/A-05; finding #11 | Decision links: `DECISION_DOC_SAFETY.md` A-02/A-05 | Not testable until policy/vendor selected | Registration/age gates remain conservative | N/A | Select minimum age floor and age verification model |
| Stripe webhook secret migration | Payments backend | 🔧 IN-FLIGHT | Open finding #30 in `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | No cert yet | No named test yet | Payment/giving flags OFF | No | Migrate legacy `stripeWebhook` to canonical secret handling |
| Guardian email verification CF (finding #44) | Safety backend | 🟢 DONE-AWAITING-CAPTURE (CF deploy owed) | `functions/guardianLink.js` + `GuardianLinkService.swift` + `GuardianLinkInvitationView.swift` (commit `35a09617`) | `docs/find-church/../GUARDIAN_LINK_WIRING_CERT.md` | `functions/test/guardianLink.test.js` 8/8 pass; BuildProject green | `guardian_link_enabled` (default OFF) | No — `firebase deploy --only functions:onGuardianLinkCreated,functions:verifyGuardianLink` | Human deploy 2 CFs + install Trigger Email extension; flip flag after A-03 policy decision |
| Stripe webhook idempotency | Payments backend | 🔧 IN-FLIGHT | Open finding #47 in `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | No cert yet | No named test yet | Payment/giving flags OFF | No | Add idempotency storage and replay-safe webhook handling |
| Server-side RBAC org/church mutations | CommunityOS/RBAC backend | 🔧 IN-FLIGHT | Open finding #48 in `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | No cert yet | No named test yet | Admin/org mutation paths remain gated | No | Move privileged org/church mutations behind server-side RBAC checks |
| Phone auth Gen2 migration | Auth/Safety backend | 🔧 IN-FLIGHT | Open finding #51 in `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` | P0 phone hashing package exists; Gen2 migration not certified | Existing phone PII Jest `3/3` in P0 package; Gen2 tests still owed | Phone auth deployment still human-gated | No | Migrate phone auth functions to Gen2 with App Check/Auth/rate-limit posture |
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
- ☐ SAFETY: Grant legalReviewer claim — Firebase Auth UID of designated safety officer (see `DECISION_DOC_SAFETY.md` A-04); run: `firebase auth:users:update <UID> --custom-claims '{"legalReviewer":true}' --project amen-5e359` or via Admin SDK: `admin.auth().setCustomUserClaims(uid, { legalReviewer: true })`
- ☐ SAFETY: Enable App Check enforce-mode — Firebase Console → App Check → each CF → toggle Enforce Mode ON; order: `submitSafetyReport` → `moderation/*` → Berean OS + Selah functions; pre-condition: only after RUN_ME.sh Stage 4 STEP 3 (functions deploy) is verified working (also echoed as the final instruction in RUN_ME.sh)

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

### SAFETY FOLLOW-ON RECONCILIATION

| Source finding | Board disposition | Owner lane |
|---|---|---|
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #30 legacy Stripe webhook secret | 🔧 row: Stripe webhook secret migration | Payments backend |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #44 Guardian email verification CF | 🔧 row: Guardian email verification CF | Safety backend |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #47 Stripe webhook idempotency | 🔧 row: Stripe webhook idempotency | Payments backend |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #48 Server-side RBAC org/church mutations | 🔧 row: Server-side RBAC org/church mutations | CommunityOS/RBAC backend |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #51 Phone auth Gen2 migration | 🔧 row: Phone auth Gen2 migration | Auth/Safety backend |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #10 NCMEC CyberTipline stub | 🧍 row: NCMEC registration and live submission | Safety/legal |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #11 Age verification/COPPA | 🧍 row: Age verification and COPPA vendor | Safety/legal |
| `DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md` #33 NCMEC hardcoded TODO credentials | 🧍 row: NCMEC credential placeholders | Safety/legal |

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

---

### Agent 2 — Runtime Proof Status (2026-06-11)
- Simulator state: **Booted** (UUID `313273F4-133A-42A8-9D12-8784FC893230`, iPhone 17 Pro 27.0)
- App installed: **No — human must build and run via Xcode first** (app container not present on sim)
- Test run: **BLOCKED by pre-existing build error** — duplicate `CONTRACTS.md` resource copy rule (`AMENAPP/ConnectSpaces/CONTRACTS.md` vs `AMENAPP/Shared/Contracts/CONTRACTS.md` both copy to same app bundle path). Last verified green: `5525cf6e` — 1857/1857 passing (per Section 5 scoreboard). Fix: remove one CONTRACTS.md from the Xcode target's Copy Bundle Resources phase.
- WALKTHROUGH_SCRIPT.md: **FILED** — 15 stations, ≈45 min total, signed-in entry point, flags + paths + doctrine checks per station
- CAPTURE_PLAN.md: **FILED** — 67 ordered screenshots across 16 groups, priority tier (Must Have / Should Have), Guideline 1.2 safety evidence groups K and L flagged MUST HAVE
- Human's part: (1) Fix duplicate CONTRACTS.md build error → (2) Build + run via Xcode → (3) Sign in → (4) Follow WALKTHROUGH_SCRIPT.md (≈2 min per station) → (5) Capture screenshots per CAPTURE_PLAN.md

### Agent 4 — Launch Config Status (2026-06-11)
- LAUNCH_CONFIG_VNEXT.md: FILED at repo root
- Total flags evaluated: 278
- Recommended ON: 148 (core proven + safety-hardened; default true in code with no unmet CF/decision gate)
- Recommended OFF: 130 (backend not deployed / GROUP A or B decision open / in-flight lane / DONE-AWAITING-CAPTURE / CF dependency unmet)
- Key ON categories: Moderation, Berean RAG, Church Discovery v1, Selah Media OS, Daily Digest, Social Safety OS (all 25 flags), Aegis Pre-Post Review, Feed Intelligence, Church Notes, Smart Share, Profile V2, Connect Hub v1, Discussion OS
- Key OFF categories: Spiritual OS (27 CFs not deployed), Connect V2 (CF not deployed), Find Church 2.0 (rules + CFs pending), AIL (CF not deployed, in-flight), Context System (bait-transcript not run), Community OS (Phase 1 incomplete), ONE OS (CFs not deployed), Berean OS (CFs not deployed), Amen Pulse (SDK error)
- Human action: Read LAUNCH_CONFIG_VNEXT.md → approve flag set → publish 15 RC keys to Remote Config after RUN_ME.sh → follow 30-step ordered flag flip sequence
- Critical reminder: NCMEC_SUBMISSION_ENABLED must remain false until A-01 (NCMEC registration) is resolved — criminal liability risk

### Agent 3 — Decision Counsel Status (2026-06-11)
- DECISION_BRIEFS/: **FILED** — 48 individual decision briefs + EXECUTIVE_SUMMARY.md + 2 legal memos (LEGAL_MEMO_NCMEC.md, LEGAL_MEMO_COPPA.md) = 51 files total
- GROUP A (ANSWER-NOW hard blockers): **8 items** — A-01 through A-08
- GROUP B (BEFORE-LAUNCH): **25 items** — B-01 through B-25
- GROUP C (LATER, 90-day window): **15 items** — C-01 through C-15
- Legal counsel required for: **A-01** (NCMEC 18 U.S.C. § 2258A), **A-03** (COPPA verifiable parental consent), **A-05** (age verification method), **A-02 if EU launch planned** (GDPR-K)
- Critical code gap confirmed: `isGuardianApprovedContact()` is fail-open (line 566 `if !doc.exists { return true }`) — one-line fix ready pending A-03 decision
- NCMEC pipeline status: queue-only (no live HTTP call); `TODO_ESP_ID` / `TODO_ESP_API_KEY` are literal placeholders; `NCMEC_SUBMISSION_ENABLED=false` — **do not enable** until attorney completes registration
- Human action: Read `DECISION_BRIEFS/EXECUTIVE_SUMMARY.md` → answer GROUP A items → engage attorney for A-01 and A-03 → sign DECISION_DOC_SAFETY.md sign-off table

### Agent 5 — Submission Mechanic Status (2026-06-11)
- APP_PRIVACY_LABELS.md: **FILED** — full privacy nutrition label derived from code analysis (PrivacyInfo.xcprivacy + all 15 NS*UsageDescription keys + ATT + HealthKit + CoreMotion + StoreKit + all UGC types); tracking confirmed via NSPrivacyTracking=true; all App Store Connect answers tabulated row-by-row; third-party SDK list included
- AGE_RATING_WORKSHEET.md: **FILED** — all 13 Apple questionnaire questions answered; recommended rating **12+** (Social Networking + UGC); UGC mitigation evidence mapped to source files; minor safety age-tier table documented; operational SLA gap flagged as HUMAN action
- REVIEW_READINESS.md: **FILED** — Guideline 1.2 UGC compliance evidence (report/block/moderate/SLA), Guideline 4.8 Sign in with Apple confirmed present, Guideline 5.1 ATT confirmed, demo account instructions, complete review notes draft (paste-ready), full pre-submission blocking checklist
- RELEASE_NOTES.md: **FILED** — "What's New" (v1.0 full text), short description (136 chars), full description (~2400 chars), keywords (93 chars), subtitle (30 chars), promotional text; all within App Store Connect character limits; metadata field-by-field checklist included
- ARCHIVE_AND_TESTFLIGHT.md: **FILED** — 9-step archive/upload/TestFlight guide; entitlements verification; export compliance answers; 19-station TestFlight acceptance checklist; all pre-submission gates listed with cross-references
- Human actions remaining:
  - Create demo account `review@amen-appstore-demo.com` with 3+ posts, 2+ prayer requests, 1 church note (REVIEW_READINESS.md)
  - Answer privacy labels in App Store Connect using APP_PRIVACY_LABELS.md
  - Answer age rating questionnaire in App Store Connect using AGE_RATING_WORKSHEET.md
  - Enter release metadata (description, keywords, screenshots) using RELEASE_NOTES.md
  - Set Privacy Policy URL and Support URL in App Store Connect
  - Verify account deletion works end-to-end on device
  - Document moderation SLA and publish moderation contact email
  - Archive and upload per ARCHIVE_AND_TESTFLIGHT.md (after all 10 backend deploy steps complete)
  - Complete TestFlight 19-station checklist on a real device before submitting
