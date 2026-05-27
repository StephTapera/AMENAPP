# Berean Accessibility & Performance Audit

**Audit date:** 2026-05-27  
**Auditor:** Agent C (accessibility + performance)  
**Files audited:** BereanChatView.swift, BereanComposerBar.swift, BereanDesignSystem.swift, BereanStructuredCardView.swift, BereanProvenanceChips.swift, BereanFollowUpChips.swift, BereanDynamicIsland.swift, BereanMessageMenuView.swift, BereanScrollCoordinator.swift, BereanSmartPillSystem.swift

---

## Accessibility Summary

**Overall score: B+ (Good baseline, 7 targeted gaps)**

The Berean chat UI has a noticeably strong accessibility foundation relative to typical iOS chat apps. `@MainActor` is marked, `reduceMotion` and `reduceTransparency` are injected via `@Environment` in most animated components, and key interactive controls carry explicit `.accessibilityLabel` + `.accessibilityHint`. The `BereanBrandBadge` is correctly hidden (`accessibilityHidden(true)`). The thinking indicator uses `.accessibilityAddTraits(.updatesFrequently)`.

**Most critical gaps (in order):**
1. Hero prompt chips — fully interactive, zero VoiceOver labels (BereanChatView.swift ~L2102)
2. `BereanMessageMenuView` action grid — 10 buttons, no labels (only icon + 9pt micro-text)
3. Dynamic Island dismiss/action buttons — unlabeled xmark and "Open Full"/"Copy" buttons
4. Hero section `Text("Berean")` at 56pt fixed size — will not scale with Dynamic Type
5. Many `BereanSuggestionChip` instances lack `.accessibilityLabel` (BereanDesignSystem.swift)
6. `BereanFollowUpChipRow` individual chips have no label; only `animateIn()` is region-guarded
7. `reducedMotion` guard missing on the `BereanDynamicIsland` aura blob animation

---

## Accessibility — Detail

### Missing VoiceOver Labels

| File | Element | Current state | What it should say |
|------|---------|---------------|--------------------|
| BereanChatView.swift ~L2102–2124 | `heroPromptChipRow` — each `Button` inside `ForEach(heroPromptChips)` | No `.accessibilityLabel` applied to chips | `"chip.title — \(chip.prompt)"` or at minimum `chip.title` |
| BereanChatView.swift ~L2161–2222 | `modeChip(title:icon:mode:)` Buttons | No `.accessibilityLabel`; visible text present so VO reads it, but `.accessibilityAddTraits(.isSelected)` is missing for the active chip | Add `.accessibilityAddTraits(isSelected ? .isSelected : [])` |
| BereanMessageMenuView.swift ~L50–63 | Each of the 10 action `Button`s in the `LazyVGrid` | Button label built from `Image + 9pt Text(action.label)` — VO reads the 9pt text only, no hint | Add `.accessibilityLabel(action.label)` + `.accessibilityHint(hintForAction(action.id))` per button |
| BereanDynamicIsland.swift ~L392–399 | `Button { vm.dismiss() }` (xmark in top row) | No `.accessibilityLabel` | `.accessibilityLabel("Close Berean response")` |
| BereanDynamicIsland.swift ~L487–505 | "Open Full" button in `responseContent` | No `.accessibilityLabel` | `.accessibilityLabel("Open full Berean response")` |
| BereanDynamicIsland.swift ~L507–525 | "Copy" button in `responseContent` | No `.accessibilityLabel` | `.accessibilityLabel("Copy response to clipboard")` |
| BereanDesignSystem.swift ~L161–187 | `BereanSuggestionChip` | `Button(action: onTap)` with no `.accessibilityLabel`; VoiceOver reads the chip `text` parameter, which is adequate for label but there is no hint | Add `.accessibilityHint("Sends this prompt to Berean")` |
| BereanFollowUpChips.swift ~L126–151 | `chipButton(_:index:)` in `BereanFollowUpChipRow` | No `.accessibilityLabel`; VoiceOver will read chip label text but no hint explaining what happens | Add `.accessibilityHint(chip.prompt.isEmpty ? "Saves this response" : "Sends follow-up to Berean")` |
| BereanFollowUpChips.swift ~L290–301 | Each `actionButton` in `BereanResponseActionBar` | No `.accessibilityLabel` or `.accessibilityHint` on the VStack-inside-Button | The enclosing `Button` should have `.accessibilityLabel(label)` (the string parameter already exists); add hint per action |
| BereanChatView.swift ~L1298–1310 | Back "chevron.left" Button in `smartBlurHeader` | No `.accessibilityLabel` | `.accessibilityLabel("Back")` |
| BereanChatView.swift ~L2573–2582 | "xmark" dismiss in `intelligenceFollowUpRow` | No `.accessibilityLabel` | `.accessibilityLabel("Dismiss follow-up suggestions")` |

### Dynamic Type Violations

Hard-coded `.font(.system(size: X))` calls bypass the Dynamic Type scale. Every instance below should be replaced with a `.font(.systemScaled(X, weight:))` call (the project's existing helper) or a semantic font (e.g., `.body`, `.caption`).

| File | Line (approx.) | Value | Issue |
|------|---------------|-------|-------|
| BereanChatView.swift | ~L1883 | `.font(.system(size: 56, weight: .semibold, design: .rounded))` | Hero "Berean" title — 56pt fixed; does not scale |
| BereanChatView.swift | ~L1887 | `.font(.system(size: 18, weight: .regular))` | Hero subtitle — fixed |
| BereanChatView.swift | ~L1321 | `.font(.system(size: 13, weight: .semibold))` | Nav bar title icon — fixed |
| BereanChatView.swift | ~L1322 | `.font(.systemScaled(15, weight: .semibold))` | This one already uses `systemScaled`, OK |
| BereanChatView.swift | ~L1384 | `.font(.system(size: 11, weight: .semibold))` | Compressed mode capsule icon — fixed |
| BereanChatView.swift | ~L1385 | `.font(.system(size: 13, weight: .semibold))` | Compressed mode capsule label — fixed |
| BereanChatView.swift | ~L1417 | `.font(.system(size: 12, weight: .semibold))` | Study toggle glyph — fixed |
| BereanChatView.swift | ~L1419 | `.font(.system(size: 12, weight: .semibold))` | Study toggle text — fixed |
| BereanChatView.swift | ~L2057 | `.font(.system(size: 12, weight: .semibold))` | Mode label icon — fixed |
| BereanChatView.swift | ~L2060 | `.font(.system(size: 11, weight: .semibold))` | Mode label text — fixed |
| BereanChatView.swift | ~L2067 | `.font(.system(size: 28, weight: .semibold))` | Hero prompt heading — fixed (largest readability risk after 56pt title) |
| BereanChatView.swift | ~L2073 | `.font(.system(size: 14, weight: .regular))` | Hero support text — fixed |
| BereanChatView.swift | ~L1159 | `.font(.system(size: 13, weight: .semibold))` | "Saved to Church Notes" toast — fixed |
| BereanChatView.swift | ~L2108 | `.font(.system(size: 11, weight: .semibold))` | Hero chip icon — fixed |
| BereanChatView.swift | ~L2109 | `.font(.system(size: 14, weight: .medium))` | Hero chip text — fixed |
| BereanStructuredCardView.swift | ~L119 | `.font(.systemScaled(14, weight: .semibold))` | Uses systemScaled, OK |
| BereanStructuredCardView.swift | ~L142 | `.font(.systemScaled(15, weight: .regular))` | Uses systemScaled, OK |
| BereanDynamicIsland.swift | ~L479 | `AMENFont.regular(14)` | If AMENFont uses fixed pt this does not scale — verify |
| BereanComposerBar.swift | ~L290 | `.font(.system(size: 17, weight: .semibold))` | Plus icon in utility button — fixed |
| BereanComposerBar.swift | ~L338 | `.font(.system(size: 14, weight: .semibold))` | Tools slider icon — fixed |

**Highest-risk:** The 56pt "Berean" hero title and 28pt prompt heading. Users with large accessibility text sizes will get no scaling on these splash-screen-scale headings.

### Contrast Issues

Background is near-white (Color(red: 0.956, green: 0.956, blue: 0.936) ≈ #F4F4EE). WCAG AA requires 4.5:1 for normal text, 3:1 for large text (≥18pt/14pt bold).

| File | Element | Opacity / Color | Estimated ratio on #F4F4EE | Risk |
|------|---------|-----------------|---------------------------|------|
| BereanComposerBar.swift ~L340 | Tools button icon when `toneNudgeActive = false` | `BereanColor.textPrimary.opacity(0.58)` | ~3.5:1 for small icon at 14pt | Borderline — fails AA for normal text |
| BereanComposerBar.swift ~L374 | Mic button when `isVoiceEnabled = false` | `BereanColor.textPrimary.opacity(0.38)` | ~2.3:1 | Fails AA — disabled state, but still an interactive button |
| BereanComposerBar.swift ~L534 | Ghost draft xmark icon | `BereanColor.textPrimary.opacity(0.38)` | ~2.3:1 | Fails AA (interactive dismiss button) |
| BereanComposerBar.swift ~L464 | "Cancel voice input" xmark | `Color.black.opacity(0.26)` | ~1.8:1 | Fails AA (interactive) |
| BereanChatView.swift ~L2453–2455 | Context memory rail deselected chip text | `Color.black.opacity(0.45)` | ~2.8:1 at 12pt | Fails AA for normal text |
| BereanDynamicIsland.swift ~L385 | "thinking" status text | `BereanIslandColor.auraCyan.opacity(0.75)` on dark island bg | Likely passes on dark bg — verify |
| BereanFollowUpChips.swift ~L139 | Chip text | `Color(white: 0.20)` on `Color(.secondarySystemBackground)` | ~7:1 — passes |
| BereanSmartPillSystem.swift ~L347 | Deselected pill text | `Color.primary` on `Color(.secondarySystemBackground)` | Passes |

**Most impactful failure:** The disabled mic button at opacity 0.38 is still tappable and actionable (it calls `onVoice()`), so it should meet contrast requirements, not be treated as purely decorative.

### Missing Reduce Motion Guards

| File | Element | Issue |
|------|---------|-------|
| BereanDynamicIsland.swift ~L278–305 | `startAuraAnimation()` — calls `withAnimation(.easeInOut(duration: 3.2).repeatForever(...))` and spark drift | No `reduceMotion` check before launching; the `BereanDynamicIsland` view does not inject `@Environment(\.accessibilityReduceMotion)` at all |
| BereanDynamicIsland.swift ~L627–639 | `startSnakeLoop()` — launches repeating path-tracing animations on the Canvas | No `reduceMotion` check |
| BereanDynamicIsland.swift ~L411–421 | `thinkingDots` — `scaleEffect` animation on `pulsing` state with no reduce-motion branch | No guard |
| BereanDynamicIsland.swift ~L443–458 | `thinkingContent` — 5 bars with `.easeInOut.repeatForever` animations on `pulsing` | No guard |
| BereanChatView.swift ~L1896–1897 | `heroSection` — `AmenHeroMarkView` + VStack use `Motion.adaptive(...)` but the hero compression scaleEffect at L1876 is not guarded | Low risk; outer `Motion.adaptive` likely wraps `reduceMotion`, but verify |
| BereanChatView.swift ~L1172 | `animation(.easeInOut(duration: 0.25), value: showSavedToNotesToast)` on toast overlay | No `reduceMotion` guard — should be `.animation(reduceMotion ? .none : ...)` |

**Critical:** The Dynamic Island aura blob with a 3.2-second repeating animation, parallax offset, and rotation is directly violating WCAG 2.3.3 (Animation from Interactions). Users with vestibular disorders who have Reduce Motion enabled will still see the full looping blob.

### Missing Reduce Transparency Guards

| File | Element | Issue |
|------|---------|-------|
| BereanChatView.swift ~L1291–1373 | `smartBlurHeader` — uses `.ultraThinMaterial` for the entire header background without a `reduceTransparency` branch | On high-contrast mode, the material provides poor contrast |
| BereanChatView.swift ~L2082–2093 | `adaptivePromptSurface` — `.ultraThinMaterial` fill + `Color.white.opacity(0.58)` overlay. If `reduceTransparency` is on, content behind bleeds through | Should substitute `Color(.systemBackground)` |
| BereanChatView.swift ~L2115–2120 | `heroPromptChipRow` chip backgrounds | `.ultraThinMaterial` with no `reduceTransparency` branch |
| BereanDynamicIsland.swift (entire file) | No `@Environment(\.accessibilityReduceTransparency)` injected | The aura blob's translucent `RadialGradient` layers and the island card's `strokeBorder`/backdrop blur all lack reduce-transparency handling |
| BereanMessageMenuView.swift ~L66 | `.ultraThinMaterial` menu background | No `reduceTransparency` guard — should fall back to `Color(.systemBackground)` |
| BereanFollowUpChips.swift ~L228 | `BereanThinkingStatus` background `Capsule().fill(Color(.secondarySystemBackground))` | OK — uses a solid system color; no issue |

**Note:** Several files already handle this correctly (`BereanComposerBar`, `BereanModePickerSheet`, `BereanStructuredCardView`, `BereanSmartPillButton`). The gap is specifically in the Dynamic Island, message menu, and hero surfaces.

### Tap Target Violations

WCAG 2.5.5 requires 44×44pt minimum touch target.

| File | Element | Visual frame | Issue |
|------|---------|--------------|-------|
| BereanMessageMenuView.swift ~L50–63 | Each action button in 4-col `LazyVGrid` | `.frame(maxWidth: .infinity).padding(.vertical, 8)` — at 390pt screen width with 10pt padding and 6pt spacing: ~`(390 - 20 - 18) / 4 ≈ 88pt wide × ~36pt tall` | Height is ~36pt — fails 44pt minimum. No `.contentShape` override present |
| BereanDynamicIsland.swift ~L392–399 | xmark dismiss button | `.frame(width: 24, height: 24)` with `Circle` background | 24×24pt — critically small for a key dismiss control |
| BereanComposerBar.swift ~L289–303 | Utility "plus" button | `.frame(width: 40, height: 40)` | 40×40pt — misses 44pt by 4pt. No `.contentShape` extends it |
| BereanComposerBar.swift ~L362–387 | `micButton` | `.frame(width: 38, height: 38)` | 38×38pt — fails by 6pt |
| BereanComposerBar.swift ~L388–418 | `sendButton` | `.frame(width: 38, height: 38)` on the Circle | 38×38pt visual; the outer ZStack has no explicit frame override. Note: `BereanInputComposer` in BereanDesignSystem.swift uses `frame(width: 44, height: 44)` correctly; the `BereanCompactComposerBar` variant does not |
| BereanComposerBar.swift ~L420–437 | `stopButton` | `.frame(width: 38, height: 38)` | 38×38pt |
| BereanProvenanceChips.swift ~L14–36 | `BereanProvenanceChip` | `.padding(.horizontal, 10).padding(.vertical, 6)` on a chip with ~12pt text | Vertical height ≈ 12 + 12 = 24pt. Fails — but provenance chips are informational more than navigation; still should meet 44pt or add `.contentShape` |

---

## Performance Summary

**Overall score: B (Solid architecture, 4 targeted concerns)**

The ViewModel is `@MainActor final class` — correct. `LazyVStack` is used for the message list — correct for large threads. The `BereanScrollCoordinator` throttles at 60ms. Streaming auto-scroll is debounced at 100ms. `BereanChatMsg` is `Identifiable` with stable `UUID` IDs.

**Most critical bottlenecks:**
1. Streaming token append hits `@Published var messages` on **every chunk** — this triggers a full `ObservableObject` diff and redraws the entire message list for each character
2. `loadMessageCount()` uses a `DispatchQueue.main.async` completion handler inside a `@MainActor` class — should be `await MainActor.run { }` or an async function
3. `BereanDynamicIsland.typeText(_:)` appends one character per 16ms (~60fps) to a `@Published var displayedText` — causes 60 view redraws/second on the island overlay
4. `adaptivePromptSurface` and `heroSection` recompute `heroCompressionProgress` (which reads `composerVM.collapseProgress`) on every `body` call — these are non-trivial closures re-evaluating on scroll

---

## Performance — Detail

### Scroll Performance Risks

| File | Issue | Estimated impact on 200-message thread |
|------|-------|---------------------------------------|
| BereanChatView.swift ~L1471 | `LazyVStack(spacing: 0)` correctly wraps the outer content, but inside it there is a **nested `LazyVStack(spacing: 16)`** at ~L1538 for the messages. Nested `LazyVStack` inside `LazyVStack` can break cell recycling — outer lazy stack materializes the inner lazy stack as a single cell | At 200 messages, the inner `LazyVStack` may allocate all 200 rows at once when the outer row becomes visible. Consider flattening to a single `LazyVStack` or using `List` |
| BereanChatView.swift ~L1565–1572 | `GeometryReader` inside `LazyVStack.background` for `ContentHeightKey` preference — fires on every layout pass | Low individual cost but runs on every scroll frame alongside `ScrollOffsetPreference`; combined causes 2 preference passes per frame |
| BereanChatView.swift ~L1619–1622 | `onChange(of: vm.messages.last?.content)` — fires for every streaming chunk | With auto-scroll debounce at 100ms this is acceptable, but if the stream is fast the `last?.content` Optional extraction and scroll evaluation still happens every chunk |
| BereanChatView.swift ~L1471 | Outer `LazyVStack` wraps hero section + study surface + messages in a single stack — hero section contains `adaptivePromptSurface` with multiple `scaleEffect` + `opacity` modifiers that re-evaluate `heroCompressionProgress` | On scroll, the hero is re-laid out unnecessarily before it disappears; consider removing it from layout when `showHero == false` with an `if showHero { ... }` guard around the inner cards too |

### Main Thread Safety

| File | Issue |
|------|-------|
| BereanChatView.swift ~L706–713 | `loadMessageCount()` uses old-style Firestore callback + `DispatchQueue.main.async { self?.messageCount = ... }` inside a `@MainActor` ViewModel. The `DispatchQueue.main.async` hop is redundant but also unsafe because it captures `[weak self]` across the actor boundary without `await`. Should be an `async` function with `await` at the call site |
| BereanDynamicIsland.swift ~L84–88 | `Task { @MainActor [weak self] in try? await Task.sleep(nanoseconds: 200_000_000); self?.responseText = "" }` — this is correct but uses raw nanosecond sleep; should use `Task.sleep(for: .milliseconds(200))` for clarity |
| BereanComposerBar.swift ~L190–197 | `streamingHapticTask` runs `BereanHapticCoordinator.shared.fireSentencePulse()` from an unstructured `Task` — if `BereanHapticCoordinator` is not `@MainActor`, haptic calls land on a background executor. Verify isolation |

### Streaming Performance

| File | Issue | Recommended fix |
|------|-------|----------------|
| BereanChatView.swift ~L461–463 | `for try await chunk in stream { messages[assistantIndex].content += chunk }` — each `+=` on a `@Published` array element fires `objectWillChange` (because `messages` is `@Published var messages: [BereanChatMsg]`). At ~50 chars/sec this is 50 `willChange` publishes/sec, each causing `BereanChatView.body` to re-evaluate | Batch chunks into a local buffer and flush to `@Published` at a fixed interval (e.g. 80ms). Use a separate `@Published var streamBuffer: String` and apply to `messages` in the debounce timer already present for scroll |
| BereanDynamicIsland.swift ~L139–148 | `typeText(_:)` appends one character per `16_000_000` nanoseconds (≈16ms, 60fps) to `@Published var displayedText`. This is 60 publishes/second on the island overlay | Reduce to 30ms (33fps) for the island — the island text is small and users won't perceive the difference. Or batch 3-4 characters per tick |

### Other Performance Issues

| File | Issue | Severity |
|------|-------|----------|
| BereanChatView.swift ~L2783–2791 | `messageAccessibilityLabel(_:)` creates a new `DateFormatter` **on every call** inside `structuredMessageView` — called for every message in the `ForEach` | Medium — `DateFormatter` is expensive to allocate; hoist to a `static let` or `@State private var` |
| BereanChatView.swift ~L1860–1862 | `composerFollowUpChips` computed property calls `vm.messages.last(where:)` — evaluated in `body`, which is called on every state change | Low — `messages` array is small, but prefer caching in a `let` binding outside `VStack` |
| BereanFollowUpChips.swift ~L105–107 | `chips` computed property in `BereanFollowUpChipRow.body` calls `BereanResponseChip.chips(forModeID:responseHint:)` — `responseHint.lowercased()` runs on every body eval | Low — `responseHint` is a let; cache with `private var chips: [BereanResponseChip]` stored in `init` or use `let` at the `chips` call site |
| BereanSmartPillSystem.swift ~L200–207 | `pills` computed property calls `BereanScriptureReferenceExtractor.references(in: message.content)` — regex extraction on full message content on every body call | Medium — if `message.content` is a multi-kilobyte AI response, this regex runs on every layout. Cache result in an `@State` or use `.task(id: message.id)` |
| BereanChatView.swift ~L893–898 | Top-level `body` is wrapped in `GeometryReader { proxy in ... }` — `GeometryReader` causes its parent to fill available space and triggers a layout pass whenever any child changes size. The inner content's preference-key system (scroll offset + content height) means layout and preference propagation happen in two passes per scroll event | Medium — accepted cost for this pattern, but the outer `GeometryReader` should not wrap sheets/overlays unnecessarily |
| BereanDynamicIsland.swift ~L643–656 | `cardWidth` and `topInset` computed properties both traverse `UIApplication.shared.connectedScenes` on every `body` call. These are called inside the `islandCard` view which re-renders on `vm.state` changes | Low — cache in `.onAppear` or observe once from a `UIWindowScene` notification |

---

## Findings Summary Table

| # | File | Category | Severity | Description |
|---|------|----------|----------|-------------|
| A1 | BereanDynamicIsland.swift | Reduce Motion | Critical | Aura blob + snake loop animations have no `reduceMotion` guard |
| A2 | BereanMessageMenuView.swift | Tap Target | High | 10-button action grid height ~36pt — fails 44pt minimum |
| A3 | BereanDynamicIsland.swift | Tap Target | High | xmark dismiss button 24×24pt |
| A4 | BereanChatView.swift | Dynamic Type | High | 56pt + 28pt fixed hero fonts will not scale |
| A5 | BereanChatView.swift | VoiceOver | High | Back button, hero chips, and follow-up dismiss button unlabeled |
| A6 | BereanDynamicIsland.swift | VoiceOver | High | 3 action buttons (xmark, Open Full, Copy) have no `.accessibilityLabel` |
| A7 | BereanDynamicIsland.swift | Reduce Transparency | Medium | No `reduceTransparency` environment variable injected anywhere in file |
| A8 | BereanComposerBar.swift | Tap Target | Medium | Plus, mic, send, stop buttons all 38–40pt (not 44pt) |
| A9 | BereanComposerBar.swift | Contrast | Medium | Mic button at opacity 0.38 (~2.3:1) when disabled but still interactive |
| A10 | BereanChatView.swift | Reduce Transparency | Medium | Header, hero card, prompt chips use `.ultraThinMaterial` with no fallback |
| A11 | BereanFollowUpChips.swift | VoiceOver | Low | Chip buttons missing `.accessibilityHint` |
| P1 | BereanChatView.swift | Streaming perf | Critical | Every streaming chunk publishes to `@Published messages` triggering full view diff |
| P2 | BereanDynamicIsland.swift | Streaming perf | High | `typeText` publishes 60 times/second to `@Published displayedText` |
| P3 | BereanChatView.swift | Scroll perf | High | Nested `LazyVStack` inside `LazyVStack` may defeat cell recycling at 200+ messages |
| P4 | BereanChatView.swift | Main thread | Medium | `loadMessageCount()` uses `DispatchQueue.main.async` in `@MainActor` class |
| P5 | BereanSmartPillSystem.swift | Compute | Medium | `BereanScriptureReferenceExtractor.references()` regex runs on every `body` call |
| P6 | BereanChatView.swift | Compute | Medium | `messageAccessibilityLabel` allocates `DateFormatter` on every message render |

---

## Quick Wins (can fix in < 30 min each)

1. **Add `.accessibilityLabel("Back")` to the chevron.left button** in `smartBlurHeader` (1 line)
2. **Add `.accessibilityLabel("Close Berean response")` to the Dynamic Island xmark** (1 line)
3. **Add `.accessibilityLabel("Open full Berean response")` and `.accessibilityLabel("Copy response")` to the two island action buttons** (2 lines)
4. **Inject `@Environment(\.accessibilityReduceMotion) private var reduceMotion` into `BereanDynamicIsland`** and guard `startAuraAnimation()` and `startSnakeLoop()` — reduces vestibular risk
5. **Hoist `DateFormatter` in `messageAccessibilityLabel` to a static/instance property** — eliminates repeated allocation
6. **Reduce `typeText` interval from 16ms to 30ms** — halves island render pressure with zero perceptible difference
7. **Add `.contentShape(Rectangle().size(CGSize(width: 44, height: 44)))` to the 38pt composer buttons** (mic, send, stop) — enlarges hit area without changing visual size
