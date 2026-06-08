# AMEN iOS App — Source Census

**Last Updated:** 2026-06-07  
**Audit Date:** 2026-06-07  
**Total Swift Files:** 2,898  
**Total Cloud Function Files:** 200+  
**Firestore Rules:** 1 (firestore.rules)  

## iOS App Source Structure (AMENAPP/)

### Top-Level Folders by Swift File Count

| Folder | Count | Purpose |
|--------|-------|---------|
| AMENAPP (root) | 955 | Main app container, utilities, singletons, services |
| Creator | 79 | Content creation, drafts, publishing |
| ChurchNotes | 53 | Church note-taking, sermon capture, AI features |
| BereanOS | 43 | AI formation assistant, memory graph, trust ledger |
| AIIntelligence | 42 | Living Intelligence, formation cards, ranking engine |
| SelahScripture | 28 | Bible provider, spiritual notes, discernment checks |
| SupportIntelligence | 26 | Support tickets, AI support routing |
| Discussion | 13 | Discussion threads, message context, real-time |
| BereanDailyFormation | 10 | Daily formation cards, habit tracking |
| TrustOS | 9 | Trust scoring, signals, relationships |
| DevotionalGenerator | 7 | Dynamic devotional generation |
| Wellness | 6 | Mood tracking, risk assessment |
| TrustSignals | 6 | Signal collection, behavioral metadata |
| MessagingFilters | 6 | DM safety, mutual follow verification |
| BereanOnboarding | 6 | Formation onboarding flows |
| Berean | 6 | Legacy Berean integration |
| ActionThreads | 5 | Action reminders, task threads |
| SpacesOS | 4 | Community spaces, events |
| MessagingOS | 4 | Private messaging, DM coordination |
| Media | 4 | Media playback, transcript management |
| ContentFlowOS | 4 | Content pipeline, publishing |
| ChurchNotesOS | 4 | Church note aggregation |
| BereanPrayer | 4 | Prayer intercession, AI prayer |
| BereanMentorship | 4 | Mentorship requests, matching |
| SafetyOS | 3 | Safety reports, escalation |
| CompoundIdentityGraph | 3 | Social graph, follow relationships |
| RouterOS | 2 | Deep linking, route resolution |
| LivestreamOS | 2 | Live events, streaming |
| DiscoveryOS | 2 | Discovery algorithm |
| CreatorOS | 2 | Creator dashboard |
| CommunityIntelligenceOS | 2 | Community needs, distribution |

### Key Configuration Files

- **Info.plist:** `/AMENAPP/Info.plist` — App metadata, build configuration
- **Entitlements:** 
  - `/AMENAPP/AMENAPP.entitlements` (standard)
  - `/AMENAPP/AMENAPP.release.entitlements` (production)
  - Capabilities: App Groups, Push Notifications, Sign in with Apple, Background Modes (Fetch, Remote Notification)
- **Firestore Rules:** `/firestore.rules` (2,000+ lines, frozen contract C5 §2–7)
- **Remote Config:** Configured in AppDelegate via FirebaseRemoteConfig
- **Google Service Info:** `GoogleService-Info.plist` (Firebase project config)

### Key Root-Level Swift Files (AMENAPP/ folder)

**Core App Lifecycle:**
- `AMENAPPApp.swift` — App entry point, Firebase init, background tasks
- `AppDelegate.swift` — FCM, Crashlytics, RTDB persistence
- `ContentView.swift` — Root TabView, 8 tabs, auth gates

**Models & Services:**
- `Post.swift` — Post model, Firestore document
- `UserModel.swift` — User profile, entitlements
- `PremiumManager.swift` — StoreKit, subscriptions (com.amen.pro.{monthly,yearly,lifetime})
- `NotificationService.swift` — Firestore listener, badge counts
- `AuthenticationViewModel.swift` — Auth state machine
- `ContentViewModel.swift` — Tab selection, feed state

**Safety & Moderation:**
- `ModerationConstitutionModels.swift` — ZeroTolerance/HighRisk/Sensitive enums, EnforcementAction (0-5 ladder)
- `MinorSafetyService.swift` — Age gate, COPPA enforcement
- `PostTrustAnalysisService.swift` — Trust scoring for content

**Design System:**
- `AmenColorScheme.swift` — Adaptive colors (systemGroupedBackground migration)
- `AmenAdaptiveColors.swift` — Dark/light mode tokens
- `GlassMaterial.swift` — Liquid Glass, frosted effects

**Intelligence & Formation:**
- `BereanFaithOSContracts.swift` — CapabilityTier (FREE/PLUS/PRO), Memory kinds, Workspace kinds, Formation card kinds
- `ONEProvenanceModels.swift` — ONEProvenanceClass (captured/edited/aiAssisted/synthetic/unknown), ONEFeedModeKind, ONEReachBudget
- `TrueSourceModels.swift` — ProvenanceStatus, DistributionDecision
- `AmenJourneyEngine.swift` — User journey tracking
- `BehavioralAwarenessEngine.swift` — Session lifecycle, screen tracking

**Advanced Features:**
- `SabbathModeService.swift` — Sabbath config, sessions, reflections, presence
- `SundayChurchFocusManager.swift` — Sunday focus gate
- `AmenSimpleModeView.swift` — Accessibility mode
- `AppConfig.swift` — Feature flags, numeric limits

**File count breakdown by extension:**
- `.swift` files: 2,898 total
- Grouped by domain/product line (Creator, Berean, ChurchNotes, Spaces, etc.)
- No `.h` or `.m` Objective-C files (pure Swift codebase)

---

## Cloud Functions (functions/)

**Generation Split:**
- **Gen 1 (v1):** Inline definitions in `index.js`, older Node.js Cloud Functions API
- **Gen 2 (v2):** Inline definitions in `v2functions.js` and `v2triggers/` directory, modern Node.js v2 SDK

### Gen 2 Functions (v2functions.js)

Currently 1 merged trigger in `v2functions.js`:
- `onRealtimeCommentCreate` — Firestore-triggered, handles comments + replies

All other gen-2 functions are in `v2triggers/` directory (replicated for development/testing):
- `v2triggers/index.js`
- `v2triggers/v2functions.js`
- `v2triggers/v2entry.js` (entry point)

### Key Gen 1 Functions (index.js)

**Subscription & Payments:**
- `cancelAllSubscriptions` — Stripe subscription cancellation, context.auth gated
- `stripeWebhook` — Stripe webhook handler for charge updates, refunds, disputes

**Cloud Function Categories (200+ total):**

1. **Moderation & Safety:**
   - `aiModeration.js`, `imageModeration.js`, `moderatePost.js`, `moderateUGC.js`
   - `contentModeration.js`, `contentModerationTriggers.js`
   - `adminModerationFunctions.js`, `reportFunctions.js`
   - `ncmecReporter.js` — NCMEC CyberTipline integration

2. **AI & Intelligence (intelligence/ subdirectory):**
   - `amenLive.js`, `amenLiveCallable.js` — AMEN Live sessions
   - `churchPulse.js` — Church health metrics
   - `digestBuilder.js` — Intelligence brief generation
   - `worldResponse.js`, `worldResponseCallable.js` — Global response cards
   - `rankingBrain.js` — Ranking algorithm
   - `callModelRouter.js` — Model routing (Gemini/Claude/etc)
   - `prayerGraph.js` — Prayer intelligence
   - `needDetection.js` — Community needs classification
   - `opportunityGraph.js` — Opportunity ranking
   - `contracts.js` — Contract definitions (gen-2 only)

3. **Berean OS:**
   - `bereanFunctions.js`, `bereanFeaturesFunctions.js`
   - `bereanStudyFunctions.js`, `bereanRealtimeFunctions.js`
   - `berean_os_*.js` (advisory, debate, documents, graph, memory, mentor, perspectives, projects, research, sources, truth, wisdom)

4. **Church Notes:**
   - `churchNotesAICallables.js`, `churchNotesMediaPipeline.js`
   - `transcribeChurchNotesAudio.js`, `aiChurchNotes.js`

5. **Creator & Content:**
   - `creatorDraftFunctions.js`, `publishPipelineFunctions.js`
   - `studioFunctions.js`, `studioExport.js`, `studioImageGeneration.js`
   - `discussionFunctions.js`, `discussionContextFunctions.js`, `discussionDraftFunctions.js`

6. **Spaces & Events:**
   - `spacesFunctions.js`, `spacesEventsFunctions.js`, `spacesLiveFunctions.js`
   - `spacesStripeFunctions.js`, `spacesSafetyFunctions.js`

7. **Messaging & Communication:**
   - `communicationOS.js`, `commentGateway.js`
   - `discussionMediatorFunctions.js`, `discussionMemoryFunctions.js`

8. **User & Account:**
   - `userActivityFunctions.js`, `profilePropagation.js`
   - `accountDeactivation.js`, `accountDeletion.js`, `accountSubscriptionFunctions.js`
   - `twoFactorAuth.js`, `phoneAuthOnly.js`, `phoneAuthRateLimit.js`

9. **Notifications & Messaging:**
   - `pushNotifications.js`, `pushNotifications_enhanced.js`
   - `notificationRoutingPipeline.entry.ts` (TypeScript, notification coordination)
   - `notificationGrouping.js`, `notificationCleanup.js`
   - `engagementNotifications.js`

10. **Search & Discovery:**
    - `algoliaSync.js` — Algolia indexing
    - `search/catalogSearch.js`, `search/followKnowledge.js`

11. **Billing & Monetization:**
    - `stripeFunctions.js`, `stripeWebhook.js`
    - `billing/catalogEntitlements.js`, `billing/affiliateLinkWrapper.js`

12. **Catalogs & Knowledge:**
    - `catalog/catalogSchema.js`, `catalog/` — Catalog metadata
    - `ingestion/ingestionEngine.js`, `ingestion/importHub.js`
    - `ingestion/providers/{googleBooksProvider, podcastRSSProvider, spotifyProvider, substackProvider, youtubeProvider}.js`

13. **Other Specialized:**
    - `amenAIFeatures.js`, `aiPersonalization.js`, `aiProactiveFeatures.js`, `aiPromptFeatures.js`
    - `trustScore.js`, `trustScoreSystem.js` — Trust scoring
    - `livingMemory.js` — Memory graph features
    - `voicePrayer.js`, `ttsService.js` — Voice features
    - `nvidiaClient.js` — NVIDIA integration (likely deprecated/legacy)
    - `genkitFunctions.js` — Firebase Genkit integration
    - `reminderScheduler.js`, `maintenanceSchedulers.js`

### Provider Integrations (functions/selah/)

- `bibleProviderAdapter.js` — Bible content routing (YouVersion, OpenLicense, etc)
- `discernmentEngine.js` — Spiritual discernment checks
- `discernmentPrompts.js` — Prompt library
- `openLicenseVerseService.js` — Open License Bible API
- `selahCorpusService.js`, `selahCorpusUtils.js` — Bible corpus management

### Middleware & Auth

- `middleware/requireAuth.js` — Auth guard for callables
- `authHelpersV1.js`, `authenticationHelpers.js` — Auth utilities

### Testing & Configuration

- `test/`, `tests/` — Jest test suites for functions
- `.eslintrc.js` — Linting configuration
- `jest.config.js` — Jest configuration (in intelligence/ and v2triggers/)

### Environment & Configuration

- `.env.local.example` — Template for local emulator
  - `BEREAN_LLM_KEY` — Gemini API key
  - `EMBEDDING_KEY` — Embedding service key
  - `.env.local` is gitignored (secrets never committed)

---

## Firestore Collections (Extracted from firestore.rules)

**Total Unique Collections:** 50+

| Collection | Read Gate | Write Gate | CF-Only? |
|-----------|-----------|-----------|----------|
| users/{uid} | signed-in | owner (protected fields CF-only) | No |
| users/{uid}/private/age_assurance | owner | owner (CF-only for updates) | Partial |
| users/{uid}/safety/* | owner or admin | CF-only | Yes |
| users/{uid}/trust/* | owner | CF-only | Yes |
| users/{uid}/drafts/* | owner | CF-only | Yes |
| users/{uid}/media/* | owner | CF-only | Yes |
| users/{uid}/notifications/* | owner | CF-only (create), owner (delete) | Partial |
| users/{uid}/actions/* | owner | owner | No |
| posts/{postId} | privacy-gated | owner or moderator (soft-delete) | No |
| posts/{postId}/comments/* | signed-in | signed-in | No |
| prayers/{prayerId} | privacy-gated | owner | No |
| discussions/{discussionId} | privacy-gated | owner or moderator | No |
| conversations/{conversationId} | participant only | participant | No |
| churchNotes/{noteId} | owner/collaborator/admin | owner/collaborator | No |
| bereanInsights/{insightId} | owner/admin | CF-only | Yes |
| moderationQueue/{itemId} | moderator+ | moderator+ | No |
| auditLog/{eventId} | owner/executive_admin | CF-only (none) | Yes |
| spaces/{spaceId} | signed-in (minor gate: church-verified) | admin | No |
| events/{eventId} | signed-in | admin | No |
| jobs/{jobId} | signed-in (no minors) | admin | No |
| volunteerOpportunities/* | signed-in | admin | No |
| works/{workId} | signed-in (visibility gate) | creator (no self-publish) | No |
| knowledgeNodes/{nodeId} | creator only | creator | No |
| ingestionJobs/{jobId} | creator only | CF-only (status advance) | Yes |
| verificationClaims/{claimId} | creator/admin | CF-only (approval) | Yes |
| broadcastMessages/* | signed-in | admin | No |
| berean/{uid}/memory/* | owner | owner | No |
| berean/{uid}/messages/* | owner | owner (user role only) | No |
| one_moments/{momentId} | sender/recipient | CF-only | Yes |
| sabbathSessions/{sessionId} | owner | owner | No |
| sabbath/reflections/* | owner ONLY (no admin) | owner | No |
| amen_live_sessions/* | signed-in | CF-only | Yes |
| needs/{needId} | signed-in | CF-only | Yes |
| church_pulse/{churchId} | signed-in | CF-only | Yes |
| intelligence_cards/* | owner only | CF-only | Yes |
| intelligenceBriefs/* | owner only | CF-only | Yes |
| discernmentChecks/* | creator only | creator | No |

---

## Feature Flags & Configuration

### Remote Config Keys (AppDelegate.setupRemoteConfig)
- Located in Firebase Console under AMEN project
- Used for: AI API key rotation, feature gates, numeric limits

### In-App Purchase SKUs
- `com.amen.pro.monthly` — AMEN Pro monthly
- `com.amen.pro.yearly` — AMEN Pro yearly  
- `com.amen.pro.lifetime` — AMEN Pro one-time
- `com.amen.spaces.member.monthly` — Space membership
- `com.amen.spaces.founding.monthly` — Space founding member

### Numeric Limits (AppConfig.swift)
- URL cache: 200MB memory, 500MB disk
- Session timeout: 15 minutes
- FCM token refresh: on auth state change + foreground
- Background task: 5-second hard timeout

### Feature Enums
- **CapabilityTier:** FREE, PLUS, PRO
- **AgeTier:** adult, teen, under_minimum
- **OnEFeedMode:** close, create, learn, local, quiet
- **FormationCardKind:** scripture, reflection, prayer, habit, challenge, testimony, crisis (NO AI on crisis)
- **ProvenanceClass:** captured, edited, aiAssisted, synthetic, unknown (confidence < 0.70 → unknown)

---

## Security Invariants Enforced by Firestore Rules

| Code | Invariant | Scope |
|------|-----------|-------|
| I-1 | Soft-delete only (isDeleted: false→true, never reverse) | All content |
| I-2 | C-AUDIT mutations CF-batch-enforced | Audit trail |
| I-3 | [MINOR] Minors private by default; public requires publicConfirmed=true | Posts, prayers |
| I-4 | MFA/passkeys opt-in; no rule gates on MFA status | Users |
| I-5 | No raw PII (contactPhone, contactEmail, homeAddress, salaryAmount) | Opportunities, jobs |
| I-6 | ownerUidEncrypted never readable by any client | Prayers (anonymous) |
| I-7 | BereanInsight CF-write-only | Intelligence |
| I-8 | Age profile immutable by clients | users/{uid}/private/age_assurance |
| S-1 | Sabbath config/sessions/reflections owner-only | Sabbath |
| S-2 | Reflections NEVER readable by admin, CF, or cross-user | Sabbath reflections |
| S-4 | sabbathPresence.resting: text-only, never a count | Sabbath presence |
| B-1 | Berean per-user isolation | Berean |
| B-2 | Berean visibility default 'private' | Berean |
| B-3 | Minors: connectors denied, org/public writes denied | Berean |
| SE-1 | selahNotes owner-only; no hard deletes | Selah |

---

## Summary

- **2,898 Swift files** organized by product line (Creator, Berean, Spaces, ChurchNotes, etc)
- **200+ Cloud Functions** split between gen-1 (index.js) and gen-2 (v2functions.js + v2triggers/)
- **50+ Firestore collections** all governed by comprehensive rules in firestore.rules
- **8-tab TabView** root navigation in ContentView (Home, Discovery, Inbox, Resources, Notifications, Profile, Spaces, Intelligence)
- **5 capability tiers** across different product lines (Berean FREE/PLUS/PRO, Spaces free/member/founding)
- **3 age gates** enforced by Firestore rules + AuthViewModel (adult, teen, under_minimum)
- **No hardcoded API keys** in source; all credential management via Remote Config + .env.local (gitignored)

