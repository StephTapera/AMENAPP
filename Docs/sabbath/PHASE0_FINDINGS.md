# PHASE 0 AUDIT FINDINGS — Sabbath Mode Build
**Date:** 2026-06-07  
**Agent:** PHASE 0 AUDIT AGENT (read-only)  
**Status:** COMPLETE — all downstream agents unblocked

---

## T1 — Module Map

### 1. Root Navigation / Router

✅ FOUND

**Entry point:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPPApp.swift`  
**Root view:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ContentView.swift`

**How it works:**  
- `AMENAPPApp` (`@main`) instantiates `ContentView` inside a `WindowGroup`. There is no TabView in the traditional sense.
- `ContentView` owns the navigation state via `@StateObject private var viewModel: ContentViewModel`. The tab selection is `viewModel.selectedTab: Int`.
- Navigation is a custom `AMENTabBar` with 8 tabs (indices 0–7):
  - 0 = `HomeView`
  - 1 = `AMENDiscoveryView`
  - 2 = `SpiritualInboxView`
  - 3 = `ResourcesView` (contains Church Notes + Find Church)
  - 4 = `AMENNotificationsView`
  - 5 = `ProfileView`
  - 6 = `AmenConnectSpacesHubView`
  - 7 = `WhatNeedsAttentionView`
- All tabs are `keepMountedTab` (opacity-based, not destroyed) to preserve state.
- **Shabbat gate:** `SundayChurchFocusGateView` is shown in place of non-allowed tabs when `SundayChurchFocusManager.shared.shouldGateFeature()` returns true. Allowed tabs during shabbat: 3 (Resources), 5 (Profile), 7 (Intelligence).
- Auth routing ladder in order: `TwoFactorVerificationGateView` → `AMENAuthLandingView` → `ReactivationPromptView` → `UsernameSelectionView` → `OnboardingView` → `EmailVerificationGateView` → `AmenSimpleModeView` → main content.

**Key config files:**
- `AMENFeatureFlags.swift` — feature flag singleton
- `AppReadyStateManager.swift` — loading screen orchestrator
- `ShabbatModeService.swift` — Shabbat active state
- `SundayChurchFocusManager.swift` — church focus window manager

---

### 2. Notification System

✅ FOUND

**Primary file:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/NotificationService.swift`  
**Entry:** `NotificationService.shared` (singleton, `@MainActor ObservableObject`)  
**Started:** `NotificationService.shared.startListening()` called in `ContentView.onAppear` (via `mainContent.onAppear` block).

**Other key files:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/PushNotificationHandler.swift` — handles APNs/FCM token registration, stores token at `users/{uid}/deviceTokens/{token}` with `platform`, `enabled`, `locale`, `timezone` fields.
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/NotificationService.swift` — Firestore real-time listener on `users/{uid}/notifications` + top-level `/notifications` collection.
- FCM token registration: `DeviceTokenManager.shared.registerDeviceToken()` called from auth state listener in `AMENAPPApp`.
- Deep link routing: `NotificationDeepLinkRouter.shared` + `NotificationOpenCoordinator.shared`.

**Backend (Cloud Functions):**
- `Backend/functions/src/notifications/onSocialEvent.ts` — generates notifications on social events
- `Backend/functions/src/notifications/counts.ts`, `maintenance.ts`, `invalidation.ts`, `prayerAnsweredBatch.ts`, `deliverQuietHoursDigest.ts`

---

### 3. Spaces Module (ConnectSpaces)

✅ FOUND

**Hub entry point:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift`  
**Tab index:** 6 (`AmenConnectSpacesHubView` in `ContentView.selectedTabView`)  
**Directory:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/ConnectSpaces/`

Key sub-views inside `ConnectSpaces/`:
- `Spaces/AmenMinistryRoomShellView.swift` — ministry room shell
- `AmenBeforeShareCheckView.swift` — pre-share safety check
- `AmenYouMenuSheet.swift` — "You" context menu
- `AmenUploadScanGateView.swift` — upload safety scan gate
- `AmenIntelligenceSeamService.swift` — intelligence seam

Backend: `Backend/functions/src/spaces/` directory.

---

### 4. Church Notes Module

✅ FOUND

**Location:** Tab 3 (ResourcesView) → NavigationLink into church notes views  
**Service files:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesService.swift` — main service
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesAudioEngine.swift` — audio capture
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesAIService.swift` — AI processing
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesSermonCaptureService.swift` — sermon capture
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesTabSystem.swift` — tab UI
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesShareHelper.swift` — sharing

**Backend callable:** `generateChurchNotesSummary` (in `Backend/functions/src/berean/controllers/generateChurchNotesSummary.ts`)  
Deep link scheme: `amenapp://notes/{shareLinkId}` handled in `AMENAPPApp.handleChurchNoteDeepLink`.

---

### 5. Find a Church Module

✅ FOUND

**Primary view:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/FindChurchView.swift`  
**Entry:** `NavigationLink(destination: FindChurchView())` in `ResourcesView.swift` at line 534.  
**Supporting:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/FindChurchGlassComponents.swift`, `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchDiscoveryPulse.swift`  
**Backend:** `Backend/functions/src/churchDiscovery.ts`, `churchDiscoveryPhase2.ts`, `churchDiscoveryPhase3.ts`, `churchJourney.ts`

---

### 6. Berean AI Router

✅ FOUND

**Swift routing:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ModelRoutingEngine.swift` — `MREProvider` enum, `MRERoutingDecision` struct. Routes via `BereanCoreService.process()`.

**Cloud Function callable name:** `bereanChatProxy` — called as `Functions.functions().httpsCallable("bereanChatProxy")` throughout the Swift codebase (ClaudeAPIService, UnifiedChatView, ReasoningViewModel, CreatorViewModel, SpacesViewModel, ChurchVerificationService, ArkService).

**JS routing config:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/router/amenRouting.config.js`  
This is the **single source of truth** for provider routing. Task keys are strings like `"berean_chat"`, `"guard_input"`, `"moderate_content"`, etc.

**JS callable wrapper:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/routerCallable.js`  
Exported functions: `callModelBerean`, `callModelTest`, `callModelCommentCoach`, `callModelDailyBrief`, `callModelSearch`.

**There is no `amen.routing.config.ts` file** — the canonical equivalent is `functions/router/amenRouting.config.js` (CommonJS, not TypeScript).

---

### 7. Auth Module

✅ FOUND

**ViewModel:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AuthenticationViewModel.swift`  
**Sign-in UI:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SignInView.swift`  
**Landing:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAuthLandingView.swift`

**Source of truth for `uid`:** `Auth.auth().currentUser?.uid` (FirebaseAuth). Used everywhere in the codebase. `AuthenticationViewModel.isAuthenticated` drives the ContentView routing ladder.

Supports: email/password, phone OTP, Google Sign-In (`GIDSignIn`), Apple Sign-In, email-link (passwordless).  
2FA gate: `TwoFactorVerificationGateView` shown before main content when `authViewModel.needs2FAVerification == true`.

---

### 8. Firestore User Schema

✅ FOUND

**Collection path:** `users/{uid}`  
**Model file:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/UserModel.swift`

Fields present in `UserModel` (the canonical Codable struct decoded from Firestore):

| Field | Type | Notes |
|-------|------|-------|
| `id` | String? | @DocumentID = uid |
| `email` | String? | Optional for phone auth |
| `displayName` | String | Required |
| `username` | String | Unique, @-handle |
| `initials` | String | |
| `bio` | String? | |
| `profileImageURL` | String? | |
| `createdAt` | Date | |
| `updatedAt` | Date | |
| `followersCount` | Int | |
| `followingCount` | Int | |
| `postsCount` | Int | |
| `isPrivate` | Bool | |
| `notificationsEnabled` | Bool | |
| `pushNotificationsEnabled` | Bool | |
| `emailNotificationsEnabled` | Bool | |
| `notifyOnLikes` | Bool | |
| `notifyOnComments` | Bool | |
| `notifyOnFollows` | Bool | |
| `notifyOnMentions` | Bool | |
| `notifyOnPrayerRequests` | Bool | |
| `allowMessagesFromEveryone` | Bool | |
| `showActivityStatus` | Bool | |
| `allowTagging` | Bool | |
| `showInterests` | Bool | |
| `showSocialLinks` | Bool | |
| `showBio` | Bool | |
| `showFollowerCount` | Bool | |
| `showFollowingCount` | Bool | |
| `showSavedPosts` | Bool | |
| `showReposts` | Bool | |
| `loginAlerts` | Bool | |
| `showSensitiveContent` | Bool | |
| `requirePasswordForPurchases` | Bool | |
| `lastUsernameChange` | Date? | |
| `lastDisplayNameChange` | Date? | |
| `pendingUsernameChange` | String? | |
| `pendingDisplayNameChange` | String? | |
| `usernameChangeRequestDate` | Date? | |
| `displayNameChangeRequestDate` | Date? | |
| `interests` | [String]? | |
| `goals` | [String]? | |
| `preferredPrayerTime` | String? | |
| `hasCompletedOnboarding` | Bool | |
| `bannerColorId` | String? | |

**Additional fields set by services (not in UserModel CodingKeys, but written via `setData(merge: true)`):**
- `shabbatModeEnabled` (Bool) — written by `ShabbatModeService.persistToFirestore`
- `restModeActive` (Bool) — written by `onRestModePolicyWritten` Cloud Function trigger
- `restModeLevel` (String) — written by `onRestModePolicyWritten`
- `restModeCheckedAt` (Timestamp) — written by `onRestModePolicyWritten`
- `fcmTokenUpdatedAt` (Timestamp) — written by PushNotificationHandler

**Note:** There is NO `timezone` field in the users document. Timezone is device-local only (see T3).

---

### 9. Liquid Glass Design Tokens

✅ FOUND

**Primary token files:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmenGlassDesignTokens.swift` — `AmenGlassMetrics`, `AmenGlassBehavior`, `AmenPresencePriority`, `AmenSmartAction`, `AmenPulseSignalType`, `AmenSemanticTerm`
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` — `AmenLiquidGlassCapsuleSurface`, `AmenLiquidGlassPillButton`

**Metrics tokens (from `AmenGlassMetrics`):**
- `cornerRadiusSmall = 10`
- `cornerRadiusMedium = 16`
- `cornerRadiusLarge = 24`
- `pillHeightCompact = 32`
- `pillHeightRegular = 40`
- `borderWidth = 0.6`
- `shadowRadius = 8`
- `innerHighlightOpacity = 0.22`
- `pillHorizontalPadding = 12`
- `pillVerticalPadding = 7`
- `pillStackSpacing = 8`
- `popoverMaxWidth = 280`
- `popoverCornerRadius = 18`

**Behavior tokens (from `AmenGlassBehavior`):**
- `scrollOpacity = 0.0`
- `pressedScale = 0.97`
- `busyBackgroundOpacity = 0.18`
- `cleanBackgroundOpacity = 0.08`
- `pillHideVelocityThreshold = 300`
- `pillShowRestDelay = 0.35s`
- `presencePillMaxVisible = 3`

**Surface pattern (used throughout all Liquid Glass views):**
```swift
Capsule(style: .continuous).fill(.ultraThinMaterial)
  .overlay { Capsule().fill(Color.white.opacity(isSelected ? 0.20 : 0.12)) }
  .overlay { Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.5) }
  .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
```

**Additional design system files:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmenAdaptiveColors.swift` — adaptive color system
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AnimationTokens.swift` — animation constants
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanDesignSystem.swift` — Berean-specific design
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/LiquidGlassEffects.swift`, `LiquidGlassButtons.swift`, `LiquidGlassAdaptiveSurface.swift`

**IMPORTANT rule from project memory:** Use `Color(hex: "...")` pattern, NOT `Color.amenGold` or named color extensions — those do not compile.

---

## T2 — Safety Allow-List Identification (CRITICAL)

### Surface 1: Crisis Resources (mental health, hotlines)

✅ FOUND

**View name:** `CrisisResourcesDetailView`  
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/CrisisResourcesDetailView.swift`  
**Navigation:** `NavigationLink(destination: CrisisResourcesDetailView())` in `ResourcesView.swift` line 603, inside the "Support & Wellness" grid under `.crisis` and `.mentalHealth` filter categories.  
**Also accessible from:** `AIBibleStudyView.swift` line 361 (via NavigationLink).

**Route identifier in `AmenRoute` enum:**
```swift
case emergencySupport  // policyKey: "emergency_support"
```
This is listed in `RestModeRoutes.allowed` — it is ALWAYS available during rest mode.

**RestModeGate route key:** `"emergency_support"` — explicitly in the allowed list.

---

### Surface 2: Emergency-Family Contact (Trusted Contacts)

✅ FOUND

**View name:** `TrustedCircleView`  
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/TrustedCircleView.swift`  
**Navigation:** `NavigationLink(destination: TrustedCircleView())` in `ResourcesView.swift` line 907, under the `IntelligentSupportActionCard` for `.messageTrustedContact` action type.  
**Also accessible via:** `VictimShieldControlsView` which shows a sheet to `TrustedContactSetupView` (`AmenTrustedContactSetupView.swift`).

**No explicit RestModeGate route key** — `TrustedCircleView` is only reachable via `ResourcesView` which is tab 3 (allowed during Shabbat). The trusted-contacts surface is NOT gated by `RestModeGate.canOpen()` at the view level; access is implicitly allowed because Resources tab is allowed.

---

### Surface 3: Child-Safety Report

⚠️ PARTIAL

**Current state:** `ChildSafetyAgentStubView` — a stub, not a live report flow.  
**File:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/TrustOS/GatedAgentStubViews.swift`  
**Navigation:** `NavigationLink(destination: ChildSafetyAgentStubView())` in `PrivacySettingsView.swift` line 729.  
**Stub message:** "This feature requires a vendor integration review and is not yet active. Enabled pending App Store & legal approval."

**Live child safety services (backend only, no dedicated report UI):**
- `AmenChildSafetyService.swift` at `/AMENAPP/AMENAPP/CommunityOS/ChildSafety/AmenChildSafetyService.swift`
- `AmenChildSafetyModels.swift`
- `AmenMinorExperienceView.swift`
- `MinorSafetyService.swift` — server-side enforcement
- `CameraChildSafetyService.swift` — camera-specific

**CONCLUSION:** The child-safety report UI is a **stub** that is explicitly marked pending App Store approval. There is no live user-facing "report a minor" flow. The Sabbath Mode allow-list must include this route by its stub identifier until the full flow is built.

**SAFETY_ALLOW_LIST entry for child safety:** `ChildSafetyAgentStubView` (reachable from PrivacySettingsView, currently a stub). If Sabbath Mode needs to guarantee this surface is always available, wire it as a RestModeGate `"emergency_support"` equivalent OR add it to `AmenRoute` with `isAllowedDuringShabbat: true`.

---

## T3 — Timezone Source of Truth

✅ FOUND

**The user's timezone is NOT stored in the Firestore users document.**

Timezone is **device-local only**, read at runtime as `TimeZone.current.identifier`.

**Where it appears:**
1. **`ShabbatModeService`** (`/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ShabbatModeService.swift`):
   - Uses `TimeZone.current` at runtime for Sunday detection: `isSundayNow(in timeZone: TimeZone = .current)`
   - `userTimezoneIdentifier` property returns `TimeZone.current.identifier`
   - Stored locally in `UserDefaults` under key `"shabbatMode_userTimezone"` (for ShabbatModeService internal use, not synced to Firestore)

2. **`RestModePolicy`** (`/AMENAPP/AMENAPP/RestModePolicy.swift`):
   - Has `var timezone: String` field — this IS stored in Firestore at `restModePolicies/{uid}.timezone`
   - Used by `RestModeGate` and `restModeEvaluator.ts` Cloud Function
   - Written when user sets a rest mode policy (not automatically; must be provided by the caller)

3. **Device token subcollection** (`users/{uid}/deviceTokens/{token}`):
   - `"timezone": TimeZone.current.identifier` written by `PushNotificationHandler` on token registration
   - This is per-device, not a user-level field

4. **ShabbatAnalytics, AmenDailyDigestService, ChurchRankingService** — all use `TimeZone.current.identifier` inline, not stored.

**TIMEZONE_SOURCE for Sabbath Mode:**
- For iOS gate logic: `TimeZone.current` (device locale, runtime)
- For server-side evaluation: `restModePolicies/{uid}.timezone` (IANA string, user-chosen when policy is created)
- For backend notification routing: `users/{uid}/deviceTokens/{token}.timezone` (per-device)

**RECOMMENDATION:** Sabbath Mode server functions should read from `restModePolicies/{uid}.timezone` (already established pattern in `restModeEvaluator.ts`). If no policy exists, fall back to `users/{uid}/deviceTokens/{mostRecentToken}.timezone`.

---

## T4 — Security Sweep (P0)

### `src/sabbath/` directory
✅ Does not exist — no pre-existing sabbath source to audit.

### `Backend/functions/v2functions.js`
✅ Does not exist at `Backend/functions/v2functions.js`.
The file lives at `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/v2functions.js`.
**No hardcoded API keys, secrets, or credentials found.** Uses `admin.initializeApp()` with no explicit credentials (relies on ADC). References `require("./shabbatMiddleware")` for Shabbat logic.

### `Backend/functions/index.js`
✅ Does not exist at `Backend/functions/index.js`.
The file lives at `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/index.js`.
**No hardcoded API keys, secrets, or credentials found.**

### `AMENAPP/AIIntelligence/BereanContextCoordinator.swift`
✅ **No hardcoded secrets found.** File is a pure data-transformation coordinator with no network calls or credentials.

### `AMENAPP/AMENSecureMessagingService.swift`
✅ **No hardcoded secrets found.** Uses Firebase Functions callables; credentials are server-side.

### `AMENAPP/Config.xcconfig`

⚠️ PARTIAL — Two values present that warrant attention:

1. **`AMEN_GOOGLE_MAPS_API_KEY = AIzaSyB5ZgV2c6XHLnhuW2fBXqzute6vYBS8q_Q`**
   - This is a real API key embedded in the build config.
   - Comment in file: "restricted to bundle ID in Google Cloud Console. Only used for in-app map tile rendering."
   - **Assessment:** Present by design, restricted by bundle ID. Not a new exposure. Do not copy to sabbath-related config.

2. **`ALGOLIA_APP_ID = 182SCN7O9S` / `ALGOLIA_SEARCH_KEY = 8982c2ffa12f21fece6e36c8132518f6`**
   - Comment in file: "search-only key (read-only, safe for client use). SECURITY: Rotate this key..."
   - **Assessment:** Read-only search key. Intentionally client-visible. Comment warns to rotate; existing key may be in git history.

3. All other keys (`CLAUDE_API_KEY`, `OPENAI_API_KEY`, `XAI_KEY`, `API_BIBLE_KEY`, `NEWSAPI_KEY`, `UNSPLASH_KEY`, `YOUVERSION_API_KEY`, `YOUTUBE_API_KEY`, etc.) are **empty** — correct.

**P0 finding:** No new critical secrets exposure. The Google Maps key and Algolia search key are documented as intentionally present. Sabbath Mode agents must NOT add any API keys to xcconfig.

---

## T5 — Existing Sabbath / Rest Mode Code

✅ FOUND — Substantial existing codebase. Sabbath Mode is PARTIALLY BUILT. Do NOT duplicate.

### Existing iOS Swift files (live, not stubs):

| File | Purpose |
|------|---------|
| `/AMENAPP/ShabbatModeService.swift` | Master Shabbat toggle + Firestore sync + Sunday detection |
| `/AMENAPP/SundayChurchFocusManager.swift` | Church focus window manager (fires `showSundayPrompt`) |
| `/AMENAPP/AMENAPP/SundayRestModeSheet.swift` | The modal sheet shown when user hits a blocked route |
| `/AMENAPP/AMENAPP/RestModeGate.swift` | `AmenRoute` enum + `RestModeGate` singleton + override flow |
| `/AMENAPP/AMENAPP/RestModePolicy.swift` | `RestModePolicy` Codable struct + all enums + route constants |
| `/AMENAPP/ContentView.swift` | `isAllowedDuringChurchFocus()`, `SundayChurchFocusGateView`, `SundayShabbatPromptView` |

### Existing backend files:

| File | Exports |
|------|---------|
| `Backend/functions/src/restModeEvaluator.ts` | `evaluateRestMode`, `setRestModePolicy`, `onRestModePolicyWritten`, `resolvePostAILabel` |
| `functions/v2functions.js` | Shabbat guard in `onRealtimeCommentCreate` via `require("./shabbatMiddleware")` |
| `functions/router/amenRouting.config.js` | Routing table (no sabbath task yet) |

### Test file:
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPPTests/RestModeTests.swift` — existing tests for RestModeGate

### Firestore collection for policies:
- `restModePolicies/{uid}` — already established; `RestModePolicy` struct maps to this.

### What is NOT yet built (gaps for Sabbath Mode agents to fill):
- No `ShabbatModeSettingsView` (dedicated settings screen for configuring the mode)
- `ChildSafetyAgentStubView` is a stub — the child safety allow-list surface is not wired to any live flow
- `SundayChurchFocusGateView` exists but may need Sabbath-specific content variants
- No `src/sabbath/` directory in Backend or repo root

---

## T6 — React / Prototype Layer

✅ FOUND

**JSX files at repo root:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Berean.jsx` — React prototype for Berean AI UI
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Berean 2.jsx` — duplicate

**Prototype HTML directory:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Prototypes/SpiritualOS/` (and `/SpiritualOS 2/`)

**No `src/` directory at repo root.** Existing JSX files are dropped directly at the repo root level — NOT in a `src/` subdirectory.

**Where new Sabbath React/JSX prototype files should live:**

Based on the existing pattern (Berean.jsx at root), Sabbath prototypes should be placed at:

```
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Prototypes/SabbathMode/
```

or if creating a JSX prototype (like Berean.jsx):

```
/Users/stephtapera/Desktop/AMEN/AMENAPP copy/SabbathMode.jsx
```

**If the build spec calls for a `src/sabbath/` path** (i.e., React source for a web prototype or genkit service), the closest existing `src/` directories are:
- `genkit/src/` — for genkit AI server code
- `Backend/functions/src/` — for TypeScript Cloud Functions (primary backend)
- `cloud-run/search/src/` and `cloud-run/feed/src/` — for Cloud Run services

**REACT_PROTOTYPE_PATH:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Prototypes/SabbathMode/` (new directory, does not exist yet — must be created). For backend TypeScript functions: `Backend/functions/src/sabbath/`.

---

## T7 — Backend Structure

✅ FOUND

**Canonical backend for new features:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Backend/functions/src/` (TypeScript, v2 Firebase Functions)

**The file `Backend/functions/v2functions.js` does NOT exist.** The legacy JS backend lives at `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/v2functions.js` — this is the OLD JS backend, not the primary one. **New Sabbath functions must be written in TypeScript in `Backend/functions/src/`.**

### Naming conventions from `Backend/functions/src/` exports:

**Pattern 1 — camelCase verb+Noun callables:**
```
evaluateRestMode          ← existing, from restModeEvaluator.ts
setRestModePolicy         ← existing
onRestModePolicyWritten   ← existing (Firestore trigger)
bereanChatProxy           ← callable
generateChurchNotesSummary
bereanHelperSummarizePrompt
```

**Pattern 2 — camelCase domain+Action:**
```
checkBiblicalAlignment
suggestBiblicalRewrite
saveAICorrection
getDiscernmentPrompt
```

**Pattern 3 — on+Event (Firestore/RTDB triggers):**
```
onRestModePolicyWritten
onPostCreated
onRealtimeCommentCreate
onMessageSent
onUserFollow
```

**Pattern 4 — scheduled+Action:**
```
sendDailyNotificationDigest
generateNextYearHolidayCalendar
calculateCovenantChurnRisk
```

**Legacy JS functions/index.js callModel pattern (DO NOT use for new TS functions):**
```
callModelBerean
callModelCommentCoach
callModelDailyBrief
callModelSearch
```

**V2FUNCTIONS_NAMING_CONVENTION:**  
For new Sabbath Mode Cloud Functions in TypeScript (`Backend/functions/src/sabbath/`), follow the pattern of `restModeEvaluator.ts`:
- Callables: `camelCase` verb+Noun, e.g. `evaluateSabbathMode`, `getSabbathPolicy`, `setSabbathPreference`
- Triggers: `on` + PascalCase event, e.g. `onSabbathPolicyWritten`
- Scheduled: `scheduledSabbathWindowCheck`
- Export via `Backend/functions/src/index.ts` with `export * from "./sabbath/yourFile"`
- Region: always `{ region: "us-central1" }`
- Auth + App Check: always required (`if (!request.app) throw HttpsError("unauthenticated", ...)`)

---

## Summary Tables

### SAFETY_ALLOW_LIST

These three surfaces MUST remain accessible during Sabbath Mode regardless of gate state:

```swift
// AmenRoute identifiers that must always be in RestModeRoutes.allowed
let SABBATH_SAFETY_ALLOW_LIST: [String] = [
    "emergency_support",      // → CrisisResourcesDetailView (NavigationLink in ResourcesView line 603)
    "trusted_circle",         // → TrustedCircleView (NavigationLink in ResourcesView line 907)
                              //   NOTE: No current AmenRoute case for this — must ADD .trustedCircle
    "child_safety_report"     // → ChildSafetyAgentStubView (NavigationLink in PrivacySettingsView line 729)
                              //   NOTE: Currently a STUB — add AmenRoute case when live flow is built
]
```

**WARNING for downstream agents:**
- `emergency_support` already exists in `AmenRoute` and `RestModeRoutes.allowed`. No change needed.
- `trusted_circle` does NOT exist in `AmenRoute` — you must ADD `case trustedCircle = "trusted_circle"` and add `"trusted_circle"` to `RestModeRoutes.allowed`.
- `child_safety_report` does NOT exist in `AmenRoute` — add `case childSafetyReport = "child_safety_report"` and add to `RestModeRoutes.allowed`. The view is currently `ChildSafetyAgentStubView`; update when live.

### TIMEZONE_SOURCE

```
iOS (device-level):     TimeZone.current.identifier  — runtime, no storage needed
Server (policy-level):  Firestore: restModePolicies/{uid}.timezone  — IANA string, set when user saves policy
Server (fallback):      Firestore: users/{uid}/deviceTokens/{token}.timezone  — per-device, written on token registration
UserDefaults (local):   "shabbatMode_userTimezone" key in ShabbatModeService  — local cache only, not synced
```

Sabbath Mode MUST evaluate timezone on the server using `restModePolicies/{uid}.timezone`. Follow the exact pattern in `restModeEvaluator.ts` function `isPolicyActive()`.

### REACT_PROTOTYPE_PATH

```
New Sabbath prototype files → /Users/stephtapera/Desktop/AMEN/AMENAPP copy/Prototypes/SabbathMode/
New Sabbath CF TypeScript   → /Users/stephtapera/Desktop/AMEN/AMENAPP copy/Backend/functions/src/sabbath/
Export registration         → /Users/stephtapera/Desktop/AMEN/AMENAPP copy/Backend/functions/src/index.ts
                              (add: export * from "./sabbath/yourFunction";)
```

### V2FUNCTIONS_NAMING_CONVENTION

```
Callables:  evaluateSabbathMode | getSabbathPolicy | setSabbathPreference | getSabbathWindowStatus
Triggers:   onSabbathPolicyWritten | onSabbathWindowChanged
Scheduled:  scheduledSabbathWindowEvaluation
Region:     always "us-central1"
Auth:       if (!request.app) throw HttpsError("unauthenticated", "App Check required.")
            if (!request.auth) throw HttpsError("unauthenticated", "Must be authenticated.")
Export via: Backend/functions/src/index.ts
```

---

## Key File Reference (Absolute Paths)

| Item | Path |
|------|------|
| Root navigation | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ContentView.swift` |
| App entry | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPPApp.swift` |
| Shabbat service | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ShabbatModeService.swift` |
| RestModeGate | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/RestModeGate.swift` |
| RestModePolicy | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/RestModePolicy.swift` |
| SundayRestModeSheet | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/SundayRestModeSheet.swift` |
| SundayChurchFocusManager | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SundayChurchFocusManager.swift` |
| CrisisResourcesDetailView | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/CrisisResourcesDetailView.swift` |
| TrustedCircleView | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/TrustedCircleView.swift` |
| ChildSafetyAgentStubView | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/TrustOS/GatedAgentStubViews.swift` |
| ResourcesView (navigation hub) | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ResourcesView.swift` |
| RestModeEvaluator (CF) | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Backend/functions/src/restModeEvaluator.ts` |
| Backend index.ts | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/Backend/functions/src/index.ts` |
| Routing config (JS) | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/router/amenRouting.config.js` |
| Config.xcconfig | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/Config.xcconfig` |
| UserModel | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/UserModel.swift` |
| AuthViewModel | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AuthenticationViewModel.swift` |
| NotificationService | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/NotificationService.swift` |
| LiquidGlass tokens | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AmenGlassDesignTokens.swift` |
| LiquidGlass components | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AIIntelligence/LiquidGlass/AmenLiquidGlassComponents.swift` |
| ConnectSpaces hub | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift` |
| FindChurchView | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/FindChurchView.swift` |
| ChurchNotesService | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ChurchNotesService.swift` |
| BereanContextCoordinator | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AIIntelligence/BereanContextCoordinator.swift` |
| ModelRoutingEngine | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ModelRoutingEngine.swift` |
| v2functions (legacy JS) | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/functions/v2functions.js` |
| RestModeTests | `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPPTests/RestModeTests.swift` |
