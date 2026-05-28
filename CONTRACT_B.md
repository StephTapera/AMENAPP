# CONTRACT_B.md — Spaces v2 Chat Core
> Agent B deliverables. Downstream agents (C, D, E, F) build against this contract.
> Do not redefine any type listed here.

---

## File Locations

| File | Path |
|------|------|
| `SpacesChatModels.swift` | `AMENAPP/Spaces/Chat/SpacesChatModels.swift` |
| `SpacesChatService.swift` | `AMENAPP/Spaces/Chat/SpacesChatService.swift` |
| `FilterTabData.swift`    | `AMENAPP/Spaces/Chat/FilterTabData.swift` |
| `ThreadListView.swift`   | `AMENAPP/Spaces/Chat/ThreadListView.swift` |
| `ThreadDetailView.swift` | `AMENAPP/Spaces/Chat/ThreadDetailView.swift` |

---

## Public Types

### `ThreadFilter` (SpacesChatModels.swift)

```swift
enum ThreadFilter: String, CaseIterable, Identifiable {
    case all      // displayName: "All"
    case vip      // displayName: "VIP"
    case unreads  // displayName: "Unreads"
    case external // displayName: "External"
}
```

Filter logic applied by `SpacesChatService`:
- `.all` — all threads
- `.vip` — threads whose ID is in `SpacesChatService.vipThreadIds`
- `.unreads` — threads where `unreadCount > 0`
- `.external` — threads where `hasExternalMembers == true`

---

### `ThreadSummary` (SpacesChatModels.swift)

```swift
struct ThreadSummary: Codable, Identifiable {
    var id: String
    var spaceId: String
    var title: String
    var createdBy: String
    var createdAt: Date
    var lastMessageAt: Date
    var lastMessagePreview: String?
    var unreadCount: Int
    var hasExternalMembers: Bool  // ← "external member" signal for Agent C
}
```

---

### `SpacesChatMessage` (SpacesChatModels.swift)

```swift
struct SpacesChatMessage: Codable, Identifiable {
    var id: String
    var threadId: String
    var spaceId: String
    var authorId: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    var authorHomeCommunityId: String?  // nil = owning community; non-nil = external
    var body: String
    var createdAt: Date
    var editedAt: Date?
    var reactions: [String: [String]]  // emoji → [userId]
    var attachments: [SpacesChatAttachment]
    var isDeleted: Bool                // soft-delete sentinel — NEVER hard-delete
}
```

`isDeleted == true` renders "This message was removed." — never hide the row.

---

### `SpacesChatAttachment` (SpacesChatModels.swift)

```swift
enum SpacesChatAttachmentType: String, Codable { image, video, file, audio }

struct SpacesChatAttachment: Codable, Identifiable {
    var id: String
    var type: SpacesChatAttachmentType
    var url: String
    var thumbnailURL: String?
    var fileName: String?
    var fileSizeBytes: Int?
}
```

---

### `SpacesChatTypingIndicator` (SpacesChatModels.swift)

```swift
struct SpacesChatTypingIndicator {
    var userId: String
    var displayName: String
    var timestamp: Date
}
```

RTDB path: `typing/{spaceId}/{threadId}/{userId}`. Nodes older than 5 s are treated as stale.

---

### `SpacesChatReadState` (SpacesChatModels.swift)

```swift
struct SpacesChatReadState: Codable {
    var threadId: String
    var userId: String
    var lastReadMessageId: String
    var lastReadAt: Date
}
```

Firestore path: `spaces/{spaceId}/threads/{threadId}/readStates/{userId}`.

---

### `SpaceFilterTabData` (FilterTabData.swift)

```swift
/// Data that drives All / VIP / Unreads / External filter tabs.
/// Agent C imports this. Do not put UI logic here.
struct SpaceFilterTabData {
    let filter: ThreadFilter
    let count: Int      // badge count; 0 = no badge
    let isSelected: Bool
}
```

Factory method (also in FilterTabData.swift):

```swift
extension SpaceFilterTabData {
    static func makeAll(
        threads: [ThreadSummary],
        vipThreadIds: Set<String>,
        currentFilter: ThreadFilter
    ) -> [SpaceFilterTabData]
}
```

Agent C calls `SpaceFilterTabData.makeAll(...)` to build the filter-tab row.

---

## `SpacesChatService` Method Signatures

```swift
@MainActor
final class SpacesChatService: ObservableObject {

    // Published
    @Published var threads: [ThreadSummary]
    @Published var currentFilter: ThreadFilter
    @Published var messages: [SpacesChatMessage]
    @Published var typingUsers: [SpacesChatTypingIndicator]
    @Published var lastError: String?

    // Readable by Agent C for badge construction
    var vipThreadIds: Set<String>

    // Thread list
    func loadThreads(spaceId: String, filter: ThreadFilter) async
    func setFilter(_ filter: ThreadFilter)

    // Messages
    func loadMessages(threadId: String, spaceId: String) async
    func sendMessage(threadId: String, spaceId: String, body: String, replyToId: String?) async throws
    func softDeleteMessage(messageId: String, threadId: String, spaceId: String) async throws
    func addReaction(emoji: String, messageId: String, threadId: String, spaceId: String) async throws
    func removeReaction(emoji: String, messageId: String, threadId: String, spaceId: String) async throws

    // Read state
    func markThreadRead(threadId: String, spaceId: String, lastMessageId: String) async

    // Typing (RTDB)
    func startTyping(threadId: String, spaceId: String) async
    func stopTyping(threadId: String, spaceId: String) async
    func observeTyping(threadId: String, spaceId: String)
    func stopObservingTyping(threadId: String, spaceId: String)

    // Berean @mention
    func invokeBerean(threadId: String, spaceId: String, message: String, spaceType: SpaceV2Type) async throws

    // Lifecycle
    func stopListening()
}
```

---

## Views Exported

### `ThreadListView`

```swift
struct ThreadListView: View {
    init(spaceId: String, space: AmenSpaceExtended)
}
```

- Renders filter tab bar (`AmenLiquidGlassControlDock`) + thread rows (glass cards)
- Checks `space.isDeleted` — shows "This Space is no longer available." if true
- Navigates to `ThreadDetailView` on thread tap
- External-member indicator: `link` SF Symbol in `AmenTheme.Colors.amenPurple` (placeholder for C's `LinkedGlyph`)

### `ThreadDetailView`

```swift
struct ThreadDetailView: View {
    init(threadId: String, spaceId: String, space: AmenSpaceExtended)
}
```

- Entitlement gate: calls `EntitlementService.shared.observeEntitlement` live
- Locked overlay exposes `showPurchaseSheet: @State Bool` — Agent E/C wires this to the purchase sheet
- Berean @mention: body `lowercased().hasPrefix("@berean")` → `service.invokeBerean(...)`
- Deleted messages: always rendered as "This message was removed." (never hidden)
- External author: `authorHomeCommunityId != nil` → `amenPurple` chain glyph (placeholder for C's `LinkedGlyph`)

---

## How "External Members Present" is Signalled

| Location | Field | Meaning |
|----------|-------|---------|
| `ThreadSummary.hasExternalMembers` | `Bool` | Thread has ≥ 1 member with non-nil `homeCommunityId` |
| `SpacesChatMessage.authorHomeCommunityId` | `String?` | Non-nil = author is from a linked external community |

Both are populated from Firestore. In `ThreadRowCard` and `MessageBubble`, a placeholder `link` SF Symbol in `AmenTheme.Colors.amenPurple` renders the signal. Agent C replaces these with `LinkedGlyph` in v2 — the placeholder glyph is comment-tagged `// placeholder for C's LinkedGlyph`.

---

## Firestore Paths Owned by B (read/write)

```
spaces/{spaceId}/threads/{threadId}          — loadThreads listener
spaces/{spaceId}/threads/{threadId}/messages/{messageId}  — loadMessages listener + sendMessage + softDelete + reactions
spaces/{spaceId}/threads/{threadId}/readStates/{userId}   — markThreadRead
spaces/{spaceId}/members/{userId}            — role check in softDeleteMessage (read only)
RTDB: typing/{spaceId}/{threadId}/{userId}   — startTyping / stopTyping / observeTyping
```

---

## Naming Collisions Resolved

Pre-existing types in the codebase that conflict with the mandate's type names:

| Mandate name | Conflict source | B's resolution |
|---|---|---|
| `SpaceMessage` | `AMENAPP/AMENAPP/Spaces/SpacesModels.swift` | Renamed → `SpacesChatMessage` |
| `MessageAttachment` | `AMENAPP/Message.swift` | Renamed → `SpacesChatAttachment` |
| `TypingIndicator` | `AMENAPP/MessageModels.swift` | Renamed → `SpacesChatTypingIndicator` |
| `ReadState` | none | Renamed → `SpacesChatReadState` for clarity |

---

## Handoff

**What changed:** New directory `AMENAPP/Spaces/Chat/` with 5 files (0 new errors, 2 intentional RTDB-callback warnings).

**Contract exposed:** `SpacesChatService` is the single write/read seam for threads + messages + reactions + typing. `SpaceFilterTabData.makeAll(...)` is the seam for Agent C's filter-tab row. `hasExternalMembers` on `ThreadSummary` and `authorHomeCommunityId` on `SpacesChatMessage` are the cross-community signals Agent C replaces with `LinkedGlyph`.

**Assumptions made:** (1) `SpaceEntitlement` ambiguity between `SpacesEntitlementModels.swift` and `SpacesModels.swift` resolved by not storing the full entitlement struct in `ThreadDetailView` — only `isLocked: Bool` is tracked. (2) RTDB `setValue`/`removeValue` use callback-based variants to avoid the `try await` requirement on fire-and-forget typing signals (two `warning: Consider using async alternative` suppressed by design). (3) `AmenSpaceType.churchMinistry` is used as the Berean bridge type for `.chat` and `.announcement` SpaceV2Types — this is the closest legacy type and does not introduce the word "church" into any user-visible string.
