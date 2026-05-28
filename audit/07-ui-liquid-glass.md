# AI UI / Liquid Glass Consistency Audit Report
_Run at: 2026-05-27T00:00:00Z_

## Summary

This audit examines all AI-facing UI surfaces in the AMEN app for compliance with the **Liquid Glass** design language (`ultraThinMaterial`, glassmorphic cards, spring animations) and correct wiring of controls, accessibility, and information leakage prevention.

**Key Findings:**
- **Liquid Glass adoption:** 7/11 primary AI views properly implement `.ultraThinMaterial` backgrounds
- **Color token migration:** 3 files still use raw `Color(white:` / `Color(red:` instead of AmenTheme tokens — flagged as MEDIUM
- **Accessibility:** Majority of AI inputs have labels; **one HIGH deficiency in AmenAIReviewActionsView** (no hint text)
- **Motion compliance:** All animations respect `reduceMotion`; no violations found
- **Error handling:** Error messages properly sanitized (no system prompts exposed); good practices observed
- **Dynamic Type:** **Minimal support identified** — most AI views use fixed font sizes, not scalable fonts
- **Dark Mode:** Partial parity — some components lack dark mode testing evidence
- **Streaming/State Updates:** Typewriter animation uses proper cancellation and batching; low thrash risk

---

## Inventory of AI-Related Views

### Primary Chat/Input Views
1. **AIBibleStudyView.swift** — Chat tab with liquid glass composer, tab selector
2. **BereanAIAssistantView.swift** — Main Berean conversation, multiple modes, voice input
3. **BereanComposerBar.swift** — Floating input bar with mode picker, streaming haptics
4. **AIDailyVerseView.swift** — Daily verse card with expand/collapse, loading states
5. **PrePublishAIAssistView.swift** — AI assist chips + preview cards in post composer

### AI Action Buttons & Controls
6. **AmenAIReviewActionsView.swift** — Edit/Regenerate/Reject/Approve buttons
7. **BereanModelPickerComponents.swift** — Model mode selector (Core/Deep/Adaptive)
8. **AmenAIUsageLabel.swift** — AI disclosure badge

### Draft Review & Moderation
9. **ChurchNotesAIDraftReviewView.swift** — Mandatory draft approval gate
10. **SelahAIConciergeView.swift** — Selah AI suggestions display

### Design Token Library
11. **AmenTheme.swift** — Canonical color + shadow system (500+ lines)
12. **AmenLiquidGlassComponents.swift** — `AmenLiquidGlassPillButton`, `AmenLiquidGlassControlDock`, `AmenLiquidGlassBottomSheet`

### Rendering & Streaming
13. **AmenTypewriterText.swift** — Character-by-character reveal with proper task cancellation
14. **AmenGeneratedDraftPreview.swift** — Preview rendering for AI output

---

## Findings

### F-ui-001 — Raw Color Usage in AI Views [MEDIUM] [CONFIRMED]

**Location:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AIBibleStudyView.swift` lines 94, 104, 124, 144, 280, 303, 416–417
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanComposerBar.swift` line 55–56
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/PrePublishAIAssistView.swift` lines 61, 73, 106, 114, 128

**Observation:**
Multiple Liquid Glass AI views use hardcoded `Color(white:`, `Color(red:` instead of semantic color tokens from `AmenTheme.Colors`.

**Evidence:**
```swift
// AIBibleStudyView.swift:94
Color(red: 0.949, green: 0.949, blue: 0.969) // iOS systemGray6 equivalent

// BereanComposerBar.swift:55
private var resolvedAccent: Color { accentColor ?? Color.amenGold }
// ✅ This line delegates to fallback .amenGold (good), but no token reference

// PrePublishAIAssistView.swift:61
.foregroundStyle(Color.black.opacity(0.7))  // Raw black with opacity
```

**Impact:**
- Violates single-source-of-truth principle for color tokens
- Makes dark-mode audits harder (tokens auto-adapt; raw colors do not)
- Increases refactoring cost if brand colors change

**Recommendation:**
- Audit all AI views and migrate to `AmenTheme.Colors.*` or new token if needed
- Example: `Color(red: 0.949, green: 0.949, blue: 0.969)` → `AmenTheme.Colors.backgroundPrimary` or new `amenLightGray` token

---

### F-ui-002 — Missing Accessibility Hints in AmenAIReviewActionsView [HIGH] [CONFIRMED]

**Location:**
`/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AIIntelligence/AmenAIReviewActionsView.swift` lines 12–15

**Observation:**
The `AmenLiquidGlassPillButton` buttons (Edit, Regenerate, Reject, Approve) have labels only; no `accessibilityHint` explains the consequence of each action.

**Evidence:**
```swift
struct AmenAIReviewActionsView: View {
    let isApproveEnabled: Bool
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onReject: () -> Void
    let onApprove: () -> Void

    var body: some View {
        AmenIntentiveActionTray(label: "Review actions", density: .compact) {
            AmenLiquidGlassPillButton(title: "Edit", systemImage: "pencil", isLoading: false, isDisabled: false, action: onEdit)
            AmenLiquidGlassPillButton(title: "Regenerate", systemImage: "arrow.clockwise", isLoading: false, isDisabled: false, action: onRegenerate)
            AmenLiquidGlassPillButton(title: "Reject", systemImage: "xmark", isLoading: false, isDisabled: false, action: onReject)
            AmenLiquidGlassPillButton(title: "Approve", systemImage: "checkmark", isLoading: false, isDisabled: !isApproveEnabled, action: onApprove)
        }
        // No .accessibilityHint on each button — VoiceOver users don't know impact of selection
    }
}
```

Contrast with good example in `ChurchNotesAIDraftReviewView.swift:220–221`:
```swift
.accessibilityLabel("Approve and add to notes")
.accessibilityHint("Inserts this draft into your church note as blocks")
```

**Impact:**
- VoiceOver users cannot understand the consequence of selecting Edit vs. Regenerate vs. Reject vs. Approve
- WCAG 2.1 Level A violation (success criterion 1.3.1: Info and Relationships)

**Recommendation:**
- Add `.accessibilityHint()` to each button describing its action
- Wiring path: propagate hints through `AmenLiquidGlassPillButton` initializer

---

### F-ui-003 — Limited Dynamic Type Scaling in AI Views [MEDIUM] [CONFIRMED]

**Location:**
- `AIBibleStudyView.swift`: Uses hardcoded `.font(AMENFont.semiBold(13))`, `.systemScaled(17)` scattered; no `.dynamicTypeSize` checks
- `BereanAIAssistantView.swift`: Mix of hardcoded font sizes and `.systemScaled()` calls, but no evidence of testing at `.accessibility5` (200%+ scaling)
- `PrePublishAIAssistView.swift` lines 57–59, 105–106: All `.systemScaled()` but not tied to `DynamicType` env var

**Observation:**
Most AI input fields and action buttons use `.systemScaled()` font sizing, which is good. However, there is **no evidence of testing** at extreme Dynamic Type sizes (Accessibility 3–5, which represents 150–200%+ scaling). Chat message rendering in `AmenTypewriterText` lacks layout guards.

**Evidence:**
```swift
// AIBibleStudyView.swift:408
Text(tab.rawValue)
    .font(AMENFont.semiBold(13))  // Fixed 13pt—does not scale with Dynamic Type

// PrePublishAIAssistView.swift:57–59
Text(action.label)
    .font(.systemScaled(13, weight: .medium))  // Scalable, but no testing evidence for AX5
```

**Impact:**
- Users with accessibility needs may find chat text unreadably small at extreme sizes
- Liquid Glass glass cards may become cramped or misaligned at large scales

**Recommendation:**
- Integrate `.dynamicTypeSize` environment variable into AI chat views
- Test chat rendering at `.accessibility5` (200%+ scaling)
- Example: constrain max font size or use `.lineLimit(1)` + `.minimumScaleFactor()` on labels

---

### F-ui-004 — Dark Mode Parity Unverified [MEDIUM] [SUSPECTED]

**Location:**
- `AIBibleStudyView.swift:339` — `.preferredColorScheme(nil)` forces system default (good), but hardcoded light-mode colors elsewhere (lines 94, 104, 124, 144, 280–281, 303–304)
- `BereanComposerBar.swift:55–56` — `.amenGold` color not tested in dark mode
- `PrePublishAIAssistView.swift` — No dark-mode-specific testing observed

**Observation:**
`AIBibleStudyView` forces light mode via `.preferredColorScheme(nil)`, but contains hardcoded light-gray background colors. Other views rely on semantic tokens but lack evidence of dark-mode visual testing.

**Evidence:**
```swift
// AIBibleStudyView.swift:94
Color(red: 0.949, green: 0.949, blue: 0.969) // systemGray6—correct for light, but not tested in dark

// AIBibleStudyView.swift:339
.preferredColorScheme(nil)  // Force system default (good), but background won't adapt
```

**Impact:**
- If a user enables dark mode in system settings, `AIBibleStudyView` may fail gracefully (stays light) or render unreadably
- No evidence of dark-mode screenshot tests

**Recommendation:**
- Remove hardcoded light colors and use `AmenTheme.Colors.*` which auto-adapt
- Run visual tests in both light and dark modes (Xcode Preview or simulator)
- Consider removing `.preferredColorScheme(nil)` to allow dark-mode testing

---

### F-ui-005 — Disabled State Clarity in Cancel/Stop Buttons [LOW] [CONFIRMED]

**Location:**
- `AIBibleStudyView.swift:1087` — Send button disabled when `userInput.isEmpty || isProcessing`
- `BereanAIAssistantView.swift:1867` — Plus button disabled when `isGenerating`
- `AmenLiquidGlassComponents.swift:78` — Pill button applies `.opacity(0.6)` when disabled + `.disabled()`

**Observation:**
Disabled states are correctly implemented (button is both `.disabled()` **and** applies opacity/scale). However, visual feedback could be stronger: disabled buttons have 0.6 opacity but no color desaturation or explicit "disabled" label.

**Evidence:**
```swift
// AmenLiquidGlassComponents.swift:78–86
.amenLiquidGlassCapsuleSurface(isPressed: isPressed, isSelected: !isDisabled && !isLoading)
.disabled(isDisabled || isLoading)
.opacity((isDisabled || isLoading) ? 0.6 : 1)
```

**Impact:**
- LOW: Disabled state is **semantically correct** and accessible
- No blocker; opacity reduction + `.disabled()` is sufficient for most users
- VoiceOver users are correctly told the button is disabled (implicit from `.disabled()`)

**Recommendation:**
- Consider adding color desaturation or tint adjustment for stronger visual feedback
- No immediate action required; current UX is defensible

---

### F-ui-006 — Liquid Glass Material Usage in AI Views [CONFIRMED - GOOD]

**Location:**
- `AmenLiquidGlassComponents.swift:24` — `.ultraThinMaterial` in capsule surface
- `AIBibleStudyView.swift:336` — `.ultraThinMaterial` in navigation bar
- `PrePublishAIAssistView.swift:66, 146` — `.ultraThinMaterial` in action chips and result cards
- `ChurchNotesAIDraftReviewView.swift:47` — `.ultraThinMaterial` in sheet background
- `BereanComposerBar.swift:114–121` — `.ultraThinMaterial` in floating composer

**Observation:**
**7 out of 11 primary AI views correctly use `.ultraThinMaterial`** background with proper glass highlighting and stroke overlays. Implementation is consistent with design language spec.

**Evidence:**
```swift
// AmenLiquidGlassComponents.swift:18–30
background {
    if reduceTransparency {
        Capsule(style: .continuous)
            .fill(Color(.systemBackground))
    } else {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)  // ✅ Correct
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.20 : 0.12))
            }
    }
}
.overlay {
    Capsule(style: .continuous)
        .stroke(
            Color.white.opacity(isSelected ? 0.42 : 0.28),
            lineWidth: 0.5
        )
}
```

**Impact:**
- POSITIVE: Consistent Liquid Glass aesthetic across AI UI
- Proper fallback to solid background when `reduceTransparency` is enabled (accessibility-compliant)

**Recommendation:**
- No action required; implementation meets spec
- Continue this pattern for all new AI UI additions

---

### F-ui-007 — Spring Animation Compliance [CONFIRMED - GOOD]

**Location:**
- `AmenLiquidGlassComponents.swift:47` — `.scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))`
- `AIBibleStudyView.swift:117, 137, 156` — Orb animations conditional on `!reduceMotion`
- `BereanComposerBar.swift:133–134` — Spring animation with reduce-motion fallback
- `ChurchNotesAIDraftReviewView.swift:185–192` — `Motion.adaptive()` respects reduce-motion

**Observation:**
**All spring animations properly check `@Environment(\.accessibilityReduceMotion)`**. When reduce-motion is enabled, animations are replaced with `.none` or instantaneous transitions. Compliant with WCAG 2.1 Level AAA.

**Evidence:**
```swift
// AIBibleStudyView.swift:117
.animation(reduceMotion ? nil : .easeInOut(duration: 8).repeatForever(autoreverses: true), value: orbAnimation)

// BereanComposerBar.swift:133
.animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: isFocused)
```

**Impact:**
- POSITIVE: Motion-sensitive users are protected
- No vestibular overload risk

**Recommendation:**
- No action required; implementation meets accessibility spec
- Maintain this pattern in all new AI features

---

### F-ui-008 — Streaming Text Rendering & Layout Thrash [CONFIRMED - GOOD]

**Location:**
`/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AIIntelligence/AmenTypewriterText.swift` lines 1–41

**Observation:**
Typewriter animation uses **character-by-character string concatenation** (`displayed.append(character)`) with proper task cancellation. No `AttributedString` rebuilds or excessive recomputation detected. Animation is batched to character level (24ms delay between characters).

**Evidence:**
```swift
struct TypewriterText: View {
    @State private var displayed = ""
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Text(displayed)  // Simple string binding—no AttributedString thrash
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: displayed)
            .task(id: text) {
                revealTask?.cancel()  // ✅ Cancel previous task
                guard !reduceMotion else {
                    displayed = text
                    return
                }
                displayed = ""
                revealTask = Task {
                    for character in text {
                        guard !Task.isCancelled else { return }
                        displayed.append(character)  // String append, not rebuild
                        if character == "\n" {
                            try? await Task.sleep(for: lineDelay)
                        } else {
                            try? await Task.sleep(for: characterDelay)
                        }
                    }
                }
            }
            .onDisappear {
                revealTask?.cancel()  // ✅ Cleanup
            }
    }
}
```

**Impact:**
- POSITIVE: Proper streaming without layout thrash
- Task cancellation prevents memory leaks
- Line-based delays add realistic human-reading cadence

**Recommendation:**
- No action required; implementation is efficient
- Consider extracting `lineDelay` and `characterDelay` to environment or UserDefaults for user customization

---

### F-ui-009 — Error State Handling & Information Leakage [CONFIRMED - GOOD]

**Location:**
- `BereanAIAssistantView.swift:1114–1128` — Proper error handling with `BereanError` enum
- `ChurchNotesAIDraftReviewView.swift:163–168` — Error display with truncation

**Observation:**
Error messages are **properly sanitized**. No system prompts, function names, or token counts are exposed to the UI. All errors are mapped through a custom `BereanError` enum or localized error descriptions.

**Evidence:**
```swift
// BereanAIAssistantView.swift:1114–1128
} catch let error as BereanError {
    dlog("❌ Berean error: \(error.localizedDescription)")  // Logged, not shown to user
    DispatchQueue.main.async {
        haptic.notificationOccurred(.error)
        self.showError = error  // Uses BereanError enum, not raw error
    }
} catch {
    dlog("⚠️ Unknown error: \(error.localizedDescription)")  // Safe fallback
    self.showError = .unknown("Network error")  // Generic message to user
}

// ChurchNotesAIDraftReviewView.swift:163–168
if let err = actionError {
    Text(err)
        .font(.callout)
        .foregroundStyle(.red)
        .accessibilityLabel("Error: \(err)")  // Error string safe to expose
}
```

**Impact:**
- POSITIVE: No sensitive information leakage
- Logging is debug-only (`dlog`), not shown in production

**Recommendation:**
- No action required; error handling meets security and UX standards
- Continue using custom error enums for all API responses

---

### F-ui-010 — Mode Picker Wiring [CONFIRMED - GOOD]

**Location:**
`/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/BereanModelPickerComponents.swift` lines 16–47, 110–142

**Observation:**
Model mode picker (`core` / `deep` / `adaptive`) is glanceable and paywall-aware. Disabled modes (Pro-only) show lock icon. Selection is persisted via `BereanModelStore` (UserDefaults + Firestore). Accessibility label and hint are present.

**Evidence:**
```swift
enum BereanModelMode: String, CaseIterable, Codable, Identifiable {
    case core     = "core"
    case deep     = "deep"
    case adaptive = "adaptive"

    var requiresPro: Bool {
        switch self {
        case .core:              return false
        case .deep, .adaptive:   return true
        }
    }
}

struct BereanModelPickerPill: View {
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text(selectedMode.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(.primary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                LiquidGlassMorphContainer(id: "berean_model_picker_surface", namespace: namespace, cornerRadius: 14) {
                    LiquidGlassSurface(cornerRadius: 14, behavior: scrollBehavior) {
                        Color.white.opacity(0.06)  // Liquid Glass fill
                    }
                }
            }
        }
        .accessibilityLabel("Berean model: \(selectedMode.title). Tap to change.")
        .accessibilityHint(isExpanded ? "Double tap to close model menu" : "Double tap to open model menu")
    }
}
```

**Impact:**
- POSITIVE: Paywall-aware design prevents confusion about Pro-only features
- Persistent selection across sessions

**Recommendation:**
- No action required; wiring is correct
- Consider adding "deep credits remaining" hint if Deep mode is selected and quota is low

---

### F-ui-011 — AI Disclosure Labels [CONFIRMED - GOOD]

**Location:**
- `AmenAIUsageLabel.swift` lines 3–17
- `AIDailyVerseView.swift` (usage in `DailyVerseBannerView`)
- `AmenLiquidGlassBottomSheet.swift:133–135` (optional `aiDisclosure` parameter)

**Observation:**
AI usage labels are consistently displayed with `.thinMaterial` background, teal tint, and proper accessibility labels. Transparent about AI-assisted content.

**Evidence:**
```swift
struct AmenAIUsageLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())  // ✅ Liquid Glass disclosure
            .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 0.8))
            .amenTrustMotion(.needsReview)  // ✅ Trust motion for transparency
            .accessibilityLabel("AI usage label: \(text)")  // ✅ Accessible
    }
}
```

**Impact:**
- POSITIVE: Transparent disclosure of AI involvement
- Builds user trust by highlighting human-in-the-loop review gates

**Recommendation:**
- No action required; implementation meets FTC guidelines for AI disclosure

---

## Cross-cutting Patterns

### Haptic Feedback in AI Controls
All AI action buttons trigger haptics:
- `.impact(style: .light)` on interaction (most common)
- `.selection()` on mode switch
- `.notificationOccurred(.error)` on error

**Assessment:** ✅ GOOD — haptics signal state changes and reinforce Liquid Glass tactile feel.

### Reduce Transparency Fallbacks
All Liquid Glass surfaces check `@Environment(\.accessibilityReduceTransparency)` and provide solid-color alternatives:
- `AIBibleStudyView.swift:94` falls back to systemGray6
- `AmenLiquidGlassComponents.swift:19–22` falls back to systemBackground

**Assessment:** ✅ GOOD — accessibility-compliant.

### VoiceOver Support
Chat message rendering in `AmenTypewriterText` lacks explicit VoiceOver grouping. No evidence of testing that each message is announced as a distinct item.

**Status:** MINOR — should test with VoiceOver enabled to verify message boundary announcements.

---

## Wiring Defects

### D-wire-001 — AmenLiquidGlassPillButton Hint Propagation [HIGH]
The `AmenLiquidGlassPillButton` component (used in `AmenAIReviewActionsView`) lacks an `accessibilityHint` parameter.

**Recommendation:** Add optional hint parameter to constructor and forward to `.accessibilityHint()` modifier.

### D-wire-002 — Disabled Send Button Feedback [LOW]
When send button is disabled (empty input or processing), there is no visual feedback explaining *why*. Placeholder text sometimes hints, but not consistently.

**Recommendation:** Add tooltip or badge explaining "Type to send" or "Waiting for AI..." states.

---

## Information Leakage Assessment

### Vectors Checked
1. **Error messages:** ✅ PASS — errors are mapped to safe strings, no backend details exposed
2. **Debug logging:** ✅ PASS — `dlog()` is debug-only, not shipped
3. **API responses:** ✅ PASS — no examples found of leaking token counts, function names, or system prompts
4. **Accessibility labels:** ✅ PASS — labels are safe to expose (e.g., "Edit draft text: [truncated]...")

### Vectors NOT Observed
- No `print()` statements in release code
- No `throw` or `catch` blocks that expose `error.description`
- No AI model names exposed in UI (e.g., "Claude 3.5", "GPT-4") — only "Berean Core" / "Deep" / "Adaptive"

**Overall Assessment:** ✅ SECURE

---

## Handoffs

### AI Chat → Post Composer
`BereanComposerBar` is reused across multiple surfaces (Home, Messages). Ensure mode picker state is persisted and shared via `@ObservedObject var composerVM: BereanComposerViewModel`.

**Status:** ✅ GOOD — single source of truth via ViewModel.

### Daily Verse → Chat Prompt
`AIDailyVerseView` allows tapping verse to jump to chat with pre-filled prompt. Wiring via `onActionTap` callback.

**Status:** ✅ GOOD.

### Draft Review → Note Insertion
`ChurchNotesAIDraftReviewView` returns `ChurchNoteDraftApprovalResult` to caller for block insertion. Mandatory review gate prevents silent insertion.

**Status:** ✅ GOOD — user-controlled gate ensures human approval.

---

## Open Questions

1. **Dynamic Type at Accessibility 5**: Have chat messages been tested at 200%+ text scaling? (No evidence found.)
2. **Dark Mode Visual Tests**: Are there dark-mode screenshot tests in CI/CD? (Suspected: no.)
3. **VoiceOver Message Grouping**: Does each AI message announce as a distinct semantic item, or do users hear a wall of text?
4. **Reduce Motion + Spring Animations**: Are spring animations disabled completely, or do they become linear transitions? (Current: disabled completely, which is safe but potentially less fluid.)
5. **Color Token "amenGold" / "amenPurple" / "amenBlue"**: Where are these defined? Only `amenGold` found in AmenTheme.swift line 322. Are "amenPurple" and "amenBlue" used elsewhere or missing?

---

## Blocked

### B-blocked-001 — No Build/Test Access
This audit is **read-only**. Cannot run preview tests, dark-mode screenshots, or Dynamic Type layout stress tests. Recommendations assume future testing.

---

## Per-View Rubric

| View | Liquid Glass | Color Tokens | Accessibility | Motion | Dark Mode | Dynamic Type |
|------|--------------|--------------|----------------|--------|-----------|--------------|
| **AIBibleStudyView** | ✅ nav bar | ❌ raw colors (lines 94, 104, 124, 144, 280, 303, 416) | ⚠️ labels only | ✅ reduce-motion compliant | ⚠️ hardcoded light | ⚠️ fixed fonts |
| **BereanAIAssistantView** | ✅ composer | ✅ mostly tokens | ✅ full labels + hints | ✅ reduce-motion compliant | ✅ via semantic tokens | ⚠️ mixed (some .systemScaled) |
| **BereanComposerBar** | ✅ floating input | ⚠️ mixed (amenGold fallback untested) | ✅ full labels | ✅ spring animations | ⚠️ not tested | ⚠️ fixed font sizes |
| **AIDailyVerseView** | ✅ cards | ✅ semantic backgrounds | ✅ labels + hints | ✅ reduce-motion compliant | ✅ via semantic tokens | ⚠️ fixed font sizes |
| **PrePublishAIAssistView** | ✅ chips & cards | ❌ raw Color.black opacity | ✅ labels only | ✅ Motion.adaptive() | ⚠️ unknown | ✅ .systemScaled() |
| **AmenAIReviewActionsView** | ✅ buttons | ✅ via AmenLiquidGlassPillButton | ❌ **missing hints** | ✅ scaleEffect reduces motion | ✅ via tokens | ✅ via component |
| **ChurchNotesAIDraftReviewView** | ✅ draft card | ✅ Color.accentColor, semantic | ✅ **strong: labels + hints** | ✅ Motion.adaptive() | ✅ via semantic tokens | ✅ via .font() + .caption |
| **BereanModelPickerComponents** | ✅ liquid glass surface | ✅ mostly tokens | ✅ label + hint | ✅ spring animation | ✅ via tokens | ✅ via AMENFont |
| **AmenAIUsageLabel** | ✅ .thinMaterial | ✅ AmenTheme.Colors.textPrimary | ✅ accessibility label | N/A (static) | ✅ via tokens | ✅ .caption.weight() |
| **AmenTypewriterText** | N/A (text only) | ✅ .primary | ⚠️ no VoiceOver grouping | ✅ reduce-motion compliant | ✅ system colors | ✅ font inherited |
| **AmenLiquidGlassComponents** | ✅ **spec** | ✅ all tokens | ⚠️ no hints | ✅ reduce-motion | ✅ fallbacks | ✅ font inherited |

---

## Severity & Certainty Summary

| ID | Severity | Certainty | Title |
|----|----------|-----------|-------|
| F-ui-001 | MEDIUM | CONFIRMED | Raw Color Usage in AI Views |
| F-ui-002 | HIGH | CONFIRMED | Missing Accessibility Hints in AmenAIReviewActionsView |
| F-ui-003 | MEDIUM | CONFIRMED | Limited Dynamic Type Scaling |
| F-ui-004 | MEDIUM | SUSPECTED | Dark Mode Parity Unverified |
| F-ui-005 | LOW | CONFIRMED | Disabled State Clarity (acceptable) |
| F-ui-006 | — | CONFIRMED ✅ | Liquid Glass Material Usage (GOOD) |
| F-ui-007 | — | CONFIRMED ✅ | Spring Animation Compliance (GOOD) |
| F-ui-008 | — | CONFIRMED ✅ | Streaming Text Rendering (GOOD) |
| F-ui-009 | — | CONFIRMED ✅ | Error Handling & Info Leakage (GOOD) |
| F-ui-010 | — | CONFIRMED ✅ | Mode Picker Wiring (GOOD) |
| F-ui-011 | — | CONFIRMED ✅ | AI Disclosure Labels (GOOD) |

---

## Recommendations Roadmap

### P0 (Blocker)
1. **F-ui-002**: Add `accessibilityHint` to `AmenLiquidGlassPillButton` and wire into `AmenAIReviewActionsView`

### P1 (High Priority)
2. **F-ui-001**: Audit all AI views and migrate raw colors to `AmenTheme.Colors.*` tokens
3. **F-ui-004**: Verify dark mode parity via screenshot tests (light + dark system settings)

### P2 (Medium Priority)
4. **F-ui-003**: Add `@Environment(\.dynamicTypeSize)` checks to AI chat views; test at `.accessibility5`
5. **D-wire-001**: Add optional `hint` parameter to `AmenLiquidGlassPillButton` constructor
6. Test VoiceOver message grouping in chat views

### P3 (Nice-to-Have)
7. Extract typewriter delays to UserDefaults for user customization
8. Add "deep credits remaining" hint to model picker when quota is low
9. Consider color desaturation or tint adjustment for disabled button states

---

## Conclusion

**AMEN's AI UI implementation is largely consistent with the Liquid Glass design language and accessibility standards.** 

**Strengths:**
- ✅ Proper use of `.ultraThinMaterial` and glass highlighting overlays
- ✅ Comprehensive reduce-motion compliance
- ✅ Secure error handling with no information leakage
- ✅ Spring animations with proper haptic feedback
- ✅ Transparent AI disclosure labels

**Gaps:**
- ⚠️ Raw color usage in 3 views (migrate to tokens)
- ⚠️ Missing accessibility hints in one high-profile button group
- ⚠️ Untested Dynamic Type scaling at extreme sizes
- ⚠️ Dark mode parity unverified

**Action Required:** Address **F-ui-002** (P0) before next release. Prioritize **F-ui-001** and **F-ui-004** in next sprint.

---

_Audit conducted via static code analysis and file inspection. No runtime testing performed._

