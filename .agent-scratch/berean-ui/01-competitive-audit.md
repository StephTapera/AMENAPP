# Berean Competitive UX Audit

**Agent:** A — Read-only research (no code changes)
**Date:** 2026-05-27
**Files read:** BereanChatView.swift, BereanComposerBar.swift, BereanChatsListView.swift,
BereanChatsView.swift, BereanLandingView.swift, BereanDynamicIsland.swift,
BereanModeEngine.swift, BereanDesignSystem.swift, BereanFollowUpView.swift,
BereanStructuredCardView.swift, BereanProvenanceChips.swift, BereanMessageMenuView.swift

---

## Executive Summary

Berean is a spiritually differentiated AI chat client with genuine strengths that neither
Claude iOS nor ChatGPT iOS can match: domain-specific personality modes backed by real
theological lenses, a provenance/trust layer that surfaces how each answer was prepared,
Dynamic Island Live Activity for in-flight streaming, and deep integration with AMEN's social
graph (post-context routing, Church Notes handoff, prayer saving). However, the chat surface
has three structural weaknesses that will register as regressions to users who also use Claude
iOS or ChatGPT: (1) message bubbles render plain text only — no markdown, no code blocks,
no inline verse links — making complex answers feel flat; (2) the conversation list shows
only title and relative date with no model/mode badge, no preview snippet, and no unread
indicator; and (3) the composer's tools sheet is a plain grid rather than the contextual
inline chips that Claude iOS and ChatGPT have trained users to expect immediately after a
response. These gaps are fixable and none require architectural surgery.

---

## Affordance Inventory

| # | Affordance | Berean | Claude iOS | ChatGPT iOS | Gap Severity |
|---|------------|--------|------------|-------------|--------------|
| 1 | **Send button** | Gold-filled circle, arrow-up icon, disabled state, haptic on tap | Black circle, arrow-up, same | Circle with arrow-up, same | EVEN |
| 2 | **Stop streaming** | Square stop button replaces send during streaming; haptic | Same pattern | Same pattern | EVEN |
| 3 | **Typing state** | Composer VM transitions idle → typing → focused tracked | Implicit; no visual state chip | Implicit | MEDIUM — Berean actually has richer state machine but none of it surfaces visually to the user |
| 4 | **Thinking indicator** | 3-dot animated bounce with Berean brand badge avatar | Animated "thinking" word + spinner | Bouncing dots | EVEN |
| 5 | **Thinking step label** | `BereanThinkingStateBanner` cycles named steps (e.g. "Searching scripture…") when Grok helper enabled | Named "thinking" steps in extended thinking mode | "Searching…" / "Running code…" inline chips | MEDIUM — Berean's banner is conditional on feature flag; not always shown |
| 6 | **Streaming auto-scroll** | Debounced 100ms timer + drag-to-pause (DragGesture sets dragging=true) | Same + scroll-to-top FAB | Same | EVEN |
| 7 | **Message bubbles — layout** | User: right-aligned black filled capsule. AI: left-aligned secondary background capsule with brand badge. Spring entrance animation per message | Same layout pattern | Same layout pattern | EVEN |
| 8 | **Message bubbles — content rendering** | Plain `Text(content)` — no markdown, no AttributedString, no syntax highlighting | Full CommonMark markdown rendered: bold, italics, headers, bullet lists, code blocks, inline code | Full markdown + code blocks with syntax highlight + copy-code button | CRITICAL — multi-paragraph answers with headers/lists render as raw markdown text in Berean |
| 9 | **Inline verse rendering** | None — Bible references appear as plain text with no tap-to-expand | N/A | N/A | HIGH — Berean-unique feature that is missing; competitors wouldn't have it but users would expect it from a Bible app |
| 10 | **Long-press message menu** | 10-action grid sheet (Ask, Explain, Apply, Verses, Search, Dig In, Copy, Notes, Pray, Post) — glass card floated on dismiss | Copy, Edit (user), Regenerate, Thumb up/down, Share via system sheet | Copy, Regenerate, Share, Flag | BEREAN STRONGER — 10 domain-specific actions vs 3-4 generic ones |
| 11 | **Context menu (native SwiftUI)** | `.contextMenu` on each message: Copy, Save to Notes, Save to Memory, Start Study Thread, View in Memory, Regenerate, Report response | Same native context menu with fewer items | Same | EVEN (Berean has more items) |
| 12 | **Regenerate** | Available via context menu; removes last assistant + user pair, re-sends | In context menu | In message menu and context menu | MEDIUM — Berean's regenerate is buried in context menu only; ChatGPT surfaces it prominently in the long-press sheet |
| 13 | **Copy message** | In context menu AND long-press sheet (two paths) | Context menu only | Context menu + action sheet | EVEN |
| 14 | **Save / export message** | Save to Church Notes (context menu + long-press), Save to Memory (context menu), Save to Prayer (long-press sheet) | Share via system sheet | Share via system sheet | BEREAN STRONGER — 3 distinct save destinations vs generic share |
| 15 | **Report response** | `ReportUnsafeAIResponseSheet` — Cloud Function backed, destructive button in context menu | Thumbs down + flag in context menu | Thumbs up/down inline + flag | MEDIUM — Berean's report is one level deeper than competitors |
| 16 | **Model / tier indicator** | `modelFallbackNotice` banner auto-clears after 4s when server downgrades tier. No persistent model badge in header | Model pill in nav bar (e.g. "Claude 3.7 Sonnet") — always visible, tappable to switch | GPT-4o/ChatGPT-4 badge in nav bar — always visible | HIGH — no persistent model badge in Berean; users can't see what tier answered them between turns |
| 17 | **Mode / personality indicator** | Compressed mode capsule appears in header center on scroll; static chip below composer always visible; mode shown in BereanModePickerSheet | N/A — single model, no personality modes | GPTs picker in composer | BEREAN STRONGER — richer mode system than either competitor |
| 18 | **Mode switching** | Composer toolbar button → BereanModePickerSheet (Scripture, Prayer, Deep Study); header menu → BereanModeDrawer; horizontal chip row in hero state | Not applicable | GPTs picker in compose bar or left drawer | EVEN in mechanics; Berean's modes are domain-specific and stronger in concept |
| 19 | **Keystroke-inferred mode suggestion** | Composer tracks keystroke rhythm and backspace density to infer mode (`inferredMode`); shows "Suggested" badge on relevant mode in picker | None | None | BEREAN UNIQUE — no competitor has this |
| 20 | **Theological lens** | 3 lenses: Wisdom (Paul), Prayer (David), Discernment (Solomon) — system prompt modifiers | None | None | BEREAN UNIQUE |
| 21 | **Tone checker** | After 12s + 40 chars, scanner checks for self-condemnation phrases; toolbar button glows gold; opens ToneCheckerSheet | None | None | BEREAN UNIQUE |
| 22 | **Scripture paste detection** | Detects Bible references via regex when pasted; auto-switches to scriptureStudy mode; changes placeholder | None | None | BEREAN UNIQUE |
| 23 | **Draft restore (ghost draft)** | BereanDraftStore shows previous unsent draft as dismissible chip above composer; tap to restore | None | Typed text persists in input field (no cross-session restore) | BEREAN STRONGER — cross-session draft chip is a distinct affordance |
| 24 | **Status pill** | `BereanStatusPillType` floating pill above composer (e.g. "Verifying…", "Grounding…") | None visible in UI | "Searching the web…" / "Running code…" chips inline | MEDIUM — concept exists in Berean but appears to show internal processing states rather than user-meaningful progress |
| 25 | **Voice input** | Mic button in composer → BereanVoiceInputSheet (Whisper transcription); user reviews transcript before sending; voice disabled alert if setting off | Hold-to-talk orb, real-time transcription streamed into field | Voice Mode orb with full duplex conversation | HIGH — Berean requires tap-to-open-sheet + review+send; ChatGPT's hold-to-talk is faster for quick queries |
| 26 | **Voice mode (full conversation)** | BereanVoiceOrb.swift + BereanVoiceInputSheet.swift exist; no hold-to-talk or full-duplex mode | Extended audio mode (headphone icon) | Advanced Voice Mode (full duplex, emotion-aware) | HIGH — no real-time duplex voice; Berean only has transcription-then-send flow |
| 27 | **Dynamic Island / Live Activity** | `BereanDynamicIsland.swift` — thinking aura blob + responded card anchored below island; cached result fast path | No Live Activity | No Live Activity | BEREAN UNIQUE AND STRONGER |
| 28 | **Conversation list — layout** | Glass cards: title (1 line), mode badge chip (translation field = mode label), relative date, "Open" pill, bookmark icon. Sorted by lastUpdated. Limit 50. | Section headers by date, title preview (2 lines), model badge, no preview snippet | Title (1 line), no model indicator, preview snippet (1 line) | MEDIUM — Berean missing preview snippet; no last-message preview means users can't skim conversations to find the one they want |
| 29 | **Conversation list — search** | Full-text search over title field only; clear button; empty state | Full text search over conversation content (semantic in some cases) | Exact-match search over title | MEDIUM — Berean title-only search; no preview/content search |
| 30 | **Conversation list — swipe actions** | None — no swipe-to-delete, no swipe-to-pin | Swipe-to-delete | Swipe-to-delete, swipe-to-archive | HIGH — no swipe-to-delete or pin is a significant list management regression |
| 31 | **Conversation list — rename** | No rename affordance visible in list | Long-press → rename | Long-press → rename | HIGH — conversations get auto-titled from first user message but no way to rename |
| 32 | **Conversation list — folder / project grouping** | Folder button in header exists (taps to `// folder action` stub) — **not implemented** | Projects (Claude.ai Pro) | No folders | MEDIUM — visual promise of folders not yet backed by functionality |
| 33 | **New conversation** | Prominent glass card at top of list with + icon; full-screen cover to BereanHomeView | New chat FAB (+) in nav bar | New chat button top-right | EVEN |
| 34 | **Conversation search from landing** | BereanLandingView has no search; BereanChatsListView has search | Search from any screen via nav bar | Search from any screen | MEDIUM — no search accessible from the active chat screen |
| 35 | **Provenance / source chips** | `BereanProvenanceChipRow` per assistant message: Berean-checked, Scripture-grounded, AI-assisted, External context, Needs caution, Sensitive topic — tappable to BereanProvenanceSheet | No per-message provenance chips | No per-message provenance chips | BEREAN UNIQUE AND STRONGER — transparency feature competitors lack entirely |
| 36 | **Citation verifier** | `BereanSourceGroundingService` in backend; surfaces as "Scripture-grounded" provenance chip | No — hallucination not called out explicitly | No | BEREAN STRONGER — though only surfaced as chip color, not inline footnotes |
| 37 | **Follow-up suggestion chips** | `BereanFollowUpView` + `BereanSmartFollowUpChips` — two tiers: static contextual chips above composer + AI-generated `intelligence.followUpSuggestions` after response (auto-send on tap, dismiss X button) | Suggested follow-up chips after some responses (not always) | Suggested follow-ups after some responses | EVEN — Berean's two-tier approach (static + dynamic) is architecturally stronger |
| 38 | **Hero / empty state** | Rich animated hero: AMEN medallion + large "Berean" wordmark + mode-adaptive prompt card + horizontal prompt chips. Mode chips row for quick mode switch. Continuity cards for recent sessions. | Minimalist centered logo + "Start a new chat" | Logo + recent conversation shortcuts | BEREAN STRONGER — hero state has far more information density and onboarding value |
| 39 | **Structured response cards** | `BereanStructuredCard` — typed cards (prayer, decision, meal, debate, factCheck, crisis) with accent stripe, icon badge, save/share footer. Crisis card is a special case with 988 hotline. | No typed card UI — all responses in same bubble | No typed card UI | BEREAN UNIQUE AND STRONGER |
| 40 | **Study mode (reasoning panel)** | `BereanStudyModeSurface` — collapsible panel showing 9 reasoning nodes (scripture, crossRefs, commentary, sermons, articles, originalLanguage, historicalContext, application, notes); scanning → active → complete state machine; tappable to BereanReasoningSummarySheet | Extended thinking (shows "Thinking…" state but no structured node breakdown) | No equivalent | BEREAN STRONGER — more structured than Claude's extended thinking display |
| 41 | **Attachment support** | Add Photo, Add File buttons in tools sheet → `BereanAttachmentPickerSheet`. Attachments embedded in composer context. Currently shows "Attachment upload is not enabled for this build" alert in some paths | Full image + file attachment, PDF preview | Image generation inline, image upload, file upload, code execution | HIGH — attachment flow exists in code but is feature-flagged off ("Attachment upload is not enabled for this build") |
| 42 | **Code rendering** | No code block component found — plain `Text()` rendering only | Syntax-highlighted code blocks with language label + copy button | Same, plus "Run" button for Python | CRITICAL — any response containing code or verse in original language renders as plain monospaced text |
| 43 | **Markdown rendering** | None — `Text(content)` on `BereanMessageBubble.bubbleContent`. No `AttributedString`, no `SwiftUI.Text` markdown via `LocalizedStringKey` | Full markdown via custom renderer | Full markdown | CRITICAL — headers (##), bold (**), lists (-), blockquotes (>) all appear as literal characters |
| 44 | **Conversation title** | Auto-generated from first user message (prefix 60 chars); shown in header center capsule | Auto-generated + editable | Auto-generated + editable | MEDIUM — no in-context rename |
| 45 | **Keyboard avoiding** | Composer fixed to bottom of ZStack with `.padding(.bottom, metrics.composerBottomPadding)` — relies on safe area math rather than SwiftUI's keyboard avoidance | `ignoresSafeArea(.keyboard)` + scroll animation | Same | LOW — metrics-based approach works but is more brittle |
| 46 | **Haptic feedback** | Per-action haptics: send (medium), stop (medium), mode change (light), tool open (light); periodic `sentencePulse` during streaming via BereanHapticCoordinator | Limited haptics on send | Limited haptics on send | BEREAN STRONGER — streaming haptic pulse is unique |
| 47 | **Accessibility** | Comprehensive: `accessibilityLabel`, `accessibilityHint`, `.isSelected` trait on mode chips, `.updatesFrequently` on thinking indicator, reduceMotion + reduceTransparency branches throughout | Good | Good | EVEN |
| 48 | **Memory / context scope** | `BereanMemoryScopeStore` with 4 scopes: off, thisChat, thisProject, allBerean. Cross-session history fetched from Firestore when allBerean selected. Memory chip rail in composer overlay. | Memory tab (saved facts, distinct from chat history) | Memory toggle + "Temporary Chat" mode | EVEN — conceptually comparable; Berean's scope selector is more granular |
| 49 | **Spiritual memory** | `SpiritualMemoryView` — domain-specific memory for biblical insights, linked verses, category. Accessible via context menu "View in Memory" | No spiritual/domain memory | No spiritual/domain memory | BEREAN UNIQUE |
| 50 | **Post-to-social** | Long-press → "Post" action calls `onPostToAMEN` to route message to AMEN feed | No | No | BEREAN UNIQUE |
| 51 | **Handoff / Continuity** | `userActivity` NSUserActivity with `AmenHandoff.BereanChat.activityType` — eligible for Handoff, Siri search, prediction | Full Handoff support | Limited | EVEN |
| 52 | **Wallpaper / theme** | `BereanWallpaperManager` — tappable from header menu, adjusts contrastStyle (foreground color) to maintain legibility | Dark/light mode + accent color | Themes (Plus) | BEREAN STRONGER in chat customization |
| 53 | **Concise mode** | `BereanAISettingsStore.conciseModeEnabled` injects system prompt modifier | No | No explicit toggle | BEREAN UNIQUE |
| 54 | **Crisis escalation** | `crisisEscalationDetected` flag bypasses safety sanitization for 988/Crisis Text Line responses; rendered as `BereanStructuredCard.crisisCard` | Soft refusal | Soft refusal | BEREAN STRONGER — explicit crisis card with hotline numbers preserved |
| 55 | **CarPlay** | `BereanCarPlayRouter.swift` exists — CarPlay integration for voice + chat | None | None | BEREAN UNIQUE |
| 56 | **AI correction** | `CorrectTheAIView` — user can submit correction with theological lens; can trigger rewrite that replaces message in-place | Thumbs down feedback only | Thumbs down feedback only | BEREAN STRONGER |

---

## Critical Gaps (Berean missing entirely)

### C-1: No Markdown Rendering — CRITICAL
Every structured response from Claude (headers, bold, lists, bullet points, blockquotes)
renders as raw markdown symbols in Berean's `Text(content)` bubble. Users coming from
Claude iOS or ChatGPT will immediately perceive Berean as "broken." Fix requires adopting
`LocalizedStringKey` markdown rendering or a third-party parser (Down, swift-markdown-ui)
for assistant bubbles.

### C-2: No Code Block Component — CRITICAL
`BereanMessageBubble.bubbleContent` uses `Text(content)` directly. Any response containing
a code snippet, original-language verse, or structured list formatted as code will appear as
unstyled monospace characters without a copy-code button. A `BereanCodeBlock` component with
a copy button is needed.

### C-3: Swipe-to-Delete / Swipe-to-Pin on Conversation List — HIGH
`BereanChatsListView.conversationRow` uses a plain `Button` with no swipe actions. Users
muscle-memorize swipe-to-delete across all iOS list apps. Without it, deleting an old
conversation requires going through the header menu → "Clear All" (which deletes everything)
— there is no per-conversation delete at all.

### C-4: Conversation Rename — HIGH
Conversations are auto-titled from the first 60 characters of the user's first message.
There is no in-context rename in the list row or in the active chat header. Both Claude iOS
and ChatGPT have long-press-to-rename on conversation rows.

### C-5: Persistent Model / Tier Badge — HIGH
The `modelFallbackNotice` banner only appears for ~4 seconds when a tier downgrade occurs.
Between turns there is no indicator of which model tier (Core vs Deep) answered the last
question. Claude iOS shows the model name in the nav bar on every turn; users who care about
AI transparency will not know what tier they are on.

### C-6: Voice Hold-to-Talk — HIGH
Berean's voice path opens a separate sheet, records, transcribes with Whisper, then requires
the user to tap Send. ChatGPT's hold-to-talk (and its Advanced Voice Mode) bypasses this
friction entirely. For quick scripture lookups while driving or cooking, Berean's voice flow
has two extra taps compared to competitors.

### C-7: Conversation Preview Snippet — MEDIUM
`BereanChatsListView` shows conversation title and date only. The mode badge (currently
showing the mode raw value, not a meaningful snippet) does not substitute for a 1-line
preview of the last message. Users returning to find a conversation must open it to know what
was discussed.

### C-8: Inline Bible Verse Tap-to-Expand — HIGH (domain-specific gap)
When Berean's responses cite verses (e.g., "Proverbs 3:5"), they appear as plain text.
Neither Claude iOS nor ChatGPT has this either, but for a Bible-focused AI this is an
expected affordance: tap a verse reference → show the full text in a popover or sheet. This
gap makes Berean feel less specialized than it is.

### C-9: Folder / Project Grouping for Conversations — MEDIUM
The `BereanChatsListView` header shows a folder icon button with a `// folder action` comment
stub. Claude iOS has Projects (Pro). The visual affordance promises a feature that does not
exist yet.

### C-10: Attachment Upload Gating — HIGH
The composer tools sheet shows "Add Photo" and "Add File" buttons, but the actual picker path
in `BereanChatView` shows an alert: "Attachment upload is not enabled for this build." Users
who tap these buttons will receive a confusing modal telling them to describe the attachment
in text instead. Either the buttons should be hidden behind the same feature flag or the
feature should be enabled.

---

## Berean Unique Strengths

These affordances exist in Berean that neither Claude iOS nor ChatGPT iOS have:

1. **Theological lenses (Wisdom / Prayer / Discernment)** — system-prompt-level response
   modifiers derived from biblical archetypes (Paul / David / Solomon). No competitor has
   domain-specific personality modes backed by structured 5-step response frameworks.

2. **Provenance chips per message** — `BereanProvenanceChipRow` exposes whether a response
   was Berean-checked, Scripture-grounded, AI-assisted by a helper model, uses external
   context, requires caution, or detected a sensitive topic. Tapping opens the full
   `BereanProvenanceSheet` explaining the review pipeline. This is a genuine trust and
   transparency advantage.

3. **Dynamic Island Live Activity** — Berean's `BereanDynamicIsland` puts a thinking aura
   blob and responded snippet in the Dynamic Island, enabling users to see responses without
   returning to the app. No AI chatbot competitor has this.

4. **Typed structured response cards** — `BereanStructuredCard` with prayer, decision, meal,
   debate, factCheck, and crisis types. Each card has an accent stripe, icon badge, and
   save/share footer. The crisis card hardcodes 988 + Crisis Text Line numbers.

5. **Study Mode reasoning panel** — 9-node collapsible panel (scripture, cross-references,
   commentary, original language, application, etc.) with per-node state machine. Richer
   than Claude's "Thinking…" indicator.

6. **Keystroke rhythm inference** — detects slow typing (prayer mode) vs high backspace
   density (deep study) and surfaces mode suggestion in the picker.

7. **Tone checker** — after prolonged typing, scans for self-condemnation or spiritual
   bypassing phrases and offers a rewrite via `ToneCheckerSheet`. Unique pastoral feature.

8. **Scripture paste detection** — regex detects Bible references in pasted text, auto-sets
   scriptureStudy mode, and updates the composer placeholder.

9. **Ghost draft restore chip** — cross-session persisted draft shown as dismissible chip
   above composer.

10. **Spiritual memory** — domain-specific saved insights with verse linkage, distinct from
    generic chat memory.

11. **Post-to-social** — direct routing of an AI response into the AMEN feed from the
    long-press message menu.

12. **AI correction with lens** — user can submit a theological correction specifying which
    lens to apply; Berean can rewrite the message in-place.

13. **Streaming haptic pulse** — periodic haptic during SSE streaming (BereanHapticCoordinator
    `sentencePulse`), creating a tactile rhythm that reinforces "Berean is working."

14. **CarPlay integration** — BereanCarPlayRouter supports scripture lookups and prayer while
    driving.

---

## Recommended Priority Order

### P0 — Critical (block ship)

| # | Fix | Reason |
|---|-----|--------|
| P0-1 | Implement markdown rendering in `BereanMessageBubble` | C-1: Plain text rendering of markdown symbols is a broken-app perception |
| P0-2 | Add `BereanCodeBlock` component for code/verse-language fences | C-2: Code and original-language content is unreadable |
| P0-3 | Remove or feature-flag "Add Photo" / "Add File" buttons when upload disabled | C-10: Showing broken buttons actively harms trust |

### P1 — High (ship-blocking within 2 sprints)

| # | Fix | Reason |
|---|-----|--------|
| P1-1 | Swipe-to-delete on conversation rows | C-3: iOS muscle memory; no per-conversation delete exists |
| P1-2 | Conversation rename | C-4: Both main competitors have this; power users need it |
| P1-3 | Persistent model/tier badge in chat header | C-5: Users need to know what tier is answering |
| P1-4 | Inline Bible verse tap-to-expand | C-8: Highest-ROI domain-specific feature; foundational for a Bible AI |
| P1-5 | Simplify voice path (hold-to-record in composer) | C-6: Two-extra-taps friction on every voice query |

### P2 — Medium (first two post-launch sprints)

| # | Fix | Reason |
|---|-----|--------|
| P2-1 | Add last-message preview snippet to conversation rows | C-7: Standard list UX |
| P2-2 | Implement folder/project grouping (or remove the button stub) | C-9: Visual promise must not be broken |
| P2-3 | Promote Regenerate to long-press message menu (currently context-menu only) | Affordance 12: Surface discoverability |
| P2-4 | Add in-conversation search (find previous message) | Affordance 34 |
| P2-5 | Add timestamp on message long-press or hover | Standard chat UX; both competitors show it |

### P3 — Low polish (backlog)

| # | Fix | Reason |
|---|-----|--------|
| P3-1 | Model-mode badge always visible in header (not just on tier downgrade) | Transparency |
| P3-2 | Swipe-to-pin on conversation rows | Power-user list management |
| P3-3 | Semantic content search across conversation list | Claude iOS has this |
| P3-4 | Keyboard avoiding: migrate to SwiftUI's `ignoresSafeArea(.keyboard)` + scrollable anchor | Low fragility |
| P3-5 | Conversation count cap indicator (currently 50, no UI feedback) | Edge case UX |

---

## Notes on Architecture vs UX Gaps

Several gaps in this audit are UX surface issues sitting on top of already-built backend
capabilities:

- Markdown exists in responses from Claude but is stripped/ignored at render time.
  `AttributedString(markdown:)` or `swift-markdown-ui` can fix this with ~100 lines of code.

- Verse tap-to-expand needs only a regex pass on `BereanMessageBubble.bubbleContent` to
  detect and linkify references — the verse lookup infrastructure (`BereanScriptureEngine`,
  `SelahScripture`) already exists.

- The swipe actions gap is a single `.swipeActions` modifier on the conversation row button.

None of the P0 or P1 gaps require new services or backend changes. They are presentation-
layer additions that can be done without touching Firestore schemas or Cloud Functions.
