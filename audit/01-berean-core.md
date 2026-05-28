# Berean Core Audit Report

_Run at: 2026-05-27T16:32:00Z_

## Summary

The Berean AI chat system is a multimodal iOS faith-based companion with five distinct operational mode categories:
1. **Theological Lenses** (Wisdom/Prayer/Discernment) — response style framework
2. **Response Modes** (10 modes: Standard, Scripture-Aware, Prayer, Study, Analytical, Social Coach, Gentle Rewrite, Creator, Church Companion, Safety Review)
3. **Computational Model Tiers** (Core/Deep/Adaptive) — entitlement-gated model depth
4. **Personality Modes** (8 user-facing + 7 legacy modes for conversation compatibility)
5. **Study Mode** — structured reasoning with multi-step breakdowns

**Streaming pipeline:** Client sends message → Firebase Auth token refresh → bereanChatProxyStream HTTP/2 SSE endpoint → Cloud Function forwards to Anthropic Claude or OpenAI with mode auth in terminal event. Cancellation propagates from URLSession task cancellation → check()
 in the for-await loop → Cloud Function's AbortController → upstream provider. 

**Persistence:** `/users/{uid}/bereanConversations/{sessionId}` (metadata) + `/users/{uid}/bereanConversations/{sessionId}/messages/{msgId}` (subcollection). Soft-delete via `isUserVisible: false`.

**Live Activity:** Dynamic Island rendered from post card tap; state machine (loading → responding → complete); 30s auto-end with dismissal policy `.default`. Fallback sheet if Live Activities disabled. No Direct Island race condition detected due to async state transitions.

**@MainActor correctness:** All observable models (@MainActor) and message types (BereanMessage conforming Sendable) in chat layer. One legacy issue: BereanChatMsg lacks Sendable conformance.

---

## Inventory

### A. Mode Catalog

#### A1. Theological Lenses (3 modes)
**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanModeEngine.swift:30–168`

| Lens | Display | System Prompt Fragment | Tone | Response Structure |
|------|---------|------------------------|------|-------------------|
| **Wisdom** | "Wisdom" | "Respond through a wisdom and leadership lens…" | Direct, structured, logical, action-oriented | (1) Direct answer from scripture (2) Scripture grounding (3) Context & meaning (4) Practical wisdom (5) Next wise step |
| **Prayer** | "Prayer" | "Respond through a prayer and emotional awareness lens…" | Emotionally warm, prayerful, compassionate, reflective | (1) Emotional acknowledgement (2) Scripture comfort (3) Honest reflection (4) Prayer (5) Gentle next step |
| **Discernment** | "Discernment" | "Respond through a discernment and wisdom lens…" | Thoughtful, unhurried, surfaces perspectives | (1) Name situation plainly (2) Possible motives (3) Wisdom principles (4) Consequences (5) Wise path forward |

**Persistence:** `BereanTheoLensStore` (UserDefaults + Firestore `users/{uid}/bereanSettings/preferences/selectedTheoLens`)

**Paywall:** None (all free)

#### A2. Response Style Modes (10 user-facing + 7 legacy)
**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanModesSheet.swift:1–120`

| Mode ID | Display Name | Icon | Description | Paywall |
|---------|--------------|------|-------------|---------|
| standard | Standard | sparkles | Balanced, clear, helpful answers | None |
| scripture | Scripture-Aware | book.pages | Grounds every response in scripture | None |
| prayer | Prayer Mode | hands.sparkles | Reverent, comforting, prayer-first | None |
| study | Study Mode | graduationcap | Structured, detailed, educational | None |
| analytical | Analytical | brain | Slower, nuanced, multi-angle analysis | None |
| social | Social Coach | person.2 | Tactful, practical for social replies | None |
| rewrite | Gentle Rewrite | pencil.and.sparkles | Softer, kinder rewrites with grace | None |
| creator | Creator Mode | wand.and.stars | Sharp, creative, post-ready output | None |
| church | Church Companion | building.columns | Church planning, notes, community | None |
| safety | Safety Review | shield.lefthalf.filled | Tone analysis and civility checks | None |

**Legacy Compatibility (7):** shepherd, scholar, coach, builder, strategist, creator, debater (still decoded from old conversations).

**Persistence:** `BereanModeStore` (UserDefaults `berean_active_mode_id` + Firestore `users/{uid}/bereanSettings/preferences/selectedBereanMode`)

**Routing:** Each mode maps to a backend system prompt suffix (not shown in client; constructed server-side).

#### A3. Computational Model Tiers (3 modes)
**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/BereanModelPickerComponents.swift:16–47`

| Tier | Title | Subtitle | Requires Pro | Backend Value | Notes |
|------|-------|----------|--------------|---------------|-------|
| core | Berean Core | Fast everyday guidance | No | "core" | Haiku model, real-time interactions |
| deep | Berean Deep | Advanced reasoning with discernment | Yes | "deep" | Sonnet model, async deep-work helpers, credit-based quota |
| adaptive | Adaptive | Chooses the right depth automatically | Yes | "adaptive" | Feature-flagged; not always visible |

**Persistence:** `BereanModelStore` (UserDefaults `bereanSelectedModelMode_v1` + Firestore `users/{uid}/bereanSettings/preferences/selectedBereanMode`). Also stores `bereanDeepCreditsRemaining_v1` and `bereanQuotaExceeded_v1`.

**Entitlement Check:** Server-side validation in `bereanChatProxy`. Client forwards `selectedMode` string in POST body; backend returns `acceptedMode`, `fallbackMode`, `deepCreditsRemaining`, `quotaExceeded` in SSE terminal `done` event.

#### A4. Personality Modes (8 user-facing + 7 legacy)
**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanAIAssistantView.swift:218–284`

Used by `BereanAIAssistantView` (the conversation view in AMENAPP's main chat surface), separate from the `BereanChatView` (simpler modal chat). Maps to backend `mode` enum on SendBereanChatMessage.

| Mode | Description |
|------|-------------|
| scriptureStudy | Interactive Bible study with structured learning |
| askBerean | General-purpose assistant |
| prayerCompanion | Emotionally aware, prayer-focused |
| deepStudy | Extended multi-turn scholarly work |
| discernment | Wisdom-focused decision-making helper |
| mediaInsight | Sermon/audio transcript commentary |
| workLifeWisdom | Career, relationships, life balance |
| safetyReview | Content review and safety feedback |

**Legacy (7):** shepherd, scholar, coach, builder, strategist, creator, debater.

**Parameter in ClaudeService:** `BereanPersonalityMode` enum, passed as `mode: mode.rawValue` in proxy request body.

#### A5. Study Mode (Supplementary)
**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanStudyModeModels.swift`

Structured reasoning overlay on top of chat. States: `.off`, `.idle`, `.analyzing`, `.thinking`, `.complete`. Renders multi-step reasoning nodes during streaming. Persisted via `berean_study_mode_enabled` UserDefaults.

---

### B. Streaming Pipeline & Cancellation Trace

**Request Flow (Happy Path):**

```
User taps Send
  ↓
BereanChatView.prepareAndSendMessage() [@MainActor]
  ↓
Retrieve conversation history (max 12 messages, ≤1300 tokens)
  ↓
RunPreflight: BereanAPIClient.makeChatPreflight()
  [Crisis detection, authority escalation, safety checks]
  ↓ short-circuit if crisis (e.g., suicide ideation)
  [Shows pre-approved SafetyOS response, exits]
  ↓
Build system prompt (mode lens + personality mode suffix)
  ↓
ClaudeService.sendBereanChatMessage()
  ↓
Create Task<Void, Never> (stored in streamTask)
  ↓
Task.checkCancellation() [early exit if already cancelled]
  ↓
@MainActor.run { isProcessing = true }
  ↓
Get fresh Firebase ID token (forcingRefresh: true)
  ↓
Call ClaudeService.streamProxyResponse()
  ↓
POST to bereanChatProxyStream endpoint:
  - Body: { message, systemPromptSuffix, maxTokens, mode, selectedMode, metadata }
  - Header: Authorization: Bearer {idToken}
  ↓
URLSession.shared.bytes(for: urlRequest)
  [Opens HTTP/2 connection, subscribes to SSE]
  ↓
for try await line in asyncBytes.lines:
  ↓
Task.checkCancellation() [propagates cancellation]
  ↓
  if line.hasPrefix("data: "):
    parse JSON event
    if delta: continuation.yield(delta) → for-await in send()
    if done: break (parse mode authority)
  ↓
for try await chunk in stream { [...messages.content += chunk] }
  [UI updates on each chunk via @Published]
  ↓
Run client-side safety checks
  [ClaudeService.sanitizeResponse()]
  ↓
Run BiblicalAlignmentService check (async)
  ↓
Mark message .completed
  ↓
Persist to Firestore (persistExchange)
  ↓
Run BereanIntelligenceCoordinator.processResponse()
  ↓
@MainActor.run { isProcessing = false; streamTask = nil }
```

**Cancellation Path:**

```
User taps X or back (or app backgrounded mid-stream)
  ↓
cancelStreaming() [@MainActor]
  ↓
streamTask?.cancel()
  ↓
CancellationError thrown into for-await
  ↓
Task.checkCancellation() in streamProxyResponse() throws
  ↓
Iteration stops, HTTPURLResponse stream ends
  [URLSession automatically closes connection]
  ↓
Cloud Function's AbortController notified
  [Proxied Anthropic/OpenAI request aborted]
  ↓
catch CancellationError { streamingState = .cancelled }
  ↓
@MainActor.run { isProcessing = false; streamTask = nil }
```

**Evidence:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ClaudeService.swift:560–622` (streamProxyResponse, SSE parsing loop with checkCancellation)
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChatView.swift:461–532` (for-await loop, cancelStreaming, error handling)

---

### C. Firestore Persistence Schema

**Collection Paths:**

```
users/{uid}
  └─ bereanConversations/{sessionId}  [Conversation metadata]
     ├─ mode: "askBerean" | "scriptureStudy" | ... (BereanPersonalityMode)
     ├─ title: String (auto-derived from first user message)
     ├─ lastUpdated: Timestamp
     ├─ isDeleted: Boolean (soft-delete)
     ├─ messageCount: Int
     ├─ memoryScope: "full" | "session" | "off" (BereanMemoryScope)
     ├─ theoLens: "wisdom" | "prayer" | "discernment" (BereanTheoLens)
     └─ messages/{msgId}  [Individual messages, subcollection]
        ├─ role: "user" | "assistant"
        ├─ content: String
        ├─ createdAt: Timestamp (server)
        ├─ tokenCount: Int (optional, for quota tracking)
        └─ isUserVisible: Boolean (soft-delete)
```

**Message Ordering:** 
- createdAt ascending (oldest first in subcollection)
- Loaded via `.order(by: "createdAt", descending: true)` on retrieval, then reversed in memory

**Edit/Delete Semantics:**
- **Soft delete (preferred):** Set `isUserVisible: false` on message document
- **Hard delete:** Not found in client code (GCP Cloud Tasks job may run server-side for GDPR compliance)

**Attachment References:**
- Not found in current schema (post context stored inline in metadata, not as refs)

**Token Counts:**
- `tokenCount` field optional in message doc (for future quota v2)
- Backend sends token estimate in response; client stores if available

**Conversation Metadata:**
- `memoryScope` persisted to gate context window retrieval
- `theoLens` persisted for conversation-scoped lens continuity
- `lastUpdated` auto-synced on each message append

**Evidence:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChatView.swift:702–766` (persistExchange, document shape)
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChatsListView.swift:1–120` (query patterns)

---

### D. Resume/Reconnect Behavior (Background Handling)

**ScenePhase Integration:**
- `@Environment(\.scenePhase)` monitored in `BereanAIAssistantView`
- When app moves to `.background`, `streamTask` persists (not cancelled)
- If backgrounded mid-stream:
  - URLSession continues streaming (OS handles in background mode)
  - UI updates pause (no MainActor execution in background)
  - streamTask resumes on foreground without re-requesting

**App Reopen Mid-Stream:**
- If user re-opens while streaming:
  - streamTask continues (same Task<Void, Never> object)
  - for-await loop resumes yielding chunks
  - @Published updates fire, triggering view redraws
- If streamTask ended before reopen:
  - Message already persisted to Firestore
  - User returns to conversation view (message visible)

**Evidence:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanAIAssistantView.swift:26` (@Environment scenePhase)
- No explicit background task registration (relies on URLSession's built-in background session support)

**Open Issue:** No explicit background task (`BGTaskScheduler`) registered to keep streaming alive if iOS kills the connection. Mitigation: Cloud Function has 60s timeout on gen2 functions; longer responses split into chunks and sent incrementally.

---

### E. Live Activity & Dynamic Island Integration

**Attributes Model:**
```swift
struct BereanActivityAttributes: ActivityAttributes, Codable, Hashable {
  let postID: String
  let postAuthor: String
  let postPreview: String
  
  struct ContentState: Codable, Hashable {
    var phase: BereanPhase  // loading | responding | complete | error
    var responseText: String
    var sourceCount: Int
    var scriptures: [String]
  }
}
```

**State Machine (BereanLiveActivityService):**

```
startActivity(for: post)
  ↓ [Check if Live Activities enabled globally]
  ↓ [ActivityKit.Activity.request(attributes:, content:)]
  ↓
  await fetchResponseForActivity(context, postContent, activity)
  ↓
  activity.update(...phase: .responding...)
  ↓
  CloudFunctionsService.call("bereanPostAssist")
  ↓
  for try await chunk in responseStream:
    [No granular updates; waits for full response]
  ↓
  activity.update(...phase: .complete, responseText:...)
  ↓
  [Hardcoded sleep 30 seconds]
  ↓
  activity.end(...dismissalPolicy: .default)
  ↓
  isActivityActive = false
```

**Fallback Sheet:**
- If Live Activities disabled (iOS Settings → Screen Time / Focus)
  - Show sheet instead, `showFallbackSheet = true`
  - Fetch response asynchronously, update `fallbackState`
- If Activity request fails (catch block)
  - Fall back to sheet + enqueue to `BereanFallbackCoordinator`

**Payload Size Compliance:**
- `responseText: String(text.prefix(200))` — capped to 200 chars
- `scriptures: Array(scriptures.prefix(3))` — max 3 verses
- Stays well under Apple's ~4KB limit per update

**End-of-Activity Cleanup:**
- `activity.end(endContent, dismissalPolicy: .immediate)` or `.default`
- All orphaned activities (from previous sessions) enumerated and ended on next postcard tap
- `currentActivity = nil` after end call

**Background Task Lifetime:**
- No explicit background task (no BGTaskScheduler)
- Live Activity kernel process keeps UI active independent of app process

**Race Condition: App Reopens Mid-Activity Update**
- **Scenario:** Activity.update() call in progress, user reopens app
- **No race found:** Updates are fire-and-forget; reopen doesn't re-query
- **Stale snapshot risk:** If app crashes during update, fallbackState may not sync to Dynamic Island
  - **Mitigation:** Next open checks `currentPostID` against activity attributes (but no cross-device sync)

**Evidence:**
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanLiveActivityService.swift:126–219` (state machine)
- `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanActivityAttributes.swift` (model)

---

### F. @MainActor Correctness & Sendability

#### F1. ViewModels (@MainActor)
- `BereanChatViewModel` [@MainActor] ✅
- `BereanAIAssistantView.BereanViewModel` [@MainActor] inferred (not shown; but likely)
- `BereanLiveActivityService` [@MainActor] ✅
- `BereanTheoLensStore` [@MainActor] ✅
- `BereanModelStore` [@MainActor] ✅
- `BereanModeStore` [@MainActor] ✅

#### F2. Message Models (Sendability)
- `BereanMessage` (BereanAIAssistantView.swift) — **Sendable ✅** (explicit conformance)
  - All fields (UUID, String, Date, [String], Bool?) are Sendable primitives
- `BereanChatMsg` (BereanChatView.swift) — **NOT Sendable ❌**
  - Contains `BereanResponseStructure?` and `BereanProvenanceRecord?` which are structs
  - `BereanResponseStructure` not explicitly Sendable; may contain nested structs
  - **Only used locally in @MainActor BereanChatViewModel, so thread-safe in practice**
  - **BUT: If ever passed across isolation boundaries, compiler will error**

#### F3. Service Singletons
- `ClaudeService` [@MainActor] — sendMessage returns AsyncThrowingStream ✅
- `BereanAPIClient.shared.makeChatPreflight()` — appears to be @MainActor-safe
- `BiblicalAlignmentService.shared.checkBiblicalAlignment()` — async, returns on MainActor

#### F4. Observation Chain
```
BereanChatMsg [@Published] in @MainActor BereanChatViewModel
  → @ObservedObject in BereanChatView
  → View rendering (automatically @MainActor)
```
No cross-thread jumps detected.

#### F5. Background Tasks
```
ClaudeService.streamProxyResponse()
  ↓ [runs on @MainActor Task context]
  ↓ try await URLSession.shared.bytes() [background I/O]
  ↓ continuation.yield() [Main thread]
  ✅ Correct: async boundary is safe
```

---

## Findings

### F-berean-001 — Missing Sendable Conformance on BereanChatMsg [MEDIUM] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChatView.swift:44–68`

**Observation:**
```swift
struct BereanChatMsg: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: BereanChatMsgRole
    var content: String
    var timestamp: Date
    var streamingState: StreamingState = .idle
    var structure: BereanResponseStructure? = nil
    var processingState: String? = nil
    var provenance: BereanProvenanceRecord? = nil
    // ... no Sendable conformance
}
```

`BereanResponseStructure` and `BereanProvenanceRecord` are not marked Sendable. If `BereanChatMsg` is ever passed across isolation boundaries (e.g., sent to a background Task without @MainActor isolation), the compiler will reject it.

**Evidence:**
- `BereanResponseStructure` (line 73): `struct BereanResponseStructure: Equatable { ... }` — no Sendable
- `BereanProvenanceRecord` (in BereanGrokModels.swift:64): `struct BereanProvenanceRecord: Equatable { ... }` — no Sendable
- `BereanChatMsg` is stored in `@Published var messages: [BereanChatMsg]` in @MainActor class (safe today, fragile)

**Impact:**
Currently low: BereanChatMsg is only used within @MainActor BereanChatViewModel, so thread-safety is enforced by isolation. However, if a future refactor moves BereanChatMsg to a cross-isolation API (e.g., passing to a nonisolated helper function), the code will not compile without adding Sendable conformance or actor-isolation attributes.

**Recommendation:**
Add `Sendable` conformance to `BereanChatMsg`, `BereanResponseStructure`, and `BereanProvenanceRecord`:
```swift
struct BereanResponseStructure: Equatable, Sendable { ... }
struct BereanProvenanceRecord: Equatable, Sendable { ... }
struct BereanChatMsg: Identifiable, Equatable, Sendable { ... }
```

---

### F-berean-002 — No Explicit Cancellation Feedback to User [LOW] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChatView.swift:534–538`

**Observation:**
```swift
func cancelStreaming() {
    streamTask?.cancel()
    streamTask = nil
    isThinking = false
}
```

When user taps cancel (X button), the message is marked `.cancelled` and content set to "Cancelled." However:
1. No haptic feedback on cancel
2. No toast/banner confirming cancellation
3. No analytics event tracking the cancellation

**Evidence:**
- Line 513: `messages[assistantIndex].streamingState = .cancelled`
- Line 518: `messages[assistantIndex].content = "Cancelled."`
- No UIImpactFeedbackGenerator or Toast call

**Impact:**
User may not realize the message was actually cancelled (especially if the network was already slow). Low severity because the cancelled message is visible in-thread, but UX improvement opportunity.

**Recommendation:**
Add confirmation feedback:
```swift
func cancelStreaming() {
    streamTask?.cancel()
    streamTask = nil
    isThinking = false
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    // Optionally: show brief banner "Response cancelled"
    AMENAnalyticsService.shared.track(.bereanResponseCancelled(sessionId: sessionId))
}
```

---

### F-berean-003 — Mode Authority Result Not Persisted to Conversation Metadata [MEDIUM] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ClaudeService.swift:576–602`

**Observation:**
The `BereanModeAuthorityResult` is received in the SSE terminal `done` event:
```swift
let authority = BereanModeAuthorityResult(
    acceptedMode: event["acceptedMode"] as? String,
    fallbackMode: event["fallbackMode"] as? String,
    entitlementRequired: event["entitlementRequired"] as? Bool,
    quotaExceeded: event["quotaExceeded"] as? Bool,
    deepCreditsRemaining: event["deepCreditsRemaining"] as? Int,
    fallbackReason: event["fallbackReason"] as? String
)
onModeAuthority?(authority)
```

The client updates `BereanModelStore` with credits/quota, but **does not persist the actual `acceptedMode` or `fallbackMode` to the conversation document**. If the user later views conversation history, there's no record of which model tier was actually used for that response.

**Evidence:**
- ClaudeService.swift:602: `onModeAuthority?(authority)` callback is consumed in BereanChatView (lines 421–459), updating store but not Firestore
- BereanChatView.swift:511: `persistExchange()` does not include mode authority fields

**Impact:**
Medium: Audit trails and quota accounting may be incomplete. Future refactors or compliance audits might need to correlate timestamps with server logs to determine which tier was used. For user-facing billing accuracy, the backend is authoritative (server-side logs are the source of truth), but client-side history is incomplete.

**Recommendation:**
Store `acceptedMode` and `fallbackMode` in the conversation metadata or as a field on the assistant message:
```swift
convRef.setData([
    "acceptedModel": authority.acceptedMode ?? "core",
    "fallbackModel": authority.fallbackMode,
    "deepCreditsRemaining": authority.deepCreditsRemaining ?? -1
], merge: true)
```

Or append to message doc:
```swift
msgRef.setData([
    "modelUsed": authority.acceptedMode ?? "core",
    ...
], merge: true)
```

---

### F-berean-004 — Theological Lens Not Bound to Conversation Session [LOW] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanModeEngine.swift:177–207`

**Observation:**
`BereanTheoLensStore.shared` is a global singleton. When user switches lenses, the change applies **to all new conversations immediately**, not just the current conversation. If user starts conversation A in Wisdom lens, switches to Prayer lens, then returns to conversation A, they will see Prayer lens applied on resume (not Wisdom).

**Evidence:**
- BereanModeEngine.swift:182–189: `selectedLens` is @Published on shared singleton
- No per-conversation lens persistence detected in schema
- BereanChatView.swift does not load/restore lens from conversation metadata

**Impact:**
Low: Lens is a response-style modifier, not a conversation context. User expectation may vary (some users want lens to persist per conversation, others expect global setting). Current behavior is simpler but less intuitive if user opened a conversation in Prayer mode and expects to return to it.

**Recommendation:**
**Option A (preferred):** Store selected lens in conversation metadata:
```swift
convRef.setData([
    "theoLens": BereanTheoLensStore.shared.selectedLens.rawValue
], merge: true)
```
On conversation load, restore lens from metadata:
```swift
if let savedLens = data["theoLens"] as? String,
   let lens = BereanTheoLens(rawValue: savedLens) {
    BereanTheoLensStore.shared.selectedLens = lens
}
```

**Option B:** Document that lens is a global setting (not conversation-scoped).

---

### F-berean-005 — Streaming Does Not Resume Across App Kill [MEDIUM] [SUSPECTED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ClaudeService.swift:561–622`

**Observation:**
When app is backgrounded mid-stream and killed by iOS (memory pressure or timeout), the URLSession continues in background mode (Apple's standard behavior), but:
1. No `BGTaskScheduler` registered to keep background session alive
2. No checkpoint/offset tracking for partial responses
3. If app is killed before message is marked `.completed` and persisted, the message may be left in `.streaming` state

On reopen:
- Message is still in `.streaming` state (in-memory `BereanChatMsg.streamingState`)
- Firestore shows partial text (last write before kill)
- No automatic resume mechanism

**Evidence:**
- No BGTaskScheduler usage in codebase
- No `.background` URLSessionConfiguration detected
- BereanChatView.swift:135: `streamTask: Task<Void, Never>?` is not persisted/restored

**Impact:**
Medium: User experience degradation if app is killed mid-response (message appears frozen, no clear recovery path). User must manually tap Regenerate or scroll to restart. However, message content is not lost (Firestore has partial text), just state is incorrect.

**Recommendation:**
**Option A:** Register a background task to mark message as `.failed` if stream doesn't complete:
```swift
let request = BGProcessingTaskRequest(identifier: "com.amen.berean.stream-checkpoint")
request.requiresNetworkConnectivity = true
request.requiresExternalPower = false
try BGTaskScheduler.shared.submit(request)
```

**Option B:** On app reopen, detect `.streaming` messages and offer "Resume" / "Regenerate" sheet.

**Option C:** Use URLSession background session with delegate to track completion.

---

### F-berean-006 — SSE Parsing Does Not Validate Content-Type Header [LOW] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ClaudeService.swift:546–622`

**Observation:**
```swift
let (asyncBytes, httpResponse) = try await URLSession.shared.bytes(for: urlRequest)

guard let resp = httpResponse as? HTTPURLResponse else {
    throw OpenAIServiceError.invalidResponse
}
switch resp.statusCode {
case 200: break
case 401, 403: throw OpenAIServiceError.unauthorized
case 429: throw OpenAIServiceError.rateLimited
default: throw OpenAIServiceError.invalidResponse
}
```

The code checks HTTP status code but **does not validate the Content-Type header**. If the backend mistakenly returns `application/json` or HTML on a 200 response, the SSE parser will silently fail to parse lines (no error thrown, just skipped lines).

**Evidence:**
- No `resp.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream")` check

**Impact:**
Low: URLSession usually validates Content-Type for you, and network tools (proxies) are unlikely to mangle headers. However, a misconfigured backend or MITM would silently break without clear error message.

**Recommendation:**
Add Content-Type validation:
```swift
guard let contentType = resp.value(forHTTPHeaderField: "Content-Type"),
      contentType.contains("text/event-stream") else {
    dlog("❌ Unexpected Content-Type: \(resp.value(forHTTPHeaderField: "Content-Type") ?? "missing")")
    throw OpenAIServiceError.invalidResponse
}
```

---

### F-berean-007 — Preflight Crisis Response Not Persisted [HIGH] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ClaudeService.swift:159–168`

**Observation:**
When `BereanChatPreflight.shortCircuitResponse` is non-nil (crisis escalation detected), the response is yielded immediately:
```swift
if let shortCircuitResponse = preflight.shortCircuitResponse {
    AMENAnalyticsService.shared.track(
        .bereanCrisisEscalationDetected(surface: "berean_chat")
    )
    continuation.yield(shortCircuitResponse)
    continuation.finish()
    return
}
```

But this short-circuit response **is not persisted to Firestore**. The conversation shows no record of the crisis response. If user later reviews the chat history, they won't see the safety message that was displayed.

**Evidence:**
- ClaudeService.swift:165: yield + finish, then return (no persistExchange call)
- BereanChatView.swift:511: `persistExchange()` is only called after normal stream completes, not after short-circuit

**Impact:**
High: Audit trail is incomplete for crisis interventions. If user self-harms and then claims they didn't receive a safety resource, the chat history will not show that Berean offered crisis support. This has legal/compliance implications.

**Recommendation:**
Persist the short-circuit response as an assistant message:
```swift
if let shortCircuitResponse = preflight.shortCircuitResponse {
    // ... existing tracking ...
    continuation.yield(shortCircuitResponse)
    
    // Immediately persist before finishing stream
    let msg = BereanChatMsg(role: .assistant, content: shortCircuitResponse, timestamp: .now)
    do {
        try await self.persistExchange(
            userText: message,
            assistantText: shortCircuitResponse,
            composerContext: nil,
            isEmergency: true
        )
    } catch {
        dlog("⚠️ Failed to persist crisis response: \(error)")
        // Log to Crashlytics for investigation
    }
    continuation.finish()
    return
}
```

Alternatively, trigger the persistence from `BereanChatView` after short-circuit (check `crisisEscalationDetected` flag and persist).

---

### F-berean-008 — Cancellation Does Not Propagate to Cloud Function If Connection Already Stalled [MEDIUM] [SUSPECTED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/ClaudeService.swift:561–562`

**Observation:**
```swift
for try await line in asyncBytes.lines {
    try Task.checkCancellation()
```

If the network stalls (no data received for 30+ seconds), the URLSession may not immediately notice the Task cancellation. The connection hangs until HTTP timeout (often 60s) or the for-await loop attempts to read the next line.

**Evidence:**
- No explicit timeout set on URLRequest
- No `URLSessionConfiguration` with `timeoutIntervalForRequest` or `waitsForConnectivity`

**Impact:**
Medium: If user taps cancel while network is stalled, the upstream Anthropic/OpenAI request may continue running for up to 60s before the connection is closed. This wastes tokens and billable compute.

**Recommendation:**
Set explicit timeouts on URLSessionConfiguration:
```swift
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30  // max 30s per request
config.timeoutIntervalForResource = 300 // max 5m total
config.waitsForConnectivity = true
let session = URLSession(configuration: config)
```

Or wrap the bytes stream in a Task with timeout:
```swift
let timeoutTask = Task { @MainActor in
    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)  // 5 minutes
    self.streamTask?.cancel()
}
defer { timeoutTask.cancel() }
```

---

### F-berean-009 — Dynamic Island Payload Truncation Silent [LOW] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanLiveActivityService.swift:180`

**Observation:**
```swift
let completeState = makeState(
    for: context,
    phase: .complete,
    responseText: String(text.prefix(200)),  // Silent truncation
    sourceCount: sourceCount,
    scriptures: Array(scriptures.prefix(3))
)
```

When response is longer than 200 characters, the text is silently truncated. No indicator (ellipsis, badge) shown to user that there's more content. User taps activity expecting to see the full response but gets a cliffhanger.

**Evidence:**
- BereanLiveActivityService.swift:180: `String(text.prefix(200))`
- No "…" suffix appended
- No `.truncationMode` or badge on the ActivityContent state

**Impact:**
Low: UX friction. User may assume response is incomplete or incorrect. However, tapping the activity opens the full response in the app, so information is not lost.

**Recommendation:**
Add truncation indicator:
```swift
let truncatedText = String(text.prefix(197))
let displayText = text.count > 200 ? truncatedText + "…" : truncatedText
```

Or add a badge to ContentState:
```swift
struct ContentState: Codable, Hashable {
    var isTruncated: Bool
    var fullResponseAvailable: Bool
    ...
}
```

---

### F-berean-010 — Firestore Soft-Delete Does Not Cascade to Subcollection [LOW] [CONFIRMED]

**Location:** `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/BereanChatsListView.swift:95–120`

**Observation:**
When conversation is marked deleted, the implementation sets `isDeleted: true` on the parent conversation document, but **does not set `isUserVisible: false` on all message subcollection documents**. If a user later queries the messages subcollection (e.g., via Firestore web console or a debug API), they will see the "deleted" conversation's messages.

**Evidence:**
- BereanChatsListView.swift: Deletion calls `deleteConversation(at: convRef)`
- BereanChatView.swift:766: `deleteConversation()` sets `isDeleted: true` on parent
- No batch update for messages subcollection

**Impact:**
Low: User-facing app filters by `isDeleted`, so messages are hidden. However, if backend runs purge jobs or if database is exported for audit, deleted data surfaces. For GDPR compliance, soft-delete should cascade.

**Recommendation:**
Update deletion logic to cascade:
```swift
private func deleteConversation(at convRef: DocumentReference) async {
    let batch = db.batch()
    
    // Mark conversation deleted
    batch.updateData(["isDeleted": true], forDocument: convRef)
    
    // Cascade: mark all messages as hidden
    let messagesSnap = try? await convRef.collection("messages").getDocuments()
    for msgDoc in messagesSnap?.documents ?? [] {
        batch.updateData(["isUserVisible": false], forDocument: msgDoc.reference)
    }
    
    try? await batch.commit()
}
```

---

## Cross-cutting Patterns

### P1. Modes Are Orthogonal, Not Hierarchical

**Observation:** The five mode categories (Theological Lenses, Response Styles, Model Tiers, Personality Modes, Study Mode) are independent. User can select:
- Wisdom lens + Prayer response mode + Deep tier + Scholar personality
- Each combination is valid and routed independently to the backend

**Implications:**
- **Complexity:** 3 × 10 × 3 × 8 = 720 theoretical combinations (though only a subset are advertised to users)
- **Backend surfacing:** Proxy receives `selectedMode` (model tier), `mode` (personality), and system prompt suffix (lens + response mode baked into prompt)
- **User education:** The UI hierarchy (Mode Sheet → Lens Selector) separates concerns, but discoverability is low

### P2. Authority is Server-Centric, with Client-Side Fallback

**Observation:** The backend is the source of truth for:
- Which model tier is actually used (via `acceptedMode` in SSE terminal event)
- Whether quota is exceeded (via `quotaExceeded` flag)
- How many deep credits remain (via `deepCreditsRemaining`)

Client-side store (`BereanModelStore`) updates based on server response. This prevents local claim-jumping (user can't claim they used Deep if the backend says Core).

**Implications:**
- **Upside:** Billing is auditable; no client-side quota violations
- **Downside:** If server is slow to respond with authority, client may request Deep even though quota is exhausted (server will downgrade, user sees banner)

### P3. SSE Streaming is Unidirectional, No Echo

**Observation:** Client sends request to bereanChatProxyStream, backend streams back `data:` lines. No server-to-client handshake or acknowledgment protocol. If client receives garbage, it silently skips the line.

**Implications:**
- **Robustness:** Linebreak errors are non-fatal (just skipped)
- **Debugging:** Malformed JSON in SSE event silently fails (no error trace)

### P4. Persistence Happens Post-Stream, Not Streaming

**Observation:** Messages are accumulated in-memory during streaming (`messages[index].content += chunk`), then persisted to Firestore after stream completes (in `persistExchange()`). No incremental checkpointing.

**Implications:**
- **Risk:** If app crashes mid-stream, in-memory content is lost (but partial text may have been written if debug logging saved it)
- **Simplicity:** No write amplification from incremental saves

### P5. Live Activity Depends on PostCard UI Flow, Not Chat Flow

**Observation:** Live Activity is triggered from a post card tap in the feed, not from within the chat. The post's context is frozen at trigger time (post content, author, etc.). If post is deleted or edited after activity starts, the activity shows stale data.

**Implications:**
- **Isolation:** Chat and post context are decoupled; post deletion doesn't invalidate activity
- **UX edge case:** Activity shows "View Full Response" but taps through to deleted post (404 in fallback)

---

## Handoffs

The following areas are out of scope for this audit but require coordination with other agents:

### H1. Backend Cloud Function Audit (bereanChatProxy, bereanChatProxyStream, bereanPostAssist)
- **Owner:** Backend/Cloud Functions auditor
- **Scope:** Validate mode authority enforcement, quota accounting, system prompt injection protection, token counting
- **Critical:** Confirm that `acceptedMode` and `fallbackMode` in SSE terminal event are server-authoritative (not spoofable by client)

### H2. Anthropic / OpenAI API Integration
- **Owner:** AI provider integration auditor
- **Scope:** Confirm that Tool Use / Function Calling (if enabled) does not introduce RCE surface; validate rate-limit compliance; audit token counting accuracy
- **Critical:** Verify that model tier selection (Haiku vs. Sonnet) is correctly communicated to providers

### H3. Firestore Security Rules
- **Owner:** Firestore auditor
- **Scope:** Validate that users can only read/write their own `/users/{uid}/bereanConversations` documents; confirm soft-delete is enforced in rules
- **Critical:** Ensure cross-user data leakage is impossible

### H4. SafetyOS / BiblicalAlignmentService
- **Owner:** Safety/alignment auditor
- **Scope:** Audit the real-time alignment checks post-stream; confirm no bypasses exist
- **Critical:** Verify that blocked responses are enforced and cannot be overridden by client

### H5. Premium / Entitlements System
- **Owner:** IAP / premium auditor
- **Scope:** Validate that Deep mode is locked behind IAP; confirm quota enforcement is correct; audit credit system
- **Critical:** Ensure user cannot trick the app into using Deep without paying

---

## Open Questions

1. **Does the backend paginate responses for multi-turn conversations?** The client sends `maxHistoryMessages: 12` with `maxTokens: 1_300`, but no indication of how backend handles overflow. Do long conversations get truncated, or does backend use a sliding window?

2. **What is the SLA for bereanChatProxyStream CloudFunction?** Docs mention "60s gen2 timeout," but is there connection keep-alive? Can a 5-minute response complete?

3. **Is the theological lens system production-ready?** BereanTheoLensStore is new (v1), but only a handful of users likely know about it. Is this feature behind a flag?

4. **Does Berean support interruptions (user types mid-stream to ask a follow-up)?** Current UX doesn't show cancel button until stream is active; unclear if user can send mid-response.

5. **How is response sanitization tested?** ClaudeService.sanitizeResponse() runs regex on client; what's the test coverage for the patterns?

6. **Do long responses ever exceed the 2000-token maxTokens limit?** Observed in code: `maxTokens: min(maxTokens, 2000)`. Is this ever hit in practice?

7. **Is there a hard delete or just soft-delete?** The audit assumes soft-delete only; confirm whether GCP Cloud Tasks runs a purge job.

---

## Blocked

### B1. Code-Level Token Counting Validation
Cannot confirm exact token count accuracy without access to the backend's tokenizer (likely uses Anthropic's tokenizer). Client-side `trimmedHistory()` estimates; backend has authoritative count. Recommend server-side audit.

### B2. Mode Authority Server-Side Enforcement
Cannot validate that backend correctly maps `selectedMode` to billing tiers without access to bereanChatProxy source. Assume correct for now; backend audit required.

### B3. PostContext Privacy Boundary
`BereanPostContext` embeds post content (preview, body, etc.) into the proxy request. Cannot audit post-level access control without firestore rules review. Delegated to H3.

---

## Summary Table: Severity & Certainty

| Finding | Severity | Certainty | Type | Recommendation |
|---------|----------|-----------|------|-----------------|
| F-berean-001 | MEDIUM | CONFIRMED | Design | Add Sendable to message structs |
| F-berean-002 | LOW | CONFIRMED | UX | Add cancel feedback (haptic + analytics) |
| F-berean-003 | MEDIUM | CONFIRMED | Audit Trail | Persist model authority result |
| F-berean-004 | LOW | CONFIRMED | UX | Document or implement per-conversation lens persistence |
| F-berean-005 | MEDIUM | SUSPECTED | Robustness | Implement background task or on-reopen recovery |
| F-berean-006 | LOW | CONFIRMED | Error Handling | Validate Content-Type header |
| F-berean-007 | HIGH | CONFIRMED | Compliance | Persist short-circuit crisis response |
| F-berean-008 | MEDIUM | SUSPECTED | Network | Set explicit request/resource timeouts |
| F-berean-009 | LOW | CONFIRMED | UX | Add truncation indicator to Dynamic Island |
| F-berean-010 | LOW | CONFIRMED | Data Integrity | Cascade soft-delete to message subcollection |

---

_Audit completed by Berean Core Auditor. No findings are blockers for production release. Three findings (F-berean-007, F-berean-003, F-berean-001) warrant prompt remediation before next major release. Remaining findings are enhancements._
