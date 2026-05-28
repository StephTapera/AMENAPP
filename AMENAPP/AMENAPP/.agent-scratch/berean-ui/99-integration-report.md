# Berean UI Rebuild — Integration Report (Updated)
_Agent I — Integration Verification — 2026-05-28_

## Branch
`berean/ui-rebuild-liquid-glass-v1`

---

## New Files Created (7)

| File | Path | Description |
|---|---|---|
| `BereanThreadCapsule.swift` | `AMENAPP/BereanThreadCapsule.swift` | Morphing nav capsule with 3 states (compact / collapsed / expanded). Compact shows mode pill + memory dot; collapsed shows a chevron only; expanded drawer shows full thread metadata. All 3 states spring-animated and reduceMotion-gated. |
| `BereanConversationSpine.swift` | `AMENAPP/BereanConversationSpine.swift` | Trailing-edge 12pt glass scrubber spine. One dot per message, color-coded by role and content type (user / aiNormal / aiCitation / aiStructured). Dots stagger in via `contentAppear` spring; tapping scrolls the ScrollViewProxy to the target message. |
| `BereanThinkingStrip.swift` | `AMENAPP/BereanThinkingStrip.swift` | 32pt translucent activity strip between the thread capsule and the message list. Driven by `@Binding var action: BereanThinkingAction` (9 states). Springs to 0pt height when `.idle`. Pulse dot + shimmer sweep both gated on `accessibilityReduceMotion`. |
| `BereanMemoryChip.swift` | `AMENAPP/BereanMemoryChip.swift` | Glass chip in the composer/microstate area. Shimmers gold→purple when `isActive`. Pulsing gold capsule border while active. Tapping opens `BereanMemoryDetailSheet` listing all memory entries. Both animations gated on `reduceMotion`. |
| `BereanMessageTray.swift` | `AMENAPP/BereanMessageTray.swift` | Floating pill tray for focused AI messages. Exposes Copy, Regenerate, Share, Audio, More. Springs in beneath the bubble; auto-dismisses on scroll. `.accessibilityActions` block exposes all 5 actions to VoiceOver without requiring a long-press gesture. |
| `BereanCitationTile.swift` | `AMENAPP/BereanCitationTile.swift` | Inline glass citation chip for provenance sources. Tapping expands a `BereanCitationDetailSheet` with cross-reference chips, confidence bar, and contextual note. Reference text uses `BereanColor.textPrimary` to meet WCAG AA. |
| `BereanComposerTray.swift` | `AMENAPP/BereanComposerTray.swift` | Capability-first adaptive composer tray. Shows quick-start suggestions (empty draft), scripture detection chip (gold pulse on ref), reasoning chips (question intent), and inline mode picker (5 modes) + expandable capabilities panel — all without presenting a sheet. |

---

## Phase 2 Fixes Applied (this session)

| Fix ID | File | What Changed | Audit Finding Closed |
|---|---|---|---|
| **Fix E-1** | `BereanConversationSpine.swift` | `SpineDot` outer frame expanded from `22×22pt` to `44×44pt` (`.contentShape(Rectangle())` already present); visual dot unchanged at `baseDiameter` | DS-finding #20 / A-12 equivalent — P0 WCAG 2.5.5 hit target violation |
| **Fix E-2** | `BereanConversationSpine.swift` | `SpineDot` now accepts `index: Int` and `total: Int`; `dotAccessibilityLabel` emits "Message N of M — Berean reply — citation-heavy" strings; call site in `dotColumn` passes `index + 1` and `messages.count` | A-C03-equivalent — no VoiceOver spatial orientation on spine dots |
| **Fix E-3** | `BereanConversationSpine.swift` | `BereanConversationSpineColors` private enum deleted; `SpineDotKind.dotColor` now uses `Color.amenPurple` / `Color.amenBlue` global tokens from `ChurchNotesDesignSystem.swift` | DS-finding #1 — hardcoded private RGB colors (DS-9) |
| **Fix E-4** | `BereanThreadCapsule.swift` | `.accessibilityHidden(true)` on collapsed-state mode pill changed to `.accessibilityHidden(false)`, restoring VoiceOver announcement of active personality mode in scrolled-collapsed state | A-C02-equivalent — mode capsule invisible to VoiceOver when compressed |
| **Fix F-1** | `BereanMemoryChip.swift` | `stopAnimations()` wraps `shimmerPhase = 0.0` and `borderPulse = false` inside `withAnimation(.none)` blocks; forcibly removes in-flight `repeatForever` CAAnimations rather than only resetting SwiftUI state | P-10 — `stopAnimations()` didn't cancel `repeatForever` animations |
| **Fix F-2** | `BereanMemoryChip.swift` | `startBorderPulse()` replaces `.easeInOut(duration: 1.1).repeatForever` with `capsuleSpring` (`.spring(response: 0.42, dampingFraction: 0.82).repeatForever`) | DS-finding #6 — non-spring interactive animation in border pulse |
| **Fix F-3** | `BereanMemoryChip.swift` | `.accessibilityHidden(true)` added to brain icon in `BereanMemoryDetailSheet.headerSection` | A-24 — VoiceOver read "brain image" before heading text |
| **Fix F-4** | `BereanThinkingStrip.swift` | `stopAnimations()` wraps `pulseScale = 1.0` and `shimmerPhase = 0.0` inside `withAnimation(.none)` blocks | P-11 — `stopAnimations()` didn't cancel `repeatForever` animations |
| **Fix F-5** | `BereanThinkingStrip.swift` | `startPulse()` replaces `.easeInOut(duration: 0.72).repeatForever` with `fastSpring` (`.spring(response: 0.28, dampingFraction: 0.88).repeatForever`); inline `.animation` on `pulseDot` updated to match | DS-findings #4 and #5 — non-spring pulse animation (two occurrences) |
| **Fix F-6** | `BereanThinkingStrip.swift` | `shimmerOverlay` `GeometryReader` gains `.accessibilityHidden(true)` | A-22 — shimmer GeometryReader visible to accessibility tree |
| **Fix F-7** | `BereanThinkingStrip.swift` | `let action` promoted to `@Binding var action: BereanThinkingAction`; previews updated to `.constant(action)` / `$action`; `BereanChatView.swift` call site updated from `action: currentThinkingAction` to `action: $currentThinkingAction` | Intelligence surface gap D-SSE-1 — strip only ever received `.drafting`; now parents can drive all 9 action states from SSE pipeline events |
| **Fix G-1** | `BereanMessageTray.swift` | `.accessibilityActions { }` block added to outer `ZStack` exposing Copy, Regenerate, Share, Read aloud, More as named VoiceOver custom actions | A-15 — ship-blocker: long-press tray inaccessible to VoiceOver (no `.accessibilityAction`) |
| **Fix G-2** | `BereanCitationTile.swift` | Primary chip `Text(source.reference)` and cross-reference chip `Text(ref.reference)` changed from `Color.amenGold` foreground to `BereanColor.textPrimary`; `Color.amenGold` retained for ornamental badge icon and confidence bar only; both texts gain `.dynamicTypeSize(.xSmall ... .accessibility3)` | A-23 — ship-blocker: `amenGold` on white glass ~2.8:1 contrast (WCAG AA fail at 11–13pt) |
| **Fix G-3** | `BereanCitationTile.swift` | Cross-reference `ScrollView` gains `.accessibilityLabel("Cross-references")`; citation detail sheet Close button gains `.accessibilityLabel("Close citation").accessibilityHint("Dismisses citation detail")`; icon images inside cross-reference chips marked `.accessibilityHidden(true)` | A-18, A-19 — citation sheet group label and close-button label missing |
| **Fix H-1** | `BereanComposerTray.swift` | `@State private var goldPulseTask: Task<Void, Never>? = nil` stored property added; `startGoldPulse()` calls `goldPulseTask?.cancel()` + resets state before creating new task; explicit `true`/`false` transitions with `guard !Task.isCancelled` between sleeps; `.onDisappear { goldPulseTask?.cancel() }` added to `scriptureDetectedChip` | P-07 — ship-blocker: unbounded concurrent goldPulse tasks on each scripture ref change (memory leak + CPU drain) |
| **Fix H-2** | `BereanComposerTray.swift` | Clarifying comment added above `reasoningReadyChip` confirming `Color.amenPurple` is the global token from `ChurchNotesDesignSystem.swift`; no private copy in this file | DS-9 promotion documentation |
| **Fix H-3** | `BereanComposerTray.swift` | `startGoldPulse()` spring changed from `response: 1.1, dampingFraction: 0.55` (slow, underdamped) to `response: 0.42, dampingFraction: 0.82` (matches tray's own animation modifiers) | DS-finding #6-equivalent — non-matching spring damping in pulse |

---

## Quality Bar Checklist

| Item | Status | Notes |
|---|---|---|
| All 7 new files compile without errors | PASS | Build 0 errors confirmed (second run after SPM transient resolve) |
| `@Binding var action` in ThinkingStrip + `$currentThinkingAction` at call site | PASS | Verified in `BereanThinkingStrip.swift` L85 and `BereanChatView.swift` L1002 |
| SpineDot hit target = 44×44pt | PASS | `BereanConversationSpine.swift` L184: `.frame(width: 44, height: 44)` confirmed |
| SpineDot VoiceOver labels include index + total | PASS | `dotAccessibilityLabel` at L198–208 confirmed with "Message N of M" pattern |
| Private RGB color enum (`BereanConversationSpineColors`) deleted | PASS | Not present in file; `SpineDotKind.dotColor` uses `Color.amenPurple` / `Color.amenBlue` |
| `stopAnimations()` uses `withAnimation(.none)` in MemoryChip | PASS | `BereanMemoryChip.swift` L213–214 confirmed |
| `stopAnimations()` uses `withAnimation(.none)` in ThinkingStrip | PASS | `BereanThinkingStrip.swift` L257–258 confirmed |
| `.easeInOut` pulse animation replaced with spring in ThinkingStrip | PASS | `startPulse()` uses `fastSpring` at L234; inline `.animation` on `pulseDot` at L173 uses `fastSpring` |
| `.easeInOut` border pulse replaced with spring in MemoryChip | PASS | `startBorderPulse()` uses `capsuleSpring` at L201 |
| `.accessibilityActions` block in BereanMessageTray | PASS | `BereanMessageTray.swift` L71–93 confirmed; exposes Copy, Regenerate, Share, Read aloud, More |
| `amenGold` on text replaced with `BereanColor.textPrimary` in CitationTile | PASS | Agent G confirmed; `Color.amenGold` retained only for ornamental badge/bar |
| goldPulseTask stored + cancelled in ComposerTray | PASS | `BereanComposerTray.swift` L73 property, L611 cancel-before-start, L248 `.onDisappear` cancel |
| All springs use approved presets (no `.easeInOut` in new files) | PASS (new files only) | All 7 new files: springs are `.spring(response:dampingFraction:)` only; shimmers use `.linear` (approved exempt) |
| `.ultraThinMaterial` backgrounds gated on `reduceTransparency` | PASS | All 7 files implement `reduceTransparency` fallback to solid system fills |
| `accessibilityReduceMotion` gating on all animations | PASS | All 7 files check `reduceMotion` before starting shimmer, pulse, or spring transitions |
| No `@MainActor` or Firestore code touched in service files | PASS | All changes confined to view/component files; no service files modified |

---

## Regression Checklist

| Regression Risk | Verification | Result |
|---|---|---|
| `BereanChatView` still compiles after `@Binding` change to ThinkingStrip | Read `BereanChatView.swift` L1002: `BereanThinkingStrip(action: $currentThinkingAction)` | PASS |
| `BereanConversationSpine` call site passes new `index:` and `total:` params | Read `BereanConversationSpine.swift` L107–108: `index: index + 1, total: messages.count` in `dotColumn` ForEach | PASS |
| `BereanMemoryChip` `stopAnimations()` does not conflict with `startShimmer()` guard | `startShimmer()` has no guard; `stopAnimations()` resets `shimmerPhase` via `.none`; `handleActiveChange` gates the call | PASS |
| `BereanComposerTray` `goldPulseTask` does not fire on every render (only `onAppear` + `onChange(of: ref)`) | L246–248 confirmed: `onAppear`, `onChange(of: ref)`, `onDisappear` only | PASS |
| `BereanMessageTray` `.accessibilityActions` does not conflict with `.onLongPressGesture` in parent `BereanChatView` | `.accessibilityActions` is a separate modifier on the tray itself; long-press is on parent; no conflict | PASS |
| Build passes after all changes | Two build runs: first failed with SPM dependency graph transient error; second succeeded in 31s | PASS |

---

## Known Gaps / Follow-on Work

These items are **not** fixed in this PR. They require model-layer changes, backend wiring, or are designated follow-on sprints.

### Crash Risk (do not ship without fixing)

| ID | Issue | File(s) | Notes |
|---|---|---|---|
| **CR-1** | `discernment` is referenced in `heroPrompt` (L2061) and `BereanComposerTray.primaryModes` (L82) but `BereanPersonalityMode` enum may not have a `.discernment` case depending on the model definition | `BereanChatView.swift`, `BereanComposerTray.swift`, `BereanAIAssistantView.swift` | This is a potential crash if a switch exhausts all `BereanPersonalityMode` cases and `.discernment` is an unrecognized value. Requires model-layer audit and enum addition before App Store submission. Flagged in intelligence audit finding D-CR-1. |

### Competitive Gaps (not addressed in this PR)

| ID | Gap | Severity | Audit Source |
|---|---|---|---|
| CG-1 | No inline markdown rendering in primary message path — `BereanStructuredResponseView` uses plain `Text()` | Critical | Competitive audit finding CG-1 |
| CG-2 | Attachments blocked by `showAttachmentsComingSoon` alert — photo/file upload non-functional | Critical | CG-2 |
| CG-3 | No edit-sent-message affordance | Critical | CG-3 |
| CG-4 | Regenerate is buried in context menu only (no persistent visible button) | High | CG-4 |
| CG-5 | No last-message preview in conversations list rows | High | CG-5 |
| CG-6 | No per-conversation delete (only Clear All with no confirmation) | High | CG-6, CG-16 |
| CG-7 | Voice output (TTS) `onAudio: {}` is a no-op — `BereanVoiceSpeechService` not wired | High | CG-7 |
| CG-8 | No `.scrollDismissesKeyboard(.interactively)` on ScrollView | High | CG-8 |
| CG-9 | No alternative response selection (N/M arrows) | High | CG-9 |
| CG-10 | Conversation search is title-only (no full-text) | High | CG-10 |
| CG-15 | Recent session cards in `BereanHomeView` navigate to new blank chat, not existing session | Medium | CG-15 |

### Intelligence Wiring Gaps (not addressed in this PR)

| ID | Gap | File(s) | Audit Source |
|---|---|---|---|
| IW-1 | `BereanContextMemoryService.startListening()` never called; `entries: []` hardcoded in `BereanMemoryChip` — sheet always shows empty state | `BereanChatView.swift` L1077, `BereanChatViewModel.swift` init | D-1a |
| IW-2 | `continuationSuggestion()` never called; hero resume cards are hardcoded placeholder data | `BereanChatView.swift` L898–917 | D-1b |
| IW-3 | `BereanThinkingStrip` only ever driven to `.drafting` — `.retrieving`, `.verifying`, `.memoryRead`, etc. never wired from SSE pipeline | `BereanChatView.swift` L1323–1327 | D-2a (binding is now ready; drive sites still missing) |
| IW-4 | `BereanAnswerEngine` disconnected from `BereanChatViewModel.send()` — citation pipeline unused | `BereanChatViewModel.swift` | D-citation |
| IW-5 | `BereanLiveActivityManager` not wired to `BereanChatViewModel.send()` / streaming — main chat never updates Dynamic Island | `BereanChatViewModel.swift` | D-4a |
| IW-6 | Memory scope not shown in `BereanMemoryChip` label — chip always reads "Memory" regardless of scope | `BereanMemoryChip.swift` L138 | D-3b |
| IW-7 | BiblicalAlignmentService silent rewrites produce no user-visible "edited" badge | `BereanChatView.swift` L498–520 | D-3a |
| IW-8 | Active post context chip missing — when `vm.activePostContext != nil` no chip is shown above composer | `BereanChatView.swift` | D-2c |

### Design System Gaps (not addressed in this PR — P1/P2 backlog)

| ID | Gap | File(s) | Audit Source |
|---|---|---|---|
| DS-1 | `BereanThinkingStrip` still has private `Color._bereanPurple` / `Color._bereanBlue` constants (the file comment acknowledges this; they match the values in `ChurchNotesDesignSystem.swift` but are not using the global extension) | `BereanThinkingStrip.swift` L23–26 | DS-finding #2 |
| DS-2 | `BereanMemoryChip` still has private `Color._memoryPurple` constant | `BereanMemoryChip.swift` L23 | DS-finding #3 |
| DS-3 | `BereanChatView` has 10+ hardcoded RGB colors in workspace cards, paywall banner, mode-fallback banner, section cards | `BereanChatView.swift` L924, L2844, L2932, L3110, L3164, L3352 | DS-findings #12–19 |
| DS-4 | `BereanComposerTray` two tap targets below 44pt (`capabilitiesToggleButton` 44×36pt, `modePickerToggleButton` 36×36pt) | `BereanComposerTray.swift` L496, L531 | DS-findings #21, #22 |
| DS-5 | `BereanChatView` five non-spring animations (header compression, toast, LazyVStack, hero hide, auto-scroll) | `BereanChatView.swift` L1275, L1481, L1696, L1729, L1746 | DS-findings #7–11 |

### Accessibility Gaps (not addressed in this PR — follow-on sprint)

| ID | Gap | Audit Source |
|---|---|---|
| AC-1 | 10+ `BereanChatView` elements missing `accessibilityLabel` / `accessibilityHint`: hero prompt chips (A-01), mode chips (A-02), quick action pills (A-03), suggestion pills (A-04), follow-up action pills (A-05), `headerModeCapsule` (A-08, **ship-blocker**), context memory rail chips (A-09), intelligence follow-up chips (A-10), "Correct the AI" button (A-16) | 03-a11y-perf-audit |
| AC-2 | `bereanErrorBanner` and `modeFallbackBanner` dismiss buttons at 28×28pt (A-12, A-13) — both below 44pt minimum | 03-a11y-perf-audit |
| AC-3 | `structuredMessageView` missing `.accessibilityElement(children: .combine)` (A-14) | 03-a11y-perf-audit |

### Performance Gaps (not addressed in this PR)

| ID | Gap | Audit Source |
|---|---|---|
| PERF-1 | Per-keystroke `classifyInput` call in ViewModel `didSet` — needs 300ms debounce | P-01 |
| PERF-2 | Per-scroll-tick `onPreferenceChange` updating 3 state properties + animations — needs throttle | P-03 |
| PERF-3 | `.animation(…, value: vm.isThinking)` on outer `LazyVStack` — move to `processingIndicator` only | P-04 |
| PERF-4 | `BereanScriptureReferenceExtractor.references()` called per-render per-message — needs memoization | P-05 |

---

## Intelligence Visibility Status

_Status after this PR — based on Agent D's audit matrix._

| Capability | Pre-PR Score (0–5) | Post-PR Score | Change | Notes |
|---|---|---|---|---|
| 5 Primary Modes (mode picker, header, tray) | 4 | 4 | — | No change. `discernment` enum gap (CR-1) still present. |
| SSE Token Streaming | 4 | 4.5 | +0.5 | `BereanThinkingStrip` now accepts `@Binding`; all 9 action states can now be driven. Drive sites (pipeline wiring) still TODO. |
| Firestore Conversation Persistence | 3 | 3 | — | No change. |
| Pinecone Vector Retrieval | 0 | 0 | — | Still invisible; backend wiring not in this PR scope. |
| BereanContextMemoryService Long-Term Memory | 3 | 3 | — | Chip UX unchanged; `entries: []` still hardcoded. |
| BereanRAGService Source Attribution | 2 | 2 | — | No change. |
| BereanAnswerEngine Citation Pipeline | 2 | 2 | — | No change; citation reference text contrast fixed but pipeline still disconnected. |
| Citation Verifier Visible Outcome | 1 | 1.5 | +0.5 | `BereanCitationTile` now shows reference text at WCAG AA contrast; user can read citations clearly. |
| Memory Scope Selector | 1 | 1 | — | No change; scope still not shown in chip. |
| BiblicalAlignmentService Silent Rewrites | 1 | 1 | — | No change. |
| RTDB Post Context | 2 | 2 | — | No change. |
| Discernment Prompt Pre-send | 3 | 3 | — | No change. |
| Dynamic Island Live Activity | 3 | 3 | — | No change; main chat send() still not wired. |
| Study Mode Reasoning Visualization | 4 | 4 | — | No change. |
| Grok Helper / Provenance Chips | 3 | 3 | — | No change. |
| Voice Input | 4 | 4 | — | No change. |
| Voice Output (TTS read-aloud) | 0 | 0 | — | `BereanMessageTray` Audio button still calls empty `onAudio: {}`; VoiceOver can now reach it via `.accessibilityActions` but the action itself is a no-op. |
| Message Tray Accessibility | 0 | 5 | +5 | Ship-blocker A-15 closed. All 5 tray actions now reachable via VoiceOver `.accessibilityActions`. |

---

## Competitive Position Update

_Berean vs Claude iOS vs ChatGPT iOS — after Phase 2 fixes._

| Dimension | Berean (post-PR) | Claude iOS | ChatGPT iOS | Rating |
|---|---|---|---|---|
| Personality / mode switching (13 modes, mid-chat) | Full 13-mode drawer + 5-mode inline tray | Not present | GPTs only, no mid-chat switch | **STRONGER** |
| Scripture citation chips + translation comparison | Present; reference text now WCAG AA-compliant | Not present | Not present | **STRONGER** |
| Study Mode 9-node reasoning visualization | Present (node states simulated, not event-driven) | Not present | Not present | **STRONGER** |
| Spiritual discernment pre-send intercept | Present | Not present | Not present | **STRONGER** |
| Church Notes save from any message | Present | Not present | Not present | **STRONGER** |
| Correct the AI (biblical lens) | Present inline | Not present | Not present | **STRONGER** |
| Cross-session memory scope control (4 scopes) | Present (scope not shown in chip — IW-6) | Fixed memory | Fixed memory | **STRONGER** |
| Ghost draft restore | Present | Not present | Not present | **STRONGER** |
| Dynamic Island Live Activity | Present (post-card path only; main chat not wired) | Not present | Not present | **STRONGER** |
| Crisis safety short-circuit (988 Lifeline) | Present | Safety banner only | Safety banner only | **STRONGER** |
| Ambient aura + wallpaper | Present | Not present | Not present | **STRONGER** |
| CarPlay / Handoff | Present | Handoff only | Handoff only | **STRONGER** |
| Message tray VoiceOver accessibility | **Fixed this PR** — all actions now reachable | N/A | N/A | **RESOLVED** |
| Inline markdown rendering | Plain text (structured view only) | Full markdown | Full markdown | **WEAKER** |
| User message editing | Not present | Present | Present | **WEAKER** |
| Regenerate button visibility | Context menu only (3 taps deep) | Persistent button | Persistent N/M arrows | **WEAKER** |
| Voice output (TTS read-aloud) | Stubbed no-op (`onAudio: {}`) | Not present | Present | **WEAKER** |
| File/photo attachments | Gated behind "coming soon" alert | Full support | Full support | **WEAKER** |
| Per-conversation delete | Clear All only (no swipe-delete) | Swipe delete | Swipe delete + archive | **WEAKER** |
| Conversation list last-message preview | Not present | Present | Present | **WEAKER** |
| Keyboard dismiss on scroll | Not present | Present | Present | **WEAKER** |
| Alternative response selection | Not present | Not present | N/M arrows | **WEAKER** |
| Streaming token display | 80ms debounced — smooth | Token-by-token | Token-by-token | **EVEN** |
| Stop generation | Present | Present | Present | **EVEN** |
| Memory browser | Present (sheet empty — IW-1) | Settings page | Settings page | **EVEN** |
| Haptic feedback | Present | Present | Present | **EVEN** |

---

## Build Status

| Run | Result | Elapsed | Notes |
|---|---|---|---|
| Run 1 | **FAILED** — "Could not compute dependency graph: Failed to receive dependency graph response" | 0.9s | Xcode / SPM transient indexing error; not a Swift source error |
| Run 2 | **PASSED** — 0 errors, 0 warnings from Berean UI files | 31.3s | Clean build; all 7 new files + BereanChatView.swift binding update compile successfully |

**Final status: BUILD PASSING — 0 errors.**

---

_Report generated by Agent I (Integration) — 2026-05-28. Source reads verified against live file content; build verified against `AMENAPP.xcworkspace` scheme `AMENAPP`._
