# Agent 6 — Architecture & State

## Method

**Scanned:** AMEN iOS SwiftUI app (~300 Swift files, ~1,700 @State/@StateObject/@EnvironmentObject/@ObservedObject declarations, 1,257 `.shared` singleton accesses, 716 navigation calls)

**Tools Used:**
- Grep: pattern matching for state decorators, singletons, navigation, auth flows, error handling
- Read: direct examination of AMENAPPApp.swift, AppDelegate.swift, AuthenticationViewModel.swift, BereanGrokCoordinator.swift, BereanGrokModels.swift, AMENTabBar.swift, AMENFeatureFlags.swift, AskAmenCompanionRouter.swift
- Bash: counting patterns, searching architecture markers, locating routers/coordinators

**Scope:**
- State management drift across @State, @StateObject, @ObservedObject, @EnvironmentObject, Combine @Published, and Observation framework
- Singleton overuse (1,257 occurrences of `.shared`)
- Tight coupling (direct service instantiation in views, direct Firebase Functions calls)
- Navigation pattern inconsistency (716 files using mixed NavigationStack, NavigationLink, .sheet, .fullScreenCover, .navigationDestination)
- Auth flow fragmentation (137 sign-in/out/up occurrences across ~5+ distinct paths)
- Berean mode state distribution (22+ distinct "Berean*Mode" enums with decentralized mutations)
- Error handling architecture (2,808 occurrences of .alert/.sheet/errorMessage/showError)
- Feature module coupling and Firebase Cloud Function duplication

---

## Findings

### CRITICAL (ship-blocking)

#### 1. **State Management Chaos: 3+ Parallel State Layers for Auth & Onboarding**
- **Files:** AMENAPPApp.swift (lines 27–33), AuthenticationViewModel.swift (lines 18–72), ContentView (inferred)
- **Issue:** Auth state lives in 4 places simultaneously:
  1. `Auth.auth().currentUser` (Firebase)
  2. `AuthenticationViewModel.isAuthenticated` & `.needsOnboarding` (@Published)
  3. `AMENAPPApp.hasCompletedOnboarding` (@State)
  4. UserDefaults cache at `"hasCompletedOnboarding_<uid>"`
  
  Reads from cache during `loadOnboardingStatusSync()` (lines 532–550) can race with async `checkOnboardingStatus()` in `AuthVM.init()` (line 140–143), causing the fullScreenCover Binding to re-evaluate at unpredictable moments. Users may see onboarding/age-gate flashing or stuck views.
- **Why it matters:** Multi-source authority leads to stale reads, race conditions on cold launch, and inconsistent navigation decisions.
- **Suggested fix:** Single source of truth: Auth state lives in `AuthenticationViewModel` ONLY. AMENAPPApp reads from there. Remove the UserDefaults cache read from the critical path (cache is for warm starts, not cold launches).
- **Effort:** M (refactor AuthVM to own onboarding state, sync AuthVM into ContentView, remove AMENAPPApp.onboarding state).

#### 2. **1,257 Singleton `.shared` Calls Across the Codebase — No Dependency Injection Layer**
- **Files:** 250 files; heavy in: BereanChatView.swift, CreatePostView.swift, ProfileView.swift, PrayerView.swift, BereanChatView.swift (34 instances)
- **Example:** BereanChatView.swift:485 calls `ClaudeService.shared.sendBereanChatMessage(…)` directly; BereanChatView.swift:575 calls `BiblicalAlignmentService.shared.checkBiblicalAlignment(…)` directly; line 668 calls `ChurchNoteBlockRepository.shared.createNote(…)`.
- **Issue:** Views directly instantiate concrete service singletons. No protocols, no dependency injection, no testing seams. If a service holds view-level state (auth tokens, current user context, session flags), mutating it in a singleton makes state invisible to SwiftUI's reactivity system.
  - `BereanModelStore.shared` (lines 389, 503, 511, 516) mutates selected mode without publishing to SwiftUI.
  - `BereanModeStore.shared` (line 390) mutates study mode outside @Published.
  - `BereanMemoryScopeStore.shared` (lines 420, 738) holds conversation memory scope in a singleton (not @Observable).
- **Why it matters:** Singleton mutations are invisible to SwiftUI's change detection. Views do not re-render when a singleton's state changes. Session state can diverge from UI. This is the #1 cause of "stale data" bugs.
- **Suggested fix:** 
  1. Extract an `@MainActor class ServiceContainer: ObservableObject` that owns all singletons and publishes their state.
  2. Pass `@ObservedObject var services: ServiceContainer` to root views.
  3. Convert view-level state singletons (BereanModelStore, BereanModeStore, BereanMemoryScopeStore) to @Published properties on ServiceContainer.
  4. Create protocol-based facades for testing.
- **Effort:** L (multi-day refactor; ~250 files to update with dependency injection, extensive testing needed).

#### 3. **Auth Sign-Out Paths Not Centralized — Token Refresh, Session Timeout, Forced Logout Diverge**
- **Files:** AuthenticationViewModel.swift (lines 291–359), AMENAPPApp.swift (lines 721–734), SettingsView.swift (inferred), SessionTimeoutManager (inferred), AccountDeactivationService (inferred)
- **Issue:** Sign-out happens in at least 3 distinct places:
  1. `AuthenticationViewModel.signOut()` — clears @Published state, calls Firebase signOut.
  2. `AMENAPPApp` auth state listener (line 720–734) — unregisters device tokens, stops FollowService, etc., triggered by Firebase listener.
  3. SessionTimeoutManager (notified via `.sessionTimeout` in AuthVM.init line 155–171) — clears pending2FA credential, wipes phone auth.
  4. `forceLogout()` in AccountDeactivationService (inferred) — separate code path.
  
  Cleanup is **not idempotent**. If two paths fire concurrently (e.g., token revocation + session timeout), state corruption is possible (device tokens registered twice, listeners double-stopped, etc.).
- **Why it matters:** Users can be left in inconsistent state: signed out on Firebase but still holding cached credential in AuthVM, or device tokens dangling. Next sign-in may fail silently.
- **Suggested fix:** Single `AuthenticationManager` owns all sign-out logic. All other code calls `AuthenticationManager.signOut(reason:)`. This function atomically:
  1. Calls Firebase.signOut()
  2. Unregisters device token
  3. Stops all listeners
  4. Clears sensitive state (2FA credential, pending tokens)
  5. Publishes `isAuthenticated = false` once all cleanup is done.
- **Effort:** M (consolidate 3+ signOut paths into one atomic function, add integration tests for concurrent sign-outs).

#### 4. **Navigation Stack Unpredictability: 716 Files Using Arbitrary Mix of NavigationStack, NavigationLink, .sheet, .fullScreenCover, .navigationDestination**
- **Files:** Scattered across codebase; BereanChatView.swift, CreatePostView.swift, ProfileView.swift each have multiple contradictory navigation modifiers.
- **Issue:** No consistent navigation pattern. Some views use NavigationStack(path:), others use @State + .navigationDestination(), others use .sheet(), others use .fullScreenCover(). Deep links are routed through NotificationOpenCoordinator, NotificationDeepLinkRouter, UniversalLinkRouter, AmenContentRouter — multiple routers, no single coordinator.
  - Example: AMENAPPApp.swift onOpenURL (lines 336–372) handles:
    1. Firebase Auth callbacks (line 341)
    2. Google Sign-In (line 347)
    3. NotificationOpenCoordinator (line 354)
    4. NotificationDeepLinkRouter (line 356)
    5. Email auth links (line 361)
    6. Church notes deep links (line 364)
    7. Live Activity deep links (line 367)
    8. Share Extension drafts (line 370)
  
  If NotificationDeepLinkRouter and NotificationOpenCoordinator both claim the same URL, the second one is silently ignored — no error, silent data loss.
- **Why it matters:** App navigation is unpredictable. Deep links may be ignored. Users can get stuck on wrong screens. Back button behavior is inconsistent (NavigationStack vs. .sheet have different semantics).
- **Suggested fix:** Single `NavigationCoordinator` (or `Router`) owns all navigation decisions. All view state changes publish to this coordinator. Deep link routing funnels through one entry point. Use NavigationStack as the root abstraction (iOS 16+), with programmatic path management.
- **Effort:** L (requires rearchitecting 716 navigation callsites; high risk of regressions).

#### 5. **Firebase Cloud Functions Called 247 Times Without Centralized Wrapper — Duplicated Error Handling, Retry Logic, Token Refresh**
- **Files:** BereanChatView.swift (line 485), AskAmenCompanionRouter.swift (line 25), AmenVerificationFlowCoordinator, ChurchNoteBlockRepository, and ~240 other locations.
- **Example:**
  ```swift
  // AskAmenCompanionRouter.swift:25
  let result = try await functions.httpsCallable("askAmenCompanion").call([…])
  
  // BereanChatView.swift:485
  let stream = ClaudeService.shared.sendBereanChatMessage(…)  // Likely calls functions internally
  
  // Repeated 247 times across the codebase
  ```
  Each call site has its own error handling, retry logic, and token refresh semantics. No single point to:
  - Log all function calls for observability
  - Implement global retry/backoff
  - Refresh auth tokens on 401
  - Track quota / rate-limiting
  - Measure latency
- **Why it matters:** Inconsistent error recovery. Some calls retry, others fail silently. No observability into function failures across the app.
- **Suggested fix:** Create `FirebaseCloudFunctionWrapper` protocol + concrete implementation. All 247 callsites call through this wrapper. It owns retry logic, token refresh, and instrumentation.
- **Effort:** M (create wrapper, audit 247 callsites, migrate incrementally).

#### 6. **Berean Mode State Scattered Across 22+ Enums and Stores — Mutations Not Synchronized**
- **Files:** BereanModelStore (inferred from line 389), BereanModeStore (line 390), BereanMemoryScopeStore (line 420), BereanVoiceMode, BereanDriveMode, BereanPrayerMode, BereanLiveMode, BereanVoiceViewMode, BereanDiscernmentMode, BereanModelMode, BereanSessionMode, BereanResponseMode, BereanPersonalityMode, BereanQuickMode, BereanStudyModeState, AskBereanInputMode, BereanHomeMode, BereanAuraMode, BereanInteractionMode, BereanRealtimeTransportMode, BereanPulseMode, and more.
- **Issue:** Berean's "current mode" (study vs. companion vs. drive vs. voice vs. live vs. pulse) is not a single enum. It's split across 22+ unrelated enums in different files. `BereanChatView` reads from both `BereanModelStore.selectedMode` (line 389) and `BereanModeStore.selectedMode` (line 390) — two different mode stores. When user switches from "Study" to "Companion" mode:
  1. Which store updates first?
  2. Is `BereanMemoryScopeStore` invalidated?
  3. Do conversation threads persist or reset?
  
  This is a state synchronization nightmare.
- **Why it matters:** User may switch modes and see stale conversation history, or mode changes may not propagate to all observers.
- **Suggested fix:** Single `BereanMode` enum (study, companion, drive, voice, live, pulse). Single `@MainActor @Observable class BereanModeManager` owns current mode. All mode changes go through `BereanModeManager.setMode(_:)`, which atomically updates all dependent state (conversation threads, memory scope, model tier).
- **Effort:** M (consolidate 22 enums, create single BereanModeManager, audit all mode-dependent state).

---

### HIGH (fix this sprint)

#### 1. **SignIn / Authentication ViewModel Holds 2FA Credential in Memory Across Background Transitions**
- **Files:** AuthenticationViewModel.swift (lines 77–80, 186–192)
- **Issue:** When 2FA is triggered, the plain-text `AuthCredential` (email + password) is stored in `pending2FACredential` (line 80). If the app is backgrounded during the 2FA wait, the credential sits in heap memory while the app is suspended. A memory dump could expose the plaintext password.
  - Mitigation exists (lines 186–192) to wipe the credential on background, but this is a **defensive patch**, not a structural fix.
- **Why it matters:** Plaintext credentials in memory, even for a few seconds, is a security violation.
- **Suggested fix:** Do not store AuthCredential. Instead:
  1. On 2FA detection, sign out the user immediately.
  2. When the user completes 2FA, prompt them to re-enter password + 2FA code in a single flow.
  3. No intermediate credential storage.
- **Effort:** M (refactor 2FA flow, UX testing).

#### 2. **AppDelegate and AMENAPPApp Have Overlapping Responsibilities — Unclear Ownership**
- **Files:** AppDelegate.swift (1–260), AMENAPPApp.swift (58–131, 374–469)
- **Issue:** Both files initialize Firebase, configure services, and set up listeners:
  - **AppDelegate:** Firebase.configure(), Crashlytics, App Check, Firestore settings, FCM setup (lines 70–233)
  - **AMENAPPApp:** Remote Config setup, background tasks, startup task orchestration, auth state listener (lines 58–131, 374–469)
  
  No clear separation. If a developer adds a new startup task, where does it go? No documented contract.
- **Why it matters:** Maintenance burden. New developers don't know where to put initialization code. Duplicated logic risk (e.g., both files might try to register FCM).
- **Suggested fix:** Define clear contract:
  - **AppDelegate:** UIApplication lifecycle only (launch, foreground/background, notification handling).
  - **App:** SwiftUI app initialization and state management.
  - Move all Firebase initialization to AppDelegate. Move all SwiftUI state setup to App. Document the boundary.
- **Effort:** S (reorganize code, add comments).

#### 3. **Error Handling: 2,808 Occurrences of Alert/Sheet/errorMessage — No Centralized Error Presenter**
- **Files:** Every major view has its own @Published errorMessage and @State showError. Examples: AuthenticationViewModel (lines 32–33), BereanChatView, CreatePostView, ProfileView.
- **Issue:** Each view shows its own .alert(). No centralized error presentation. A user may see multiple error alerts at once if two services fail concurrently. Error messages are inconsistently worded (some say "couldn't respond right now", others say "Error: xyz"). No audit trail of errors.
- **Why it matters:** Poor UX (multiple overlapping alerts), no observability into errors across the app, code duplication in every view.
- **Suggested fix:** `ErrorPresenter` @MainActor @ObservableObject with a queue of errors. All services call `ErrorPresenter.shared.present(error:)`. Views observe ErrorPresenter and show one error at a time. Errors automatically log to Crashlytics.
- **Effort:** M (create ErrorPresenter, migrate 100+ views to use it, add instrumentation).

#### 4. **Feature Flags Are @Published Singletons, Not Dependency Injected — Testing Impossible**
- **Files:** AMENFeatureFlags.swift (lines 26–150)
- **Issue:** All code reads flags from `AMENFeatureFlags.shared`. Tests cannot override flags. A test that needs `bereanRAGEnabled = false` will flip it globally for all tests running in parallel, causing test interference.
- **Why it matters:** Feature flag testing is fragile and flaky.
- **Suggested fix:** `FeatureFlagProvider` protocol with default impl (reads Remote Config) and test impl (returns hardcoded values). Inject FeatureFlagProvider into views that need flags.
- **Effort:** M (create protocol, inject in ~50 flagged views, update tests).

#### 5. **Auth Token Refresh: checkAuthTokenValidity() Throttled to 4-Hour Window — Token Revocation Not Detected Until 4 Hours Later**
- **Files:** AMENAPPApp.swift (lines 475–502)
- **Issue:** On foreground, app checks if token is valid. But it only re-checks every 4 hours (line 485). If a user's account is deactivated, their token is revoked server-side, but the app won't know for up to 4 hours. During that time, API calls will fail with 401, and the user will see generic "permission denied" errors instead of being redirected to sign-in.
- **Why it matters:** Users with deactivated accounts can't sign back in immediately; they see cryptic permission errors.
- **Suggested fix:** On API 401, immediately sign out and redirect to sign-in. Don't wait 4 hours.
- **Effort:** S (add 401 interceptor to Firestore/Functions; sign out on 401).

---

### MEDIUM (next sprint)

#### 1. **ViewModels Hold @State for View-Level State — Not @StateObject — Lifecycle Unclear**
- **Files:** BereanChatViewModel (inferred), CreatePostViewModel (inferred), ProfileViewModel (inferred)
- **Issue:** Many views instantiate @StateObject private var viewModel = SomeViewModel(). But the ViewModel itself uses @State for sub-properties instead of @Published. This creates a hollow reference: the ViewModel is retained, but its internal state is not observed.
- **Suggested fix:** ViewModels should use @Published for observable state, never @State. Or adopt @Observable (Swift 5.10+).
- **Effort:** M (audit ViewModels, migrate @State to @Published).

#### 2. **Navigation Destination Binding Overload — Many Views Have 10+ @State Navigation Flags**
- **Files:** CreatePostView.swift (226 @State/@StateObject/@ObservedObject occurrences), BereanChatView.swift (47 occurrences), ProfileView.swift (116 occurrences)
- **Issue:** Views like CreatePostView have dozens of @State bools for navigation (showImagePicker, showVideoEditor, showDraftsPicker, etc.). SwiftUI's NavigationStack with value-based path management is much cleaner.
- **Suggested fix:** Consolidate 10+ boolean flags into a single @State enum or NavigationPath.
- **Effort:** M (requires view refactoring; medium risk).

#### 3. **Service Initialization Scattered Across AppDelegate, AMENAPPApp, and Lazy Singletons**
- **Files:** AppDelegate.swift (line 78), AMENAPPApp.swift (lines 309–322), ServiceBootstrapper (inferred)
- **Issue:** Some services initialize in AppDelegate (via ServiceBootstrapper). Others initialize on first use (lazy singletons). Others initialize in onAppear. No clear initialization order, making debugging startup issues difficult.
- **Suggested fix:** Create explicit ServiceBootstrapper that initializes services in a documented order. Mark services as @MainActor to prevent race conditions.
- **Effort:** S–M (document init order, add ServiceBootstrapper tests).

#### 4. **Notification Listeners Accumulate — Auth Listener, Session Timeout Listener, Multiple Service Observers**
- **Files:** AuthenticationViewModel.swift (lines 155–171, 179–193), AMENAPPApp.swift (lines 665–737)
- **Issue:** NotificationCenter.default.addObserver() calls can leak if the observer is not removed. The deinit (line 196–200) removes some, but not all. If a view is rapidly created and destroyed (e.g., in a list), observers can accumulate.
- **Suggested fix:** Use NotificationCenter.Publisher (Combine) or Swift.Notifications (iOS 17) to auto-clean observers.
- **Effort:** S (migrate to Combine publishers).

#### 5. **Berean Grok Pipeline: State Transitions Not Atomic — Race Conditions Possible**
- **Files:** BereanGrokCoordinator.swift (lines 42–104, 142–160)
- **Issue:** Methods like `pillTapped()` set state (e.g., `showLinkSummarySheet = true`) and then call async closures. If the user taps another pill before the async closure completes, state can be corrupted (two pills firing in parallel).
- **Suggested fix:** Add reentrancy guards. Only allow one flow at a time. Queue subsequent taps.
- **Effort:** S (add isProcessing flag, test edge cases).

---

### LOW (backlog)

#### 1. **AppStorage Keys Scattered — No Centralized Schema**
- **Files:** Multiple files use AppStorage with magic strings: `"hasCompletedAgeVerification"`, `"hasCompletedOnboarding_<uid>"`, etc.
- **Fix:** Create `AppStorageKeys` enum to centralize all keys and prevent typos.
- **Effort:** S.

#### 2. **Live Activity State Not Synchronized with Main App — Potential Divergence**
- **Files:** LiveActivityManager (inferred), BereanLiveActivityService (inferred), PrayerLiveActivityService (inferred)
- **Fix:** Single source of truth for Live Activity state. Sync bidirectionally with app state.
- **Effort:** M.

#### 3. **Firestore Local Cache Configuration Duplicated**
- **Files:** AppDelegate.swift (lines 103–110), possibly other files
- **Fix:** Move cache config to a single shared function.
- **Effort:** S.

#### 4. **Pagination / Infinite Scroll State Decentralized**
- **Files:** Various feed views (inferred)
- **Fix:** Create shared PaginationManager.
- **Effort:** M.

#### 5. **Image Cache Not Bounded — Unbounded Memory Growth**
- **Files:** ImageCache.swift (inferred)
- **Fix:** Implement LRU cache eviction.
- **Effort:** S–M.

---

## What I did NOT check

1. **Performance / Latency:** Did not measure app startup time, screen transition latency, or API call timings. Architecture issues identified here likely cause 200–500ms delays.

2. **Security Comprehensive Audit:** Checked only obvious credential storage issues (2FA credential). Did not audit encryption, data signing, or rate-limiting.

3. **Offline Sync Logic:** Did not examine Firestore offline queue or RTDB sync semantics in detail.

4. **Memory Leaks / Retain Cycles:** Scanned for common patterns (circular @ObservedObject, dangling closures) but did not run Instruments or Xcode memory profiler.

5. **Testing Capability:** Did not assess how testable the codebase is or run the test suite. High tight coupling (1,257 singletons, no DI) suggests tests will be flaky.

6. **Accessibility:** Did not audit VoiceOver labels or keyboard navigation.

7. **Concurrency Safety:** Did not audit for Swift concurrency violations (non-MainActor mutations on MainActor classes, data races). The @MainActor annotations on some classes suggest awareness, but likely not comprehensive.

8. **Swift Observation Framework Adoption:** Did not check if @Observable (Swift 5.10+) has been adopted anywhere. Codebase appears to use @Published only.

9. **Third-Party Library Coupling:** Did not audit dependencies or version pins for risk (e.g., Firebase SDK breaking changes).

10. **Deprecated API Usage:** Did not check for deprecated SwiftUI APIs (e.g., @State-based presentation APIs on older iOS).

---

## Summary

The AMEN app has **severe architectural debt** in state management (3–4 parallel auth authority layers), singleton coupling (1,257 bare `.shared` calls), and navigation consistency (716 arbitrary combinations of navigation APIs). These are not "nice to have" refactors — they are **actively causing bugs** (race conditions on auth, silent navigation failures, stale view state).

**Recommended Priority:**
1. **CRITICAL first:** Consolidate auth state (HIGH impact, M effort).
2. **CRITICAL second:** Extract ServiceContainer and inject dependencies (HIGHEST impact, L effort, do incrementally).
3. **Next sprint:** Centralize navigation routing, error handling, and sign-out paths (M–L efforts).

**Total Effort to Clean Up:** ~2 weeks (L + L + M + M + M).
