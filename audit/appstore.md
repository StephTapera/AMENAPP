# App Store Compliance & Metadata Audit

**Date:** 2026-05-28  
**Branch:** audit/2026-05-28  
**Auditor:** Claude Code (automated static analysis)

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `Info.plist:41` | **Blocker** | Permission string key | `NSUserNotificationsUsageDescription` is not a valid Info.plist key. The correct key is `NSUserNotificationsUsageDescription` does not exist — Apple's actual key is **`NSUserNotificationUsageDescription`** (no plural). The real push-notification permission is **not** declared via a plist key at all; push is requested at runtime via `UNUserNotificationCenter.requestAuthorization`. This invalid key is dead weight and may confuse App Review automated tooling. Remove it. |
| `Info.plist:103-104` | **Blocker** | ATT / Privacy | `NSUserTrackingUsageDescription` is present, but `PrivacyInfo.xcprivacy` sets `NSPrivacyTracking = false` and `NSPrivacyTrackingDomains` is empty. The ATT dialog is unconditionally requested at app launch (`AMENAPPApp.swift:316`). Apple's ATT rules require the dialog to be shown only when the app actually uses tracking. If the app collects no cross-app/cross-site tracking data, `NSUserTrackingUsageDescription` must be removed and the `ATTrackingManager.requestTrackingAuthorization` call must be deleted. If it does collect tracking data, `NSPrivacyTracking` must be `true` and domains listed. The current state is contradictory and will likely cause App Review rejection. |
| `AMENAPP.entitlements:5` | **Blocker** | Entitlements | `aps-environment` is set to `development` in the non-release entitlements file. The release entitlements (`AMENAPP.release.entitlements`) correctly uses `production`. Confirm that the App Store archive build configuration maps to the release entitlements file — if the wrong file is used, push notifications will silently fail in production builds on user devices. |
| `Info.plist:65-68` | **Blocker** | Secrets in bundle | `SPOTIFY_CLIENT_SECRET` is stored in Info.plist (loaded from `Config.xcconfig` at build time). Even via xcconfig substitution, the resolved value ends up readable in the app binary/bundle via `strings` or `plutil`. A client secret should never ship inside an app bundle. Move Spotify token exchange to a Cloud Function that proxies requests without exposing the secret client-side. |
| `GivingInAppSheet.swift:270-279` + `GivingInAppSheet.swift:401` | **Blocker** | Payments compliance | The "Donate with Card" fallback button calls `withAnimation { showSuccess = true }` immediately without actually processing a payment (line 279 comment: `// TODO: Present Stripe payment sheet for non-Apple Pay users`). Similarly, `paymentAuthorizationController(_:didAuthorizePayment:handler:)` at line 401 also has `// TODO: Send payment.token.paymentData to your Stripe backend` — the payment token is never actually sent. Users without Apple Pay will see a success screen without a real charge. This is fraudulent UX and will cause rejection under guideline 3.1 and a chargebacks/legal issue. |
| `PrivacyInfo.xcprivacy` (entire file) | **Blocker** | Privacy manifest — missing data type | The manifest does not declare `NSPrivacyCollectedDataTypeUserID`. The app collects Firebase Auth UIDs, links them to name, email, posts, messages, and health data. UserID is a required data type when collecting linked identifiers. Omission will fail App Store automated privacy report validation. |
| `PrivacyInfo.xcprivacy` (entire file) | **Blocker** | Privacy manifest — missing data type | The app processes **financial information** (Stripe payments, Apple Pay, subscription prices, StoreKit purchases, mentorship plan fees). `NSPrivacyCollectedDataTypePaymentInfo` or `NSPrivacyCollectedDataTypeFinancialInfo` is not declared in the manifest. |
| `Info.plist:105-108` | **High** | Entitlement/permission scope | `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` are declared for HealthKit. Multiple files (`BreathingExerciseView.swift`, `SynapticStudioView.swift`, `MovementWellnessView.swift`, `GroundingExerciseView.swift`) use `HKHealthStore`. However, no `com.apple.developer.healthkit` entitlement exists in either `.entitlements` file. The app will crash at runtime on any HealthKit call without this entitlement. Additionally, a faith social app using HealthKit requires a specific App Store category and a convincing justification to App Review. |
| `AMENAPP.entitlements:12` | **High** | Entitlements — unjustified | `com.apple.developer.background-tasks.continued-processing.gpu` is present in both entitlements files. This is a restricted entitlement for ML model inference tasks. There is no visible CoreML on-device inference (the `MLNotificationClassifier.swift` uses CoreML but only for classification, not GPU-intensive continued processing). Apple requires written justification and approval for this entitlement. Submit a request via the entitlements request form; until approved it may cause notarization failure. |
| `AMENAPP.entitlements:24` | **High** | Entitlements — unjustified | `com.apple.developer.location.push` (Location Push Service Extension) entitlement is present. The code uses `UNLocationNotificationTrigger` (standard location-based local notifications, which do not require this entitlement). `com.apple.developer.location.push` is for the separate Location Push Service Extension target (a separate `.appex` bundle). There is no such extension in the project. Remove this entitlement or add the extension; the mismatch will cause a binary validation error. |
| `Info.plist:109-110` | **High** | Export compliance | `ITSAppUsesNonExemptEncryption` is `false`. The app uses `CryptoKit` (AES-GCM encryption in `CrisisHistoryService.swift`, `AMENMessageSafetyEngine.swift`, end-to-end message encryption). Standard encryption algorithms used for security purposes are exempt under EAR 740.17, but the declaration must accurately reflect usage. Set this to `true` with an ECCNClassification if needed, or confirm with legal that AES-GCM for data protection qualifies as exempt, then add the `ITSEncryptionExportComplianceCode` key. Current `false` declaration while using AES-GCM is inaccurate and could trigger OFAC/export review. |
| `PrivacyInfo.xcprivacy` (entire file) | **High** | Privacy manifest — missing API | The app uses `UserDefaults` extensively. The manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` ("access your own app's UserDefaults"). Confirm this is the correct reason code — `CA92.1` is for third-party SDKs. The first-party reason code is **`1C8F.1`** ("access app-specific data from UserDefaults within your own app"). Using the wrong reason code may cause App Review rejection. |
| `Info.plist:62-76` | **High** | Secrets in bundle | API keys for `YOUVERSION_API_KEY`, `YOUTUBE_API_KEY`, `GOOGLE_VISION_API_KEY`, `VERTEX_AI_KEY`, `CLAUDE_API_KEY`, and `OPENAI_API_KEY` are stored in Info.plist via xcconfig substitution. These resolve to plaintext in the shipped bundle. Any of these keys with billing attached (OpenAI, Anthropic, Google Vision, Vertex AI) can be extracted and abused. Move all AI API calls to Cloud Functions where keys are stored as server-side environment variables. |
| `GivingInAppSheet.swift:56-57` | **High** | Payments compliance | The app charges a 2% platform fee on top of nonprofit donations processed via Apple Pay (`platformFee: Double { effectiveAmount * 0.02 }`). Apple Pay is being used as the payment method for charitable giving. Under App Store guidelines 3.1.1 and 3.1.3, Apple Pay may be used for physical goods/services and charitable giving — however, layering a platform fee on top of a charitable donation routed outside of IAP may require App Review discussion. The fee structure must be prominently disclosed in App Store metadata. |
| `MentorModel.swift:98-101` | **High** | Placeholder data | Stripe price IDs `"price_growth"` and `"price_deep"` are hardcoded test/placeholder values, not real Stripe price IDs. If mentorship payments are live for any users, these will fail at payment time. Must be replaced with actual Stripe price IDs from the dashboard before submission. |
| `InAppReviewPromptView.swift:139` | **Med** | Placeholder content | `// TODO: Replace with actual app icon asset` — review prompt shows a generic flame SF Symbol instead of the real AMEN app icon. App Review may flag this as placeholder UI (guideline 2.3.7: apps with placeholder content are rejected). |
| `InAppReviewPromptView.swift:185` | **Med** | Placeholder content | `// TODO: Implement feedback flow for low ratings` — the low-rating path is unimplemented. Users who rate 1–2 stars see no follow-up. While not an automatic rejection, this is guideline 2.3.7 territory and also substandard UX. |
| `ChurchEditProfileView.swift:584` | **Med** | Placeholder content | `// TODO: Persist changes to service layer` — Church edit profile view does not save changes. If this view is user-accessible, changes will silently be discarded. Guideline 2.1: apps that don't work as expected will be rejected. |
| `SavedSearchNotificationIntegration.swift:149` | **Med** | Placeholder content | `// TODO: Present SavedSearchesView and highlight this search` — a notification deep-link route is unimplemented. Notification taps will silently do nothing, violating guideline 4.5.4 (notifications must be used for relevant content). |
| `Sharing/InstagramStoryShare.swift:8` | **Med** | Missing Info.plist entries | `// TODO(Info.plist): Add "instagram-stories", "instagram", "fb-stories", "facebook"` to `LSApplicationQueriesSchemes`. Without these, `canOpenURL` will always return false on iOS 18+ and the share buttons will be silently disabled. Not a rejection blocker but broken feature. |
| `AMENAPPApp.swift:316` | **Med** | ATT UX timing | ATT dialog is requested inside a `.userInitiated` Task immediately after the first frame renders, with no contextual explanation screen shown first. Apple's Human Interface Guidelines require showing a purpose screen before the system ATT dialog. Showing the dialog with no lead-in reduces opt-in rates and may receive reviewer pushback. |
| `Spaces/Shell/CommunitySwitcherView.swift:169-172` | **Med** | Hardcoded test data | `ownerUserId: "u1"` hardcoded in what appears to be preview/seed data within a production-shipped file. Confirm this is only in `#Preview` blocks and not reachable at runtime. |
| `PrivacyInfo.xcprivacy` (entire file) | **Med** | Privacy manifest — tracking domains | `NSPrivacyTrackingDomains` is an empty array. The app calls Firebase Analytics, Algolia, Crashlytics, and potentially Stripe domains. If `NSPrivacyTracking` is truly `false`, this is fine — but the ATT call in the app code contradicts this. Resolve the tracking/ATT contradiction first; then populate domains if tracking is actually happening. |
| `Info.plist` (missing key) | **Med** | Missing notification permission key | The key in Info.plist is `NSUserNotificationsUsageDescription` (invalid). Push notification permission is correctly requested at runtime via `UNUserNotificationCenter`, which is the right pattern — no plist key is required. However, several features also use `UNLocationNotificationTrigger` (geofence-based notifications). These require `NSLocationAlwaysAndWhenInUseUsageDescription` or `NSLocationWhenInUseUsageDescription` — the latter is present (`Info.plist:89`), which is acceptable for WhenInUse location triggers. |
| `Info.plist` (missing key) | **Low** | Missing permission | `NSRemindersUsageDescription` is present in `Info.plist:98`. `EKEventStore().requestFullAccessToReminders()` is called in `SmartMessageHostIntegration.swift:227` and `SmartMessageActionMenu.swift:125`. The key text reads "AMEN creates reminders for prayer commitments, church events, and spiritual goals." — this is adequate. No issue beyond noting this feature requires iOS 17+ for `requestFullAccessToReminders`. |
| `Info.plist:37-38` | **Low** | Permission string accuracy | `NSAppleMusicUsageDescription` mentions "worship songs in your Church Notes." MusicKit is used conditionally (`#if canImport(MusicKit)`). The description is sufficient but should be broader — the app also uses it for general worship playback from `WorshipMusicService.swift`. Minor wording improvement recommended. |
| `AMENAPPApp.swift:317` (ATT in non-authenticated context) | **Low** | Age rating consistency | The app collects Date of Birth during sign-up and enforces age gating (`AgeAssuranceService.swift`). The minimum age is `AppConfig.Legal.minimumAge` (not hardcoded here — needs verification it is ≥13 for COPPA). The app must declare an age rating of 12+ or 17+ depending on content. A faith social app with messaging, user-generated content, and health data likely warrants **17+** in the App Store (guideline 1.3). Verify the declared age rating in App Store Connect matches the app's actual minimum age and content. |
| `AuthDebugView.swift` / `QuickAuthTest.swift` / `DeveloperMenuView.swift` | **Low** | Debug views in production | These files are wrapped in `#if DEBUG` at the file level (confirmed at line 8/9 of each file). Provided the scheme configuration correctly sets `DEBUG` only for development and not for archive/release builds, these will not ship. Verify the Archive scheme does not define `DEBUG`. |
| `BereanFastMode.swift:283` | **Low** | Placeholder content | `// TODO: Add common word definitions` — affects the Berean AI quick-definition feature but is internal to a not-yet-launched feature path. Low risk for rejection if the feature is gated. |

---

## Likely Rejection Reasons

Ordered by rejection likelihood based on Apple's review history patterns:

1. **ATT inconsistency (Blocker)** — `NSUserTrackingUsageDescription` present and `ATTrackingManager` called unconditionally, but `NSPrivacyTracking = false`. App Review's automated scanner will flag this contradiction immediately. Either remove all ATT code (if no cross-app tracking) or correctly declare tracking in the privacy manifest.

2. **Unimplemented payment flow / false success screen (Blocker)** — `GivingInAppSheet` shows a "Thank you — your gift is confirmed" success screen when no Stripe call is made (Apple Pay token not sent to backend; non-Apple Pay path shows success without charge). This violates guideline 3.1 and constitutes deceptive behavior under guideline 5.3. Reviewers test payment flows.

3. **Missing HealthKit entitlement (High)** — App will crash on any device when HealthKit is accessed without the `com.apple.developer.healthkit` entitlement. Reviewers test on real devices.

4. **`com.apple.developer.location.push` entitlement without extension (High)** — Binary validation during App Store upload may reject the binary outright if this restricted entitlement is present without the corresponding Location Push Service Extension bundle. This is a pre-review automated check.

5. **Privacy manifest missing UserID + Financial data types (Blocker)** — Apple's automated privacy nutrition label generation will fail or produce an inaccurate label. Starting Spring 2024, apps with incomplete privacy manifests are rejected.

6. **Placeholder UI visible to reviewers (Med)** — The review prompt shows a generic flame icon with `TODO: Replace with actual app icon`. Church edit profile silently discards all edits. These are visible to reviewers exercising normal app flows.

7. **SPOTIFY_CLIENT_SECRET in app bundle (Blocker)** — Secrets are bundled in a readable plist. While Apple does not mechanically scan for secrets, a reviewer inspecting the binary (common for apps using financial data) could find it, and it violates App Store guidelines 5.4 (privacy) and creates a real security incident vector.

8. **Incorrect `ITSEncryptionExportComplianceCode` declaration (High)** — Declaring `false` while using AES-GCM. Low probability of direct rejection, but if flagged during export compliance review by OFAC, the app can be held.

---

## Fix Recommendations

### Blocker fixes (required before submission)

**B-1: Resolve ATT contradiction**
- Decide: does AMEN actually perform cross-app/cross-site tracking? (Firebase Analytics device ID tracking counts.)
- If NO tracking: delete `NSUserTrackingUsageDescription` from `Info.plist`, delete the `ATTrackingManager.requestTrackingAuthorization` call in `AMENAPPApp.swift:314-321`, and set `NSPrivacyTracking = false` (already done in xcprivacy).
- If YES tracking: set `NSPrivacyTracking = true` in `PrivacyInfo.xcprivacy`, populate `NSPrivacyTrackingDomains` with the actual domains (e.g., `app-measurement.com`, `firebase.com`), and keep the existing ATT call but add a purpose screen before it.

**B-2: Fix the giving payment flow**
- In `GivingInAppSheet.swift:401`: implement the Cloud Function call to forward `payment.token.paymentData` to the Stripe backend before calling `completion(.success)`.
- In `GivingInAppSheet.swift:278-279`: either implement the Stripe Payment Sheet (`StripePaymentSheet.present()`) or hide the "Donate with Card" button entirely until the Stripe integration is complete. Do NOT show a success state without a confirmed charge.

**B-3: Add HealthKit entitlement**
- In Xcode: Target → Signing & Capabilities → + → HealthKit
- This adds `com.apple.developer.healthkit` (read) and `com.apple.developer.healthkit.background-delivery` (if needed)
- Also add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` (already in Info.plist — verify the strings are accurate for what data is read vs. written)
- Consider whether HealthKit is a core feature or can be feature-flagged off for the initial submission to reduce App Review scrutiny surface

**B-4: Remove or justify `com.apple.developer.location.push` entitlement**
- If the app does NOT have a Location Push Service Extension target, remove this key from both `.entitlements` files.
- `UNLocationNotificationTrigger` for geofence-based local notifications does NOT require this entitlement. Standard `CoreLocation` + `NSLocationWhenInUseUsageDescription` is sufficient.
- The existing code in `SmartChurchNotifications.swift`, `NotificationScheduler.swift`, etc. uses standard `UNLocationNotificationTrigger` — no extension needed.

**B-5: Move secrets server-side**
- `SPOTIFY_CLIENT_SECRET`: Move Spotify Client Credentials token exchange to a Cloud Function. The iOS app calls the CF, which returns a short-lived bearer token.
- `CLAUDE_API_KEY`, `OPENAI_API_KEY`: All calls to Anthropic and OpenAI APIs must be proxied through Cloud Functions. These keys must never be in the shipped binary.
- `VERTEX_AI_KEY`, `GOOGLE_VISION_API_KEY`: Same — proxy via Cloud Functions with Firebase App Check enforced.
- `YOUTUBE_API_KEY` and `YOUVERSION_API_KEY` are lower risk (read-only public APIs) but should still be server-side.
- Remove the corresponding `<key>` entries from Info.plist entirely.

**B-6: Update `PrivacyInfo.xcprivacy` data types**
Add the following missing `NSPrivacyCollectedDataType` entries:
```xml
<!-- User ID — Firebase Auth UID linked to all user data -->
<dict>
    <key>NSPrivacyCollectedDataType</key>
    <string>NSPrivacyCollectedDataTypeUserID</string>
    <key>NSPrivacyCollectedDataTypeLinked</key>
    <true/>
    <key>NSPrivacyCollectedDataTypeTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypePurposes</key>
    <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
    </array>
</dict>
<!-- Payment info — Apple Pay + Stripe payment tokens -->
<dict>
    <key>NSPrivacyCollectedDataType</key>
    <string>NSPrivacyCollectedDataTypePaymentInfo</string>
    <key>NSPrivacyCollectedDataTypeLinked</key>
    <true/>
    <key>NSPrivacyCollectedDataTypeTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypePurposes</key>
    <array>
        <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
    </array>
</dict>
```

**B-7: Fix UserDefaults reason code**
- In `PrivacyInfo.xcprivacy`, change `NSPrivacyAccessedAPITypeReasons` for `NSPrivacyAccessedAPICategoryUserDefaults` from `CA92.1` to `1C8F.1` (first-party app accessing its own UserDefaults).

**B-8: Remove invalid plist key**
- Delete `NSUserNotificationsUsageDescription` (and its value) from `Info.plist`. This key does not exist in Apple's schema. Push authorization is handled at runtime via `UNUserNotificationCenter` — no plist key is required or recognized.

### High priority fixes

**H-1: Remove or justify `com.apple.developer.background-tasks.continued-processing.gpu`**
- This restricted entitlement requires explicit Apple approval via the entitlement request form at developer.apple.com.
- If GPU-intensive CoreML inference is genuinely required, apply for the entitlement and document the use case.
- If it was added speculatively, remove it from both `.entitlements` files.

**H-2: Export compliance declaration**
- The app uses AES-GCM (`CryptoKit`) for data-at-rest protection (crisis history, church notes encryption key).
- Standard AES used solely for data protection (not for hiding/obfuscating the app itself) qualifies as exempt encryption under EAR 740.17(b)(3).
- Set `ITSAppUsesNonExemptEncryption = false` is technically defensible for data-protection-only AES, but add a comment in `Info.plist` documenting the legal basis.
- If end-to-end message encryption (`AMENMessageSafetyEngine.swift`) is user-facing, Apple may classify this as non-exempt. Consult legal; if non-exempt, set `true` and file an annual self-classification report with BIS.

**H-2: Replace Stripe placeholder price IDs**
- `MentorModel.swift:98-101`: Replace `"price_growth"` and `"price_deep"` with actual Stripe Dashboard price IDs before any paid mentorship tier is exposed to users.

### Medium priority fixes

**M-1: Complete the review prompt**
- `InAppReviewPromptView.swift:139`: Replace `Image(systemName: "flame.fill")` with the actual AMEN app icon asset (add `Image("AppIcon")` or use an asset catalog image).
- `InAppReviewPromptView.swift:185`: Implement the low-rating feedback path (e.g., open a support email link or in-app feedback form).

**M-2: Fix ChurchEditProfileView persistence**
- `ChurchEditProfileView.swift:584`: Implement save logic calling the appropriate service layer before launch. If this view is behind a feature flag that is off, document that — otherwise it is broken user-facing functionality.

**M-3: ATT purpose screen**
- If ATT is kept: show a custom full-screen purpose view explaining what AMEN uses the IDFA for, before calling `requestTrackingAuthorization`. Place this after the user has had meaningful interaction with the app (not at first launch).

**M-4: Add LSApplicationQueriesSchemes**
- `Sharing/InstagramStoryShare.swift:8`: Add `instagram-stories`, `instagram`, `fb-stories`, `facebook` to `LSApplicationQueriesSchemes` array in `Info.plist` to enable `canOpenURL` checks.

**M-5: Age rating declaration**
- Verify the age rating set in App Store Connect. A faith social app with: direct messaging (18+ gated), user-generated content, health data integration, and an AI chatbot warrants **17+** (infrequent/mild sexual themes is not the concern — the messaging features and UGC are). A 17+ rating still allows over-13 users if the app's own age gate is properly enforced (which `AgeAssuranceService` does).

### Low priority fixes

**L-1: Confirm debug views are excluded from release**
- Verify in Xcode that the Release/Archive scheme does NOT define the `DEBUG` flag.
- `AuthDebugView.swift`, `DeveloperMenuView.swift`, `QuickAuthTest.swift` are all inside `#if DEBUG` — this is correct.

**L-2: Remove hardcoded test email strings**
- `AuthDebugView.swift:18` and `QuickAuthTest.swift:15` contain `"test@example.com"` / `"test@test.com"` — these are inside `#if DEBUG` blocks and will not ship, but confirm.

---

## Summary Scorecard

| Category | Status |
|----------|--------|
| PrivacyInfo.xcprivacy exists | ✅ Present |
| PrivacyInfo.xcprivacy complete | ❌ Missing UserID, PaymentInfo data types; wrong UserDefaults reason code |
| ATT consistency | ❌ Contradictory — ATT called but NSPrivacyTracking=false |
| Permission strings (camera, mic, photo, location, contacts) | ✅ All present and reasonable |
| Permission strings (HealthKit) | ✅ Present but entitlement missing |
| Permission strings (invalid key) | ❌ NSUserNotificationsUsageDescription is not a real key |
| Entitlements justified | ❌ location.push has no extension; gpu entitlement needs approval; HealthKit missing |
| aps-environment | ⚠️ development in debug; production in release — verify archive config |
| Account deletion | ✅ `DeleteAccountView` + `AccountDeletionService` fully implemented and discoverable via Settings |
| No placeholder content (blocking) | ❌ Payment success shown without charge; review prompt uses placeholder icon |
| External payment compliance | ⚠️ Apple Pay giving + platform fee — review guideline 3.1 applicability |
| Private API usage | ✅ No `_`-prefixed private API calls found |
| Secrets in bundle | ❌ Spotify client secret + 6 AI API keys resolve to plaintext in binary |
| Age rating consistency | ⚠️ Needs App Store Connect verification for 17+ |
| Export compliance | ⚠️ AES-GCM used; `false` declaration is borderline — document legal basis |
