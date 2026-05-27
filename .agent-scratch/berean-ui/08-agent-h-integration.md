# Agent H — BereanComposerTray Integration Notes

## New file
`AMENAPP/BereanComposerTray.swift`

## What was built
A floating glass tray (`BereanComposerTray`) that sits above the Berean composer input bar and adapts to draft intent. It replaces both the `BereanModePickerSheet` (sheet) and `BereanComposerToolSheet` (sheet) for mode-switching with an inline experience.

Key features:
- 5 quick-start intent states (empty, scriptureRef, question, prayer, modeKeyword)
- Inline mode picker — all 5 primary `BereanPersonalityMode` cases, no sheet
- Expandable capabilities panel — 9 capabilities, spring expand, no sheet
- Gold pulse border on scripture-detected chip (reduce-motion: static border)
- Full accessibility: VoiceOver labels + hints on every interactive element
- `@Environment(\.accessibilityReduceMotion)` and `\.accessibilityReduceTransparency` guards on every animation and material

## New type defined in this file
```swift
enum BereanDraftIntent: Equatable {
    case empty
    case question
    case scriptureRef(String)
    case prayer
    case modeKeyword(BereanPersonalityMode)
}
```
No other files need to import or redeclare this — it lives in BereanComposerTray.swift.

---

## Wiring into BereanComposerBar (BereanComposerBar.swift)

### Step 1 — Add `@State` for the computed intent

In `BereanCompactComposerBar`, add one state property alongside the existing `detectedScriptureRef`:

```swift
@State private var currentDraftIntent: BereanDraftIntent = .empty
```

### Step 2 — Compute the intent from existing detection logic

Add a private helper that maps the existing state variables to a `BereanDraftIntent`:

```swift
private func computeDraftIntent(text: String) -> BereanDraftIntent {
    if text.isEmpty { return .empty }
    if let ref = detectedScriptureRef { return .scriptureRef(ref) }
    let lower = text.lowercased()
    if lower.contains("pray") || lower.contains("prayer") {
        return .prayer
    }
    if lower.contains("scripture") || lower.contains("verse") || lower.contains("bible") {
        return .modeKeyword(.scriptureStudy)
    }
    if text.contains("?") || lower.hasPrefix("why") || lower.hasPrefix("what") || lower.hasPrefix("how") {
        return .question
    }
    return .empty
}
```

Then call it inside the existing `onChange(of: messageText)` handler, after `detectScripturePaste`:

```swift
currentDraftIntent = computeDraftIntent(text: newValue)
```

### Step 3 — Insert the tray above the input capsule

In the `body` of `BereanCompactComposerBar`, replace the current `VStack(spacing: 0)` opening with `VStack(spacing: 8)` so the tray gets 8 pt breathing room, then insert `BereanComposerTray` **before** the ghost-draft chip and above the HStack that contains the input field:

```swift
VStack(spacing: 8) {        // was spacing: 0
    // NEW: contextual tray
    BereanComposerTray(
        draftText: $messageText,
        draftIntent: currentDraftIntent,
        selectedMode: selectedMode,
        onModeChange: { mode in
            showModePicker = false      // no-op now but keeps state clean
            inferredMode = nil
            onModeChange?(mode)
            Analytics.logEvent("berean_mode_selected", parameters: ["mode": mode.rawValue])
        },
        onChipTap: { suggestion in
            messageText = suggestion
        },
        onActionTap: handleToolSelection
    )

    // existing ghost draft chip, follow-up chips, status pill, HStack input...
```

### Step 4 — Remove or retain the legacy sheets

The `showModePicker` / `BereanModePickerSheet` sheet can be removed now that mode switching is fully inline in the tray. Keep the `showActions` / `BereanComposerToolSheet` sheet only if there are actions not represented in the tray; otherwise remove it and route all action taps through `onActionTap` on the tray.

If keeping both temporarily for a phased rollout, they are still functional — the tray just provides a faster, visible path.

---

## Props reference

| Prop | Type | Source in BereanCompactComposerBar |
|------|------|-------------------------------------|
| `draftText` | `Binding<String>` | `$messageText` |
| `draftIntent` | `BereanDraftIntent` | `currentDraftIntent` (new @State) |
| `selectedMode` | `BereanPersonalityMode` | `selectedMode` |
| `onModeChange` | `(BereanPersonalityMode) -> Void` | wraps existing `onModeChange?` |
| `onChipTap` | `(String) -> Void` | writes into `messageText` |
| `onActionTap` | `(BereanLiquidAction.ActionType) -> Void` | `handleToolSelection` |

---

## What is NOT in this file
- `BereanDraftIntent` classification logic — that belongs in `BereanCompactComposerBar` (or a new `BereanIntentClassifier` service) so it stays co-located with the existing `detectScripturePaste` + `trackKeystrokeRhythm` logic.
- The `BereanGrokCoordinator` already classifies input in real time; for the final wiring, drive `currentDraftIntent` from the coordinator's output instead of the local heuristic above.
