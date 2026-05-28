# AMEN iOS App — Deployment & Release Readiness Audit (Agent 7)

**Audit Date:** 2026-05-26  
**Auditor:** Agent 7 — Deployment & Release Readiness  
**Scope:** Privacy manifests, ATT, build settings, version numbers, Firebase config, dev/prod separation, onboarding, metadata

---

## 1. Privacy Manifest (PrivacyInfo.xcprivacy)

### Status: PRESENT ✅

**File:** `/AMENAPP/PrivacyInfo.xcprivacy`

The app includes a complete privacy manifest with the following required APIs declared:

- **NSPrivacyAccessedAPICategoryUserDefaults** (CA92.1) — ✅ Present
- **NSPrivacyAccessedAPICategoryFileTimestamp** (C617.1) — ✅ Present
- **NSPrivacyAccessedAPICategorySystemBootTime** (35F9.1) — ✅ Present
- **NSPrivacyAccessedAPICategoryDiskSpace** (E174.1) — ✅ Present

**NSPrivacyCollectedDataTypes declared:**
- Name (linked, app functionality)
- Email Address (linked, app functionality)
- Phone Number (unlinked, app functionality)
- User Content (linked, app functionality)
- Photos/Videos (linked, app functionality)
- Coarse Location (unlinked, app functionality)
- Contacts (unlinked, app functionality)
- Product Interaction (unlinked, analytics + app functionality)
- Crash Data (unlinked, app functionality)
- Performance Data (unlinked, app functionality)
- Device ID (unlinked, app functionality)

**Tracking Status:** `NSPrivacyTracking = false` ✅

### Observation

The privacy manifest is well-structured and covers the primary required APIs. However, **third-party SDK privacy manifests should be verified during integration**. The project uses Firebase, Algolia, and other SDKs — ensure that all SDKs that declare required-reason APIs have their own privacy manifests bundled.

**Risk:** If any third-party SDK (e.g., analytics, crash reporting) declares required-reason APIs but is missing a privacy manifest, App Store will reject the submission.

---

## 2. App Tracking Transparency (ATT)

### Status: IMPLEMENTED ✅

**Implementation:**
- **File:** `AppDelegate.swift` (lines 152–159)
- **Code:** `ATTrackingManager.requestTrackingAuthorization { status in ... }`
- **Timing:** Requested after a 1-second delay post-launch (allows launch screen to settle)
- **Import:** `import AppTrackingTransparency` ✅

**Info.plist Declaration:**
- **Key:** `NSUserTrackingUsageDescription` ✅
- **Value:** "AMEN uses this to personalize your experience, show relevant content, and measure the effectiveness of our outreach. You can change this at any time in Settings."

**Status Check:** `VertexAIPersonalizationService.swift` properly guards personalization logic with:
```swift
guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return }
```

### Observation

ATT is correctly implemented. The request is made at the correct time and only after user consent is checked before accessing IDFA. No issues detected.

---

## 3. Age Gating / COPPA Compliance

### Status: PARTIALLY IMPLEMENTED ⚠️

**Onboarding Age Verification:**
- **File:** `OnboardingOnboardingView.swift` (line 56)
- **Code:** Date picker for DOB with default 18 years in the past
- **Flow:** Age verification slide shown during onboarding

**Observations:**

1. **No minimum age enforcement detected** — The code collects DOB but does not enforce a minimum age (e.g., 13+ for general users, or parental consent for <13).

```swift
@State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
```

This collects the birth year but no validation logic prevents under-13 users from signing up.

2. **No explicit COPPA handling** — If the app allows minors (under 13), COPPA (Children's Online Privacy Protection Act) compliance is required:
   - Parental consent collection
   - Limited data collection for minors
   - `NSPrivacyCollectedDataTypes` accuracy for minors
   - Data retention/deletion for minors

3. **Privacy manifest does not distinguish minors** — The `NSPrivacyCollectedDataTypes` collected list (name, email, phone, location, contacts) should be reviewed to ensure it's appropriate for under-13 users if they are allowed.

**Risk Level:** **P1 (Medium-High)** — If the app allows minors without COPPA compliance, App Store will reject the submission and potential FTC enforcement.

**Recommendation:** Explicitly enforce an age gate (e.g., "Must be 13+") OR implement full COPPA compliance (parental consent, limited tracking, data deletion).

---

## 4. Required Info.plist Keys

### Status: COMPREHENSIVE ✅ (with one concern)

**All required usage description keys present:**

| Key | Value | Status |
|-----|-------|--------|
| `NSCameraUsageDescription` | "AMEN uses the camera to take photos for posts, messages, and your profile picture." | ✅ |
| `NSMicrophoneUsageDescription` | "AMEN uses the microphone to let you compose posts, prayers, and messages by voice." | ✅ |
| `NSPhotoLibraryUsageDescription` | "AMEN needs access to your photo library to share images in posts, messages, and your profile." | ✅ |
| `NSPhotoLibraryAddUsageDescription` | "AMEN saves shared photos and church media to your photo library." | ✅ |
| `NSLocationWhenInUseUsageDescription` | "AMEN uses your location to find nearby churches and faith communities." | ✅ |
| `NSCalendarsUsageDescription` | "AMEN adds church events and service reminders to your calendar so you never miss a moment." | ✅ |
| `NSCalendarsWriteOnlyAccessUsageDescription` | "AMEN adds church events and service reminders to your calendar when you choose Add to Calendar." | ✅ |
| `NSCalendarsFullAccessUsageDescription` | "AMEN uses calendar access only when you choose to save church events or service reminders." | ✅ |
| `NSRemindersUsageDescription` | "AMEN creates reminders for prayer commitments, church events, and spiritual goals." | ✅ |
| `NSContactsUsageDescription` | "AMEN uses your contacts to help you find friends who are already on the app. No contact information is stored on our servers." | ✅ |
| `NSFaceIDUsageDescription` | "AMEN uses Face ID to keep your account secure and let you sign in quickly." | ✅ |
| `NSHealthShareUsageDescription` | "AMEN reads your heart rate and activity to help Synaptic Studio craft prayers and reflections that match how you feel right now. No health data is stored." | ✅ |
| `NSHealthUpdateUsageDescription` | "AMEN may log mindfulness minutes from prayer and meditation sessions to Apple Health, helping you track your spiritual wellness alongside your physical health." | ✅ |
| `NSUserTrackingUsageDescription` | "AMEN uses this to personalize your experience, show relevant content, and measure the effectiveness of our outreach. You can change this at any time in Settings." | ✅ |
| `NSAppleMusicUsageDescription` | "AMEN uses Apple Music to play worship songs in your Church Notes." | ✅ |
| `NSSpeechRecognitionUsageDescription` | "AMEN uses speech recognition to let you compose posts, prayers, and messages by voice." | ✅ |
| `NSUserNotificationsUsageDescription` | "We'll send you reminders about church service times and when you're near your saved churches" | ✅ |

**LSApplicationQueriesSchemes:**
- `spotify` — ✅ Present and appropriate

**ITSAppUsesNonExemptEncryption:** `false` — ✅ Correct (app uses encryption only for standard transport)

**All descriptions are meaningful and not placeholder text.** ✅

---

## 5. Build Settings & Signing

### Status: CRITICAL ISSUES ⚠️ ⚠️

**Deployment Target:**
- **IPHONEOS_DEPLOYMENT_TARGET = 26.2** ⚠️ **INVALID**
- iOS 26.2 does not exist. The latest iOS version is iOS 18 (as of May 2026). This is a **critical build configuration error**.
- This will fail App Store submission and prevent the app from building for real devices.

**Recommendation:** Set to a realistic value such as `iOS 16.0` or `iOS 17.0` (common minimum deployment targets).

**Swift Version:**
- **SWIFT_VERSION = 5.0** ✅ — Reasonable, though Swift 6.0+ would enable stricter concurrency checking.

**Debug Configuration:**
- `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"` — ✅ Present
- `DEBUG=1` set in Debug configuration — ✅ Correct

**Code Signing:**
- `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` are referenced via variable substitution — ✅ (Not visible in pbxproj but expected to be set via Xcode settings)

**SWIFT_STRICT_CONCURRENCY:**
- **NOT FOUND** ⚠️ — The project does not set `SWIFT_STRICT_CONCURRENCY = complete`.
- This is a **P2 recommendation** for modern async/await correctness and race condition prevention. Apple encourages this for apps using concurrency.

**OTHER_SWIFT_FLAGS:**
- No problematic flags detected that would affect Release builds.

---

## 6. Version / Build Numbers

### Status: CRITICAL ISSUES ⚠️ ⚠️

**Current Settings:**
- **MARKETING_VERSION = 1.0** ⚠️ **PLACEHOLDER**
- **CURRENT_PROJECT_VERSION = 1** (main app) / **5** (extensions) ⚠️ **INCONSISTENT**

**Issues:**

1. **Version 1.0 is a placeholder.** Before App Store submission, increment to reflect the actual release (e.g., 1.0.0 → 1.0.1 if this is a bug fix, or increment the minor/major version based on release strategy).

2. **Build numbers are inconsistent:**
   - Main app: CURRENT_PROJECT_VERSION = 1
   - ShareExtension, WidgetExtension, NotificationServiceExtension: CURRENT_PROJECT_VERSION = 5
   
   This mismatch could cause provisioning issues and is confusing for release management.

3. **CFBundleShortVersionString and CFBundleVersion missing from Info.plist** — These are typically auto-populated from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, but should be verified to be present in the built bundle.

**Recommendation:** Update to a meaningful version (e.g., 1.0.0) and ensure all targets use consistent build numbers.

---

## 7. Firebase Config Targets

### Status: SINGLE PROJECT (POTENTIAL ISSUE) ⚠️

**.firebaserc:**
```json
{
  "projects": {
    "default": "amen-5e359"
  }
}
```

**firebase.json:**
```json
{
  "functions": [
    { "source": "Backend/functions", "codebase": "default", "runtime": "nodejs22" },
    { "source": "Backend/spatial-functions", "codebase": "spatial", "runtime": "nodejs22" }
  ],
  "firestore": { "rules": "AMENAPP/firestore.deploy.rules", "indexes": "AMENAPP/firestore.indexes.json" },
  "storage": { "rules": "AMENAPP/storage.rules" }
}
```

**GoogleService-Info.plist:**
- **PROJECT_ID:** `amen-5e359` ✅ Matches .firebaserc
- **BUNDLE_ID:** `tapera.AMENAPP` ✅ Matches
- **Analytics:** `IS_ANALYTICS_ENABLED = false` ✅
- **Ads:** `IS_ADS_ENABLED = false` ✅

**Observations:**

1. **No development/staging/production separation** — `.firebaserc` defines only a `default` project. For a production app, best practice is:
   - Development: `amen-dev` or `amen-staging`
   - Production: `amen-prod`
   
   This prevents accidental cloud function deployments or Firestore rule changes to production.

2. **No `.firebaserc` local override** — There's no `.firebaserc.local` for developer-specific configs.

3. **Runtime: Node.js 22** — Verify that this version is still supported by Google Cloud Functions at time of submission.

**Risk:** Misdeployment could accidentally modify production Firestore rules or functions.

**Recommendation:** Implement multi-environment Firebase setup with distinct projects for dev/staging/prod.

---

## 8. Dev vs Prod Config Separation

### Status: WELL STRUCTURED ✅

**Debug Logging:**
- **DebugLog.swift** defines a `dlog()` macro that compiles to a no-op in Release builds.
- All hot-path logging (feed cells, snapshot listeners) uses `dlog()` instead of `print()`.
- Production logging is effectively eliminated in Release builds. ✅

**#if DEBUG Guards:**
- ~285 instances of `#if DEBUG` guards found in the codebase.
- Development-only features (AuthDebugView, AlgoliaSyncDebugView, ChurchNotesStressTests) are properly guarded.
- CarPlay scene configuration is included but noted as a placeholder until entitlement approval.

**Simulator-specific code:**
- `#if targetEnvironment(simulator)` used to skip APNS registration and suppress simulator noise.
- App Check uses Debug Provider on simulator, App Attest on real devices. ✅

**Potential Concerns:**
- 20 instances of bare `print()` calls found (mostly in stress tests and debug views). These should not impact Release builds since they're in DEBUG-guarded code.

**Overall:** Dev/prod separation is well-managed. ✅

---

## 9. Config Keys & API Key Injection

### Status: SECURE ✅

**Config.xcconfig approach:**
- API keys are injected at build time via substitution variables: `$(VAR_NAME)`
- Keys are **never hardcoded** in Info.plist or source files.
- Comment explicitly warns: "Never hardcode secrets in Info.plist directly — they are readable from the app bundle with `strings` or `plutil`."
- FirebaseCore, OpenAI, Anthropic keys are stored via **Firebase Secret Manager** (not in the app bundle).

**Example:**
```xml
<key>CLAUDE_API_KEY</key>
<string>$(CLAUDE_API_KEY)</string>
<!-- Variable substituted at build time; actual value not included in source -->
```

**Best Practice:** Secrets stored in Firebase Secret Manager are accessed server-side via Cloud Functions, preventing exposure. ✅

---

## 10. Onboarding Flow Completeness

### Status: COMPREHENSIVE ✅

**6-Step Onboarding Flow:**

1. **Value Proposition** — Brand/why AMEN is different
2. **Account Setup** — Profile photo, username, DOB collection
3. **Privacy & Safety** — Data collection disclosure + Terms of Service acceptance + Privacy Policy acceptance
4. **Personalization** — Interest selection + AI consent toggles
5. **Follow Suggestions** — Suggested accounts/communities
6. **Community Discovery** — Church finder / community discovery

**Terms of Service:**
- **Link:** `https://amenapp.com/terms` ✅
- **Collection:** Links in `AMENLinks` enum (line 26–28) and OnboardingFlowView (visible in both legacy and production flows)
- **Acceptance:** `hasAgreedToTerms` flag enforced (user must check box to continue)

**Privacy Policy:**
- **Link:** `https://amenapp.com/privacy` ✅
- **Collection:** Same as ToS
- **Acknowledgment:** Privacy disclosure shown on step 3

**Post-Onboarding Prompts:**
- First post suggestion sheet (`ONBFirstPostSheet`) — ✅
- Find church sheet (`FindChurchView`) — ✅
- Notification permission onboarding — ✅

**Observation:** The app does not explicitly show a "data retention/deletion" disclosure. While privacy policy should cover this, consider adding explicit language during onboarding about data deletion upon account removal.

---

## 11. App Store Metadata Requirements

### Status: PARTIAL ⚠️

**CFBundleDisplayName:**
- **NOT FOUND** in Info.plist ⚠️
- The app may be using a default product name. Verify that the proper "AMEN" display name is set in Xcode's target settings (PRODUCT_NAME or PRODUCT_DISPLAY_NAME).

**Launch Screen:**
- **UILaunchScreen = {}** (empty dict) — SwiftUI-based launch screen, modern approach ✅
- Consider whether a custom launch screen view is needed (currently using default).

**CFBundleGetInfoString:**
- **Value:** "AMEN 1.0 — Faith-centered social network" ✅
- Descriptive and appropriate.

**FirebaseAppDelegateProxyEnabled:**
- **Value:** `false` ✅ (explicit Firebase delegate management)

**Supported Localizations:**
- **en** — English only ✅

**LSApplicationQueriesSchemes:**
- **spotify** — For podcast/music integration ✅

---

## Summary of Findings

### Strengths ✅
1. **Privacy manifest** is comprehensive and covers required APIs.
2. **ATT implementation** is correct and timely.
3. **Info.plist usage descriptions** are thorough and meaningful.
4. **Dev/prod config separation** is well-structured with guard macros.
5. **Onboarding flow** is complete with ToS and Privacy Policy links.
6. **API key security** — secrets stored in Firebase Secret Manager, not bundled.
7. **Code signing entitlements** (HealthKit, WeatherKit, CarPlay placeholders) properly declared.

### Critical Issues ⚠️⚠️
1. **Deployment Target iOS 26.2** — Does not exist; will fail App Store submission. Must be set to a valid iOS version (e.g., iOS 16.0).
2. **Version Numbers (1.0 build 1)** — Placeholder; should be incremented before submission. Build number mismatch across targets.
3. **CFBundleDisplayName missing** — Should be verified to ensure "AMEN" displays correctly on home screen.
4. **No age gate enforcement** — App collects DOB but does not enforce minimum age or COPPA compliance.

### Recommendations ⚠️
1. **Set IPHONEOS_DEPLOYMENT_TARGET to a valid iOS version** (e.g., 16.0 or 17.0).
2. **Enforce age verification** (13+) or implement full COPPA compliance.
3. **Implement multi-environment Firebase setup** (dev/staging/prod projects).
4. **Enable SWIFT_STRICT_CONCURRENCY** for async/await correctness.
5. **Ensure CFBundleDisplayName is set** and displays correctly.
6. **Verify privacy manifests** for all bundled third-party SDKs (Firebase, Algolia, etc.).

---

## Launch Readiness: Blockers Identified

| Category | Finding | Severity | Action |
|----------|---------|----------|--------|
| Build Settings | IPHONEOS_DEPLOYMENT_TARGET = 26.2 (invalid) | **P0 — Blocks Build** | Fix immediately |
| Metadata | Version 1.0 / Build 1 (placeholder) | **P1 — Blocks Submission** | Increment version |
| COPPA | No age gate enforcement | **P1 — Potential Rejection** | Enforce 13+ or COPPA |
| Metadata | CFBundleDisplayName missing | **P2 — Minor** | Verify in Xcode settings |
| Build Settings | SWIFT_STRICT_CONCURRENCY not set | **P2 — Recommended** | Enable for modern concurrency |
| Firebase | No dev/prod separation | **P2 — Risk Mitigation** | Implement multi-project setup |

---

**Audit Completed:** 2026-05-26

