# Agent 5 — UX Polish & Accessibility Audit
**Date:** 2026-05-27  
**Branch:** berean/ui-rebuild-liquid-glass-v1  
**Build status after changes:** PASS (0 errors)

---

## Scope

Full-app audit across Feed, Profile, Prayer, Berean AI, Discover, Activity, Church Notes, Prayer Wall, and shared component libraries. Read actual view code for every major screen. ~200+ Swift files reviewed.

---

## Findings

### 1. Empty States

| Screen | Status | Notes |
|---|---|---|
| Feed (EmptyFeedView) | GOOD | Two-variant empty state (new user / following-but-empty) with CTAs |
| Prayer Wall (ModernPrayerWallView) | PARTIAL → FIXED | Loading state existed; category-filtered empty state was missing — `filteredPrayers.isEmpty` fell through to `ForEach(filteredPrayers)` rendering nothing |
| Activity Feed | GOOD | Global empty, community empty, no-church state, and error+retry all present |
| BereanPulse | GOOD | Dedicated `BereanPulseEmptyStateView` and `BereanPulseErrorStateView` |
| Berean Chat | GOOD | `emptyStateCards` array for placeholder suggestions when no sessions |
| Profile posts/replies/saved | GOOD | Each tab has an AMENLoadingIndicator + empty state copy |
| SmartCommunitySearch | GOOD | `SmartCommunitySearchEmptyState` component |
| ChurchNotes Search | GOOD | `ContentUnavailableView` with system illustration |
| Topic Feed | GOOD | `emptyState` private var present |
| Resource Hub | GOOD | `emptyStateView` present |

**Severity of missing filtered empty state (Prayer Wall):** Medium — user sees blank white space when switching to a category with zero prayers, with no explanation.

---

### 2. Loading Skeletons / Indicators

| Screen | Status | Notes |
|---|---|---|
| Feed (HomeFeedViewModel) | GOOD | `AMENLoadingIndicator()` shown while `isLoading` |
| Profile | GOOD | `AMENLoadingIndicator` + "Loading…" text; individual ProgressViews per section |
| Discover | GOOD | `DiscoveryTrendSkeletonCard` (shimmer) for verse and video sections |
| Berean sessions | PARTIAL | `loadRecentSessions()` called in init but no loading spinner surfaced in `BereanHomeView` while sessions resolve — conversations section silently populates |
| Prayer Wall | GOOD | Loading spinner + text while `viewModel.isLoading && viewModel.prayers.isEmpty` |
| BereanPulse | GOOD | `BereanPulseLoadingView` exists |

---

### 3. Error States

| Screen | Status | Notes |
|---|---|---|
| Activity Feed | GOOD | `feedErrorState` with wifi.exclamationmark icon and Retry button |
| ModernPrayerWall | GOOD | `errorMessage` surfaced inline with Retry button |
| Profile | GOOD | `.alert("Couldn't Load Profile")` with Retry button |
| DirectMessageLauncherView | GOOD | Error state with message + retry implied by sheet re-open |
| BereanHomeView sessions | PARTIAL | Error logged via `dlog` but not surfaced to the user — silent failure |
| Discover landing | GOOD | DisasterAlertCard for urgent content; individual sections silently skip on error |

---

### 4. Offline Behavior

**Severity: Medium (Deferred)**  
No dedicated offline banner was found. The app uses Firebase's offline persistence which shows cached data silently. No explicit "You're offline — showing cached content" messaging. This is a broader architecture concern — a single `NetworkMonitor` banner at the root would address all screens simultaneously. See Deferred list.

---

### 5. Haptics Consistency

**Overall:** GOOD — The codebase has 1,595 uses of `HapticManager`, `UIImpactFeedbackGenerator`, or `UINotificationFeedbackGenerator`. Every primary tab tap uses `.sensoryFeedback(.selection)` in `AMENTabBar`. Feed mode switches, category pills, and prayer actions all trigger `.light` impact.

**Gaps found:**
- `ActivityFeedView` tab filter pills used `UIImpactFeedbackGenerator(style: .light).impactOccurred()` directly (creating a new generator per tap instead of reusing). Low priority — functionally correct.
- `GlassActionPill` in `LiquidGlassButtons.swift` also creates a new `UIImpactFeedbackGenerator` per tap. Same pattern, low priority.

---

### 6. VoiceOver — Missing Labels (FOUND & FIXED)

**Critical gaps fixed in this session:**

| Component | File | Issue | Fix Applied |
|---|---|---|---|
| `CategoryPill` | `FeedCardViews.swift` | Icon-based label missing; selected state not announced | Added `.accessibilityLabel(title)` + `.accessibilityAddTraits(isSelected ? [.isSelected] : [])` |
| `ReactionButton` | `FeedCardViews.swift` | SF Symbol icon + count had no accessible label | Added `.accessibilityLabel(...)` that composes `accessibilityName` + count; added new `accessibilityName` parameter with empty default |
| `FormatButton` | `FeedCardViews.swift` | Icon-only formatting buttons had no label | Added `.accessibilityLabel(label.isEmpty ? icon : label)` + `.isSelected` trait; new `label` parameter |
| `GlassActionPill` | `LiquidGlassButtons.swift` | All icon buttons unlabeled for VoiceOver | Added `accessibilityLabels: [String]` parameter with fallback to SF Symbol name |
| `GlassCircularButton` | `LiquidGlassButtons.swift` | No VoiceOver label | Added `accessibilityLabel: String` parameter with fallback to SF Symbol name |
| `ActivityRow` icon | `ActivityFeedView.swift` | Decorative icon not hidden; combined view improved | Added `.accessibilityHidden(true)` on icon ZStack; added `.accessibilityElement(children: .combine)` on row |
| `ActivityFeedView` filter pills | `ActivityFeedView.swift` | Tab pills missing selected state announcement | Added `.accessibilityLabel(tab.rawValue)` + `.accessibilityAddTraits(isSelected ? [.isSelected] : [])` |
| `PrayerCategoryPill` | `ModernPrayerWallView.swift` | Decorative icon not hidden; selected state missing | Added `.accessibilityHidden(true)` on icon; `.accessibilityLabel` + `.isSelected` trait on button |
| `ModernPrayerCard` pray button | `ModernPrayerWallView.swift` | "Pray" button had no label for state or count | Added `.accessibilityLabel(isPraying ? "Praying — N prayers" : "Pray — N prayers")` |
| `EmptyFeedView` decorative icons | `EmptyFeedView.swift` | Icon ZStacks not hidden from VoiceOver | Added `.accessibilityHidden(true)` on both icon clusters |

**Remaining (not fixed in this session):**

- `CommunityCard`, `SmartCommunityCard`, `TrendingCard` in `FeedCardViews.swift` — icons inside card buttons are decorative; the card button text conveys the label. Low risk since `Button(action: ...) { VStack { Image, Text } }` — VoiceOver picks up the Text. Medium priority.
- `BereanFloatingTabBar` — tab icons have accompanying text; acceptable.
- ~190 icon-only `Button { Image(systemName:) }` instances across the codebase need case-by-case review. The most critical (actions without adjacent text) are addressed above.

---

### 7. Dynamic Type

**Overall:** GOOD  
- `AmenAdaptiveInterfaceSystem.swift` provides `dynamicTypeSize.isAccessibilitySize` checks.  
- `AIIntelligence/LiveCaptionOverlay.swift`, `MediaCaptionOverlay.swift`, `MessagingFilters/MessagingInboxFilterTray.swift`, `AmenFeedContextLabelSystem.swift` all respond to large type.  
- `AmenLivingHeroSystem.swift` adapts layout at accessibility sizes.  
- No `.dynamicTypeSize(...)` range bounds were found — no cap preventing AX5 expansion. This is correct behavior for most text; layout stress-testing at AX5 should be done manually.

**Gap:** Fixed-height containers (`frame(height: 100)` in `CommunityCard`, `frame(height: 48)` on CTAs) will clip text at AX5. These are Deferred — medium effort to audit every fixed-height view.

---

### 8. Reduce Motion

**Overall:** GOOD — 470 instances of `accessibilityReduceMotion` environment variable checks found across the codebase. `Motion.adaptive(.spring(...))` wrapper used throughout `HomeView`, `AMENDiscoveryView`, and feed interactions. `BereanFloatingTabBar`, `AmenLiquidGlassButton`, `BereanInteractiveUI`, and `LiquidGlassVerseDrawer` all check and provide non-spring fallbacks.

---

### 9. Reduce Transparency

**Overall:** GOOD — 10 instances found. `AmenAdaptiveInterfaceSystem`, `AmenLiquidGlassButton`, `AmenLiquidGlassCardOverlay`, and `AmenMessagingAttachmentMenu` all fall back to solid fills when reduce transparency is enabled.

**Gap:** `GlassActionPill` and `GlassCircularButton` in `LiquidGlassButtons.swift` use `.ultraThinMaterial` unconditionally. Small component, low risk — see Deferred.

---

### 10. Color Contrast

**Potential issues (not auto-fixable without design input):**

- `Color.black.opacity(0.6)` text on white in `CommunityCard.subtitle` → ~3.5:1. Fails WCAG AA (requires 4.5:1 for normal text).  
- `Color.secondary` foreground on `Color(.secondarySystemBackground)` in several empty state subtitles — passes in light mode (~4.7:1) but needs manual verification in dark mode.  
- `amenGold` on white backgrounds: not used directly as text in any audited file; used as icon tint and accent, not as body text, so contrast concern is lower.

---

### 11. Dark Mode Parity

**Overall:** GOOD  
All audited screens use semantic colors (`Color.primary`, `Color.secondary`, `Color(.systemBackground)`, `.regularMaterial`, `.ultraThinMaterial`), which automatically adapt. No hardcoded `Color.white` or `Color.black` used as primary text. Some explicit `Color.black.opacity(0.6)` in `CommunityCard.subtitle` and `FeedCardViews` will need a manual dark-mode check (opacity on black is invisible in dark mode). Flagged in Deferred.

---

### 12. Keyboard / ScrollDismissesKeyboard

**Fixed:** `YourFeedView` — main settings scroll view now has `.scrollDismissesKeyboard(.immediately)`.  

**Good coverage found:** 18 existing `.scrollDismissesKeyboard(.interactively)` calls across `CreatePostView`, `PostDetailView`, `FindChurchView`, `WriterNoteView`, `MinimalAuthenticationView`, `OnboardingOnboardingView`, `ChurchNotesView`, `MessagingComponents`, `AMENDiscoveryView`, `ResourcesView`.

**Remaining gaps:** `ModernPrayerWallView.NewPrayerSheet` uses a Form — no `scrollDismissesKeyboard`. `BereanStudyHomeView` composer — `composerText` TextField lives in a pinned overlay, not a scroll view; not applicable. See Deferred.

---

### 13. Tap Targets

**Fixed:** `GlassActionPill` icon buttons — visual icon was `frame(width: 24, height: 24)`, now wrapped in `frame(width: 44, height: 44)` with `contentShape(Rectangle())`.

**Remaining issues:**  
- `HeyFeedTuningPill` has a 16×16 icon — the surrounding pill extends the tappable area so functional size is adequate, but VoiceOver focus rectangle will be small. Low priority.
- `BereanFloatingTabBar` tab frames are 38×26 — below 44pt height. Deferred (M effort; requires layout change in a complex animated tab bar).
- `WitnessMediaAttachmentAdapter` remove button is 28×28. Deferred.
- `AmenSpaceBannerRail` dismiss button is 30×30. Deferred.

---

### 14. Safe Area / iPad / Landscape

**No specific issues found in audited files** — all screens use `ignoresSafeArea()` appropriately, `safeAreaInset(edge:)` for bottom overlays, and `maxWidth: .infinity` for content width. iPad is likely untested but not a blocking concern for current scope.

---

### 15. Deep Links

Navigation routes reviewed in `HomeView.ActivityRouteSheet` — prayer, Selah, Berean chat, Berean insight, church page, announcement, church note, group, prayer update, reply, calendar event all wired. Deep link coordinator exists in `AMENDeepLinkRouter` (seen in git status). No gaps found in scoped review.

---

### 16. Localization Readiness

**Overall:** POOR for localization hardening, but consistent with the rest of iOS social apps at this stage.  
No `LocalizedStringKey` or `String(localized:)` was found — all strings are string literals. This is expected for a v1 product targeting English speakers. The app is not ready for App Store localization submission but this is a known gap.  
**High-count hardcoded string areas:** Every `Text("...")` in every file. Not a blocking issue for current scope. Deferred (XL effort).

---

## Implemented

### Files Modified

| File | Lines Changed | What Changed |
|---|---|---|
| `AMENAPP/AMENAPP/FeedCardViews.swift` | +10 | `CategoryPill`: added `.accessibilityLabel(title)` + `.accessibilityAddTraits(.isSelected)` |
| `AMENAPP/AMENAPP/FeedCardViews.swift` | +12 | `ReactionButton`: added `accessibilityName` parameter; added `.accessibilityLabel(...)` + `.isSelected` trait |
| `AMENAPP/AMENAPP/FeedCardViews.swift` | +5 | `FormatButton`: added `label` parameter; added `.accessibilityLabel(...)` + `.isSelected` trait |
| `AMENAPP/LiquidGlassButtons.swift` | +10 | `GlassActionPill`: added `accessibilityLabels: [String]` param; per-button `.accessibilityLabel`; fixed tap target from 24×24 to 44×44 |
| `AMENAPP/LiquidGlassButtons.swift` | +10 | `GlassCircularButton`: added `accessibilityLabel: String` param; ensured minimum 44pt frame |
| `AMENAPP/ActivityFeedView.swift` | +6 | `ActivityRow`: icon ZStack `.accessibilityHidden(true)`; `.accessibilityElement(children: .combine)` on row |
| `AMENAPP/ActivityFeedView.swift` | +2 | Filter pills: `.accessibilityLabel(tab.rawValue)` + `.accessibilityAddTraits(isSelected)` |
| `AMENAPP/ModernPrayerWallView.swift` | +20 | Added filtered empty state for `filteredPrayers.isEmpty` (icon + title + subtitle) |
| `AMENAPP/ModernPrayerWallView.swift` | +7 | `PrayerCategoryPill`: icon `.accessibilityHidden(true)`; `.accessibilityLabel` + `.isSelected` trait |
| `AMENAPP/ModernPrayerWallView.swift` | +3 | `ModernPrayerCard` pray button: `.accessibilityLabel` with state + count |
| `AMENAPP/AMENAPP/EmptyFeedView.swift` | +2 | Decorative icon ZStacks: `.accessibilityHidden(true)` on both new-user and following-empty icons |
| `AMENAPP/YourFeedView.swift` | +1 | Added `.scrollDismissesKeyboard(.immediately)` to main ScrollView |

**Total changes: 12 call sites across 6 files. Build: PASS (0 errors, 0 warnings introduced).**

---

## Deferred

| Item | Reason Deferred | Effort |
|---|---|---|
| Offline banner (NetworkMonitor root view) | Requires new singleton `NetworkMonitor` + root-level banner injection via `ZStack` or `.overlay` — touches `ContentView` and all tab containers | M |
| Berean sessions silent loading state | `BereanHomeViewModel.loadRecentSessions()` needs a `@Published var isLoadingHistory: Bool` + skeleton row in `bereanConversationPreview` | S |
| `GlassActionPill` + `GlassCircularButton` reduce-transparency fallback | Need to read `accessibilityReduceTransparency` and swap `.ultraThinMaterial` for `Color(.systemBackground)` | S |
| `BereanFloatingTabBar` tap target (38×26) | Animated floating tab bar — changing frame requires layout audit to avoid breaking the animation chain | M |
| `WitnessMediaAttachmentAdapter` remove button (28×28) | Media attachment row — needs `.frame(minWidth: 44, minHeight: 44)` + `contentShape` | S |
| `AmenSpaceBannerRail` dismiss button (30×30) | Same fix pattern as above | S |
| Fixed-height containers (AX5 Dynamic Type) | ~50+ `frame(height: N)` containers will clip text at AX5. Requires per-container audit and `fixedSize(horizontal: false, vertical: true)` changes | L |
| Dark mode audit for `Color.black.opacity(0.6)` text | `CommunityCard.subtitle`, `FeedCardViews` subtitle text — should use `Color.primary.opacity(0.6)` or a semantic secondary color | S |
| `ModernPrayerWallView.NewPrayerSheet` — scrollDismissesKeyboard | `Form` wrapping a `TextEditor` — `.scrollDismissesKeyboard(.interactively)` should be added to the Form | S |
| `CommunityCard` / `SmartCommunityCard` icon accessibility | Decorative icons inside button views — should add `.accessibilityHidden(true)` to the icon | S |
| WCAG AA contrast for `Color.black.opacity(0.6)` on light gray | Fails at 3.5:1 — swap to `Color(UIColor.secondaryLabel)` | S |
| Localization readiness (all `Text("...")` literals) | Full-app L10n requires String Catalog + `LocalizedStringKey` migration | XL |
| iPad layout stress testing | No iPad-specific layout bugs found by code review, but no tested | M |
| `.sensoryFeedback` migration from UIKit generators | Replace `UIImpactFeedbackGenerator` direct calls with `.sensoryFeedback` SwiftUI modifier for consistency | M |
| BereanHomeView error state for session load failure | Silent `dlog` failure — needs a toast or banner | S |

---

## Risk Notes

1. **`ReactionButton.accessibilityName` is a new parameter with an empty default** — all existing call sites continue to compile and behave identically. VoiceOver will fall back to the SF Symbol name if the caller doesn't supply the label. This is safe but means the VoiceOver experience for reaction buttons depends on callers being updated. Recommend a follow-up pass through `PostDetailView` and `FeedCardViews` to supply human-readable `accessibilityName` values (e.g. "Amen", "Comment", "Repost").

2. **`GlassCircularButton.accessibilityLabel` naming clash** — the parameter is named `accessibilityLabel: String` (lowercase `a`), not the SwiftUI modifier `.accessibilityLabel(...)`. This intentionally avoids shadowing the modifier while providing a clear API. The modifier is applied inside the body using the stored value.

3. **`GlassActionPill` tap target change** — icon hit area enlarged from 24×24 to 44×44 via `contentShape(Rectangle())`. The visual icon remains 24×24 inside the larger invisible hit area. The pill's overall size is unchanged. Low regression risk.

4. **`CategoryPill` `.accessibilityAddTraits(.isSelected)`** — this tells VoiceOver to announce "selected" when the pill is active. This is the correct HIG pattern for filter chips and tab-like controls. No regression risk.

5. **No `@MainActor` violations introduced** — all changes are pure view modifiers applied to already-`@MainActor`-isolated view bodies. No concurrency context changes.
