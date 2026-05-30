# Agent 9 — Things You Might Forget

## Method
Read-only audit of AMEN iOS SwiftUI app codebase (~646K LOC across 1000+ files) using:
- **Grep**: Searched for offline/network patterns, timeouts, retries, character limits, locale/formatting, merge conflicts, error handling, `#if DEBUG`, `@testable import`, singleton state management
- **File reads**: AMENAPPApp.swift, AppDelegate.swift, BereanChatView.swift, BereanComposerState.swift, AmenCovenantCheckoutService.swift, EmptyFeedView.swift, RestModeGate.swift, AMENFeatureFlags.swift, NetworkMonitor.swift, GivingInAppSheet.swift
- **Scope**: Offline UX, network resilience, input validation, locale/currency, state lifecycle, build config, app backgrounding, crash surface area

---

## Findings

### CRITICAL (ship-blocking)

#### 1. Berean Chat: No offline fallback for streaming responses
**File**: BereanChatView.swift:43–900  
**Issue**: When user sends a message during no network or during streaming, there is no graceful offline state or error message shown. The `ClaudeService` streaming is initiated but if network drops mid-stream:
- No timeout on streaming tasks
- No retry mechanism for failed requests
- UI hangs in "streaming" state indefinitely
- User cannot cancel/dismiss the spinner

**Why it matters**: Users on cellular or during network glitches will see a frozen "Berean is thinking..." state with no way out. Directly impacts core AI feature (blocks Berean on poor networks).

**Suggested fix**: 
- Add 60-second timeout to streaming requests
- Show error banner if stream drops
- Add "Cancel" button during streaming
- Implement offline fallback message: "Berean is offline. Check your connection."

**Effort**: M

---

#### 2. No idempotency guard on Stripe checkout taps
**File**: AmenCovenantCheckoutService.swift:69–100  
**Issue**: If user rapidly taps "Complete Purchase" twice while ASWebAuthenticationSession is loading, `startCheckout(covenantId:tierId:)` can be called twice concurrently, issuing two `createCovenantCheckoutSession` Cloud Function calls. ASWebAuthenticationSession will present twice or cause race conditions in callback parsing.

**Why it matters**: Users can accidentally charge twice for Covenant subscriptions. Critical financial data-loss bug. App Store review rejection risk.

**Suggested fix**:
```swift
@Published private var isCheckoutInProgress = false

func startCheckout(...) async {
    guard !isCheckoutInProgress else { return }
    isCheckoutInProgress = true
    defer { isCheckoutInProgress = false }
    // ... rest of flow
}
```
Disable "Pay Now" button while `isCheckoutInProgress == true`.

**Effort**: S

---

#### 3. Singleton state leak on account switch / sign-out
**File**: AMENAPPApp.swift:719–735  
**Issue**: On sign-out, the code resets `fcmSetupDone` and calls `FollowService.shared.stopListening()`, but several singletons do NOT clear their cached user data:
- `PostInteractionsService.shared` — holds liked/amened/reposted sets for old user
- `DraftsManager.shared` — draft content from previous user
- `BadgeCountManager.shared` — unread count from old user
- `AmenSuggestionsService.shared`, `GrowthLoopEngine.shared` — personalized recommendations

On re-login with a different account in the same session, these singletons will serve stale user data to the new user until app restart.

**Why it matters**: Privacy leak (user A can see user B's saved posts) + incorrect feed/suggestions. Especially critical if testing multiple accounts or in family-share scenarios.

**Suggested fix**:
In `setupAuthStateListener()` on sign-out branch:
```swift
else {
    PostInteractionsService.shared.resetUserState() // add this
    DraftsManager.shared.clearAll()
    BadgeCountManager.shared.reset()
    AmenSuggestionsService.shared.clearCache()
    GrowthLoopEngine.shared.reset()
    // ... existing cleanup
}
```
Each singleton needs a public `reset()` method.

**Effort**: M

---

#### 4. Raw NSError shown to users in error states
**File**: BereanErrorView.swift, ComponentsSharedUIComponents.swift (error.localizedDescription)  
**Issue**: Throughout the app, error messages are displayed directly from NSError:
```swift
Text(error.localizedDescription)
```
Firebase errors return cryptic codes like: "Permission denied. Missing or insufficient permissions." or "[FIRAuthErrorCode.operation] 'account cannot be created' — user@example.com"

**Why it matters**: Users see internal error codes instead of friendly guidance. Bad UX on every failed network call.

**Suggested fix**: Wrap Firebase/network errors with user-friendly fallbacks:
```swift
func userFriendlyMessage(_ error: Error) -> String {
    let nsError = error as NSError
    switch nsError.code {
    case 17011: return "Email already in use. Try signing in instead."
    case 17020: return "Invalid email format."
    // Firebase codes: https://firebase.google.com/docs/auth/ios/errors
    default: return "Something went wrong. Please try again."
    }
}
```

**Effort**: M

---

### HIGH (fix this sprint)

#### 5. No character limit enforcement on Berean chat input
**File**: BereanChatView.swift (no validation visible in input field)  
**Issue**: BereanGenkitService trims input to 4000 chars server-side, but there is NO client-side UI indicator or hard limit on the input field. User can paste a 10,000-char message, tap send, and only the first 4000 is silently sent. User has no feedback that truncation happened.

**Why it matters**: Silent data loss on user input. User thinks they sent a full question but only the first ~4000 chars were processed.

**Suggested fix**:
- Add `maxLength: 4000` to TextField
- Show char counter: "4000 / 4000 characters"
- Disable send button when > 4000 chars

**Effort**: S

---

#### 6. No empty state for search results, Inbox, notifications
**File**: AmInbox.swift, SmartCommunitySearchView.swift (no EmptyStateView variant)  
**Issue**: When user searches with no results, or Inbox is empty, or notification list is empty — no view is shown. UI either:
- Shows a spinner forever
- Shows blank scroll area with no explanation

**Why it matters**: UX confusion. Users think the feature is broken ("why is nothing loading?") vs "no results found."

**Suggested fix**: Implement empty states per view:
```swift
if searchResults.isEmpty {
    EmptySearchResultsView(query: searchQuery)
} else {
    List(searchResults) { result in ... }
}
```

**Effort**: M

---

#### 7. Berean streaming response backgrounding
**File**: BereanChatView.swift, AMENAPPApp.swift scene phase  
**Issue**: When user is mid-conversation and Berean is streaming a response, then:
1. User backgrounds the app (home button)
2. System may kill the streaming task
3. User returns to app 10 minutes later
4. Chat is frozen in "streaming" state
5. No way to resume or clear the state

The `BehavioralAwarenessEngine.shared.endSession()` on background (line 451) does NOT cancel the streaming task or show offline/error state to the user.

**Why it matters**: Core Berean UX is broken after backgrounding during a stream. User must kill and reopen app.

**Suggested fix**:
- On scene phase → background, cancel any active streaming tasks
- Reset `streamingState` to `.idle` or `.failed`
- Show toast: "Connection paused. Reload to continue."

**Effort**: M

---

#### 8. No timeout on Firestore reads (feed load, profile load)
**File**: FirebasePostService.swift, UserProfileView.swift  
**Issue**: Firestore `.getDocument()` and `.getDocuments()` calls have no explicit timeout. On slow networks or Firestore outages:
- Feed load spins forever
- Profile load freezes
- User has no way to retry or dismiss

**Why it matters**: Common complaint on slow networks. App feels broken.

**Suggested fix**:
```swift
let task = Task {
    do {
        let doc = try await withTimeoutSeconds(30) {
            try await db.collection("posts").document(id).getDocument()
        }
    } catch URLError.timedOut {
        showError("Network timeout. Check your connection.")
    }
}
```

**Effort**: M

---

#### 9. First-launch blank screen for new users
**File**: AMENAPPApp.swift:200–421  
**Issue**: On first launch:
1. `ContentView()` renders
2. `AuthenticationViewModel.checkOnboardingStatus()` runs async in background
3. If user is new, `needsOnboarding = true` is set
4. **But** there is a race condition: the fullScreenCover for `OnboardingView` is gated on:
   ```swift
   hasCompletedOnboarding == false && Auth.auth().currentUser != nil
   ```
   If `hasCompletedOnboarding` defaults to `true` (line 544), and `AuthVM.needsOnboarding` is still loading, user sees ContentView (which tries to load feed) instead of onboarding.

**Why it matters**: New users see a broken feed view instead of being guided through first-use flow.

**Suggested fix**: 
- Ensure `hasCompletedOnboarding` starts as `nil` (optional)
- Block feed rendering until onboarding status is known
- Show loading screen instead of blank feed

**Effort**: M

---

#### 10. No currency locale formatting in Giving / Spaces
**File**: GivingInAppSheet.swift:160, SpacesFeeCalculatorWrapper.swift  
**Issue**: Hardcoded "$" symbol for currency:
```swift
Text("$\(Int(amount))")  // Always "$" even if user is in EUR/GBP locale
```
And no locale-aware number formatting (e.g., "1,000.00 USD" vs "1.000,00 EUR").

**Why it matters**: International users see wrong currency symbol. Financial app credibility issue.

**Suggested fix**:
```swift
let formatter = NumberFormatter()
formatter.locale = Locale.current
formatter.currencyCode = userCurrency ?? "USD"
formatter.numberStyle = .currency
Text(formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)")
```

**Effort**: M

---

#### 11. DateFormatter without locale set
**File**: CreatePostView.swift:lines with DateFormatter  
**Issue**: Multiple places create DateFormatter but don't set locale:
```swift
let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: selectedDateTime)
```
This uses system locale by default, but if locale is changed mid-session, formatter is stale.

**Why it matters**: Date display could be inconsistent or wrong after locale changes.

**Suggested fix**:
```swift
let f = DateFormatter()
f.locale = Locale.autoupdatingCurrent  // or Locale.current
f.dateFormat = "EEEE"
return f.string(from: selectedDateTime)
```

**Effort**: S

---

### MEDIUM (next sprint)

#### 12. No pagination / infinite scroll protection
**File**: BereanChatView.swift:857–884 (loadOlderMessages), OpenTableView.swift  
**Issue**: `loadOlderMessages()` will fetch every page on rapid upward scrolls. No debounce, no max-pages guard. Could fetch 100+ pages if user scrolls aggressively through a long conversation.

**Why it matters**: Wasteful network/bandwidth. Potential DoS on self.

**Suggested fix**: Debounce `loadOlderMessages()` with 500ms delay, add `maxMessagesAllowed = 1000` cap.

**Effort**: S

---

#### 13. Emoji-heavy posts can break layout
**File**: ThinkFirstGuardrailsService.swift  
**Issue**: Code checks for excessive emojis but only on moderation scoring, not layout:
```swift
let emojiCount = text.unicodeScalars.filter { $0.properties.isEmoji }.count
if Double(emojiCount) / Double(max(text.count, 1)) > 0.3 { /* flag as risky */ }
```
But no truncation or wrapping safeguard. A post like "🎉🎉🎉🎉..." (1000 emojis) will render and break label size calculations.

**Why it matters**: Post card can overflow or display incorrectly.

**Suggested fix**: Clamp emoji count in rendering layer:
```swift
let displayText = text.count > 500 ? String(text.prefix(500)) + "…" : text
```

**Effort**: S

---

#### 14. Draft persistence across app kills not guaranteed
**File**: BereanChatView.swift (persistLocalCache), CreatePostView.swift (persistDraftIfNeeded)  
**Issue**: Comments in code acknowledge: "Firestore offline persistence does NOT queue creates reliably." Drafts are persisted to Firestore via `persistExchange()`, but if user kills the app mid-write, draft is lost.

**Why it matters**: Users lose their work.

**Suggested fix**:
- Use `@AppStorage` + UserDefaults for local draft backup BEFORE sending to Firestore
- On app reopen, restore from local cache if Firestore write didn't complete

**Effort**: M

---

#### 15. No retry with exponential backoff on network failures
**File**: FirebasePostService.swift, BereanChatView.swift  
**Issue**: Network calls fail immediately with no retry. If POST to create a comment fails due to transient network hiccup, it's game over.

**Why it matters**: Flaky networks (switching towers, weak signal) cause data loss.

**Suggested fix**: Wrap all Firestore writes in retry logic:
```swift
func retryableWrite(_ work: @escaping () async throws -> Void) async throws {
    var attempt = 0
    while attempt < 3 {
        do {
            try await work()
            return
        } catch {
            attempt += 1
            let delay = pow(2.0, Double(attempt)) // 2s, 4s, 8s
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
```

**Effort**: M

---

#### 16. Live Activity expiration not handled
**File**: LiveActivityBridge.swift  
**Issue**: Code requests Live Activities but there's no explicit handler for when they expire (30-min default TTL). If user is looking at the Dynamic Island and it expires mid-stream, there's no fallback UI.

**Why it matters**: Dynamic Island goes blank without explanation.

**Suggested fix**: Detect expiration via `ActivityKit.Activity<T>.activities.isEmpty` and show a toast: "Activity ended."

**Effort**: S

---

#### 17. No skeleton/placeholder on slow feeds
**File**: OpenTableView.swift, BereanChatView.swift  
**Issue**: When feed is loading, content area is blank/white. No skeleton loaders or placeholder shimmer.

**Why it matters**: Perceived latency feels longer than it is. Users think the app is broken.

**Suggested fix**: Show placeholder cards with gray shimmer during fetch.

**Effort**: M

---

### LOW (backlog)

#### 18. No RTL (right-to-left) text support
**File**: BereanChatView.swift, PostCard.swift  
**Issue**: Text is not marked with `.lineLimit(nil)` and no explicit RTL handling. A post in Arabic or Hebrew may render incorrectly.

**Why it matters**: Low priority unless app is localizing to Middle East, but worth noting for future.

**Suggested fix**: Add `.flipsForRightToLeftLayoutDirection()` to text containers, test with Arabic locale.

**Effort**: M (if shipping to RTL markets)

---

#### 19. No zero-width joiner (ZWJ) emoji validation
**File**: ThinkFirstGuardrailsService.swift  
**Issue**: Emoji check counts raw scalars. Complex emoji sequences like "👨‍👩‍👧‍👦" (family emoji with ZWJs) may not render correctly if truncated mid-sequence.

**Why it matters**: Edge case, but could cause layout jank or crashes.

**Suggested fix**: Use `String.UnicodeScalarView` to safely truncate on grapheme cluster boundaries (not scalar boundaries).

**Effort**: L

---

#### 20. @testable imports missing in production code
**File**: Searched all .swift files  
**Result**: None found. **No issues here.** Code does not accidentally import test utilities.

**Effort**: N/A

---

## What I did NOT check

1. **SwiftUI previews correctness** — #Preview macros exist but I didn't validate they render. (Would need xcodebuild)
2. **Actual network timeouts in prod** — Code inspection only; live network testing required
3. **Actual merge conflict markers in pbxproj** — The project file is in a separate derived dir; only scanned swift files
4. **Push notification code paths (both in-app + background)** — PushNotificationHandler.swift not fully read
5. **Account linking / multiple identity providers** — Only checked Firebase phone/email, not Google/Apple Sign-In edge cases
6. **Actual locale switching behavior** — Formatter configuration looks OK but runtime locale switch not tested
7. **Memory leaks from singletons** — `@MainActor` singletons look safe but static analyzer would catch actual leaks
8. **Dependency cycle detection** — No SPM/CocoaPods audit; too large to scan
9. **Analytics event typos or missing events** — Thousands of `Analytics.logEvent` calls not audited
10. **First-launch dark mode defaults** — Not scanned appearance/UIAppearance configuration

---

## Summary

**Critical path vulnerabilities** (Berean offline, Stripe idempotency, singleton state leak) should ship soon. **High UX issues** (no empty states, no timeouts, raw errors) are visible to every user and degrade the app on poor networks. **Medium polish items** (retries, drafts, locale) improve robustness. **Low items** are edge cases or future-proofing.

**Estimated remediation effort**: 8–12 engineering days across all severities.
