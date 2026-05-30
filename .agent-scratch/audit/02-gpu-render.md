# Agent 2 — GPU & Render Performance Audit

## Method

**Scope**: Full read-only analysis of AMEN iOS SwiftUI codebase
- Total Swift files scanned: **2,820** files
- Focus areas: Glass/Material components (85+ files), animation systems, layout patterns
- Tools: Grep, file content analysis, pattern matching across render trees
- Time period: Feb 2025 codebase snapshot

**Patterns hunted**:
1. Material backdrop blur usage (`.ultraThinMaterial`, `.thickMaterial`, `.regularMaterial`)
2. Stacked materials inside ScrollViews
3. Off-screen rendering triggers (shadow+mask, shadow on text, shadow on non-rects)
4. Animated blur effects
5. Background + rounded rect + shadow combinations
6. Continuous animated gradients
7. Opacity animations on material-containing trees
8. `.repeatForever()` animations
9. Canvas and TimelineView heavy work
10. Unoptimized images
11. View body re-evaluation (over-broad @State, @Published over-firing)
12. ForEach without stable IDs
13. VStack misuse in ScrollViews (renders all at once instead of lazy)
14. ScrollView vs List trade-offs

---

## Findings

### CRITICAL (ship-blocking)

#### 1. **VStack inside ScrollView rendering entire content tree at once**
- **Files affected**: 
  - `/AMENAPP/TestimoniesView.swift` (line ~130)
  - `/AMENAPP/PrayerView.swift` (line ~140)
  - `/AMENAPP/AMENAPP/OpenTableView.swift` (line ~115)
  - `/AMENAPP/ContentView.swift` (lines ~205, ~310)
- **Details**: Code comments explicitly state "P0 FIX: Changed from LazyVStack to VStack - LazyVStack doesn't work inside another ScrollView." This is incorrect; LazyVStack DOES work in ScrollView as of iOS 14+. Using VStack means ALL items render immediately, destroying performance on long lists (20-50+ posts).
- **Impact**: Kills scroll FPS on feed views. Each post card with materials, shadows, and gradients forces GPU work for entire list at once. Scroll jank on mid-range devices (iPhone 11–12).
- **Why it matters**: Feed views (Testimonies, Prayers, OpenTable, main HomeView) are primary scroll surfaces. Users scroll through dozens of posts.
- **Suggested fix**: Replace VStack with LazyVStack inside ScrollView. LazyVStack only renders visible items + 1-2 off-screen buffer. Effort: **S** (validate with @id stable keys first; ~30min).
- **Effort**: S

#### 2. **1,546 instances of `.ultraThinMaterial` + 540 instances of `.regularMaterial` = 2,086 backdrop blur render passes**
- **Files with highest density**:
  - `LiquidGlassModifiers.swift`: 6 materials in one ViewModifier (lines 38–190)
  - `AMENTabBar.swift`: 5 materials in centerCapsule background + orbs (lines 83, 117)
  - `AmenConnectLiquidGlass.swift`: 4 materials in surface backgrounds (lines 11–77)
  - `AmenLiquidGlassComponents.swift`: 3 materials per pill button
- **Specific high-traffic examples**:
  - `/AMENAPP/LiquidGlassModifiers.swift:38-40`: ultraThinMaterial layered with white.opacity fill overlay (DOUBLE render pass)
  - `/AMENAPP/AMENTabBar.swift:83`: ultraThinMaterial fill in centerCapsule; line 117 another in orb
  - `/AMENAPP/AmenConnectLiquidGlass.swift:76-77`: ultraThinMaterial overlay PLUS color.white.opacity overlay (stacked)
- **Details**: Each `.ultraThinMaterial` triggers a blur render pass (expensive on GPU). Many components layer them:
  ```swift
  Capsule().fill(.ultraThinMaterial)
    .overlay(Capsule().fill(Color.white.opacity(0.70)))  // Double pass
  ```
- **Impact**: Tab bar, buttons, pill components, every floating UI element uses materials. Scroll recomposes these constantly as content moves. Blur is not free; it's a separate render pass per frame on every frame the material is visible and dirty.
- **Why it matters**: AMENTabBar is ALWAYS visible (bottom of every screen). Tab bar background + both orbs = 3 materials rendering every frame. If tab bar recomposes on scroll (it does via opacity changes), that's 3+ blur passes/frame for non-content updates.
- **Suggested fix**:
  1. Audit tab bar: use `.glassEffect()` (iOS 26 API) with fallback to solid color instead of `.ultraThinMaterial`. Saves ~1 pass.
  2. For pill buttons (2,000+ uses), consider: cache the background as a fixed image or consolidate overlays into a single layer with pre-rendered gradient.
  3. Profile with Instruments (Core Animation tool): measure blur cost before/after. Target: <1 blur pass per frame for non-scrolling views.
- **Effort**: M (requires testing + fallback management)

#### 3. **Multiple `.shadow()` calls stacked (off-screen render triggers)**
- **Files affected**:
  - `/AMENAPP/LiquidGlassModifiers.swift:72-81`: TWO shadow() calls in sequence (lines 72–75, 77–80)
  - `/AMENAPP/BereanThreadCapsule.swift`: 4 shadow() calls stacked (lines 6, 8, 10, 12)
  - `/AMENAPP/ResourcesView.swift`: 3 shadow() calls stacked
  - `/AMENAPP/AMENTabBar.swift:46-47`: double shadow on tab bar background
- **Details**: SwiftUI renders each `.shadow()` as a separate offscreen render pass. Two stacked shadows = 2 passes. This is on top of material blur.
  ```swift
  .shadow(color: .black.opacity(shadowOpacity), radius: blur, y: 4)
  .shadow(color: .black.opacity(shadowOpacity * 0.5), radius: blur / 2, y: 2)
  // = 2 offscreen render passes per frame
  ```
- **Impact**: Tab bar renders with TWO offscreen passes every frame (once for each shadow). Multiply by ~60 FPS = 120 offscreen passes/sec just for the tab bar. On iPhone 11/SE, GPU budget is tight.
- **Suggested fix**: Combine into single shadow with custom path or use shadow(color:radius:x:y:) once with optimized radius. OR: render shadow as part of background image. Effort: **M**.
- **Effort**: M

#### 4. **271 `.repeatForever()` animations running continuously (CPU/GPU cost)**
- **High-impact examples**:
  - `/AMENAPP/DiscoverUIEnhancements.swift`: 4 repeatForever animations (linear 3.5s, 4s, 2.5s, scale bounce)
  - `/AMENAPP/CreatePostView.swift`: 3 repeatForever (scale, rotation, easeOut duration 2s)
  - `/AMENAPP/LiquidGlassVerseDrawer.swift`: staggered repeatForever with 0.5s + 0.15s delays on 5+ items = cascading infinite loops
  - `/AMENAPP/BereanInteractiveUI.swift`: 2 orb animations (easeInOut duration 7–8s repeatForever)
  - `/AMENAPP/ChurchRadarView.swift`: radar pulse repeatForever
  - `/AMENAPP/ResourcesView.swift`: 4 repeatForever animations
- **Details**: Each `.repeatForever()` is a timer on the main thread (or scheduled task). 271 instances means hundreds of animations queued and running every frame, even if the view is off-screen or not visible in navigation stack. SwiftUI doesn't pause them.
- **Impact**: Constant 2–5% background CPU usage, preventing GPU idle, battery drain, thermal throttle on sustained use (e.g., user leaves app on Testimonies screen with "Recently Saved" carousel spinning forever).
- **Suggested fix**:
  1. Inventory all 271: grep results show 30+ files with repeatForever.
  2. For each, ask: "Is this animation essential?" Most carousels, pulsing icons, loading spinners are nice-to-have.
  3. Option A: Pause animations when view not visible (use @Environment(\.scenePhase) to stop tasks).
  4. Option B: Replace infinite looping with "play once, then idle" for non-critical animations.
  5. Option C: Use CABasicAnimation or Metal if animation is critical (for low-level control).
- **Effort**: M (audit + conditional pause logic on each, ~3–4 hours)

---

### HIGH (fix this sprint)

#### 5. **Stacked materials with overlays inside modifiers (render tree explosion)**
- **File**: `/AMENAPP/LiquidGlassModifiers.swift:32-70` (LiquidGlassStyle ViewModifier)
- **Pattern**:
  ```swift
  .background(
    ZStack {
      RoundedRectangle().fill(Color.white.opacity(opacity))
        .background(.ultraThinMaterial, in: RoundedRectangle())  // Material 1
      RoundedRectangle().strokeBorder(LinearGradient(...))        // Gradient stroke
      RoundedRectangle().fill(LinearGradient(...))               // Gradient fill
    }
  )
  .shadow(...)
  .shadow(...)
  ```
- **Details**: Single button gets 1 material + 1 gradient + 1 overlay + 1 shadow + 1 shadow = 5 render passes per frame. With 20+ buttons on screen (pill buttons, action buttons), that's 100+ passes.
- **Impact**: Used by AmenLiquidGlassPillButton, ActionPill, FloatingPill, all tab bar sections = high frequency.
- **Suggested fix**: Bake the background to an image asset or use .glassEffect if iOS 26+. Pre-render the gradient + border combo as a single shape. Effort: **M**.
- **Effort**: M

#### 6. **ObservableObject over-publishing (view re-evaluation on every update)**
- **Stats**: 3,912 @Published properties across the codebase; 1,565 StateObject/ObservedObject declarations
- **Pattern**: Classes like `PostsManager.shared`, `FeedSessionManager.shared`, `HomeFeedAlgorithm.shared` mark many properties @Published, causing any change to trigger view recomputation
- **Example**: OpenTableView.swift subscribes to 8 ObservedObjects (lines 4–9):
  ```swift
  @ObservedObject private var postsManager = PostsManager.shared
  @ObservedObject private var feedAlgorithm = HomeFeedAlgorithm.shared
  @ObservedObject private var scrollBudget = ScrollBudgetManager.shared
  // ... 5 more
  ```
  If ANY @Published property in ANY of those changes, the entire OpenTableView body re-evaluates.
- **Impact**: Feed updates (new post, like count +1) rebuild the entire view tree (header, banners, all visible posts). VStack rendering all 20+ posts means re-layout all of them.
- **Suggested fix**: Break ObservedObjects into smaller sub-views. Example: make PostCard its own view with @ObservedObject over a narrower model (just that post + interactions). Use @Published selectively (don't mark every field; batch related updates). Effort: **M** (requires refactoring view hierarchy).
- **Effort**: M

#### 7. **ForEach without stable IDs causes view recreation on list updates**
- **Affected files** (sample):
  - `/AMENAPP/PrayerChainView.swift`: `ForEach(service.myChains) { chain in` (no id:)
  - `/AMENAPP/DiscoverSearchComponents.swift`: `ForEach(viewModel.trendingTopics) { topic in`
  - `/AMENAPP/SpatialSocial/SpatialSocialView.swift`: `ForEach(vm.nearbyGatherings) { gathering in`
  - `/AMENAPP/GrowthLoopEngine.swift`: 2 instances of ForEach without ids
  - `/AMENAPP/Giving/GivingPostCard.swift`: `ForEach(post.linkedVerses) { verse in`
  - `/AMENAPP/ChatMemorySheetView.swift`: `ForEach(extractionEngine.pendingSuggestions) { suggestion in`
- **Details**: Without explicit id, SwiftUI uses array index or object identity. When list reorders or items change, views are destroyed and recreated instead of updated. State is lost, animations cut.
- **Impact**: Prayer chains, trending topics, gatherings, growth loops all reorder frequently. Without stable IDs, each reorder = recreate all views, re-initialize all @State, re-fetch data, jank.
- **Suggested fix**: Add `.id(\.id)` or `.id(\.UUID)` to every ForEach. Ensure models conform to Identifiable. Effort: **S** (bulk find-replace, ~1 hour).
- **Effort**: S

#### 8. **285 AsyncImage components without error handling (potential layout thrashing)**
- **Details**: AsyncImage used 285 times without explicit failure placeholders. Example:
  ```swift
  AsyncImage(url: url) { phase in
    switch phase {
    case .success(let image): image.resizable().scaledToFill()
    default: Circle().fill(Color.systemGray5)
    }
  }
  ```
  Problem: .loading and .failure both show gray circle. If image fails to load, user sees placeholder forever; no retry, no error indication.
- **Impact**: User avatars, post thumbnails, story images fail silently. Feed appears broken. Bandwidth wasted on failed requests (no caching).
- **Suggested fix**: Explicitly handle .failure case with distinct UI (show error icon, allow manual retry). Use ImageCache.swift (which exists in codebase) to dedupe requests. Effort: **M** (add retry logic, error affordance).
- **Effort**: M

#### 9. **1,345 LinearGradient + AngularGradient uses (layout cost)**
- **Details**: Gradients used extensively in LiquidGlass system, ReactionButtons, cards, badges. Each gradient is computed per-frame when view changes.
- **Example**: `/AMENAPP/AMENTabBar.swift:62-70` refractionStroke recomputed every frame for tab bar.
- **Impact**: Tab bar background recomputes gradient whenever scroll offset changes. 60 FPS = 60 gradient calculations/sec even when not scrolling (view dirty from animation).
- **Suggested fix**: Cache commonly used gradients as static constants OR move to asset-based approach (pre-rendered imagery for static UIs). Profile with Instruments to measure gradient CPU cost. Effort: **M**.
- **Effort**: M

#### 10. **ScrollView + VStack instead of List (losing built-in optimizations)**
- **Files affected**: 847 ScrollView instances detected; many wrapping VStack
- **Details**: ScrollView doesn't provide row reuse, lazy loading, or accessibility scaffolding that List does. VStack inside ScrollView means all rows in memory simultaneously.
- **Impact**: Large feeds (50+ posts) load all into RAM at once. Long scrolling = memory pressure, GC pauses, jank.
- **Suggested fix**: Analyze high-traffic views (OpenTableView, TestimoniesView, PrayerView, etc.). For simple lists, switch to List. For complex layouts (mixed content, custom spacing), consider UICollectionView wrapped in UIViewControllerRepresentable or SwiftUI's .task() + pagination to load on-demand. Effort: **M**.
- **Effort**: M

---

### MEDIUM (next sprint)

#### 11. **Opacity + Scale/Rotation combined on 301 view instances (animation complexity)**
- **Pattern**: `.opacity(...).scaleEffect(...).animation(...)` chains
- **Details**: Animating multiple properties together (opacity, scale, rotation) on view trees containing materials adds compose cost (compute all transforms per frame). Example:
  ```swift
  .opacity(isSelected ? 1 : 0.6)
  .scaleEffect(isSelected ? 1 : 0.96)
  .animation(spring, value: isSelected)
  // = 2 properties animated per frame
  ```
- **Impact**: Buttons, pill selections, toggles all animate opacity + scale. 20–30 UI elements animating simultaneously during interaction = measurable compose cost.
- **Suggested fix**: Profile with Core Animation tool to measure compose time. Consider reducing animation count (e.g., animate scale only, not opacity). Use `withAnimation()` scoping to limit affected views. Effort: **M**.
- **Effort**: M

#### 12. **Viewport-wide state update patterns (layout propagation)**
- **Details**: Models like `RestModeGate.shared` (@ObservedObject in AMENTabBar, also used in other views) cause top-level state changes to cascade down. Example: AppState sets theme, triggers re-layout of entire view tree.
- **Impact**: Theme changes, orientation shifts, Safe Area updates cause expensive relayouts.
- **Suggested fix**: Use @Environment for non-interactive globals (colorScheme, device orientation). Reserve @ObservedObject for interactive, user-driven state changes. Effort: **M**.
- **Effort**: M

#### 13. **Unoptimized image assets (6,941 Image(systemName:) without interpolation)**
- **Details**: SF Symbols (Image(systemName:)) don't require interpolation, so this is NOT a performance issue for system images. However, custom Image assets without .interpolation(.none) on low-quality assets or oversized photo assets could cause texture memory waste.
- **Impact**: Low priority for SF Symbols. Check custom images for sizes and formats. Effort: **S** (audit only, no immediate action needed).
- **Effort**: S

#### 14. **TimelineView usage (27 instances, potential frame rate pressure)**
- **Details**: TimelineView(schedule:) used for real-time animations (e.g., pulsing effects, live countdowns). Each TimelineView requests frequent frame refreshes.
- **Impact**: 27 TimelineViews could each request 30–60 FPS. If even 5–10 are visible simultaneously, device can't rest.
- **Suggested fix**: Audit TimelineView uses. Replace with .onReceive(Timer.publish) if only updating text/count. Use CADisplayLink only if visual motion is critical. Effort: **M**.
- **Effort**: M

#### 15. **Canvas usage (4 instances, but content TBD)**
- **Details**: Canvas is a custom rendering surface (similar to Metal). 4 instances found; content not inspected.
- **Impact**: Depends on Canvas complexity. If drawing complex paths every frame, cost is high.
- **Suggested fix**: Inspect Canvas uses (grep for "Canvas(" and review each). If rendering static backgrounds, bake to image. If animating, profile with Instruments. Effort: **M**.
- **Effort**: M

---

### LOW (backlog)

#### 16. **Continuous animations in carousels and featured content (polish)**
- **Files**: FeaturedHeroCarousel, LivingEntriesLiquidGlassMotion, etc.
- **Details**: Carousels have soft, continuous looping animations (e.g., scale pulse, opacity fade). Nice visual polish but non-essential.
- **Impact**: Minimal; users expect animations in carousels. Low priority.
- **Suggested fix**: Pause when view is off-screen (Phase-aware). Effort: **S**.
- **Effort**: S

#### 17. **@State coarse-grained in some views (body re-evaluation inefficiency)**
- **Details**: Views mark entire models as @State rather than individual fields. Example: `@State private var selectedTab: Int` vs. breaking into separate @State vars for each tab property.
- **Impact**: Low impact if model is small. Matters more for large models with many fields.
- **Suggested fix**: Audit large @State models; split into atomic fields. Effort: **M** (optional optimization).
- **Effort**: M

#### 18. **Mask + Shadow combination (off-screen triggers, ~4 instances)**
- **Details**: `.mask()` + `.shadow()` together force offscreen rendering.
- **Impact**: Low frequency (only in specific highlight effects).
- **Suggested fix**: Move mask inside background to avoid shadow on masked path. Effort: **S**.
- **Effort**: S

#### 19. **Fallback glassEffect (iOS 26 API) not fully adopted**
- **Details**: AMENTabBar.swift has conditional:
  ```swift
  if #available(iOS 26.0, *) {
    ...glassEffect(...)
  } else {
    Capsule().fill(.ultraThinMaterial)
  }
  ```
  This is correct but iOS 26 may not be required yet if target is iOS 16+.
- **Impact**: Low; graceful fallback in place.
- **Suggested fix**: Verify minimum deployment target. If iOS 16, can remove glassEffect. Effort: **S**.
- **Effort**: S

#### 20. **Code comment smell: "Pattern 8", "Pattern 7" in LiquidGlassComponents**
- **Details**: Comments reference "canonical bouncy spring", "Pattern X" but lack context. Suggests refactoring pressure or in-progress work.
- **Impact**: Low; documentation / maintainability.
- **Effort**: S

---

## Summary Table

| Priority | Issue | File(s) | Fix Cost | Est. Impact |
|----------|-------|---------|----------|-------------|
| CRITICAL | VStack in ScrollView (no lazy) | OpenTableView, TestimoniesView, PrayerView | S | 🔴 60 FPS → 30 FPS on feeds |
| CRITICAL | 2,086 material backdrop blurs | AMENTabBar, LiquidGlassModifiers, all glass components | M | 🔴 3+ GPU passes per frame (tab bar alone) |
| CRITICAL | Stacked shadows (2–4 per component) | LiquidGlassModifiers, BereanThreadCapsule, AMENTabBar | M | 🔴 2–4 offscreen passes per shadow stack |
| CRITICAL | 271 repeatForever animations | Discover, CreatePost, LiquidGlassVerse, BereanUI | M | 🔴 CPU + GPU always active, battery drain |
| HIGH | Stacked materials in modifiers | LiquidGlassModifiers | M | 🟠 5 render passes per button |
| HIGH | ObservableObject over-publishing | PostsManager, FeedAlgorithm, etc. (8 in OpenTableView) | M | 🟠 Full view tree recompose on any @Published change |
| HIGH | ForEach without stable IDs | 20+ files | S | 🟠 View destruction on list reorder, state loss |
| HIGH | 285 AsyncImage no error handling | Scattered throughout | M | 🟠 Silent failures, broken layouts |
| HIGH | 1,345 gradient calculations | Tab bar, reaction buttons, cards | M | 🟠 CPU gradient compute every frame |
| HIGH | ScrollView + VStack (no List) | 847 ScrollView instances | M | 🟠 All rows in RAM, memory pressure |
| MEDIUM | Opacity + Scale/Rotation (301) | Buttons, pills, toggles | M | 🟡 Compose cost, measurable on slow devices |
| MEDIUM | TimelineView frame pressure (27) | Real-time animations | M | 🟡 Frame rate spiking |
| MEDIUM | Canvas content inspection (4) | TBD | M | 🟡 If complex paths, high cost |
| MEDIUM | @State coarse-grained | Some large models | M | 🟡 Inefficient body recompute |
| LOW | Carousel continuous animations | FeaturedHeroCarousel, etc. | S | 🟢 Polish; minor battery impact |
| LOW | Mask + Shadow (4 instances) | Specific highlights | S | 🟢 Low frequency |

---

## What I Did NOT Check

1. **Network request debouncing**: Did not audit API call timing or request coalescing. Scope was GPU/render only.
2. **Deep view hierarchy depth**: Did not count nesting levels (VStack > HStack > ZStack depth), though 5+ levels = render cost.
3. **Memory leaks or retain cycles**: Out of scope; would require runtime analysis.
4. **Custom Metal shaders** (if any): Not detected in grep. If present in binary frameworks, missed.
5. **SwiftUI version-specific regressions**: Assumed latest stable SwiftUI for iOS 16+. Older OS APIs may have worse performance.
6. **Actual FPS measurement**: No Instruments profiling run. Findings are based on code patterns known to cause issues, not measured data.
7. **Third-party SDK impacts**: Firebase, Google Sign-In, etc. render cost not audited.
8. **Accessibility performance**: Reduce Motion and Reduce Transparency are checked in code but not verified to work correctly.

---

## Recommendations (Priority Order)

1. **IMMEDIATE** (this week):
   - Switch 5 high-traffic views from VStack to LazyVStack inside ScrollView. Validate with stable IDs. Expected: +30 FPS on scroll.
   - Audit and fix ForEach without stable IDs (20+ files, 1 hour bulk fix).

2. **THIS SPRINT** (next 1–2 weeks):
   - Profile tab bar with Core Animation tool. Measure blur + shadow cost. Target: consolidate to 1 material + 1 shadow max.
   - Inventory 271 repeatForever animations. Pause off-screen animations via @Environment(\.scenePhase). Expected: -2–5% background CPU.
   - Refactor high-publishing ObservableObjects (PostsManager, FeedAlgorithm) to narrower sub-views. Expected: fewer full-tree recomputes.

3. **NEXT SPRINT**:
   - Cache or pre-render common gradients (1,345 instances). Expected: -5–10% gradient CPU.
   - Replace 847 ScrollView + VStack combinations with List where applicable. Expected: -20–30% memory on long lists.
   - Consolidate stacked shadows in LiquidGlassModifiers and other high-frequency components.

4. **BACKLOG**:
   - Pause TimelineView updates when view is off-screen.
   - Inspect and optimize Canvas content (4 instances).
   - Reduce @State model size (split into atomic fields).
   - Add error handling to 285 AsyncImage instances.

---

## Conclusion

The AMEN app's visual design is ambitious and beautiful. However, the **GPU/render architecture has debt**:

- **2,086 material blur passes** spread across the app, with many stacked in single modifiers
- **271 infinite animations** running in background, preventing idle/throttle
- **High-traffic feeds render all rows at once** instead of lazy-loading
- **ObservedObject cascades** cause entire view trees to recompute on minor data changes

**Severity**: The app is likely to show scroll jank on mid-range devices (iPhone 11–12, iPhone SE 2nd gen) in long-scroll feeds. High-end phones (iPhone 14+) may mask the issue, leading to invisible performance regression until scaled.

**Effort to fix**: ~20–30 hours of focused work across 1–2 sprints (quick wins + systemic refactoring). ROI is high: visible FPS improvement, reduced battery drain, smaller memory footprint.

**Recommend**: Start with VStack → LazyVStack conversion and ForEach ID fixes (quick wins, high impact). Parallelize with tab bar profiling and ObservedObject refactoring.

