# Human Gate Queue — App Store Readiness
Generated: 2026-06-16 | Branch: app-store-readiness-overnight

> This is your morning to-do list. Nothing here has been deployed or activated.
> Items are separated by urgency. Nothing requiring a human decision has been made.
> The overnight agent made 4 safe GREEN code edits only (see AUTOFIX_CHANGELOG.md).

---

## P0 BLOCKERS — Must clear before ANY TestFlight or App Store submission

| ID | Lane | Title | Why Gated | Exact Action | Est Time | Blocking |
|---|---|---|---|---|---|---|
| BTN-001 | RED | Spaces Join/Paywall bypasses entitlement check | Both onJoin closures in AmenSpaceDetailView.swift set isSubscribed=true client-side without calling AmenSpaceEntitlementService or writing Firestore membership; any user can join paid Spaces for free | Wire both onJoin closures to AmenSpaceEntitlementService.checkEntitlement() and add Firestore membership write; set isSubscribed only on server success; add @State var isJoining Bool guard | 1–2 hrs |  YES |
| SAFE-010 | YELLOW | Minor guardian approval falls back to allow | AmenChildSafetyService.isGuardianApprovedContact() lines 563-572 returns true (allow) when no guardian document exists; any minor without an active guardian portal can receive DMs from any mutual follow | Change fallback `return true` to `return false` in isGuardianApprovedContact() until OPEN-2 is resolved with T&S Lead; then escalate OPEN-2 immediately | 30 min code + T&S escalation | YES |

---

## P1 HIGH — Must clear before App Store submission

| ID | Lane | Title | Why Gated | Exact Action | Est Time | Blocking |
|---|---|---|---|---|---|---|
| PRIV-001 | RED | Three NSUsageDescription strings missing from Info.plist | NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSLocationWhenInUseUsageDescription are absent; iOS will terminate the app with a privacy exception at runtime when these APIs are accessed; App Store Review will reject | Add all three keys to AMENAPP/AMENAPP/Info.plist with AMEN-specific purpose strings (see Decision Brief PRIV-001 below) | 15 min | YES |
| SEC-006 | RED | ITSAppUsesNonExemptEncryption missing | Without this key App Store Connect will prompt for encryption compliance on every upload and may reject automated CI uploads | Add `<key>ITSAppUsesNonExemptEncryption</key><false/>` to Info.plist if only standard TLS is used; if custom E2EE DMs are present set to true and complete Apple encryption documentation | 20 min + legal check | YES |
| SAFE-002 | RED | Report+Block absent from Spaces, Prayer, and PrayerFeed surfaces | SpaceCardView, PrayerRoomView, AmenPrayerFeedView have no report or block affordances; bad actors can post unchallenged in these surfaces | Add context-menu ellipsis to SpaceCardView with reportSpace(); add long-press or ellipsis to prayer request items in PrayerRoomView and AmenPrayerFeedView with reportPrayerRequest() + blockAuthor(); wire to existing ModerationService and SafetyReportingService | 3–4 hrs | YES |
| AUTH-004 | YELLOW | Google re-auth on account deletion is broken | DeleteAccountView.swift ReauthenticationSheet renders static text for Google providers with no GIDSignIn call; Google-signed-in users cannot complete account deletion | Add GIDSignIn.sharedInstance.signIn(presenting:) call to the Google provider branch; create OAuthCredential from result; call Auth.auth().currentUser?.reauthenticate(); then call onComplete(true) | 2–3 hrs | YES |
| AUTH-006 | RED | Terms and Privacy URLs must serve live legal documents | https://amenapp.com/terms and https://amenapp.com/privacy are hardcoded in 3 Swift files; whether they serve App Review-compliant documents (COPPA/KOSA notices, GDPR Art.13, 30-day deletion disclosure) is unverifiable by code | LEGAL GATE: counsel must confirm both URLs serve live, complete documents before submission; if not live, publish them before submission | Legal + engineering | YES |
| AUTH-013 | RED | 30-day deletion grace period not backed by server job | AccountManagementService.softDeleteAccount() writes deletedAt and deletionScheduledFor to Firestore; no CF or Cloud Scheduler job that purges accounts 30 days later was found in either functions directory | BACKEND GATE: deploy a Cloud Scheduler job or Firestore TTL rule that reads deletionScheduledFor and executes full deletion (Auth + Firestore + Storage) after 30 days; verify it exists before submission | 1 day backend work | YES |
| AUTH-009 | YELLOW | AccountRecoveryView soft-delete has no re-auth guard | service.softDeleteAccount() is called directly on button confirmation without re-auth; Apple Guideline 5.1.1 requires re-auth before account deletion | Wrap the deleteAccount() button action in AccountRecoveryView behind ReauthenticationSheet (import from DeleteAccountView); only call softDeleteAccount() after onComplete(true) | 1–2 hrs | YES |
| BTN-002 | RED | 26 AdaptiveComposer card buttons are silent stubs | Tapping Give Now, RSVP, Poll vote, Play, Study in Berean, Add to Calendar, Get Directions, etc. either does nothing or updates local UI without persisting to Firestore; users will file App Store review complaints about broken features | Either wire each stub to its described backend action OR add .disabled(true) with an accessibilityHint("Coming soon") to prevent silent no-ops; RSVP, Poll vote, and Checklist must not update local UI state if they do not write Firestore | 1–2 days | YES |
| BTN-003 | RED | VisitConfirmationBanner has no loading guard | Two rapid taps on 'Yes, log visit' dispatch two concurrent confirmVisit(visit) Tasks to Firestore; visit may be logged twice | Add @State private var isConfirming = false; set true before Task fires; add defer { isConfirming = false }; add .disabled(isConfirming) to both buttons; add ProgressView indicator | 1 hr | YES |
| BTN-004 | RED | GivingImpactView PDF sheet has no dismiss button | PDF sheet presents bare PDFKitView with no NavigationStack, no toolbar, and no Done button; on iPad the sheet may not be swipe-dismissable | Wrap PDFKitView in NavigationStack with a toolbar Done button calling showingPDF = false; guard the sheet so it only presents when pdfData != nil | 1 hr | YES |
| PERF-006 | RED | fatalError in MessageOutbox.init crashes production app | MessageOutbox.init calls fatalError() unconditionally (outside #if DEBUG) when SwiftData ModelContainer creation fails; any schema migration failure (after an app update) will permanently crash the app on every launch until reinstall | Replace fatalError with a do/catch that falls back to in-memory ModelContainer, matching the pattern in LocalSelahSession.swift lines 141-143; log the error but do not crash | 1 hr | YES |
| SAFE-003 | YELLOW | CSAM pipeline is reactive only — no proactive hash-scan | AmenChildSafetyService.prepareCSAMEscalation() handles manual reports and CF vision scan results; no proactive PhotoDNA/perceptual-hash scan on image upload was found; detectionSource values include ios_hash_match but no matching code was found | BACKEND GATE: confirm whether Backend/functions/src/mediaScanning.ts or functions/imageModeration.js performs hash-based CSAM scanning on every image upload; if not, implement before any public launch; document NCMEC registration status | Multi-day backend work | YES |
| SAFE-005 | YELLOW | Minors not blocked from public Discovery at iOS layer | AmenChildSafetyService.filterContentForMinor() is a client-side stub returning items unchanged; minor user profiles may appear in public discovery to unknown adults before the CF authoritative filter responds | Add iOS-layer check in DiscoveryService and AMENDiscoveryView: if currentUser.isMinor then remove minor's profile from public discovery results and hide profiles with isMinor=true from the discovery feed | 2–3 hrs | YES |
| PRIV-005 | YELLOW | AI features fire before first-run consent UI | DailyDigestService and SmartCommentService gate on bare UserDefaults booleans (consentDailyBrief, consentSmartComment) that could be set true by Remote Config or a prior session; no affirmative consent screen is shown before callModel fires | Design and implement a first-run AI consent sheet shown before the first DailyDigest fetch and before SmartComment is called; tie consent to ConsentStore (not bare UserDefaults) for consistency with BereanContextRAGService | 1–2 days design + dev | YES |
| PRIV-007 | YELLOW | Full privacy policy not accessible before login | WelcomeToAMENView shows a 3-bullet PrivacySummarySheet; AMENAuthLandingView has no privacy link; the full policy in AmenLegalDocumentContent.privacyPolicy is post-login only; GDPR Art.13 requires full disclosure before data collection begins at first launch | Add a link on AMENAuthLandingView that opens the full privacy policy text (either embed AmenLegalDocumentContent.privacyPolicy in a pre-auth sheet or link to https://amenapp.com/privacy); PrivacySummarySheet can remain as a companion | 2 hrs | YES |
| A11Y-002 | RED | LiquidGlassModifiers lack Reduce Transparency fallback | 5 glass modifiers (LiquidGlassStyle, InputGlassStyle, ActionPillStyle, FloatingPillStyle, SuggestionChipStyle) always render .ultraThinMaterial regardless of accessibilityReduceTransparency; text contrast fails for this accessibility population | Add @Environment(\.accessibilityReduceTransparency) private var reduceTransparency to all 5 structs and AdaptiveGlassModifier; in body() branch to Color(uiColor: .systemBackground) when reduceTransparency is true; follow the exact pattern in GlassMaterial.swift lines 44-67 | 2–3 hrs | YES |
| A11Y-003 | RED | LiquidGlassAnimations ignore Reduce Motion | MetaballMergeEffect, ElasticPressEffect, StickyEdgeDockEffect, LiquidGlassCardStyle, TabBarIconBounce, LiquidGlassButtonStyle, InstantFeedbackButtonStyle, PillTabButtonStyle, and GlassSheetContainer all call .animation() directly with spring values; none reads accessibilityReduceMotion | Add @Environment(\.accessibilityReduceMotion) to each struct; replace .animation(spring, value:) with .animation(Motion.adaptive(spring), value:); in MetaballMergeEffect disable blur when reduceMotion is true; in GlassSheetContainer use .scaleEffect(1.0) unconditionally when reduceMotion is true | 3–4 hrs | YES |
| FIRE-010 | YELLOW | createSpaceTier CF missing space-owner check | functions/src/spaces/callable.ts createSpaceTier validates caller auth but does not verify the caller owns or administers the target spaceId; any authenticated user can create a paid tier on any Space | After verifying auth, read spaces/{spaceId} from Firestore and check doc.data().leaderId === userId; throw permission-denied if not; deploy to us-east1 (us-central1 at quota) | 1 hr + deploy | YES |

---

## P2 MEDIUM — Should fix before submission but will not block review

| ID | Lane | Title | Exact Action | Est Time |
|---|---|---|---|---|
| AUTH-011 | YELLOW | DeleteAccountView confirmation uses try? on signOut | Replace try? Auth.auth().signOut() with authViewModel.signOut() from environment object to run full cleanup sequence | 30 min |
| SAFE-008 | YELLOW | Church notes AI consent edge not confirmed | Read BereanChurchNotesBridge.swift and ChurchNotesAIService.swift; confirm each AI call checks ConsentStore.shared.isEnabled(.graphToBerean) or a dedicated consent edge before sending to CF | 1 hr |
| FIRE-003 | YELLOW | /users top-level readable by all signed-in users | Audit exact fields on /users/{uid} root document; move PII fields to /private/ subcollection | 2 hrs |
| FIRE-008 | YELLOW | Duplicate /safetyAuditLog Firestore rule blocks | Remove the duplicate block in Global Resilience section (~line 3195); add comment explaining the first block at ~line 2982 supersedes it; deploy rules | 30 min + deploy |
| FIRE-009 | YELLOW | /testimonies unauthenticated read | T&S decision: add isSignedIn() guard if unauthenticated reads are unintended; deploy rules | 30 min + deploy |
| FIRE-013 | YELLOW | Several callables have enforceAppCheck: false | Enable App Check report-only mode on no-enforced callables; add rate-limiting from rateLimit.ts | 2 hrs + deploy |
| FIRE-016 | YELLOW | Rate limiting missing in functions/src callables | Import rateLimit.ts utility into scripture_getVerses, bereanIsland_trigger, writeWithBerean_assist, sermonCompanion_session; apply per-uid rate limits | 2 hrs + deploy |
| FIRE-020 | YELLOW | Storage uploads/approved publicly readable | Policy decision: add isSignedIn() guard or document public CDN delivery intent | 30 min + deploy |
| FIRE-021 | YELLOW | Three overlapping profile photo path names | After quarantine pipeline is deployed, consolidate to single path; add comment mapping iOS files to paths for now | 1 hr |
| FIRE-022 | YELLOW | Legacy MIME-type regex helpers on churchNotes paths | Replace isAudioType/isImageType/isVideoType with isAllowedAudioType/isAllowedImageType/isAllowedVideoType on lines 425-441; remove deprecated helpers; deploy storage rules | 1 hr + deploy |
| FIRE-023 | YELLOW | prayerOS prayer detail stored unencrypted | Implement application-layer encryption for the detail field using Cloud KMS before prayerOS goes public | 1–2 days backend |
| FIRE-025 | YELLOW | scripture_searchVerses fetches 200 docs — DoS risk | Add per-uid rate limiting (max 10 searches/min); cap Firestore fetch to 50 docs | 1 hr + deploy |
| BTN-005 | YELLOW | AmenConnectV2View workspace button is no-op | Wire to workspace/presence switcher sheet OR remove interactive affordance; update accessibilityLabel | 2 hrs |
| BTN-006 | YELLOW | Add to Calendar shows toast only | Implement EventKit EKEventStore authorization + event write OR hide button behind feature flag | 3–4 hrs |
| BTN-007 | YELLOW | Covenant post deep-link navigation stub | Implement post fetch by ID + NavigationLink destination to PostDetailView | 2 hrs |
| BTN-009 | YELLOW | AmenSpaceDetailView moderation sheet missing parent dismiss | Pass explicit onDismiss: { showModeration = false } closure to the moderation sheet presentation | 30 min |
| A11Y-001 | YELLOW | 112 files use hard-coded font sizes | Replace .font(.system(size: N)) with semantic styles (.caption2 for 10pt, .caption for 12pt, .footnote for 13pt); update .systemScaled extension to use UIFontMetrics.default.scaledValue(for:) | 1–2 days |
| A11Y-004 | YELLOW | Tab bar touch targets 40pt | Increase cameraButton inner frame to .frame(width: 44, height: 44); audit 250 files with sub-44pt frames | 2 hrs |
| A11Y-005 | YELLOW | Decorative images missing .accessibilityHidden(true) | Add .accessibilityHidden(true) to background gradients, dividers, logo watermarks, specular overlays starting with PostCard, HomeView, AMENTabBar, ProfileView | 2–3 hrs |
| A11Y-008 | YELLOW | GlassSheetContainer backdrop ignores reduceMotion | Replace direct .animation() calls with .animation(AmenMotion.sheetAnimation(reduceMotion), value: isVisible); skip scaleEffect when reduceMotion is true | 1 hr |
| A11Y-009 | YELLOW | FloatingActionBubble reads UIAccessibility directly | Convert to @Environment(\.accessibilityReduceMotion); fix MetaballBadge bounce chain guard | 1 hr |
| A11Y-010 | YELLOW | HighlightSweepModifier fires without reduceMotion check | Add @Environment(\.accessibilityReduceMotion); in body() skip overlay sweep when reduceMotion is true | 30 min |
| PERF-001 | YELLOW | HomeView bare Task{} in onReceive | Store Task handle in @State; cancel in onDisappear | 30 min |
| PERF-002 | YELLOW | AmenMinistryRoomDiscussionsTab bare Task{} in onAppear | Store Task; cancel in onDisappear alongside vm.stop() | 30 min |
| PERF-005 | YELLOW | DiscussionThreadService returns raw ListenerRegistration | Audit all call sites; convert to internal start/stop API | 2 hrs |
| PERF-009 | YELLOW | assertionFailure in AmenAIFeaturesService not in #if DEBUG | Wrap in #if DEBUG for consistency | 15 min |
| PERF-010 | YELLOW | try! ModelContainer in LocalSelahSession and LocalPostDraft | Replace with try and catch with log + disabled state | 30 min |
| PERF-012 | YELLOW | try! NSRegularExpression in AmenMentionParser | Replace with Regex literal (Swift 5.7+) or try? with assertionFailure comment | 30 min |
| PERF-013 | YELLOW | DispatchQueue.main.async without [weak self] in 9 files | Add [weak self] to non-singleton classes (VoiceDevotionalManager, VoiceRecorder) | 1 hr |
| PERF-014 | YELLOW | DispatchQueue.main.async in 25+ files instead of MainActor | Migrate to await MainActor.run{} or @MainActor class annotation | 1–2 days |
| SEC-001 | YELLOW | Firebase API key in GoogleService-Info.plist | Verify bundle-ID and SHA-1 app restrictions are set in Firebase console; add GoogleService-Info.plist to .gitignore; rotate key if repo has ever been public | 1 hr |
| SEC-007 | YELLOW | GPU background-tasks entitlement requires Apple approval | Confirm approved in Developer portal and provisioning profile; remove if not in use | 30 min |
| SEC-008 | YELLOW | location.push entitlement requires Apple approval | Confirm approved and provisioned; remove if not actively used in current release | 30 min |
| SEC-010 | YELLOW | Debug/release entitlements diverge | Confirm which entitlements file is assigned to Release build configuration; sync Siri and time-sensitive notification entries as needed | 1 hr |

---

## P3 LOW — Polish items; can ship without but address before 1.1

| ID | Description |
|---|---|
| BTN-008 | Verify WisdomLibraryHeroBanner production callsites always have a real NavigationLink destination |
| AUTH-001 | Document skipOnboarding() as a feature-sheet dismiss for future auditors |
| AUTH-012 | Confirm CI archives use Release configuration so AuthDebugView is stripped |
| SEC-003 | (Already fixed) Emulator useEmulator line removed |
| PRIV-006 | (Already fixed) os_log %{private}@ applied |

---

## RED Decision Briefs

### PRIV-001 — Three Missing NSUsageDescription Keys

**Problem:** NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, and NSLocationWhenInUseUsageDescription are absent from the production Info.plist at `AMENAPP/AMENAPP/Info.plist`. They exist only in `Info.plist.template` with generic placeholder text. iOS 17+ will terminate the app with a `com.apple.privacy` exception the first time any of these APIs is accessed, regardless of runtime permission check patterns in Swift code.

**Exact Fix (15 minutes):** Open `AMENAPP/AMENAPP/Info.plist` in Xcode or a text editor and add these three entries inside the root `<dict>`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>AMEN uses the microphone to record voice devotionals and voice messages.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>AMEN accesses your photo library to share images and videos in posts and messages.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>AMEN uses your location to find churches near you.</string>
```

Use AMEN-specific strings, not the template's generic placeholders. These strings appear in the iOS permission prompt and must describe the actual use case.

**Affected files:** AMENAPP/AMENAPP/Info.plist, VoiceRecordingEngine.swift (microphone), FileAttachmentHandler.swift + VideoAttachmentHandler.swift (photo library), FindChurchView.swift (location).

---

### SEC-006 — ITSAppUsesNonExemptEncryption Missing

**Problem:** App Store Connect requires this key for all submissions. Without it, every upload triggers an Export Compliance question that can block automated CI uploads and confuse reviewers. The app uses HTTPS/TLS for all network calls, which qualifies as encryption under US export regulations (EAR 742.15(b)).

**Options:**
1. Set to `false` — correct if the app uses ONLY standard OS TLS (no custom encryption, no custom cipher suites). This covers HTTPS, Firebase SDK encryption, and standard WebSocket TLS.
2. Set to `true` — required if the app implements custom encryption (e.g., the Signal-protocol E2EE in AMENEncryptionService.swift). If true, Apple requires an annual self-classification report to the US Bureau of Industry and Security. This is straightforward for most apps but requires legal sign-off.

**Recommendation:** The presence of AMENEncryptionService.swift with Signal-protocol Keychain keys suggests the app implements end-to-end encryption beyond standard TLS. Legal/engineering must decide whether AMENEncryptionService constitutes non-exempt encryption. If so, set to `true` and file the BIS self-classification. If AMENEncryptionService uses only Apple's CryptoKit/CommonCrypto (which are exempt), set to `false`.

**Exact Fix:** Add to Info.plist root `<dict>`:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>   <!-- or <true/> per legal decision above -->
```

---

### AUTH-006 — Terms and Privacy URL Liveness

**Problem:** The app hardcodes `https://amenapp.com/terms` and `https://amenapp.com/privacy` in OnboardingOnboardingView.swift, OnboardingFlowView.swift, and AboutAmenView.swift. App Store Review Guideline 5.1.1 states the privacy policy must be accessible, current, and accurately disclose data practices. The URLs must return live HTTP 200 documents before submission.

**Required document content for App Review:**
- Full COPPA disclosures (collection practices for minors, parental rights)
- KOSA disclosures (data practices for teens if applicable in jurisdiction)
- GDPR Article 13 disclosures (legal basis, retention periods, data subject rights)
- Third-party AI data sharing (Firebase/Google, Anthropic/Claude, NVIDIA NIM)
- Account deletion grace period (30-day disclosure, what happens at day 30)
- Contact information for privacy requests

**Action:** Confirm with counsel that both URLs serve complete documents before submitting to App Store. This cannot be auto-fixed from code.

---

### AUTH-013 — 30-Day Deletion Grace Period

**Problem:** DeleteAccountView.swift tells users their data will be permanently deleted after 30 days. AccountManagementService.softDeleteAccount() writes `deletedAt` and `deletionScheduledFor` Firestore fields. However, no Cloud Function, Cloud Scheduler job, or Firestore TTL policy was found in either `functions/` or `Backend/functions/src/` that reads `deletionScheduledFor` and executes the purge at day 30. If no such job exists, the 30-day disclosure is inaccurate, violating GDPR Article 17 (right to erasure) and App Store Guideline 5.1.1.

**Required backend job behavior:**
1. Read all `/users/{uid}` documents where `deletionScheduledFor` <= now and `accountStatus == 'pending_deletion'`
2. Execute AccountDeletionService equivalent server-side: delete Firestore subcollections, Storage files across all paths, Realtime Database nodes, Algolia records, and Firebase Auth account
3. Log deletion completion to `/safetyAuditLog` with `type: 'account_purge_complete'`
4. Schedule: run hourly or daily; must complete within 30 days of `deletionScheduledFor` timestamp

**Action:** Verify the job exists. If not, implement and deploy before App Store submission. This is a GDPR-critical item.

---

### SAFE-002 — Report + Block on Spaces and Prayer

**Problem:** SpaceCardView, PrayerRoomView, and AmenPrayerFeedView are public-facing UGC surfaces where bad actors can post harmful content (theology abuse, harassment, CSAM) and no in-context report or block affordance exists. Users must navigate away from the surface to block via UserProfileView, which most users will not do.

**Implementation guidance:**
- SpaceCardView: add context menu `.contextMenu { Button("Report Space") { … } }` wired to ModerationService.reportSpace(spaceId:)
- PrayerRoomView / AmenPrayerFeedView: add long-press or ellipsis menu on each prayer request card with two options: "Report Prayer Request" (SafetyReportingService.reportContent()) and "Block [Author]" (BlockService.block(uid:))
- All three surfaces can reuse PostCardReportSheet and BlockUserHelper from the existing infrastructure

---

### SAFE-003 — CSAM Hash-Scan Gap

**Problem:** The iOS CSAM pipeline (AmenChildSafetyService.prepareCSAMEscalation) and the backend NCMEC reporter (functions/ncmecReporter.js) are correctly architectured but only respond to user reports and CF vision scan classification. No code was found that computes a perceptual hash of uploaded images and compares against a CSAM database (e.g., PhotoDNA, NCMEC hash database, or Apple's NeuralHash-equivalent).

**Options:**
1. Integrate a third-party CSAM hash-check API (e.g., Project Protect by Thorn, AWS Rekognition Detect Moderation Labels) into the image upload Cloud Function
2. Use Apple's CSAM detection framework where available (restricted to specific use cases per Apple terms)
3. Register with NCMEC, obtain their hash database via NCMEC Connect, and implement server-side hash comparison

**Minimum required before public launch:** NCMEC registration. This is a legal step, not a code step. See DECISION_BRIEFS/A-01_NCMEC_Registration.md if it exists, or create one.

---

### SAFE-010 — Minor Guardian Portal OPEN-2

**Problem:** AmenChildSafetyService.isGuardianApprovedContact() lines 563-572 explicitly comments "OPEN-2 placeholder: document absent means guardian tools not yet active — allow." The result is that any minor without an active guardian setup can receive DMs from any mutual follow without guardian approval. On a COPPA-regulated platform this is a compliance risk.

**Immediate safe fix (30 min):** Change `return true` to `return false` in the absent-document fallback. This means minors without an active guardian link cannot send or receive DMs until the guardian portal is configured. This is the conservative COPPA-safe stance.

**Longer term:** Implement the guardian portal and resolve OPEN-2 with T&S Lead so that parents can approve contacts rather than the system defaulting to either allow or deny.

---

### BTN-001 — Spaces Paywall Bypass

**Problem:** AmenSpaceDetailView.swift lines 317 and 382 both contain FIXME A-005 markers. The hero `onJoin` and `PaywallOverlay.onJoin` closures both set `isSubscribed = true` immediately on tap with no server verification. Any user can join any paid Space for free.

**Fix pattern:**
```swift
// Before (bypass)
isSubscribed = true

// After (correct)
isJoining = true
Task {
    defer { isJoining = false }
    do {
        let result = try await AmenSpaceEntitlementService.shared.checkEntitlement(spaceId: space.id)
        if result.granted {
            try await SpaceMembershipService.shared.joinSpace(spaceId: space.id)
            isSubscribed = true
        } else {
            showPaywall = true
        }
    } catch {
        // show error
    }
}
```

---

### CREDENTIAL ROTATION

**Situation:** GoogleService-Info.plist is committed to git history and contains the Firebase API key (AIzaSy... pattern). The key is intentionally bundled per Firebase design, but if the repo has ever been public or has non-trusted contributors, the key may have been extracted.

**Action:**
1. Verify Firebase console: Go to Project Settings > API credentials > Key restrictions. Confirm the key is restricted to the exact bundle ID and SHA-1 fingerprints used in production.
2. If any doubt about exposure: rotate the key in Firebase console (Project Settings > Regenerate key), download a new GoogleService-Info.plist, and add GoogleService-Info.plist to .gitignore going forward.
3. Confirm all CI/CD pipelines inject the plist from a secret manager rather than committing it.

---

### NCMEC CYBERTIPLING REGISTRATION

**Status:** NCMEC registration cannot be confirmed from code. The backend files reference NCMEC submission but registration is a legal/business process.

**Action:** Contact NCMEC (cybertipline.org/submit_report) to register as an Electronic Service Provider before public launch. Registration is required to legally submit CyberTipline reports in the US. Without registration, the backend submission pipeline is architecturally correct but legally unactivated.

---

### FIREBASE RULES DEPLOY

**Current state:** Changes to Firestore and Storage rules are developed locally but not deployed. Rules must be deployed to take effect.

**Command (from repo root only):**
```bash
firebase deploy --only firestore:rules --project amen-5e359
firebase deploy --only storage --project amen-5e359
```

See DEPLOY_PLAN.md for full runbook.

---

### US-CENTRAL1 QUOTA WARNING

**Status:** us-central1 is at ~999-1000/1000 Cloud Run services. Any new function deployment to us-central1 will fail with HTTP 429.

**Action:** All new functions must deploy to us-east1. Add each new function to the Interim Region Table in docs/FUNCTION_INVENTORY.md. See docs/deploy-topology.md for the quota reclamation plan (522 DEAD services identified, requires human approval before deletion).
