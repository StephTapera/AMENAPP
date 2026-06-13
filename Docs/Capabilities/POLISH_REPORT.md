# Capabilities v1 — Wave 3 Polish Report

**Date:** 2026-06-13
**Branch:** feature/berean-island-w0
**Agent:** Wave 3 POLISH

---

## Check 1: Motion Adaptive Compliance

### CapabilityPickerView
**PASS** — Both the `.transition(...)` and `.animation(value:)` modifiers already branch on `@Environment(\.accessibilityReduceMotion)`. Spring animations are replaced with `.easeInOut(duration: 0.2)` when motion is reduced.

### PrayerFollowUpBanner
**PASS (already correct in HEAD)** — Prior wave (b06925b7) already added `@Environment(\.accessibilityReduceMotion)` and the conditional `withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.25))`. Confirmed via `git show HEAD`.

### All other Capability views
**PASS** — No other `withAnimation` or `.spring(...)` calls found in VerseCardView, VerseLookupView, ContextSettingsView, PrayerOSCardSheet, or PrayerCardsListView.

---

## Check 2: Dynamic Type Compliance

### PrayerCardsListView — empty state icon
**FIXED** — `Image(systemName: "hands.and.sparkles").font(.system(size: 56))` replaced with `.font(.largeTitle).imageScale(.large)`. Fixed font sizes in SwiftUI SF Symbol images do not scale with the user's preferred text size; `.largeTitle` + `.imageScale(.large)` adapts automatically.

### All other text elements (all files)
**PASS** — All text uses semantic text styles: `.headline`, `.subheadline`, `.body`, `.caption`, `.footnote`, `.title3`. No other `.font(.system(size:))` violations found.

### frame(height:) clipping
**PASS** — Card rows and list rows use `.padding(.vertical:)` rather than `frame(height:)` constraints. The only `frame` usage is `frame(maxWidth: .infinity, maxHeight: .infinity)` (correct) and `frame(minHeight: 60)` in VerseCardView loading state (correct — min, not fixed).

---

## Check 3: Dark Mode Colors

### All Capability views
**PASS** — No hardcoded hex colors or `Color(red:green:blue:)` found. All background fills use semantic materials:
- `.regularMaterial` — adapts automatically
- `Color(uiColor: .systemBackground)` in ContextSettingsView loading overlay — adapts automatically
- `.quaternary`, `.secondary`, `.tertiary` foreground styles — adapt automatically
- `Color.accentColor` for tier badges — system accent, adapts automatically

---

## Check 4: iPad Layout — Presentation Detents

### VerseLookupView
**PASS (already correct in HEAD)** — Prior wave added `.presentationDetents([.medium, .large])` on the `NavigationStack` body. The view already has this as of HEAD commit (1bb97615).

### PrayerOSCardSheet (via PrayerCardsListView)
**PASS** — `PrayerOSCardSheet` wraps itself in `NavigationStack`, so on iPad it renders as a form sheet with the system-appropriate presentation style. Additionally, `PrayerCardsListView` and `PrayerCardDetailView` both add `.presentationDetents([.medium, .large])` to the sheet call site (already in HEAD).

---

## Check 5: Copy Review

**PASS** — Zero violations. `grep -rn "Lorem|lorem|placeholder|TODO:|FIXME:|test data|dummy"` on `AMENAPP/AMENAPP/Capabilities/**/*.swift` returned no matches. All user-visible copy is human-readable and faith-appropriate.

---

## Check 6: ContextSettingsView → Settings Navigation

**FIXED** — Added a `NavigationLink("Data & Context") { ContextSettingsView() }` to `PrivacySettingsView.swift`, placed in the DATA & ANALYTICS section after the analytics opt-out card. The block is gated behind `AMENFeatureFlags.shared.capabilitiesCoreEnabled` (default OFF). Includes a footer note explaining the feature's purpose.

File modified: `AMENAPP/PrivacySettingsView.swift`

---

## Check 7: GlassKit Consistency

### CapabilityPickerView
**PASS** — Uses `.glassSurface(cornerRadius: 16)` — the canonical app glass modifier from `DesignSystem/GlassMaterial.swift`. This is the correct pattern for floating panels.

### PrayerOSCardSheet, PrayerCardsListView, VerseLookupView
**PASS** — These are full-screen sheet/form surfaces. They correctly use `.background(.regularMaterial)` — the same pattern used throughout the app for form backgrounds (confirmed in PrivacySettingsView, ContextSettingsView). Applying `glassSurface` on a full-screen form would be incorrect.

### VerseCardView, PrayerFollowUpBanner, VerseInsertPreview
**PASS** — These are popover/card components. They use `.background(.regularMaterial, in: RoundedRectangle(...))` — consistent with inline card patterns used throughout the app. These are not floating panels so `glassSurface` is not the right modifier.

---

## Check 8: Zero-State Polish

### PrayerCardsListView — 0 cards
**PASS** — Has `Image(systemName: "hands.and.sparkles")` (now with `.font(.largeTitle).imageScale(.large)`), status-appropriate title text ("No active prayers" / "No answered prayers yet" / "No archived prayers"), subtitle copy, and a `.borderedProminent` "Start your first prayer" button.

### CapabilityPickerView — 0 capabilities
**PASS** — Has `Image(systemName: "puzzlepiece.extension")`, "No capabilities available" headline, and "Capabilities are rolled out gradually. Check back soon." body copy.

### VerseLookupView — before first search
**PASS (already correct in HEAD)** — Shows `instructionalState` when `query.isEmpty`: `Image(systemName: "text.book.closed")`, "Find a verse" headline, and explanatory body copy directing users to try "John 3:16" or "God is love".

---

## Summary

| Check | Result | File Changed |
|---|---|---|
| 1. Motion adaptive compliance | PASS | — |
| 2. Dynamic Type | FIXED | PrayerCardsListView.swift |
| 3. Dark mode colors | PASS | — |
| 4. iPad presentation detents | PASS | — |
| 5. Copy review | PASS | — |
| 6. ContextSettingsView in Settings | FIXED | PrivacySettingsView.swift |
| 7. GlassKit consistency | PASS | — |
| 8. Zero-state polish | PASS | — |

**Fixes committed:** 2
**DEFERRED:** 0
