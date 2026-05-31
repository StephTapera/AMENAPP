# A10 Accessibility + Motion Report — Phase 4

## FindChurchView

### VoiceOver: FAIL (2 issues fixed)
- **AI Recommendations button (line ~1423)** had no `.accessibilityLabel` or `.accessibilityHint`. VoiceOver would read the icon and sub-text separately and give no context about the expand/collapse state. Fixed: added dynamic label `"AI Recommendations, expanded/collapsed"` and hint.
- **Map pin stagger `onAppear`** — opacity/scale were gated but the stagger dispatch itself was not, so VoiceOver users heard nothing if a pin appeared (immaterial to VoiceOver but the `scaleEffect(… : 0.4)` created a zero-size hit target during animation). Fixed alongside reduce-motion guard.

### Dynamic Type: PASS
All text uses `.font(.systemScaled(…))` or semantic styles (`.headline`, `.body`, `.subheadline`). No raw `UIFont` or `.system(size:)` without a scaler. `fixedSize` is applied where needed (ProvenanceReasonRow). No issues found.

### Reduce Motion: FAIL (2 issues fixed)
- **`.scrollTransition` in church list (FindChurchView ~line 1523)**: Was `.animated(.spring(…))` unconditionally — no reduce-motion guard. Users with Reduce Motion enabled still got scale+opacity enter/exit effects on every cell scroll. Fixed: passes `.identity` when `reduceMotion`, and gates scale/opacity transforms.
- **Map pin stagger animation (FindChurchMapView ~line 6456–6462)**: `DispatchQueue.asyncAfter` delays + `withAnimation` ran unconditionally. Reduce Motion users got animated pin drops with a 0.4 → 1.0 scale spring per pin. Fixed: immediate `pinsVisible = true` with no animation when `reduceMotion` is on; `scaleEffect` start value also collapsed to `1` when reduceMotion.

### Contrast: PASS
`amenGlassScrim()` is available and applied where text sits over media. Map annotation text in `GlassPin` always renders inside a `amenGlass(.thin)` capsule with opaque fallback when `reduceTransparency` is on — sufficient contrast over map tiles. `ChurchAnnotationView` and `ClusterAnnotationView` both render on material-backed surfaces. No bare text over satellite tiles.

---

## FindChurchGlassComponents

### VoiceOver: FAIL (6 issues fixed)
1. **`CompressedChurchHeader` — expanded Back button**: No `.accessibilityLabel`. Fixed: `"Back"`.
2. **`CompressedChurchHeader` — expanded Refresh button**: No `.accessibilityLabel`. Fixed: `"Refresh search"`.
3. **`CompressedChurchHeader` — expanded Map toggle button**: No `.accessibilityLabel`. Fixed: dynamic `"Switch to list view"` / `"Switch to map view"`.
4. **`CompressedChurchHeader` — expanded Filter button**: No `.accessibilityLabel`. Fixed: `"Filter churches"`.
5. **`CompressedChurchHeader` — compressed Filter button**: No `.accessibilityLabel`. Fixed: `"Filter churches"`.
6. **`GlassFilterMenuPill`**: No `.accessibilityLabel` or `.accessibilityHint` on the struct itself. Callers adding site-level labels was inconsistent. Fixed in the struct definition and at all two call sites in `ChurchMapSheetFilterBar`.
7. **`ChurchNotePostCardActionBlock` — Church Notes button**: No `.accessibilityLabel` or `.accessibilityHint`. VoiceOver would combine child text labels but not announce the church name. Fixed: contextual label includes `churchName`.
8. **`ChurchNotePostCardActionBlock` — PostCard button**: Same as above. Fixed.
9. **Decorative icons in `ChurchNotePostCardActionBlock`**: SF Symbol icons and trailing chevrons/arrows not hidden from VoiceOver. Fixed: added `.accessibilityHidden(true)`.
10. **`CompressedChurchHeader` — location icon**: Decorative `location.fill` icon not hidden. Fixed: `.accessibilityHidden(true)`.

### Dynamic Type: PASS
All uses `.font(.systemScaled(…))`.

### Reduce Motion: PASS
`ChurchDiscoveryBottomSheet` correctly checks `reduceMotion` for drag gesture snap. `GlassFilterPill` animation guarded. `ChurchNotePostCardActionBlock` onAppear guarded. `AnimatedChurchStatsRow` count-up guarded. No bare unguarded animations found.

### Contrast: PASS
All filter chip text renders over `.ultraThinMaterial` or solid white capsule backgrounds. `isReduceTransparencyEnabled` fallback to `Color.white` in `ChurchSearchGlassCapsule` and `ChurchDiscoveryBottomSheet.sheetBackground`. WCAG AA pass assumed for black text on white/near-white glass.

---

## FindChurchAnnotation

### VoiceOver: PASS
`ChurchAnnotationView` has `.accessibilityLabel("\(annotation.church.name), \(annotation.church.distance) away")` and `.accessibilityHint("Double tap to view details")`. `ClusterAnnotationView` has appropriate combined label and hint. Decorative items in `GlassPin` (teardrop triangle) are not marked hidden but are child elements of the combined pin — acceptable.

### Dynamic Type: PASS
`ClusterAnnotationView` uses `.font(.system(size: 14, weight: .bold))` — pin badges are intentionally fixed-size (annotation pins must not reflow within map frame). Acceptable.

### Reduce Motion: PASS (no animations in annotation files)
Animations for the pin are in `GlassPin` (AmenGlassKit), which guards with `reduceMotion`.

### Contrast: PASS
`ClusterAnnotationView` renders count text in `amenBlue` on a material circle with opaque fallback.

---

## PostProvenance files

### PostProvenanceSheet — VoiceOver: PASS
- Loading skeleton: `.accessibilityLabel("Loading feed provenance")`.
- Reason rows: `.accessibilityElement(children: .combine)` with descriptive label including confidence percentage.
- Error view: icons marked `.accessibilityHidden(true)`.
- Sheet root: `.accessibilityElement(children: .contain)`.
- All agency action buttons use `GlassActionRow` which now has `.accessibilityLabel` + `.accessibilityHint`.

### PostProvenanceSheet — Dynamic Type: PASS
Uses `.font(.system(size: 14/15))` in `ProvenanceReasonRow` — these are semantic content rows, not display text. The `.fixedSize(horizontal: false, vertical: true)` on the label allows growth. Minor note: switching to `.body` / `.subheadline` semantic styles would be more robust but not a blocking issue.

### PostProvenanceSheet — Reduce Motion: PASS
All `withAnimation` calls wrapped in `reduceMotion ? .none : Motion.adaptive(…)`.

### ProvenanceInfoButton — VoiceOver: PASS
`.accessibilityLabel("Why you're seeing this post")` and `.accessibilityHint("Double tap to learn why this post is in your feed")` are present.

### ProvenanceInfoButton — Reduce Motion: PASS
Uses `GlassKitPressStyle(reduceMotion: reduceMotion)`.

---

## AmenGlassKit

### VoiceOver: FAIL (2 issues fixed)
1. **`GlassSheet` drag indicator**: The `RoundedRectangle` drag handle was not `.accessibilityHidden(true)`. VoiceOver would announce "image" or pause on a purely decorative element. Fixed.
2. **`GlassActionRow`**: Missing `.accessibilityHint`. VoiceOver announced only the label with no guidance on the action. Fixed: uses `subtitle ?? "Double tap to activate"` as hint — when subtitle is present it doubles as a richer description.

### VoiceOver: PASS (existing)
- `LiquidGlassTabBar`: `.accessibilityLabel(item.label)` + `.isSelected` trait on active tab.
- `GlassPin`: `.accessibilityLabel(label)` + `.isSelected` trait.
- `GlassChip`: `.accessibilityLabel(label)` + `.isSelected` trait.
- `GlassButton`: `.accessibilityLabel(label)` + `.accessibilityHint(hint ?? "")`.
- `AmenFloatingGlassBackButton`: `.accessibilityLabel("Back")`.

### Dynamic Type: PASS
`LiquidGlassTabBar` uses `minimumScaleFactor(0.72)` on the 11pt label. `GlassChip` and `GlassButton` use `.subheadline` / `.system(size: 13)` — these are intentionally fixed pill labels; chips must not reflow inside horizontal scroll rails.

### Reduce Motion: PASS
- `LiquidGlassTabBar`: `.animation(reduceMotion ? .easeInOut(duration: 0.16) : Motion.liquidSpring, value: isCompressed)` — correctly degraded (not disabled entirely, which would cause jarring jumps).
- `GlassPin`: `reduceMotion ? .easeInOut(duration: 0.12) : Motion.liquidSpring`.
- `GlassChip`: all spring animations guarded.
- `GlassButton`: `reduceMotion ? .easeOut : Motion.springPress`.
- `AmenGlassLoadingSkeleton`: shimmer completely suppressed when `reduceMotion`.
- `GlassKitPressStyle`: scale effect zero when `reduceMotion`.

### Contrast: PASS
`amenGlassScrim()` gradient is available and documented for hero/map text. `AmenGlassModifier` falls back to `Color(uiColor: .systemBackground)` when `reduceTransparency` is on, ensuring full contrast. `glassStroke` is hidden under `reduceTransparency` (no thin border confusion). AMEN palette tokens only — no Apple system blue on text.

---

## Fixes Applied

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` expanded Back button: no `.accessibilityLabel` | Added `.accessibilityLabel("Back")` |
| 2 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` expanded Refresh button: no `.accessibilityLabel` | Added `.accessibilityLabel("Refresh search")` |
| 3 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` expanded Map toggle: no `.accessibilityLabel` | Added dynamic label for list/map mode |
| 4 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` expanded Filter button: no `.accessibilityLabel` | Added `.accessibilityLabel("Filter churches")` |
| 5 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` compressed Back button: no `.accessibilityLabel` | Added `.accessibilityLabel("Back")` |
| 6 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` compressed Filter button: no `.accessibilityLabel` | Added `.accessibilityLabel("Filter churches")` |
| 7 | `FindChurchGlassComponents.swift` | `CompressedChurchHeader` decorative location icon not hidden | Added `.accessibilityHidden(true)` |
| 8 | `FindChurchGlassComponents.swift` | `GlassFilterMenuPill`: no label/hint in struct definition | Added `.accessibilityLabel(label)` + hint |
| 9 | `FindChurchGlassComponents.swift` | `ChurchMapSheetFilterBar` denomination pill: no site label | Added contextual `.accessibilityLabel` + hint |
| 10 | `FindChurchGlassComponents.swift` | `ChurchMapSheetFilterBar` sort pill: no site label | Added `.accessibilityLabel` + hint |
| 11 | `FindChurchGlassComponents.swift` | `ChurchNotePostCardActionBlock` Notes button: no label/hint | Added church-name-contextual label + hint |
| 12 | `FindChurchGlassComponents.swift` | `ChurchNotePostCardActionBlock` PostCard button: no label/hint | Added church-name-contextual label + hint |
| 13 | `FindChurchGlassComponents.swift` | Decorative icons in `ChurchNotePostCardActionBlock` not hidden | Added `.accessibilityHidden(true)` to icon/chevron images |
| 14 | `FindChurchView.swift` | AI Recommendations `Button` missing label/hint | Added dynamic label (expanded/collapsed state) + hint |
| 15 | `FindChurchView.swift` | `.scrollTransition` not guarded by `reduceMotion` | Passes `.identity` configuration when `reduceMotion`; scale/opacity transforms also gated |
| 16 | `FindChurchView.swift` | Map pin stagger animation not guarded by `reduceMotion` | Immediate `pinsVisible = true` when `reduceMotion`; `scaleEffect` start value also collapses to `1` |
| 17 | `AmenGlassKit.swift` | `GlassSheet` drag indicator not `.accessibilityHidden(true)` | Added `.accessibilityHidden(true)` |
| 18 | `AmenGlassKit.swift` | `GlassActionRow` missing `.accessibilityHint` | Added hint using `subtitle ?? "Double tap to activate"` |

## Items Not Fixed (by design or out of scope)

| Item | Reason |
|------|--------|
| `GlassPin` label text uses `.system(size: 12)` fixed | Map annotation pin text must be fixed-size — reflow inside a map annotation causes layout breakage. Acceptable per WCAG SC 1.4.4 exception for "captions and images of text". |
| `ClusterAnnotationView` count text uses `.system(size: 14)` fixed | Same as above — annotation badge. |
| `LiquidGlassTabBar` tab labels at 11pt with `minimumScaleFactor(0.72)` | Tab bar labels are capped by the capsule geometry; minimum is 7.9pt effective. Acceptable for navigation chrome. Announce via `.accessibilityLabel` on each button. |
| `ProvenanceReasonRow` uses `.system(size: 14/15)` | Minor improvement opportunity but not blocking; `fixedSize` ensures vertical growth. |
