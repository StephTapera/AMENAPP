# Phase 2 — Agent H: BereanComposerTray.swift Fixes
2026-05-28

## Summary

Three fixes were applied to `/AMENAPP/BereanComposerTray.swift` addressing the critical performance issue P-07 and two design-system clarifications.

**Fix 1 — GoldPulse task leak (P-07, Critical):** Added `@State private var goldPulseTask: Task<Void, Never>? = nil` as a stored property. `startGoldPulse()` now calls `goldPulseTask?.cancel()` and resets `scriptureGoldPulse = false` before assigning a new task to `goldPulseTask`. The inner loop was refactored from a single `.toggle()` call into explicit `true`/`false` transitions with explicit `guard !Task.isCancelled else { break }` checks between sleeps, eliminating the race where `toggle()` could land in the wrong state after cancellation. `.onDisappear { goldPulseTask?.cancel() }` was added to `scriptureDetectedChip` so the loop is always cancelled when the chip leaves the view hierarchy. Previously, every `onChange(of: ref)` created a new competing loop with no cancellation path, causing unbounded concurrent task accumulation and CPU drain.

**Fix 2 — amenPurple token audit (DS-9):** Confirmed that `Color.amenPurple` is already defined as a global `extension Color` token in `ChurchNotesDesignSystem.swift` (`Color(hex: "A855F7")`). No private copy exists in `BereanComposerTray.swift`. A clarifying comment was added above `reasoningReadyChip` documenting that the global token is in use and the DS-9 promotion is already complete, preventing future agents from adding a redundant private copy.

**Fix 3 — Spring curve consistency:** The original `startGoldPulse()` used `.spring(response: 1.1, dampingFraction: 0.55)` — an overly slow, low-damping spring that produced sluggish, underdamped oscillation. This was replaced with `.spring(response: 0.42, dampingFraction: 0.82)` matching the tray's own `.animation` modifiers (line 113). No `.easeInOut` curves were present in the file; all interactive animations (mode chip selection, tray expand/collapse) already used spring physics. The shimmer pulse border now toggles via explicit `true`/`false` states with `guard !Task.isCancelled` protection rather than the previous `.toggle()` pattern.

## Files changed
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanComposerTray.swift`

## Lines affected
- Line 71–73: `@State private var goldPulseTask` property added
- Line 248: `.onDisappear { goldPulseTask?.cancel() }` added to `scriptureDetectedChip`
- Lines 254–255: DS-9 comment added above `reasoningReadyChip`
- Lines 607–628: `startGoldPulse()` fully rewritten with task cancellation, stored task assignment, and corrected spring parameters
