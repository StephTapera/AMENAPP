# Agent G — Integration Note
## Files delivered: BereanMessageTray + BereanCitationTile
**Date:** 2026-05-27  
**Branch:** audit-fixes/2026-05-26

---

## Files written

| File | Location |
|------|----------|
| `BereanMessageTray.swift` | `AMENAPP/BereanMessageTray.swift` |
| `BereanCitationTile.swift` | `AMENAPP/BereanCitationTile.swift` |

---

## BereanMessageTray — integration steps

### 1. Wire into the message bubble parent

The tray floats **8 pt below the bottom edge** of the focused message bubble. In whatever view holds `BereanMessageBubble`, add:

```swift
@State private var trayVisible = false
@State private var focusedMessageId: UUID? = nil
```

On long-press of the bubble:
```swift
.onLongPressGesture {
    focusedMessageId = message.id
    withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
        trayVisible = true
    }
}
```

Then beneath the bubble (inside the same `VStack` that contains it):
```swift
if focusedMessageId == message.id {
    BereanMessageTray(
        message: message,
        isVisible: $trayVisible,
        onRegenerate: { viewModel.regenerate(message) },
        onShare:      { shareSheet(message.content) },
        onAudio:      { viewModel.playAudio(message) },
        onMore:       { showMessageMenu = true }
    )
    .padding(.horizontal, 16)
}
```

### 2. Auto-dismiss on scroll

In `BereanChatView` (or whatever `ScrollView` wraps messages), add a scroll-position observer that sets `trayVisible = false`. Example with `scrollPosition` modifier (iOS 17+):

```swift
.onScrollGeometryChange(for: CGFloat.self, of: { geo in
    geo.contentOffset.y
}) { _, _ in
    trayVisible = false
}
```

### 3. Wire the "···" overflow to BereanMessageMenuView

The `onMore` closure should present `BereanMessageMenuView` via `.sheet(isPresented:)` or a custom overlay. `BereanMessageMenuView` already exists at `AMENAPP/BereanMessageMenuView.swift` — no changes needed there.

---

## BereanCitationTile — integration steps

### 1. Add BereanProvenanceSource to BereanProvenanceRecord

`BereanProvenanceSource` is currently declared locally in `BereanCitationTile.swift`. Once the model update is ready, move the struct to `BereanGrokModels.swift` (where `BereanProvenanceRecord` lives) and add:

```swift
// In BereanProvenanceRecord:
var sources: [BereanProvenanceSource] = []
```

Remove the local declaration from `BereanCitationTile.swift` at that point.

### 2. Add BereanCitationRow below AI message bubbles

Inside whatever renders the message content (likely `BereanMessageBubble` or the VStack in `BereanChatView`'s `ForEach`), append the citation row conditionally:

```swift
// After the message text content:
if let provenance = message.provenance, !provenance.sources.isEmpty {
    BereanCitationRow(sources: provenance.sources)
        .padding(.top, 6)
}
```

This directly closes the P0 intelligence surface miss: provenance data exists on messages but was never rendered.

### 3. No changes required to BereanProvenanceChips.swift

`BereanCitationRow` is additive — it renders *citation sources* (scripture references, documents) while `BereanProvenanceChipRow` renders *verification status chips* (Berean-checked, AI-assisted, etc.). Both can coexist below the message bubble.

---

## Design compliance checklist

- No hardcoded colors: all tokens from `BereanColor.*`, `Color.amenGold`, `Color.amenBlack`
- No `.system(size:)` fonts: all `AMENFont.semiBold`, `.medium`, `.regular`
- No linear/ease animations: all `.spring(response:dampingFraction:)` or `.none` when reduceMotion is active
- `@Environment(\.accessibilityReduceMotion)` checked before every animation
- `@Environment(\.accessibilityReduceTransparency)` checked before every `.ultraThinMaterial`
- All interactive elements have `accessibilityLabel` and `accessibilityHint`
- `BereanCitationTile` announces `"Citation: John 3:16, verified"` pattern to VoiceOver
- Minimum 44x44 pt tap targets on all buttons
- "Copied" toast uses `Task` + `Task.sleep` — no `Timer`
- `BereanMessageTray` guard: renders nothing for `.user` role messages

---

## Open items for downstream agents

- **Agent H / markdown rendering**: `BereanMessageTray` is a peer of the bubble, not inside it — no interaction with markdown rendering work.
- **BereanProvenanceRecord.sources**: field needs to be added before `BereanCitationRow` can be wired to live data. Tracked above.
- **Audio playback** (`onAudio`): closure is wired through but `BereanChatViewModel` needs to expose a `playAudio(_ message:)` method. Current `BereanVoiceSessionService` handles TTS — bridge needed.
