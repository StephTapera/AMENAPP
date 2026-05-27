# Berean Intelligence Surface Audit

**Agent:** D — Intelligence Surface Audit
**Date:** 2026-05-27
**Files read:** BereanChatView.swift, BereanComposerBar.swift, BereanModeEngine.swift, BereanIntelligenceCoordinator.swift, BereanMemoryService.swift, BereanContextMemoryService.swift, BereanSourceGroundingService.swift, BereanMemoryStripView.swift, BereanFollowUpChips.swift, BereanDynamicIsland.swift, BereanGrokCoordinator.swift (AMENAPP/AMENAPP/), BereanGrokModels.swift, BereanIslandViewModel+LiveActivity.swift, BereanActionEngine.swift, BereanSmartPillSystem.swift, BereanConversationSafetyService.swift

---

## Executive Summary

**Intelligence Visibility Score: 4 / 10**

Berean is a deeply capable AI system concealed behind a minimal, clean interface. The gap between what Berean *does* and what the user *sees it doing* is severe. Behind every response, Berean: classifies the input in real time, checks safety, builds a cross-session memory graph, runs biblical alignment verification, injects theological lenses, checks provenance, generates follow-up suggestions, and optionally runs a multi-node study-mode reasoning pipeline — none of which the user can directly observe in the default chat flow.

The few surfaces that do exist (ThinkingStatus cycling phrases, modeFallbackBanner, BereanMemoryStripView, BereanSmartPillsView) are either feature-flag gated, contextually narrow, or only partially deployed. The most powerful capabilities — memory recall, soaking/keystroke inference, tone nudge, multi-session context injection, biblical alignment post-processing, and safety classification — are entirely silent.

A user interacting with Berean cannot tell: what sources backed the answer, whether their memory was used, what theological lens shaped the response, whether the answer was silently rewritten by alignment checks, or whether a safety classifier ran on what they typed.

---

## Capability Visibility Map

| Capability | What it does | Currently visible? | How | Gap |
|---|---|---|---|---|
| **Personality Modes** (askBerean, scriptureStudy, prayerCompanion, deepStudy, scholar) | Fundamentally reshapes response format, tone, placeholder text, and quick-start chips | Partially | `selectedComposerModeChip` (capsule, icon + label above composer); mode picker sheet via toolbar button or swipe; header mode capsule when scrolled | Mode is labeled but its downstream effect on response structure is invisible. User sees "Prayer" label, not "this changes the 5-step response format to emotional acknowledgment → scripture comfort → honest reflection → prayer → gentle next step." |
| **Theological Lenses** (Wisdom, Prayer, Discernment) | Injects a full structured system-prompt fragment that reshapes tone profile, 5-step response structure, and smart pill preferences | Yes — `BereanTheoLensSelectorView` renders pill strip above composer | Three pills (Wisdom / Prayer / Discernment) with selected state; on-select shows "Inspired by…" sub-label | The prompt transformation is invisible. User taps "Discernment" but doesn't see that this forces a 5-step structure (name situation → motives → wisdom principles → consequences → wise path). No preview of what structure to expect. |
| **SSE Streaming** | Real-time token delivery from ClaudeService | Yes | Typewriter character-by-character rendering in chat bubble; composer enters `.streaming` state showing stop button and breathing ambient glow | Good. Stop button clearly present. Streaming glow on composer capsule is subtle but present. |
| **BereanThinkingStatus** (contextual phrases) | Cycles phrases like "Cross-referencing passages…", "Checking Scripture context…" during inference | Yes — `BereanThinkingStatus` widget exists in BereanFollowUpChips.swift | Spinning ring + rotating phrase string below the message list while generating | Good UX component, but it's a generic animation — phrases are mode-keyed off `modeID` string, not driven by what Berean is actually doing step-by-step at that moment. |
| **BereanGrokCoordinator input classification** | Classifies every keystroke in real time: intent (scripture/doctrine/personal/external/link/studyOutline), risk level (low/elevated/high/pastoral/crisis), whether input is long/contains links/is sensitive | Partially — `BereanGrokOverlay` shows `BereanComposerActionPillRow` | Composer action pills appear above the bar when input is classified and `bereanHelperModelEnabled` flag is ON | Feature-flagged. Classification result (intent, risk) is never directly shown to user. Pill row only surfaces 6 actions (simplifyFirst, summarizeLink, extractThemes, externalContext, checkScripture, createStudyOutline) — not the classification signal itself. |
| **Ghost draft inference and restore** | Persists unsent drafts per surface/mode, restores them as a tappable chip on re-open | Yes | `ghostDraftChip` renders above composer with "Continue: '…'" label and dismiss button | Reasonably well surfaced. Tapping restores draft. Gap: no indication of *when* the draft was saved or which mode it belongs to. |
| **Soaking state detection** | After 30 seconds of idle typing, `isSoaking = true` subtly modifies send button glow from `.edgeLitCapsule` to `.breathing` with `.focused` intensity | Invisible to user | Send button glow changes from edgeLit to breathing ambient — accessible only if user notices very subtle animation difference | Completely invisible in practice. No label, no tooltip, no visual change that communicates "Berean noticed you've been sitting with this." This is a missed emotional resonance signal. |
| **Keystroke rhythm inference** | Tracks 8-keystroke window; slow avg interval (>0.8s) infers prayerCompanion, high backspace density (>25%) infers deepStudy; writes to `inferredMode` | Partially invisible — drives `BereanModePickerSheet` "Suggested" badge | When mode picker is opened, inferred mode gets an amber "Suggested" capsule beside it | The suggestion only surfaces when the user manually opens the mode picker. No proactive nudge. User who never opens the picker never sees the inference at all. |
| **Tone nudge system** | After 12 seconds of typing >40 chars containing self-condemnation or bypassing phrases, `toneNudgeActive = true`; the slider/tools button glows gold and its accessibilityHint changes | Partially | Tools button foreground changes from `.textPrimary.opacity(0.58)` to `resolvedAccent` (gold); ambient glow switches to `.breathing`; tapping now opens ToneCheckerSheet instead of mode picker | Visual change is subtle (gold tint on one small button). No text label. A user who doesn't notice the color shift misses the intervention entirely. Gap: no explanatory nudge text like "Berean noticed something." |
| **Memory strip / context window** | `BereanMemoryStripView` shows topic nodes derived from prior messages: emoji + label + thread connector line; collapsible | Yes — view exists and is built | Horizontal scrolling node strip with "Context window · N topics" header; collapsible with chevron | The strip surfaces topic labels (Faith, Prayer, Tech, Business) but these are generated by a simple keyword matcher (`bereanTopicMeta`) — not the actual Firestore memory entries being used for generation. The real memory (`BereanMemoryService.insights`, `BereanContextMemoryService.memories`) injected into the prompt is never shown here. |
| **Persisted user memory** (BereanMemoryService / BereanContextMemoryService) | After each exchange, `extractMemoryFromConversation` runs a secondary Claude call to extract up to 2 facts (struggle/scripture/decision/interest/milestone/belief/prayer/question), saves to Firestore, updates `userContext` (spiritualTopics, recentStruggles, favoriteVerses, growthAreas), and `buildContextSummary()` injects up to 300 chars into the next system prompt | Nearly invisible | `SpiritualMemoryView` is accessible via the memory button in the header menu; `showSpiritualMemorySheet` sheet exists | The extraction happens silently. User never sees: "I just learned something about you and saved it." The `BereanContextSource` selector (`selectedContextSources`) in the view controller exists but is not rendered into any visible UI element in the chat scroll. No indicator that personalization is active during the current response. |
| **Memory scope selector** (off / thisChat / thisProject / allBerean) | Controls how much conversation history and cross-session context is injected into requests | Unknown — not rendered in any of the audited files | `BereanMemoryScopeStore.shared.scope` is read in `send()` and the value controls history building, but no UI chip/indicator shows the current scope in the chat view | Silent. User cannot see whether Berean has access to this-chat-only, all sessions, or no memory at all. |
| **Cross-session history injection** (allBerean scope) | Fetches last 4 sessions from Firestore, extracts up to 8 messages, prepends them chronologically to the current history | Invisible | No UI feedback whatsoever when cross-session context is being used | A user asking a follow-up question from a prior day has no idea their previous sessions are being read. No "drawing from your previous conversations" signal. |
| **BereanSourceGroundingService** (citation verifier) | Extracts verse references from responses; `hasBibleCitation()` gates auto-save; `classifySafety()` calls a Cloud Function for safety classification | Partially — citation extraction drives auto-save and smart pills | `BereanSmartPillsView` shows `.showScriptureContext` pill when citations exist; auto-save toast "Saved to Church Notes" appears | Safety classification result (safe/unsafe, userMessage) surfaces only if non-safe via `intelligence.safetyBanner`; citation extraction itself is invisible. User doesn't know when Berean verified sources vs. when it didn't. |
| **Provenance chips** | `BereanProvenanceRecord` tracks: helperModelUsed, externalContextUsed, scriptureChecked, safetyReviewed, bereanVerified verdict | Partially — built and stored | `capturedProvenance` is set on `messages[assistantIndex].provenance`; `showProvenanceLabels` AppStorage flag; `BereanGrokOverlay` has a provenance sheet | `BereanProvenanceChips.swift` file does not exist at the audited path — likely a view that should render per-message provenance chips but is not yet wired to the message bubble. The sheet can only be opened by `coordinator.showProvenance()`, which requires a user gesture that isn't clearly surfaced in the default flow. |
| **Smart pills** (BereanSmartPillsView) | Context-sensitive action pills below completed messages, driven by lens × crisis state × sensitivity flags × scripture presence | Conditionally visible | `BereanSmartPillsView` renders below `BereanSpiritualMessage` instances | Requires `BereanSpiritualMessage` type — plain `BereanChatMsg` messages in the default chat flow don't use this view. Gap: smart pills may not appear for all assistant messages. |
| **Follow-up suggestion chips** | `BereanIntelligenceCoordinator.processResponse()` generates follow-ups via `BereanStudyThreadService.generateFollowUps()` after each response | Partially | `intelligenceFollowUpRow` in the VStack overlay renders when `intelligence.followUpSuggestions` is non-empty | Good when populated. But suggestions only appear after `processResponse()` completes async — there's a latency window where the message has arrived but follow-ups haven't. No loading state for this. |
| **BereanThinkingStateBanner** (thinking steps) | During inference, cycles through `BereanThinkingStep` cases: "Understanding your question…", "Checking Scripture context…", "Reviewing safety…", "Preparing response…" | Yes — but feature-flagged | `BereanThinkingStateBanner` shown above composer when `vm.isThinking && bereanHelperModelEnabled` | Good UX when enabled. Exposes that safety review is happening, which builds trust. But it's a timed cycle, not driven by actual backend step completion signals. |
| **Study mode reasoning nodes** | `BereanStudyModeSurface` shows 9 reasoning categories (scripture, crossReferences, commentary, sermons, articles, originalLanguage, historicalContext, application, notes) with states (idle/scanning/active/complete) | Yes — when study mode is toggled ON | `BereanStudyModeSurface` renders above messages when `vm.isStudyModeEnabled`; nodes animate through states during inference; tapping a node opens `BereanReasoningSummarySheet` | Well surfaced. The best-in-class intelligence surface in the app. But it requires an explicit opt-in toggle ("Study" button in header). Default off means most users never see it. |
| **Model tier and fallback** | SSE terminal event provides `onModeAuthority` callback; if server downgraded the tier, `modelFallbackNotice` is set and shown for 4s | Yes | `modeFallbackBanner` appears at bottom overlay with clear text: "Berean switched to Core — Deep requires a Pro subscription." | Good. Transparent about tier decisions. |
| **Paywall / message limit** | Free users capped at 10 messages | Yes | `paywallBanner` appears in the bottom overlay stack | Clear. |
| **Dynamic Island Live Activity** | During BereanIslandViewModel triggered queries (from PostCard), drives thinking aura blob + "thought for Ns" + scripture reference surfaced to Live Activity | Yes — in context | `BereanDynamicIsland` view: aura blob in thinking state; card drops with response snippet + "thought for Ns" timer | Only triggered from PostCard quick queries, not from main BereanChatView streaming. Gap: the main chat has no equivalent "thinking time" counter. |
| **Crisis escalation detection** | `crisisEscalationDetected` is set when preflight `shortCircuitResponse` is non-nil; crisis responses bypass alignment sanitization and show pre-approved life-saving contact info | Partially | Crisis state changes smart pills to safety override set (Pause, Breathe, Talk to Someone, Find Help, Psalm 23, Save Privately) | The fact that a crisis was detected is never announced to the user in non-crisis-pill UI. No banner like "We noticed this might be a difficult moment." Alignment check bypass is invisible. |
| **Biblical alignment post-processing** | Every completed response runs `BiblicalAlignmentService.checkBiblicalAlignment()`; status can be aligned/contextNeeded/needsDiscernment/blocked; response may be prepended with a context note or silently rewritten | Completely invisible | None — no UI signal of any kind when this runs or modifies a response | Critical gap. The response the user reads may be different from what the model generated. They have no way to know this, which reduces trust rather than building it. |
| **Discernment prompt intercept** | Before sending, `BiblicalAlignmentService.getDiscernmentPrompt()` can set `shouldPrompt = true` and surface `SpiritualDiscernmentPromptView` | Partially visible | Sheet appears with discernment options before the message is sent | Good — this is a visible pre-send intervention. User actively chooses a lens. |
| **Tone checker / ToneCheckerSheet** | Activated by `toneNudgeActive` when self-condemnation or bypassing phrases are detected; offers a rewrite | Partially — via subtle button glow | Gold glow on tools button; tapping opens ToneCheckerSheet only when `toneNudgeActive` | The trigger visual (gold button) is too subtle. Most users will miss it. |
| **Context lens** | `BereanContextLensView.fromConversationState()` shows mode/context status overlay when thinking or manually pinned | Partially | Shown above mode bar when `vm.isThinking || showContextLens` | Good — visible during thinking. But it disappears immediately when thinking stops. Only shows the context, not what specifically was injected. |
| **BereanConversationSafetyService** | Analyzes messages for sexual intent, aggression, manipulation, grooming; builds SafetyIntervention with escalating levels; injects typing delays at moderate/elevated risk | Partially — intervention sheet | `activeIntervention` drives a sheet with scripture + options (redirect, pause, restrict) when level >= .mild | Used in peer messaging, not in the AI chat surface. Typing delay and intervention are surfaced but the user doesn't know the system is actively monitoring the conversation for safety signals. |
| **BereanActionEngine** | Extracts actionable imperatives from AI responses (pray, read, study, reflect, journal, reach_out, share, apply); saves to Firestore; schedules growth loop notifications | Invisible | `extractActions()` returns suggestions but no view in the audited files renders them in-chat | The system exists but its output is never surfaced in the conversation view itself. |
| **Handoff / Spotlight / Siri Prediction** | Chat session registers a `NSUserActivity` with title, sessionId, and last query for multi-device handoff and Siri prediction | Invisible in-app | `userActivity` modifier in the view body | Expected to be invisible in-app; surfaces in iOS system. |

---

## Invisible Capabilities (critical gaps)

These are features that run during every or most conversations with zero visual feedback to the user:

### 1. Memory extraction (silent secondary AI call)
After every exchange, `BereanContextMemoryService.extractMemoryFromConversation()` runs a separate Claude API call to extract personal facts from the conversation. The user never sees: that this is happening, what was extracted, or that their profile is being updated. This is a significant trust and transparency gap — especially under GDPR/CCPA and because users interacting with a spiritual AI assistant have heightened expectations around data.

**Impact:** High. Spiritual intimacy requires explicit consent visibility.

### 2. Biblical alignment post-processing (silent response rewriting)
`BiblicalAlignmentService.checkBiblicalAlignment()` runs on every completed response. Status `contextNeeded` prepends text; `needsDiscernment` may silently replace the response with a rewrite; `blocked`/`humanReview` replaces with a refusal message. The user has no idea the response they are reading has been modified from what the model generated.

**Impact:** Critical. Silent rewriting destroys trust if users ever discover it. Even well-intentioned rewriting should be transparent ("Berean added context for clarity").

### 3. Cross-session memory injection
When `memoryScope == .allBerean`, Berean fetches messages from the user's last 4 conversations and injects them into the current context. No badge, chip, or disclosure tells the user "drawing on 3 previous conversations." The user cannot see which sessions are being read.

**Impact:** High. Users need to know their prior conversations influence current answers.

### 4. Soaking state
After 30 seconds of idle composition, `isSoaking = true` changes the send button glow from edge-lit to breathing. The intent is poetic (mirroring the user "soaking in prayer") but the signal is completely imperceptible to virtually all users. The emotional moment is wasted.

**Impact:** Medium. A missed resonance opportunity that could meaningfully differentiate Berean from generic chat AI.

### 5. Keystroke rhythm inference (mode suggestion trapped behind picker)
Slow keystrokes infer `prayerCompanion`; high backspace density infers `deepStudy`. The result `inferredMode` only surfaces as an amber "Suggested" badge *inside the mode picker sheet*, which requires the user to manually open the picker. Users who never open the mode picker never see the inference.

**Impact:** Medium. The inference is valuable but its surfacing mechanism is non-existent in practice.

### 6. Safety classification on responses
`BereanSourceGroundingService.classifySafety()` calls a Cloud Function (`classifyBereanSafety`) on every completed response. If non-safe, `intelligence.safetyBanner` shows. But there is no feedback when the check completes as "safe" — no confidence indicator, no "Berean reviewed this response" signal.

**Impact:** Medium. A confidence/trust chip showing safety was reviewed would build user trust without surfacing unsafe content.

### 7. BereanActionEngine extraction
`extractActions()` parses every AI response for imperative actions (pray, read, study, journal, etc.). These are saved to Firestore and drive the growth loop notification system. But the extracted actions are never shown in-conversation. The user has no opportunity to review, confirm, or dismiss them.

**Impact:** Medium. Unseen actions in Firestore with upcoming notifications create a surprise/distrust experience.

### 8. Context building from prior messages (BereanContextMemoryService.buildContextSummary)
`buildContextSummary()` builds up to 300 chars of "User context: struggling with X; interested in Y; growing in Z; has asked about A, B, C before" — but this is injected silently into system prompts. The user has no way to see or edit this context profile during a conversation.

**Impact:** Medium-high. This is the most direct form of personalization and users cannot audit or correct it without navigating to a separate settings screen.

---

## Partially Visible Capabilities

### Tone nudge system
The mechanism exists and is wired — the tools button turns gold and breathing when `toneNudgeActive`. However:
- The color change is too subtle for most users to notice
- There is no text label or tooltip
- The accessibilityHint says "Berean noticed something — tap to check your tone" but only VoiceOver users see this
- Recommendation: Add a small animated text pill below the composer: "Berean noticed something" with a tap-to-open affordance.

### Keystroke rhythm inference → mode suggestion
The inference runs and stores `inferredMode` correctly. The "Suggested" badge inside the mode picker sheet is a good pattern. But it requires manual discovery. The recommendation is a non-intrusive proactive nudge: a brief context-aware placeholder or a subtle chip appearing near the mode indicator.

### Memory strip view
`BereanMemoryStripView` displays topic nodes derived from keyword matching of the conversation. It correctly collapses/expands and fires `onNodeTap`. However:
- The topics are based on a simple 5-category keyword matcher, not the actual memory entries being injected into the system prompt
- Real memory (`BereanContextMemoryService.memories`) is invisible here
- The strip label "Context window" is technically accurate but doesn't communicate *personalized memory recall*

### Follow-up suggestion row
`intelligence.followUpSuggestions` renders chips above the composer when non-empty. Good. But:
- There's no loading state while follow-up generation is in progress
- The suggestions are not labeled as "AI-generated follow-ups" vs. static chips
- When `followUpSuggestions` is empty, `focusedSuggestionRow` (mode-static chips) shows instead — the user cannot distinguish AI-generated suggestions from static templates

### Provenance (partially wired)
`capturedProvenance` is attached to assistant messages. `BereanProvenanceSheet` exists and renders provenance details. `showProvenanceLabels` AppStorage flag exists. But `BereanProvenanceChips.swift` doesn't exist at the expected path, meaning no per-message chips render. The sheet can only be reached via `coordinator.showProvenance()` — a call path that must be triggered by a context menu action.

### Safety intervention (BereanConversationSafetyService)
When risk level >= `.mild`, an intervention sheet appears with a scripture reference and options. This is visible and appropriate. However, users aren't told what triggered it (beyond the scripture reference), and the `typingDelayMs` friction (200-400ms) is invisible.

---

## Well-Surfaced Capabilities

### Study mode reasoning nodes
`BereanStudyModeSurface` is the best example of transparent AI process in the app. When study mode is ON:
- 9 reasoning categories animate through scanning → active → complete states
- A collapsible summary view appears when scrolled away
- Tapping a node opens a detail sheet
- The header capsule gains a graduation cap icon
This is excellent. It treats the AI's reasoning as a first-class UI object.

### Model tier and fallback banner
`modeFallbackBanner` is clear, honest, and auto-dismisses after 4 seconds. Text explains the reason ("Deep credits exhausted", "requires Pro subscription"). Good transparency.

### Stop generation button
The stop button replaces the send button during streaming, is clearly labeled, has proper haptics, and cancels the stream task correctly.

### Dynamic Island (BereanDynamicIsland)
For PostCard-triggered queries, the Dynamic Island overlay shows: thinking aura blob, "thought for Ns" counter after completion, response snippet with typing effect, and "Open Full" deep link. The thinking-to-responded state transition is polished.

### Mode chip above composer
`selectedComposerModeChip` with icon + text label above the composer is clear and tappable. The header mode capsule when scrolled reinforces mode awareness.

### Discernment prompt intercept
`SpiritualDiscernmentPromptView` as a pre-send gate is well-executed: it interrupts before sending, presents clear options, and allows dismissal to send without modification.

### Ghost draft chip
The draft restore chip is well-labeled ("Continue: '...'"), dismissable, and correctly restores draft on tap.

### Paywall banner
Clear, informative, correctly positioned in the overlay stack.

---

## Recommended Intelligence Surface Additions

Ranked by user trust and intelligence visibility impact:

### 1. Memory activity indicator (trust-critical)
**Problem:** Silent memory extraction and profile building.
**Recommendation:** A small persistent chip or badge in the session header: "Berean is learning from this conversation" with a link to Spiritual Memory view. After memory extraction, flash a brief toast: "Berean saved a reflection from this conversation." Make extraction opt-in confirmation on first use.

### 2. Transparent response post-processing disclosure
**Problem:** Biblical alignment rewriting is completely silent.
**Recommendation:** When `status == .contextNeeded`, prepend an inline chip before the response body: "Berean added context for reflection." When `status == .needsDiscernment` triggers a rewrite, show a diff affordance: "Berean refined this response — tap to see original." Never silently replace without a user-visible signal.

### 3. Soaking state visual — "You've been sitting with this"
**Problem:** 30 seconds of composing silence detects spiritual soaking but the signal is imperceptible.
**Recommendation:** After 30 seconds, animate a brief text label below the send button: "Take your time" or "Berean is ready when you are." The breathing glow is present but too subtle; pair it with text.

### 4. Context injection disclosure ("drawing on…" chip)
**Problem:** Cross-session memory injection is invisible.
**Recommendation:** When `memoryScope == .allBerean` and cross-session messages were fetched, show a small chip above the first response in the session: "Drawing on 2 previous conversations." Tapping opens a list of which conversations were included with timestamps.

### 5. Tone nudge pill (replace invisible button glow)
**Problem:** The tone nudge relies on a subtle gold button tint that most users miss.
**Recommendation:** When `toneNudgeActive = true`, animate a small pill below the composer: "Berean noticed something — tap to check" with a dismiss X. This text-labeled intervention is far more discoverable than a color change on a small button.

### 6. Provenance chips per message
**Problem:** `BereanProvenanceChips.swift` does not exist; provenance data is attached to messages but never rendered.
**Recommendation:** Build and wire `BereanProvenanceChips` — small horizontal chips below each assistant message. Minimal version: scripture-verified badge, safety-reviewed badge, helper-model-used badge. Full version: tap to expand `BereanProvenanceSheet`. This directly answers "how do I know Berean checked this?"

### 7. Keystroke inference proactive nudge
**Problem:** Mode suggestion from keystroke rhythm is trapped behind manual mode picker.
**Recommendation:** When `inferredMode` is set, show a non-intrusive suggestion chip near the mode indicator: "Prayer mode? Berean noticed your pace." Dismissable. One tap to accept. Should not interrupt or delay typing.

### 8. Safety check confidence indicator
**Problem:** `classifySafety` runs on every response but the user only hears about it when it fails.
**Recommendation:** A small "Berean reviewed" checkmark or shield micro-badge on completed messages when safety classification returned "safe." Subtle, but it builds accumulated trust over many interactions.

### 9. Memory scope indicator in session header
**Problem:** Users don't know whether Berean has access to this chat only, all sessions, or no memory.
**Recommendation:** A small persistent badge in the header or above the composer showing the current memory scope: "This chat only" / "All Berean conversations" / "No memory." Tapping opens memory scope settings.

### 10. Action extraction review card
**Problem:** BereanActionEngine extracts actions silently and schedules notifications without user review.
**Recommendation:** After responses containing 2+ extracted actions, show a compact card: "Berean extracted 2 action steps — review?" Expanding it shows the actions with check/dismiss controls before they enter Firestore and the notification queue.

---

## Summary Table: Visibility by Category

| Category | Score | Main Gap |
|---|---|---|
| Streaming / generation status | 8/10 | No per-step backend progress signal |
| Mode and lens selection | 7/10 | Effect on response structure invisible |
| Memory and personalization | 2/10 | All activity completely silent |
| Retrieval and grounding | 3/10 | Citation extraction visible only indirectly via smart pills |
| Safety classification | 3/10 | Only failure case surfaced; pass case invisible |
| Provenance | 2/10 | Data attached to messages, never rendered |
| Study mode reasoning | 9/10 | Excellent — model intelligence as first-class UI |
| Tone and safety interventions | 4/10 | Tone nudge too subtle; crisis pills good |
| Action extraction | 1/10 | Completely invisible |
| Post-processing (alignment) | 0/10 | Silent rewriting, critical trust gap |
