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

