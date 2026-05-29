# Screens & UI States Audit
**Date:** 2026-05-28  
**Branch:** audit/2026-05-28  
**Auditor:** Claude Sonnet 4.6 (automated static analysis)

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| `SignInView.swift:2259` | Blocker | Force-unwrap / Crash | `anyWindowScene!` force-unwrapped on the last-resort UIWindow fallback. If the app has no connected window scene (edge-case but possible during background launch), this crashes at sign-in. |
| `Feature05_AccountabilityThread.swift:119` | Blocker | Force-unwrap / Crash | `snap!.documentID` inside a Firestore `addSnapshotListener` callback. The guard on line 117 checks `snap?.data()` but not `snap` itself being non-nil; the force-unwrap is therefore one code-path away from a crash. |
| `Feature09_SharedTestimonyDraft.swift:151` | Blocker | Force-unwrap / Crash | Same pattern as above — `snap!.documentID` after a guard that only protects `snap?.data()`. |
| `BereanAdvancedFeaturesViews.swift:154` | Blocker | Force-unwrap / Crash | `studyPlan!` rendered directly in the view body. The optional is checked via `else { StudyPlanDisplay(plan: studyPlan!) }` with no enclosing `if let`, so a race between the async fetch and the view update can hit nil. |
| `BereanAdvancedFeaturesViews.swift:471` | Blocker | Force-unwrap / Crash | `Text(analysis!)` rendered in the view body without an `if let` guard. If `analysis` is cleared asynchronously while the view is rendering, this crashes. |
| `CommentRateLimiter.swift:155,163,173` | Blocker | Force-unwrap / Crash | `inLastMinute.min(...)!`, `inLastHour.min(...)!`, `inPostWindow.min(...)!` — all three are forced on the result of `min()`. The arrays are checked with `.count >= limit` (not `.isEmpty`) before each call, but a concurrent mutation could still produce an empty array; the safer pattern is `guard let oldest = …min(…) else { return }`. |
| `AmenPulseAwarenessSystem.swift:78` | Blocker | Force-unwrap / Crash | `currentSuggestion!.priority` after `currentSuggestion == nil` check — the short-circuit `guard` idiom is inverted (`|| currentSuggestion!.priority`). Correct at runtime today, but fragile; should use `if let`. |
| `WitnessCameraView.swift:319` | Blocker | Force-unwrap / `as!` Crash | `layer as! AVCaptureVideoPreviewLayer` in a `UIView` subclass. Safe only if `layerClass` override is always called. If the subclass is ever instantiated without the override (e.g., deserialized from a nib/storyboard not in this project), it will `EXC_BAD_ACCESS`. |
| `LiquidGlassMessagesView.swift:244-256` | Blocker | Retain Cycle / Leak | `NotificationCenter.default.addObserver(forName:…)` closures at lines 244 and 252 capture `self` (via `keyboardHeight`) without `[weak self]`. These closures are never removed — `removeObserver` is not called in `onDisappear` or `deinit`. This leaks the view and fires callbacks after the view is gone. |
| `AntiHarassmentEngine.swift:213` | High | Force-unwrap | `AppealStatus(rawValue: appealStatusRaw!)` — checked with `!= nil` but forced unwrap is redundant and fragile. Use `if let`. |
| `TestimoniesView.swift:772` | High | Force-unwrap in View Body | `"\(count!) …"` inside a Text label. The `count != nil` ternary guard is correct but the force-unwrap style is dangerous; a SwiftUI re-render that fires between the nil check and the force-unwrap can crash. Use `if let c = count`. |
| `ConnectConverseView.swift` (loadTopics) | High | Missing Error State | `loadTopics()` silently logs errors to `dlog` and sets `isLoading = false`. If Firestore fails (offline, permissions), the screen shows the empty-state "No conversations yet" — indistinguishable from a genuinely empty collection. No error banner or retry button is shown. |
| `PostSchedulingSystem.swift:374,394,424,558,584,657,765,995,1345,1396` | High | Dark Mode | Multiple toolbar titles and sheet labels use `.foregroundColor(.black)` — invisible in Dark Mode against a dark navigation bar background. Should use `.primary` or a semantic color. |
| `WellnessRiskLayer.swift:742,771,823,872,913,970,1065,1107,1222,1270` | High | Dark Mode | Extensive use of `.foregroundColor(.black)` for body text throughout the Wellness Risk sheet. Unreadable in Dark Mode. |
| `SpatialHomeView.swift:215-228` | High | Dark Mode | Community-member placeholder list uses `.foregroundColor(.black)` and `.foregroundColor(.black.opacity(0.6))` without dark mode adaptation. |
| `AMENAccountTypeOnboardingView.swift:236,310,425,558` | High | Dark Mode | Onboarding body text uses `.foregroundColor(.black)`. First-run experience is broken in Dark Mode. |
| `ChurchEditProfileView.swift:131,225,299,332,345,426,445,518` | High | Dark Mode | Multiple form field labels in church profile editing use `.foregroundColor(.black)`. |
| `TestimonyViralSheet.swift:191` | High | Dark Mode | `.foregroundColor(.black)` on text inside a sheet with dynamic background. |
| `ProfileView.swift:6451` | Med | Dark Mode | Isolated `.foregroundColor(.black)` in the main profile view. |
| `UserProfileView.swift:67` | Med | Dark Mode | `PostType.openTable.color` returns `Color.black` (a hardcoded token). Badge rendered over a photo will be invisible in certain themes. Use a semantic token. |
| `BereanChatView.swift:1286,1440,1502,1504,1507,1510,1540,1542,1597` | Med | Dynamic Type | Chat bubble labels use `.font(.system(size: 13/12/11/10/9, weight: …))` instead of scaled fonts. Small text at accessibility font sizes will not grow. |
| `AmenSyncStudioView.swift` (multiple) | Med | Dynamic Type | Studio view uses `.font(.system(size: 9/10/12/14/…))` raw sizes throughout with no `.dynamicTypeSize` constraint or `.minimumScaleFactor`. Small badge and status labels will clip at larger accessibility sizes. |
| `SuggestedAccountPeekSheet.swift:67-297` | Med | Dynamic Type | Entire peek sheet uses raw `.font(.system(size: …))` (11–18pt) without scaling. |
| `ResourcesView.swift:336` | Med | Spinner Without Timeout | `ProgressView()` in the "playing" content slot has no timeout or error recovery path visible in the surrounding code. If the media URL fails to load, the spinner persists indefinitely. |
| `TopicFeedView.swift:128,138` | Med | Spinner Without Timeout | Two `ProgressView()` spinners without error recovery shown in the topic feed loading path. |
| `DiscipleshipJourneyView.swift:29` | Med | Spinner Without Timeout | Single `ProgressView()` with no `isLoading` timeout guard shown here. |
| `ConnectConverseView.swift:46` | Med | Missing Error State | `ProgressView().padding(.top, 40)` is the sole loading state; transitions directly to an empty state on error (see above). |
| `ScriptureIntentDetector.swift:207` | Med | Force-unwrap | `bestMatch!.score` in a loop — safe in the current logic flow but relies on the `score > 0` guard that runs one call site earlier; easy to introduce a regression. Use `if let`. |
| `OpenTableView.swift` | Med | Offline Behavior | `showOfflineBanner` is only shown when `allPosts.isEmpty`. A user who loaded posts while online, then went offline, will see stale posts with no visual indicator that the feed is stale. |
| `NotificationsView.swift` | Low | Missing Error Recovery | `handleOnAppear` and `refreshNotifications` do not expose an error state to the user. If the Firestore listener fails to attach, the screen silently stays at the `skeletonRows` state or `emptyStateView`. |
| `ProfileView.swift:638-838` | Low | Retain Cycle Risk | Five `NotificationCenter.addObserver` registrations store results in `@State` vars and remove them `onDisappear`. If a navigation pop and fast re-push occur before `onDisappear`, the old observers may not be cleaned up before new ones are registered, resulting in duplicate callbacks. |
| `UserProfileView.swift:861-901` | Low | Retain Cycle Risk | `newPostObserver` and `repostObserver` closures capture `self` strongly (via `self.posts`, `self.reposts`, etc.) without `[weak self]`. If the profile view is dismissed while an in-flight notification fires, self is kept alive. |
| `ResourcesView.swift:1286-1317` | Low | NotificationCenter Leak (guarded) | Pattern is safe here (guard against duplicate registration + cleanup in `removeKeyboardObservers`), but referenced for completeness; verify `removeKeyboardObservers` is always called in `onDisappear`. |
| `AboutAmenView.swift:175,196,217` | Low | Force-unwrap | `URL(string: "https://…")!` force-unwrapped for known-good static strings. Low risk but should use `URL(string:)!` only with literal compile-time values; acceptable as is. |
| `VictimShieldControlsView.swift:176` | Low | Force-unwrap | `URL(string: url)!` where `url` is a runtime variable, not a static literal — if the string is malformed (e.g., from Firestore), this crashes. |
| `JobDetailView.swift:453` | Low | Force-unwrap | `URL(string: url) ?? URL(string: "https://amen.app")!` — the fallback force-unwrap is fine (static string) but the pattern is fragile; document intent. |
| `BereanChatView.swift (view body)` | Low | Dark Mode | Several `Color.white.opacity(…)` background overlays applied to message bubble containers will look washed out in Dark Mode because the Liquid Glass system already applies `.ultraThinMaterial`; double-layering white opacity on a dark material yields a grey tint instead of white glass. |
| `PostSchedulingSystem.swift:702,722` | Low | Dynamic Type | Fixed-height `frame(height: 52)` and `frame(height: 48)` on CTA buttons will clip multiline button labels at xxLarge accessibility font. |

---

## Not Fully Wired

### ConnectConverseView — Missing Error State
`loadTopics()` catches errors and logs them but leaves the UI in the empty-state view (`topics.isEmpty && !isLoading`). The user has no indication that the load failed and no retry affordance. Required states:
- Loading — present (ProgressView)
- Empty — present (empty state copy)
- **Error — absent**
- Timeout — absent

### TopicFeedView — No Error / Timeout State
Two `ProgressView()` spinners (lines 128, 138) without associated error display. If the async data load fails or returns slowly, the screen is stuck in a spinner. No timeout guard visible.

### DiscipleshipJourneyView — No Error State
Single `ProgressView()` with no fallback path visible in the file.

### ResourcesView "Now Playing" Slot — No Timeout
`ProgressView()` at line 336 for media loading. The `AMENResourcesHubView` wraps this behind a flag but the inner view does not guard against indefinite spinner if the media URL is unreachable.

### OpenTableView — Stale Feed Indicator
Feed correctly shows an offline banner when posts list is empty and the network is down. However, if the user already has posts in memory and then goes offline, the feed renders stale posts with no visual staleness indicator (e.g., "last updated 10 min ago"). Partially mitigated by pull-to-refresh but inconsistent with AMEN's "fast, premium UX" standard.

### NotificationsView — Silent Firestore Failure
If `NotificationService.shared` fails to attach its Firestore listener (e.g., rules error, offline with no cache), `isLoading` never becomes `false` — the skeleton rows show indefinitely. There is no timeout that transitions to `emptyStateView` with a "Couldn't load — tap to retry" message.

---

## Fix Recommendations

### P0 — Fix immediately (crash risk)

1. **`Feature05_AccountabilityThread.swift:119` and `Feature09_SharedTestimonyDraft.swift:151`**  
   Change the guard to `guard let self, let snap, let d = snap.data() else { return }` and then use `snap.documentID` (non-optional after the guard).

2. **`BereanAdvancedFeaturesViews.swift:154,471`**  
   Wrap both in `if let studyPlan` / `if let analysis` rather than relying on the outer `else` branch not allowing nil through.

3. **`CommentRateLimiter.swift:155,163,173`**  
   Use `guard let oldest = <array>.min(by:) else { return .success }` to avoid the force-unwrap. The guard is cheap and eliminates the crash path under concurrent mutation.

4. **`LiquidGlassMessagesView.swift:244-256`**  
   Refactor `setupKeyboardObservers()` to the same pattern already used in `ResourcesView` — store tokens in `@State` variables and call `removeObserver` in `onDisappear`. Add `[weak self]` captures inside the closures.

5. **`SignInView.swift:2259`**  
   Replace `UIWindow(windowScene: anyWindowScene!)` with a nil-coalescing fallback: `guard let scene = anyWindowScene else { return UIWindow() }`.

### P1 — Fix before next TestFlight (dark mode / broken flows)

6. **`PostSchedulingSystem.swift`, `WellnessRiskLayer.swift`, `AMENAccountTypeOnboardingView.swift`, `ChurchEditProfileView.swift`, `SpatialHomeView.swift`**  
   Replace all `.foregroundColor(.black)` on text elements with `.foregroundColor(.primary)` (or the AMEN semantic token `ProfileDesignTokens.textPrimary`). Run a global search for `\.foregroundColor(\.black)` and audit each call site.

7. **`ConnectConverseView.swift`**  
   Add `@State private var loadError: Error? = nil` and show an `InlineErrorBanner` when `loadError != nil`, with a retry button that calls `Task { await loadTopics() }`.

8. **`TestimonyViralSheet.swift:191`**  
   Replace `.foregroundColor(.black)` with `.foregroundColor(.primary)`.

### P2 — Polish / consistency

9. **Dynamic Type in `BereanChatView`, `AmenSyncStudioView`, `SuggestedAccountPeekSheet`**  
   Replace raw `Font.system(size: N)` with `AMENFont.*` scale calls (which already honor Dynamic Type via `UIFontMetrics`) or add `.dynamicTypeSize(…<.accessibility1)` caps with `.minimumScaleFactor(0.8)` so labels compress gracefully rather than clipping.

10. **`OpenTableView` stale-feed indicator**  
    Add a subtle "Updated X min ago" timestamp line below the `#OPENTABLE` header when `networkMonitor.isConnected == false` and `!postsManager.openTablePosts.isEmpty`. This costs one line and aligns with the product standard.

11. **`NotificationsView` silent failure**  
    Add a 5-second timeout in `handleOnAppear`: if `notificationService.isLoading` is still true after 5 s, set a `@State var loadFailed = true` flag and show a retry banner in `contentView` above `skeletonRows`.

12. **`VictimShieldControlsView.swift:176`**  
    Replace `URL(string: url)!` with `if let destination = URL(string: url) { Link(…, destination: destination) }` to avoid crash on malformed URL from Firestore.

13. **`PostSchedulingSystem.swift:702,722` fixed-height buttons**  
    Change `frame(height: 52)` / `frame(height: 48)` to `frame(minHeight: 52)` / `frame(minHeight: 48)` so text can overflow vertically at accessibility font sizes.

---

## Stress Test Script

1. **Force unwraps** — Enable Firestore offline emulator → navigate to Accountability Thread → verify no crash on snapshot with nil `data()`.
2. **Dark Mode** — In iOS Simulator, toggle Dark Mode from Control Center → open Post Scheduling, Wellness Risk Layer, Church Edit Profile, Onboarding → verify all body text is visible.
3. **ConnectConverseView error state** — Block Firestore traffic (airplane mode + clear cache) → open Conversations tab → verify error banner appears with retry, not silent empty state.
4. **Dynamic Type** — In Settings > Accessibility > Display & Text Size, set font to "Accessibility Extra Extra Extra Large" → open Berean Chat and Studio → verify no clipped labels.
5. **LiquidGlassMessagesView keyboard leak** — Navigate to Messages chat → open keyboard → kill app in background → relaunch → confirm no duplicate keyboard observers by checking Xcode memory graph for retained view instances.
6. **Stale feed offline** — Load OpenTable feed on Wi-Fi, switch to airplane mode, scroll → confirm "You're offline" banner appears when feed is empty; check that stale-but-visible posts don't silently mislead.
7. **Notifications spinner** — Revoke Firestore read permission in Firebase console for `/notifications` → open Notifications tab → confirm timeout and retry banner appear within 5 s.

---

## Acceptance Criteria Checklist

- [ ] Zero force-unwraps inside Firestore snapshot callbacks
- [ ] Zero force-unwraps in SwiftUI view body computed properties (unless value is provably non-nil by construction)
- [ ] All screens with async data show: (1) loading skeleton, (2) empty state, (3) error + retry state
- [ ] No `.foregroundColor(.black)` or `.foregroundColor(.white)` on text that must adapt to Dark Mode
- [ ] All navigation-level body text uses `AMENFont.*` or `.systemScaled` (which respects Dynamic Type) rather than raw `.system(size:)`
- [ ] Fixed-height row containers use `minHeight:` not `height:` to allow Dynamic Type expansion
- [ ] `LiquidGlassMessagesView` keyboard observers removed in `onDisappear` with `[weak self]` captures
- [ ] `UserProfileView` and `ProfileView` NotificationCenter closures use `[weak self]`
- [ ] `VictimShieldControlsView` URL construction guarded against nil
- [ ] OpenTable shows visual freshness indicator when offline with cached posts
- [ ] Notifications view has a 5-second timeout fallback to error + retry
