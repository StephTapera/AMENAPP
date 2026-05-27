# Agent E — BereanThreadCapsule & BereanConversationSpine Integration

## Files delivered

- `AMENAPP/BereanThreadCapsule.swift`
- `AMENAPP/BereanConversationSpine.swift`

---

## BereanThreadCapsule — wiring into BereanChatView

### 1. Add state to BereanChatView

```swift
@State private var threadScrollOffset: CGFloat = 0
```

### 2. Place the capsule above the message ScrollView

The capsule should sit in a `VStack` or `ZStack` just below the navigation bar / status bar safe area, above the `ScrollView` that contains messages.

```swift
VStack(spacing: 0) {
    BereanThreadCapsule(
        threadTitle: viewModel.threadTitle,
        mode: viewModel.currentMode,
        verseCount: viewModel.attachedVerseCount,
        docCount: viewModel.attachedDocCount,
        memoryOn: viewModel.memoryEnabled,
        theologicalLens: viewModel.theologicalLens,
        scrollOffset: $threadScrollOffset,
        onBackTapped: { dismiss() }
    )
    .padding(.horizontal, 16)
    .padding(.top, 8)

    messageScrollView  // your existing ScrollView
}
```

### 3. Drive `scrollOffset` from the scroll position

Use a `GeometryReader` preference or a `coordinateSpace` scroll tracker inside the messages `ScrollView`. Example using a background geometry reader on the first message row:

```swift
ScrollView {
    LazyVStack { ... }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: -geo.frame(in: .named("messageScroll")).minY
                    )
            }
        )
}
.coordinateSpace(name: "messageScroll")
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
    threadScrollOffset = max(0, offset)
}
```

`ScrollOffsetPreferenceKey` should be a simple `CGFloat` preference key (define once in a shared file if not already present).

---

## BereanConversationSpine — wiring into BereanChatView

### 1. Add state to BereanChatView

```swift
@State private var visibleMessageId: UUID? = nil
```

### 2. Wrap the messages ScrollView with ScrollViewReader and overlay the spine

```swift
ScrollViewReader { proxy in
    ZStack(alignment: .trailing) {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.messages) { msg in
                    BereanMessageBubble(...)
                        .id(msg.id)
                        .onAppear { visibleMessageId = msg.id }
                }
            }
        }

        BereanConversationSpine(
            messages: viewModel.messages,
            visibleMessageId: $visibleMessageId,
            scrollProxy: proxy
        )
        .padding(.trailing, 4)
        // Only show spine when thread has enough messages to warrant scrubbing
        .opacity(viewModel.messages.count >= 6 ? 1 : 0)
        .animation(.spring(response: 0.36, dampingFraction: 0.76), value: viewModel.messages.count)
    }
}
```

### 3. Keep `visibleMessageId` in sync on new messages

```swift
.onChange(of: viewModel.messages.count) { _, _ in
    visibleMessageId = viewModel.messages.last?.id
}
```

---

## Accessibility notes

- `BereanThreadCapsule` exposes a single `.accessibilityLabel` on the compact button summarising the full microstate. The expanded drawer uses `accessibilityElement(children: .contain)` so VoiceOver can navigate individual chips.
- `BereanConversationSpine` reads as "Thread scrubber, N messages" and each dot carries a role + content-type label. The currently-visible dot gets `.isSelected` trait.
- Both views fully guard `@Environment(\.accessibilityReduceMotion)` and `@Environment(\.accessibilityReduceTransparency)`.

---

## Color token gap (DS-9)

`Color.amenPurple` and `Color.amenBlue` are not yet defined in the global color system (`AmenAdaptiveColors.swift` / `AmenColorScheme.swift`). The spine file defines them in a `private enum BereanConversationSpineColors` namespace to avoid polluting the module scope. Once the design system token sheet adds them globally, remove the private namespace and switch to `Color.amenPurple` / `Color.amenBlue` directly.
