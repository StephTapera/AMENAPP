# AMEN — AI Capability Registry (Module C)

*Generated: 2026-06-16 | Branch: app-store-readiness-overnight*

---

## Trust Tier Model

| Tier | Name | Authority Level | Examples |
|------|------|-----------------|---------|
| T-0 | SYSTEM | Absolute — hardcoded invariants, cannot be overridden | CSAM block, COPPA floor, crisis hotline requirement |
| T-1 | ADMIN | Platform operator — enforced server-side | Moderation decisions, org verification, ban enforcement |
| T-2 | VERIFIED | Server-verified identity with entitlement claims | Authenticated uid + App Check token |
| T-3 | CONSENTED | T-2 + explicit user consent recorded server-side | consentCreatorAI Firestore record (not UserDefaults) |
| T-4 | GUEST | Unauthenticated or anonymous session | Read-only feed, public content |
| T-5 | MINOR | Age-verified minor account (COPPA-governed) | Youth Mode sessions, restricted DM surface |
| T-6 | PRIOR-AI-OUTPUT | Content produced by a prior AI step | Berean drafts, daily digest summaries |

---

## AI Surface Inventory & Capability Manifests

### Summary Table

| Surface | File | Mode | Context Classes | Actions | Streams | Memory Write | Minor Tier Allowed | Auth Required | App Check Required | Wiring Status |
|---------|------|------|-----------------|---------|---------|-------------|-------------------|--------------|-------------------|---------------|
| berean.pipelineClient | BereanPipelineClient.swift | Ask | PRIVATE, SENSITIVE | none | No | No | unknown | No | No | **Unsafe** |
| berean.coreService | BereanCoreService.swift | Ask | PUBLIC, PRIVATE, SENSITIVE | draft.post, send.prayer, dm.screen | No | No | unknown | No | No | **Unsafe** |
| selah.ask | AskSelahView.swift | Ask | PRIVATE, SENSITIVE | none | Yes | No | unknown | No | No | **Unsafe** |
| berean.roomFirst | BereanRoomFirstView.swift | Reflect | PUBLIC | none | No | No | unknown | No | No | Partial |
| berean.roomFirstService | BereanRoomFirstService.swift | Reflect | PRIVATE | none | No | No | unknown | No | No | **Unsafe** |
| berean.coCreatorInlineView | BereanCoCreatorInlineView.swift | Build | PRIVATE | draft.post | No | No | unknown | No | No | **Unsafe** |
| berean.coCreatorService | BereanCoCreatorService.swift | Build | PRIVATE | draft.post | No | No | unknown | No | No | **Dead** |
| berean.traditionAwareView | BereanTraditionAwareView.swift | Discern | PUBLIC | none | No | No | unknown | No | No | Partial |
| berean.traditionAwareProvider | BereanTraditionAwareProvider.swift | Discern | PUBLIC | none | No | No | unknown | No | No | **Dead** |
| feed.whyAmISeeingThis | WhyAmISeeingThisSheetV2.swift | Discern | PRIVATE | feed.hide | No | No | unknown | Yes | No | Partial |
| feed.explanationService | FeedExplanationService.swift | Discern | PRIVATE | feed.hide | No | No | unknown | Yes | No | Partial |
| berean.memoryView | BereanMemoryView.swift | Reflect | SENSITIVE | memory.delete, memory.lock | No | Yes | no | No | No | Partial |
| berean.personalContextProvider | BereanPersonalContextProvider.swift | Reflect | PRIVATE, SENSITIVE | none | No | No | restricted | Yes | No | Partial |
| safety.aegisC59Detector | AegisC59Detector.swift | Guard | SENSITIVE | none | No | No | yes | No | No | **Unsafe** |
| safety.youthModeService | YouthModeService.swift | Guard | SENSITIVE | none | No | Yes | yes | No | No | **Unsafe** |
| safety.youthModeFeedModifier | YouthModeFeedModifier.swift | Guard | PUBLIC | feed.filter | No | No | yes | No | No | FullyWired |
| prayer.chainAssemblyService | PrayerChainAssemblyService.swift | Build | PRIVATE, SENSITIVE | send.prayer | No | Yes | unknown | No | No | **Unsafe** |
| berean.groupNotebookService | BereanGroupNotebookService.swift | Build | PRIVATE, SENSITIVE | none | Yes | Yes | unknown | Yes | No | Partial |
| berean.groundingSheet | AmenDistinctives.swift | Discern | PUBLIC | none | No | No | unknown | No | No | **Dead** |
| berean.dailyOfficeView | AmenDistinctives.swift | Reflect | PUBLIC | none | No | No | unknown | No | No | **Dead** |
| berean.feedbackView | BereanFeedbackView.swift | Guard | SENSITIVE | report.submit | No | Yes | unknown | No | No | Partial |
| intelligence.prayerMatchView | PrayerMatchView.swift | Ask | PRIVATE, SENSITIVE | send.prayer | No | No | unknown | No | No | Partial |
| berean.realtimeSessionManager | BereanRealtimeSessionManager.swift | Ask | SENSITIVE | none | Yes | No | no | Yes | No | Partial |
| berean.voiceAssistantView | BereanVoiceAssistantView.swift | Ask | SENSITIVE | none | Yes | No | no | Yes | No | Partial |
| berean.studyService | BereanStudyService.swift | Discern | PUBLIC, PRIVATE | draft.churchNote | No | No | no | Yes | No | FullyWired |
| comment.smartCommentService | SmartCommentService.swift | Guard | PRIVATE | none | No | No | unknown | No | No | Partial |
| digest.dailyDigestService | DailyDigestService.swift | Reflect | PRIVATE | none | No | No | unknown | No | No | Partial |
| ai.reviewViewModel | AmenAIReviewViewModel.swift | Guard | PRIVATE | draft.post | No | No | unknown | No | No | Partial |
| safety.moderationProvider | AmenSafetyModerationProvider.swift | Guard | PRIVATE, SENSITIVE | none | No | No | yes | No | No | FullyWired |
| creator.aiFeatures | AmenAIFeaturesService.swift | Build | PRIVATE | draft.post | No | No | unknown | No | No | Partial |

---

### Per-Surface Capability Manifests

---

#### berean.pipelineClient

```
Surface:           berean.pipelineClient
File:              AMENAPP/AMENAPP/AIIntelligence/BereanPipelineClient.swift
Mode:              Ask
Context Classes:   PRIVATE, SENSITIVE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Unsafe
```

Critical Gaps:
1. No `Auth.auth().currentUser` check — uid is caller-supplied, not server-verified at entry point
2. Consent gate uses `UserDefaults "consentCreatorAI"` — not an authoritative server-side check; can be reset by clearing app data
3. No minor-tier gate — `AgeAssuranceService` never checked before calling `bereanPipeline` CF
4. No App Check enforcement on client side — relies entirely on CF-level enforcement
5. Kill switch is a Remote Config bool checked locally; if RC fetch fails, stale value may allow calls when flag should be false

---

#### berean.coreService

```
Surface:           berean.coreService
File:              AMENAPP/BereanCoreService.swift
Mode:              Ask
Context Classes:   PUBLIC, PRIVATE, SENSITIVE
Actions:           draft.post, send.prayer, dm.screen
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Unsafe
```

Critical Gaps:
1. `process()` has no `Auth.auth().currentUser` guard — any caller can invoke AI processing without an authenticated session
2. No consent check in `process()` — only `featureFlags.isEnabled()` is checked; consent gate must be enforced at this layer for surfaces that bypass `BereanPipelineClient`
3. No minor-tier gate at the routing layer — `crisisDetection` and `dmSafetyGate` are always enabled per `AIFeatureFlags`, but minors should still be excluded from certain categories
4. `userId` is optional and caller-supplied — no server-verified identity
5. No App Check enforcement — DM screening and prayer request screening run without attestation

---

#### selah.ask

```
Surface:           selah.ask
File:              AMENAPP/AskSelahView.swift
Mode:              Ask
Context Classes:   PRIVATE, SENSITIVE
Actions:           none
Streaming:         true
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Unsafe
```

Critical Gaps:
1. No explicit `Auth.auth().currentUser` check before initiating streaming session
2. No consent gate visible in this view — consent must be verified before calling `SelahService.shared.askSelah()`
3. No feature flag check visible — no kill switch protection
4. No minor-tier gate — `AgeAssuranceService` not consulted
5. Missing `accessibilityLabel` on input bar and send button
6. No AI-generated content disclosure label rendered in the UI

---

#### berean.roomFirst

```
Surface:           berean.roomFirst
File:              AMENAPP/AMENAPP/AIIntelligence/BereanRoomFirstView.swift
Mode:              Reflect
Context Classes:   PUBLIC
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. No error state rendered in the view — `BereanRoomFirstService` errors are silently dropped
2. No AI-generated content disclosure label
3. No minor-tier gate — `BereanRoomFirstService.fetchContribution()` not checked against `AgeAssuranceService`

---

#### berean.roomFirstService

```
Surface:           berean.roomFirstService
File:              AMENAPP/AMENAPP/AIIntelligence/BereanRoomFirstService.swift
Mode:              Reflect
Context Classes:   PRIVATE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Unsafe
```

Critical Gaps:
1. No `Auth.auth().currentUser` check before Firestore reads or CF calls
2. No minor-tier gate
3. No cancel support — long-running local synthesis cannot be interrupted

---

#### berean.coCreatorInlineView

```
Surface:           berean.coCreatorInlineView
File:              AMENAPP/AMENAPP/AIIntelligence/BereanCoCreatorInlineView.swift
Mode:              Build
Context Classes:   PRIVATE
Actions:           draft.post
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Unsafe
```

Critical Gaps:
1. `BereanCoCreatorService` returns hardcoded placeholder strings — constitutional pipeline is entirely bypassed
2. No consent gate in `BereanCoCreatorService` — `consentCreatorAI` never checked
3. No AI-generated content disclosure label in view
4. No minor-tier gate
5. Errors from service silently dropped with `try?` in toolbar button — blocked state never surfaced to user
6. No cancel while invoking — spinner shows but user cannot interrupt

---

#### berean.coCreatorService

```
Surface:           berean.coCreatorService
File:              AMENAPP/AMENAPP/AIIntelligence/BereanCoCreatorService.swift
Mode:              Build
Context Classes:   PRIVATE
Actions:           draft.post
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Dead
```

Critical Gaps:
1. Generates hardcoded static strings — no real LLM call is made; constitutional pipeline is bypassed entirely
2. No consent check — `consentCreatorAI` UserDefaults key never verified
3. No `Auth.auth()` check
4. No minor-tier gate
5. No structured error type — throws propagated to callers without context

---

#### berean.traditionAwareView

```
Surface:           berean.traditionAwareView
File:              AMENAPP/AMENAPP/AIIntelligence/BereanTraditionAwareView.swift
Mode:              Discern
Context Classes:   PUBLIC
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. No AI-generated content disclosure label
2. No minor-tier gate

---

#### berean.traditionAwareProvider

```
Surface:           berean.traditionAwareProvider
File:              AMENAPP/AMENAPP/AIIntelligence/BereanTraditionAwareProvider.swift
Mode:              Discern
Context Classes:   PUBLIC
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Dead
```

Critical Gaps:
1. Pure local keyword matching with hardcoded content — no LLM call wired
2. No consent check
3. No minor-tier gate

---

#### feed.whyAmISeeingThis

```
Surface:           feed.whyAmISeeingThis
File:              AMENAPP/AMENAPP/AIIntelligence/WhyAmISeeingThisSheetV2.swift
Mode:              Discern
Context Classes:   PRIVATE
Actions:           feed.hide
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     true
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No AI-generated content disclosure label on explanation rows
2. No consent gate for AI-generated explanations
3. No minor-tier gate
4. No cancel path on initial load — user cannot abort the `generateFeedExplanation` CF call

---

#### feed.explanationService

```
Surface:           feed.explanationService
File:              AMENAPP/AMENAPP/AIIntelligence/FeedExplanationService.swift
Mode:              Discern
Context Classes:   PRIVATE
Actions:           feed.hide
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     true
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No consent gate for AI processing of feed behavior data
2. No minor-tier gate
3. No cancel support — in-flight CF calls cannot be aborted

---

#### berean.memoryView

```
Surface:           berean.memoryView
File:              AMENAPP/AMENAPP/AIIntelligence/BereanMemoryView.swift
Mode:              Reflect
Context Classes:   SENSITIVE
Actions:           memory.delete, memory.lock
Streaming:         false
Memory Write:      true
Minor Tier Allowed: no
Auth Required:     false   [MISSING — relies on caller]
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. `userId` passed in from caller — no `Auth.auth()` check inside this view
2. No AI-generated content disclosure label on memory entries
3. No minor-tier gate enforced at this view level — minor check must come from caller

---

#### berean.personalContextProvider

```
Surface:           berean.personalContextProvider
File:              AMENAPP/AMENAPP/AIIntelligence/BereanPersonalContextProvider.swift
Mode:              Reflect
Context Classes:   PRIVATE, SENSITIVE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: restricted
Auth Required:     true
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No consent check — relies entirely on caller to enforce consent gate before invoking
2. Tier-P block is architectural but no explicit minor age check; only Tier P entitlement blocks access, not a COPPA-specific age gate

---

#### safety.aegisC59Detector

```
Surface:           safety.aegisC59Detector
File:              AMENAPP/AMENAPP/AIIntelligence/AegisC59Detector.swift
Mode:              Guard
Context Classes:   SENSITIVE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: yes
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Unsafe
```

Critical Gaps:
1. No `Auth.auth()` check before calling `detectAegisC59` CF — uid not sent in payload
2. C60 `checkYouthInteractionPolicy()` accepts `senderAge` and `recipientAge` as caller-supplied `Int?` — no server-authoritative age verification; COPPA bypass risk
3. No App Check enforcement on client CF call

---

#### safety.youthModeService

```
Surface:           safety.youthModeService
File:              AMENAPP/AMENAPP/AIIntelligence/YouthModeService.swift
Mode:              Guard
Context Classes:   SENSITIVE
Actions:           none
Streaming:         false
Memory Write:      true
Minor Tier Allowed: yes
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Unsafe
```

Critical Gaps:
1. `activate()` accepts a caller-supplied `birthYear` without verifying against a server identity claim — caller can pass any year to bypass youth restrictions
2. No `Auth.auth()` check inside `activate()` before writing to Firestore
3. `dmAllowed()` fallback allows DMs on network error — for a minor-adjacent safety gate, fail-closed would be more appropriate

---

#### safety.youthModeFeedModifier

```
Surface:           safety.youthModeFeedModifier
File:              AMENAPP/AMENAPP/AIIntelligence/YouthModeFeedModifier.swift
Mode:              Guard
Context Classes:   PUBLIC
Actions:           feed.filter
Streaming:         false
Memory Write:      false
Minor Tier Allowed: yes
Auth Required:     false
App Check Required: false
Wiring Status:     FullyWired
```

Critical Gaps: None

---

#### prayer.chainAssemblyService

```
Surface:           prayer.chainAssemblyService
File:              AMENAPP/AMENAPP/AIIntelligence/PrayerChainAssemblyService.swift
Mode:              Build
Context Classes:   PRIVATE, SENSITIVE
Actions:           send.prayer
Streaming:         false
Memory Write:      true
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Unsafe
```

Critical Gaps:
1. No `Auth.auth().currentUser` check before writing to Firestore or calling `assemblePrayerChain` CF
2. No consent gate
3. No minor-tier gate
4. No cancel support for in-flight chain assembly

---

#### berean.groupNotebookService

```
Surface:           berean.groupNotebookService
File:              AMENAPP/AMENAPP/AIIntelligence/BereanGroupNotebookService.swift
Mode:              Build
Context Classes:   PRIVATE, SENSITIVE
Actions:           none
Streaming:         true
Memory Write:      true
Minor Tier Allowed: unknown
Auth Required:     true
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No consent gate — group members whose messages are used for guide generation have not individually consented to AI processing of their content
2. No minor-tier gate — a group notebook session could include minor users whose content is sent to the LLM

---

#### berean.groundingSheet

```
Surface:           berean.groundingSheet
File:              AMENAPP/AMENAPP/AIIntelligence/AmenDistinctives.swift
Mode:              Discern
Context Classes:   PUBLIC
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Dead
```

Critical Gaps:
1. `startLocalPreview` is a hardcoded stub — no real LLM call is made; constitutional pipeline never invoked
2. `isStreaming` flag exists but the stream path is not wired to any real provider
3. No `Auth.auth()` check
4. No consent gate
5. No minor-tier gate
6. No feature flag kill switch visible in this file

---

#### berean.dailyOfficeView

```
Surface:           berean.dailyOfficeView
File:              AMENAPP/AMENAPP/AIIntelligence/AmenDistinctives.swift
Mode:              Reflect
Context Classes:   PUBLIC
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Dead
```

Critical Gaps:
1. `generatePreviewOffice` is a hardcoded local stub — no LLM call wired
2. No AI-generated content disclosure label
3. No `accessibilityLabel` on office body text or tradition picker
4. No consent gate
5. No minor-tier gate
6. No feature flag kill switch

---

#### berean.feedbackView

```
Surface:           berean.feedbackView
File:              AMENAPP/AMENAPP/AIIntelligence/BereanFeedbackView.swift
Mode:              Guard
Context Classes:   SENSITIVE
Actions:           report.submit
Streaming:         false
Memory Write:      true
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. `userId` falls back to `"anonymous"` string — no hard `Auth.auth()` guard; unauthenticated reports can be submitted
2. No minor-tier check before submitting safety reports — report data includes `userId` and feedback categories that could identify a minor

---

#### intelligence.prayerMatchView

```
Surface:           intelligence.prayerMatchView
File:              AMENAPP/Intelligence/PrayerMatchView.swift
Mode:              Ask
Context Classes:   PRIVATE, SENSITIVE
Actions:           send.prayer
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING — delegates to service]
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. No `Auth.auth()` check visible in view — delegates entirely to `EventPrayerNeedService`
2. No AI-generated content disclosure label
3. No consent gate visible
4. No feature flag kill switch visible in this view
5. No minor-tier gate
6. No cancel path on load

---

#### berean.realtimeSessionManager

```
Surface:           berean.realtimeSessionManager
File:              AMENAPP/AIIntelligence/BereanRealtimeSessionManager.swift
Mode:              Ask
Context Classes:   SENSITIVE
Actions:           none
Streaming:         true
Memory Write:      false
Minor Tier Allowed: no
Auth Required:     true
App Check Required: false  [MISSING — server enforces but client does not pre-verify]
Wiring Status:     Partial
```

Critical Gaps:
1. No explicit `Auth.auth().currentUser` guard before calling `createRealtimeSession` CF — relies on Firebase callable automatic token attachment, but no client-side hard check
2. No App Check enforcement on client side — server CF enforces it but client does not pre-verify
3. No consent gate for realtime voice AI session creation

---

#### berean.voiceAssistantView

```
Surface:           berean.voiceAssistantView
File:              AMENAPP/AIIntelligence/BereanVoiceAssistantView.swift
Mode:              Ask
Context Classes:   SENSITIVE
Actions:           none
Streaming:         true
Memory Write:      false
Minor Tier Allowed: no
Auth Required:     true
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. Minor gate is enforced via `BereanRealtimeSessionManager.createSession()` but the view itself has no redundant guard — a future refactor bypassing the manager could expose minors to voice AI
2. No AI-generated content disclosure label on response card
3. No consent gate visible in this view before session start
4. Feature flag check is present (`bereanVoiceAssistantEnabled`) but no kill switch for the underlying realtime session

---

#### berean.studyService

```
Surface:           berean.studyService
File:              AMENAPP/AIIntelligence/BereanStudyService.swift
Mode:              Discern
Context Classes:   PUBLIC, PRIVATE
Actions:           draft.churchNote
Streaming:         false
Memory Write:      false
Minor Tier Allowed: no
Auth Required:     true
App Check Required: false  [MISSING]
Wiring Status:     FullyWired
```

Critical Gaps:
1. No App Check enforcement — CF calls go through without client attestation
2. No consent gate — `consentCreatorAI` or equivalent UserDefaults key not checked before calling study CFs
3. Citation enforcement (Gate 3) only applies to exegetical types — `compareTranslations` is exempt; a fabricated cross-reference in a comparison response would not be caught

---

#### comment.smartCommentService

```
Surface:           comment.smartCommentService
File:              AMENAPP/AIIntelligence/SmartCommentService.swift
Mode:              Guard
Context Classes:   PRIVATE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No `Auth.auth().currentUser` guard before calling `callModelCommentCoach` CF — unauthenticated calls can be made if consent UserDefaults is set
2. No minor-tier gate — minors can invoke comment coaching
3. No App Check enforcement on client side
4. Client-side hourly rate limit uses UserDefaults — trivially bypassed by clearing app data or using multiple devices

---

#### digest.dailyDigestService

```
Surface:           digest.dailyDigestService
File:              AMENAPP/AIIntelligence/DailyDigestService.swift
Mode:              Reflect
Context Classes:   PRIVATE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No `Auth.auth().currentUser` guard before calling `callModelDailyBrief` CF
2. No minor-tier gate
3. No App Check enforcement on client side
4. `buildUserSummary()` sends `preferredBibleBook` from UserDefaults to Anthropic API without verifying it against a profile — a spoofed or injected UserDefaults value could influence LLM output

---

#### ai.reviewViewModel

```
Surface:           ai.reviewViewModel
File:              AMENAPP/AIIntelligence/AmenAIReviewViewModel.swift
Mode:              Guard
Context Classes:   PRIVATE
Actions:           draft.post
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false
App Check Required: false
Wiring Status:     Partial
```

Critical Gaps:
1. ViewModel is a pure state machine — no actual AI call is made here; wiring status depends entirely on its callers
2. No minor-tier gate at this layer
3. `approveDraft()` transitions to `.approved` with no server-side confirmation — callers must enforce that approval triggers a server round-trip before publish

---

#### safety.moderationProvider

```
Surface:           safety.moderationProvider
File:              AMENAPP/AIIntelligence/AmenSafetyModerationProvider.swift
Mode:              Guard
Context Classes:   PRIVATE, SENSITIVE
Actions:           none
Streaming:         false
Memory Write:      false
Minor Tier Allowed: yes
Auth Required:     false
App Check Required: false
Wiring Status:     FullyWired
```

Critical Gaps:
1. `isMediaScanningAvailable` hardcoded to `false` — CSAM scanning pipeline is intentionally not wired (HUMAN+LEGAL GATE per code comment); media uploads are not scanned until this gate is resolved
2. No `Auth.auth()` check before calling `checkContentSafety` CF — unauthenticated moderation calls possible if the coordinator is invoked before sign-in

---

#### creator.aiFeatures

```
Surface:           creator.aiFeatures
File:              AMENAPP/AIIntelligence/AmenAIFeaturesService.swift
Mode:              Build
Context Classes:   PRIVATE
Actions:           draft.post
Streaming:         false
Memory Write:      false
Minor Tier Allowed: unknown
Auth Required:     false   [MISSING]
App Check Required: false  [MISSING]
Wiring Status:     Partial
```

Critical Gaps:
1. No `Auth.auth().currentUser` guard before calling `generateCreatorDraft` or `ragSearch` CFs
2. No minor-tier gate — minors can invoke creator draft generation if they have the `consentCreatorAI` UserDefaults key set
3. No App Check enforcement on client side
4. Client-side rate limit uses UserDefaults — trivially bypassed by clearing app data
5. `ragSearch` with `churchNotes` or `savedVerses` scope sends personal content to Pinecone vector DB — no per-item PII minimization before embedding

---

## Action Safety Matrix

| Action | Allowed via AI? | Requires Confirm? | Requires Re-auth? | Requires Admin? | Server-authz? | Audit Log? | Undo? | Current Status |
|--------|----------------|-------------------|-------------------|-----------------|---------------|------------|-------|----------------|
| post (publish) | Yes (Build mode) | Yes — PrePostReviewSheet required | No | No | Required | Required | No (delete available) | PARTIAL — PrePostReviewSheet not wired in all paths |
| message (DM) | Yes (Guard — dm.screen) | No (screened inline) | No | No | Required | Required | No | PARTIAL — dm.screen action exists but BereanCoreService auth missing |
| follow | No | N/A | N/A | N/A | N/A | N/A | N/A | NOT AI-driven |
| block | No | N/A | N/A | N/A | N/A | N/A | N/A | NOT AI-driven |
| report | Yes (Guard — report.submit) | No | No | No | Required | Required | No | PARTIAL — BereanFeedbackView allows anonymous reports |
| payment | No | N/A | N/A | N/A | N/A | N/A | N/A | HUMAN+LEGAL GATE |
| subscription | No | N/A | N/A | N/A | N/A | N/A | N/A | HUMAN+LEGAL GATE |
| delete-account | No | N/A | Yes (required) | No | Required | Required | No (30-day grace) | NOT AI-driven |
| moderate | Yes (Admin only) | Yes | No | Yes | Required | Required | Yes (undo-ban) | PARTIAL — adminReviewPost callable wired; iOS pending UI |
| privacy-change | No | N/A | Yes (required) | No | Required | Required | Yes | NOT AI-driven |
| feed.hide | Yes (Discern mode) | No | No | No | Required | UNVERIFIED | No | PARTIAL — WhyAmISeeingThisSheetV2 wired but no audit log confirmed |
| feed.filter | Yes (Guard mode) | No | No | No | No (client-side) | No | N/A | FullyWired (YouthModeFeedModifier) |
| draft.post | Yes (Build mode) | Yes — AI review step | No | No | Required before publish | Required | Yes (discard) | PARTIAL — BereanCoCreatorService is Dead (hardcoded stubs) |
| send.prayer | Yes (Build mode) | No | No | No | Required | Required | UNVERIFIED | UNSAFE — PrayerChainAssemblyService missing auth |
| memory.delete | Yes (Reflect mode) | Yes | No | No | Required | Required | No | PARTIAL — BereanMemoryView auth relies on caller |
| memory.lock | Yes (Reflect mode) | Yes | No | No | Required | Required | No | PARTIAL — same as memory.delete |
| draft.churchNote | Yes (Discern mode) | No | No | No | Required | UNVERIFIED | Yes (discard) | FullyWired (BereanStudyService) |

---

## Per-Mode Safety Profiles (Berean 5 Modes)

| Mode | Context Classes Permitted | Actions Permitted | Streaming Allowed | Memory Write Allowed | Minor Tier Allowed |
|------|--------------------------|-------------------|-------------------|---------------------|-------------------|
| Ask | PRIVATE, SENSITIVE | none | Yes | No | No (default — must be explicitly gated per surface) |
| Discern | PUBLIC, PRIVATE | feed.hide, draft.churchNote | No | No | Restricted — PUBLIC context only unless minor gate present |
| Build | PRIVATE | draft.post, send.prayer, draft.churchNote | Yes (group notebook only) | Yes (chain assembly, group notebook) | No |
| Guard | PUBLIC, PRIVATE, SENSITIVE | feed.filter, report.submit | No | Yes (youth mode, feedback) | Yes (Guard is safe for minors where minorTierAllowed=yes) |
| Reflect | PUBLIC, PRIVATE, SENSITIVE | memory.delete, memory.lock | No | Yes (memory view) | Restricted — SENSITIVE context requires explicit minor=no gate |

Notes:
- "Ask" and "Build" modes must never be accessible to minor tiers without an explicit COPPA-compliant age gate.
- "Guard" mode surfaces are the primary safety layer for minor users and must fail-closed on network error.
- "Reflect" mode surfaces that touch SENSITIVE context (memory) must enforce `minorTierAllowed: no`.

---

## Wiring Status Summary

### FullyWired (3 surfaces)

All required gates present at the wired layer (auth, consent, minor check, kill switch, error state, loading state).

- `safety.youthModeFeedModifier` — YouthModeFeedModifier.swift
- `berean.studyService` — BereanStudyService.swift *(gaps: App Check + consent on client side)*
- `safety.moderationProvider` — AmenSafetyModerationProvider.swift *(gaps: CSAM HUMAN+LEGAL GATE, auth before CF)*

### Partial (15 surfaces)

Present: some gates. Missing: 1–3 critical gates.

- `berean.roomFirst` — BereanRoomFirstView.swift
- `berean.traditionAwareView` — BereanTraditionAwareView.swift
- `feed.whyAmISeeingThis` — WhyAmISeeingThisSheetV2.swift
- `feed.explanationService` — FeedExplanationService.swift
- `berean.memoryView` — BereanMemoryView.swift
- `berean.personalContextProvider` — BereanPersonalContextProvider.swift
- `berean.groupNotebookService` — BereanGroupNotebookService.swift
- `berean.feedbackView` — BereanFeedbackView.swift
- `intelligence.prayerMatchView` — PrayerMatchView.swift
- `berean.realtimeSessionManager` — BereanRealtimeSessionManager.swift
- `berean.voiceAssistantView` — BereanVoiceAssistantView.swift
- `comment.smartCommentService` — SmartCommentService.swift
- `digest.dailyDigestService` — DailyDigestService.swift
- `ai.reviewViewModel` — AmenAIReviewViewModel.swift
- `creator.aiFeatures` — AmenAIFeaturesService.swift

### Unsafe (9 surfaces)

Missing auth OR missing consent OR missing minor gate at a surface that handles PRIVATE/SENSITIVE context.

- `berean.pipelineClient` — BereanPipelineClient.swift
- `berean.coreService` — BereanCoreService.swift
- `selah.ask` — AskSelahView.swift
- `berean.roomFirstService` — BereanRoomFirstService.swift
- `berean.coCreatorInlineView` — BereanCoCreatorInlineView.swift
- `safety.aegisC59Detector` — AegisC59Detector.swift
- `safety.youthModeService` — YouthModeService.swift
- `prayer.chainAssemblyService` — PrayerChainAssemblyService.swift

### Dead (4 surfaces)

No real LLM call wired — hardcoded stubs or pure local keyword matching.

- `berean.coCreatorService` — BereanCoCreatorService.swift
- `berean.traditionAwareProvider` — BereanTraditionAwareProvider.swift
- `berean.groundingSheet` — AmenDistinctives.swift
- `berean.dailyOfficeView` — AmenDistinctives.swift

---

## GREEN Fixes Applied (this run)

The following files received targeted fixes in this sweep. Each fix count reflects discrete, auditable changes at that file.

| File | Fixes |
|------|-------|
| BereanContextCoordinator.swift | 1 |
| bereanChatProxy.ts | 6 |
| BereanCoreService.swift | 3 |
| conversationHistory.ts | 1 |
| BereanPulseActionRouter.swift | 1 |
| contextualActionRouter.ts | 1 |
| AmenAIFeaturesService.swift | 1 |
| bereanChatProxyStream.ts | 2 |
| systemPrompt.ts | 1 |
| PostAIUsage.swift | 1 |
| aiDisclosure.ts | 1 |
| sensitiveTopicPolicy.ts | 1 |
| callables.ts | 1 |
| BereanConstitutionalConfig.swift | 1 |
| YouthModeService.swift | 1 |

**Total GREEN fixes this run: 22**

---

## YELLOW & RED Items

YELLOW and RED items require human review before the relevant surface can be promoted to FullyWired or shipped in a production build. See `HUMAN_GATE_QUEUE.md` for full decision records.

### RED Items — Block App Store submission (22 total)

| ID | Surface | Issue |
|----|---------|-------|
| RED-001 | berean.pipelineClient | uid is caller-supplied — no server-verified identity at entry |
| RED-002 | berean.coreService | `process()` has no Auth guard — AI routing runs unauthenticated |
| RED-003 | selah.ask | No auth, no consent, no kill switch, no minor gate on streaming surface |
| RED-004 | berean.roomFirstService | No Auth check before Firestore reads |
| RED-005 | berean.coCreatorService | Dead — hardcoded stubs; constitutional pipeline bypassed |
| RED-006 | berean.groundingSheet | Dead — `startLocalPreview` is a stub; no auth, consent, or flags |
| RED-007 | berean.dailyOfficeView | Dead — `generatePreviewOffice` is a stub; ships as if functional |
| RED-008 | safety.aegisC59Detector | `checkYouthInteractionPolicy()` accepts caller-supplied ages — COPPA bypass |
| RED-009 | safety.youthModeService | `activate()` accepts caller-supplied birthYear; `dmAllowed()` fails open |
| RED-010 | prayer.chainAssemblyService | No auth before Firestore writes or CF calls |
| RED-011 | berean.feedbackView | `userId` falls back to `"anonymous"` — unauthenticated safety reports accepted |
| RED-012 | safety.moderationProvider | `isMediaScanningAvailable` hardcoded false — CSAM pipeline not wired (HUMAN+LEGAL GATE) |
| RED-013 | berean.traditionAwareProvider | Dead — pure local keyword matching presented as AI discernment |
| RED-014 | berean.coCreatorInlineView | Errors silently dropped with `try?`; no cancel path |
| RED-015 | comment.smartCommentService | Client-side rate limit via UserDefaults — trivially bypassable |
| RED-016 | creator.aiFeatures | No auth before `generateCreatorDraft`/`ragSearch`; PII sent to Pinecone unminimized |
| RED-017 | digest.dailyDigestService | `preferredBibleBook` from UserDefaults sent to LLM unverified — injection vector |
| RED-018 | berean.groupNotebookService | Group members have not individually consented to AI processing of their content |
| RED-019 | berean.pipelineClient | Consent gate via UserDefaults only — not authoritative; can be cleared |
| RED-020 | safety.youthModeService | `dmAllowed()` fails open on network error for minor-adjacent safety gate |
| RED-021 | berean.memoryView | `userId` passed in from caller — no internal Auth check on SENSITIVE memory writes |
| RED-022 | selah.ask | No AI-generated content disclosure label on a streaming SENSITIVE surface |

### YELLOW Items — Require human decision before GA (34 total)

| ID | Surface | Issue |
|----|---------|-------|
| YEL-001 | All surfaces | App Check not enforced client-side on any CF-calling surface (server enforces only) |
| YEL-002 | berean.studyService | No consent gate before study CFs despite FullyWired auth |
| YEL-003 | berean.studyService | `compareTranslations` exempt from citation enforcement — fabrication not caught |
| YEL-004 | feed.whyAmISeeingThis | No consent gate for AI processing of feed behavior data |
| YEL-005 | feed.explanationService | No consent gate for AI processing of feed behavior data |
| YEL-006 | berean.realtimeSessionManager | No consent gate before voice AI session creation |
| YEL-007 | berean.voiceAssistantView | View has no redundant minor guard — relies solely on manager |
| YEL-008 | berean.voiceAssistantView | No AI-generated content disclosure label on response card |
| YEL-009 | berean.roomFirst | No error state rendered — service errors silently dropped |
| YEL-010 | berean.roomFirst | No AI-generated content disclosure label |
| YEL-011 | berean.memoryView | No AI-generated content disclosure label on memory entries |
| YEL-012 | berean.personalContextProvider | No consent check — fully deferred to caller |
| YEL-013 | berean.personalContextProvider | Tier-P block is not a COPPA-specific age gate |
| YEL-014 | berean.realtimeSessionManager | No explicit client-side Auth guard before CF call |
| YEL-015 | intelligence.prayerMatchView | No AI-generated content disclosure label |
| YEL-016 | intelligence.prayerMatchView | No feature flag kill switch in view |
| YEL-017 | intelligence.prayerMatchView | No cancel path on load |
| YEL-018 | ai.reviewViewModel | `approveDraft()` requires no server round-trip before publish |
| YEL-019 | berean.coCreatorInlineView | No AI-generated content disclosure label |
| YEL-020 | berean.traditionAwareView | No AI-generated content disclosure label |
| YEL-021 | berean.traditionAwareView | No minor-tier gate |
| YEL-022 | berean.feedbackView | No minor-tier check before submitting reports with minor-identifying data |
| YEL-023 | comment.smartCommentService | No App Check enforcement |
| YEL-024 | digest.dailyDigestService | No App Check enforcement |
| YEL-025 | creator.aiFeatures | Client-side rate limit trivially bypassable via UserDefaults |
| YEL-026 | berean.groupNotebookService | No App Check enforcement |
| YEL-027 | berean.pipelineClient | Kill switch relies on stale Remote Config — no fail-closed on RC fetch failure |
| YEL-028 | selah.ask | No feature flag kill switch visible in AskSelahView.swift |
| YEL-029 | safety.moderationProvider | No Auth check before `checkContentSafety` CF |
| YEL-030 | prayer.chainAssemblyService | No cancel support for in-flight chain assembly |
| YEL-031 | berean.roomFirstService | No cancel support for long-running local synthesis |
| YEL-032 | berean.voiceAssistantView | No kill switch for the underlying realtime session |
| YEL-033 | berean.studyService | No App Check enforcement on CF calls |
| YEL-034 | All "unknown" minorTierAllowed surfaces | 18 surfaces have `minorTierAllowed: unknown` — requires explicit policy decision per surface before App Store submission |

---

*Registry last updated: 2026-06-16. Next review: before any App Store submission. Human gate decisions tracked in HUMAN_GATE_QUEUE.md.*
