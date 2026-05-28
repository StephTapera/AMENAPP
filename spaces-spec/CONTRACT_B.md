# CONTRACT_B — Spaces Chat Core
# Agent B delivery contract
# Status: AGENT_B_COMPLETE

---

## 1. Deliverables

All five Swift files are written and confirmed **zero diagnostics** via
`XcodeRefreshCodeIssuesInFile`.

| File | Path | Diagnostics |
|------|------|-------------|
| `SpacesChatCoreModels.swift` | `AMENAPP/AMENAPP/Spaces/ChatCore/` | 0 |
| `SpacesChatViewModel.swift` | `AMENAPP/AMENAPP/Spaces/ChatCore/` | 0 |
| `SpacesChatView.swift` | `AMENAPP/AMENAPP/Spaces/ChatCore/` | 0 |
| `SpacesTypingService.swift` | `AMENAPP/AMENAPP/Spaces/ChatCore/` | 0 |
| `SpacesFilterService.swift` | `AMENAPP/AMENAPP/Spaces/ChatCore/` | 0 |

Gap report: `spaces-spec/AUDIT_B.md`

---

## 2. Public API Surface (for Agent C)

### SpacesChatView

```swift
// Embed in SpaceDetailView (Agent C):
SpacesChatView(viewModel: chatVM, spaceId: space.spaceId)
```

`SpacesChatView` is a `@MainActor struct` with:
- `@ObservedObject var viewModel: SpacesChatViewModel`
- `let spaceId: String`

Manages its own `.task { await viewModel.loadSpace(spaceId:) }` and
`.onDisappear { viewModel.stopListening() }`. Agent C does not call these.

### SpacesChatViewModel

```swift
@MainActor
final class SpacesChatViewModel: ObservableObject {
    @Published var messages: [SpacesChatMessage]
    @Published var threads: [ThreadSummary]
    @Published var activeThreadId: String?
    @Published var draftBody: String
    @Published var isLoading: Bool
    @Published var error: Error?
    @Published var typingUserIds: [String]

    var filterSignals: SpaceFilterSignals        // computed, no extra Firestore reads
    var externalMemberMessages: [SpacesChatMessage]  // authorHomeCommunityId != nil

    func loadSpace(spaceId: String) async
    func selectThread(_ threadId: String) async
    func sendMessage(body: String) async
    func softDeleteMessage(id: String) async
    func toggleReaction(emoji: String, messageId: String) async
    func startTyping()
    func stopTyping()
    func startListening()
    func stopListening()
    func setFilter(_ filter: ThreadFilter)
    func toggleVIP()
    func markActiveThreadRead()
}
```

### SpaceFilterSignals

```swift
struct SpaceFilterSignals {
    let spaceId: String
    let hasUnread: Bool
    let unreadCount: Int          // sum of ThreadSummary.unreadCount for unseen threads
    let hasExternalMembers: Bool  // any thread has cross-community member
    let latestMessagePreview: String?
    let latestMessageAt: Date?
    let isVIP: Bool               // user-starred (UserDefaults, v1)
}
```

Agent C reads `viewModel.filterSignals` to drive unread badges, VIP stars, and
sort order in the Spaces list. No additional Firestore reads required.

### SpacesFilterService

```swift
final class SpacesFilterService {
    static let shared: SpacesFilterService

    func signals(for spaceId: String, threads: [ThreadSummary]) -> SpaceFilterSignals
    func batchSignals(_ spacesWithThreads: [(spaceId: String, threads: [ThreadSummary])]) -> [SpaceFilterSignals]
    func lastSeenAt(spaceId: String) -> Date
    func markSeen(spaceId: String)
    var vipSpaceIds: Set<String>
    func toggleVIP(spaceId: String)
    func isVIP(spaceId: String) -> Bool
}
```

### SpacesTypingService

Standalone RTDB wrapper — usable independently of `SpacesChatService`.

```swift
final class SpacesTypingService {
    static let staleThresholdSeconds: TimeInterval  // = 5.0

    func startTyping(spaceId: String, threadId: String)
    func stopTyping(spaceId: String, threadId: String)
    func observe(spaceId: String, threadId: String,
                 onUpdate: @escaping @MainActor ([SpacesChatTypingIndicator]) -> Void)
    func stopObserving()
}
```

---

## 3. Architecture Decisions

### 3a. Transport: Firestore snapshot listeners (NOT BereanRealtimeWebSocketTransport)

`BereanRealtimeWebSocketTransport` is a WebSocket bridge to OpenAI — not a
general-purpose realtime transport. Spaces chat uses Firestore `.addSnapshotListener`
(bridged to `@Published` via `Task { @MainActor in }`) via the pre-existing
`SpacesChatService` in `AMENAPP/Spaces/Chat/`. No new transport layer was built.

### 3b. DM Strategy

Direct Messages are modeled as a `Space` with:
- `type: .chat`
- `accessPolicy: .free`
- `members: [userA, userB]`

No separate DM collection. `SpacesChatView` / `SpacesChatViewModel` work for DMs
unchanged — the `spaceId` is the DM Space's Firestore doc ID. Agent D (creation
wizard) creates the DM Space; Agent C routes to it.

### 3c. Soft-Delete Only

`softDeleteMessage` sets `isDeleted = true` on the Firestore document.
`SpacesChatView` renders a tombstone ("This message was removed.") for deleted
messages. No `.delete()` call is ever made on a Firestore document.

### 3d. External Member Signal

`SpacesChatMessage.authorHomeCommunityId: String?` is `nil` for same-community
authors and non-nil for cross-community (linked) authors. `SpacesChatView`
renders a `link.circle.fill` placeholder glyph. Agent C replaces this with its
own `LinkedGlyph` component using the same condition.

`SpacesChatViewModel.externalMemberMessages` returns the filtered subset for
Agent C to badge/sort.

### 3e. VIP (v1)

VIP = user-starred spaces. Stored as `Set<String>` in `UserDefaults` under key
`vipSpaceIds`. Firestore-backed VIP (e.g., admin-pinned spaces) is deferred to v2.

### 3f. No Combine

All async coordination uses `async/await` + `Task { @MainActor in }`. No
`Combine` publishers or `AnyCancellable` anywhere in the ChatCore layer.

### 3g. Firestore Path

```
spaces/{spaceId}/threads/{threadId}/messages/{messageId}
```

Top-level collection is `amenCommunities`, NOT `communities`.
Delegated entirely to `SpacesChatService` — ChatCore layer does not read
Firestore directly.

### 3h. RTDB Typing Path

```
typing/{spaceId}/{threadId}/{userId}
Payload: { userId: String, timestamp: ServerValue.timestamp() }
```

Client-side stale expiry: nodes older than 5 seconds are discarded before
dispatching to `onUpdate`.

---

## 4. Design Token Compliance

All colors come from `AmenTheme.Colors` only. No local `Color(hex:)` or
`Color(.systemXxx)` literals except for SwiftUI system fills
(`Color(.systemFill)`, `Color(.systemBackground)`) which have no `AmenTheme`
equivalent. No "church" strings appear anywhere in the ChatCore layer.

---

## 5. Pre-existing Issues (not introduced by Agent B)

The following errors existed before Agent B's changes and are out of scope:

- `SmartSuggestion` redeclaration across multiple files
- `ChurchDetailExperience` type errors in the Discover layer
- `CommunityRole` redeclaration (pre-existing conflict in Spaces/Chat layer)

---

## 6. Seams for Agent C

| Seam | How Agent C uses it |
|------|---------------------|
| `SpacesChatView(viewModel:spaceId:)` | Embed directly in `SpaceDetailView` |
| `viewModel.filterSignals` | Drive unread badge, VIP star, sort order in Spaces list |
| `viewModel.externalMemberMessages` | Cross-community message badge/filter |
| `viewModel.selectThread(_:)` | Navigate into a thread from thread list |
| `SpacesFilterService.shared.batchSignals(_:)` | One-pass signals for all spaces |
| `SpacesTypingService` (standalone) | Reuse in any view that needs typing presence |

---

AGENT_B_COMPLETE
