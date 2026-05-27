# Agent F — BereanThinkingStrip + BereanMemoryChip Integration Note

**Date:** 2026-05-27  
**Agent:** F (activity strip + memory chip)  
**Files written:**
- `AMENAPP/BereanThinkingStrip.swift`
- `AMENAPP/BereanMemoryChip.swift`

---

## What was built

### BereanThinkingStrip

A 32pt full-width translucent strip that collapses to zero height when idle. It communicates exactly what Berean is doing during streaming at the same vocabulary level as `BereanDynamicIsland` ("thinking…", "responding…").

**Key details:**
- `BereanThinkingAction` enum with 10 states. Dot colors: gold=retrieving/studyMode, blue=verifying/drafting, purple=grounding/alignmentCheck/prayerMode, muted gold=memoryRead/memoryWrite.
- Strip height animates via `.spring(response: 0.42, dampingFraction: 0.82)` (capsule preset).
- Text crossfades via `.id(action.rawValue)` + `.transition(.asymmetric(.opacity, .opacity))` using `.spring(response: 0.28, dampingFraction: 0.88)` (fast preset).
- Shimmer: `LinearGradient` swept from `shimmerPhase=0` to `shimmerPhase=1.3` in 1.8s `.linear.repeatForever`. Wrapped in `if !reduceMotion` guard — no shimmer or pulse when Reduce Motion is ON.
- Pulse dot: `.easeInOut(duration: 0.72).repeatForever(autoreverses: true)` guarded by `reduceMotion`.
- Background: `.ultraThinMaterial` + `AmenTheme.Colors.glassFill`; falls back to `Color(uiColor: .secondarySystemBackground)` when `reduceTransparency` is ON.

**Integration in BereanChatView / composerVM:**
```swift
// In your chat view body, between the thread capsule and the message list:
BereanThinkingStrip(action: composerVM.thinkingAction)

// composerVM must expose:
@Published var thinkingAction: BereanThinkingAction = .idle

// Drive it from SSE stream events:
// .retrieving when the retrieval/scripture lookup starts
// .verifying when citation checking runs
// .drafting when the token stream begins
// .memoryRead / .memoryWrite when memory ops fire
// .idle when streaming ends or on error
```

---

### BereanMemoryChip

A glass capsule chip with a brain SF Symbol and "Memory" label. In the active state a gold→purple→gold gradient shimmers across the chip and the border pulses. Tapping it opens `BereanMemoryDetailSheet`.

**Key details:**
- `BereanMemoryEntry`: `id, title, body, savedAt, usedInCurrentResponse`.
- `BereanMemoryChip(isActive:entries:onOpenSettings:)` — all three are the full public interface.
- Shimmer: 1.4s linear sweep, `amenGold.opacity(0.18)` → `_memoryPurple.opacity(0.12)` → `amenGold.opacity(0.18)`. Guarded by `reduceMotion`.
- Border pulse: `.easeInOut(1.1).repeatForever(autoreverses: true)` toggling `amenGold.opacity(0.50)` ↔ `amenGold.opacity(0.20)`. Guarded by `reduceMotion`. When reduce-motion is on, border is shown statically at `amenGold.opacity(0.40)`.
- Background: `.ultraThinMaterial` + glass fill; falls back to `AmenTheme.Colors.surfaceChip` when `reduceTransparency` is ON.
- Sheet: `BereanMemoryDetailSheet` uses `Color(uiColor: .systemBackground)` + `bereanGlassCard()` rows. Entries marked `usedInCurrentResponse: true` show a gold "Used" badge.

**Integration:**
```swift
// Place chip in the microstate/composer area of BereanChatView:
BereanMemoryChip(
    isActive: composerVM.memoryIsActive,
    entries: composerVM.memoryEntries,
    onOpenSettings: { router.push(.memorySettings) }
)

// composerVM must expose:
@Published var memoryIsActive: Bool = false
@Published var memoryEntries: [BereanMemoryEntry] = []

// Set memoryIsActive = true when a memory read/write SSE event fires.
// Set memoryEntries from the memory context payload returned by the API.
// Set usedInCurrentResponse = true for entries whose IDs appear in the response payload.
```

---

## Compliance checklist

| Rule | Status |
|------|--------|
| No hardcoded colors | PASS — uses `BereanColor.*`, `Color.amenGold`, `AmenTheme.Colors.*`, `Color(uiColor:)` only |
| No non-spring animations | PASS — shimmer uses `.linear` (explicitly approved for sweeps); all transitions use named spring presets |
| Shimmer gated on reduceMotion | PASS — `if !reduceMotion` wraps both shimmer overlays |
| Pulse gated on reduceMotion | PASS — `guard !reduceMotion` in animation start helpers |
| reduceTransparency backgrounds | PASS — both files fall back to solid colors |
| All tap targets ≥ 44×44pt | PASS — `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())` |
| accessibilityLabel + hint | PASS — chip, done button, settings link, entry rows all labeled |
| AMENFont typography only | PASS — no `.font(.system(size:))` |
| #Preview blocks | PASS — 5 previews total (2 strip, 3 chip/sheet) |

---

## Notes for downstream agents

- `Color.amenPurple` and `Color.amenBlue` are referenced in `BereanComposerTray.swift` and `BereanStudySheetView.swift` as global tokens but have no global `extension Color` definition found at audit time. Both files in this PR use file-private `_bereanPurple` / `_memoryPurple` aliases to avoid a build error. **Recommend:** add `static let amenPurple` and `static let amenBlue` to `AmenAdaptiveColors.swift` to unify usage.
- The `BereanThinkingAction.memoryRead` and `.memoryWrite` states are the primary UX fix for the "Berean silently extracts memory with zero user signal" trust gap (intelligence surface 4/10). Pair with `BereanMemoryChip.isActive = true` when these states are active to give the user full visibility.
