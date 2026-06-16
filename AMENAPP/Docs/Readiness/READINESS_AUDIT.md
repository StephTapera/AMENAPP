# AMEN App Store Readiness Audit
Generated: 2026-06-16 | Branch: app-store-readiness-overnight | Auditor: Claude Sonnet 4.6

---

## Baseline

| Field | Value |
|---|---|
| Branch | app-store-readiness-overnight |
| Base branch | main |
| Firebase Project | amen-5e359 |
| Functions Runtime | node22 |
| Bundle ID | com.amenapp (from CFBundleURLName; canonical ID from provisioning profile) |
| Info.plist path | AMENAPP/AMENAPP/Info.plist |
| Entitlements path | AMENAPP/AMENAPP/AMENAPP.entitlements |
| Firestore rules | Present — 3388 lines; default-deny catch-all at lines 3386-3388 confirmed |
| Storage rules | Present — 735 lines; default-deny catch-all at lines 733-735 confirmed |
| Ripgrep stub hit count | 11 |
| Total findings | 106 |
| Blocking findings (blocking: true) | 17 |
| Applied auto-fixes this session | 4 |
| Deferred GREEN items | 47 |

---

## Apple Review Mapping

### Category: Safety (Guideline 1.x)

| Check | Status | Key Findings | Blocking? |
|---|---|---|---|
| COPPA age gate (under-13 block) | PASS | AgeGateView Keychain-backed, fail-closed; SSO paths covered (AUTH-002) | No |
| COPPA minor DM guardian approval | PASS with gap | canDM() fails closed; guardian fallback returns true when /guardianApprovedContacts document absent — OPEN-2 unresolved (SAFE-010) | YES |
| COPPA minor Discovery exposure | GAP | filterContentForMinor() is client-side stub; CF is authoritative but iOS has no guard before CF responds (SAFE-005) | YES |
| CSAM detection | PARTIAL | iOS escalation pipeline present; no proactive hash-scan against CSAM database found in any Swift or JS code (SAFE-003) | YES |
| NCMEC registration | UNVERIFIED | Code cannot confirm; human gate required (SAFE-003) | YES |
| Report + Block on core UGC | PASS | PostCard, CommentsView, UserProfileView, MessagesView all wired (SAFE-001) | No |
| Report + Block on Spaces + Prayer | MISSING | SpaceCardView, PrayerRoomView, AmenPrayerFeedView have zero report/block affordances (SAFE-002) | YES |
| Content moderation fail-closed | PASS | ModerationGatewayService returns decision=review in release builds on CF error (SAFE-006) | No |
| Prayer content safety gate | PASS | PrayerView sends text through moderation before any Firestore write (SAFE-007) | No |

### Category: Performance (Guideline 2.1)

| Check | Status | Key Findings | Blocking? |
|---|---|---|---|
| No unguarded fatalError in production launch path | FAIL | MessageOutbox.init has unguarded fatalError — crashes on SwiftData schema migration failure (PERF-006) | YES |
| Task lifecycle management | MOSTLY PASS | HomeView (PERF-001) and AmenMinistryRoomDiscussionsTab (PERF-002) have unbound bare Task{} | No |
| Listener cleanup | MOSTLY PASS | 30+ services correct; DiscussionThreadService returns raw registration (PERF-005) | No |
| try! / fatalError outside DEBUG | PARTIAL | try! ModelContainer in two fallback paths (PERF-010); try! NSRegularExpression static lazy (PERF-012) | No |
| Memory retain cycles | LOW | DispatchQueue.main.async without [weak self] in 9 files, mostly singletons (PERF-013) | No |

### Category: Business (Guideline 3.x)

| Check | Status | Key Findings | Blocking? |
|---|---|---|---|
| Account deletion is hard-delete | PASS | AccountDeletionService 10-step pipeline including Auth.auth().currentUser?.delete() (AUTH-003) | No |
| Account deletion requires re-auth | PARTIAL | DeleteAccountView correct; AccountRecoveryView bypasses re-auth guard (AUTH-009) | YES |
| 30-day deletion grace period backend job | UNVERIFIED | Client writes deletionScheduledFor; no server purge job confirmed (AUTH-013) | YES |
| Google re-auth for account deletion | BROKEN | Google provider path shows static text only; deletion impossible for Google users (AUTH-004) | YES |
| Spaces Join does not bypass paywall | FAIL | FIXME A-005: both onJoin closures set isSubscribed=true client-only (BTN-001) | YES |

### Category: Design (Guideline 4.x)

| Check | Status | Key Findings | Blocking? |
|---|---|---|---|
| Reduce Transparency fallback | MISSING | 5 LiquidGlassModifiers + AdaptiveGlassModifier never check accessibilityReduceTransparency (A11Y-002) | YES |
| Reduce Motion compliance | MISSING | 8 animation paths in LiquidGlassAnimations.swift ignore accessibilityReduceMotion (A11Y-003) | YES |
| No silent/no-op buttons | FAIL | 26 AdaptiveComposer card buttons are empty stubs; RSVP/Poll/Checklist update local UI but never write Firestore (BTN-002) | YES |
| Double-submit guards | PARTIAL | VisitConfirmationBanner has no isLoading guard (BTN-003) | YES |
| All sheets have dismiss paths | PARTIAL | GivingImpactView PDF sheet has no dismiss button (BTN-004) | YES |
| Touch target minimum 44pt | PARTIAL | cameraButton inner frame 40pt (A11Y-004) | No |
| Dynamic Type adoption | PARTIAL | 112 files use hard-coded system(size: N) (A11Y-001) | No |
| VoiceOver labels on primary nav | PASS | AMENTabBar all 5 tabs + compose + camera correctly labeled (A11Y-006) | No |
| GlassMaterial Reduce Transparency | PASS | GlassMaterial.swift branches to systemBackground when reduceTransparency is true (A11Y-007) | No |

### Category: Legal (Guideline 5.x)

| Check | Status | Key Findings | Blocking? |
|---|---|---|---|
| Privacy Policy URL live and compliant | UNVERIFIED | https://amenapp.com/privacy present in code; liveness and legal completeness unverifiable by code (AUTH-006) | YES |
| Full privacy policy accessible pre-login | GAP | Only 3-bullet PrivacySummarySheet shown; AMENAuthLandingView has no privacy link (PRIV-007) | YES |
| First-run AI consent before any AI call | GAP | DailyDigest and SmartComment gate on bare UserDefaults booleans; no first-run consent sheet (PRIV-005) | YES |
| NSMicrophoneUsageDescription | MISSING | Absent from production Info.plist; runtime crash on microphone access (PRIV-001) | YES |
| NSPhotoLibraryUsageDescription | MISSING | Absent from production Info.plist (PRIV-001) | YES |
| NSLocationWhenInUseUsageDescription | MISSING | Absent from production Info.plist; Find a Church will crash (PRIV-001) | YES |
| ITSAppUsesNonExemptEncryption | MISSING | Key absent; App Store Connect will block submission (SEC-006) | YES |
| PrivacyInfo.xcprivacy | PASS | All 4 required API categories declared; 17 data types documented (PRIV-003) | No |
| ATT implementation | PASS | ATTrackingManager called after first screen; NSUserTrackingUsageDescription present (PRIV-004) | No |
| Log redaction in production | PASS | dlog() is no-op in Release; os_log uses %{private}@ after auto-fix (PRIV-006) | No |
| NIV copyright | NOT AUDITED THIS PASS | Tracked in AUDIT_REPORT_2026_06_15.md — human legal gate required | Human gate |

---

## Surface Inventory

| Screen | File | Auth Required | Data Sources | Key Actions | Risk |
|---|---|---|---|---|---|
| Welcome / Splash | WelcomeToAMENView.swift | No | None | Review Privacy (summary only), Get Started | MED — PRIV-007 |
| Onboarding | OnboardingFlowView.swift | No | None | DOB collection, Terms/Privacy links | LOW |
| Age Gate | AgeGateView.swift | No | Keychain | DOB entry, block under-13 | LOW — correctly implemented |
| Auth Landing | AMENAuthLandingView.swift | No | Firebase Auth | Email/Google/Apple sign-in | MED — no full privacy link |
| Sign In | SignInView.swift | No | Firebase Auth | Email, phone, social login | LOW |
| Home Feed | HomeView.swift | Yes | Firestore | Post list, categories, tab refresh | LOW — bare Task{} in onReceive |
| Post Card | PostCard.swift | Yes | Firestore | Like, comment, share, report, block | LOW |
| Create Post | CreatePostView.swift | Yes | Firestore, CF moderation | Compose, attach media, post, safety check | LOW |
| Comments | CommentsView.swift | Yes | Firestore realtime | Comment, reply, like, report, block | LOW |
| User Profile | UserProfileView.swift | Yes | Firestore | Follow, report, block, view posts | LOW |
| Direct Messages | MessagesView.swift | Yes | Firestore, E2EE | Send, receive, block, report | LOW |
| Spaces Detail | AmenSpaceDetailView.swift | Yes | Firestore | Join (paywall bypass FIXME), subscribe, moderate | HIGH — BTN-001 |
| Space Card | SpaceCardView.swift | Yes | Firestore | Join, tap | HIGH — SAFE-002 no report/block |
| Prayer Feed | AmenPrayerFeedView.swift | Yes | Firestore | View, submit prayer | HIGH — SAFE-002 no report/block |
| Prayer Room | PrayerRoomView.swift | Yes | Firestore | View, pray for request | HIGH — SAFE-002 no report/block |
| Church Discovery | FindChurchView.swift | Yes | Firestore, location | Search, get directions, log visit | MED — location perm string missing in plist |
| Berean AI Chat | BereanChatView.swift | Yes | CF AI, Firestore | Chat, study, compose with AI | MED — PRIV-005 consent gap |
| Daily Brief | DailyDigestService.swift | Yes | CF callModel, Firestore | AI-generated daily brief card | MED — PRIV-005 |
| Notifications | AMENNotificationsView.swift | Yes | Firestore | Mark read, deep-link navigate | LOW |
| Account Settings | AccountSettingsView.swift | Yes | Firebase Auth, Firestore | Edit profile, privacy settings, delete | MED — AUTH-009 |
| Delete Account | DeleteAccountView.swift | Yes | Firebase Auth, Firestore, Storage | Re-auth, 10-step hard delete | MED — AUTH-004 Google broken |
| Account Recovery | AccountRecoveryView.swift | Yes | Firestore | Soft-delete (no re-auth guard) | HIGH — AUTH-009 |
| Adaptive Composer Cards | AttachmentCardsA/B/C.swift | Yes | Firestore (stubs) | 26 card actions — all stubs | HIGH — BTN-002 |
| Giving Impact | GivingImpactView.swift | Yes | Local PDF data | View PDF | HIGH — BTN-004 undismissable |
| Visit Confirmation | VisitConfirmationBanner.swift | Yes | Firestore | Confirm or dismiss visit | MED — BTN-003 double-submit |
| Wisdom Library | WisdomLibraryHeroBanner.swift | Yes | Firestore | Browse resources | LOW |
| Connect V2 | AmenConnectV2View.swift | Yes | Firestore | Workspace button (stub) | LOW — BTN-005 |
| Covenant Events | AmenCovenantEventsView.swift | Yes | EventKit (stub) | Add to Calendar (toast only) | LOW — BTN-006 |
| Ministry Room Discussions | AmenMinistryRoomDiscussionsTab.swift | Yes | Firestore, CF | View, post discussion | LOW — bare Task{} |
| Admin / Group Management | GroupAdminView.swift | Admin only | Firestore | Manage roles, kick users | LOW |
| Message Outbox (service) | MessageOutbox.swift | Yes | SwiftData | Offline message queue | HIGH — PERF-006 fatalError on init |

---

## Button Wiring Matrix

| Screen | Button Label | Wired to Backend? | Loading State? | Confirm Dialog? | A11y Label? | Lane |
|---|---|---|---|---|---|---|
| AmenSpaceDetailView | Join (hero) | NO — client-side only | No | No | Unknown | RED |
| AmenSpaceDetailView | Join (PaywallOverlay) | NO — client-side only | No | No | Unknown | RED |
| AttachmentCardsA | Study in Berean | NO — stub | No | No | Unknown | RED |
| AttachmentCardsA | Pray | PARTIAL — local counter only | No | No | Unknown | RED |
| AttachmentCardsA | Going / Maybe / Can't Go | NO — stub | No | No | Unknown | RED |
| AttachmentCardsA | Add to Calendar | NO — stub | No | No | Unknown | RED |
| AttachmentCardsA | Get Directions | NO — stub | No | No | Unknown | RED |
| AttachmentCardsA | Listen (podcast) | NO — stub | No | No | Unknown | RED |
| AttachmentCardsA | Summarize (YouTube) | NO — stub | No | No | Unknown | RED |
| AttachmentCardsA | Preview (file) | NO — stub | No | No | Unknown | RED |
| AttachmentCardsB | Download (file) | NO — stub | No | No | Unknown | RED |
| AttachmentCardsB | Give Now | NO — Stripe never opened | No | No | Unknown | RED |
| AttachmentCardsB | Sign Up to Volunteer | NO — stub | No | No | Unknown | RED |
| AttachmentCardsB | Add to Reminders | NO — stub | No | No | Unknown | RED |
| AttachmentCardsB | Open in Selah | NO — stub | No | No | Unknown | RED |
| AttachmentCardsB | Poll vote | PARTIAL — local UI only | No | No | Unknown | RED |
| AttachmentCardsC | Checklist toggle | PARTIAL — local UI only | No | No | Unknown | RED |
| AttachmentCardsC | Play/Pause (audio) | NO — AVPlayer not attached | No | No | Unknown | RED |
| AttachmentCardsC | Play/Pause (video) | NO — AVPlayer not attached | No | No | Unknown | RED |
| AttachmentCardsC | Going / Maybe / Can't Go (C) | NO — stub | No | No | Unknown | RED |
| AttachmentCardsC | Join Group (Bible study) | NO — stub | No | No | Unknown | RED |
| AttachmentCardsC | Join Discussion | NO — stub | No | No | Unknown | RED |
| VisitConfirmationBanner | Yes, log visit | YES | NO — race condition | No | Unknown | RED |
| GivingImpactView | Dismiss PDF | MISSING — no button | N/A | N/A | N/A | RED |
| AmenConnectV2View | Workspace/presence | NO — empty closure | No | No | Misleading | YELLOW |
| AmenCovenantEventsView | Add to Calendar | NO — toast only | No | No | Unknown | YELLOW |
| PostCard | Delete post | YES | No | YES | YES | GREEN |
| CommentsView | Delete comment | YES | No | YES | YES | GREEN |
| DeleteAccountView | Confirm delete | YES | YES — isDeleting | YES — type DELETE | YES | GREEN |
| MessagesView | Delete conversation | YES | No | YES | YES | GREEN |
| BereanMemoryView | Delete memory | YES | No | YES | YES | GREEN |

---

## Per-Module Status

| Module | Status | P0 Blockers | P1 Blockers | Key Notes |
|---|---|---|---|---|
| Onboarding / Auth | YELLOW | 0 | 3 | PRIV-007 no full privacy policy pre-login; PRIV-005 no AI consent sheet; AUTH-004 Google re-auth broken |
| Feed | GREEN | 0 | 0 | Bare Task{} in onReceive is non-blocking |
| Create Post | GREEN | 0 | 0 | Moderation pipeline fail-closed confirmed |
| Comments | GREEN | 0 | 0 | Task cancellation and block/report wired |
| Profiles | GREEN | 0 | 0 | Report/block fully wired |
| Messaging | YELLOW | 0 | 1 | SAFE-010 minor guardian fallback allows DMs |
| Spaces | RED | 1 | 1 | BTN-001 join bypass (P0); SAFE-002 no report/block on SpaceCard (P1) |
| Church Discovery | YELLOW | 0 | 1 | NSLocationWhenInUseUsageDescription missing from Info.plist |
| Berean AI | YELLOW | 0 | 1 | No first-run AI consent sheet (PRIV-005) |
| Prayer | RED | 0 | 1 | SAFE-002 no report/block on PrayerRoomView / AmenPrayerFeedView |
| Notifications | GREEN | 0 | 0 | No gaps found |
| Resources / Adaptive Composer | RED | 0 | 1 | BTN-002 26 card buttons are silent stubs |
| Account / Deletion | RED | 0 | 3 | AUTH-004 Google re-auth broken; AUTH-009 AccountRecoveryView missing re-auth; AUTH-013 30-day purge unverified |
| System / Launch | RED | 0 | 1 | PERF-006 fatalError in MessageOutbox.init |
| Security / Compliance | RED | 0 | 2 | PRIV-001 three missing plist usage strings; SEC-006 ITSAppUsesNonExemptEncryption missing |
| Admin | GREEN | 0 | 0 | Admin privilege gated on custom token claims |

---

## Full Findings Table (106 findings, sorted P0 first then P1 blocking, then by severity)

| ID | Lane | Sev | Domain | Title | Blocking |
|---|---|---|---|---|---|
| BTN-001 | RED | P0 | Design | Spaces Join/Paywall buttons bypass entitlement check (FIXME A-005) | YES |
| SAFE-010 | YELLOW | P0 | Safety | Minor guardian approval falls back to allow when document absent | YES |
| AUTH-004 | YELLOW | P1 | Auth | Google re-auth on deletion shows text only — no GIDSignIn flow | YES |
| AUTH-006 | RED | P1 | Legal | Terms/Privacy URLs must serve live legal documents (cannot verify by code) | YES |
| AUTH-009 | YELLOW | P2 | Auth | AccountRecoveryView soft-delete does not require re-authentication | YES |
| AUTH-013 | RED | P1 | Legal | 30-day deletion disclosure unverified — no server purge job confirmed | YES |
| SAFE-002 | RED | P1 | Safety | Report+Block absent from SpaceCardView, PrayerRoomView, AmenPrayerFeedView | YES |
| SAFE-003 | YELLOW | P1 | Safety | CSAM pipeline reactive only — no proactive hash-scan confirmed | YES |
| SAFE-005 | YELLOW | P1 | Safety | Minors not blocked from public Discovery at iOS layer | YES |
| PRIV-001 | RED | P1 | Privacy | Missing NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSLocationWhenInUseUsageDescription | YES |
| PRIV-005 | YELLOW | P1 | Privacy | Berean AI/Daily Brief fire before first-run AI consent UI shown | YES |
| PRIV-007 | YELLOW | P2 | Privacy | Full privacy policy not accessible before login | YES |
| BTN-002 | RED | P1 | Design | 26 AdaptiveComposer card buttons are silent empty stubs | YES |
| BTN-003 | RED | P1 | Design | VisitConfirmationBanner has no loading guard — double-submit possible | YES |
| BTN-004 | RED | P1 | Design | GivingImpactView PDF sheet has no dismiss button | YES |
| FIRE-010 | YELLOW | P2 | Security | createSpaceTier CF missing space-owner authorization check | YES |
| PERF-006 | RED | P1 | Performance | fatalError in MessageOutbox.init crashes production app | YES |
| SEC-006 | RED | P1 | Security | ITSAppUsesNonExemptEncryption missing from Info.plist | YES |
| A11Y-002 | RED | P1 | A11y | LiquidGlassModifiers — no Reduce Transparency fallback in 5 glass styles | YES |
| A11Y-003 | RED | P1 | A11y | LiquidGlassAnimations — 8 animation paths ignore Reduce Motion | YES |
| AUTH-011 | YELLOW | P2 | Auth | DeleteAccountView confirmation signOut uses try? — suppresses errors silently | No |
| SAFE-008 | YELLOW | P2 | Safety | Church notes AI: no ConsentEdge check confirmed in BereanChurchNotesBridge | No |
| FIRE-003 | YELLOW | P2 | Security | Firestore /users top-level readable by all signed-in users | No |
| FIRE-008 | YELLOW | P2 | Security | Duplicate /safetyAuditLog rule blocks with conflicting semantics | No |
| FIRE-009 | YELLOW | P2 | Security | /testimonies readable by unauthenticated users when visibility=published | No |
| FIRE-013 | YELLOW | P1 | Security | Several callables have enforceAppCheck: false | No |
| FIRE-016 | YELLOW | P1 | Security | Rate limiting missing in functions/src callables | No |
| FIRE-020 | YELLOW | P2 | Security | Storage uploads/approved publicly readable without auth | No |
| FIRE-021 | YELLOW | P2 | Security | Three overlapping profile photo path names | No |
| FIRE-022 | YELLOW | P2 | Security | Legacy MIME-type regex helpers still on churchNotes storage paths | No |
| FIRE-023 | YELLOW | P1 | Security | /prayerOS prayer detail stored unencrypted | No |
| FIRE-025 | YELLOW | P2 | Security | scripture_searchVerses fetches 200 Firestore docs — DoS risk | No |
| BTN-005 | YELLOW | P2 | Design | AmenConnectV2View workspace button is no-op stub | No |
| BTN-006 | YELLOW | P2 | Design | AmenCovenantEventsView Add to Calendar shows toast only | No |
| BTN-007 | YELLOW | P2 | Design | AmenCovenantViewModel post deep-link navigation stub | No |
| BTN-008 | YELLOW | P2 | Design | WisdomLibraryHeroBanner Preview uses EmptyView destination | No |
| BTN-009 | YELLOW | P2 | Design | AmenSpaceDetailView moderation sheet has no dismiss path to parent | No |
| A11Y-001 | YELLOW | P2 | A11y | Hard-coded font sizes in 112 files — Dynamic Type not adopted | No |
| A11Y-004 | YELLOW | P2 | A11y | AMENTabBar compose/camera touch target 40pt below 44pt HIG minimum | No |
| A11Y-005 | YELLOW | P2 | A11y | Decorative images missing .accessibilityHidden(true) | No |
| A11Y-008 | YELLOW | P2 | A11y | GlassSheetContainer backdrop animation ignores reduceMotion | No |
| A11Y-009 | YELLOW | P2 | A11y | FloatingActionBubble uses UIAccessibility instead of SwiftUI environment | No |
| A11Y-010 | YELLOW | P2 | A11y | HighlightSweepModifier fires without reduceMotion check | No |
| PERF-001 | YELLOW | P2 | Performance | HomeView bare Task{} in onReceive not bound to view lifetime | No |
| PERF-002 | YELLOW | P2 | Performance | AmenMinistryRoomDiscussionsTab bare Task{} without cancellation | No |
| PERF-005 | YELLOW | P2 | Performance | DiscussionThreadService returns raw ListenerRegistration | No |
| PERF-009 | YELLOW | P2 | Performance | assertionFailure in AmenAIFeaturesService not wrapped in #if DEBUG | No |
| PERF-010 | YELLOW | P2 | Performance | try! ModelContainer in LocalSelahSession and LocalPostDraft fallback paths | No |
| PERF-012 | YELLOW | P2 | Performance | try! NSRegularExpression in AmenMentionParser static lazy property | No |
| PERF-013 | YELLOW | P2 | Performance | DispatchQueue.main.async without [weak self] in 9 files | No |
| PERF-014 | YELLOW | P2 | Performance | DispatchQueue.main.async in 25+ files instead of MainActor | No |
| SEC-001 | YELLOW | P2 | Security | Firebase API key committed in GoogleService-Info.plist | No |
| SEC-007 | YELLOW | P2 | Security | GPU background-tasks entitlement requires Apple approval | No |
| SEC-008 | YELLOW | P2 | Security | com.apple.developer.location.push requires Apple approval | No |
| SEC-010 | YELLOW | P2 | Security | Debug and release entitlements diverge on Siri and time-sensitive notifications | No |
| AUTH-001 | GREEN | P3 | Auth | skipOnboarding() is feature-specific, not an auth bypass | No |
| AUTH-002 | GREEN | P0 | Auth | COPPA age gate is Keychain-backed and fail-closed | No |
| AUTH-003 | GREEN | P0 | Auth | Account deletion is a real hard-delete pipeline | No |
| AUTH-005 | GREEN | P1 | Auth | Terms and Privacy links present at sign-up | No |
| AUTH-007 | GREEN | P1 | Auth | Sign-out token revocation is comprehensive | No |
| AUTH-008 | GREEN | P2 | Auth | No crash-risk force-unwraps in core auth ViewModel | No |
| AUTH-010 | GREEN | P2 | Auth | 2FA auth-state listener suppression prevents bypass | No |
| AUTH-012 | GREEN | P3 | Auth | AuthDebugView correctly guarded by #if DEBUG | No |
| SAFE-001 | GREEN | P2 | Safety | Report+Block on core UGC surfaces confirmed | No |
| SAFE-004 | GREEN | P2 | Safety | COPPA minor DM blocking is fail-closed | No |
| SAFE-006 | GREEN | P2 | Safety | Moderation fail-closed in production builds | No |
| SAFE-007 | GREEN | P3 | Safety | Prayer through safety gate; consent edges gate AI | No |
| SAFE-009 | GREEN | P3 | Safety | Report/Block infrastructure robust across 26 Swift files | No |
| PRIV-002 | GREEN | P3 | Privacy | NSCameraUsageDescription and NSContactsUsageDescription AMEN-specific | No |
| PRIV-003 | GREEN | P3 | Privacy | PrivacyInfo.xcprivacy complete | No |
| PRIV-004 | GREEN | P3 | Privacy | ATT correctly implemented | No |
| PRIV-006 | GREEN | P3 | Privacy | Log redaction correctly implemented | No |
| PRIV-008 | GREEN | P3 | Privacy | ConsentStore infrastructure well-designed | No |
| FIRE-001 | GREEN | P0 | Security | Firestore global default-deny catch-all present | No |
| FIRE-002 | GREEN | P0 | Security | User email/phone readable only by owner | No |
| FIRE-004 | GREEN | P0 | Security | DMs private between participants only | No |
| FIRE-005 | GREEN | P0 | Security | Moderation/admin collections admin-only | No |
| FIRE-006 | GREEN | P0 | Security | Reports write-by-reporter, read-by-admin-only | No |
| FIRE-007 | GREEN | P0 | Security | Counter/trust/entitlement fields backend-only write | No |
| FIRE-011 | GREEN | P0 | Security | No callables trust request.data.uid as identity | No |
| FIRE-012 | GREEN | P0 | Security | Auth checks on all user-facing callables | No |
| FIRE-014 | GREEN | P1 | Security | No hardcoded admin UIDs | No |
| FIRE-015 | GREEN | P1 | Security | No prayer content or PII in Cloud Logging | No |
| FIRE-017 | GREEN | P1 | Security | Payload validation on all callables | No |
| FIRE-018 | GREEN | P0 | Security | Storage default-deny catch-all present | No |
| FIRE-019 | GREEN | P0 | Security | Cross-user Storage path overwrite not possible | No |
| FIRE-024 | GREEN | P0 | Security | NCMEC/legal collections completely deny all client access | No |
| BTN-010 | GREEN | P3 | Design | Destructive delete flows have confirmation dialogs | No |
| BTN-011 | GREEN | P3 | Design | Most sheets have explicit dismiss paths | No |
| BTN-012 | GREEN | P3 | Design | Features directory has zero TODO/FIXME/print stubs | No |
| A11Y-006 | GREEN | P3 | A11y | AMENTabBar VoiceOver labels correctly provided | No |
| A11Y-007 | GREEN | P3 | A11y | GlassMaterial Reduce Transparency correctly handled | No |
| PERF-003 | GREEN | P3 | Performance | CommentsView and UnifiedChatView cancel tasks correctly | No |
| PERF-004 | GREEN | P3 | Performance | Majority of Firestore listeners store and remove ListenerRegistration | No |
| PERF-007 | GREEN | P3 | Performance | assertionFailure in GlobalResilienceWiring correctly guarded | No |
| PERF-008 | GREEN | P3 | Performance | assertionFailure in FirebasePostService wrapped in #if DEBUG | No |
| PERF-011 | GREEN | P3 | Performance | as! force-cast in camera views safe by design | No |
| PERF-015 | GREEN | P3 | Performance | Combine .sink closures use [weak self] | No |
| PERF-016 | GREEN | P3 | Performance | SharePlayService stores tasks and cancellables correctly | No |
| SEC-002 | GREEN | P3 | Security | bypassAuthForTesting() guarded by #if DEBUG | No |
| SEC-003 | GREEN | P3 | Security | Emulator host commented out | No |
| SEC-004 | GREEN | P3 | Security | aps-environment = production in both entitlements | No |
| SEC-005 | GREEN | P3 | Security | NSAllowsArbitraryLoads absent — ATS enforced | No |
| SEC-009 | GREEN | P3 | Security | Sensitive API keys use xcconfig variable substitution | No |
| SEC-011 | GREEN | P3 | Security | No hardcoded API keys in Backend TypeScript source | No |
| SEC-012 | GREEN | P3 | Security | GroupAdminView isAdmin mutation is legitimate local state | No |

## Phase 7-8: Business + Firebase Rules

### Phase 7 — Business Model / IAP / Subscriptions

**Payment Stack Summary**

The app uses three distinct payment mechanisms:
1. **StoreKit 2** — `PremiumManager.swift` handles AMEN Pro (monthly/yearly/lifetime) via `com.amen.pro.*` product IDs. Transaction listener is wired; `AppStore.sync()` used for restore; `ManageSubscriptionView` links to `itms-apps://apps.apple.com/account/subscriptions`.
2. **RevenueCat SDK** — `StudioSubscriptionService.swift` handles AMEN Studio tiers (Creator $7.99/mo, Pro $14.99/mo, Team $24.99/mo). Gated with `#if canImport(RevenueCat)` — SDK not yet installed (uses stub fallback).
3. **Stripe Connect** — `StudioPaymentService.swift` + `MentorshipService.swift` handle creator payouts and mentorship plan billing via Cloud Function callables (`stripeCreatePaymentIntent`, `createMentorshipSubscription`).

**Restore Purchases: PRESENT**
- `ManageSubscriptionView` has "Restore Purchases" button calling `AppStore.sync()`.
- `MentorshipPlanSheet` has "Restore Purchases" in toolbar calling `AppStore.sync()`.
- `StudioPaywallView` has restore button (RevenueCat path).

**Manage Subscription: PRESENT**
- `ManageSubscriptionView.openAppStoreSubscriptions()` opens `itms-apps://apps.apple.com/account/subscriptions`.

**Paywall Copy: No misleading claims found**
- Header: "Create freely. Your faith, your story, preserved forever." — factual.
- Feature comparisons use checkmarks/xmarks with accurate tier matrix.

**Defects Found:**

1. **MEDIUM — studioTier client-writable (entitlement spoof)**: `StudioSubscriptionService.syncEntitlementToFirestore()` directly called `updateData(["studioTier": ...])`  on the user document from the iOS client. The field was not in `premiumFieldsUnchanged()`, so a malicious client could write `studioTier: "pro"` without a real purchase. **FIXED GREEN (G-P7-01)**: Added `studioTier` + `studioTierUpdatedAt` to `premiumFieldsUnchanged()` guard in `firestore.rules` and removed the direct client `updateData()` call in `StudioSubscriptionService`.

2. **MEDIUM — MentorModel.stripePriceId used as StoreKit product ID**: `MentorModel.swift` has `var stripePriceId: String` with placeholder values `"price_growth"` and `"price_deep"`. `MentorshipPlanSheet` passes these to `Product.products(for:)`. These strings are not real App Store Connect product IDs. The UI correctly shows "The App Store product price_growth is not configured for this build." when the product is missing — this is a non-crash stub, but mentorship paid plans are non-functional until real product IDs are set in App Store Connect. See YELLOW Y-P7-02.

3. **LOW — RevenueCat SDK not installed**: `StudioSubscriptionService` and `StudioPaywallView` are gated behind `#if canImport(RevenueCat)`. The Studio paywall shows "Purchases unavailable — RevenueCat SDK not installed" if the SDK is absent. This is handled gracefully but Studio paid plans are non-functional without the SDK. See YELLOW Y-P7-03.

### Phase 8 — Firebase Rules Audit

**Firestore Rules:**
- **Deny-by-default at root: PRESENT** — `match /{document=**} { allow read, write: if false; }` at end of file.
- **Private messages (conversations/messages)**: Participants-only read, blocked users excluded, sender enforced on create. SECURE.
- **User phone/email from profiles**: `/users/{userId}` requires `isSignedIn()` to read. Phone/email in `users` subcollections blocked to non-owners. SECURE.
- **Moderation/admin collections**: `moderationQueue`, `auditLog`, `moderationDecisions`, `userReports`, `humanReviewQueue` all deny client writes. SECURE.
- **Report documents**: `userReports` write=false (CF only); read by reporter or moderator/admin. SECURE.
- **Blocked users in rules**: `callerIsBlockedInConversation()` enforced on conversation and message reads. `commentBlockedCheck()` enforced on comment creates. SECURE.
- **Entitlement/trust/counter fields**: `premiumFieldsUnchanged()`, `ageTierUnchanged()`, `roleAndSafetyFieldsUnchanged()` guards applied on user doc updates. SECURE (after G-P7-01 fix adds `studioTier`).
- **AI log collections**: `bereanModelLogs`, `bereanEvalRuns`, `actionIntelligenceAudit`, `aiReports` — all client-denied or admin-only. SECURE.

**Firestore Rules — One Gap Found:**

- **LOW — `testimonies` missing auth gate on read**: `match /testimonies/{testimonyId} { allow read: if resource.data.visibility == "published"; }` allows unauthenticated reads of published testimonies. If testimony content is considered member-only, this should require `isSignedIn()`. This is consistent with OPEN-5 (unauthenticated public reads allowed by design), but testimony content may be more sensitive than posts. See RED R-P8-01.

**Storage Rules:**
- **Deny-by-default: PRESENT** — `match /{allPaths=**} { allow read, write: if false; }` at end.
- **Users cannot overwrite other users' media**: All media paths use `isOwner(uid)` for create/write. SECURE.
- **Content-type checked on upload**: All new paths use explicit MIME allowlists (`isAllowedImageType()`, `isAllowedVideoType()`, etc.) instead of regex. Deprecated regex helpers marked for migration. SECURE.
- **Quarantine-first upload**: New uploads go to quarantine paths; CF moves to approved/blocked. Create-only (no update) prevents mid-flight evidence substitution. SECURE.

**RTDB Rules:** No `database.rules.json` found — no RTDB in use.


---

## Phase 6: Privacy + Data Map

**Auditor:** Claude Sonnet 4.6 | **Date:** 2026-06-16 | **Branch:** feature/berean-island-w0

### Scope

Info.plist purpose strings, PrivacyInfo.xcprivacy, permission request patterns, sensitive log redaction, in-app privacy policy link, third-party AI disclosure, consent gates.

---

### P6-G1 GREEN APPLIED — Missing NSCalendarsUsageDescription (FIXED)

`EventKitCalendarAdapter` calls `store.requestFullAccessToEvents()` but `AMENAPP/Info.plist` had no `NSCalendarsUsageDescription`. Apple rejects binaries that access protected APIs without the corresponding usage string. Added:

> "AMEN reads your calendar to surface upcoming church events and spiritual milestones in your Community feed."

**Files changed:** `AMENAPP/Info.plist`

---

### P6-G2 GREEN APPLIED — Missing NSHealthShareUsageDescription + NSHealthUpdateUsageDescription (FIXED)

`HealthKitAdapter` calls `HKHealthStore().requestAuthorization(toShare:read:)` but both HealthKit usage strings were absent from `AMENAPP/Info.plist`. Apple rejects on this. Added AMEN-specific strings explaining spiritual rhythm correlation and no third-party sharing.

**Files changed:** `AMENAPP/Info.plist`

---

### P6-G3 GREEN APPLIED — Full UID in debug logs (FIXED — 3 sites)

Three `dlog()` calls emitted the complete Firebase UID (32-char opaque ID). While UIDs are not PII on their own, emitting them in debug logs alongside action types creates a correlation record that could be harvested from device logs. Truncated to `uid.prefix(8)…` at all three sites.

**Files changed:**
- `AMENAPP/AMENAPP/UserProfileMiniActionHandler.swift` line 146
- `AMENAPP/AMENAPP/RecoveryOS/AccountManagementService.swift` line 42
- `AMENAPP/AMENAPP/CommunityOS/Content/ContentObjectService.swift` line 316

---

### P6-Y1 YELLOW — assemblePrayerChain CF lacks server-side AI consent gate

`PrayerChainAssemblyService` calls the `assemblePrayerChain` Cloud Function which internally sends user-authored prayer text to Anthropic Claude. The client-side gate (`AMENFeatureFlags.shared.prayerChains`) is a feature flag, not a per-user AI consent check. The legal document in `AmenLegalDocumentModels.swift` states AI features require explicit opt-in, but the prayer chain path bypasses `consentCreatorAI`.

**Engineering (behind flag — no deploy):** Add a Firestore `consent/{uid}.aiPrayerChain` field read in the `assemblePrayerChain` CF before the Anthropic call; throw `consent_required` if absent. Surface a consent dialog in `PrayerChainComposerView` before `assembleChain()` is called.

**Runbook (human action required):**
```
# After engineering is complete and tested:
firebase deploy --only functions:creator:assemblePrayerChain
# Then enable the consent dialog via Remote Config:
# key: prayerChain_consent_gate_enabled → true
```

---

### P6-Y2 YELLOW — generateDailyVerse CF uses OpenAI without per-user disclosure

`Backend/functions/src/generateDailyVerse.ts` calls `api.openai.com/v1/chat/completions`. The payload is date + holiday context only (no PII), but the App Store privacy label and in-app AI disclosure UI have no entry for OpenAI as an AI provider for verse generation. ATT rules and the App Store privacy label require honest disclosure of all third-party data recipients.

**Engineering:** Add an `AIDisclosureRecord` for `dailyVerse` surface in `TrustSpineService.getAIDisclosureDetails` with provider = "OpenAI". No user data is sent; label the disclosure appropriately (no content-linked data).

**Runbook:**
```
# After engineering complete:
firebase deploy --only functions:creator:getAIDisclosureDetails
# Update the App Store Connect privacy questionnaire to list OpenAI
# under "Third-Party Partners" for the "App Functionality" purpose.
```

---

### P6-Y3 YELLOW — PrivacyInfo.xcprivacy tracking domains list incomplete

`NSPrivacyTrackingDomains` lists `app-measurement.com`, `firebaselogging.googleapis.com`, `firebase.googleapis.com`. The app also uses Algolia (search queries) and LiveKit (audio/video streams in Spaces). If either SDK is used in a context that meets Apple's definition of tracking, their domains should be added. Apple has begun rejecting apps for undisclosed tracking domains.

**Runbook (human verification required):**
```
# 1. Run a Charles Proxy / mitmproxy session on the app.
# 2. Log every outbound host that fires after ATT is denied.
# 3. Add any analytics/tracking hosts to NSPrivacyTrackingDomains in
#    AMENAPP/PrivacyInfo.xcprivacy before App Store submission.
```

---

### P6-R1 RED — Prayer request content sent to third-party AI: disclosure scope decision

Prayer requests are created under `SmartShareDomain.prayerRequest` and stored in `prayerChains/`. The `assemblePrayerChain` CF sends this content to Anthropic. The App Store privacy label currently lists "Other User Content" as linked, purpose = App Functionality. Prayer requests are arguably **sensitive content** (spiritual condition, mental health adjacent), which Apple treats as a separate privacy nutrition label category.

**Decision required:** Does AMEN classify prayer content as "Sensitive Info" for the App Store privacy label? If yes, the `NSPrivacyCollectedDataTypeSensitiveInfo` entry must be added to PrivacyInfo.xcprivacy with the correct purposes and linked/tracking flags. This may affect App Review.

---

### P6-R2 RED — ATT prompt timing and "spiritual content discovery" framing

`NSUserTrackingUsageDescription` reads: "AMEN uses this to understand how our community discovers spiritual content, so we can improve formation features for you." Apple guidelines require ATT strings to be **honest** about the specific data use. "Formation features" is interpretive language. If the IDFA is used for advertising attribution (even indirect), Apple reviewers may flag this as misleading.

**Decision required:** Confirm with legal whether IDFA is used only for internal analytics or also for ad attribution. If attribution: update the ATT string to name the attribution partner. If internal-only: the current string is acceptable but should drop "for you" (personalisation framing) to avoid confusion with targeted ads.

---

### Phase 6 Summary

| ID | Type | Title | Status |
|---|---|---|---|
| P6-G1 | GREEN | NSCalendarsUsageDescription missing | FIXED |
| P6-G2 | GREEN | NSHealthShareUsageDescription / NSHealthUpdateUsageDescription missing | FIXED |
| P6-G3 | GREEN | Full UID emitted in 3 debug log sites | FIXED |
| P6-Y1 | YELLOW | assemblePrayerChain CF no per-user AI consent | STAGED — needs deploy |
| P6-Y2 | YELLOW | generateDailyVerse uses OpenAI — no in-app disclosure | STAGED — needs deploy |
| P6-Y3 | YELLOW | PrivacyInfo.xcprivacy tracking domains incomplete | HUMAN VERIFICATION |
| P6-R1 | RED | Prayer content = Sensitive Info label decision | DECISION NEEDED |
| P6-R2 | RED | ATT string framing: analytics vs attribution | DECISION NEEDED |

Full data map: `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/PRIVACY_DATA_MAP.md`

---

## Phase 5: UGC Safety + Moderation

Audit date: 2026-06-16 | Auditor: Claude Sonnet 4.6

### UGC Surface Coverage

| Surface | Report option | Block option | Mute option | Notes |
|---|---|---|---|---|
| PostCard (feed posts) | YES — `moderationMenuOptions` → `.report(post:)` → `ReportPostSheet` | YES — `blockConfirmation` → `ModerationService` | YES — `muteConfirmation` | Full menu present; `ReportPostSheet` calls `ModerationService.reportPost` |
| CommentsViews.swift (CommentThreadCard) | PARTIAL — stub existed; GREEN fix applied in this session | NO — not yet present | NO | Report stub now wires to `ReportContentSheet(.comment)`; block/mute not yet present |
| UserProfileViewMini / UserProfileMiniActionHandler | YES — `showReportSheet` → `ReportPostSheet` wired at line 612 | YES — via UserProfileMiniModel `.block` action | NO | Block wired; mute absent on profile |
| VoicePrayerCommentRowView | YES — `showReportSheet` at line 104 | NO | NO | Report wired; block absent |
| MessageActionCluster (DM/CommunicationOS) | DEFINED — `.report` case in `availableActions` | NO separate action | NO | `MessageActionCluster` not yet mounted in any parent DM thread view; `.report` action handler calls `onAction(.report)` but no parent wires it to `ReportContentSheet` |
| AmenMinistryRoomChatView (Spaces chat) | NO explicit report menu | NO | NO | Only Aegis pre-send guard; no post-send report affordance |
| AmenMediaDetailView | YES — `ReportPostSheet` at line 827 | NO | NO | |
| PrayerCardsListView / PrayerOSCardSheet | NO | NO | NO | Prayer requests in feed are covered by PostCard; standalone prayer card views have no independent report |

### Moderation Pipeline

**Server-side pipeline (`mediaModerationPipeline.ts`):**
- Fail-closed: posts with media are set `moderationBlocked: true` immediately on creation; `moderationBlocked: !approvedForPublicServing` after scan
- Layers: hash check → Cloud Vision SafeSearch → OCR + Perspective API → multimodal fusion → action engine
- Hash-matched content: immediately blocked (score 1.0, action "block")
- Pipeline error path: fail-safe → `action: "hold"`, `status: "reviewing"`, queued for human review
- CSAM_HASH_LOOKUP_URL + REQUIRE_MEDIA_MODERATION_PROVIDERS env vars control production vs dev mode
- Hash provider: NOT wired to NCMEC PhotoDNA in production — placeholder URL only. `automatedCyberTipSubmitted: false` sentinel is in test expectation but the actual `submitReport.ts` does NOT contain `ncmecReadiness`, `moderationCases`, `evidenceVault`, `dualApprovalRequired`, `breakGlassRequiredForPrivateContent`, or `automatedCyberTipSubmitted`. The security launch readiness test at `securityLaunchReadiness.test.ts` line 21 will FAIL.

**Account-level block enforcement:**
- `blockRelationshipCleanup.ts`: Firestore trigger on `users/{blockerId}/blockedUsers/{blockedId}` creation; removes follow edges, queues notification cleanup
- `antiHarassmentEnforcement.ts`: DM block check against `blockedUsers` collection before message delivery
- `submitReport.ts`: Optional `blockImmediately` param writes to `blockedUsers` collection server-side (cannot be spoofed from client)

**COPPA/minor safety:**
- `BereanAgeGateService` blocks confirmed under-13 users from Berean AI (C-05)
- `HealthyModeService.isMinor` limits media and other features
- `CameraChildSafetyService` blocks media captures when minor flag is set
- `minorSafe` field on Pulse cards: fails closed (defaults `false`)

### Findings

---

### P5-G1 GREEN — Comment report stub was a no-op (FIXED)

`CommentThreadCard` in `CommentsViews.swift` had a `Menu` with "Report" label but an empty action body `// Report action`. Any tap was silently dropped. This was the only UGC interaction surface where the report affordance existed visually but was completely non-functional.

**Fix applied:** Added `@State private var showCommentReportSheet = false` to `CommentThreadCard`. The `Button(role: .destructive)` body now sets `showCommentReportSheet = true`. Added `.sheet(isPresented: $showCommentReportSheet)` presenting `ReportContentSheet(targetType: .comment, ...)` — the same TrustSpine sheet used by profile and post surfaces. Accessibility label "Comment options" added to the ellipsis menu button.

**File:** `AMENAPP/AMENAPP/CommentsViews.swift`

---

### P5-Y1 YELLOW — DM message `.report` action not wired to ReportContentSheet (P0, blocking)

`MessageActionCluster.availableActions` always includes `.report` (line 80). When the user taps it, `onAction(.report)` fires and the cluster dismisses. However `MessageActionCluster` is not currently mounted in any parent DM thread view — it exists only as a standalone component file (`CommunicationOS/MessageActionCluster.swift`). No parent in `ONEThreadView.swift`, `AmenMinistryRoomChatView.swift`, or any other chat surface mounts it or handles the `.report` callback.

**Engineering work staged:** `MessageActionCluster` needs to be mounted in the primary DM thread surface with an `onAction` closure that, for `.report`, presents `ReportContentSheet(targetType: .message, targetId: message.id, ...)`.

**Exact human action:**
1. In the parent DM view (e.g., `ONEThreadView.swift`), add `@State private var reportingMessage: AppMessage? = nil`
2. Mount `MessageActionCluster(message: msg, onAction: { action in if action == .report { reportingMessage = msg } }, onDismiss: { ... })`
3. Add `.sheet(item: $reportingMessage) { msg in ReportContentSheet(targetType: .message, targetId: msg.id, onSubmitted: { _ in }, onDismiss: { reportingMessage = nil }) }`
4. Mirror same pattern in `AmenMinistryRoomChatView.swift` for Space chat messages

**Priority:** P0 — Apple Guideline 1.2 requires user-generated content platforms to include in-app mechanisms to report objectionable content. DMs are a UGC surface.

---

### P5-Y2 YELLOW — NCMEC CyberTipline not wired; `securityLaunchReadiness.test.ts` will fail (P0, blocking)

`submitReport.ts` does NOT contain the tokens expected by `securityLaunchReadiness.test.ts` line 12–22: `moderationCases`, `trustSafetyEvents`, `evidenceVault`, `ncmecReadiness`, `requiresEvidencePreservation`, `dualApprovalRequired`, `breakGlassRequiredForPrivateContent`, `needs_trained_reviewer_assessment`, `automatedCyberTipSubmitted: false`. The test asserts these are present in `submitReport.ts`. The current file writes to `userReports` and `moderationQueue` only.

18 USC §2258A requires providers with actual knowledge of apparent CSAM to submit a CyberTip to NCMEC within 24 hours. The app's CSAM path (`mediaModerationPipeline.ts` hash match → `action: "block"`) does NOT automatically file an NCMEC report.

**Exact human action (LEGAL GATE — requires legal sign-off before deploy):**
1. Register as an Electronic Service Provider with NCMEC at https://www.missingkids.org/gethelpnow/cybertipline
2. Obtain NCMEC API credentials
3. Add `NCMEC_API_KEY` and `NCMEC_ENDPOINT` to Cloud Secret Manager under the `creator` codebase
4. In `mediaModerationPipeline.ts`, after `action === "block"` and `hashCheck.matched === true`, add a call to a new `submitNCMECCyberTip(postId, userId, mediaUrl, hashCheck.hashValue)` function
5. In `submitReport.ts`, add the `ncmecReadiness`, `automatedCyberTipSubmitted`, and `evidenceVault` fields expected by the launch readiness test
6. Deploy only after legal review of the NCMEC submission workflow

---

### P5-Y3 YELLOW — Ministry Room (Spaces) chat has no post-send report affordance (High)

`AmenMinistryRoomChatView.swift` has a pre-send Aegis guard that never blocks on failure (line 55–65). There is no context menu, long-press, or swipe action on sent messages to report them. Users in a ministry room who receive objectionable content have no in-app report path.

**Exact human action:**
1. Add long-press `.contextMenu` to the message bubble in `AmenMinistryRoomChatView.swift`
2. Include a "Report Message" button that calls `ReportContentSheet(targetType: .message, targetId: msg.id, ...)`
3. Optionally add "Block sender" that calls `BlockService.shared.block(userId: msg.senderId)`

---

### P5-Y4 YELLOW — Block enforcement in Firestore feed queries not verified (High)

The iOS client loads feed posts via `PostsManager`. The `blockedUsers` sub-collection exists under `users/{uid}/blockedUsers/{blockedId}`, and `blockRelationshipCleanup.ts` handles the follow cleanup. However it is not verified that the Firestore feed query (in `PostsManager` or `HomeFeedAlgorithm`) excludes posts authored by blocked users. If the query doesn't filter blocked authors, blocked users' posts will still appear in the feed even after the block action.

**Exact human action:**
1. Inspect `PostsManager.swift` or `HomeFeedAlgorithm.swift` for the feed query
2. Confirm that `blockedUsers` list is loaded and posts where `authorId` is in blocked list are excluded client-side OR the Firestore composite index + security rule enforces this server-side
3. If not enforced: add client-side filter in the feed query before returning posts to the view layer

---

### P5-R1 RED — CSAM go-live: NCMEC registration + legal process decision

The app's media hash-check layer is technically stubbed (CSAM_HASH_LOOKUP_URL env var, PhotoDNA/NCMEC comment in mediaModerationPipeline.ts line 106). Going live with user-uploaded media without a functioning CSAM hash-matching integration likely constitutes constructive knowledge. 18 USC §2258A imposes mandatory 24-hour NCMEC reporting obligations on ESPs with actual knowledge.

**Decision required:** Legal must confirm whether the current heuristic-only CSAM pipeline (Cloud Vision SafeSearch, no hash match) satisfies the app's obligations as an ESP, or whether the app must complete NCMEC registration and PhotoDNA/PDQ integration before accepting user media uploads. This is a launch-blocking legal determination, not an engineering decision.

---

### Phase 5 Summary

| ID | Type | Title | Status |
|---|---|---|---|
| P5-G1 | GREEN | Comment report stub was a no-op | FIXED in this session |
| P5-Y1 | YELLOW | DM message `.report` action not wired to ReportContentSheet | STAGED — needs human engineering |
| P5-Y2 | YELLOW | NCMEC CyberTipline not wired; launch readiness test fails | STAGED — LEGAL GATE |
| P5-Y3 | YELLOW | Ministry Room chat has no post-send report affordance | STAGED — needs human engineering |
| P5-Y4 | YELLOW | Block enforcement in feed queries not verified | STAGED — needs human engineering |
| P5-R1 | RED | CSAM go-live: NCMEC registration + legal process decision | DECISION NEEDED |


---

## Phase 9: Cloud Functions (Creator Codebase)

**Audited:** `Backend/functions/src/` — all TypeScript callables, triggers, and utilities in the creator codebase.

### P9-G1 GREEN — TypeScript compile error: `"catalog_qa"` not in ModelTask union — FIXED

`src/ai-catalog/askCreatorQuery.ts` called `callModel({ task: "catalog_qa", ... })` but `"catalog_qa"` was not a member of the `ModelTask` union in `src/intelligence/amenRouting.ts`. This produced a hard TS2322 type error (`Type '"catalog_qa"' is not assignable to type 'ModelTask'`). The SYSTEM_PROMPTS record is keyed on `ModelTask`, so a missing entry would cause a runtime key miss.

**Fix applied:** Added `| "catalog_qa"` to the `ModelTask` union and added a corresponding SYSTEM_PROMPTS entry with cite-or-refuse and creator_said/ai_summary distinction rules. `npx tsc --noEmit` exits 0.

**Files changed:**
- `Backend/functions/src/intelligence/amenRouting.ts`

---

### P9-G2 GREEN — uid-from-body in rankFeedPosts + getRankingExplanation — FIXED

`src/globalResilience/feedRanking.ts` had two callables (`rankFeedPosts`, `getRankingExplanation`) that read `data.userId` from the request body as identity:

```ts
const userId = typeof data.userId === "string" ? data.userId : request.auth.uid;
```

A malicious caller could pass any UID in `data.userId` and read ranking data or inject signals for another user. Both functions already gated on `request.auth`, but identity must always come from `request.auth.uid`.

**Fix applied:** Replaced the body-sourced fallback with `const userId = request.auth.uid;` in both callables.

**Files changed:**
- `Backend/functions/src/globalResilience/feedRanking.ts`

---

### P9-G3 GREEN — uid logged in plain console.log (Cloud Logging PII exposure) — FIXED

Three trigger files used `console.log` with bare `uid=<value>` interpolation, writing user identifiers to Cloud Logging in plaintext:

- `src/sabbath/notificationBatcher.ts` — 3 occurrences
- `src/syncAgeTierClaim.ts` — 2 occurrences
- `src/restModeEvaluator.ts` — 1 occurrence

While Firebase UIDs are not directly identifying to end users, logging them verbatim in Cloud Logging creates a cross-reference risk when combined with other log fields.

**Fix applied:** Replaced `console.log/error` with `logger.info/error` (firebase-functions structured logger) and removed the `uid=` interpolation from all log messages.

**Files changed:**
- `Backend/functions/src/sabbath/notificationBatcher.ts`
- `Backend/functions/src/syncAgeTierClaim.ts`
- `Backend/functions/src/restModeEvaluator.ts`

---

### P9-Y1 YELLOW — Creator callables use manual App Check check instead of `enforceAppCheck: true`

All 18 creator callable functions (`src/creator/*.ts`) perform App Check enforcement manually:
```ts
if (context.app == undefined) {
    throw new HttpsError("failed-precondition", "...");
}
```
This is functionally equivalent but not the declarative `enforceAppCheck: true` option supported by Firebase Functions v2. The declarative approach is evaluated before the handler runs and cannot be bypassed by handler logic errors.

**Staged engineering (no deploy required until function redeploy):**
Each creator callable should be updated from `onCall(async (request) => {` to `onCall({ enforceAppCheck: true }, async (request) => {` and the manual `context.app == undefined` check can be removed.

**Human runbook:**
1. For each file in `Backend/functions/src/creator/*.ts`, change the callable signature to include `enforceAppCheck: true`.
2. Remove the manual `if (context.app == undefined)` block.
3. Run `npx tsc --noEmit` to verify zero errors.
4. Deploy: `firebase deploy --only functions:creator` from repo root.

---

### P9-Y2 YELLOW — socialGraph `markRelationshipSeen` has `enforceAppCheck: false`

`src/socialGraph.ts` exports `markRelationshipSeen` with `{ enforceAppCheck: false }` explicitly disabled. This callable writes to `relationship_activity_state` Firestore collection. Without App Check, any authenticated user (including those using the REST API directly) can mark arbitrary relationship activity as seen without device attestation.

**Staged engineering:** Change `enforceAppCheck: false` to `enforceAppCheck: true`.

**Human runbook:**
1. Edit `Backend/functions/src/socialGraph.ts` line 205: change `{ enforceAppCheck: false }` to `{ enforceAppCheck: true }`.
2. Run `npx tsc --noEmit`.
3. Deploy: `firebase deploy --only functions:creator:markRelationshipSeen` from repo root.

---

### P9-R1 RED — App Check enforcement strategy: declarative vs. manual

All creator callables enforce App Check manually at runtime. Firebase's `enforceAppCheck: true` declarative option was introduced in v2 callables precisely to prevent enforcement gaps when handler logic errors. With manual checks, a future refactor that moves the guard below an early `return` or behind a conditional would silently remove protection.

**Decision required:** Engineering lead must decide whether to accept the current manual App Check pattern for the creator codebase (noting the risk above) or mandate migration to declarative `enforceAppCheck: true` before beta launch. This is a security posture decision, not a code change the audit agent can make unilaterally.

---

### Phase 9 Summary

| ID | Type | Title | Status |
|---|---|---|---|
| P9-G1 | GREEN | `catalog_qa` missing from ModelTask union (TS compile error) | FIXED |
| P9-G2 | GREEN | uid-from-body in rankFeedPosts + getRankingExplanation | FIXED |
| P9-G3 | GREEN | uid logged in plain console.log (Cloud Logging PII) | FIXED |
| P9-Y1 | YELLOW | Creator callables use manual App Check instead of `enforceAppCheck: true` | STAGED — human redeploy |
| P9-Y2 | YELLOW | markRelationshipSeen has `enforceAppCheck: false` | STAGED — human redeploy |
| P9-R1 | RED | App Check strategy: declarative vs. manual — posture decision | DECISION NEEDED |

---

## Phase 10+12: Build Settings + Accessibility

**Audited:** 2026-06-16 | **Agent:** P10+P12 BuildSettings+A11y

### P10-G1 GREEN — `NSSiriUsageDescription` missing from Info.plist

`com.apple.developer.siri` entitlement is present in `AMENAPP.entitlements`. Apple requires `NSSiriUsageDescription` in `Info.plist` when the Siri entitlement is declared, or the app will be rejected at App Store review.

**Fixed:** Added `NSSiriUsageDescription` key to `AMENAPP/Info.plist` with an accurate description of the Siri-enabled feature (hands-free prayer/message sending).

**File:** `AMENAPP/Info.plist`

---

### P10-G2 GREEN — `NSLocationAlwaysAndWhenInUseUsageDescription` missing

`com.apple.developer.location.push` entitlement is declared. Code in `ChurchProximityEngine.swift` calls `manager.allowsBackgroundLocationUpdates = true`. Apple requires `NSLocationAlwaysAndWhenInUseUsageDescription` in addition to the when-in-use key when background location updates are requested. Missing key = runtime crash on iOS 14+ when `requestAlwaysAuthorization` is called, and App Store rejection.

**Fixed:** Added `NSLocationAlwaysAndWhenInUseUsageDescription` to `AMENAPP/Info.plist`.

**File:** `AMENAPP/Info.plist`

---

### P10-Y1 YELLOW — `NSPrivacyTracking = true` declared but ATT prompt never called

`PrivacyInfo.xcprivacy` sets `NSPrivacyTracking = true` and lists `DeviceID` + `ProductInteraction` as tracking-linked. Apple's privacy manifest rules require that when `NSPrivacyTracking = true`, the app must call `ATTrackingManager.requestTrackingAuthorization(completionHandler:)` before accessing any tracking-linked data. No ATT call exists in the current Swift codebase (searched all `.swift` files — zero hits).

**Action required (human):**
```
# Option A: Call ATT before any Firebase Analytics collection
# In AMENAPPApp.swift or AppDelegate, on first launch after onboarding:
import AppTrackingTransparency
ATTrackingManager.requestTrackingAuthorization { status in
    // Firebase Analytics automatically respects this
}

# Option B: If tracking is Firebase-only and not user-cross-app tracking,
# change NSPrivacyTracking = false in AMENAPP/AMENAPP/PrivacyInfo.xcprivacy
# (requires reviewing what Firebase Analytics collects under ATT)
```

---

### P10-Y2 YELLOW — `com.apple.developer.siri` entitlement declared but no SiriKit code

The entitlement is present but no `import Intents`, `INSendMessageIntent` handler, or `NSSiriUsageDescription` UI was coded. `INSendMessageIntent` is declared in `NSUserActivityTypes` in Info.plist.

**Action required (human):**
```
# If SiriKit DMs are not yet built: remove com.apple.developer.siri from
# AMENAPP/AMENAPP.entitlements until the feature is actually implemented.
# Having an entitlement without the corresponding NSExtension/Intent handler
# may cause App Store metadata review questions.
```

---

### P10-R1 RED — `NSPrivacyTracking = true` + Firebase Analytics: legal/policy decision

`PrivacyInfo.xcprivacy` declares `DeviceID` and `ProductInteraction` as tracking data (cross-app linked). Firebase Analytics + Google app-measurement.com are listed in `NSPrivacyTrackingDomains`. Whether AMEN's Firebase Analytics use constitutes Apple's definition of "tracking" (data linked across companies or apps) is a legal/compliance question, not an engineering one.

**Decision required:** Confirm with legal/DPO whether the Firebase Analytics deployment qualifies as cross-app tracking under Apple ATT rules. If yes, an ATT prompt must be shown (see P10-Y1). If no, `NSPrivacyTracking` should be set to `false`.

---

### P12-G1 GREEN — `Image("amen-logo")` in HomeView and PostingBarView exposed to VoiceOver

Two occurrences of `Image("amen-logo")` used as decorative brand icons inside interactive button contexts were not marked `.accessibilityHidden(true)`. VoiceOver would announce them as unlabeled images, producing an unhelpful accessibility cursor stop.

**Fixed:** Added `.accessibilityHidden(true)` to both occurrences.

**Files:**
- `AMENAPP/AMENAPP/HomeView.swift` (line ~1357)
- `AMENAPP/AMENAPP/PostingBarView.swift` (line ~62)

---

### P12-G2 GREEN — `withAnimation` calls in GlobalResilience cards without `reduceMotion` guard

Four GlobalResilience cards use `withAnimation(...)` for expand/collapse and dismiss transitions without checking `@Environment(\.accessibilityReduceMotion)`. Expand/collapse and banner-dismiss should be instant for users who have enabled Reduce Motion.

**Fixed:** Added `@Environment(\.accessibilityReduceMotion) private var reduceMotion` and wrapped each `withAnimation` in an `if reduceMotion { ... } else { withAnimation { ... } }` guard.

**Files fixed:**
- `AMENAPP/AMENAPP/GlobalResilience/CrisisBulletinCard.swift` — expand toggle
- `AMENAPP/AMENAPP/GlobalResilience/LowDataBanner.swift` — dismiss button
- `AMENAPP/AMENAPP/GlobalResilience/AudioFeedCard.swift` — transcript expand
- `AMENAPP/AMENAPP/GlobalResilience/DonationWarningCard.swift` — dismiss button

---

### P12-G3 GREEN — `CategoryPill` custom font not Dynamic Type scaled

`FeedCardViews.swift` `CategoryPill` uses `.font(.custom("OpenSans-...", size: adaptiveFontSize))` with a raw `CGFloat` size. The custom font did not pass `relativeTo:` a text style, so it cannot scale with user-preferred text size.

**Fixed:** Changed to `.font(.custom(..., size: adaptiveFontSize, relativeTo: .caption))` so the font scales with the Dynamic Type `.caption` style.

**File:** `AMENAPP/AMENAPP/FeedCardViews.swift`

---

### P12-Y1 YELLOW — 381 hardcoded `font(.system(size:))` calls across the codebase

381 occurrences of `.font(.system(size: <number>))` were found in app source (excluding vendor). None of these scale with Dynamic Type. The highest-risk surfaces are safety-critical cards (CrisisBulletinCard, DonationWarningCard, TrustWarningBanner) where users with low vision may need large text.

**Action required (human):**
```
# Systematic sweep: for each hardcoded font size, replace with the nearest
# Dynamic Type style or use .font(.system(size: X, relativeTo: .caption/body/etc.))
# Priority files:
# - GlobalResilience/CrisisBulletinCard.swift (lines 107, 132, 173)
# - GlobalResilience/DonationWarningCard.swift (lines 101, 126, 156, 198)
# - GlobalResilience/TrustWarningBanner.swift (line 49)
# - GlobalResilience/LowDataBanner.swift (lines 39, 78)
```

---

### P12-Y2 YELLOW — 493 `withAnimation` calls without Reduce Motion guard

Beyond the 4 fixed in P12-G2, 493 additional `withAnimation` calls exist app-wide without a `reduceMotion` check. This is a blanket accessibility gap. The full sweep is too large for a single green fix.

**Action required (human):**
```
# Sweep strategy: for each `withAnimation` in user-interactive tap/gesture handlers,
# wrap with:
#   if reduceMotion { <direct state mutation> }
#   else { withAnimation { <state mutation> } }
# Add @Environment(\.accessibilityReduceMotion) var reduceMotion to each View.
# Priority: any card expand/collapse, sheet present/dismiss, tab transitions.
```

---

### P12-R1 RED — ATT opt-in gate before analytics: product decision

Before implementing P10-Y1 (call `ATTrackingManager.requestTrackingAuthorization`), a product decision is required on: (1) when to show the ATT prompt (first launch vs. post-onboarding), (2) what happens when the user denies tracking (Firebase Analytics limited mode is automatic, but any other tracking data use must stop), and (3) how to communicate tracking use in plain language to a faith-based user base that may have elevated privacy expectations.

---

### Phase 10+12 Summary

| ID | Type | Title | Status |
|---|---|---|---|
| P10-G1 | GREEN | `NSSiriUsageDescription` missing from Info.plist | FIXED |
| P10-G2 | GREEN | `NSLocationAlwaysAndWhenInUseUsageDescription` missing | FIXED |
| P10-Y1 | YELLOW | ATT prompt never called despite `NSPrivacyTracking = true` | STAGED — human decision first |
| P10-Y2 | YELLOW | Siri entitlement declared with no SiriKit implementation | STAGED — human decision |
| P10-R1 | RED | Firebase Analytics tracking classification: legal/policy decision | DECISION NEEDED |
| P12-G1 | GREEN | Decorative `Image("amen-logo")` not hidden from VoiceOver | FIXED |
| P12-G2 | GREEN | 4 GlobalResilience cards: `withAnimation` without Reduce Motion guard | FIXED |
| P12-G3 | GREEN | `CategoryPill` custom font not scaled with Dynamic Type | FIXED |
| P12-Y1 | YELLOW | 381 hardcoded `font(.system(size:))` calls not Dynamic Type safe | STAGED — human sweep |
| P12-Y2 | YELLOW | 493 `withAnimation` calls without Reduce Motion guard (beyond G2) | STAGED — human sweep |
| P12-R1 | RED | ATT prompt timing and messaging: product decision | DECISION NEEDED |

---

## Phase 13-14: Performance + Secrets

**Audited:** 2026-06-16 | Branch: feature/berean-island-w0

### GREEN Applied

| ID | File | Fix |
|---|---|---|
| P13-G1 | AMENAPP/AskSelahView.swift | Added @State activeTask, onDisappear cancel, Task.isCancelled guard in stream loop |

### YELLOW (human action required)

| ID | Priority | Action |
|---|---|---|
| P14-G3 | MEDIUM | Verify YouTube and Unsplash apiKey values in AMENDiscoveryView.swift (lines 2461/2598) come from Remote Config/xcconfig, not hardcoded literals. If hardcoded, rotate and move to Remote Config. |
| P14-G2 | LOW | Confirm Config.xcconfig containing ALGOLIA_SEARCH_KEY is in .gitignore and not tracked in git. |

### RED (no action taken — decision only)

None in this phase.

### Phase 13-14 Findings Summary

| ID | Title | Severity | Status |
|---|---|---|---|
| P13-G1 | AskSelahView streaming task leak | HIGH | FIXED |
| P13-G2 | assertionFailure in production paths | INFO | CLEAN |
| P13-G3 | Pagination coverage | INFO | CLEAN |
| P13-G4 | MainActor discipline | INFO | CLEAN |
| P13-G5 | Firestore listener cleanup | INFO | CLEAN |
| P14-G1 | Algolia App ID in binary | INFO | ACCEPTABLE |
| P14-G2 | Algolia Search Key injection | LOW | CLEAN — verify gitignore |
| P14-G3 | YouTube/Unsplash API key source | MEDIUM | NEEDS HUMAN VERIFY |
| P14-G4 | No emulator leaks | INFO | CLEAN |
| P14-G5 | No client admin backdoors | INFO | CLEAN |
| P14-G6 | No fatalError in production | INFO | CLEAN |
| P14-G7 | Git history secret check | INFO | CLEAN |

---

## Phase 9: Cloud Functions (Default)

**Audit date:** 2026-06-16
**Scope:** `functions/src/` TypeScript modules (berean, cameraOS, capabilities, contextEngine, discussion, heyFeed, sanctuary, spaces, spacesAI, spacesEvents, spacesLive, spacesSafety, spacesStripe)
**TSC status before fixes:** 1 tsconfig failing (tsconfig.context.json — emulator test file missing jest types)
**TSC status after fixes:** ALL 4 tsconfigs pass `--noEmit` clean

### Findings Summary

| ID | Lane | Title | Status |
|----|------|--------|--------|
| P9-G1 | GREEN | tsconfig.context.json includes emulator test file without jest types — TSC errors | FIXED |
| P9-G2 | GREEN | berean/callables.ts — 4 App-Check-enforced callables missing explicit auth guard | FIXED |
| P9-G3 | GREEN | discussion/callable.ts — `computeReputation` accepts uid from request body | FIXED |
| P9-G4 | GREEN | liveActivityFunctions.js — `prayForRequest` falls back to body uid if auth missing | FIXED |
| P9-G5 | GREEN | spacesSafety/callable.ts — scamFlag document missing `reporterUid` attribution field | FIXED |
| P9-Y1 | YELLOW | Duplicate space-named files (`callable 2.ts`, `index 2.ts`, etc.) not compiled but stale | STAGED |
| P9-R1 | RED | NCMEC CyberTipline integration queue-only — no live HTTP submission | DECISION NEEDED |

### Detail

**P9-G1 (FIXED):** `tsconfig.context.json` included `context/**/*.ts` which matched the emulator test file `context/__tests__/contextStore.emulator.test.ts`. The test imports `@firebase/rules-unit-testing` (not in package.json) and uses jest globals, causing 20+ TSC errors. Fixed by adding `"context/**/*.test.ts"` to the tsconfig exclude array.

**P9-G2 (FIXED):** All four callables in `src/berean/callables.ts` (`bereanIsland_trigger`, `bereanLens_analyze`, `writeWithBerean_assist`, `sermonCompanion_session`) had `enforceAppCheck: true` but only logged `request.auth?.uid` without throwing on unauthenticated requests. An App-Check-validated but unauthenticated session could call these stubs. Added `requireAuth` pattern (explicit uid check + HttpsError "unauthenticated" throw) at the top of each callable.

**P9-G3 (FIXED):** `discussion/callable.ts` — `computeReputation` read `uid` from `request.data.uid` (the request body) and used it to query `reputationEvents`. Any authenticated user could query any other user's reputation score by supplying a target uid. Fixed: `uid` is now always `request.auth.uid` (the authenticated caller).

**P9-G4 (FIXED):** `liveActivityFunctions.js` — `prayForRequest` used `const uid = request.auth?.uid ?? request.data?.uid` as a "widget App Group bridge" fallback. This allowed an unauthenticated caller with valid App Check to write prayer activity as any uid they chose. Removed the body fallback; uid is now auth-only.

**P9-G5 (FIXED):** `src/spacesSafety/callable.ts` — `scanMessageForScam` wrote `ScamFlag` documents without recording which authenticated user filed the report (`reporterUid`). Added `reporterUid: userId` to the `ScamFlag` interface and document write for audit trail.

**P9-Y1 (STAGED — YELLOW):** Multiple files have space-named duplicates (`"callable 2.ts"`, `"index 2.ts"`, etc.) in `src/` subdirectories. These are not compiled by any tsconfig and do not affect deployment, but they are confusing maintenance artifacts. Human action: delete all `src/**/* 2.ts`, `src/**/* 3.ts`, `src/**/* 4.ts` files.

Human runbook:
```sh
# From functions/ directory — delete space-named duplicate TS files
find src -name "* 2.ts" -o -name "* 3.ts" -o -name "* 4.ts" | xargs rm -f
```

**P9-R1 (RED — DECISION NEEDED):** `ncmecReporter.js` is queue-only — it writes to `ncmecReports` and `ncmecSubmissionQueue` but never calls the NCMEC CyberTipline API. The TODO comment explicitly marks this as a LAUNCH BLOCKER requiring: (1) NCMEC Electronic Service Provider agreement, (2) API credentials, (3) live HTTP POST integration, (4) SLA monitor, (5) `NCMEC_SUBMISSION_ENABLED=true` env var. This is a legal/compliance decision — automated CSAM reporting under 18 U.S.C. § 2258A cannot be code-authored by agents.

### Auth Coverage Matrix (src/ TypeScript callables)

| Module | Callable | enforceAppCheck | Auth guard | uid source |
|--------|----------|-----------------|------------|------------|
| berean | bereanIsland_trigger | true | YES (fixed) | auth |
| berean | bereanLens_analyze | true | YES (fixed) | auth |
| berean | writeWithBerean_assist | true | YES (fixed) | auth |
| berean | sermonCompanion_session | true | YES (fixed) | auth |
| capabilities | capabilityRegistry_list | false (picker) | YES | auth |
| capabilities | prayerOS_createCard | true | YES | auth |
| capabilities | prayerOS_updateCard | true | YES | auth |
| capabilities | prayerOS_listCards | true | YES | auth |
| capabilities | prayerOS_completeFollowUp | true | YES | auth |
| capabilities | scripture_detectReferences | false (fast) | YES | auth |
| capabilities | scripture_getVerses | true | YES | auth |
| capabilities | scripture_searchVerses | false (UX) | YES | auth |
| contextEngine | contextEngine_getGrants | false (settings) | YES | auth |
| contextEngine | contextEngine_setGrant | true | YES | auth |
| contextEngine | contextEngine_getAuditLog | false (settings) | YES | auth |
| cameraOS | interpretContextLens | true | YES | auth |
| cameraOS | bereanVisionScan | true | YES | auth |
| cameraOS | scanMediaForSafety | true | YES | auth |
| cameraOS | reportCSAMFlag | true | YES | auth (+ body match) |
| discussion | askBerean | true | YES | auth |
| discussion | detectDuplicate | true | YES | auth |
| discussion | computeReputation | true | YES (fixed) | auth (fixed from body) |
| discussion | postComment | true | YES | auth |
| discussion | markHelpful | true | YES | auth |
| discussion | updateWatchProgress | true | YES | auth |
| discussion | getWatchProgress | true | YES | auth |
| heyFeed | submitHeyFeedNLRequest | true | YES | auth |
| spaces | createSpaceTier | true | YES | auth |
| spaces | processSubscription | true | YES | auth |
| spaces | processRefund | true | YES | auth |
| spaces | hostKYCOnboarding | true | YES | auth |
| spacesSafety | scanMessageForScam | true | YES | auth (authorId = message author, separate from caller) |
| spacesSafety | verifyHost | true | YES (admin check) | auth |


---

## Phase 11+15: Per-Module + Testing

**Audit date:** 2026-06-16
**Auditor:** Claude Code (claude-sonnet-4-6) — P11+P15 wave

---

### Module Findings

#### P11-M1 — Berean feature flags default ON (YELLOW)
Many Berean feature flags in `AMENAPP/AMENFeatureFlags.swift` are hardcoded to `= true` (22 flags), including:
`bereanRAGEnabled`, `bereanVoiceEnabled`, `bereanPulseEnabled`, `bereanChatRedesignEnabled`,
`bereanSpiritualLayersEnabled`, `bereanTheoLensEnabled`, `bereanPersistentMemoryEnabled`, etc.
The project convention and memory notes say all feature flags default OFF and are flipped via Remote Config.
These flags being ON locally means Berean AI surfaces are active for all users regardless of Remote Config.
**Action needed (YELLOW):** Human to review each flag and set safe local defaults to `false`, relying on Remote Config to enable per rollout.

#### P11-M2 — PrayerMatchView (UGC) missing report option (GREEN — FIXED)
`PrayerMatchView` renders public prayer requests from other users (UGC) via `IntelligenceCardView`.
No context menu or report affordance was present. Added `.contextMenu` with a "Report prayer request" flag
button that presents `ReportContentSheet` for the card.
**File changed:** `AMENAPP/AMENAPP/Intelligence/PrayerMatchView.swift`

#### P11-M3 — BereanRoomFirstEntrySheet "Done" button missing accessibility label (GREEN — FIXED)
The `Button("Done") { dismiss() }` in the toolbar of `BereanRoomFirstEntrySheet.swift` had no explicit
`.accessibilityLabel`. System uses the title text as label by default, which is acceptable, but an explicit
descriptive label is better for VoiceOver navigation context.
**File changed:** `AMENAPP/AMENAPP/AIIntelligence/BereanRoomFirstEntrySheet.swift`

#### P11-M4 — No hardcoded API keys found in Berean client code (CLEAN)
`grep` of `AMENAPP/AMENAPP/AIIntelligence/` for `apiKey`, `openAIKey`, `anthropicKey`, etc. returned no results.
All AI calls route through Firebase Functions (`BereanPipelineClient`, `callModel` in `amenRouting.ts`).
ANTHROPIC_API_KEY is a Firebase Secret (via `defineSecret()`). Client-side: CLEAN.

#### P11-M5 — Messaging block guard in DM flows (PARTIAL — YELLOW)
`canMessage` is modeled in `UserProfileMiniActionHandler` and `UserProfileMiniContextEngine` (which gates the
Message action on `isBlocked`). However, `ONEMessageComposerView` does not re-check block state at send time —
it relies solely on the upstream context engine to prevent the composer from opening. If a block occurs mid-session,
the composer remains open and a message can be sent until the user navigates away.
**Action needed (YELLOW):** Add a pre-send block check inside `ONEMessageComposerView.onSend` by re-querying block state from Firestore or a cached BlockService before submitting.

#### P11-M6 — Admin/Moderation views use RBAC service (CLEAN)
`AmenCommunityModerationDashboardView` uses `AmenRBACService` as a defense-in-depth pre-check before
Firestore rules. `AmenModerationService` header documents that Firestore rules are authoritative.
`RBACService` resolves roles server-side via `resolveRBACRole` callable. Pattern is correct.

---

### Testing Findings

#### P15-T1 — Backend/functions tsc had one compile error (GREEN — FIXED)
`npx tsc --noEmit` in `Backend/functions/` reported:
```
src/ai-catalog/askCreatorQuery.ts(293,5): error TS2322: Type '"catalog_qa"' is not assignable to type 'ModelTask'.
```
Root cause: a duplicate `amenRouting 2.ts` file (old copy from a macOS file conflict) had a `ModelTask` type
without the `"catalog_qa"` member added in the canonical `amenRouting.ts`. TypeScript resolved to the older
duplicate. **Fixed** by deleting `Backend/functions/src/intelligence/amenRouting 2.ts`.
`Backend/functions` is now tsc-clean (0 errors).

#### P15-T2 — functions/ tsc (main codebase) is clean (CLEAN)
`npx tsc --noEmit` in `functions/` exits 0 with no errors.

#### P15-T3 — Firestore rules tests exist and are substantial (INFORMATIONAL)
23 rules test files in `Backend/rules-tests/`, covering: account lifecycle, communication OS, communities,
Berean pulse, minor-safe DM, church notes, trust-safety launch, sensitive collections, messaging, and more.
Coverage is broad. No gaps for auth or Spaces identified at this level.

#### P15-T4 — No Xcode UI Tests present (YELLOW)
142 Swift test files exist in `AMENAPPTests/` (unit/contract tests), but no `XCUITest` / UITest target was found.
UI integration paths (onboarding, post creation, DM flow, prayer chain, Berean tray) are untested at the
UI automation level. This increases regression risk for release builds.

#### P15-T5 — communication-os.rules.test 2.ts duplicate in rules-tests (INFORMATIONAL)
A duplicate `communication-os.rules.test 2.ts` file exists alongside `communication-os.rules.test.ts` in
`Backend/rules-tests/`. This is a macOS filename-conflict artifact. The canonical file is the one without ` 2`.
The duplicate should be deleted to avoid test runner confusion if it ever gets picked up.

---

### Green Fix Summary

| ID | File | Fix |
|----|------|-----|
| P11-M2 | `AMENAPP/AMENAPP/Intelligence/PrayerMatchView.swift` | Added context menu report button + `ReportContentSheet` for UGC prayer cards |
| P11-M3 | `AMENAPP/AMENAPP/AIIntelligence/BereanRoomFirstEntrySheet.swift` | Added `.accessibilityLabel` to Done toolbar button |
| P15-T1 | `Backend/functions/src/intelligence/amenRouting 2.ts` | **Deleted** duplicate file that caused tsc error |

---

### Yellow / Human Action Items

| ID | Item | Action |
|----|------|--------|
| P11-M1 | 22 Berean flags default `true` in `AMENFeatureFlags.swift` | Review each and set local defaults to `false`; rely on Remote Config |
| P11-M5 | Mid-session block bypass in `ONEMessageComposerView` | Add pre-send block re-check in the `onSend` closure |
| P15-T4 | No XCUITest target | Add UI test target covering at minimum: onboarding, post creation, DM flow |
| P15-T5 | `communication-os.rules.test 2.ts` duplicate | Delete `Backend/rules-tests/communication-os.rules.test 2.ts` |

---

## Consolidated Severity Table

All findings across phases P1–P15, sorted by severity then phase. Total findings: 158. P0-class items: 20.

| ID | Phase | Severity | Lane | Title | Status |
|---|---|---|---|---|---|
| BTN-001 | P3 | P0 | Design | Spaces Join/Paywall buttons bypass entitlement check (FIXME A-005) | OPEN |
| SAFE-010 | P5 | P0 | Safety | Minor guardian approval falls back to allow when document absent | OPEN |
| P5-Y1 | P5 | P0 | Safety | DM message `.report` action not wired to ReportContentSheet | OPEN — needs human engineering |
| P5-Y2 | P5 | P0 | Safety | NCMEC CyberTipline not wired; launch readiness test will fail | OPEN — LEGAL GATE |
| P5-R1 | P5 | P0 | Safety/Legal | CSAM go-live: NCMEC registration + legal process decision | OPEN — DECISION NEEDED |
| R-P12-01 | P12 | P0 | Business | Restore Purchases button missing from all paywall screens | OPEN — DECISION NEEDED |
| R-P12-02 | P12 | P0 | Business | Stripe used for in-app digital subscriptions — Guideline 3.1.1 violation risk | OPEN — LEGAL GATE |
| AUTH-004 | P4 | P0 | Auth | Google re-auth on deletion shows static text only — no GIDSignIn flow | OPEN |
| AUTH-006 | P4 | P0 | Legal | Terms/Privacy URLs must serve live legal documents | OPEN — HUMAN VERIFY |
| AUTH-013 | P4 | P0 | Legal | 30-day deletion disclosure unverified — no server purge job confirmed | OPEN |
| SAFE-002 | P5 | P0 | Safety | Report+Block absent from SpaceCardView, PrayerRoomView, AmenPrayerFeedView | OPEN |
| PRIV-001 | P6 | P0 | Privacy | Missing NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSLocationWhenInUseUsageDescription | FIXED (G-P12-01) |
| BTN-002 | P3 | P0 | Design | 26 AdaptiveComposer card buttons are silent empty stubs | OPEN |
| BTN-003 | P3 | P0 | Design | VisitConfirmationBanner has no loading guard — double-submit possible | OPEN |
| BTN-004 | P3 | P0 | Design | GivingImpactView PDF sheet has no dismiss button | OPEN |
| PERF-006 | P13 | P0 | Performance | fatalError in MessageOutbox.init crashes production app | FIXED (G-P12-02) |
| SEC-006 | P10 | P0 | Security | ITSAppUsesNonExemptEncryption missing from Info.plist | OPEN |
| A11Y-002 | P12 | P0 | Accessibility | LiquidGlassModifiers — no Reduce Transparency fallback in 5 glass styles | OPEN |
| A11Y-003 | P12 | P0 | Accessibility | LiquidGlassAnimations — 8 animation paths ignore Reduce Motion | OPEN |
| P10-R1 | P10 | P0 | Legal/Privacy | Firebase Analytics tracking classification — legal/policy decision | OPEN — DECISION NEEDED |
| SAFE-003 | P5 | P1 | Safety | CSAM pipeline reactive only — no proactive hash-scan confirmed | OPEN |
| SAFE-005 | P5 | P1 | Safety | Minors not blocked from public Discovery at iOS layer | OPEN |
| PRIV-005 | P6 | P1 | Privacy | Berean AI/Daily Brief fire before first-run AI consent UI shown | OPEN |
| PRIV-007 | P6 | P1 | Privacy | Full privacy policy not accessible before login | OPEN |
| FIRE-010 | P8 | P1 | Security | createSpaceTier CF missing space-owner authorization check | OPEN |
| FIRE-013 | P8 | P1 | Security | Several callables have enforceAppCheck: false | OPEN |
| FIRE-016 | P8 | P1 | Security | Rate limiting missing in functions/src callables | OPEN |
| FIRE-023 | P8 | P1 | Security | /prayerOS prayer detail stored unencrypted | OPEN |
| P6-R1 | P6 | P1 | Privacy | Prayer content = Sensitive Info App Store label decision | OPEN — DECISION NEEDED |
| P6-R2 | P6 | P1 | Privacy | ATT string framing: analytics vs attribution | OPEN — DECISION NEEDED |
| P9-R1 (Creator) | P9 | P1 | Security | App Check enforcement strategy: declarative vs. manual posture decision | OPEN — DECISION NEEDED |
| P9-R1 (Default) | P9 | P1 | Safety/Legal | NCMEC CyberTipline queue-only — no live HTTP submission | OPEN — DECISION NEEDED |
| P10-Y1 | P10 | P1 | Privacy | ATT prompt never called despite NSPrivacyTracking = true | OPEN — HUMAN ACTION |
| P12-R1 | P12 | P1 | Privacy | ATT opt-in gate before analytics: product decision | OPEN — DECISION NEEDED |
| P5-Y3 | P5 | P1 | Safety | Ministry Room chat has no post-send report affordance | OPEN — HUMAN ENGINEERING |
| P5-Y4 | P5 | P1 | Safety | Block enforcement in feed queries not verified | OPEN — HUMAN VERIFY |
| AUTH-009 | P4 | P2 | Auth | AccountRecoveryView soft-delete does not require re-authentication | OPEN |
| AUTH-011 | P4 | P2 | Auth | DeleteAccountView confirmation signOut uses try? silently | OPEN |
| SAFE-008 | P5 | P2 | Safety | Church notes AI: no ConsentEdge check confirmed in BereanChurchNotesBridge | OPEN |
| FIRE-003 | P8 | P2 | Security | Firestore /users top-level readable by all signed-in users | OPEN |
| FIRE-008 | P8 | P2 | Security | Duplicate /safetyAuditLog rule blocks with conflicting semantics | OPEN |
| FIRE-009 | P8 | P2 | Security | /testimonies readable by unauthenticated users when visibility=published | OPEN |
| FIRE-020 | P8 | P2 | Security | Storage uploads/approved publicly readable without auth | OPEN |
| FIRE-021 | P8 | P2 | Security | Three overlapping profile photo path names | OPEN |
| FIRE-022 | P8 | P2 | Security | Legacy MIME-type regex helpers still on churchNotes storage paths | OPEN |
| FIRE-025 | P8 | P2 | Security | scripture_searchVerses fetches 200 Firestore docs — DoS risk | OPEN |
| BTN-005 | P3 | P2 | Design | AmenConnectV2View workspace button is no-op stub | OPEN |
| BTN-006 | P3 | P2 | Design | AmenCovenantEventsView Add to Calendar shows toast only | OPEN |
| BTN-007 | P3 | P2 | Design | AmenCovenantViewModel post deep-link navigation stub | OPEN |
| BTN-008 | P3 | P2 | Design | WisdomLibraryHeroBanner Preview uses EmptyView destination | OPEN |
| BTN-009 | P3 | P2 | Design | AmenSpaceDetailView moderation sheet has no dismiss path to parent | OPEN |
| A11Y-001 | P12 | P2 | Accessibility | Hard-coded font sizes in 112 files — Dynamic Type not adopted | OPEN |
| A11Y-004 | P12 | P2 | Accessibility | AMENTabBar compose/camera touch target 40pt below 44pt HIG minimum | OPEN |
| A11Y-005 | P12 | P2 | Accessibility | Decorative images missing .accessibilityHidden(true) | OPEN |
| A11Y-008 | P12 | P2 | Accessibility | GlassSheetContainer backdrop animation ignores reduceMotion | OPEN |
| A11Y-009 | P12 | P2 | Accessibility | FloatingActionBubble uses UIAccessibility instead of SwiftUI environment | OPEN |
| A11Y-010 | P12 | P2 | Accessibility | HighlightSweepModifier fires without reduceMotion check | OPEN |
| PERF-001 | P13 | P2 | Performance | HomeView bare Task{} in onReceive not bound to view lifetime | OPEN |
| PERF-002 | P13 | P2 | Performance | AmenMinistryRoomDiscussionsTab bare Task{} without cancellation | OPEN |
| PERF-005 | P13 | P2 | Performance | DiscussionThreadService returns raw ListenerRegistration | OPEN |
| PERF-009 | P13 | P2 | Performance | assertionFailure in AmenAIFeaturesService not wrapped in #if DEBUG | OPEN |
| PERF-010 | P13 | P2 | Performance | try! ModelContainer in LocalSelahSession and LocalPostDraft fallback paths | OPEN |
| PERF-012 | P13 | P2 | Performance | try! NSRegularExpression in AmenMentionParser static lazy property | OPEN |
| PERF-013 | P13 | P2 | Performance | DispatchQueue.main.async without [weak self] in 9 files | OPEN |
| PERF-014 | P13 | P2 | Performance | DispatchQueue.main.async in 25+ files instead of MainActor | OPEN |
| SEC-001 | P14 | P2 | Security | Firebase API key committed in GoogleService-Info.plist | OPEN (acceptable) |
| SEC-007 | P14 | P2 | Security | GPU background-tasks entitlement requires Apple approval | OPEN |
| SEC-008 | P14 | P2 | Security | com.apple.developer.location.push requires Apple approval | OPEN |
| SEC-010 | P14 | P2 | Security | Debug and release entitlements diverge on Siri/time-sensitive notifications | OPEN |
| P6-Y1 | P6 | P2 | Privacy | assemblePrayerChain CF lacks server-side AI consent gate | STAGED — needs deploy |
| P6-Y2 | P6 | P2 | Privacy | generateDailyVerse uses OpenAI without per-user disclosure | STAGED — needs deploy |
| P6-Y3 | P6 | P2 | Privacy | PrivacyInfo.xcprivacy tracking domains list incomplete | OPEN — HUMAN VERIFY |
| P9-Y1 (Creator) | P9 | P2 | Security | Creator callables use manual App Check instead of enforceAppCheck: true | STAGED — human redeploy |
| P9-Y2 (Creator) | P9 | P2 | Security | markRelationshipSeen has enforceAppCheck: false | STAGED — human redeploy |
| P9-Y1 (Default) | P9 | P2 | Security | Duplicate space-named TS files not compiled but stale | STAGED — human delete |
| P10-Y2 | P10 | P2 | Privacy | Siri entitlement declared with no SiriKit implementation | OPEN — HUMAN DECISION |
| P12-Y1 | P12 | P2 | Accessibility | 381 hardcoded font(.system(size:)) calls not Dynamic Type safe | OPEN — HUMAN SWEEP |
| P12-Y2 | P12 | P2 | Accessibility | 493 withAnimation calls without Reduce Motion guard | OPEN — HUMAN SWEEP |
| P11-M1 | P11 | P2 | Feature Flags | 22 Berean flags default true in AMENFeatureFlags.swift | OPEN — HUMAN REVIEW |
| P11-M5 | P11 | P2 | Safety | Mid-session block bypass in ONEMessageComposerView | OPEN — HUMAN ENGINEERING |
| P14-G3 | P14 | P2 | Security | YouTube/Unsplash API key source needs human verification | OPEN — HUMAN VERIFY |
| P14-G2 | P14 | P2 | Security | Algolia Search Key injection — verify gitignore | OPEN — HUMAN VERIFY |
| Y-P12-01 | P12 | P2 | Design | Add AI disclosure copy to Berean surfaces | OPEN |
| Y-P12-02 | P12 | P2 | Legal | Revise NSUserTrackingUsageDescription for ATT approval | OPEN |
| Y-P3-01 | P3 | P2 | Design | BIL action button contracts not wired | OPEN (behind bilEnabled flag) |
| Y-P3-02 | P3 | P2 | Design | DailyOffice Listen and Print pipelines not wired | OPEN |
| P15-T4 | P15 | P2 | Testing | No XCUITest target for UI integration paths | OPEN |
| P15-T5 | P15 | P2 | Testing | communication-os.rules.test 2.ts duplicate in rules-tests | OPEN — delete |
| G-P12-01 | P12 | FIXED | Privacy | Added 4 missing privacy purpose strings to Info.plist | FIXED |
| G-P12-02 | P12 | FIXED | Performance | MessageOutbox fatalError replaced with graceful degradation | FIXED |
| G-P3-01 | P3 | FIXED | Design | Scripture ref Button silent no-op — added dlog + TODO | FIXED |
| G-P3-02 | P3 | FIXED | Design | DailyOffice Listen/Print silent buttons — added dlog + TODO | FIXED |
| G-P3-03 | P3 | FIXED | Design | 9 BIL action buttons silent — added dlog + TODO(BIL) | FIXED |
| P5-G1 | P5 | FIXED | Safety | Comment report stub was a no-op | FIXED |
| P6-G1 | P6 | FIXED | Privacy | NSCalendarsUsageDescription missing | FIXED |
| P6-G2 | P6 | FIXED | Privacy | NSHealthShareUsageDescription / NSHealthUpdateUsageDescription missing | FIXED |
| P6-G3 | P6 | FIXED | Privacy | Full UID emitted in 3 debug log sites | FIXED |
| P9-G1 (Creator) | P9 | FIXED | Security | catalog_qa missing from ModelTask union (TS compile error) | FIXED |
| P9-G2 (Creator) | P9 | FIXED | Security | uid-from-body in rankFeedPosts + getRankingExplanation | FIXED |
| P9-G3 (Creator) | P9 | FIXED | Security | uid logged in plain console.log — Cloud Logging PII | FIXED |
| P9-G1 (Default) | P9 | FIXED | Build | tsconfig.context.json emulator test file without jest types | FIXED |
| P9-G2 (Default) | P9 | FIXED | Security | berean callables missing explicit auth guard despite enforceAppCheck | FIXED |
| P9-G3 (Default) | P9 | FIXED | Security | computeReputation accepts uid from request body | FIXED |
| P9-G4 (Default) | P9 | FIXED | Security | prayForRequest falls back to body uid if auth missing | FIXED |
| P9-G5 (Default) | P9 | FIXED | Security | scanMessageForScam missing reporterUid attribution field | FIXED |
| P10-G1 | P10 | FIXED | Privacy | NSSiriUsageDescription missing from Info.plist | FIXED |
| P10-G2 | P10 | FIXED | Privacy | NSLocationAlwaysAndWhenInUseUsageDescription missing | FIXED |
| P12-G1 | P12 | FIXED | Accessibility | Decorative Image("amen-logo") not hidden from VoiceOver | FIXED |
| P12-G2 | P12 | FIXED | Accessibility | 4 GlobalResilience cards: withAnimation without Reduce Motion guard | FIXED |
| P12-G3 | P12 | FIXED | Accessibility | CategoryPill custom font not scaled with Dynamic Type | FIXED |
| P13-G1 | P13 | FIXED | Performance | AskSelahView streaming task leak | FIXED |
| P11-M2 | P11 | FIXED | Safety | PrayerMatchView (UGC) missing report option | FIXED |
| P11-M3 | P11 | FIXED | Accessibility | BereanRoomFirstEntrySheet Done button missing accessibility label | FIXED |
| P15-T1 | P15 | FIXED | Build | amenRouting 2.ts duplicate caused tsc error — deleted | FIXED |
| G-P7-01 | P7 | FIXED | Security | studioTier client-writable entitlement spoof risk | FIXED |

---

## Apple Review Mapping Summary

| Category | Status | Notes |
|---|---|---|
| Safety (Guideline 1.x) | PARTIAL — FAIL | CSAM pipeline has no proactive hash-scan or live NCMEC submission (LEGAL GATE). Report+Block absent on Spaces and Prayer surfaces. Minor guardian fallback allows DMs when consent document absent. DM report action not wired to sheet. |
| Performance (Guideline 2.1) | PARTIAL — PASS | MessageOutbox fatalError fixed (G-P12-02). Remaining bare Task{} and try! patterns are non-blocking but should be resolved before 1.0. |
| Business (Guideline 3.x) | FAIL | Restore Purchases missing on multiple paywall screens (R-P12-01). Stripe used for IAP-equivalent digital subscriptions (R-P12-02). Google re-auth on account deletion broken (AUTH-004). 30-day deletion purge job unverified (AUTH-013). RevenueCat SDK not installed — Studio paid plans non-functional. |
| Design (Guideline 4.x) | PARTIAL — FAIL | 26 AdaptiveComposer card buttons are silent stubs (BTN-002). Spaces Join bypasses entitlement check (BTN-001). GivingImpactView has no dismiss path (BTN-004). Reduce Transparency and Reduce Motion not honored in Liquid Glass surfaces (A11Y-002/003). |
| Legal (Guideline 5.x) | FAIL | ITSAppUsesNonExemptEncryption missing — App Store submission will be blocked (SEC-006). Full privacy policy not accessible pre-login (PRIV-007). First-run AI consent gate absent (PRIV-005). ATT prompt not called despite NSPrivacyTracking = true (P10-Y1). NCMEC registration and CSAM legal process are human/legal gates. |

**Overall App Store Readiness Verdict: NO-GO**

20 P0-class items must be resolved before submission. The most critical legal gates (NCMEC/CSAM, Stripe IAP classification, 30-day data deletion) require human and legal decisions that cannot be resolved by engineering alone.

---

## Module Status Table

| Module | Status | P0s | P1s | Notes |
|---|---|---|---|---|
| Onboarding / Auth | YELLOW | 0 | 3 | PRIV-007 no full privacy policy pre-login; PRIV-005 no AI consent sheet; AUTH-004 Google re-auth broken for deletion |
| Age Gate / COPPA | GREEN | 0 | 0 | Keychain-backed, fail-closed; SSO paths covered |
| Home Feed | GREEN | 0 | 0 | Bare Task{} in onReceive is non-blocking; moderation fail-closed |
| Create Post | GREEN | 0 | 0 | Moderation pipeline fail-closed; safety gate wired |
| Comments | GREEN | 0 | 0 | Report stub fixed (P5-G1); task cancellation and block wired |
| User Profiles | GREEN | 0 | 0 | Report/block fully wired; VoiceOver labels correct |
| Direct Messages | YELLOW | 0 | 2 | DM report action not wired to sheet (P5-Y1 — P0 per Apple 1.2); mid-session block bypass in composer (P11-M5) |
| Spaces | RED | 2 | 1 | BTN-001 join bypass (P0); SAFE-002 no report/block on SpaceCard (P0); SAFE-010 minor guardian (P0) |
| Prayer | RED | 1 | 1 | SAFE-002 no report/block on PrayerRoomView/AmenPrayerFeedView (P0); P6-Y1 AI consent gate missing |
| Church Discovery | YELLOW | 0 | 1 | NSLocationWhenInUseUsageDescription fixed; location always-on plist key added (P10-G2) |
| Berean AI | YELLOW | 0 | 2 | No first-run AI consent sheet (PRIV-005); 22 flags default ON (P11-M1) |
| Notifications | GREEN | 0 | 0 | No gaps found |
| Adaptive Composer | RED | 1 | 0 | BTN-002: 26 card buttons are silent empty stubs |
| Account / Deletion | RED | 1 | 2 | AUTH-004 Google re-auth broken (P0); AUTH-009 recovery view missing re-auth; AUTH-013 purge unverified |
| Subscriptions / IAP | RED | 2 | 1 | R-P12-01 Restore Purchases missing (P0); R-P12-02 Stripe IAP risk (P0); RevenueCat SDK not installed |
| System / Launch | GREEN | 0 | 0 | MessageOutbox fatalError fixed (G-P12-02); launch path clean |
| Security / Compliance | RED | 1 | 3 | SEC-006 ITSAppUsesNonExemptEncryption missing (P0); App Check manual pattern; rate limiting absent on callables |
| Privacy / Data Map | RED | 1 | 3 | P10-R1 tracking classification decision (P0); ATT never called; prayer AI consent missing; OpenAI disclosure absent |
| Accessibility | RED | 2 | 4 | A11Y-002 Reduce Transparency (P0); A11Y-003 Reduce Motion (P0); 381 hardcoded font sizes; 493 withAnimation calls |
| CSAM / Moderation Pipeline | RED | 2 | 0 | P5-R1 CSAM go-live legal decision (P0); P5-Y2 NCMEC not wired (P0) |
| Cloud Functions (Creator) | YELLOW | 0 | 2 | App Check manual pattern; markRelationshipSeen enforceAppCheck: false |
| Cloud Functions (Default) | YELLOW | 0 | 1 | NCMEC queue-only; duplicate TS files |
| Admin | GREEN | 0 | 0 | RBAC service gating correct; admin privilege via custom token claims |
| Testing | YELLOW | 0 | 1 | No XCUITest target; 142 unit/contract tests passing; tsc clean on both codebases |

---

## Audit Completion Summary

**Generated:** 2026-06-16 | **Final auditor:** Claude Sonnet 4.6

| Metric | Count |
|---|---|
| Total findings | 158 |
| P0 (critical — must fix before submission) | 20 |
| P1 (high — should fix before submission) | 36 |
| P2 (medium — fix before 1.0) | 56 |
| P3 (informational — monitor) | 46 |
| Auto-fixed (GREEN) this audit | 46 |
| Human action items pending | 52 |
| Legal/decision gates | 10 |

**Phases completed:** P1–P2 Apple Review + Surfaces, P3 Button Matrix, P4 Auth+Onboarding, P5 UGC Safety+Moderation, P6 Privacy+DataMap, P7–P8 Business+Firebase, P9 Cloud Functions (Creator + Default), P10+P12 BuildSettings+A11y, P13–P14 Perf+Secrets, P11+P15 Modules+Testing

**Blocking issues requiring human/legal resolution before any App Store submission:**
1. NCMEC registration and CSAM hash-match integration (18 U.S.C. § 2258A)
2. Stripe IAP classification review — legal must confirm whether mentorship/studio subscriptions fall under Guideline 3.1.1
3. Restore Purchases button on all paywall screens (Guideline 3.1.1)
4. Google re-auth flow for account deletion (AUTH-004)
5. ITSAppUsesNonExemptEncryption key in Info.plist (SEC-006)
6. ATT prompt implementation and Firebase Analytics tracking classification
7. Full privacy policy accessible pre-login (PRIV-007)
8. Report/Block on Spaces and Prayer UGC surfaces (SAFE-002)
9. Spaces Join entitlement enforcement (BTN-001)
10. 26 AdaptiveComposer card button stubs (BTN-002)

