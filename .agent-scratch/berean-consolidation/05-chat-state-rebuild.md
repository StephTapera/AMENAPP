# Berean Chat State Rebuild — Agent E Design Note

**Date:** 2026-05-28  
**Status:** Complete  
**Scope:** Active chat chrome consolidation — one surface visible at a time

---

## 1. Files Changed and Line Ranges

### `AMENAPP/BereanAIAssistantView.swift`

**Change 1 — Rule 5: Remove `BereanFollowUpView` from `inputBarView`**  
Original lines 1749–1758 (the `if showFollowUps...` block rendering `BereanFollowUpView` above the composer).  
Replaced with a single inline comment explaining the removal.

**Change 2 — Rule 2: Document `memoryStatusBanner` as intentionally dormant**  
Original line ~1515, the `memoryStatusBanner` computed property doc comment.  
Prepended a Rule 2 explanation stating the banner must never be wired into `inputBarView` as a standalone floating element. The property itself remains defined (not deleted) in case the capsule surface needs it as a delegate in future.

---

### `AMENAPP/BereanEnhancedComposerWrapper.swift`

**Change 1 — Rule 3 + Rule 5: Remove `responseModePickerView` and `followUpChipsView` from `body`**  
Original `body` VStack had three blocks before the suggestion chips and composer:
1. `if messageText.isEmpty && composerVM.state != .scrollingCompact { responseModePickerView }`
2. `if showFollowUps && !followUpSuggestions.isEmpty && messageText.isEmpty { followUpChipsView }`

Both blocks were removed from `body`. The private helper methods (`responseModePickerView`, `modeButton`, `followUpChipsView`, `followUpChipButton`) are retained as dead code so the bindings they reference (`responseMode`, `followUpSuggestions`, `showFollowUps`) remain valid in the struct interface. Replacing the removed blocks with inline Rule 3 and Rule 5 comments.

---

### `AMENAPP/BereanComposerBar.swift`

**Change 1 — Rule 4: Gate `BereanComposerTray` behind activation condition**  
The `BereanComposerTray` was previously always rendered as the first child of the `VStack` in `body`. It is now wrapped in an `if showActions || currentDraftIntent != .empty` guard.

- `showActions` is the existing state that becomes `true` when the "+" utility button is tapped.
- `currentDraftIntent != .empty` is true whenever the user has typed text that classifies as a question, scripture reference, prayer, or mode keyword.
- When both are false (idle composer, no text, "+" not tapped), the tray stays hidden.

Added `.animation(.amenSpring, value: showActions)` to the outer `VStack` so the show/hide transition uses the canonical spring token.  
Added `.animation(.amenSpring, value: currentDraftIntent)` to the tray itself so it re-animates when the intent changes while visible.

**Change 2 — Rule 4: Transition update**  
Changed the tray's `.transition` from `.opacity.combined(with: .move(edge: .bottom))` (unchanged from original) — kept the same transition but it now participates in the new visibility gate.

---

## 2. Before / After for Each Chrome Surface

### Capsule (BereanCompactComposerBar via BereanComposerTray)
- **Before:** Always visible above the composer, even when idle with no text. Showed quick-start chips ("Ask a question", "Study scripture", "Pray together") permanently.
- **After:** Only visible when `showActions == true` (user tapped "+") OR `currentDraftIntent != .empty` (user has typed something classifiable). Idle state: hidden. Intent detected: appears with spring animation.

### Composer Tray — Mode Picker Row
- **Before:** The `BereanComposerTray.modePickerRow` was shown whenever `draftIntent == .empty` (i.e., always when idle). This was a permanently visible mode indicator outside the capsule, violating Rule 3.
- **After:** The tray itself is hidden when idle, so the mode picker row is inaccessible in idle state. Mode selection is accessible via "+" → tray appears → mode chips visible.

### Composer — Follow-Up Chips (two removal sites)
- **Before (site 1):** `BereanAIAssistantView.inputBarView` rendered `BereanFollowUpView` above the composer whenever `showFollowUps && !followUpSuggestions.isEmpty && messageText.isEmpty`. This produced a chip row floating above the input bar.
- **Before (site 2):** `BereanEnhancedComposerWrapper.body` rendered `followUpChipsView` above the composer when `showFollowUps && !followUpSuggestions.isEmpty && messageText.isEmpty`. This was a second, functionally duplicate chip row.
- **After:** Both chip rows above the composer are removed. The canonical chip set is `BereanFollowUpChipRow` which `BereanAIAssistantView.messageBubbleRow` renders inline at the bottom of the last assistant message (lines 568–576, unchanged). This is the correct placement — chips appear inside the message thread, not floating above the input.

### Composer — Response Mode Picker (in `BereanEnhancedComposerWrapper`)
- **Before:** A `responseModePickerView` (horizontal capsule chip row: Quick / Balanced / Detailed / Study / Devotional) was shown above the composer whenever `messageText.isEmpty && composerVM.state != .scrollingCompact`. This was a second mode-indicator surface, violating Rule 3.
- **After:** The row is removed from `body`. Mode selection occurs via the capsule (BereanComposerTray inside BereanCompactComposerBar).

### Memory Indicator (`memoryStatusBanner`)
- **Before:** Defined as a private computed property in `BereanAIAssistantView` but NOT wired into any render path (already dormant).
- **After:** Remains dormant. A Rule 2 doc comment has been added explicitly prohibiting future callers from placing it outside the capsule.

---

## 3. Compromises

### `BereanSmartFollowUpChips` in `BereanComposerBar` (lines 111–115)
`BereanCompactComposerBar` has a `followUpChips: [String]` parameter. `BereanChatView` passes `composerFollowUpChips` into it, which renders `BereanSmartFollowUpChips` above the composer bar. This is technically a Rule 5 violation (chips above composer instead of inline at bottom of last message).

However, `BereanChatView` is not in the Agent E target file list, and modifying it would require re-wiring `BereanChatView.messageBubbleRow` to display `BereanFollowUpChipRow` inline — that is a separate refactor. This path is left unchanged with a non-change note below.

### `BereanComposerTray` tray still appears on "+" tap before sheet opens
When the user taps "+", `showActions` becomes true, momentarily revealing the tray before the tools sheet covers it. This is intentional per Rule 4 ("+ button has just been tapped"). The brief flash is correct behavior.

---

## 4. Non-Changes

### `BereanChatView.swift` — `composerFollowUpChips` / `BereanSmartFollowUpChips`
Expected to find a chips-above-composer violation here. Found it (lines 2843–2847 wiring `composerFollowUpChips` into `BereanCompactComposerBar.followUpChips`, which renders `BereanSmartFollowUpChips` above the bar). Left unchanged — `BereanChatView` is not in the Agent E target file list. Agent F should schedule this as a follow-up: move `BereanSmartFollowUpChips` rendering from `BereanCompactComposerBar` into `BereanChatView.messageBubbleRow` inline.

### `BereanFollowUpChips.swift` — `BereanFollowUpChipRow`
Left entirely unchanged. It is already the correct inline implementation (placed at the bottom of the last assistant message bubble in `BereanAIAssistantView.messageBubbleRow`). No modifications needed.

### `BereanMemoryStripView.swift`
Left entirely unchanged. The strip is used in `BereanAIAssistantView` only via the `memoryNodes` state that feeds `BereanMessageBubbleView`. There is no standalone `BereanMemoryStripView` instance floating outside the message area in the target files. The Rule 2 concern (memory chip appearing as a separate floating chip) relates to `memoryStatusBanner` which was already dormant.

### `AIBibleStudyView.swift` — typing dots animation in `LightChatContent`
The three-dot bounce animation (lines 791–804) inside `LightChatContent` is an inline streaming indicator embedded within the message bubble area — it is NOT a mode indicator. It is not a Rule 3 or Rule 4 violation. Left unchanged.

### `AIBibleStudyView.swift` — empty state (`BereanEmptyState`)
Not touched. Agent D owns empty state rendering.

### All streaming/SSE pipeline code
Not touched.

### `BereanFollowUpChips.swift`, `BereanVoiceInputSheet.swift`, `BereanToolsHub.swift`
Not touched. These are independent sheets with no chrome redundancy.

### Spring physics / animation constants in morphing capsule
Not touched. Only show/hide conditions and placement were changed.

---

## 5. Verification Steps for Canvas / Simulator

1. **Idle state (no messages, no text typed):** Launch `BereanAIAssistantView`. The `BereanComposerTray` (chip row + mode picker) should NOT be visible. Only the composer bar (text field + mic + send) should be present above the AI disclosure line.

2. **Tray appears on "+" tap:** Tap the "+" button. The tray should animate in from below using `.amenSpring`. The tools sheet should then appear.

3. **Tray appears on typing:** Type a question ("Why did..."). The `currentDraftIntent` becomes `.question`, revealing the tray with spring animation. Type "pray" — tray shows prayer chips.

4. **Follow-up chips inline only:** After a Berean response completes, chips (Go deeper, Simplify, Make a prayer) should appear at the BOTTOM of the last assistant message bubble, not floating above the input bar.

5. **No mode picker above composer:** After a response, the `responseModePickerView` row (Quick / Balanced / etc.) should not appear above the composer in `BereanAIAssistantView`.

6. **Memory indicator:** The `memoryStatusBanner` should never appear. If memory state needs to be shown, it should be inside the capsule text only.

7. **Streaming state:** While `isGenerating == true`, the composer tray hides (message text was cleared on send, `currentDraftIntent == .empty`, `showActions == false`). Composer bar remains visible with stop button. No other chrome appears above it.
