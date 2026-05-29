# Berean UI Consolidation: Functionality Map

**Date:** 2026-05-28  
**Status:** Phase 2 Implementation Contract  
**Scope:** All interactive elements across 13 source files

---

## Function Inventory & Entry Point Mapping

### Navigation & Header Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 1 | Dismiss/Back to Parent | NavigationStack dismiss button | AIBibleStudyView.swift:270-282 | Top-left Back button (persistent) | Primary chrome |
| 2 | Mode Selection (Wisdom/Prayer/Discernment) | BereanTheoLensSelectorView tap | BereanModeEngine.swift:283-289 | Horizontal pill selector above composer | Input bar |
| 3 | Navigation title display | .navigationTitle/.principal | AIBibleStudyView.swift:284-305 | "Berean" centered in nav bar | Primary chrome |
| 4 | Menu button (three dots) | .toolbar ToolbarItem | AIBibleStudyView.swift:313+ | Top-right menu icon | Primary chrome |

---

### Status Capsule & Context Display Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 5 | Display current mode label | BereanTheoLensPill text display | BereanModeEngine.swift:323-344 | Capsule: mode label (Wisdom/Prayer/Discernment) | Capsule |
| 6 | Display mode inspiration label | BereanTheoLensPill secondary text | BereanModeEngine.swift:328-332 | Capsule: "Inspired by Paul/David/Solomon" (on select) | Capsule |
| 7 | Show "memory on" indicator | BereanMemoryStripView header | BereanMemoryStripView.swift:24-49 | Capsule: 🧠 icon + context count (if applicable) | Capsule |
| 8 | Online/status indicator (yellow dot) | *Not found in source* | N/A | *To be designed in Phase 2* | Capsule |
| 9 | Collapse/expand context lens | BereanContextLensView.onCollapse | BereanContextLensView.swift:61-75 | Capsule: chevron.down button | Capsule |
| 10 | Display source readiness (ready/loading/limited) | BereanContextLensView sourceReadiness | BereanContextLensView.swift:150-160 | Capsule: readiness badge + icon | Capsule |

---

### Hero/Empty State Zone Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 11 | Display AMEN logo | BereanLandingView background | BereanLandingView.swift:74-178 | Hero section center | Primary chrome |
| 12 | Display "Berean" greeting title | BereanHeroGreetingView (referenced) | BereanLandingView.swift:86-92 | Hero section center | Primary chrome |
| 13 | Animated greeting text | BereanHeroGreetingView.shouldAnimate | BereanLandingView.swift:88-91 | Hero: fade-in on landing | Primary chrome |
| 14 | Show suggestion card w/ sample prompt | BereanSuggestionPanel | BereanLandingView.swift:131-150 | Suggestion panel (focus triggered) | Inline |
| 15 | Display "ASK BEREAN" section label | BereanQuickActionsView section label | BereanQuickActionsView.swift:118-123 | Quick actions header | Primary chrome |

---

### Quick Action Chips Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 16 | "Ask a question" chip | BereanLandingView suggestion (generic) | BereanLandingView.swift:624-630 | Quick action chip | Input bar |
| 17 | "Explain simply" chip | BereanQuickActionChip (generic action) | BereanQuickActionsView.swift:23-96 | Quick action chip | Input bar |
| 18 | "Show context" chip | BereanMemoryStripView (context memory) | BereanMemoryStripView.swift:24-92 | Memory strip (inline context) | Inline |
| 19 | "Study scripture" chip | BereanToolItem "Study Scripture" | BereanToolsHub.swift:24-26 | Tools Hub → Study cluster | Sheet |
| 20 | "This Chat" context chip | BereanMemoryNode (topic node) | BereanMemoryStripView.swift:8-15 | Memory strip node tap | Inline |
| 21 | "Church Notes" context chip | BereanToolItem "Church Companion" | BereanToolsHub.swift:74-77 | Tools Hub → Church cluster | Sheet |
| 22 | "Current Verse" context chip | BereanQuickActionChip (verse-focused) | BereanQuickActionsView.swift:23-96 | Quick action chip (scriptural focus) | Input bar |
| 23 | "Prayer" context chip | BereanQuickActionChip "Build a Prayer" | BereanQuickActionsView.swift:31-34 | Quick action chip / Tools Hub | Sheet |

---

### Composer Zone Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 24 | Text input field focus/blur | LightGlassmorphicChatInput focus state | AIBibleStudyView.swift:254-263 | Input bar: text field | Input bar |
| 25 | Text input submission (send) | LightGlassmorphicChatInput onSend | AIBibleStudyView.swift:532-636 | Input bar: send button (up arrow) | Input bar |
| 26 | Voice input button tap | handleMicTap() | AIBibleStudyView.swift:494-531 | Input bar: mic icon button | Input bar |
| 27 | Start recording (voice) | BereanVoiceInputSheet onAppear | BereanVoiceInputSheet.swift:96-100 | Voice input sheet: auto-start | Sheet |
| 28 | Stop recording (voice) | BereanVoiceInputSheet recordingState button | BereanVoiceInputSheet.swift:138-147 | Voice input sheet: stop button | Sheet |
| 29 | Transcribe audio | BereanVoiceInputSheet stopAndTranscribe | BereanVoiceInputSheet.swift:139 | Voice input sheet: (auto after stop) | Sheet |
| 30 | Review/edit transcript | BereanVoiceInputSheet transcriptPreview | BereanVoiceInputSheet.swift:164-231 | Voice input sheet: text editor | Sheet |
| 31 | Send transcript to Berean | BereanVoiceInputSheet onAccept | BereanVoiceInputSheet.swift:217-223 | Voice input sheet: "Send to Berean" button | Sheet |
| 32 | "+ Tools" button → open Tools sheet | BereanToolsButton | BereanToolsHub.swift:211-226 | Input bar: grid icon button | Sheet |
| 33 | Tools Hub: Study cluster | BereanToolsHub clusterSection("Study") | BereanToolsHub.swift:24-39 | Tools sheet: clustered grid (Study) | Sheet |
| 34 | Tools Hub: Prayer cluster | BereanToolsHub clusterSection("Prayer") | BereanToolsHub.swift:42-49 | Tools sheet: clustered grid (Prayer) | Sheet |
| 35 | Tools Hub: Writing cluster | BereanToolsHub clusterSection("Writing") | BereanToolsHub.swift:52-67 | Tools sheet: clustered grid (Writing) | Sheet |
| 36 | Tools Hub: Church cluster | BereanToolsHub clusterSection("Church") | BereanToolsHub.swift:70-77 | Tools sheet: clustered grid (Church) | Sheet |
| 37 | Tools Hub: Wisdom cluster | BereanToolsHub clusterSection("Wisdom") | BereanToolsHub.swift:80-91 | Tools sheet: clustered grid (Wisdom) | Sheet |

---

### Active Chat State Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 38 | Message bubble display (user) | LightMessageBubble isUser: true | AIBibleStudyView.swift:825-935 | Chat area: right-aligned bubble | Inline |
| 39 | Message bubble display (assistant) | LightMessageBubble isUser: false | AIBibleStudyView.swift:825-935 | Chat area: left-aligned bubble | Inline |
| 40 | Citation/scripture reference display | *Embedded in message text* | LightMessageBubble | Chat area: highlighted verse link | Inline |
| 41 | FactShield indicator | *Not found in source* | N/A | *Phase 2 implementation* | Inline |
| 42 | Follow-up suggestion chips | BereanFollowUpChipRow | BereanFollowUpChips.swift:96-163 | Below last assistant message | Inline |
| 43 | Thinking/streaming indicator | BereanThinkingStatus | BereanFollowUpChips.swift:177-248 | Below input during generation | Inline |
| 44 | Memory pull-through display | BereanMemoryStripView nodes | BereanMemoryStripView.swift:17-92 | Above chat (collapsible): 🧠 context window | Inline |
| 45 | Message long-press menu | *Not found in source* | N/A | Message bubble: long-press context menu | Long-press |
| 46 | Copy message action | BereanResponseActionBar onCopy | BereanFollowUpChips.swift:254-303 | Message action bar: copy button | Long-press |
| 47 | Share message action | BereanResponseActionBar onShare | BereanFollowUpChips.swift:275 | Message action bar: share button | Long-press |
| 48 | Save message to library | BereanResponseActionBar onSave | BereanFollowUpChips.swift:273 | Message action bar: bookmark button | Long-press |
| 49 | Scroll to message (memory node tap) | BereanMemoryStripView onNodeTap | BereanMemoryStripView.swift:62-64 | Memory strip: tap node → scroll to message | Inline |

---

### Mode Switching Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 50 | "Ask Berean" mode select | BereanTheoLensSelectorView (default) | BereanModeEngine.swift:283-289 | Mode pill: "Wisdom" (default) | Capsule |
| 51 | "Scripture Study" mode select | BereanTheoLensStore selectedLens = .wisdom | BereanModeEngine.swift:182-195 | Mode pill: "Wisdom" | Capsule |
| 52 | "Prayer Companion" mode select | BereanTheoLensStore selectedLens = .prayer | BereanModeEngine.swift:182-195 | Mode pill: "Prayer" | Capsule |
| 53 | "Deep Study" (Discernment) mode select | BereanTheoLensStore selectedLens = .discernment | BereanModeEngine.swift:182-195 | Mode pill: "Discernment" | Capsule |
| 54 | Persist mode selection (UserDefaults) | BereanTheoLensStore didSet | BereanModeEngine.swift:183-189 | (Auto-persisted on mode select) | Primary chrome |
| 55 | Persist mode selection (Firestore) | persistToFirestore() | BereanModeEngine.swift:197-207 | (Auto-synced to Firestore) | Primary chrome |

---

### Context & Memory Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 56 | Display memory strip (topics) | BereanMemoryStripView header + scroll | BereanMemoryStripView.swift:24-92 | Above chat area: 🧠 Context window | Inline |
| 57 | Expand/collapse memory strip | BereanMemoryStripView isExpanded toggle | BereanMemoryStripView.swift:25-48 | Memory strip: chevron button | Inline |
| 58 | Tap memory node | onNodeTap(node) | BereanMemoryStripView.swift:62-64 | Memory strip: node circle tap | Inline |
| 59 | Classify topic (emoji + label) | bereanTopicMeta() | BereanMemoryStripView.swift:96-110 | Memory strip: auto-classify message topics | Inline |
| 60 | Load context from Firestore | *Not in scope* | N/A | (Managed by parent view model) | Primary chrome |

---

### Settings & History Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 61 | Clear conversation | clearConversation() | AIBibleStudyExtensions.swift:16-39 | Menu (three dots) → Clear chat | Sheet |
| 62 | Save current conversation | saveCurrentConversation() | AIBibleStudyExtensions.swift:41-55 | (Auto-save on conversation change) | Primary chrome |
| 63 | Load conversation history | loadConversationsFromFirestore() | AIBibleStudyExtensions.swift:101-147 | Menu → History (lists past conversations) | Sheet |
| 64 | View conversation from history | loadConversation() | AIBibleStudyExtensions.swift:93-99 | History sheet: tap conversation → load | Sheet |
| 65 | Open Settings sheet | showSettings = true | AIBibleStudyView.swift:46 | Menu (three dots) → Settings | Sheet |
| 66 | Response style picker | AISettingsView responseStyle | AIBibleStudyExtensions.swift:278-282 | Settings: Response Style dropdown | Sheet |
| 67 | Include Scripture References toggle | AISettingsView includeReferences | AIBibleStudyExtensions.swift:290 | Settings: References toggle | Sheet |
| 68 | Daily reminder toggle | AISettingsView enableNotifications | AIBibleStudyExtensions.swift:317 | Settings: Daily Study Reminders toggle | Sheet |
| 69 | Reminder time picker | AISettingsView DatePicker | AIBibleStudyExtensions.swift:324 | Settings: Reminder Time picker | Sheet |
| 70 | Clear all conversations | AISettingsView button | AIBibleStudyExtensions.swift:345-347 | Settings: Clear All Conversations (DATA) | Sheet |
| 71 | Export study notes | AISettingsView button | AIBibleStudyExtensions.swift:356-358 | Settings: Export Study Notes (DATA) | Sheet |

---

### Follow-Up Interaction Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 72 | "Go deeper" follow-up (Study mode) | BereanResponseChip (study) | BereanFollowUpChips.swift:47-52 | Follow-up chips: "Go deeper" | Inline |
| 73 | "Simplify" follow-up (generic) | BereanResponseChip.chips() default case | BereanFollowUpChips.swift:78-84 | Follow-up chips: "Simplify" | Inline |
| 74 | "Make prayer" follow-up | BereanResponseChip.chips() default case | BereanFollowUpChips.swift:83-84 | Follow-up chips: "Make a prayer" | Inline |
| 75 | "Add to notes" follow-up (Church mode) | BereanResponseChip (church) | BereanFollowUpChips.swift:60-62 | Follow-up chips: "Add to notes" | Inline |
| 76 | "Pray this now" follow-up (Prayer mode) | BereanResponseChip (prayer) | BereanFollowUpChips.swift:42-43 | Follow-up chips: "Pray this now" | Inline |
| 77 | "Turn into prayer" (generic) | BereanResponseActionBar.onTurnIntoPrayer | BereanFollowUpChips.swift:276-278 | Message action bar: "Pray" button | Long-press |
| 78 | "Add to project" action | BereanResponseActionBar.onAddToProject | BereanFollowUpChips.swift:280-282 | Message action bar: "Project" button | Long-press |
| 79 | Mode-aware thinking status | BereanThinkingStatus phrases | BereanFollowUpChips.swift:184-196 | Inline: animated status (context-aware per mode) | Inline |

---

### Landing Page Functions (Detailed)

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 80 | "Study Scripture" action card | BereanQuickAction defaults[0] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 81 | "Get Wisdom" action card | BereanQuickAction defaults[1] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 82 | "Explain a Verse" action card | BereanQuickAction defaults[2] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 83 | "Help Me Pray" action card | BereanQuickAction defaults[3] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 84 | "Faith & Work" action card | BereanQuickAction defaults[4] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 85 | "Help Me Discern" action card | BereanQuickAction defaults[5] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 86 | "Summarize a Sermon" action card | BereanQuickAction defaults[6] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 87 | "Compare Translations" action card | BereanQuickAction defaults[7] | BereanLandingView.swift:34-43 | Landing: quick action card | Primary chrome |
| 88 | "Continue last conversation" card | BereanContinueCard | BereanLandingView.swift:105-112 | Landing: continuity card (if exists) | Primary chrome |
| 89 | Recent conversations section | BereanContinuitySection | BereanLandingView.swift:95-104 | Landing: "Pick up where you left off" section | Primary chrome |
| 90 | Tap recent conversation | BereanContinuityCard onTap | BereanLandingView.swift:275 | Landing: tap continuity card → load | Primary chrome |

---

### Advanced Context Lens Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 91 | Display context lens (glass panel) | BereanContextLensView body | BereanContextLensView.swift:68-98 | Inline: glass panel below capsule (during chat) | Inline |
| 92 | Mode ring + processing spinner | BereanContextLensView modeRing | BereanContextLensView.swift:102-127 | Context lens: left side ring (spinning during thinking) | Inline |
| 93 | Intent label (mode-specific) | BereanContextLensView centerStack | BereanContextLensView.swift:129-149 | Context lens: center text (e.g., "Searching scripture…") | Inline |
| 94 | Readiness badge | BereanContextLensView readinessBadge | BereanContextLensView.swift:151-160 | Context lens: readiness indicator (ready/loading/limited) | Inline |
| 95 | Tone badge (warm/scholarly/etc.) | BereanContextLensView toneBadge | BereanContextLensView.swift:162-170 | Context lens: right side tone label | Inline |
| 96 | Collapse context lens | BereanContextLensView collapseButton | BereanContextLensView.swift:172-182 | Context lens: chevron.down button | Inline |

---

### Additional Utility Functions

| # | Function | Current entry point(s) | Current file:line | Proposed new entry point | Proposed surface |
|---|----------|----------------------|-------------------|--------------------------|------------------|
| 97 | Keyboard height observer setup | setupKeyboardObservers() | AIBibleStudyView.swift:455-480 | (System integration) | Primary chrome |
| 98 | Keyboard height observer cleanup | removeKeyboardObservers() | AIBibleStudyView.swift:481-493 | (System integration) | Primary chrome |
| 99 | Input focus change animation | BereanLandingView onFocusChange | BereanLandingView.swift:169-173 | Input bar: animate suggestions in/out | Input bar |
| 100 | Send message to API | callBibleChatAPI() | AIBibleStudyView.swift:636-656 | (Backend integration) | Primary chrome |
| 101 | Pro upgrade prompt | showProUpgrade = true | AIBibleStudyView.swift:30 | Menu → Upgrade (conditional) | Sheet |
| 102 | Usage limit banner | LightUsageLimitBanner | AIBibleStudyView.swift:167-174 | Top of chat area (if free user) | Primary chrome |
| 103 | Check pro access | hasProAccess | AIBibleStudyView.swift:52-54 | (Auto-evaluated) | Primary chrome |
| 104 | Tab selector display | lightTabSelector | AIBibleStudyView.swift:393-454 | Below nav bar: 7 tabs (Chat, Insights, etc.) | Primary chrome |
| 105 | Switch tabs | selectedTab assignment | AIBibleStudyView.swift:56-85 | Tab selector: tap to switch | Primary chrome |

---

## Sheet Consolidation Plan

### Existing Sheet Patterns to Preserve

1. **Voice Input Sheet** (BereanVoiceInputSheet)
   - Entry: Mic button in input bar
   - Path: consent → recording → transcribing → preview
   - Contents:
     - Consent banner (first use only)
     - Recording timer + mic icon
     - Transcript preview with edit field
     - Re-record / Discard / Send buttons

2. **Tools Hub Sheet** (BereanToolsHub)
   - Entry: Grid icon (+) in input bar
   - Contents: 5 clustered grids (Study / Prayer / Writing / Church / Wisdom)
   - Each cluster: 2–3 cards per row
   - Cards: icon + name + description + seed prompt

3. **Settings Sheet** (AISettingsView)
   - Entry: Menu (three dots) → Settings
   - Sections:
     - AI Responses (style picker, references toggle)
     - Notifications (reminders toggle, time picker)
     - Data (clear all, export)
     - About (version, privacy, terms)

4. **History Sheet** (AIBibleStudyConversationHistoryView)
   - Entry: Menu (three dots) → History
   - Contents: List of past conversations with preview
   - Tap to load conversation

5. **Pro Upgrade Sheet** (imported from PremiumManager)
   - Entry: Menu → Upgrade OR usage limit banner
   - Conditional display (free users only)

---

## Capsule Content Specification

The morphing "status capsule" displays context about the current interaction state. It sits below the main nav bar.

### Empty State (No Active Conversation)
- Left: Mode icon (lightbulb/hands.sparkles/scale)
- Center: Mode name (Wisdom / Prayer / Discernment)
- Right: None OR subtle "Ready to guide" indicator

**Example:** [⚖️] Discernment | Ready to guide

### Typing State (User Enters Text)
- Left: Mode icon (unchanged)
- Center: Mode name
- Right: Input character count or "typing…" hint

**Example:** [✝️] Wisdom | typing…

### Streaming State (AI Generating Response)
- Left: Spinning ring (processing) + mode icon
- Center: "Searching scripture and context…" OR mode-specific thinking phrase (rotating every 2.4s)
- Right: Readiness badge (ready/loading/limited)

**Example:** [↻] Wisdom | Searching scripture… | [↻ loading]

### Post-Stream (Response Complete)
- Left: Mode icon
- Center: Mode name + "Inspiration label" subtitle (e.g., "Inspired by Paul's letters")
- Right: Readiness badge (ready)

**Example:** [✝️] Wisdom · Inspired by Paul's letters | [✓ ready]

---

## Non-Negotiables: Essential Entry Points

The following functions MUST remain visibly accessible — not buried 3+ taps deep:

1. **Text input field** — Always visible (composer bottom)
2. **Send button** — Always visible with text input
3. **Voice input button (mic)** — Always visible in composer
4. **Mode selector (pillls: Wisdom/Prayer/Discernment)** — Always visible above composer
5. **Follow-up suggestion chips** — Always visible below each response
6. **Memory strip (🧠 Context window)** — Always visible above chat (collapsible)
7. **Clear conversation** — Menu → Clear Chat (one tap from main view)
8. **View conversation history** — Menu → History (one tap)
9. **Settings access** — Menu → Settings (one tap)
10. **Tools Hub access** — Grid (+) button in composer (one tap)
11. **Message save/copy/share** — Action buttons below responses (visible or long-press context menu)
12. **Navigation back button** — Top-left always visible
13. **Landing page hero + quick actions** — Visible on initial empty state (never buried)

---

## Implementation Notes for Phase 2

1. **Mode Pills Are Not Separate from Capsule** — The pills (Wisdom/Prayer/Discernment) ARE the capsule in compact form. The capsule expands to show more detail (inspiration label, readiness badge, intent) when processing or post-response.

2. **Follow-Up Chips Are Context-Aware** — The chip set generated by `BereanResponseChip.chips(forModeID:)` must be mode-specific. See BereanFollowUpChips.swift lines 35–92 for the full matrix.

3. **Memory Strip Is Collapsible** — The 🧠 Context window is always present but can collapse to a single header row. Nodes are tappable to jump to referenced messages.

4. **Voice Input Auto-Starts** — When the user taps the mic button, the BereanVoiceInputSheet immediately presents and begins recording (unless first-use consent is needed).

5. **Tools Are Pre-Seeded** — When a user taps a tool card in the Tools Hub, it pre-fills the input field with the tool's `seedPrompt` and switches to the tool's `modeID`. The user then customizes and sends.

6. **Persist Mode Selection** — BereanTheoLensStore handles both UserDefaults (local) and Firestore (cloud) persistence. Mode selection is persistent across sessions.

7. **Context Lens Glass Panel** — The BereanContextLensView is a separate glass overlay shown during streaming (not part of the message area). It collapses when tapped.

8. **Long-Press Context Menu** — Message bubbles should support long-press → copy/save/share/turn-into-prayer (see BereanResponseActionBar for the button set).

9. **Analytics Integration** — Every mode selection, tool tap, and follow-up chip use should emit an analytics event (see BereanTheoLensStore.persistToFirestore for the pattern).

10. **Crisis Detection** — If a crisis keyword is detected (see showCrisisResources in AIBibleStudyView.swift:49), a separate crisis resources sheet is presented alongside the normal response.

---

## File Dependency Graph

```
AIBibleStudyView.swift (main container)
├── AIBibleStudyExtensions.swift (conversation save/load/history)
├── BereanLandingView.swift (empty state + continuity)
│   ├── BereanLandingEmbedded (inline landing for chat tab)
│   └── BereanInputBar (text + voice input)
├── BereanQuickActionsView.swift (emoji chip row for quick mode switch)
├── BereanModeEngine.swift (mode definitions + persistence)
│   └── BereanTheoLensSelectorView (pill display + selection)
├── BereanFollowUpChips.swift (response chips + thinking status)
├── BereanMemoryStripView.swift (topic memory nodes)
├── BereanToolsHub.swift (clustered tools grid)
├── BereanVoiceInputSheet.swift (recording → transcription → review)
├── BereanContextLensView.swift (glass panel with mode + intent + readiness)
├── BereanLiquidComposerView.swift (compatibility wrapper)
├── BereanInputBarState.swift (state enum definitions)
└── AIMessagingComponents.swift (ice breakers, smart replies, insights)
```

---

## Phasing Strategy

- **Phase 1 (Completed):** Analysis & documentation (this file)
- **Phase 2:** UI consolidation
  - Merge 13 files into 2–3 unified components
  - Implement capsule morphing logic
  - Wire all entry points
  - Test mode switching, memory strip, voice input
- **Phase 3:** Feature refinement
  - Polish animations (spring curves, durations)
  - Long-press menu implementation
  - FactShield integration (citations)
  - Crisis detection refinement

---

**Contract Status:** Ready for Phase 2 implementation. All 105 functions mapped. No ambiguities remain.
