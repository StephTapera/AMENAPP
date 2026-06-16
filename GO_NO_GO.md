# App Store Readiness — GO / NO-GO Assessment
Branch: app-store-readiness-overnight
Audit date: 2026-06-16
Auditor: Claude Sonnet 4.6 overnight autonomous pass
Total findings: 106 | Blocking: 17 | Applied auto-fixes: 4

---

## Verdict: NO-GO

**Justification:** 17 blocking findings remain open, including 2 P0s (paywall bypass and COPPA guardian fallback), 13 P1s spanning safety, privacy, accessibility, security, and App Store compliance, and 2 additional P1s (A11Y-002, A11Y-003) that will cause Apple's automated accessibility scan to reject the binary. The 4 auto-fixes applied are GREEN improvements only and do not clear any P0 or P1 blocker. The app cannot be submitted to App Store Connect in its current state without triggering at least 5 categories of App Store Review rejection (Safety 1.1, Performance 2.1, Design 4.0, Legal 5.1.1, Business 3.1).

**Estimated time to clear all blocking items:** 3–5 engineering days (code fixes) + legal/T&S reviews running in parallel.

---

## Build Readiness Assertion (Static Checks — NOT a Build Claim)

These checks are derived from static code analysis. A full build and device test is still required.

- [x] No duplicate file inclusions detected in audited source paths
- [x] No orphaned Berean constitutional system — BereanConstitutionalTrustView and related files confirmed present
- [x] .md documentation files are not observed being resource-copied into the binary (no Copy Bundle Resources phase includes .md)
- [x] CSAM escalation imports present — AmenChildSafetyService.swift exists and imports Foundation/FirebaseFirestore
- [x] No debug bypass code outside #if DEBUG — bypassAuthForTesting(), AuthDebugView, and all debug helpers confirmed guarded
- [x] No committed secrets detected in TypeScript source (Backend/functions/src)
- [ ] MISSING: NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSLocationWhenInUseUsageDescription in production Info.plist (PRIV-001)
- [ ] MISSING: ITSAppUsesNonExemptEncryption in production Info.plist (SEC-006)
- [ ] UNVERIFIED: GoogleService-Info.plist is committed with a Firebase API key; bundle ID restriction must be confirmed in Firebase console (SEC-001)

---

## Canonical Build Command — Human Runs This

```bash
# Acquire build lock first (per CLAUDE.md protocol)
echo "session:$(date +%Y%m%d%H%M) app-store-readiness build" > "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/.build-lock"

xcodebuild \
  -workspace "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP.xcworkspace" \
  -scheme AMENAPP \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -clonedSourcePackagesDirPath "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/SourcePackages.nosync" \
  -derivedDataPath "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/DerivedData.nosync" \
  clean build 2>&1 | tee "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/deploy-logs/build-$(date +%Y%m%d%H%M).log"

# Release build lock on completion
rm "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/.build-lock"
```

**Expected outcome:** BUILD SUCCEEDED with 0 errors. If build fails, check:
1. FirebaseAI iOS-27 SDK error (known pre-existing, tracked in prior audit)
2. Missing target membership for new Swift files in NoteGive/, DailyVerseCard.swift, VisitVerificationService.swift

---

## P0 Blockers Remaining

| ID | Title | Lane | Exact Human Action |
|---|---|---|---|
| BTN-001 | Spaces Join/Paywall bypasses entitlement check | RED | Wire both onJoin closures in AmenSpaceDetailView.swift (lines 317 and 382) to AmenSpaceEntitlementService.checkEntitlement() + Firestore membership write; add @State var isJoining Bool guard |
| SAFE-010 | Minor guardian approval falls back to allow when document absent | YELLOW | Change `return true` to `return false` in AmenChildSafetyService.isGuardianApprovedContact() fallback (lines 563-572); escalate OPEN-2 to T&S Lead |

---

## P1 Blockers Remaining

| ID | Title | Lane | Exact Human Action |
|---|---|---|---|
| PRIV-001 | Three NSUsageDescription strings missing from Info.plist | RED | Add NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSLocationWhenInUseUsageDescription to AMENAPP/AMENAPP/Info.plist with AMEN-specific purpose strings |
| SEC-006 | ITSAppUsesNonExemptEncryption missing | RED | Add `<key>ITSAppUsesNonExemptEncryption</key><false/>` (or `<true/>` per E2EE legal decision) to Info.plist |
| SAFE-002 | Report+Block absent from SpaceCardView, PrayerRoomView, AmenPrayerFeedView | RED | Add context-menu report/block affordances to all three views wired to ModerationService and SafetyReportingService |
| AUTH-004 | Google re-auth on account deletion shows text only | YELLOW | Implement GIDSignIn.sharedInstance.signIn() flow in DeleteAccountView.swift ReauthenticationSheet Google branch |
| AUTH-006 | Terms/Privacy URLs must serve live legal documents | RED | LEGAL GATE: counsel confirms https://amenapp.com/terms and https://amenapp.com/privacy serve App Review-compliant documents |
| AUTH-013 | 30-day deletion disclosure not backed by server purge job | RED | BACKEND GATE: verify or deploy Cloud Scheduler job that purges accounts after 30 days per deletionScheduledFor field |
| AUTH-009 | AccountRecoveryView soft-delete has no re-auth guard | YELLOW | Gate deleteAccount() in AccountRecoveryView behind ReauthenticationSheet from DeleteAccountView |
| BTN-002 | 26 AdaptiveComposer card buttons are silent stubs | RED | Wire each stub to backend action OR disable with .disabled(true) + accessibilityHint("Coming soon") |
| BTN-003 | VisitConfirmationBanner has no loading guard | RED | Add @State private var isConfirming = false; disable both buttons during async operation |
| BTN-004 | GivingImpactView PDF sheet has no dismiss button | RED | Wrap PDFKitView in NavigationStack with toolbar Done button |
| PERF-006 | fatalError in MessageOutbox.init crashes production app | RED | Replace fatalError with do/catch fallback to in-memory ModelContainer |
| SAFE-003 | CSAM pipeline reactive only — no proactive hash-scan | YELLOW | BACKEND/LEGAL GATE: implement server-side hash-based CSAM scan on image upload; register with NCMEC |
| SAFE-005 | Minors not blocked from public Discovery at iOS layer | YELLOW | Add isMinor check in DiscoveryService and AMENDiscoveryView to remove minor profiles from discovery results |
| PRIV-005 | Berean AI fires before first-run AI consent UI | YELLOW | Design and implement first-run AI consent sheet; tie to ConsentStore |
| PRIV-007 | Full privacy policy not accessible before login | YELLOW | Add full privacy policy link to AMENAuthLandingView |
| A11Y-002 | LiquidGlassModifiers lack Reduce Transparency fallback | RED | Add accessibilityReduceTransparency check to all 5 glass modifier structs following GlassMaterial.swift pattern |
| A11Y-003 | LiquidGlassAnimations ignore Reduce Motion | RED | Add accessibilityReduceMotion check to 8 animation paths; replace direct .animation() calls with Motion.adaptive() |
| FIRE-010 | createSpaceTier CF missing space-owner check | YELLOW | Read spaces/{spaceId}, verify leaderId === request.auth.uid, throw permission-denied if not; deploy to us-east1 |

---

## Consolidated Morning Action List (Ordered, Copy-Pasteable)

Execute in this order. Items 1-5 block everything else. Items 6-12 can be parallelized across engineers.

1. **[P0 SAFETY — 30 min] Fix minor guardian DM fallback**
   File: `AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift` lines 563-572
   Change: `return true` → `return false` in absent-document branch
   Then: Escalate OPEN-2 to T&S Lead for guardian portal timeline

2. **[P1 COMPLIANCE — 15 min] Add three missing NSUsageDescription strings to Info.plist**
   File: `AMENAPP/AMENAPP/Info.plist`
   Add: NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription, NSLocationWhenInUseUsageDescription
   See HUMAN_GATE_QUEUE.md Decision Brief PRIV-001 for exact strings

3. **[P1 COMPLIANCE — 20 min + legal] Add ITSAppUsesNonExemptEncryption to Info.plist**
   File: `AMENAPP/AMENAPP/Info.plist`
   Decision required: `<false/>` (TLS-only) or `<true/>` (E2EE counts)
   Consult counsel on AMENEncryptionService.swift Signal-protocol implementation

4. **[P0 BUSINESS — 1-2 hrs] Fix Spaces Join paywall bypass**
   File: `AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDetailView.swift` lines 317 and 382
   Wire both onJoin closures to AmenSpaceEntitlementService.checkEntitlement() + Firestore membership write
   See HUMAN_GATE_QUEUE.md Decision Brief BTN-001

5. **[P1 LEGAL — non-code] Verify Terms and Privacy URLs are live**
   URLs: https://amenapp.com/terms and https://amenapp.com/privacy
   Confirm with counsel that both serve App Review-compliant documents
   Cannot submit to App Store without this confirmation

6. **[P1 SAFETY — 3-4 hrs] Add Report+Block to Spaces and Prayer surfaces**
   Files: SpaceCardView.swift, PrayerRoomView.swift, AmenPrayerFeedView.swift
   Wire to ModerationService and SafetyReportingService

7. **[P1 AUTH — 2-3 hrs] Fix Google re-auth on account deletion**
   File: `AMENAPP/AMENAPP/DeleteAccountView.swift` ReauthenticationSheet Google branch
   Implement GIDSignIn.sharedInstance.signIn() + OAuthCredential + reauthenticate()

8. **[P1 AUTH — 1-2 hrs] Add re-auth guard to AccountRecoveryView**
   File: `AMENAPP/AMENAPP/RecoveryOS/AccountRecoveryView.swift`
   Gate deleteAccount() behind ReauthenticationSheet before calling softDeleteAccount()

9. **[P1 PERFORMANCE — 1 hr] Fix MessageOutbox fatalError**
   File: `AMENAPP/AMENAPP/GlobalResilience/MessageOutbox.swift` init (line ~95)
   Replace `fatalError(...)` with do/catch + in-memory ModelContainer fallback

10. **[P1 DESIGN — 1-2 days] Fix 26 AdaptiveComposer stub buttons**
    Files: AttachmentCardsA.swift, AttachmentCardsB.swift, AttachmentCardsC.swift
    For each button: wire to backend OR add .disabled(true) with accessibilityHint("Coming soon")
    Priority: RSVP, Poll vote, Checklist stubs that update local UI but don't persist

11. **[P1 DESIGN — 3-4 hrs] Fix LiquidGlass Reduce Motion and Reduce Transparency**
    Files: LiquidGlassModifiers.swift (A11Y-002), LiquidGlassAnimations.swift (A11Y-003)
    Follow GlassMaterial.swift pattern for Reduce Transparency; follow Motion.adaptive() for Reduce Motion

12. **[P1 DESIGN — 1 hr each] Fix BTN-003 and BTN-004**
    BTN-003: Add isConfirming guard to VisitConfirmationBanner.swift
    BTN-004: Add NavigationStack + Done button to GivingImpactView PDF sheet

13. **[P1 BACKEND — 1 hr + deploy] Fix createSpaceTier space-owner check**
    File: `functions/src/spaces/callable.ts`
    Add space ownership check; deploy to us-east1; add to Interim Region Table

14. **[P1 LEGAL/BACKEND — multi-day] Verify 30-day deletion purge job exists**
    Confirm Cloud Scheduler job purges accounts after deletionScheduledFor date
    If job doesn't exist: implement and deploy before submission

15. **[P1 SAFETY/LEGAL — multi-day] NCMEC registration + CSAM hash-scan**
    Register with NCMEC as Electronic Service Provider
    Confirm or implement server-side hash-based CSAM scan on image upload

16. **[P1 PRIVACY — 1-2 days] First-run AI consent sheet (PRIV-005)**
    Design consent sheet explaining data sent to AI providers (Firebase/Google, Anthropic, NVIDIA)
    Tie to ConsentStore; show before first DailyDigest fetch and SmartComment call

17. **[P1 PRIVACY — 2 hrs] Full privacy policy accessible pre-login (PRIV-007)**
    Add privacy policy link to AMENAuthLandingView
    Either embed AmenLegalDocumentContent.privacyPolicy or link to external URL

18. **[POST-SUBMISSION PREP] Firebase rules deploy**
    Apply FIRE-008, FIRE-022, FIRE-009, FIRE-020 fixes to rules files
    Then: `firebase deploy --only firestore:rules,storage --project amen-5e359`
    See DEPLOY_PLAN.md for full runbook

19. **[POST-SUBMISSION PREP] Deploy new undeployed Cloud Functions**
    Rename `selahConnection 2.ts` first
    Deploy Group 7 functions to us-east1 per DEPLOY_PLAN.md
    Add all to Interim Region Table in docs/FUNCTION_INVENTORY.md

---

## What Was Fixed Tonight

4 GREEN fixes were applied to the working tree on branch `app-store-readiness-overnight`:

| Fix | File | Change |
|---|---|---|
| A11Y-006 | AMENAPP/AMENAPP/AMENTabBar.swift | Added .accessibilityValue to tab bar buttons for badge count announcement |
| PRIV-006 | AMENAPP/AMENAPP/AMENLogger.swift | Changed os_log format from %{public}@ to %{private}@ |
| SEC-003 | AMENAPP/AMENAPP/CloudFunctionsService.swift | Removed dead commented-out emulator useEmulator line |
| SAFE-007 | AMENAPP/AMENAPP/PrivacySettingsView.swift | Wired PermissionsCenterView into Privacy Settings under Capabilities section |

See AUTOFIX_CHANGELOG.md for full details on each fix.

---

## Summary Scorecard

| Category | Total Findings | Blocking | Pass | Fixed Tonight |
|---|---|---|---|---|
| Auth | 13 | 4 | 9 | 0 |
| Safety / COPPA | 10 | 5 | 5 | 1 (SAFE-007 wiring) |
| Privacy | 8 | 3 | 5 | 1 (PRIV-006) |
| Firestore / Backend Security | 25 | 1 | 14 | 0 |
| Storage | 5 | 0 | 2 | 0 |
| Buttons / UI | 12 | 5 | 3 | 0 |
| Accessibility | 10 | 2 | 4 | 1 (A11Y-006) |
| Performance | 16 | 1 | 8 | 0 |
| Security / Secrets | 12 | 1 | 9 | 1 (SEC-003) |
| **TOTAL** | **106** | **17** | **59** | **4** |
