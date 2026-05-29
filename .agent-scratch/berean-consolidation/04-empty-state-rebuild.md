# 04-empty-state-rebuild.md
# Berean Empty State Rebuild — Agent D

**Date:** 2026-05-28  
**Status:** Complete  
**Above-fold element count: 6**

---

## Final Above-Fold Element Allocation

| # | Element | Source |
|---|---------|--------|
| 1 | Nav bar | Existing, unchanged |
| 2 | Tab selector (lightTabSelector) | AIBibleStudyView — existing, unchanged |
| 3 | Hero block (BereanHeroGreetingView) | BereanLandingView + BereanLandingEmbedded — existing, unchanged |
| 4 | Follow-up subtitle (greeting.followUp) | Inside BereanHeroGreetingView — existing, unchanged |
| 5 | Suggestion chip row (quickChips) | NEW inline horizontal ScrollView of 5 pill chips |
| 6 | Composer input (BereanInputBar / LightGlassmorphicChatInput) | Existing, unchanged |

Note: The BereanLandingView standalone path counts the status bar as implicit (system), giving exactly 6 visible user-visible elements. The AIBibleStudyView path uses the tab selector as element 2 instead of a status capsule.

---

## Elements Removed and Where Their Function Now Lives

### 1. BereanSuggestionPanel (focus-triggered modal overlay)
- **Was:** A floating panel with two sections — category chips (5 pills: Bible, Prayer, Wisdom, Notes, Hope) and suggested prompt rows (5 full-text rows with icons and arrow). Only visible when the input was focused.
- **Removed from:** `BereanLandingView.body` — the `if suggestionsVisible { BereanSuggestionPanel(...) }` block.
- **Function now lives in:** The always-visible `quickChips` ScrollView row (element 5). The 5 chip labels ("Ask a question", "Study scripture", "Explain simply", "Explore context", "Build a prayer") cover all the major intent categories from the old panel. The prompts pre-fill the input on tap, matching old behavior.

### 2. BereanContextStrip ("Scripture-grounded · Always discerning")
- **Was:** A thin caption strip with a sparkles icon and tagline text, fading in below the suggestion panel and above the input bar.
- **Removed from:** `BereanLandingView.body` — the `BereanContextStrip(label: ..., icon: ...)` call.
- **Function now lives in:** Nowhere (deliberately). This was purely decorative informational text with no interactivity. The hero subtitle line ("How can I help today?" etc.) already establishes the Berean identity and tone. Adding a second tagline line was redundant.

### 3. bereanSuggestedPrompts array (5 full-text prompt rows)
- **Was:** Private array of `BereanSuggestedPrompt` structs used by `BereanSuggestionPanel`.
- **Removed from:** `BereanLandingView.swift` — lines 629–632 of the original file.
- **Function now lives in:** The `quickChips` array's `prompt` values (partial prompts like "Help me study ", "Explain this simply: ") cover the same use case with shorter labels.

### 4. bereanCategoryChips array (5 category filter chips)
- **Was:** Private array of tuples (Bible, Prayer, Wisdom, Notes, Hope) used as the top row inside `BereanSuggestionPanel`.
- **Removed from:** `BereanLandingView.swift`.
- **Function now lives in:** The `quickChips` row covers the intent categories. Church Notes context is accessible via the "+" Tools button in the composer (BereanToolsHub Church cluster). The category filter concept is replaced by mode selection (behind the "Berean" nav title tap).

### 5. BereanSuggestedPrompt struct
- **Was:** Private Identifiable model for the prompt rows in `BereanSuggestionPanel`.
- **Removed from:** `BereanLandingView.swift`.
- **Replaced by:** Inline `(icon: String, label: String, prompt: String)` tuples in the `quickChips` array.

### 6. BereanEmptyState struct (AIBibleStudyView.swift lines 657–751)
- **Was:** An older, duplicate empty state component with a hero glyph ("B"), headline "Ask Berean", subtitle, and 6 suggestion chips. It was NOT used — `BereanLandingEmbedded` had already replaced it at the call site.
- **Removed from:** `AIBibleStudyView.swift`.
- **Function now lives in:** `BereanLandingEmbedded` (which was already the active implementation).

---

## Every File + Line Range Changed

### `/AMENAPP/BereanLandingView.swift`

| Change | Original lines | Description |
|--------|---------------|-------------|
| Added `quickChips` property | After line 71 | 5 quick-action chip tuples defined as instance property on BereanLandingView |
| Replaced body's bottom chrome | Lines 129–176 (original) | Removed `BereanSuggestionPanel` + `BereanContextStrip` block; replaced with inline `quickChips` ScrollView + `BereanInputBar` |
| Removed `BereanSuggestedPrompt`, `bereanSuggestedPrompts`, `bereanCategoryChips`, `BereanSuggestionPanel` | Lines 608–718 (original) | All private chip data and panel view replaced with one-line comment |
| Updated `BereanLandingEmbedded` | Lines 909–947 (original) | Added `quickChips` property, `chipsVisible` state, and the suggestion chip row ScrollView between hero and bottom spacer. Chips stagger in after `onSequenceComplete` fires. |

### `/AMENAPP/AIBibleStudyView.swift`

| Change | Original lines | Description |
|--------|---------------|-------------|
| Removed `BereanEmptyState` struct | Lines 655–751 (original) | Replaced with one-line comment. The type was unused; `BereanLandingEmbedded` is the active empty state. |

---

## Edge Cases and Compromises

### 1. suggestionsVisible state is retained but repurposed
The `suggestionsVisible` `@State` variable was originally used to show/hide `BereanSuggestionPanel`. It is now used solely to hide/show the `quickChips` row (chips fade out when the input is focused, so the keyboard does not push them into a crowded stack with the suggestion panel). This preserves existing focus-awareness behavior.

### 2. BereanLandingView vs. BereanLandingEmbedded chip styling
`BereanLandingView` chips use `.ultraThinMaterial` + `glassFill` + `glassStroke` (matching the existing BereanContextStrip and suggestion chip style on the landing page's light background). `BereanLandingEmbedded` chips use plain `Color.white` fill (matching the `BereanEmptyState` suggestion chip style inside `AIBibleStudyView`'s atmospheric background). This is intentional — each chip style matches its host background.

### 3. Chips in BereanLandingEmbedded are sequenced after hero animation
The chips `chipsVisible` flag is set to `true` in `onSequenceComplete` (fired when the typewriter animation finishes). If `reduceMotion` is enabled or `hasAnimatedThisSession` is already `true` (returning to empty state), chips appear immediately via `onAppear`. This ensures chips don't flash before the greeting renders.

### 4. heroComplete state variable
`BereanLandingView` has a `@State private var heroComplete = false` that was already orphaned before this change (never written or read in the view body). Left untouched to minimize diff — it does not affect behavior.

### 5. Bottom mode pill row (BereanModeControlBar)
The bottom mode pill row confirmed to NOT appear in `AIBibleStudyView.swift` or `BereanLandingView.swift`. `BereanModeControlBar` is defined in `BereanModeControlBar.swift` and used in `BereanGlassComposer.swift`, which is a different surface (not the landing view or AIBibleStudyView). No change needed.

### 6. Memory chip
No standalone Memory chip was found in `AIBibleStudyView.swift` or `BereanLandingView.swift`. The `BereanMemoryStripView` is defined separately and not rendered in the landing empty state. No change needed.

### 7. Berean secondary pill in sub-nav
No duplicate "Berean" pill was found below the main nav bar in the target files. The nav bar shows "Berean" as the principal toolbar item. No additional secondary pill exists in these files.

---

## Verification Steps for Canvas / Simulator

1. Open `AIBibleStudyView` in canvas or simulator with `messages = []`.
2. Confirm 6 above-fold elements: nav bar, tab selector, hero (greeting + follow-up), chip row (5 pills), composer.
3. Tap a chip — confirm the input field is pre-filled with the partial prompt and focused.
4. Tap the background — confirm chip row re-appears and input defocuses.
5. Send a message — confirm hero and chips disappear, chat content appears, composer stays.
6. Open `BereanLandingView` standalone preview — confirm: hero, chip row, input bar visible; no BereanContextStrip; no modal suggestion panel.
7. Focus the input bar — confirm chip row fades out (suggestionsVisible = true path).
8. Reduce Motion ON — confirm all chips appear instantly without stagger animation.
