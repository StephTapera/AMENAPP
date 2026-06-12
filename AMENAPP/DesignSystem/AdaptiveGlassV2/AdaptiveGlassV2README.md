# Adaptive Glass V2 — System Map

Gated by `adaptiveGlassV2Enabled` (default **OFF**). Flip only after the Wave 6 verification matrix passes for all 11 screens.

## Files

| File | Role |
|------|------|
| `SurfaceContracts.swift` | **Frozen Wave 0 types** — `Brightness`, `MediaKind`, `ScrollState`, `A11ySnapshot`, `SurfaceContext`, `GlassSurfaceState`, `SurfaceRole`, `\.glassSurfaceState` env key |
| `SurfaceStateResolver.swift` | Pure function `(SurfaceContext, SurfaceRole) → GlassSurfaceState`. All rules here, nowhere else. |
| `AdaptiveSurfaceEngine.swift` | `@Observable @MainActor` per-scene engine. Ingests scroll (throttled 50 ms), AmbientPalette bridge, keyboard notifications, a11y snapshot. Install via `.adaptiveSurfaceScene()`. |
| `AdaptiveSurfaceModifier.swift` | `.adaptiveSurface(role:)` — the only public adoption API. No-op when flag is OFF. |

## Rule priority (resolver)

1. A11y (`increaseContrast` / `reduceTransparency` / `contrastRisk`) → `.solidLight` — **always wins**
2. Video + `.bottomNav` → `.hidden`; video + `.topBar`/`.statusZone` → `.transparent`
3. Keyboard + `.bottomNav`/`.composerTray` → `.frosted` (relocate above keyboard)
4. Scroll × role matrix — `.atTop`, `.scrolling`, `.deep`

## Adoption pattern

```swift
// Scene root (ContentView already has this):
mainContent.adaptiveSurfaceScene()

// Feed scroll driver:
ScrollView { feedContent }.adaptiveSurfaceScrollDriver()

// Surface declaration (e.g. bottom nav):
AMENTabBar(...).adaptiveSurface(.bottomNav)

// Ambient palette bridge (media-bearing screens):
feedView.adaptiveSurfaceMediaBridge(palette: coordinator.palette, kind: .image)

// Custom renderer (reads state from env):
@Environment(\.glassSurfaceState) private var surfaceState
// → already wired in AMENTabBar.glassBackground
```

## Waves remaining

- **Wave 3** — Feed, Reels, Profiles: add `.adaptiveSurfaceScrollDriver()` + `.adaptiveSurface(.topBar)` on NavigationStack chrome; add `.adaptiveSurfaceMediaBridge()` on media-bearing PostCard/ReelCard
- **Wave 4** — Messages, Spaces, Composer: composerTray gets `.adaptiveSurface(.composerTray)` above keyboard
- **Wave 5** — Smart link cards: `.adaptiveSurface(.card)` on all smart card types
- **Wave 6** — Verification matrix: screenshot each of 11 screens × 7 states; flag stays OFF until matrix passes

## Tests

`AMENAPPTests/SurfaceStateResolverTests.swift` — 349 lines, exhaustive branch coverage (A11y overrides, video rules, keyboard transforms, all scroll × role × media combos, priority ordering invariants).
