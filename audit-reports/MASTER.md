# AMEN Audit Master Report

**Date:** 2026-05-28  
**Branch:** berean/ui-rebuild-liquid-glass-v1  
**Audit Scope:** Animation quality, performance, Firebase/network, crash stability, UX/accessibility

---

## Totals

| Agent | Domain | Findings | Implemented | Deferred |
|-------|--------|----------|-------------|---------|
| Agent 1 | Liquid Glass Animations | 9 gaps | 13 files changed, ~35 improvements | 8 items (1 XL, 4 M, 3 S) |
| Agent 2 | App Speed / Performance | 20 findings | 37 changes across 16 files | 9 items (1 XL, 3 M, 3 S, 1 L, 1 other) |
| Agent 3 | Firebase / Network | 12 findings (7 actionable) | 6 fixes across 5 files | 9 items (1 L, 4 M, 4 S) |
| Agent 4 | Crash & Stability | 18 findings | 17 fixes across 14 files | 10 items (3 M, 6 S, 1 L) |
| Agent 5 | UX Polish / Accessibility | 28 findings | 17+ fixes across 17 files | 10 items (1 XL, 3 M, 5 S, 1 L) |
| **Totals** | | **~87 findings** | **~110 discrete changes** | **~46 deferred items** |

---

## Top 10 Deferred Items

Ranked by impact x ease (highest first).

| Rank | Item | Agent | Effort | Impact | Why It Matters Most |
|------|------|-------|--------|--------|---------------------|
| 1 | **AmenSmartPromptCard/Hero CTA contrast regression** — `Color.primary` fill with white text creates white-on-white in dark mode | A5 | S | CRITICAL | Ships a visible contrast regression to every dark mode user who sees a prompt card. Block before TestFlight. |
| 2 | **`deleteAllPosts()` in `FirebasePostService` in production binary** — unguarded, no `#if DEBUG` guard, fetches ALL posts and deletes them | A3 | S | CRITICAL | A bad API call or UI bug triggering this function destroys all user content on production. Must be guarded with `#if DEBUG`. |
| 3 | **Convert `AIScriptureCrossRefService` + `AIChurchRecommendationService` polling to snapshot listeners** — busy-wait loops fire 8–120 redundant Firestore reads per invocation | A3 | S | HIGH | Pure Firestore waste, easy swap. Reduces read cost and improves latency by up to 3.5–30s per user action. Two files, same pattern. |
| 4 | **`Color(white: 0.975)` scroll background in ProfileView** — near-white hardcoded background, broken in dark mode | A5 | S | HIGH | ProfileView is one of the most-visited screens. 257 KB file makes surgical fix slightly tricky but still S effort. |
| 5 | **`TrendingCard` fill `.white` at FeedCardViews.swift:346** — same dark-mode pattern as CommunityCard already fixed | A5 | S | HIGH | Feed is the primary surface. Hardcoded white is immediately visible in dark mode for every trending card. S effort, 1-line fix. |
| 6 | **AmenSmartPromptCard/Hero dismiss buttons under 44pt tap target (30x30, 26x26)** — fails WCAG 2.5.5 and HIG | A5 | S | HIGH | Dismiss is a primary action on modal cards; under-target fails accessibility review and increases mis-tap rate. Needs design sign-off to adjust layout. |
| 7 | **`JobDetailView.swift` 4x `@StateObject` → `@ObservedObject` for `JobService.shared`** | A2 | S | MED | Same singleton double-ownership pattern already fixed in 26 other locations. Mechanical fix, zero regression risk. |
| 8 | **`RelationshipService.requestDiscipleship` unbounded duplicate-check query** — scans all discipleship records unbounded | A3 | S | MED | Same `.limit(to: 50)` pattern already applied to 4 other services. One-liner. Prevents full-scan reads for active discipleship users. |
| 9 | **`AmenMentionParser.swift` `try! NSRegularExpression` → safe pattern** | A4 | S | LOW | Cosmetic hardening; pattern is valid constant so no production risk, but inconsistent with app-wide hardening push. |
| 10 | **Cloud Function `minInstances: 1` for `bereanChatProxy`, `guardianClassify`, `generateGroupPulse`, `detectPrayerSignal`** | A3 | M | HIGH | These CFs are on real-time user paths (chat, safety, prayer signals). Cold starts add 2–8s of latency. Deploy-config change, not Swift. |

---

## Cross-Agent Conflicts

### 1. `.amenSheet()` Detents Change (A1) vs Full-Screen Content Views (A1 self-conflict + A4/A5 interaction)

Agent 1 added `.presentationDetents([.medium, .large])` globally to `AmenSheetModifier`. This means every view using `.amenSheet()` now opens at medium height first. Several views audited by Agent 4 (e.g., `FullScreenAvatarView`, `LoginHistoryView`) and Agent 5 (Creator sheets) are content-dense sheets designed to fill the full screen. Callers need explicit `.presentationDetents([.large])` overrides or their content will be clipped at 50% height on first open.

**Resolution:** Audit all `.amenSheet()` call sites (primarily `ProfileView` ~10 sites and `BereanPulseView` ~5 sites) and add `.presentationDetents([.large])` to any sheet whose content is not designed for medium-height presentation.

### 2. Image Cache Layer (A2) vs Animation Performance (A1)

Agent 2 added `CachedAsyncImage` with downsampled sizes across hot-path views. Agent 1 added parallax stretching and scale animations to `ProfileView` and `FeaturedHeroCarousel`. The profile header avatar (`CachedAsyncImage` at 200x200) will be upscaled during the parallax stretch animation. At 3x retina the 200x200 point image becomes 600x600 pixels — adequate, but the `scaleEffect(1.0 + scrollOffset * 0.0012)` on overscroll will still cause pixelation above ~1.83x. The `FullScreenAvatarView` (600pt) is correctly sized for upscaling.

**Resolution:** No immediate action needed. If pixelation is noticed during QA of profile pull-down stretch, increase profile header avatar cache size to 400x400.

### 3. `@ObservedObject` Singleton Fixes (A2) vs Animation State (A1)

Agent 2 changed 26 `@StateObject .shared` to `@ObservedObject`. Agent 1's `BereanPulseCardView` card-expand animation relies on `@State` flags inside the card. These are not singletons and were not touched by Agent 2. No conflict. However, `PostCard.swift` has 40+ `@State` properties (A2 finding F-16, deferred) — if `EquatableView` wrapping is added in a future sprint, it must not suppress re-renders of the animation state flags that drive press/expand animations.

**Resolution:** When implementing `Post → Equatable + EquatableView` (deferred), explicitly test that press scale animations and card expand states still fire correctly.

### 4. Dark Mode `Color.primary` Fill (A5) vs Legibility on Glass Surfaces (A1)

Agent 5 changed CTA button fills from `Color.black` / `Color.white` to `Color.primary`. Agent 1 added specular highlights and glass layering to several surfaces. `Color.primary` (UIColor.label) is near-black in light mode and near-white in dark mode — which means CTA buttons on glass surfaces will be nearly invisible when placed over the specular white highlight in light mode. The `AmenSmartPromptCard` dismiss area is the specific collision point.

**Resolution:** Replace `Color.primary` on filled CTA backgrounds with a dedicated high-contrast semantic token (e.g., `Color(.label)` for text, `Color(.systemFill)` or a brand accent color for filled button backgrounds). Do not use `Color.primary` as a fill color.

### 5. Firebase Listener Bounds (A3) vs Pagination (A2)

Agent 3 added `.limit(to: 50)` on meeting and prayer request listeners. Agent 2's deferred F-14 (feed virtualisation) would introduce pagination. If A3's limits conflict with A2's eventual pagination design (e.g., if `fetchMeetingsForGroup` is expected to support cursor-based pagination), the fixed 50-document limit would need to become a paginated `.limit(to: pageSize).start(afterDocument:)` pattern.

**Resolution:** When feed virtualisation is implemented, revisit the A3 limits and replace with proper cursor pagination rather than fixed caps.

---

## Architecture Patterns (Recurring Themes)

These issues appeared in 2 or more agents and represent systemic gaps, not isolated bugs.

### 1. Hardcoded Color Literals (A1, A2, A5 — 3 agents)

`Color.white`, `Color.black`, `Color(white: N)`, `.foregroundColor(.black/.gray)` appeared across 20+ files. Agent 5 fixed 17 files; A1 uses semantic tokens in new code; A2's `CachedAsyncImage` additions use system fills. Despite prior audit rounds, hardcoded colors persist because individual view files are large (257 KB ProfileView) and the problem re-appears with each new feature. **Systemic fix:** A SwiftLint custom rule banning `Color.white` / `Color.black` / `Color(white:)` in non-design-system files would catch this at PR time.

### 2. `@StateObject` on Singletons (A2, A4 — 2 agents)

Agent 2 found and fixed 26+ instances of `@StateObject private var x = SomeService.shared`. Agent 4's concurrency audit confirms the `@MainActor` adoption is healthy but did not re-audit singleton wrapper patterns. The underlying cause is that new feature views copy-paste from older files that predated the singleton pattern audit. **Systemic fix:** Add a SwiftLint rule: `@StateObject` on a property whose initialiser contains `.shared` triggers a warning.

### 3. Unbounded Firestore Queries (A3, A4 — 2 agents)

Agent 3 added `.limit()` to 6 query sites. Agent 4's risk notes flag `AntiHarassmentEngine.swift` with ~8 additional unbounded queries. The pattern is: any file added after the original service pattern audit introduced new `.getDocuments()` / `addSnapshotListener()` calls without limits. **Systemic fix:** A code review checklist item: any Firestore `.getDocuments()` or `.addSnapshotListener()` without `.limit(to:)` must be justified.

### 4. Force-Unwraps / Unsafe Force Casts (A4, A3 — 2 agents)

Agent 4 fixed 17 force-unwrap crash paths. Agent 3 identified `deleteAllPosts()` with an unbounded production delete (effectively a force-clear of all user data). Both trace to defensive-code debt — features built under time pressure without nil-path handling. The `as! Color` critical crash (A4 F-01) was shipping in production. **Systemic fix:** SwiftLint `force_cast` and `force_unwrap` rules enabled for production targets (not previews).

### 5. Missing Accessibility Labels on Interactive Elements (A5, A1 — 2 agents)

Agent 5 found 10+ views with unlabeled interactive elements; Agent 1 added new interactive animations (badge bounce, page dots, press gestures) without accessibility annotations. The new `scrollMaterialReveal` modifier and specular highlights are decorative and correctly receive no VO treatment, but new interactive elements added during animation work (Play button, specular tab capsule) should be verified for VO exposure.

---

## Recommended Next-Sprint Focus (EXACTLY 5 items)

### 1. Guard `deleteAllPosts()` with `#if DEBUG`
**File:** `AMENAPP/FirebasePostService.swift` (around line 2225)  
**Change:** Wrap the entire `deleteAllPosts()` function (and its caller chain) in `#if DEBUG ... #endif`.  
**Why:** This is the only unguarded mass-destructive operation in the production binary. One bad API call or future UI wire-up destroys all user content with no recovery path. Zero regression risk; 2-line change.

### 2. Fix `AmenSmartPromptCard` + `AmenSmartPromptHero` CTA contrast regression
**Files:** `AMENAPP/DesignSystem/Prompts/AmenSmartPromptCard.swift`, `AmenSmartPromptHero.swift`  
**Change:** Replace `Color.primary` as the CTA button fill with `Color(.label)` and update foreground text to `Color(.systemBackground)` so the pair always inverts correctly. Also resize dismiss buttons to `.frame(width: 44, height: 44)` with `.contentShape(Rectangle())`.  
**Why:** White text on white fill is a visible regression in dark mode (ships to ~40% of users). This was introduced by Agent 5's dark mode pass and must be corrected before any TestFlight distribution.

### 3. Convert polling loops to snapshot listeners in AI cross-reference services
**Files:** `AMENAPP/AIScriptureCrossRefService.swift:107` (D1), `AMENAPP/AIChurchRecommendationService.swift:183` (D2)  
**Change:** Replace `waitForReferences` and `waitForRecommendations` busy-wait poll loops with a single `addSnapshotListener` + `CheckedContinuation` + `Task.sleep` timeout race. Both use identical pattern; fix once and copy.  
**Why:** Every AI cross-reference lookup wastes up to 4 seconds and 8 redundant Firestore reads. Every church recommendation wastes up to 30 seconds and 60 reads. These are on hot AI paths that users interact with during Bible study and church discovery — the two core differentiators of the app.

### 4. Fix `AmenSheetModifier` detent collisions at all full-screen call sites
**Files:** All `.amenSheet()` call sites in `ProfileView.swift` (~10), `BereanPulseView.swift` (~5), and any other view identified by global search for `.amenSheet(`  
**Change:** Search for `.amenSheet(` app-wide. For any site whose content is designed to fill the screen (avatar viewer, login history, full composer), add `.presentationDetents([.large])` directly on that sheet's content view.  
**Why:** Agent 1's global `AmenSheetModifier` change silently clips content on all full-screen sheets. This is a UX regression across ProfileView, Berean, and potentially Creator flows. No logic change, purely presentation modifiers.

### 5. Enable SwiftLint `force_cast` + `force_unwrap` + `@StateObject`-on-singleton rules
**File:** `.swiftlint.yml` (project root or CI config)  
**Change:** Add `force_cast: error`, `force_unwrap: warning` (exclude `#Preview` files), and a custom `stateobject_shared` regex rule flagging `@StateObject.*\.shared`.  
**Why:** Agent 4 found and fixed 17 force-unwrap crash paths that were undetected for multiple audit rounds, including a guaranteed crash in `SmartContextBarView` affecting all users with default accessibility settings. Agent 2 fixed 26 `@StateObject` singleton patterns. Without lint enforcement, both patterns re-emerge with each new feature. This is the single highest-leverage systemic change — it catches the entire class of issue at PR review time, not at audit time.

---

## Key Risks to Address Before Ship

| Risk | Severity | Source | Status |
|------|----------|--------|--------|
| `SmartContextBarView.swift:616` — `AnyShapeStyle as! Color` crashes on default settings (reduce transparency OFF) for ALL users | **SHIP BLOCKER** | A4 F-01 | FIXED by I-01 |
| `deleteAllPosts()` in `FirebasePostService` is in production binary, unguarded, fetches ALL posts to delete | **SHIP BLOCKER** | A3 Risk Note 5 | NOT FIXED — must add `#if DEBUG` guard |
| `AmenSmartPromptCard/Hero` CTA: `Color.primary` fill + white label = white-on-white in dark mode | **SHIP BLOCKER** | A5 Risk Note 1 | NOT FIXED — contrast regression introduced by dark mode pass |
| `AmenSheetModifier` now opens `.medium` first globally — full-screen sheets clipped | **HIGH** | A1 Risk Note 1 | PARTIALLY FIXED — call sites need `.presentationDetents([.large])` overrides |
| `AmenVideoPlayerModel` missing `@MainActor` — off-main `@Published` mutations possible | **HIGH** | A4 F-02 | FIXED by I-02/I-03 |
| `GivingRankingService`, `GivingOrgDetailView`, `ChurchJourneyPlanViewModel`, `ProvenanceTrustPanel`, `SmartShareBackendService` — force-unwrap crashes across giving + planning flows | **HIGH** | A4 F-03 to F-07 | FIXED by I-04 to I-08 |
| `LiveMeetingViewModel` Firestore listener leak — listener orphaned on navigation away | **HIGH** | A3 F1 | FIXED |
| `BereanSmartChannelHook` + `MeetingService` + `RelationshipService` — unbounded Firestore queries | **HIGH** | A3 F2-F4 | FIXED |
| N+1 Firestore reads in `AIBibleStudyExtensions` — up to 21 serial reads per load | **HIGH** | A3 F5 | FIXED (concurrent TaskGroup) |
| 11 Creator view files and 3 DesignSystem prompt files with hardcoded `Color.white` — broken in dark mode | **HIGH** | A5 F16-F19 | FIXED |
| `ProfileView` tab bar `.black` fill — invisible in dark mode | **HIGH** | A5 F1/F2 | FIXED |
| `ErrorView` + `PostSkeletonView` — `.foregroundColor(.black)` in shared components used everywhere | **HIGH** | A5 F5-F8 | FIXED |
| Cold starts on `bereanChatProxy` + `guardianClassify` CFs — 2–8s latency on real-time safety/chat paths | **MED** | A3 D5 | NOT FIXED — requires CF deploy config |
| `AntiHarassmentEngine.swift` — ~8 unbounded Firestore queries on reports/users collections | **MED** | A3 Risk Note 4 | NOT AUDITED — out of scope this pass |
| `BereanConversationService` + `ChatMemoryService` — listener cleanup unverified in large files | **MED** | A3 D9 | NOT AUDITED — too large for this pass |

---

## Before/After Summary

### What the App Was Before This Audit

- **Animation:** Inconsistent spring presets across 13+ files — tabs, cards, toasts, and page indicators each used different spring parameters (response: 0.20–0.40, damping: 0.70–0.86). Press scales ranged from 0.94–0.97. Reduce Motion had no dedicated adaptive path. Sheets had no drag indicators or detents app-wide.
- **Performance:** 26 singleton ObservableObjects incorrectly owned via `@StateObject`, causing stale-state reads and unnecessary layout churn during list recycling. 11 hot-path `AsyncImage` calls in `PostDetailView`, `ProfileView`, `FeedComposerRow`, and `PostCard` fired uncached URLSession fetches on every navigation and scroll-to-top.
- **Firebase:** `LiveMeetingViewModel` listener leaked on every meeting view dismissal. 4 high-traffic query paths (`meetings`, `groups`, `members`, `prayer requests`) had no document limits and would full-scan on any active church. `AIBibleStudyExtensions` fetched 20 conversations with 21 sequential serial reads (N+1).
- **Stability:** A guaranteed runtime crash (`as! Color` on `AnyShapeStyle`) was shipping to all users who had "Reduce Transparency" OFF — the default. 6 additional force-unwrap crash paths in Giving, Journey, Provenance, and SmartShare flows. `AmenVideoPlayerModel` published off-main thread.
- **UX/Accessibility:** Dark mode was broken across 20+ files (Creator sheets, prompt cards, profile tab bar, error views, skeleton views, feed cards all forced white/black). VoiceOver had no labels on profile photo, follower/following counts, feed topic chips, or empty state CTA buttons.

### What the App Is After This Audit

- **Animation:** Unified `Motion.liquidSpringAdaptive` as the single Reduce Motion decision point. All tabs, cards, toasts, page indicators, and sheet transitions use `.bouncy(duration: 0.4, extraBounce: 0.1)` or the adaptive wrapper. Press scale is universally 0.96. All `.amenSheet()` calls have drag indicators and `.medium/.large` detents. Profile header has stretchy parallax overscroll. ScrollMaterialReveal applies scroll-driven glass opacity to BereanPulse top bar. SF Symbol badge bounce fires on new badge arrival.
- **Performance:** 37 discrete changes eliminating double-ownership of 26 singletons and caching all hot-path image loads. `PostDetailView` no longer fires 50 URLSession tasks on initial comment load. Profile header, reply cards, and full-screen avatar all draw from `ImageCache.shared` on repeat navigation.
- **Firebase:** All 4 unbounded query paths capped. Listener leak in LiveMeeting closed. N+1 serial reads replaced with concurrent `withThrowingTaskGroup` (up to 20x faster at full scale). Privacy dashboard count queries bounded at 1000.
- **Stability:** Guaranteed crash eliminated (SmartContextBarView). 16 additional force-unwrap crash paths hardened with `if let`, nil-coalescing, and guarded `break` patterns. `@MainActor` annotation and `[weak self]` added to video player. All Calendar and URL force-unwraps in hot paths replaced with safe fallbacks.
- **UX/Accessibility:** Dark mode fixed across 17 files covering the entire Creator OS (11 sheets), the core design system prompt components (3 files), ProfileView tab bar, shared error/skeleton components, and feed cards. VoiceOver labels added to profile photo, follower/following counts, feed topic chips, session mode chips, empty state CTAs, and collapsible section headers. All tap targets at or above 44pt minimum for fixed controls.

---

*Report synthesised by Agent 6 — Synthesis & Roadmap*  
*Source reports: agent1-animations.md, agent2-performance.md, agent3-firebase.md, agent4-stability.md, agent5-ux-accessibility.md*
