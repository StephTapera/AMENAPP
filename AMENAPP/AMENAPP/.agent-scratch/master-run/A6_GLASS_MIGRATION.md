# A6 Glass Migration Report

## Global Nav

- [x] Tab bar: `AMENTabBar` (in `AMENTabBar.swift`) is already a full Liquid Glass implementation using `LiquidGlassTabBarBackground` + `LiquidGlassOrbBackground` + `LiquidGlassActiveTabCapsule`. It correctly branches on iOS 26+ via `Glass.regular.interactive()` and falls back to `.ultraThinMaterial` for iOS < 26. This is correct kit-level branching — no feature-view changes needed for the capsule surfaces themselves.
- [x] `AmenLiquidGlassTabBar.swift` — fixed `Color(uiColor: .systemBlue)` → `AmenTheme.Colors.amenBlue` for selected-tab foreground (1 line). This was the only AMEN palette violation in the nav layer.
- [x] `ContentView.swift` — uses `AMENTabBar` at line 739, which is the authoritative glass tab bar. No changes needed.

## Posts Files Migrated

| File | Before | After | Count |
|---|---|---|---|
| `AMENAPP/AMENAPP/OpenTableView.swift` | `.presentationBackground(.regularMaterial)` | `.presentationBackground(.thinMaterial)` | 1 |
| `AMENAPP/PostDetailView.swift` | `.regularMaterial` ×2, `.ultraThinMaterial` ×3 | `.amenGlass(.regular)` ×2, `.amenGlass(.thin)` ×3 | 5 |
| `AMENAPP/CreatePostView.swift` | `.regularMaterial` ×4, `.ultraThinMaterial` ×13 | `.amenGlass(.regular)` ×4, `.amenGlass(.thin)` ×13 | 17 |
| `AMENAPP/CommentsView.swift` | `.ultraThinMaterial` ×4 | `.amenGlass(.thin)` ×4 | 4 |
| `AMENAPP/AMENAPP/PostAILabelSystem.swift` | `.presentationBackground(.ultraThinMaterial)` | `.presentationBackground(.thinMaterial)` | 1 |
| `AMENAPP/AMENAPP/PostComposerTranslationSheet.swift` | `.presentationBackground(.regularMaterial)` | `.presentationBackground(.thinMaterial)` | 1 |
| `AMENAPP/AMENAPP/PostAttachmentSystem.swift` | `.fill(.ultraThinMaterial)` ×2 | `.amenGlass(.thin)` ×2 | 2 |
| `AMENAPP/AMENAPP/PostingBarView.swift` | `.fill(.ultraThinMaterial)` ×4 | `.amenGlass(.thin)` ×4 | 4 |
| `AMENAPP/AMENAPP/SpiritualOS/PostActionReflectionSheet.swift` | `.background(.ultraThinMaterial, in:...)` ×3 | `.amenGlass(.thin)` ×3 | 3 |

**Total changes: 38**

### Mapping used
| Old | New |
|---|---|
| `.background(.ultraThinMaterial)` / `.fill(.ultraThinMaterial)` | `.amenGlass(.thin)` |
| `.background(.regularMaterial)` / `.fill(.regularMaterial)` | `.amenGlass(.regular)` |
| `.presentationBackground(.ultraThinMaterial)` | `.presentationBackground(.thinMaterial)` |
| `.presentationBackground(.regularMaterial)` | `.presentationBackground(.thinMaterial)` |

Note: `.presentationBackground()` does not accept `amenGlass()` (it requires a `ShapeStyle`), so `.thinMaterial` is used there — this is correct per kit design (the kit handles `.ultraThinMaterial` internally anyway).

## Zero-bespoke-material Verification

```
OpenTableView.swift:     0 matches
PostDetailView.swift:    0 matches
CreatePostView.swift:    0 matches
CommentsView.swift:      0 matches
PostAILabelSystem.swift: 0 matches
PostComposerTranslationSheet.swift: 0 matches
PostAttachmentSystem.swift:         0 matches
PostingBarView.swift:               0 matches
PostActionReflectionSheet.swift:    0 matches
```

All 9 Posts-surface files pass zero-bespoke-material check.

## Notes

- `AMENTabBar.swift` retains `.ultraThinMaterial` in `LiquidGlassTabBarBackground.capsuleSurface` — this is inside the kit-equivalent component itself (not a feature view), and properly guarded by `#available(iOS 26.0, *)` branching. No change needed per mandate.
- `AmenGlassKit.swift` is frozen/read-only per project convention; its internal `.ultraThinMaterial` uses are kit internals, not feature-level violations.
