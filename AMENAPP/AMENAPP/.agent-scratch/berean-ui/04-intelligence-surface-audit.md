# Berean Intelligence Surface Audit

**Agent D — Intelligence Surface Audit**
**Date:** 2026-05-28
**Branch:** berean/ui-rebuild-liquid-glass-v1

---

## Capability × UI Visibility Matrix

| Capability | What It Does | Where UI Shows It | Visibility Score (0–5) | Gap Description |
|---|---|---|---|---|
| 5 Personality Modes (askBerean, scriptureStudy, prayerCompanion, deepStudy, discernment) | Routes system prompt, response tone, and retrieval strategy per mode | BereanComposerTray mode picker row + mode chip chips (BereanComposerTray.swift L73–439); selectedComposerModeChip above composer (BereanChatView.swift L1953–1970); headerModeCapsule when scrolled (L1486–1517); BereanThreadCapsule expanded drawer (BereanThreadCapsule.swift L208) | 4 | `discernment` is referenced in heroPrompt (BereanChatView.swift L2061) but NOT present in BereanPersonalityMode enum (BereanAIAssistantView.swift L6815–6826). Enum has 11 modes total; tray only surfaces 5 primary ones. The 6 legacy modes (shepherd, scholar, coach, builder, strategist, creator) are reachable only through BereanModeDrawer sheet, not the tray. |
| SSE Token Streaming | Delivers AI tokens character-by-character; 80ms debounce buffer reduces SwiftUI diffs | Message content updates live during `.streaming` state; stop button replaces send arrow (BereanDesignSystem.swift L255–258); `BereanThinkingStrip` shows "Drafting response…" while `isThinking` (BereanChatView.swift L1324–1327) | 4 | The strip shows only `.drafting` for all streaming — it never transitions to `.retrieving`, `.verifying`, `.grounding`, etc. SSE is multi-phase internally but the UI shows a single verb. The model fallback notice (L1013–1018) IS shown when the backend downgrades tiers. |
| Firestore Conversation Persistence | Writes each exchange to `bereanConversations/{id}/messages/` subcollection with 90-day TTL; supports cross-device resume | BereanChatsListView surfaces past sessions; `loadOlderMessages` button in scroll (BereanChatView.swift L1648–1659); conversation title in header and thread capsule | 3 | No visible "saved" confirmation after each exchange. Users cannot tell when persistence is ON vs. OFF without going to memory settings. Memory scope selector exists (BereanMemoryScopeStore) but no current-session inline indicator. |
| Pinecone Vector Retrieval | RAG pipeline uses Pinecone for semantic similarity search as part of BereanRAGService | INVISIBLE — not surfaced in UI | 0 | BereanRAGService (BereanRAGService.swift L706–748) describes Pinecone retrieval in comments but the iOS RAG implementation uses `BereanLocalRetriever` (local scripture index + Firestore saved posts). The UI surface for source readiness exists (`BereanContextLensView` with `.ready/.loading/.limited`) but `sourceReadiness` is never wired to actual Pinecone query state in BereanChatView. |
| BereanContextMemoryService (Long-Term Memory) | Persists 8 semantic categories (scripture, decision, struggle, interest, milestone, belief, prayer, question) to Firestore; builds context summary prepended to prompts via Claude extraction | BereanMemoryChip above composer (BereanChatView.swift L1076–1083); tapping opens BereanMemoryDetailSheet; gold shimmer when active; gold dot in BereanThreadCapsule compact view (BereanThreadCapsule.swift L105–109) | 3 | Memory chip is wired to `vm.isThinking` for active state but `entries: []` is hardcoded (L1077). No entries from BereanContextMemoryService are passed to the chip. Sheet shows empty state for all users. The `continuationSuggestion()` method (BereanContextMemoryService.swift L346–354) is never called in any UI. |
| BereanRAGService (Retrieval-Augmented Generation) | Classifies query intent (9 types), retrieves local scripture + saved content + topic catalog, builds structured prompt, provides follow-up suggestions | BereanIntelligenceCoordinator follow-up suggestions row (BereanChatView.swift L1030–1034); intelligence safety banner (L1024–1029); scripture chips extracted from response text (L3065–3077) | 2 | BereanRAGService generates follow-up suggestions but they come from BereanIntelligenceCoordinator, not directly surfaced. The source attribution (BereanRetrievalSource with type/icon/color) is defined and rich but never rendered in the chat UI. BereanCitationRow (L3016) renders provenance.sources — but provenance is only populated from Grok coordinator, not the RAG pipeline. |
| BereanAnswerEngine (Citation-First Answers) | Enforces "no citation → no claim" policy; classifies intent (7 types); fetches YouVersion scripture; generates cited answers with historical context + interpretations per InterpretationMode (5 modes) | BereanScriptureReferenceExtractor surfaces references as tappable chips (BereanChatView.swift L3067–3076); `BereanCitationRow` for provenance sources (L3016); `ScriptureCitationRow` chip row; `AmenTranslationComparisonInline` for the first detected reference (L3072) | 2 | BereanAnswerEngine.answer() is a standalone class that is NOT called anywhere in BereanChatViewModel.send(). The send path goes through `ClaudeService.shared.sendBereanChatMessage()` directly. BereanAnswerEngine's citation pipeline (YouVersion fetch, InterpretationMode, historical context, TheologicalInterpretation) is entirely disconnected from the main chat. Scripture chips are surface-detected from response text via regex, not from BereanAnswerEngine's verified citations. |
| Citation Verifier Flow | BereanAnswerEngine: validates quotes are accurate to source (also listed as a BereanCapability in the tray) | Listed in `bereanCapabilities` panel (BereanComposerTray.swift L39): "Checks that quotes are accurate to their source." BiblicalAlignmentService.checkBiblicalAlignment() runs post-response (BereanChatView.swift L498–520) | 1 | The capabilities panel lists "Citation Verification" but it is documentation-only — no UI outcome from a citation check is ever shown to the user. BiblicalAlignmentService runs alignment checks silently and may silently rewrite or block responses (L504–519) without any user-visible "verified" or "unverified" label. |
| RTDB Context (Real-Time Database) | Provides live contextual signals (BereanContextResolver, BereanPostContext) for post-aware Berean sessions | BereanPostContext validation message shown in scroll (BereanChatView.swift L1582–1596) when post context is unavailable; postAvailabilityMessage surfaced inline | 2 | RTDB context is consumed invisibly — when available it enriches the prompt but no badge/chip tells the user "responding in context of [post title]." BereanPostContext carries postId, postContent, and an initialPrompt but only its absence (error state) is ever shown. |
| BereanContextMemoryService — Smart Recall / Continuation Suggestion | `recallRelevant()` keyword-scores all memories against the current query; `continuationSuggestion()` returns "You explored X Y ago — want to continue?" | INVISIBLE — `continuationSuggestion()` is never called from any view | 0 | The continuation suggestion string is computed but wired to nothing. No chip, banner, or inline card ever surfaces it. Hero section has resume cards (BereanChatView.swift L898–917) with similar semantic intent but they are hardcoded placeholder data, not driven by BereanContextMemoryService. |
| Dynamic Island Live Activity | BereanIslandViewModel triggers thinking/responded states; BereanLiveActivityManager manages ActivityKit session | BereanDynamicIsland.swift view exists; `trigger()` called from post-card Berean button; `startLiveActivityIfNeeded()` called on trigger | 3 | Live Activity is wired for the post-card "quick Berean" flow. Inside BereanChatView itself there is NO Live Activity start/stop wired to `vm.isThinking`. The main chat session never updates the Dynamic Island. BereanIslandViewModel.shared is a standalone path, not integrated with BereanChatViewModel. |
| Study Mode (BereanStudyModeState + ReasoningNodes) | Runs 9 BereanReasoningCategory dimensions simultaneously; shows scanning/active/complete states; saves outline to Church Notes | studyModeToggle in header (BereanChatView.swift L1519–1546); BereanStudyModeSurface in message list (L1631–1645); reasoningNode detail via BereanReasoningSummarySheet (L1201–1203); headerModeCapsule shows graduationcap icon when enabled (L1495–1497) | 4 | Study mode UI is well surfaced. Gap: node states (scanning/active/complete) are set in `beginReasoning()` before the AI response arrives — they are simulated, not driven by actual retrieval events. All nodes resolve to `.complete` immediately when streaming ends (resolveReasoning, L620–630) regardless of what was actually retrieved. |
| Grok Helper Model (System 27) | `BereanGrokCoordinator` classifies input in real-time as user types; drives thinkingStep banner during inference; records provenance (helperUsed, externalUsed, sensitiveDetected) | BereanGrokOverlay rendered above composer (BereanChatView.swift L1057–1058); BereanThinkingStateBanner shown while `bereanHelperModelEnabled` flag is ON (L1050–1055); BereanProvenanceChipRow shown after message when `bereanHelperProvenanceChipsEnabled` (L3004–3011) | 3 | Both Grok features are behind `AMENFeatureFlags` gates. When flags are OFF, provenance chips and thinking steps are both invisible. When ON, provenance chips appear but their tap action only calls `vm.grokCoordinator.showProvenance(provenance)` — no sheet or expansion is implemented. |
| BiblicalAlignmentService (Post-response check) | Runs alignment check on every completed response; can silently rewrite (needsDiscernment), add context note, or block (.humanReview) | "Correct the AI" button on every assistant message (BereanChatView.swift L3046–3053); CorrectTheAIView sheet (L1204–1238) | 1 | The alignment result (aligned/contextNeeded/needsDiscernment/blocked) is applied silently — no user-visible label differentiates an unmodified vs. a silently rewritten response. Only `.contextNeeded` prepends a visible note (L508–510). The "Correct the AI" button is always visible but implies manual correction rather than reflecting the automated alignment status. |
| Memory Scope Selector (Off / ThisChat / ThisProject / AllBerean) | Controls how much conversation history is included in each AI call; AllBerean fetches cross-session Firestore context | BereanMemoryScopeStore drives behavior; no inline current-scope indicator in BereanChatView | 1 | Scope is set somewhere in settings/onboarding but the active scope is never shown in the chat UI. Users cannot tell if they are in "off" (no history) vs "allBerean" (cross-session) mode without leaving the chat. BereanMemoryChip always shows "Memory" without indicating scope level. |
| Discernment Prompt (SpiritualDiscernmentPromptView) | BiblicalAlignmentService.getDiscernmentPrompt() intercepts sends that trigger spiritual discernment flags; presents option sheet before sending | SpiritualDiscernmentPromptView sheet presented before send when `prompt.shouldPrompt` (BereanChatView.swift L1366–1376) | 3 | The discernment sheet is well implemented but entirely invisible to the user until it triggers. No pre-send indicator shows that discernment checking is active. Some users may not understand why a sheet appeared before their message was sent. |
| Voice Input (WhisperVoiceViewModel) | Records user audio → Whisper transcription → places text in composer for review before sending | BereanVoiceInputSheet presented when voice action triggered (BereanChatView.swift L1158–1166); voice button in BereanInputComposer when text is empty (BereanDesignSystem.swift L237–243) | 4 | Well surfaced. Gap: `showVoiceDisabledAlert` (L1151–1155) only shows when `BereanAISettingsStore.voiceInputEnabled` is false, with no inline affordance to turn it on from the alert. |
| Attachment Picker (Files / Photos) | BereanAttachmentPickerSheet allows file or photo attachment; result prepends context text to user message | Attach icon in BereanInputComposer (BereanDesignSystem.swift L209–215); BereanAttachmentPickerSheet (BereanChatView.swift L1124–1145); "Attachments unavailable" alert when feature is off (L1146–1150) | 3 | Feature gate: `showAttachmentsComingSoon` alert path shows when disabled. When enabled the file/photo flows work, but no persistent indicator shows an active attachment before send. |

---

## Invisible Capabilities (Score 0–1)

### 1. Pinecone Vector Retrieval (Score: 0)
**What it does:** BereanRAGService is architected for semantic vector retrieval via Pinecone (mentioned in SemanticEmbeddingService.swift L8). BereanLocalRetriever retrieves from a local ScriptureIndex (20 hardcoded verses), DiscoveryTopic catalog, and Firestore savedPosts.

**Why invisible:** The `BereanContextLensView` (BereanContextLensView.swift) has a `sourceReadiness` property with `.ready/.loading/.limited` states and appropriate iconography — but in BereanChatView.swift the view is shown with `fromConversationState()` which computes readiness from `messageCount` and `isThinking`, not from actual Pinecone query results. The RAG pipeline result is returned as a `BereanRAGResponse` but is never passed downstream to the view layer.

**File refs:**
- Service: `AMENAPP/BereanRAGService.swift` L682–758
- Context lens: `AMENAPP/BereanContextLensView.swift` (all)
- Chat wiring: `AMENAPP/BereanChatView.swift` L1061–1071

---

### 2. BereanContextMemoryService Continuation Suggestion (Score: 0)
**What it does:** `continuationSuggestion(for query:)` (BereanContextMemoryService.swift L346–354) produces a string like "You explored 'Faith and Doubt' 3 days ago — want to continue?" The method is fully implemented with RelativeDateTimeFormatter and is correct code.

**Why invisible:** Zero call sites in the view layer. The hero section's `resumeCards` (BereanChatView.swift L898–917) are semantically identical but are hardcoded placeholder text, not driven by this method. The service's `memories` array is populated from Firestore but the UI never reads it for surfacing continuations.

**File refs:**
- Service: `AMENAPP/BereanContextMemoryService.swift` L346–354
- Hero resume cards (placeholder): `AMENAPP/BereanChatView.swift` L898–917

---

### 3. Citation Verifier — visible outcome (Score: 1)
**What it does:** BereanAnswerEngine runs a full citation verification pipeline. BiblicalAlignmentService.checkBiblicalAlignment() runs on every completed response. Both produce a verified/unverified/contested status.

**Why nearly invisible:** Both run silently. The only user-facing artifact is:
- "Correct the AI" button (visible on all messages regardless of alignment status)
- A contextNote prepend in the `.contextNeeded` case (usually never triggered)

The capabilities tray lists "Citation Verification" but this is marketing copy — no per-message verification badge, no "verified" checkmark, no "unverified" callout.

**File refs:**
- Engine: `AMENAPP/BereanAnswerEngine.swift` (entire file — disconnected from chat)
- Alignment check: `AMENAPP/BereanChatView.swift` L498–520
- Capabilities panel: `AMENAPP/BereanComposerTray.swift` L39

---

### 4. Memory Scope (Score: 1)
**What it does:** BereanMemoryScopeStore controls whether 0, 10 (thisChat), project-scoped, or cross-session (allBerean) messages are sent to the AI. AllBerean fetches from up to 4 recent Firestore sessions.

**Why nearly invisible:** The scope is set in settings, never reflected in the chat UI. BereanMemoryChip shows "Memory" without any scope indicator. The word "allBerean" never appears to users.

**File refs:**
- Scope handling in send: `AMENAPP/BereanChatView.swift` L363–373
- Memory chip: `AMENAPP/BereanMemoryChip.swift` L130–145

---

### 5. BiblicalAlignmentService — silent rewrites (Score: 1)
**What it does:** Post-response, the service can silently modify a response (`.needsDiscernment` → rewrite), prepend a context note (`.contextNeeded`), or replace with a blocking message (`.blocked/.humanReview`). Users receive a different response than what Berean originally drafted.

**Why nearly invisible:** The modification happens silently at `messages[capturedIdx].content = ...` (BereanChatView.swift L513, L517). No "edited" badge, no "alignment applied" label, no way for a user to see the original vs. the rewritten version.

**File refs:**
- Silent rewrite logic: `AMENAPP/BereanChatView.swift` L498–520

---

## Partially Visible (Score 2–3)

### 1. BereanRAGService Source Attribution (Score: 2)
The RAG pipeline's `BereanRetrievalSource` model has fully designed UI properties: `displayLabel`, `icon`, `iconColor` (BereanRAGService.swift L47–75) — but these properties are never rendered. BereanCitationRow at L3016 renders `provenance.sources` (Grok provenance, not RAG sources). The IntelligenceCoordinator follow-up chips at L1030–1034 are the closest visible output from the RAG intent classifier.

### 2. Firestore Conversation Persistence (Score: 3)
Sessions are read back in BereanChatsListView and the `loadOlderMessages` button correctly shows when `hasOlderMessages` is true. But there is no per-message save confirmation, no "sync'd" indicator, and no way to see from within a conversation whether memory scope is "off" (deleting each exchange on completion) vs. "on."

### 3. BereanContextMemoryService Long-Term Memory (Score: 3)
BereanMemoryChip has excellent UX design — shimmer on active, pulsing gold border, tappable detail sheet. The gap is entirely in wiring: `entries: []` is hardcoded at BereanChatView.swift L1077. The service listener (`startListening()`) is never called from BereanChatView or its ViewModel. `extractMemoryFromConversation()` is never called after a completed exchange.

### 4. RTDB / Post Context (Score: 2)
Error state is shown (postAvailabilityMessage banner) but success state is invisible. When Berean is responding in the context of a specific post, users get no visible indicator — no "Responding about [post excerpt]" banner, no context chip.

### 5. Dynamic Island Live Activity (Score: 3)
Fully implemented for the PostCard "quick Berean" trigger path. Not wired to BereanChatViewModel's `isThinking` state. The main chat UI and the Live Activity are independent execution paths.

### 6. Discernment Prompt (Score: 3)
Fires correctly when `BiblicalAlignmentService.getDiscernmentPrompt()` returns `shouldPrompt = true`, surfacing `SpiritualDiscernmentPromptView`. Well designed but users get no pre-send nudge that discernment checking is running.

### 7. Grok Helper / Provenance Chips (Score: 3)
Feature-flagged. When enabled: `BereanProvenanceChipRow` and `BereanGrokOverlay` show. Tap handler for provenance exists but has no sheet implementation.

---

## Well Surfaced (Score 4–5)

### 1. Mode Selection — 5 Primary Modes (Score: 4)
BereanComposerTray (L73–439) is the best-surfaced capability. The tray:
- Auto-collapses to a mode icon button in the composer (L521–552)
- Shows all 5 primary modes inline without a sheet
- Detects draft intent and highlights the suggested mode (modeKeywordChips, L334–373)
- Persists selected mode to vm.currentMode
- Propagates to the thread capsule, header, and hero prompt copy

Gap: The `discernment` mode referenced in heroPrompt (L2061) and BereanComposerTray previews (L626) does NOT exist in the `BereanPersonalityMode` enum — it will crash or silently fall through at runtime.

### 2. SSE Token Streaming (Score: 4)
The streaming UX is well executed:
- 80ms debounce buffer for smooth rendering (L463–481)
- Stop button replaces send arrow during streaming (BereanDesignSystem.swift L255–258)
- BereanThinkingStrip shows "Drafting response…" (BereanChatView.swift L1324–1327)
- `.cancelled` and `.failed` states are handled with user messages

Gap: BereanThinkingStrip defines 9 action states (retrieving, verifying, grounding, drafting, studyMode, prayerMode, alignmentCheck, memoryRead, memoryWrite) but the chat view only ever sets `.drafting` or `.idle` (L1324–1327). The richer states are never triggered.

### 3. Study Mode (Score: 4)
BereanStudyModeSurface, studyModeToggle, headerModeCapsule with graduation cap icon, BereanReasoningSummarySheet per node — the full Study Mode path is coherent and accessible. Gap: node states are simulated (all resolve to `.complete` on stream end), not event-driven.

### 4. Voice Input (Score: 4)
BereanVoiceInputSheet properly gates behind `voiceInputEnabled` flag, places transcript in composer for review before send, and is accessible from the mic button in the input bar.

---

## Recommendations: What to Surface Next

### Priority 1 — Critical Wiring Gaps

**1a. Wire BereanContextMemoryService entries to BereanMemoryChip**
- `BereanContextMemoryService.shared.startListening()` must be called in `BereanChatViewModel.init()`
- Pass `BereanContextMemoryService.shared.memories` (mapped to `BereanMemoryDisplayEntry`) into `BereanMemoryChip(entries:)`
- Call `extractMemoryFromConversation()` inside `persistExchange()` after the assistant message is confirmed
- Target file: `AMENAPP/BereanChatView.swift` L1076–1083 and the `persistExchange()` function

**1b. Surface `continuationSuggestion()` in the hero section**
- Replace the 3 hardcoded `resumeCards` with `BereanContextMemoryService.shared.recallRelevant(to: "")` or `continuationSuggestion()` calls
- Target file: `AMENAPP/BereanChatView.swift` L898–917

**1c. Fix `discernment` PersonalityMode enum gap**
- `.discernment` is referenced in `heroPrompt` (L2061), `BereanComposerTray` previews (L626), and `BereanComposerTray` primaryModes must either add `case discernment` to `BereanPersonalityMode` or correct call sites
- This is a crash risk if `.discernment` is ever passed to a switch exhausting all cases

### Priority 2 — Source Visibility

**2a. Drive BereanThinkingStrip from pipeline phases**
- Wire `.retrieving` when BereanLocalRetriever / RAG starts
- Wire `.verifying` when BiblicalAlignmentService starts
- Wire `.memoryRead` when BereanContextMemoryService is consulted
- Wire `.memoryWrite` when `extractMemoryFromConversation()` runs
- The action enum and strip are fully ready — only the drive sites are missing

**2b. Show RAG source chips below the response**
- `BereanRetrievalSource` already has `displayLabel`, `icon`, `iconColor`
- Add a `BereanRAGSourceRow` (similar to `BereanCitationRow`) rendered after assistant messages when sources are non-empty
- Requires BereanRAGService.generateResponse() to be called during send and the result stored on the message

**2c. Show active Post Context chip**
- When `vm.activePostContext != nil`, render a dismissable glass chip above the composer showing post excerpt or title
- Current: only error state (unavailable) is shown

### Priority 3 — Trust and Transparency

**3a. Add alignment status badge to messages**
- BiblicalAlignmentService results (`.aligned`, `.contextNeeded`, `.needsDiscernment`, `.blocked`) should be stored on `BereanChatMsg` and shown as a micro-badge
- Proposed: a single SF Symbol chip (`checkmark.shield` / `exclamationmark.shield`) in the message footer, tapping to show the alignment detail
- This makes the silent rewrite behavior auditable

**3b. Show active memory scope in BereanMemoryChip**
- Chip label should reflect scope: "Memory · All sessions" vs "Memory · This chat" vs "Memory off"
- Target: `BereanMemoryChip.swift` L130–145

**3c. Add "verified" / "source" provenance for citation chips**
- `ScriptureCitationRow` and `AmenTranslationComparisonInline` already surface scripture references from response text
- Wire to BereanAnswerEngine's `hasCitations` flag to differentiate regex-detected references (unverified) from engine-confirmed citations (verified) with a visual distinction

### Priority 4 — Live Activity Integration

**4a. Tie Live Activity to BereanChatViewModel streaming**
- `BereanLiveActivityManager.startLiveActivity()` / `updateActivity()` / `endActivity()` should be called from `BereanChatViewModel.send()` and its completion/cancel paths
- Currently the main chat session has zero Live Activity coverage — only the post-card quick-trigger path does
- Target: `AMENAPP/BereanChatView.swift` ViewModel `send()` method (around L304)
