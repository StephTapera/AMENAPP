# AMEN App — Submission Readiness Report
**Audit Date:** 2026-05-28  
**Branch:** audit/2026-05-28  
**Auditors:** 10 parallel domain agents  

---

## VERDICT: ❌ NO-GO

**Do not submit.** There are 28 distinct Blockers across 10 domains. Three of those Blockers — fake payment processing, ATT/privacy manifest contradiction, and Covenant/Space purchases bypassing Apple IAP — are certain App Store rejections. An additional 7 Blockers are crash risks or complete feature failures that would be caught in Apple's automated binary scan or manual review.

---

## Blockers Ranked by Submission Risk

### Rank 1 — Certain Automatic Rejection

| # | File:Line | Domain | Description | One-Line Fix |
|---|-----------|--------|-------------|--------------|
| B-01 | `GivingInAppSheet.swift:397` | Payments | Apple Pay token received but `// TODO` — success screen shown, zero money moves | Wire `PKPayment.token.paymentData` into `stripeCreatePaymentIntent` callable before calling `completion(.success)` |
| B-02 | `GivingInAppSheet.swift:~440` | Payments | "Donate with Card" button calls `withAnimation { showSuccess = true }` — no backend call | Replace animation stub with actual Stripe PaymentSheet presentation using `pendingClientSecret` |
| B-03 | `AMENAPPApp.swift:316` + `PrivacyInfo.xcprivacy` | App Store | `ATTrackingManager.requestTrackingAuthorization` called on cold launch but `NSPrivacyTracking = false` in privacy manifest — Apple scanner flags this immediately | Either remove all ATT code (if no cross-app tracking) or set `NSPrivacyTracking = true` with tracked domains in manifest |
| B-04 | `GivingInAppSheet.swift` + backend | App Store | Covenant subscriptions and paid Space access use Stripe-hosted checkout, bypassing Apple IAP — violates guideline 3.1.1 | Replace digital-content purchase paths with `StoreKit 2` IAP; donations to verified 501(c)3 orgs may remain on Stripe |
| B-05 | `PrivacyInfo.xcprivacy` | App Store | Missing `NSPrivacyCollectedDataTypeUserID`, `NSPrivacyCollectedDataTypePaymentInfo`; wrong UserDefaults reason code `CA92.1` instead of `1C8F.1` | Add missing data type entries; change UserDefaults required reason to `1C8F.1` |
| B-06 | `AMENAPP.entitlements` | App Store | `com.apple.developer.location.push` entitlement declared but no Location Push Service Extension target exists — binary validation will fail | Remove entitlement if Location Push is not launched, or add the required extension target |

### Rank 2 — Likely Human Review Rejection

| # | File:Line | Domain | Description | One-Line Fix |
|---|-----------|--------|-------------|--------------|
| B-07 | `AMENAPP.entitlements` | App Store | HealthKit (`com.apple.developer.healthkit`) absent but `BreathingExerciseView`, `SynapticStudioView`, `MovementWellnessView`, `GroundingExerciseView` call HKHealthStore — runtime crash on launch of those screens | Add `com.apple.developer.healthkit` entitlement and `NSHealthUpdateUsageDescription` / `NSHealthShareUsageDescription` to Info.plist, or remove HK calls |
| B-08 | `AccountSettingsView.swift:1293` | Settings | "Sign Out" alert calls `Auth.auth().signOut()` directly, skipping `AppLifecycleManager.performFullSignOutCleanup()` — FCM token not deactivated, listeners left open, badge not cleared | Replace direct call with `authViewModel.signOut()` |
| B-09 | `AccountDeletionService.swift:277` | Settings | `deleteDocumentsWhereField` caps at `.limit(to: 200)` — users with 200+ posts have orphaned data after deletion, violating App Store guideline 5.1.1 | Paginate deletion with a recursive callable until cursor exhausted |
| B-10 | `AccountDeletionService.swift:~277` | Settings | Keychain entries are never cleared on deletion — stub comment `// Clear keychain if needed` | Add `SecItemDelete` calls for all stored service credentials during deletion |
| B-11 | `AccountSettingsView.swift` (ReauthenticationSheet) | Settings | Google-auth users see a static label with no sign-in button on re-auth sheet — cannot complete deletion | Add `GIDSignIn.sharedInstance.signIn(...)` flow inside `ReauthenticationSheet` for Google credential re-auth |
| B-12 | `ReviewPromptManager.swift` | App Store | `itms-apps://itunes.apple.com/app/id0000000000` placeholder — "Rate AMEN" does nothing | Replace `0000000000` with the real App Store app ID |
| B-13 | `AccountSettingsView.swift` | Settings | `AgeGateView` is never presented — `ageGateEligible` flag set but no `fullScreenCover` or conditional navigation shows the gate for returning users | Add `fullScreenCover(isPresented: $ageGateEligible)` in `AMENAPPApp` or `ContentView` gating all content |
| B-14 | `amenapp.com/terms` + `amenapp.com/privacy` | Settings | Both URLs return HTTP 000 — domains do not resolve | Deploy privacy policy and terms pages, or redirect to a live URL before submission |

### Rank 3 — Crash Risk (Automated Scan / User Crash)

| # | File:Line | Domain | Description | One-Line Fix |
|---|-----------|--------|-------------|--------------|
| B-15 | `BereanAdvancedFeaturesViews.swift:154,471` | UI | `studyPlan!` and `analysis!` rendered directly in view body — async update between nil-check and render crashes | Wrap in `if let studyPlan`, `if let analysis` |
| B-16 | `Feature05_AccountabilityThread.swift:119` | UI | `snap!.documentID` in Firestore listener where guard only protects `snap?.data()`, not `snap` | Change guard to `guard let snap = snapshot, let _ = snap.data()` |
| B-17 | `CommentRateLimiter.swift:155,163,173` | UI | Three `.min(...)!` force-unwraps on arrays protected by `.count >= limit` not `.isEmpty` | Replace with `.min()` optional binding |
| B-18 | `LiquidGlassMessagesView.swift:244` | UI | `NotificationCenter` keyboard observers registered without `[weak self]`, never removed — retain cycle + crash after dealloc | Capture `[weak self]` and call `removeObserver(self)` in `onDisappear` |
| B-19 | `SignInView.swift:2259` | UI | `UIWindow(windowScene: anyWindowScene!)` on background-launch path where no window scene may exist | Guard with `guard let scene = ...windowScenes.first` |
| B-20 | `VictimShieldControlsView.swift:176` | UI | `URL(string: url)!` where `url` is a Firestore-sourced string that can be empty or malformed | Replace with `URL(string: url).map { ... }` optional chain |

### Rank 4 — Complete Feature Failure (Non-Functional at Runtime)

| # | File:Line | Domain | Description | One-Line Fix |
|---|-----------|--------|-------------|--------------|
| B-21 | `Features/MessageActions/MessageActionService.swift:102` | Frontend | `FirebaseMessageActionService` is the live `shared` singleton but all 25 methods throw `MessageActionError.notImplemented` — every message context-menu action is broken | Implement or wire the actual Firestore/FCM calls; this is the singleton used in production |
| B-22 | `BereanVoiceViewModel.swift` | Backend | `bereanVoiceProxy` and `ttsProxy` called on every voice session — neither function exists in any deployed backend; feature flag defaults to `true` | Create the two proxy CFs in `functions/bereanFunctions.js` or disable the feature flag |
| B-23 | `BereanDriveSessionService.swift` | Backend | 5 CarPlay functions (`bereanDriveRespond`, `bereanDriveSummarize`, `bereanDrivePrayerSession`, `bereanDriveChurchSearch`, `bereanDriveMessageSafetyReview`) — no backend file exists | Build or stub these CFs, or remove CarPlay entitlement |
| B-24 | Multiple payment callables in iOS | Payments | 8 Stripe Cloud Functions called from Swift (`stripeCreateConnectedAccount`, `stripeGetAccountStatus`, `stripeCreatePaymentIntent`, `stripeRequestPayout`, `createCovenantCheckoutSession`, `createStripeConnectAccount`, `createSpaceCheckoutSession`, `purchaseSpaceAccess`) are absent from `Backend/functions/src/index.ts` | Either deploy these functions or hide the UI behind the `paymentsEnabled` feature flag |
| B-25 | `AppDelegate.entitlements` / `dist-notifications/CloudFunction_NotificationRoutingPipeline.js` | Backend | `composeNotificationPayload` and `dispatchPush` have no `context.auth` check — any unauthenticated caller can forge push payloads to any user | Add `if (!context.auth) throw new functions.https.HttpsError('unauthenticated', ...)` at the top of both handlers |
| B-26 | `AMENAPP.entitlements` + `AppDelegate.swift` | Notifications | `aps-environment = development` in the entitlements file that will be signed into an Archive build — all production push notifications silently fail | Set `aps-environment = production` in the Release/Archive entitlements |
| B-27 | `BereanChatView.swift` + `ConversationRepository.ts` + `premiumBereanCallables.ts` | Data | Berean conversations are written to 3 incompatible Firestore paths — `users/{uid}/bereanConversations`, `berean_conversations`, and `users/{uid}/bereanMessages` — none of which the iOS reader queries | Pick one canonical path (recommend `users/{uid}/bereanConversations/{id}/messages`), migrate all writers and readers to it |
| B-28 | `Post.swift` | Data | `Post.PostVisibility.everyone.rawValue = "Everyone"` (capital E) but all Firestore queries filter `"everyone"` (lowercase) — all legacy posts are invisible in every feed query | Add `.lowercased()` to the rawValue, or a migration script to rewrite existing docs |

---

## High Issues (Ranked by User Impact)

| # | Domain | Description |
|---|--------|-------------|
| H-01 | Security | Firebase API key `AIzaSyBRg7axwpIAxoKjuSuCBSqCtMuxfkqfE-k` committed to git history (3 commits) — must be rotated in GCP Console with iOS bundle-ID restriction |
| H-02 | Security | Algolia search key `8727f5af5779e9795b12b565bba20dc3` hardcoded in `AlgoliaConfig.swift` and committed — rotate immediately |
| H-03 | Security | `SPOTIFY_CLIENT_SECRET` used for OAuth directly from the iOS client — move OAuth flow to a server-side CF proxy |
| H-04 | Backend | `prayers`, `bereanSessions`, `churchJourneys` allow `list: if isSignedIn()` without ownership filter — any authenticated user can enumerate another user's private spiritual data |
| H-05 | Backend | `amenStudioAI.js` not imported in `functions/index.js` — `studioGenerateContent` and `studioJournalPrompt` not deployed; iOS Studio features silently fail |
| H-06 | AI | `bereanChatProxy` missing `enforceAppCheck: true` — unauthenticated/non-attested clients can hit Anthropic API through this proxy |
| H-07 | AI | `bereanChatProxy` commented-out in `index.js` — every Berean chat call may fail with code 16 if the TypeScript deployment is not active |
| H-08 | AI | `openAIProxy` has no daily token budget or aggregate org cost cap — unbounded spend exposure |
| H-09 | AI | GUARDIAN does not pre-gate text posts — content is immediately visible; moderation runs async after publish |
| H-10 | Data | 4 missing Firestore composite indexes (`heyfeed_requests`, `heyfeed_resonance`, `pastoral_care_signals`, `bereanMemory`) — all four listeners throw at runtime in production |
| H-11 | Data | `PostMediaItem` per-media captions written in composer UI but never persisted by `MediaMetadataPersistenceService` — silently dropped on restart |
| H-12 | Data | `Post.mediaItems` always `nil` on feed decode — feed query never joins the `mediaMeta` subcollection |
| H-13 | Notifications | `PushNotificationHandler` is never assigned as UNUserNotificationCenter or Messaging delegate — its conformances are dead code |
| H-14 | Notifications | Three services (`ChurchNotificationManager`, `NotificationManager`, `BreakTimeNotificationManager`) call `setNotificationCategories` directly, bypassing `NotificationCategoryRegistrar` — last caller wipes all other categories |
| H-15 | Notifications | `BereanLiveActivityManager` wrapped in `#if false` — entire Dynamic Island / Lock Screen Live Activity is permanently disabled despite `NSSupportsLiveActivities = YES` in Info.plist |
| H-16 | Frontend | Spaces: `.bibleStudy` and `.announcement` tabs show raw `Text()` placeholders; "Manage Space" → `EmptyView()`; paid unlock sheet shows `Text("Purchase sheet coming in Agent E.")` |
| H-17 | Frontend | `ChurchEditProfileView.handleSave()` calls `dismiss()` only — never writes to Firestore |
| H-18 | Payments | Stripe iOS SDK (`StripePaymentSheet`) not added as a package dependency — `pendingClientSecret` has no UI to consume it |
| H-19 | Payments | Apple Pay merchant ID `merchant.com.amen.giving` used in code but entitlement only registers `merchant.com.amen.app` — Apple Pay always fails at runtime |
| H-20 | Settings | Post/prayer/churchNotes subcollections (`/comments`, `/likes`) not purged during account deletion — orphaned readable data after user deletion |

---

## Fix Priority Order

For submission readiness, work in this sequence:

1. **Payments** — B-01, B-02, B-24, H-18, H-19 (whole giving system is fake; fix or hide behind flag)
2. **App Store binary scan** — B-03, B-05, B-06, B-07, B-12 (will fail automated review)
3. **App Store IAP compliance** — B-04 (Covenant/Space purchases must use IAP)
4. **Account deletion** — B-09, B-10, B-11, B-13, B-14, H-20 (guideline 5.1.1 and COPPA)
5. **Crash risks** — B-15 through B-20 (crash on first user path)
6. **Secret rotation** — H-01, H-02 (keys already in git history; rotate immediately regardless of submission)
7. **Push notifications** — B-26, H-13, H-14 (production push will be silent)
8. **Backend auth** — B-25, H-04 (unauthenticated forging and data enumeration)
9. **Berean/AI** — B-22, B-23, H-06, H-07 (voice + CarPlay completely broken)
10. **Data integrity** — B-27, B-28, H-10, H-11, H-12 (invisible posts, orphaned conversations)
11. **Sign-out** — B-08 (listener leak compounds over sessions)
12. **Settings UI** — B-08, B-13, B-14 (age gate, terms URLs)

---

## Domain Summary

| Domain | Blockers | Highs | Report |
|--------|----------|-------|--------|
| Payments | 6 | 2 | [payments.md](payments.md) |
| App Store Compliance | 5 | 1 | [appstore.md](appstore.md) |
| Settings & Account Lifecycle | 6 | 3 | [settings.md](settings.md) |
| UI States & Crashes | 6 | 0 | [ui.md](ui.md) |
| Backend / Cloud Functions | 4 | 4 | [backend.md](backend.md) |
| Frontend Wiring | 4 | 4 | [frontend.md](frontend.md) |
| Data Model & Persistence | 6 | 5 | [data.md](data.md) |
| Notifications | 2 | 5 | [notifications.md](notifications.md) |
| AI Features | 3 | 5 | [ai.md](ai.md) |
| Security & Secrets | 2 | 3 | [security.md](security.md) |
| **Total** | **44** | **32** | |

---

*Full details for each finding are in the individual domain reports linked above.*
