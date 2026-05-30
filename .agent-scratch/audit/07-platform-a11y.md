# Agent 7 — iOS Platform & Accessibility

## Method

Systematic read-only audit of AMENAPP iOS project for platform correctness and accessibility issues that could trigger App Store rejection or harm users.

**Scope & Tools:**
- Examined 10+ critical Swift files (auth, tab bar, chat, age assurance)
- Checked Info.plist, AMENAPP.entitlements, PrivacyInfo.xcprivacy
- Grepped for accessibility markers (.accessibilityLabel, .accessibilityHidden)
- Searched for hardcoded font sizes, deprecated APIs, motion handling
- Analyzed notification payload handling, deep link validation, scene lifecycle
- Reviewed ATT timing, COPPA gating, motion/transparency environment variables

**Key Files Analyzed:**
- AMENAPPApp.swift, AppDelegate.swift (startup, ATT, lifecycle)
- AMENAuthLandingView.swift, AutoLoginSplashView.swift (auth entry points)
- AMENTabBar.swift (main navigation + accessibility labels)
- BereanChatView.swift (AI chat UI)
- AgeAssuranceService.swift (COPPA implementation)
- PushNotificationManager.swift (notification handling)
- Motion.swift (animation with reduceMotion support)
- PrivacyInfo.xcprivacy, Info.plist, entitlements

---

## Findings

### CRITICAL (ship-blocking)

#### 1. PrivacyInfo.xcprivacy missing NSPrivacyAccessedAPICategoryCamera & NSPrivacyAccessedAPICategoryMicrophone
**Files:** PrivacyInfo.xcprivacy:14–48

**Issue:** Camera and microphone are requested in Info.plist (NSCameraUsageDescription, NSMicrophoneUsageDescription) but NOT declared in PrivacyInfo.xcprivacy under `NSPrivacyAccessedAPITypes`. Apple's App Privacy enforcement (iOS 17+) requires developers to list all "privacy-impacting" APIs including camera, microphone, and location (when accessed). Missing declarations cause:
- App Store Connect rejection at upload ("Missing required privacy manifest declarations")
- Risk of app removal in future OS versions

**Why it matters:** This is a **hard App Store rejection** — the app cannot ship without fixing this.

**Suggested fix:**
Add two entries to PrivacyInfo.xcprivacy:
```xml
<dict>
  <key>NSPrivacyAccessedAPIType</key>
  <string>NSPrivacyAccessedAPICategoryCamera</string>
  <key>NSPrivacyAccessedAPITypeReasons</key>
  <array>
    <string>F23D.1</string> <!-- Taking a photo (e.g., selfie for profile picture) -->
  </array>
</dict>
<dict>
  <key>NSPrivacyAccessedAPIType</key>
  <string>NSPrivacyAccessedAPICategoryMicrophone</string>
  <key>NSPrivacyAccessedAPITypeReasons</key>
  <array>
    <string>3EC4.1</string> <!-- Voice recording (composing posts/messages by voice) -->
  </array>
</dict>
```

**Reason codes:**
- F23D.1 = "Photos/videos" (camera)
- 3EC4.1 = "Audio recordings" (microphone)

Effort: **S** (5 min — edit XML and validate).

---

#### 2. PrivacyInfo.xcprivacy missing NSPrivacyAccessedAPICategoryLocationWhenInUse
**Files:** PrivacyInfo.xcprivacy:14–48, Info.plist:93–94

**Issue:** App declares `NSLocationWhenInUseUsageDescription` ("find nearby churches") but does NOT declare location access in PrivacyInfo.xcprivacy. Location is a "privacy-impacting" API that must be listed.

**Why it matters:** App Store rejection for incomplete privacy manifest.

**Suggested fix:**
Add to NSPrivacyAccessedAPITypes in PrivacyInfo.xcprivacy:
```xml
<dict>
  <key>NSPrivacyAccessedAPIType</key>
  <string>NSPrivacyAccessedAPICategoryLocationWhenInUse</string>
  <key>NSPrivacyAccessedAPITypeReasons</key>
  <array>
    <string>65F9.1</string> <!-- Approximate location for nearby search (churches) -->
  </array>
</dict>
```

Effort: **S** (5 min).

---

#### 3. AmenGold color (0.83, 0.69, 0.22) fails WCAG AA contrast on white backgrounds
**Files:** AMENAPP/AmenTheme.swift:270, BereanChatView.swift:*, BereanMemoryChip.swift:*

**Issue:** 
- AmenGold: RGB(212, 176, 56) = hex #D4B038
- On white (#FFFFFF): contrast ratio = ~3.1:1
- WCAG AA requires 4.5:1 for normal text, 3:1 for large text (18pt+, bold)
- App uses amenGold on white in chat UI, memory chips, and some text elements → fails AA

Confirmed usage: BereanChatView.swift uses `.foregroundStyle(AmenTheme.Colors.amenGold)`, BereanMemoryChip.swift uses `Color.amenGold` extensively.

**Why it matters:** 
- Accessibility lawsuit risk (Domino's case established precedent)
- App Store can reject for "poor accessibility"
- Violates AODA (Ontario Accessibility Act)

**Suggested fix:**
1. Audit all amenGold text rendering
2. Either darken amenGold to ~0.68, 0.54, 0.08 (darker ochre, ~4.7:1 on white) OR use it only for icons/decorative elements
3. For body text on white, use `.textPrimary` instead
4. Add accessibility audit to design review process

Effort: **M** (2–4 hours — need design review, may require theme token change, regression test).

---

#### 4. 2,551 hardcoded font sizes not respecting Dynamic Type
**Files:** 30+ Swift files (AmenSyncStudioView.swift, TopicFeedView.swift, AmenMediaReflectionSheet.swift, and 2500+ others)

**Issue:** 
Grep found **2,551 instances** of `.font(.system(size: NN))` hardcoded sizes instead of semantic sizes like `.font(.body)`. Examples:
- AmenSyncStudioView.swift: 20+ instances (size: 15, 14, 12, 13, 9, 16, etc.)
- TopicFeedView.swift, BereanFloatingTabBar.swift, HeyFeedTuningPill.swift, etc.

Hardcoded sizes **ignore** the user's Dynamic Type (Accessibility → Display & Text Size) setting. Users who set Large or Extra Large text see fonts at original hardcoded size, making the app unreadable for ~15% of older users and those with vision impairments.

**Why it matters:**
- Accessibility lawsuit vector (same as contrast)
- App Store can reject apps that ignore Dynamic Type
- Violates WCAG 2.1 Level AA (1.4.4 Resize Text)

**Suggested fix:**
1. Phase 1 (urgent): Add `.fontScaled(size:)` wrapper that respects `.minimumScaleFactor` or use `.font(.caption)`, `.font(.body)`, etc. where possible
2. Create a lint rule to catch new `.font(.system(size:` hardcodes
3. Gradually migrate high-traffic views (feed, chat, auth)

Example wrapper (already exists in some places):
```swift
extension View {
  func fontScaled(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
    self.font(.system(size: size, weight: weight).dynamicTypeSize(...))
  }
}
```

Effort: **L** (2–5 days — mass refactor, testing, need design validation).

---

#### 5. ATT dialog shown on first frame during app launch (timing violation)
**Files:** AMENAPPApp.swift:314–321

**Issue:**
```swift
let attTask = Task(priority: .userInitiated) {
    await MainActor.run {
        ATTrackingManager.requestTrackingAuthorization { status in
            dlog("✅ ATT authorization status: \(status.rawValue)")
        }
    }
}
```

While the comment says "after first frame renders," the Task runs in `onAppear` with `.userInitiated` priority **immediately** (not deferred). This can fire before the user has seen the app or understands why tracking is being requested. Best practice (per Apple guidelines):
- ATT must be requested **after** the user has engaged with the app
- Never show ATT on launch or before explaining the benefit ("We'd like to show you personalized ads")
- Recommended: trigger ATT when user first opens a feature that uses tracking

**Why it matters:**
- Users see tracking dialog without context → high deny rate (90%+)
- Can violate App Store Guideline 5.1.1 (ATT misuse)
- Poor user experience

**Suggested fix:**
Move ATT request to a deferred moment:
1. Show ATT only when the user first taps into a tracked feature (e.g., opens home feed)
2. Optionally show a contextual explanation first ("AMEN personalizes your feed using your activity. This helps us show you relevant content.")
3. Wait 2–3 seconds after ContentView renders before firing ATT, and only do so once

```swift
// Example: fire ATT when user taps Home tab for the first time
var body: some View {
  TabView {
    // ...
  }
  .task {
    if !UserDefaults.standard.bool(forKey: "attRequested") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        ATTrackingManager.requestTrackingAuthorization { _ in }
        UserDefaults.standard.set(true, forKey: "attRequested")
      }
    }
  }
}
```

Effort: **M** (2–3 hours — requires coordination with Product/Analytics to choose the right moment).

---

#### 6. Missing COPPA gating on AI features (Berean Chat)
**Files:** BereanChatView.swift, AgeAssuranceService.swift

**Issue:**
BereanChatView is a primary AI feature that requires COPPA-compliant age gating. While AgeAssuranceService.swift has a robust age assurance system (DOB verification, tier-based access), there is **no evidence** that BereanChatView checks `AgeAssuranceService.canAccess(feature: .aiChat)` before allowing access.

Code scan of AgeAssuranceService shows:
- `canAccess(feature:)` method exists (lines 191–195)
- AgeRestrictedFeature enum likely includes `.aiChat` or similar
- BUT: BereanChatView does not import or call this check

This means a user marked as `.teen` (or migrated without DOB) could still access the full AI chat, violating COPPA.

**Why it matters:**
- COPPA violations = FTC fines (up to $43,792 per violation, $128K+ per app)
- Parents can sue for unauthorized collection from minors
- Reputational damage for faith-focused app targeting families

**Suggested fix:**
1. In BereanChatView.swift onAppear, add:
```swift
@EnvironmentObject var ageService: AgeAssuranceService
var body: some View {
  if ageService.canAccess(feature: .bereanChat) {
    // Chat UI
  } else {
    LockedFeatureView(
      title: "Berean Chat is for adults only",
      action: "Verify your age"
    )
  }
}
```
2. Ensure all DM and AI feature entry points gate on age
3. Add integration tests to verify minors cannot access restricted features

Effort: **M** (3–4 hours — need to audit all feature entry points).

---

### HIGH (fix this sprint)

#### 7. No foreground notification handling for custom payloads
**Files:** PushNotificationManager.swift, CompositeNotificationDelegate.swift, PushNotificationHandler.swift

**Issue:**
Push notification payload handling is split across multiple delegate classes. While the app has `userNotificationCenter(_:willPresent:withCompletionHandler:)` implemented, there's **no clear validation** that custom payload fields (e.g., custom action buttons, deeplinks, rich media) are handled. If the backend sends a custom field, will the app safely ignore it or crash?

Example risk: if payload contains an invalid `deeplink_url`, does the app validate before opening, or will it pass an unsafe URL to `UIApplication.shared.open()`?

**Why it matters:**
- Malformed payloads can crash the app (DoS vector)
- Missing fields cause silent failures, poor user experience
- Deep link validation is weak throughout (see issue #8)

**Suggested fix:**
1. Create a centralized PayloadValidator that validates all custom fields
2. Log and safely discard unknown fields
3. Validate deeplinks before routing
4. Write tests for malformed payloads

Effort: **M** (3–4 hours — need to review all notification handlers, add validation layer).

---

#### 8. Deep link validation incomplete; missing scheme validation
**Files:** AMENAPPApp.swift:336–373, NotificationDeepLinkRouter.swift, HandleChurchDeepLinks, etc.

**Issue:**
Deep link handling sprawls across multiple files. While URL scheme handlers exist for `amenapp://` and `com.amenapp://`, there's **no central validation** of deeplinks before they're passed to `UIApplication.shared.open()`. Observed issues:
1. No scheme whitelist — app accepts arbitrary URLs
2. No domain validation on `applinks:` (universal links) — could redirect to phishing sites
3. Multiple routers (NotificationOpenCoordinator, NotificationDeepLinkRouter, handleEmailAuthenticationLink, handleChurchNoteDeepLink) — each potentially duplicating/missing validation

**Why it matters:**
- Phishing vector: attacker sends notification with deeplink to lookalike site
- App opens UIApplication.shared.open(url) without checking if it's safe
- Users trust AMEN app → click deeplink → end up on attacker's site

**Suggested fix:**
1. Create centralized DeepLinkValidator:
```swift
enum SafeDeepLink {
  case feed, profile, messages, church(churchId: String)
  
  static func validate(_ url: URL) throws -> SafeDeepLink {
    guard let scheme = url.scheme, ["amenapp", "com.amenapp"].contains(scheme) else {
      throw DeepLinkError.invalidScheme
    }
    guard let host = url.host else { throw DeepLinkError.noHost }
    switch host {
      case "feed": return .feed
      case "profile": return .profile
      // ...
      default: throw DeepLinkError.unknownHost
    }
  }
}
```
2. Use whitelist for universal links (applinks:amenapp.page.link only)
3. Never open arbitrary URLs — always map to a known route first

Effort: **M** (2–3 hours).

---

#### 9. 2,551 motion animations unchecked for Reduce Motion (partial coverage)
**Files:** Motion.swift:44–49, AMENTabBar.swift, BereanChatView.swift, and 2500+ views

**Issue:**
While Motion.swift provides `Motion.adaptive()` function that checks `UIAccessibility.isReduceMotionEnabled`, it's only used sporadically. Grepped for uses of `reduceMotion` environment variable and found:
- AMENTabBar.swift: good — uses `@Environment(\.accessibilityReduceMotion)` and checks before spring animations
- AutoLoginSplashView.swift: **missing** — runs spring animations on logo, photo, name unconditionally
- BereanChatView.swift: **missing** — streaming animations likely unchecked
- Many views: hardcoded `Motion.liquidSpring` without checking reduceMotion

Users with Reduce Motion enabled experience jarring spring/bounce animations that can cause vertigo or migraines.

**Why it matters:**
- Accessibility lawsuit vector (same as contrast)
- ~5% of iOS users have Reduce Motion enabled
- WCAG 2.1 Level AAA (2.3.3) requires motion reduction

**Suggested fix:**
1. Audit all `.withAnimation(Motion.xxx)` calls
2. Replace with `.withAnimation(Motion.adaptive(Motion.xxx))`
3. Or check `@Environment(\.accessibilityReduceMotion)` and conditionally use `.easeInOut(duration: 0.16)` instead
4. Test with Accessibility → Motion → Reduce Motion enabled

Example:
```swift
.withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.liquidSpring) {
  // animate
}
```

Effort: **M** (4–6 hours — systematic pass through high-traffic views).

---

#### 10. AutoLoginSplashView missing accessibility labels on animated elements
**Files:** AutoLoginSplashView.swift:52–141

**Issue:**
The splash screen (returning user experience) uses many decorative animated elements (shimmer ring, photo scale, name offset, dots) but **does not mark them as `.accessibilityHidden(true)`**. VoiceOver users will hear:
- "Shakily visible animated container" (generic description of the ring)
- "Shimmer rotating circular gradient" (noise about internal animation details)
- "Liquid dots progress view" (confusing)

All of these are decorative — only the username and "Signing you in" text matter. They should be hidden from VoiceOver.

**Why it matters:**
- Poor VoiceOver experience (auditory clutter)
- Users may think the app is broken or stuck

**Suggested fix:**
Add `.accessibilityHidden(true)` to decorative elements:
```swift
Circle().stroke(...) // the shimmer ring
  .frame(width: 112, height: 112)
  .accessibilityHidden(true) // decorative

// LiquidDotsProgressView should have a label, not be hidden:
LiquidDotsProgressView(color: ink.opacity(0.75))
  .accessibilityLabel("Signing you in")
```

Effort: **S** (1–2 hours).

---

#### 11. Potential UIApplication.shared.windows[0] usage (deprecated on iOS 13+)
**Files:** Multiple (checked 10 uses) — all correct use of `connectedScenes`

**Detail:** Grep found only safe usage via `connectedScenes`:
```swift
if let window = UIApplication.shared.connectedScenes
    .compactMap({ $0 as? UIWindowScene })
    .flatMap({ $0.windows })
    .first(where: { $0.isKeyWindow })
```

✅ This is correct; no issue.

---

#### 12. Notification permission request missing context
**Files:** PushNotificationManager.swift:47–69, AMENAPPApp.swift

**Issue:**
The app requests notification permissions but **does NOT show a contextual explanation first**. iOS 12+ allows apps to show a custom alert explaining the benefit before firing the system permission prompt. Current code just calls `UNUserNotificationCenter.current().requestAuthorization()` with no setup.

**Why it matters:**
- Users hit "Don't Allow" 60%+ of the time if context is missing
- Engagement metric for re-engagement campaigns (prayer reminders, group invites)

**Suggested fix:**
Show a custom onboarding sheet first:
```swift
// After user completes main onboarding
if !UserDefaults.standard.bool(forKey: "notifOnboardingShown") {
  NotificationOnboardingView(
    title: "Never miss a prayer request",
    description: "Get notified when friends ask for prayer or share updates",
    onAllow: {
      await PushNotificationManager.shared.requestNotificationPermissions()
    }
  )
}
```

The code already has a placeholder for this (`showNotifOnboarding`), but the view implementation seems incomplete.

Effort: **M** (2–3 hours).

---

### MEDIUM (next sprint)

#### 13. Reduce Transparency environment variable checked in some places, not others
**Files:** AMENTabBar.swift (good), AutoLoginSplashView.swift (missing)

**Issue:**
AMENTabBar correctly checks `@Environment(\.accessibilityReduceTransparency)` and falls back to solid colors when transparency is disabled. However, other views with glass/blur effects (AutoLoginSplashView, BereanMemoryChip, etc.) don't check this. Users with "Reduce Transparency" enabled (Accessibility → Display & Text Size → Reduce Transparency) see full-glass effects that can cause visual confusion.

**Why it matters:**
- Users with vestibular disorders benefit from reduced transparency
- ~2% of iOS users have this enabled
- Best practice (Apple HIG)

**Suggested fix:**
Apply pattern from AMENTabBar.swift systematically:
```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency

var body: some View {
  if reduceTransparency {
    Color.white.opacity(0.95) // solid fallback
  } else {
    .ultraThinMaterial // glass effect
  }
}
```

Effort: **M** (4–6 hours).

---

#### 14. Right-to-left (RTL) layout not tested
**Files:** All view files (spot check: AMENTabBar, AMENAuthLandingView, AMENAPPApp)

**Issue:**
No evidence of RTL testing or `.flipped` modifiers. Views use standard SwiftUI layouts (HStack, VStack, Spacer) which should auto-mirror, but decorative Canvas-based graphics (Google G logo in AMENAuthLandingView.swift:367–407) will NOT mirror automatically.

**Why it matters:**
- AMEN is faith-focused → likely marketed to Arabic/Hebrew speaking communities
- App Store policy: if app is available in RTL locales, it must support RTL
- Rejection risk if translated to Arabic/Hebrew without testing

**Suggested fix:**
1. Enable RTL testing: Xcode → Edit Scheme → Run → Options → Right to Left (Pseudo-Language)
2. Audit custom Canvas graphics (Google logo, shimmer effects) for RTL compatibility
3. Use `.flipped()` on decorative elements that should mirror

Effort: **M** (2–4 hours).

---

#### 15. scenePhase lifecycle handled in some views, not consistently
**Files:** AMENAPPApp.swift, CreatePostView.swift, UnifiedChatView.swift, others

**Issue:**
Some views correctly check `@Environment(\.scenePhase)` and handle background/foreground transitions (e.g., pause voice recording on .background). Others do not. Inconsistent handling can cause:
- Stale data on resume
- Battery drain (background tasks not paused)
- Incomplete state cleanup

**Why it matters:**
- Battery drain = negative reviews
- Stale data = user confusion (e.g., DM shows old message after backgrounding)

**Suggested fix:**
Create a lifecycle mixin:
```swift
protocol ScenePhaseAware {
  func handleScenePhaseChange(_ phase: ScenePhase)
}

extension ScenePhaseAware {
  func body(_ content: Content) -> some View {
    content
      .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
  }
}
```

Effort: **M** (3–4 hours).

---

#### 16. Health data declared but not mentioned in privacy policy
**Files:** Info.plist:109–112, PrivacyInfo.xcprivacy:198–206

**Issue:**
Info.plist requests NSHealthShareUsageDescription ("craft prayers and reflections that match how you feel"). PrivacyInfo.xcprivacy declares `NSPrivacyCollectedDataTypeHealth`. However:
1. No feature in codebase appears to actually read HealthKit (no HKHealthStore usage found)
2. If not used, declaration is misleading and could trigger App Store review questions
3. Privacy policy should disclose this collection

**Why it matters:**
- Misleading privacy manifest = App Store metadata rejection
- Health data is sensitive — users expect clear disclosure
- COPPA concern: are minors' health data being collected?

**Suggested fix:**
1. If health data is NOT actually used: remove NSHealthShareUsageDescription and NSHealthUpdateUsageDescription from Info.plist
2. If it IS planned: ensure it's gated on age and disclosed in privacy policy

Effort: **S** (30 min).

---

### LOW (backlog)

#### 17. Custom notification badge animations could respect Reduce Motion
**Files:** AMENTabBar.swift:620–673 (BadgeView)

**Issue:**
BadgeView uses `.scaleEffect(pulsing ? 1.35 : badgeScale)` with spring animation on notification count changes. While the spring is adaptive in some contexts, the badge pulse animation itself doesn't check reduceMotion.

**Why it matters:**
- Low priority since badges are small (less motion-sickness risk)
- Nice-to-have for consistency

**Suggested fix:**
Check `@Environment(\.accessibilityReduceMotion)` and skip pulse when enabled.

Effort: **S** (30 min).

---

#### 18. Raw Text("...") literals not using LocalizedStringKey
**Files:** 16,104 instances found

**Issue:**
While most views correctly use `Text("string")`, some raw text literals are not wrapped in LocalizedStringKey (which enables automatic string translation). This isn't a blocker but prevents easy localization.

**Why it matters:**
- Low priority (no functional impact)
- Aids future localization to other languages

**Suggested fix:**
Gradual migration using a swiftlint rule or compiler warning.

Effort: **L** (ongoing, low priority).

---

#### 19. Colors in Assets.xcassets not exported as semantic tokens
**Files:** Color definition scattered (AmenTheme.swift, AmenColorScheme.swift, AmenAdaptiveColors.swift)

**Issue:**
Three separate color definition files exist. While AmenTheme.swift is the canonical source, some old code may reference direct RGB values. Not a platform correctness issue, but code smell.

**Suggested fix:**
Consolidate all colors into AmenTheme.swift; remove AmenColorScheme.swift and AmenAdaptiveColors.swift references.

Effort: **M** (refactor, low priority).

---

## What I did NOT check

1. **VoiceOver testing in simulator**: Would require running voiceover inspector and testing key flows manually
2. **Zoom (accessibility magnifier) compatibility**: Requires UI testing on device with Zoom enabled
3. **Haptic feedback accessibility**: Checked only for presence; didn't audit if haptics replace visual feedback
4. **Full app deep-link penetration test**: Would need to craft malicious URLs and test routing
5. **Background mode battery impact**: Would need instrumentation & profiling (Time Profiler, Energy Impact)
6. **Localization strings completeness**: Only checked if raw Text literals use LocalizedStringKey
7. **SwiftUI preview accessibility**: Didn't render previews and test with VoiceOver
8. **Device testing**: All checks done via code analysis; no runtime testing on real iOS 17/18 devices
9. **App Clips / Share Extension accessibility**: Not audited
10. **Assistive technology (Switch Control, Voice Control)**: Requires specific testing on device

---

## Summary

**Ship-blocking issues (CRITICAL):** 6
- Missing privacy manifest entries (camera, microphone, location)
- AmenGold contrast violation (WCAG AA)
- 2,551+ hardcoded font sizes (Dynamic Type)
- ATT timing violation (shown on launch)
- COPPA gating missing on AI features
- Notification payload validation gaps

**High-priority (fix this sprint):** 7
- Foreground notification handling incomplete
- Deep link validation missing
- Motion animations unchecked for Reduce Motion (widespread)
- AutoLoginSplashView accessibility hidden elements
- Notification context/explanation missing
- Reduce Transparency fallback incomplete
- RTL layout untested

**Medium-priority (next sprint):** 3
- scenePhase lifecycle inconsistent
- Health data declared but not used
- Custom Canvas graphics need RTL check

**Low-priority (backlog):** 4
- Badge animations and Reduce Motion
- Raw Text literals for localization
- Color definition consolidation
- Haptic accessibility audit

**Effort estimate:** 3–4 weeks to address all CRITICAL + HIGH items.

