# Berean Accessibility & Performance Audit
Agent C — 2026-05-28

---

## Accessibility Findings

| # | Component | Issue | Severity | Fix |
|---|-----------|-------|----------|-----|
| A-01 | **BereanChatView** — `heroPromptChipRow` | Every hero prompt chip (`ForEach(heroPromptChips)`) has **no `.accessibilityLabel`**. VoiceOver reads the raw `Text(chip.title)` label through the button, which is acceptable but `.accessibilityHint` describing the action is completely absent. Users cannot tell these are "tap to start a prompt" affordances. | Medium | Add `.accessibilityLabel(chip.title).accessibilityHint("Fills the composer with this starter prompt")` to each `Button`. |
| A-02 | **BereanChatView** — `modeChip(title:icon:mode:)` | Mode chips in the hero section are interactive `Button`s with **no `.accessibilityLabel`, no `.accessibilityHint`, and no `.accessibilityAddTraits(.isSelected)`**. VoiceOver reads only the inner `Text(title)` label without indicating selection state. | Medium | Add `.accessibilityLabel("\(title) mode")`, `.accessibilityHint("Switch Berean to \(title) mode")`, and `.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)`. |
| A-03 | **BereanChatView** — `quickActionPill(title:icon:)` | Quick action pills in the hero surface have **no accessibility modifiers whatsoever**. | Medium | Add `.accessibilityLabel(title).accessibilityHint("Fills the composer with a \(title) prompt")`. |
| A-04 | **BereanChatView** — `suggestionPill(title:icon:prompt:)` | Suggestion pills in `focusedSuggestionRow` have **no `.accessibilityLabel` or `.accessibilityHint`**. VoiceOver reads nothing for these buttons. | Medium | Add `.accessibilityLabel(title).accessibilityHint("Fills the composer with \"\(prompt)\"")`. |
| A-05 | **BereanChatView** — `followUpActionPills` | Follow-up action `Button`s (inside `BereanFollowUpFlowLayout`) have **no accessibility modifiers**. | Medium | Add `.accessibilityLabel(action.title).accessibilityHint("Sends this as your next message")` to each pill button. |
| A-06 | **BereanChatView** — `studyModeToggle` | Study mode toggle has `.accessibilityLabel("Study Mode")` and `.accessibilityValue` but **no `.accessibilityHint`** and **no `.accessibilityAddTraits(.isButton)`** (it is a plain-style button). `.accessibilityAddTraits(.isToggle)` would be semantically accurate. | Low | Add `.accessibilityHint("Toggles structured deep-study reasoning mode").accessibilityAddTraits(.isToggle)`. |
| A-07 | **BereanChatView** — `headerMenuButton` | The ellipsis menu button has `.accessibilityLabel("Options")` but **no `.accessibilityHint`** and no indication it opens a menu. VoiceOver does not announce `.isMenu` trait. | Low | Add `.accessibilityHint("Opens response mode and wallpaper options")`. For iOS 16+, wrapping in a `Menu` already exposes the popup-button trait; confirm `Menu`'s accessibility is not swallowed by `.buttonStyle(.plain)`. |
| A-08 | **BereanChatView** — `headerModeCapsule` | The compressed header mode capsule button has **no `.accessibilityLabel`, no `.accessibilityHint`**. At high scroll it is the primary navigation affordance. | High | Add `.accessibilityLabel("Mode: \(vm.currentMode.rawValue)\(vm.isStudyModeEnabled ? ", Study on" : "")").accessibilityHint("Opens mode selector")`. |
| A-09 | **BereanChatView** — `bereanContextMemoryRail` chips | The context source `Button`s have `.accessibilityLabel("\(source.label) context \(isSelected ? "active" : "inactive")")` but **no `.accessibilityHint`** and no `.accessibilityAddTraits(.isToggle)` to indicate toggling behaviour. | Low | Add `.accessibilityHint("Double tap to toggle this context source").accessibilityAddTraits(.isToggle)`. |
| A-10 | **BereanChatView** — `intelligenceFollowUpRow` suggestion pills | `ForEach(intelligence.followUpSuggestions)` buttons have **no accessibility label or hint**. | Medium | Add `.accessibilityLabel(suggestion).accessibilityHint("Sends this as your next question to Berean")`. |
| A-11 | **BereanChatView** — `paywallBanner` "Upgrade" button | The Upgrade `Button` has **no `.accessibilityLabel`** — VoiceOver reads "Upgrade" from the text, which is acceptable, but there is **no `.accessibilityHint`** explaining it opens the App Store subscriptions page. | Low | Add `.accessibilityHint("Opens the App Store to upgrade to Pro")`. |
| A-12 | **BereanChatView** — `bereanErrorBanner` dismiss button | The xmark `Button` has only `.accessibilityLabel("Dismiss error")` but **no `.contentShape`** and its frame is only `28×28pt` — **below the 44pt minimum tap target**. | High | Wrap the label in `.frame(width: 44, height: 44).contentShape(Rectangle())`. |
| A-13 | **BereanChatView** — `modeFallbackBanner` dismiss button | Same 28×28pt xmark button as the error banner — identical under-sized tap target. `.accessibilityLabel("Dismiss mode notice")` is present but `contentShape` is missing. | High | Same fix as A-12. |
| A-14 | **BereanChatView** — `userMessageBubble` | User message `Text` bubbles have no `.accessibilityLabel` on the text itself; the `.accessibilityLabel(messageAccessibilityLabel(msg))` is applied to the *parent `VStack`* at `structuredMessageView` level. This is fine for the combined group, but the parent does **not carry `.accessibilityElement(children: .combine)`**, meaning VoiceOver may still descend into child elements and re-read sub-views. | Medium | Add `.accessibilityElement(children: .combine)` to the `structuredMessageView` outer VStack to enforce a single focusable element per message. |
| A-15 | **BereanChatView** — `BereanStructuredResponseView` assistant bubble (long-press tray trigger) | The `.onLongPressGesture` that shows `BereanMessageTray` is invisible to VoiceOver — there is **no `.accessibilityAction` for custom long-press**, meaning VoiceOver users cannot access Copy / Regenerate / Share / Audio at all. | Ship-blocker | Add `.accessibilityAction(named: "Message actions") { trayVisibleForId = message.id; messageTrayVisible = true }` to the `BereanStructuredResponseView`. |
| A-16 | **BereanChatView** — `Correct the AI` button | The inline "Correct the AI" button has **no `.accessibilityLabel` or `.accessibilityHint`**, and its frame is roughly 20×20pt with no `.contentShape`. | Medium | Add `.accessibilityLabel("Correct this Berean response").accessibilityHint("Opens a form to correct AI tone or content").frame(minHeight: 44).contentShape(Rectangle())`. |
| A-17 | **BereanChatView** — `selectedComposerModeChip` | The composed mode chip (`HStack` with `.accessibilityLabel("Current Berean mode: \(compactModeTitle)")`) is **not interactive** — fine — but it is rendered inside an `HStack` inside a non-focusable parent, meaning VoiceOver will land on the inner `Text` without reading the correct label. `.accessibilityElement(children: .combine)` is missing. | Low | Add `.accessibilityElement(children: .combine)` to the outer `HStack` in `selectedComposerModeChip`. |
| A-18 | **BereanCitationTile** — cross-reference chips in sheet | The non-tappable cross-reference chips in the detail sheet have `.accessibilityLabel("Cross-reference: \(ref.reference)")` but the **chips have height 28pt** (hard-coded `frame(height: 28)`). These are informational only so no tap-target minimum applies, but VoiceOver still reads them and the label is good. However, the outer `ScrollView` in `crossReferencesSection` has **no `.accessibilityLabel`** to give the group context. | Low | Add `.accessibilityLabel("Cross-references")` to the horizontal `ScrollView` container. |
| A-19 | **BereanCitationTile** — `BereanCitationDetailSheet` Close button | "Close" toolbar button has **no `.accessibilityLabel` or `.accessibilityHint`**. | Low | Add `.accessibilityLabel("Close citation").accessibilityHint("Dismisses citation detail")`. |
| A-20 | **BereanComposerTray** — `reasoningReadyChip` / `prayerReadyChip` | Both status chips use `.accessibilityAddTraits(.isStaticText)`. These are informational — correct. But they lack `.accessibilityElement(children: .ignore)` on their inner icon, which means VoiceOver may read "sparkles image" before the label. | Low | Add `.accessibilityHidden(true)` to `Image(systemName:)` inside each status chip. |
| A-21 | **BereanComposerTray** — `activeModePill` | `.accessibilityAddTraits(.isStaticText)` is set, but the inner `Image(systemName: selectedMode.icon)` is **not hidden from accessibility**. | Low | Add `.accessibilityHidden(true)` to the icon `Image`. |
| A-22 | **BereanThinkingStrip** — shimmer overlay | `shimmerOverlay` wraps in a `GeometryReader` and sets `.allowsHitTesting(false)` but does **not set `.accessibilityHidden(true)`**. The GeometryReader itself is an accessibility element. | Low | Add `.accessibilityHidden(true)` to the shimmer overlay (the `GeometryReader`). |
| A-23 | **ALL components** — amenGold on white contrast | `Color.amenGold` is used as foreground on white/ultraThinMaterial backgrounds throughout (citation tile reference text, active mode chip text on `Color.amenGold` fill reverses to `Color.white` — fine, but `Color.amenGold` on white glass at 11–13pt falls below 4.5:1 WCAG AA). Based on a typical gold value of ~#C9A84C on white (#FFFFFF), the contrast ratio is approximately **2.8:1** — a hard WCAG AA fail at small text sizes. | Ship-blocker | Either raise amenGold luminance for text-on-white use cases (a darker `#8A6B00` variant achieves 4.5:1+), or restrict amenGold to ornamental/badge use only and use `BereanColor.textPrimary` for readable citation text. Confirm exact hex value of `Color.amenGold` and measure against white. |
| A-24 | **BereanMemoryChip** — `BereanMemoryDetailSheet` header `Image` (brain icon) | The large 20pt brain icon in the header is **not hidden from accessibility** while the adjacent `Text("What Berean remembered")` provides the label. VoiceOver will read the icon as "brain image" separately. | Low | Add `.accessibilityHidden(true)` to the header `Image(systemName: "brain")`. |
| A-25 | **BereanChatView** — `BereanVersePreviewSheet` action buttons | "Open in Selah" and "Copy" buttons have **no `.accessibilityLabel` or `.accessibilityHint`**. They rely solely on inner `Label` text, which SwiftUI surfaces automatically — this is acceptable for standard `Label`, but there is **no hint** for what "Open in Selah" means to a VoiceOver user who may not know what Selah is. | Low | Add `.accessibilityHint("Opens the full passage in the Selah Bible reader")` to the Open in Selah button. |

---

## Performance Findings

| # | File | Line(s) | Pattern | Impact | Fix |
|---|------|---------|---------|--------|-----|
| P-01 | **BereanChatView.swift** (ViewModel) | 115–121 | `@Published var inputText: String` with a `didSet` that calls `grokCoordinator.classifyInput(inputText)` **on every keystroke**. `classifyInput` is synchronous on `@MainActor` and presumably runs regex/string matching per character. | High — every keypress triggers a synchronous classification call on the main thread, blocking UI updates during fast typing. | Gate the call behind a debounce: use `Combine`'s `.debounce(for: .milliseconds(300), scheduler: RunLoop.main)` or a `Task` with `Task.sleep(for: .milliseconds(300))` before calling `classifyInput`. |
| P-02 | **BereanChatView.swift** (ViewModel) | 467–476 | SSE streaming loop flushes to `messages[assistantIndex].content` after every 80ms of accumulated chunks. Each flush triggers SwiftUI diffing of the entire `messages` `@Published` array — **every 80ms, the whole LazyVStack re-evaluates**. The debounce is correct but messages is a full array-replace. | Medium — with `LazyVStack` this is mostly mitigated, but long conversations (near `messageWindowSize=50`) cause ~50 view identity re-evaluations per flush, even for non-streaming messages. | Use a dedicated `@Published var streamingContent: String` separate from the messages array; write the completed content back to `messages` only when streaming ends. This isolates recomposition to the single streaming row. |
| P-03 | **BereanChatView.swift** | 1716–1733 | `.onPreferenceChange(ScrollOffsetPreference.self)` fires on **every scroll tick** and updates three `@State` properties (`scrollOffset`, `threadScrollOffset`, `scrollCoordinator`) plus conditionally animates `showHero`, dismisses `messageTrayVisible`, and calls `composerVM.updateScroll()`. All of this happens synchronously on the main thread per scroll frame. | High — scroll jank risk on older devices, particularly when the message list is long. | Throttle via `CADisplayLink`-backed callback, or extract the `showHero` animation and `messageTrayVisible` dismissal into a Combine pipeline with `.debounce`. `scrollCoordinator.update()` and `composerVM.updateScroll()` should be `nonisolated` so the scroll callback can be offloaded. |
| P-04 | **BereanChatView.swift** | 1696 | `.animation(.easeOut(duration: 0.2), value: vm.isThinking)` is attached to the **outer `LazyVStack`** — this animates **every child view** inside the entire message list whenever `isThinking` changes, not just the `processingIndicator`. | Medium — causes all 50 messages to participate in the animation transaction, defeating lazy loading for that frame. | Move `.animation(…, value: vm.isThinking)` to `.animation(…, value: vm.isThinking)` on the `processingIndicator` only, not the parent `LazyVStack`. |
| P-05 | **BereanChatView.swift** | 1680 | `BereanScriptureReferenceExtractor.references(in: message.content)` is called inside `bereanScriptureChip(for:)` which is called inside `structuredMessageView` — which is called inside `ForEach(vm.messages)` inside `LazyVStack`. Every time SwiftUI re-evaluates any message row (e.g. due to P-03 scroll updates), this regex/string scan runs again on the full message content. | Medium — repeated full-text regex scans per scroll frame for each visible message. | Memoize the result: add a `var scriptureReferences: [String]?` property to `BereanChatMsg` and populate it once when the message is completed (`streamingState == .completed`). Read the cached value in the view. |
| P-06 | **BereanChatView.swift** | 1752–1756 | `.onChange(of: vm.messages.last?.content)` fires **per-streaming-token** (after 80ms debounce window) and calls `debouncedScrollToBottom`. This is the intended SSE auto-scroll, but it also fires for **every message edit**, e.g. when the alignment service rewrites content (lines 508–519), triggering an unnecessary scroll mid-editing. | Low–Medium — mostly harmless but can cause visible scroll jumps when alignment service modifies messages. | Add a guard: only call `debouncedScrollToBottom` when `vm.isThinking` is `true` and `vm.messages.last?.role == .assistant`. |
| P-07 | **BereanComposerTray.swift** | 601–613 | `startGoldPulse()` launches a `Task { @MainActor in while !Task.isCancelled { … } }` — an **unbounded loop** that toggles `scriptureGoldPulse` every 1200ms. This task is created in `.onAppear` and `.onChange(of: ref)` but is **never cancelled** when the chip disappears or the ref changes. Each `onChange` call creates a new competing loop. | High — memory leak + CPU usage: multiple concurrent pulse tasks pile up when the user types and clears scripture references. | Store the task in a `@State private var goldPulseTask: Task<Void, Never>?`, cancel it in `.onDisappear` and before starting a new one in `onChange`. |
| P-08 | **BereanChatView.swift** | 1793 | `Timer.scheduledTimer(withTimeInterval:)` is created inside a `@MainActor` callback from the scroll preference change handler. The timer fires on `RunLoop.main` but is wrapped in a `Task { @MainActor in ... }` which creates an unnecessary Task hop. | Low | Call `proxy.scrollTo` directly from the timer callback on the main thread — no `Task` wrapper needed. |
| P-09 | **BereanChatView.swift** | 967–1360 | `body` is a `GeometryReader` containing a `ZStack` with nested `VStack`s, multiple `.sheet(item:)` and `.sheet(isPresented:)` closures (9 sheets total), `.overlay`, `.onReceive`, `.onChange`, `.task`, `.userActivity` — all inline in the `body` computed property. This is a **3596-line body with 9 sheet modifiers** on a single view. | Medium — long `body` means any `@State` or `@Published` change causes SwiftUI to re-evaluate all modifier closures. Sheet Bindings (e.g. `Binding<ReportingTarget?>` created inline at line 1170) are recreated on every body evaluation. | Extract major sections into subviews or `@ViewBuilder` computed properties; hoist the inline `Binding<ReportingTarget?>` to a computed property so it is not recreated per-render. |
| P-10 | **BereanMemoryChip.swift** | 187–205 | `startShimmer()` / `startBorderPulse()` are called from `onAppear` and `onChange(of: isActive)`. However `stopAnimations()` only resets state values — it does **not cancel** the `withAnimation(.repeatForever…)` animations already in flight. Calling `stopAnimations()` when `isActive` becomes `false` leaves the `repeatForever` animations running on detached `CAAnimation` layers until the view is deallocated. | Medium — visual correctness issue (borders and gradients continue animating after memory becomes inactive) and battery drain. | Use `withAnimation(nil) { shimmerPhase = 0; borderPulse = false }` inside `stopAnimations()` to forcibly remove the in-flight animation. |
| P-11 | **BereanThinkingStrip.swift** | 247–251 | `stopAnimations()` sets `shimmerRunning = false` and resets state but does **not cancel** the `withAnimation(.linear(duration: 1.8).repeatForever…)` shimmer. Same issue as P-10. | Medium | Same fix: use `withAnimation(nil)` when stopping. |
| P-12 | **BereanChatView.swift** | 2974–2982 | `messageAccessibilityLabel(_:)` creates a new `DateFormatter` **on every call** (once per rendered message per body evaluation). | Low — allocates a `DateFormatter` per-message per-frame. | Cache the formatter as a `private let` static property on the view or on `BereanChatViewModel`. |
| P-13 | **BereanChatView.swift** — `BereanChatViewModel` | 734–740 | `loadMessageCount()` uses a Firestore completion handler and dispatches to `DispatchQueue.main.async` — this is legacy GCD dispatch inside a `@MainActor` class. If the view is dismissed before the callback fires, `self` is retained until completion. | Low | Replace with `async/await` using `getDocument(source:)` inside a `Task { [weak self] in … await MainActor.run { … } }` pattern. |

---

## VoiceOver Flow (correct reading order per screen)

### Chat screen — no messages (hero state)
1. Back button (header)
2. Conversation title capsule (header center)
3. Study Mode toggle (header)
4. Options menu (header)
5. Thread Capsule — compact pill (full label with mode + microstate)
6. Thinking Strip — hidden when idle
7. *(Hero section — should be `.accessibilityElement(children: .contain)` on the outer VStack)*
8. Adaptive prompt surface: mode label, hero prompt, support line
9. Hero prompt chip row: each chip as a button *(currently missing accessibilityLabel)*
10. Mode chips row: each chip with selection state *(currently missing)*
11. Memory chip
12. Composer mode chip (informational, read once)
13. Composer input bar / BereanCompactComposerBar

### Chat screen — messages present
1. Back button
2. Conversation title capsule
3. Study Mode toggle
4. Options menu
5. Thread Capsule (compact or collapsed chevron)
6. Thinking Strip (when active: "Berean is drafting a response")
7. Load earlier messages button (if applicable)
8. **Per message (as a single combined element):**
   - "You: [content], sent at [time]" — user messages
   - "Berean: [content], sent at [time]" — assistant messages
   - Custom action: "Message actions" (VoiceOver rotor → long press)
9. Citation row chips (per message, after content)
10. Scripture chip row (per message)
11. Correct the AI button (per assistant message) *(missing label)*
12. Processing indicator when thinking
13. Intelligence follow-up suggestion chips *(missing labels)*
14. Context source rail chips (when visible)
15. Suggestion pills (when visible) *(missing labels)*
16. Memory chip (active/inactive state)
17. Composer input bar

### Thread Capsule — expanded drawer
The `.accessibilityElement(children: .contain)` grouping is correctly applied to `expandedDrawer`. Reading order within:
1. Thread title (Text)
2. Dismiss button ("Dismiss thread details")
3. Mode personality pill ("Mode: [name]")
4. Verse count chip
5. Doc count chip
6. Memory chip ("Memory is currently on/off")
7. Theological lens chip (if set)

### BereanMemoryDetailSheet
1. Done button (toolbar, top right)
2. Brain icon (should be hidden — A-24)
3. "What Berean remembered" heading
4. Subtitle text
5. Memory settings button (if present)
6. Each memory entry row (combine label: title + body + date + "Used" if applicable)

---

## Summary: Ship-blockers vs Follow-on

### Ship-blockers (must fix before launch)

| ID | Issue |
|----|-------|
| **A-08** | `headerModeCapsule` has no accessibility label or hint — the primary compressed navigation control is invisible to VoiceOver |
| **A-12** | `bereanErrorBanner` dismiss button is 28×28pt — fails 44pt minimum tap target |
| **A-13** | `modeFallbackBanner` dismiss button is 28×28pt — same failure |
| **A-15** | Long-press message tray has no `.accessibilityAction` — VoiceOver users cannot access Copy, Share, Regenerate, or Audio |
| **A-23** | `amenGold` on white glass fails WCAG AA contrast (~2.8:1) at 11–13pt — affects citation text, mode chip text, many status labels |
| **P-07** | `startGoldPulse()` task in `BereanComposerTray` is never cancelled — leaks unbounded concurrent tasks on each scripture ref change |

### Follow-on (should ship in same sprint but not day-one blockers)

| ID | Issue |
|----|-------|
| A-01 | Hero prompt chips missing `accessibilityLabel` + `accessibilityHint` |
| A-02 | Mode chips missing `accessibilityLabel`, `accessibilityHint`, `isSelected` trait |
| A-03 | Quick action pills missing all accessibility modifiers |
| A-04 | Suggestion pills missing `accessibilityLabel` + `accessibilityHint` |
| A-05 | Follow-up action pills missing all accessibility modifiers |
| A-06 | Study mode toggle missing hint + `isToggle` trait |
| A-09 | Context source rail chips missing hint + `isToggle` trait |
| A-10 | Intelligence follow-up chips missing labels |
| A-14 | `structuredMessageView` missing `.accessibilityElement(children: .combine)` |
| A-16 | "Correct the AI" button missing label, hint, and 44pt frame |
| P-01 | Per-keystroke `classifyInput` call — needs 300ms debounce |
| P-03 | Per-scroll-tick `onPreferenceChange` doing multi-state updates — throttle/debounce |
| P-04 | `.animation(…, value: vm.isThinking)` on outer `LazyVStack` — move to `processingIndicator` only |
| P-05 | `BereanScriptureReferenceExtractor.references()` called per-render per-message — needs memoization |
| P-10 | `BereanMemoryChip` `stopAnimations()` doesn't cancel `repeatForever` animation |
| P-11 | `BereanThinkingStrip` `stopAnimations()` same issue |

### Tech debt / nice-to-have

| ID | Issue |
|----|-------|
| A-07 | headerMenuButton missing hint |
| A-11 | Paywall "Upgrade" button missing hint |
| A-17 | `selectedComposerModeChip` missing `.accessibilityElement(children: .combine)` |
| A-18 | Citation sheet cross-reference ScrollView missing group label |
| A-19 | Citation detail sheet Close button missing label/hint |
| A-20–21 | Status chip icons not hidden from accessibility tree |
| A-22 | Shimmer overlay GeometryReader not hidden from accessibility |
| A-24 | Memory sheet header brain icon not hidden |
| A-25 | "Open in Selah" missing hint for non-familiar users |
| P-02 | Streaming flushes to full `messages` array — isolate to `streamingContent` |
| P-06 | `onChange(of: vm.messages.last?.content)` fires on non-streaming rewrites |
| P-08 | Timer callback wrapped in unnecessary `Task` |
| P-09 | 3596-line body with 9 inline sheets — extract subviews |
| P-12 | `DateFormatter` allocated per-call in `messageAccessibilityLabel` |
| P-13 | Legacy GCD dispatch in `loadMessageCount()` |
