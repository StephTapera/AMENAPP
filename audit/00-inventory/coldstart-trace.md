# AMEN iOS App — Cold Start Trace

**Root Entry:** `AMENAPPApp.swift` (marked with @main)  
**First View:** `ContentView.swift` (via @main struct App.body)  

## Phase 0: Process Init (before any code runs)

1. **Firebase.configure()** → `AppDelegate.didFinishLaunchingWithOptions`
   - FirebaseCore setup
   - FirebaseAuth initialization
   - FirebaseFirestore initialization + persistence config
   - FCM initialization
   - Crashlytics initialization
   - App Check initialization

2. **Background Task Registration** → `AMENAPPApp.init()`
   ```swift
   BGTaskScheduler.shared.register(
       forTaskWithIdentifier: "com.amen.app.refresh"
   )
   ```

3. **URL Cache Configuration** → `AMENAPPApp.init()`
   - 200MB memory, 500MB disk

4. **Remote Config Init** → `AMENAPPApp.init()`
   ```swift
   Task { Self.setupRemoteConfig() }  // async task
   ```

---

## Phase 1: App Launch → ContentView Render

### Entry Point
```swift
@main struct AMENAPPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var killSwitch = RemoteKillSwitch.shared
```

### ContentView Initial Render
```swift
struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @StateObject private var authViewModel: AuthenticationViewModel
    @ObservedObject private var appReadyState = AppReadyStateManager.shared
    @State private var showSplash = true
```

**Timeline:**
- `T+0ms` — ContentView.init() fires
  - `ContentViewModel()` created (tab state = 0 by default)
  - `AuthenticationViewModel()` created → checks `Auth.auth().currentUser`
  - `AppReadyStateManager.shared` accessed (singleton)
  - `RemoteKillSwitch.shared` accessed (singleton)

- `T+5ms` — First render decision: `if !authViewModel.isAuthenticated { SplashView }`

---

## Phase 2: Auth State Resolution

### Path 1: New User (No Firebase User Signed In)

```swift
if !authViewModel.isAuthenticated {
    SplashView {
        withAnimation(.easeIn(duration: 0.2)) { showSplash = false }
    }
    .onAppear {
        dlog("🚦 [LAUNCH] ContentView → auth landing appeared (isAuthenticated=false)")
        if Auth.auth().currentUser == nil {
            AppReadyStateManager.shared.signalReady()
        }
    }
}
```

**Branch: No User**
1. `AppReadyStateManager.signalReady()` called
   - Loading overlay dismissed (if shown)
   - `isShowingLoadingScreen = false`
2. Splash screen shown
3. User taps "Sign Up" or "Sign In"
4. Goes to SignInView / SignUpView

**Branch: Auth State Pending (fast cached user)**
1. If user was previously signed in and cached locally:
   - `Auth.auth().currentUser != nil` immediately
   - `AppReadyStateManager.signalReady()` NOT called here
   - Loading overlay stays visible
   - Auth listener fires → continues to next gate

### Path 2: Returning User (Cached Auth)

```swift
@State private var lastAuthStateUserId: String? = nil

// In AppDelegate or AMENAPPApp auth listener setup:
Auth.auth().addStateDidChangeListener { [weak self] auth, user in
    guard let self else { return }
    if let user = auth.currentUser {
        if self.lastAuthStateUserId != user.uid {
            self.lastAuthStateUserId = user.uid
            // GUARD: Prevent duplicate startup tasks on spurious re-fires
            // (Firebase fires this on token refresh, RTDB reconnect, App Check completion)
        }
    }
}
```

**Cached User Path (T+0 to T+200ms):**
1. `Auth.auth().currentUser` returns cached user
2. `authViewModel.isAuthenticated = true`
3. ContentView checks: `authViewModel.needsUsernameSelection`?
   - If YES (social sign-in path) → UsernameSelectionView
   - If NO → check `authViewModel.needsOnboarding`

---

## Phase 3: Sequential Onboarding Gates

### Gate 1: Username Selection (Social Sign-In Only)

```swift
else if authViewModel.needsUsernameSelection {
    UsernameSelectionView()
        .onAppear {
            dlog("🚦 [LAUNCH] ContentView → UsernameSelectionView appeared")
            AppReadyStateManager.shared.signalReady()
        }
        .onDisappear {
            authViewModel.completeUsernameSelection()
        }
}
```

**Trigger:** Google/Apple sign-in creates account without username  
**Branch Decision:** `AuthenticationViewModel.needsUsernameSelection` property  
**File:** `AuthenticationViewModel.swift` → `checkUsernameRequired()` function  
**Exit Condition:** User enters username → `completeUsernameSelection()` sets flag to false

### Gate 2: Onboarding (New User Only)

```swift
else if authViewModel.needsOnboarding {
    OnboardingView()
        .onAppear {
            dlog("🚦 [LAUNCH] ContentView → OnboardingView appeared")
            AppReadyStateManager.shared.signalReady()
        }
}
```

**Trigger:** `AuthenticationViewModel.needsOnboarding` (set when account created)  
**File:** `OnboardingView.swift` → collects preferences, age confirmation  
**Special Behavior:**
- Completes BEFORE email verification gate
- Sets `showFirstPostPromptPending = true` before tearing down
- Calls `authViewModel.completeOnboarding()` in `finishOnboarding()` (P1-1 FIX)

**Exit Condition:** `authViewModel.needsOnboarding = false`

### Gate 3: Email Verification (If Unverified)

```swift
else if authViewModel.needsEmailVerification {
    EmailVerificationGateView()
        .onAppear {
            dlog("🚦 [LAUNCH] ContentView → EmailVerificationGateView appeared")
            AppReadyStateManager.shared.signalReady()
        }
}
```

**Trigger:** `AuthenticationViewModel.needsEmailVerification`  
**File:** `EmailVerificationGateView.swift` → resend link, check completion  
**Check:** `authViewModel.checkEmailVerification()` runs in background  
**Exit Condition:** `user.isEmailVerified || userDismissed`

### Gate 4: Account Status Check

```swift
} else {
    AccountStatusGateView {
        mainContent
    }
    .onAppear {
        dlog("🚦 [LAUNCH] mainContent.onAppear fired")
    }
}
```

**Trigger:** All previous gates passed  
**Checks:** Account not suspended, not deactivated  
**File:** `AccountStatusGateView.swift`  
**Exit Condition:** Account is in good standing

---

## Phase 4: Core Service Startup (Main App Entry)

### Entry Point: mainContent.onAppear

```swift
.onAppear {
    dlog("🚦 [LAUNCH] mainContent.onAppear fired (hasStartedCoreServices=\(hasStartedCoreServices))")
    
    guard !hasStartedCoreServices else { return }
    hasStartedCoreServices = true
    
    // Phase 1 — CRITICAL: feed ready signal
    Task(priority: .high) {
        _ = PostsManager.shared
        await waitForFeedReady()
        AppReadyStateManager.shared.signalReady()
    }
    
    // Safety: hard timeout
    Task {
        try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5s cap
        AppReadyStateManager.shared.signalReady()
    }
    
    // Phase 2: secondary singletons
    Task(priority: .medium) {
        _ = PostInteractionsService.shared
        await PremiumManager.shared.loadProducts()
    }
    
    // Phase 2b: listeners
    NotificationService.shared.startListening()
    if let uid = Auth.auth().currentUser?.uid {
        ChurchInteractionService.shared.startListening(userId: uid)
        Task { await AmenJourneyEngine.shared.initialize(userId: uid) }
    }
    
    // Deep link readiness
    NotificationDeepLinkRouter.shared.markAppReady()
    NotificationTapBootstrapper.shared.appDidBecomeReady()
    
    // Phase 3: deferred checks
    Task(priority: .utility) {
        await authViewModel.checkEmailVerification()
    }
}
```

**Idempotency Guard:** `guard !hasStartedCoreServices` prevents duplicate startup on foreground transitions  
**File/Line:** `ContentView.swift` → mainContent computed property → .onAppear handler

### Critical Path (User Can Interact)

**T+0s:** Feed initialized → PostsManager.shared loaded  
**T+<1s:** postDataLoaded event fires → `waitForFeedReady()` completes → `signalReady()`  
**T+5s:** Hard timeout fires → `signalReady()` ensures loading screen exits

### Background Tasks

**Task 1 (priority: .high):**
```swift
await waitForFeedReady()  // Waits for initial feed data from Firestore
```
**Task 2 (priority: .medium):**
```swift
await PremiumManager.shared.loadProducts()  // StoreKit product refresh
```

**Task 3 (priority: .utility):**
```swift
await authViewModel.checkEmailVerification()  // Silent background check
```

---

## Phase 5: User Interaction Ready (MainContent Visible)

### Loading Overlay Dismissal

```swift
@ObservedObject private var appReadyState = AppReadyStateManager.shared
private var isShowingLoadingScreen: Bool { appReadyState.isShowingLoadingScreen }
```

**Overlay Exits When:** `AppReadyStateManager.shared.signalReady()` is called  
**Earliest:** T+<1s (feed loaded)  
**Latest:** T+5s (hard timeout)

### First Interactive Frame

1. **AllTabsZStack Rendered**
   - Tab 0 (HomeView) is active by default
   - Other 7 tabs are opacity=0, hitTesting=disabled (but loaded)

2. **Listeners Active**
   - NotificationService listening to Firestore notifications
   - ChurchInteractionService listening to church events
   - PostsManager listener subscribed to feed updates

3. **User Can:**
   - Scroll feed (Tab 0)
   - Switch tabs (1-7)
   - Tap posts, users, etc. (navigation starts)
   - See badge counts (NotificationAggregationService)

---

## Branch Decision Points

| Condition | Check File | Property | Next State |
|-----------|-----------|----------|-----------|
| No signed-in user | `AuthenticationViewModel` | `isAuthenticated == false` | SplashView |
| Social sign-in | `AuthenticationViewModel` | `needsUsernameSelection == true` | UsernameSelectionView |
| New user account | `AuthenticationViewModel` | `needsOnboarding == true` | OnboardingView |
| Email unverified | `AuthenticationViewModel` | `needsEmailVerification == true` | EmailVerificationGateView |
| Account suspended | `AccountStatusGateView` | (checks Firestore role + isActive) | Error screen |
| Deactivated account | `ContentView.else if` | `authViewModel.isDeactivated == true` | ReactivationPromptView |
| Simple Mode enabled | `AmenSimpleModeService` | `isSimpleModeActive == true` | AmenSimpleModeView |
| Sabbath active | `SabbathModeService` | `currentState == .active` | SabbathWindowView |
| Sunday focus active | `SundayChurchFocusManager` | `shouldGateFeature()` | SundayChurchFocusGateView (conditional on tab) |

---

## Minor-Specific Branches

### Age Gate (COPPA)

**Location:** `AMENAPPApp.swift`  
**Property:** `@AppStorage("hasCompletedAgeVerification")`  
**File/Line:** `AMENAPPApp.swift` init → age verification flow triggered

**Branch: Under Minimum Age (< 13 US, < 16 EU)**
- Account creation blocked entirely
- OR: Limited account with restricted access
- File: `MinorSafetyService.checkAgeEligibility()`

**Branch: Teen (13-17 US)**
- Firestore rule gate: `ageTier == 'teen'`
- Restrictions:
  - Cannot post publicly (requiresPublicConfirmed=true)
  - Cannot create discussions publicly
  - Cannot join unverified spaces
  - Cannot send DMs except to mutual-followers
  - Job listings hidden entirely (read access denied)

**Branch: Adult**
- Full access

---

## No-Network Branch

**Condition:** Device is offline when launching  
**Behavior:**
1. Firebase Auth checks cached user (if previously signed in)
2. Firestore loads from cache (if available)
3. PostsManager.shared loads cached feed data
4. `waitForFeedReady()` timeout → 5s hard cap fires → `signalReady()`
5. User sees cached data + offline banner

**File:** `AMENAPPApp.swift` + `NetworkStatusService` (if implemented)

---

## Post-Onboarding First-Post Prompt

**Trigger:** Onboarding completes  
**Flag:** `showFirstPostPromptPending = true` set in `OnboardingView.finishOnboarding()`  
**Delivery:** `mainContent.onAppear` reads flag, clears it, shows sheet after 600ms delay

```swift
if UserDefaults.standard.bool(forKey: "showFirstPostPromptPending") {
    UserDefaults.standard.removeObject(forKey: "showFirstPostPromptPending")
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 600_000_000)  // 0.6s settle time
        showFirstPostPrompt = true
    }
}
```

**File:** `ContentView.swift` → mainContent.onAppear

---

## Summary Timeline (Returning Adult User)

| Time | Event | File:Line |
|------|-------|-----------|
| T+0ms | AMENAPPApp.init() | AMENAPPApp.swift:59 |
| T+5ms | ContentView renders | ContentView.swift:14 |
| T+10ms | authViewModel checks currentUser | AuthenticationViewModel.init() |
| T+50ms | First conditional: isAuthenticated=true | ContentView.swift:line 150-350 |
| T+60ms | mainContent.onAppear fires | ContentView.swift:line 276 |
| T+80ms | PostsManager.shared instantiated | ContentView.swift:line 308 |
| T+200ms | Feed data arrives | Firestore listener |
| T+250ms | waitForFeedReady completes | ContentView.swift:line 309 |
| T+260ms | signalReady() called | AppReadyStateManager.swift |
| T+270ms | Loading overlay exits | MainContent visible |
| T+280ms | AllTabsZStack renders HomeView | ContentView.swift:line 557 |
| T+300ms | Notifications listener starts | ContentView.swift:line 328 |
| T+400ms | User can interact | (varies by device) |

---

## Summary Timeline (New User)

| Time | Event | File:Line |
|------|-------|-----------|
| T+0ms | AMENAPPApp.init() | AMENAPPApp.swift:59 |
| T+5ms | ContentView renders | ContentView.swift:14 |
| T+50ms | SplashView shown | ContentView.swift:line 200 |
| T+100ms | User taps "Sign Up" | (external navigation) |
| T+X | SignUpView → account created | (Firebase Auth) |
| T+X+100ms | authViewModel.isAuthenticated = true | Firebase listener callback |
| T+X+150ms | ContentView re-evaluates | (state change) |
| T+X+200ms | needsUsernameSelection = true | (social sign-in) |
| T+X+300ms | UsernameSelectionView shown | ContentView.swift:line 225 |
| T+X+500ms | User enters username | (user input) |
| T+X+600ms | completeUsernameSelection() → needsOnboarding = true | AuthenticationViewModel.swift |
| T+X+700ms | OnboardingView shown | ContentView.swift:line 240 |
| T+X+30s | User completes onboarding | (varies) |
| T+X+31s | needsOnboarding = false, checkEmailVerification() runs | AuthenticationViewModel.swift |
| T+X+32s | EmailVerificationGateView shown (if needed) | ContentView.swift:line 250 |
| T+X+33s | mainContent visible → core services start | ContentView.swift:line 276 |
| T+X+35s | User can interact | (after feed loads) |

