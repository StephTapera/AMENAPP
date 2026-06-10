# AIL_AUDIT.md — Phase 0 Read-Only Audit

**Accessibility Intelligence Layer (AIL)**
Lead Orchestrator audit · date 2026-06-09 · branch target `feature/ail` (not yet created)
Status: **BLOCKING CHECKPOINT — awaiting confirmation before Phase 1.**

This audit maps the real repo against the build prompt's assumptions. **Several core assumptions in the prompt do not match the codebase.** Those are escalated in §0 as P0 *contract-drift* items because they change the Phase 1 contract freeze. Everything else (surfaces, provenance, moderation, crisis, media, flags) is mapped and largely ready.

---

## 0 · P0 ESCALATIONS — read these first (they block Phase 1)

The prompt describes an architecture that **does not exist in this form**. I did not adapt around these silently; per the iron rules I'm stopping to surface the tradeoff.

| # | Prompt assumes | Repo reality | Impact on plan |
|---|---|---|---|
| **P0-1** | "three engines (Intent, Visual, Knowledge) on a shared **ContextGraph**" | **No such engines, no ContextGraph.** Architecture is a single centralized router `callModel({task, input, systemPrompt, context, userId, safetyLevel, featureFlags, namespace, queryVector})` at `functions/router/callModel.js`. "Engines" are task-routed feature modules under `functions/intelligence/`, `functions/selah/`, etc. | `describe_image: {engine:'visual'}` and `summarize_audio:{engine:'knowledge'}` in the routing delta have **no engine to bind to.** They must become `callModel` *tasks* (e.g. `task:'describe_image'`) routed to a vision-capable provider. Decision needed. |
| **P0-2** | Routing config is **`amen.routing.config.ts`** | Real file is **`functions/router/amenRouting.config.js`** (JS, not TS). Shape: `ROUTING[task] = {primary, chain[], fail, inputGuard, outputGuard, retrieval, requireCitations, degradeResult, ...}`. `PROVIDERS` map defines `claude/claudeFast/openai/gemini/nvidia/pinecone/algolia`. | The "config delta" must be authored in **JS against the real schema**, not the idealized TS block in §3.3. `fallover:'NONE'` → real equivalent is `fail:'fail_closed', chain:['claude']` with no other providers. |
| **P0-3** | Contracts live at **`src/contracts/ail.contracts.ts`** | **No `src/contracts/` dir exists.** Contracts live at `functions/selah/selah.contracts.ts` and `functions/intelligence/contracts.js`. | A1 should place `ail.contracts.ts` next to `selah.contracts.ts` (i.e. `functions/<area>/ail.contracts.ts`) to match the established pattern. Path decision needed. |
| **P0-4** | A2 owns **`functions/ail/**` in the `v2functions.js` namespace** | Gen2 split is real but the file is **`functions/v2functions.js` + `functions/v2entry.js`** (aggregator), deployed via `firebase.json` predeploy copy to `functions/v2triggers`. Callables today live gen1 in `functions/index.js`. | New `functions/ail/` is fine, but it must be **wired into `index.js` (gen1 callable) or `v2entry.js` (gen2)** — the prompt's "v2functions.js namespace" is imprecise. `ailTransform` as a **callable** belongs in the gen1 `index.js` export set, like `checkContentSafety`. |
| **P0-5** | Canonical **`Provenance` enum** to map `A11yProvenance` into | **Two unrelated provenance systems exist**, neither matching `{ai_generated, ai_human_edited, human}`: (a) Swift `ONEProvenanceClass {captured, edited, aiAssisted, synthetic, unknown}`; (b) backend `provenanceFunctions.js` sourceType `{device_camera…ai_generated, ai_assisted, unknown}`. Both are about **media capture**, not text-transform authorship. | There is **no existing text-transform provenance to map into.** `A11yProvenance` is effectively net-new. Decision: keep AIL's own 3-case enum (recommended — media provenance is a different concern) and document that it does **not** fold into `ONEProvenanceClass`. |
| **P0-6** | C13 Calm Mode / Reading Level / Translate are new | **Large overlap already shipped.** `AMENFeatureFlags.swift` already has a **"System 15: Accessibility Intelligence Layer"** block (15 flags incl. `accessibilityIntelligenceEnabled`, `readabilityLayerEnabled`, `meaningAwareTranslationEnabled`, `naturalModeEnabled`). `AmenSimpleModeService` (Calm-Mode-like), `LiveCaptionOverlay`, `AmenLiveCaptionsOverlay`, `BereanLiveTranslationBar`, `PostTranslationService`, `CommentTranslationBridge`, `AmenCaptionEditorView`, `PerMediaCaptionComposer` all exist. | **High duplication risk.** AIL must *reuse/extend* these, not rebuild. A3/A4/A5 ownership must be re-scoped to "extend existing services," and the new flags reconciled with the existing System-15 block instead of adding parallel flags. |

**My recommendation (bias = fail-open accessibility, reuse over rebuild):** keep the AIL *contracts* (`A11yTask`, `ReadingLevel`, `A11yProfile`, `A11yTransformResult`) as written — they're sound — but rewrite §3.3's routing/engine bindings to the **real `callModel` task model**, place files at the **real paths**, and re-scope Phase 2 agents to **extend** the existing accessibility/translation/caption services rather than create parallel ones. I need your sign-off on P0-1, P0-3, and P0-6 specifically before A1 freezes contracts.

---

## 1 · AI / model-routing layer (the thing AIL routes through)

- **Entry point:** `functions/router/callModel.js` → `async function callModel({task, input, systemPrompt, context, userId, safetyLevel='standard', featureFlags={}, namespace, queryVector})`.
  - Returns one of: `{output, provider, task, latencyMs}` (ok) · `{output:null, blocked:true, reason}` (blocked) · `{output, degraded:true, task}` (degraded).
  - Provider chosen purely by `ROUTING[task]` lookup → `dispatchProvider(providerKey, {systemPrompt, userMessage})`. **No provider names in feature code** (matches iron rule 12).
- **Routing config:** `functions/router/amenRouting.config.js` (332 lines). Per-task: `primary, chain[], fail('fail_closed'|'failover'|'degrade'), inputGuard, outputGuard, retrieval('pinecone'), requireCitations, degradeResult, safetyLevel, retryConfig, humanGate`.
- **Claude-only / cite-or-refuse precedent already exists:** `berean_answer: {primary:'claude', chain:['claude'], fail:'fail_closed', inputGuard:true, outputGuard:true, retrieval:'pinecone', requireCitations:true}`. AIL's `explain_scripture` should mirror this exactly.
- **Provider map (`PROVIDERS`):** `claude`(opus-4-7), `claudeFast`(sonnet-4-6), `openai`(gpt-4o), `gemini`(2.0-flash), `nvidia`(nemoguard content-safety), `pinecone`, `algolia`.
- **Secrets:** `defineSecret('ANTHROPIC_API_KEY' / 'NVIDIA_API_KEY' / 'PINECONE_API_KEY' …)` + lazy `getSecret()` in `functions/mlClients.js`. **No client-side secrets found in audited paths.** ✅ (matches iron rule 12.)
- **Adapter pattern precedent:** `functions/selah/bibleProviderAdapter.js` — `getVerses(reference, translation)` interface across `BibleApiProvider`/`BollsLifeProvider`/`CompositeOpenLicenseProvider`, with hard `assertOpenTranslationJS()` throwing for anything outside **BSB/WEB/KJV**. **This is the exact pattern for the new `SpeechProvider`, and the exact enforcement point for iron rule 2.**
- **Gen1/Gen2 split:** gen1 callables in `functions/index.js`; gen2 triggers in `functions/v2functions.js` aggregated by `functions/v2entry.js`, deployed via `firebase.json` predeploy copy to `functions/v2triggers`.

**Engines/ContextGraph:** ❌ not present (see P0-1). `context` is a plain per-call object `{userId, churchIds, seasonOfLife, …}`; durable state is Firestore + Pinecone namespaces, not a graph.

---

## 2 · Provenance, moderation, crisis (the things AIL must not break)

### Provenance
- Swift: `ONEProvenanceClass {captured, edited, aiAssisted, synthetic, unknown}` (+ `ONEProvenanceLabel` w/ C2PA). Media-capture oriented.
- Backend: `functions/provenanceFunctions.js` server-derives `syntheticMediaStatus` + `authenticityConfidence` from `sourceType`+`aiEvents`; client cannot forge. Collections `provenance/{postId}_{mediaId}`, `aiDisclosures/{docId}`. UI: `ProvenanceTrustPanel.swift`.
- **Neither models text-transform authorship → `A11yProvenance` is net-new (P0-5).**

### Moderation (FAIL-CLOSED — AIL must never weaken)
- **Gateway:** `functions/moderationGateway.js` → callable `checkContentSafety` (NVIDIA NeMo Guard). 30 checks/user/60s. Decisions `allow|warn|block|review`. **On API error → `review` (fails closed).** Valid types `{post, comment, message, dm}`.
- Swift client `ModerationGatewayService.check(content, contentType, contextId)`; 8s timeout → `review`; `canProceed = allow||warn`.
- Publish gates: `postAndCommentFunctions.js` — `finalizePostPublish` blocks if `moderation.status==='blocked'`; `addComment` requires fresh `commentModerationDecisions/{uid}_{clientCommentId}` (<10 min), hard-throws on `block`.
- Richer Swift pipeline `ModerationPipeline.evaluate(text,context,userId)` with `ModerationContext` incl. `directMessage, churchNote, prayerRequest`; actions `allow…blockImmediate`; audit → `safetyAuditLog/{uid}/events`, queue → `moderationQueue`.

### Moderation-bypass risk for AIL mount points (P0 flag from prompt §2)
- `Backend/functions/src/transformContent.ts` and `refineTranslation.ts` are callables that **return transformed text directly with NO moderation pre-gate.** Today that's acceptable because output is *display-only* and any repost re-enters the normal gate.
- **AIL rule (carry into A2 contract):** AIL transforms are **display-only and never auto-persist as user content.** If any AIL output ever becomes publishable content, it MUST route `ModerationGatewayService.check()` first. A8 must grep-verify no AIL path writes transformed text into `posts/`, `comments/`, `messages/`.
- Smart replies precedent (`SmartReplySuggestionService`) already guards via `ThinkFirstGuardrailsService` + skips generation for minors — good model for C8/C10/C11.

### Crisis (bypasses caps; never hard-blocks)
- `CrisisDetectionService.swift`: synchronous local keyword check (≤100ms) → `hasLocalCrisisSignal`; types suicide/selfHarm/abuse/DV/…; resources 988/741741/etc. Self-harm content is **allowed but routed to resources**, never hard-blocked. `moderationGateway.js` `escalateSelfHarm()` sets `crisisEscalated:true`, still returns `allow|warn`.
- **AIL contract:** crisis context must bypass all AIL caps/throttle (iron rule 3); C12 emotional-safety filter must **never blur crisis-help content** (iron rule in A6). A8 simulates capped-user-in-crisis → all AIL still functions.

### Tier-gating (AIL must contain ZERO user-facing tier checks)
- `AmenAccountTier {free, amenPlus, amenPro, creatorPro, churchPro, enterprise}` gates *features* (AI Writing Coach ≥ amenPlus, live ≥ creatorPro, …). **Moderation is tier-agnostic.**
- Rate limits: `Backend/functions/src/rateLimit.ts` (AI 20/min, 200/day; suggest 10/min, 100/day) — Firestore-transaction counters, `resource-exhausted` on exceed.
- **AIL rule:** no `AmenAccountTier`/`CapabilityTier`/`bereanCapabilityTier` reads in any AIL path except cost-throttle batch precompute that **never denies a user**. A8 greps for this (must be zero).

---

## 3 · Surfaces inventory (where AIL mounts) — all 9 found

> Note: repo has deeply nested duplicate-looking dirs (`AMENAPP/AMENAPP/AMENAPP/…`); paths below are the real ones found.

| Surface | Primary file(s) | Mount point |
|---|---|---|
| **Posts** | `AMENAPP/PostDetailView.swift`, compose `AMENAPP/CreatePostView.swift`, feed `AMENAPP/PostsSearchView.swift` | under-text translate pill / pre-publish / per-card |
| **Comments** | list+input in `PostDetailView.swift`; cell `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerCommentRowView.swift`; notes `…/ChurchNotes/Views/ChurchNoteCommentsView.swift` | intent picker beside send; per-cell translate/tone |
| **DMs** | `AMENAPP/BereanChatView.swift` (+ `UnifiedChatView`, `MentorshipChatView`); bubble `VergeMessageBubbleView.swift`; composer `…/ONE/People/Views/ONEMessageComposerView.swift`; list `MessagesView.swift` | bubble translate; composer care-check. **DM transforms NEVER cached server-side (contract §3.2).** |
| **Spaces** | hub `…/ConnectSpaces/AmenConnectSpacesHubView.swift`; detail `…/ConnectSpaces/AmenSpaceDetailView.swift`; discovery `AMENAPP/AmenSpaceDiscoveryView.swift` | header / feed item |
| **Rooms** | live `…/ConnectSpaces/Live/AmenLiveRoomShellView.swift` (**already mounts `AmenLiveCaptionsOverlay`**); prayer `…/CommunityOS/Prayer/PrayerRoomView.swift`, `AIIntelligence/BereanPrayerRoomView.swift` | extend existing captions overlay (do not rebuild) |
| **Church Notes** | editor `AMENAPP/ChurchNotes/Views/ChurchNotesExpressiveEditorScreen.swift`; viewer `…/ChurchNotes/Views/NoteShareViewerView.swift` | toolbar / share metadata |
| **Videos** | player `AMENAPP/MediaPlayerView.swift`; detail `…/AmenMediaDetailView.swift`; session `…/AmenMediaSessionView.swift`; hub `AMENAPP/Media/AmenMediaTabView.swift` | controls overlay / summary card below player |
| **Voice Notes** | recorder `AMENAPP/StudioVoiceRecorderView.swift`; playback `AMENAPP/VoiceMessageComponents.swift` | transcript toggle / playback controls |
| **Notifications** | list `…/AMENNotificationsView.swift`; card `…/Notifications/Views/AmenNotificationCard.swift` (+ `+Accessibility.swift`); toast `AmenToast.swift`; coordinator `…/Notifications/Engine/NotificationCoordinator.swift` | C14 re-entry hooks into `NotificationCoordinator.fire()` / post-dismiss |

### Existing accessibility infra to REUSE (do not duplicate — see P0-6)
- **Calm/Simple Mode:** `…/Accessibility/AmenSimpleModeService.swift` (`isSimpleModeActive`, `fontScale`, `useHighContrast`, Firestore-synced) + `AmenSimpleModeView/SettingsSection`. → **C13 should extend this, not add a parallel Calm Mode.**
- **Captions:** `AIIntelligence/LiveCaptionOverlay.swift` + `…/ConnectSpaces/Live/AmenLiveCaptionsOverlay.swift` (both already respect Reduce Motion / Reduce Transparency, glass fallback). Editing: `AmenCaptionEditorView.swift`, `PerMediaCaptionComposer.swift`, `AmenSyncCaptionService.swift`. → **C4 extends these.**
- **Translation:** `BereanLiveTranslationBar.swift`, `LiquidGlassTranslationCapsule.swift`, `PostTranslationService.swift`, `CommentTranslationBridge.swift`, `BereanContextualTranslationEngine.swift`, `PrayerRoomTranslationService.swift`, models `TranslationModels.swift`. Prefs persisted at `translationPreferences/{userId}`. → **C1 extends these.**

### Engagement counters C14 must NOT inherit (iron rule 10)
- `…/ChurchNotes/Views/ChurchNoteCommentCountBadge.swift` (open+total counts).
- Unread counts in `MessagesView` / `BereanChatView`; `SmartNotificationService`, `ReEngagementNotificationService` badges.
- → C14 stays qualitative ("Sarah answered your question"), no integers.

---

## 4 · Infra: i18n, media, speech, notifications, rules, flags

- **i18n:** legacy `.strings` (`en.lproj`, `es.lproj`), `NSLocalizedString`. **No `.xcstrings`.** Locale via `Locale.current`/`autoupdatingCurrent`; script-based detection in `BereanLanguageDetectionService`. Translation CF `translateMultilingualContent({text, sourceLanguage, targetLanguage, contentType, sourceId, visibility})`.
- **Media storage paths:** images/videos/audio under `posts/{userId}/{mediaType}/…` (`CloudStorageService`); DM video `chat_videos/{conversationId}/…` (`VideoAttachmentHandler`); sermons `sermons/{uid}/{sessionId}.m4a` (`ChurchNotesSermonCaptureService`). EXIF stripped, 1yr cache.
- **Captions today stored INLINE in Firestore**, not as VTT/SRT artifacts: `validateMediaCaptions.ts` → `posts/{postId}/mediaMeta/{mediaId}` `{caption, altText, scriptureRefs, captionModerationStatus}`. **Contract §3.2 proposes new `captions/{mediaId}` collection — confirm we add it vs extend `mediaMeta` (decision for A1/A4).**
- **Speech/ASR:** `SFSpeechRecognizer` (Berean toolbar, sermon capture, voice devotional) + OpenAI Whisper actor `WhisperVoiceService` (5-min/day cap, on-device SFSpeech fallback, consent in UserDefaults). → **`SpeechProvider` adapter wraps: on-device SFSpeech for `caption_live`, server ASR for `caption_recorded`.**
- **Notifications:** `NotificationCoordinator` (@MainActor, single `activeCard`, auto-dismiss, undo window). No re-entry summary hook exists yet → C14 injects here.
- **Firestore rules:** `firestore.rules`. User settings subcollections pattern: `users/{uid}/private|usage|safety|trust/…` mostly **owner-read / CF-write**, with `premiumFieldsUnchanged()`, `ageTierUnchanged()` validators. → A7's `users/{uid}/settings/a11yProfile` rule must be **owner read/write** but with **schema validation denying forbidden fields** (no motor metrics) — follows existing validator style.
- **Feature flags:** `AMENFeatureFlags.swift` (@MainActor singleton, Remote Config + safe local defaults; most default `true`). **Already contains a 15-flag "System 15: Accessibility Intelligence Layer" block** (P0-6) plus Church Notes media flags. Server flags cached `system/serverFeatureFlags`. → reconcile AIL flags with System-15, don't add parallel set.

---

## 5 · Confirmed alignment with iron rules (no blockers found)

- ✅ No client-side secrets in audited AI paths (`defineSecret` + `getSecret`).
- ✅ Claude-only cite-or-refuse precedent (`berean_answer`) → reuse for `explain_scripture`.
- ✅ BSB/WEB/KJV-only enforcement already hard-asserted in `bibleProviderAdapter.js` → iron rule 2 enforcement point exists.
- ✅ Moderation fails closed; crisis routes to resources without hard-block → AIL just must not weaken these.
- ✅ Existing caption/translation overlays already honor Reduce Motion + Reduce Transparency → iron rule 9 precedent.
- ✅ Adapter pattern exists for `SpeechProvider`.

## 6 · Open decisions I need from you before Phase 1 (A1 contract freeze)

1. **P0-1 engine bindings:** convert `describe_image`/`summarize_audio` from non-existent "engines" to `callModel` **tasks** routed to a vision/long-context provider? (Recommended.)
2. **P0-2/P0-3 paths:** author config delta in real **`amenRouting.config.js`**, and place **`ail.contracts.ts` under `functions/`** beside `selah.contracts.ts`? (Recommended.)
3. **P0-5 provenance:** keep `A11yProvenance` as standalone 3-case (no fold into `ONEProvenanceClass`)? (Recommended.)
4. **P0-6 reuse mandate:** re-scope Phase 2 A3/A4/A5 to **extend** existing SimpleMode/Caption/Translation services and reconcile with the existing System-15 flags, rather than build parallel stacks? (Strongly recommended — otherwise we ship duplicate accessibility systems.)
5. **Captions storage:** new `captions/{mediaId}` collection vs extend existing `posts/{postId}/mediaMeta/{mediaId}`?
6. **Branch:** create `feature/ail` now? (No code yet written; Phase 0 is read-only.)

**Nothing has been written except this file. Awaiting your confirmation to proceed to Phase 1.**
