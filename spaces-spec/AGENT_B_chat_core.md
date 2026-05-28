# Agent B — Chat Core (messages, threads, DMs, reactions)

> Read `00_MASTER_CONTRACT.md` and `CONTRACT_A.md` first. Do NOT start wiring until A is
> complete (CONTRACT_A.md ends with "AGENT_A_COMPLETE"). You build the substrate
> everything else renders into. Project root: `~/Desktop/AMEN/AMENAPP copy/`, workspace
> `AMENAPP.xcworkspace`.

## Your mandate

### Step 1 — AUDIT FIRST (gap report before changing anything)

Inventory existing infrastructure:

- **Berean streaming**: find the SSE / streaming architecture in
  `AMENAPP/AIIntelligence/` — specifically `BereanRealtimeWebSocketTransport.swift`,
  `BereanRealtimeSessionManager.swift`, `BereanRealtimeTransportCoordinator.swift`. Map
  what is truly reusable for general Space chat vs. what is Berean-AI-specific.
- **Messaging/threads**: look for any existing thread or DM models in
  `AMENAPP/AMENAPP/CommunicationOS/` and `AmenThreadView.swift` at project root.
  Check `CommunicationOSModels.swift`, `AmenConversationOSModels.swift`.
- **Reactions**: search for existing emoji reaction code in the messaging layer.
- **RTDB presence / typing indicators**: check `database.rules.json` and any presence
  service in the codebase.
- **DMs**: check if there is an existing DM model in `ConversationOS/` that can be reused
  as a degenerate Space.

Produce a gap report: reusable items, missing items, conflicts with Master Contract.

### Step 2 — Message/thread core

Implement against `CONTRACT_A.md`'s schema. Files own by B (do not edit C/D/E/F files):

**`AMENAPP/AMENAPP/Spaces/ChatCore/SpacesChatModels.swift`**
```swift
// SpaceThread: id, spaceId, title, createdBy, createdAt, lastMessageAt
// SpaceMessage: id, threadId, authorId, body, createdAt, editedAt?, reactions, attachments, status
// SpaceReaction: emoji, userIds: [String]
// SpaceDraftMessage: body, attachments (local compose state, never persisted as-is)
// MessageStatus: active | deleted
```

**`AMENAPP/AMENAPP/Spaces/ChatCore/SpacesChatService.swift`** (async/await, no Combine)
```swift
// sendMessage(to threadId: String, in spaceId: String, body: String) async throws
// editMessage(id: String, newBody: String) async throws
// softDeleteMessage(id: String) async throws  // sets status: "deleted", NEVER hard-deletes
// fetchMessages(threadId: String, before: Date?, limit: Int) async throws -> [SpaceMessage]
// streamMessages(threadId: String) -> AsyncStream<[SpaceMessage]>
// addReaction(emoji: String, to messageId: String, by userId: String) async throws
// removeReaction(emoji: String, from messageId: String, by userId: String) async throws
// updateLastMessageAt(threadId: String, spaceId: String, at: Date) async throws
```

**`AMENAPP/AMENAPP/Spaces/ChatCore/SpacesChatViewModel.swift`** (@MainActor)
```swift
@MainActor
final class SpacesChatViewModel: ObservableObject {
    @Published var messages: [SpaceMessage] = []
    @Published var draftBody: String = ""
    @Published var isLoading: Bool = false
    @Published var error: Error? = nil
    // All state mutations happen on @MainActor — no async mutations off main.
    // Streaming via AsyncStream bridged to @MainActor.
    // Expose filter data for Agent C:
    var hasUnread: Bool
    var vipMessages: [SpaceMessage]       // messages from followed/VIP authors
    var externalMemberMessages: [SpaceMessage]  // messages where author.homeCommunityId != owning community
}
```

### Step 3 — SSE/streaming reuse

If the Berean SSE path (true SSE + cancellation propagation) is reusable for general
streaming, wrap it — do not fork a second implementation. If Berean's transport is
tightly coupled to AI responses (OpenAI/Anthropic token streams), build a minimal
`FirestoreMessageStream` using Firestore real-time listeners and expose it as
`AsyncStream<[SpaceMessage]>`. The interface to Agent C must be identical regardless.

Do NOT use `Combine` (`Publisher`, `sink`, `cancellable`). Use `async/await` and
`AsyncStream` exclusively.

### Step 4 — Reactions

- Emoji picker: reuse existing reaction/emoji UI if it exists, otherwise a simple
  horizontal row of common emojis + "+" for the full picker.
- Reaction model: `reactions: [String: [String]]` on the message doc (emoji → [userId]).
  Firestore `arrayUnion`/`arrayRemove` for add/remove.
- Display: aggregate counts, highlight if current user reacted (amenGold tint).
- Do NOT implement the reaction UI row yourself — expose `SpaceMessage.reactions` and a
  `toggleReaction(emoji:messageId:)` method. Agent C renders the row.

### Step 5 — DMs as degenerate Spaces

DMs = a Space with `type: "chat"`, `accessPolicy: "free"`, `members: [userA, userB]`,
no public listing. This avoids a parallel data model and lets the same chat core render
both group chats and DMs.

If the existing `ConversationOS` DM model in Firestore has significant production data,
do NOT migrate it — bridge instead: write a `DMBridgeService` that translates existing
DM conversations to the Space model for the view layer without touching stored data.

Document your choice and the reason in CONTRACT_B.md.

### Step 6 — Typing indicators + presence

RTDB path: `presence/{userId}/typing/{threadId}: { isTyping: bool, updatedAt: timestamp }`.
Expire stale indicators after 5 seconds client-side (no server needed).

If an existing presence path exists in `database.rules.json`, extend it rather than
creating a parallel path.

### Step 7 — Filter data exposure for Agent C

Agent C's Spaces list needs these signals from the chat layer:
```swift
struct SpaceFilterSignals {
    let hasUnread: Bool
    let unreadCount: Int
    let hasExternalMembers: Bool
    let latestMessagePreview: String?
    let latestMessageAt: Date?
    let isVIP: Bool    // true if any author in the Space is followed by current user
}
```
Compute these in `SpacesChatViewModel` or a lightweight `SpacesFilterService`. Agent C
imports these; it does NOT recompute them.

### @MainActor contract (hunt and close violations)

Known crash vector: `EXC_BAD_ACCESS` / `CALayerGetSuperlayer` when async completions
mutate `@Published` properties off the main actor. Every `@Published` property must be
guarded by `@MainActor`. AsyncStream continuations must be dispatched to main before
yielding to published state. Add a build-time check: if you see any
`Task { self.somePublishedProperty = ... }` without `await MainActor.run { ... }`, fix it.

---

## Hard constraints

- No hard-deletes of messages. `status: "deleted"` only, body replaced with "" or a
  tombstone string client-side. Never `document.delete()` on a message in-render.
- Do not re-implement design components — expose data, Agent C renders.
- Do not bypass A's entitlement gate. SpacesChatService must fail gracefully (throw a
  typed `SpacesError.accessDenied`) if the Space is paid and no valid entitlement exists.
- No Combine. Async/await + AsyncStream only.
- No "church" language in any string, enum, or model field name.

---

## Deliverables

1. `AMENAPP/AMENAPP/Spaces/ChatCore/SpacesChatModels.swift`
2. `AMENAPP/AMENAPP/Spaces/ChatCore/SpacesChatService.swift`
3. `AMENAPP/AMENAPP/Spaces/ChatCore/SpacesChatViewModel.swift`
4. `AMENAPP/AMENAPP/Spaces/ChatCore/SpacesTypingService.swift` (RTDB presence)
5. `AMENAPP/AMENAPP/Spaces/ChatCore/SpacesFilterService.swift` (filter signals)
6. **`spaces-spec/CONTRACT_B.md`** — public view-model interface, filter signal struct,
   streaming API, DM strategy choice + reason, @MainActor guarantees.

---

## Done when

- All five Swift files build with zero diagnostics (use `XcodeRefreshCodeIssuesInFile`).
- No `@MainActor` violations.
- No hard-deletes in code paths.
- `CONTRACT_B.md` published ending with "AGENT_B_COMPLETE".
