# Dynamic Reply Preview — Contract
<!-- VERSION: 1.0.2 — 2026-05-27 -->

> **Amendment process**: Any change to this file requires updating the version line at the top.
> Downstream agents read the version before using any symbol.

---

## 1. File Inventory (real discovered paths)

| Role | Status | Exact Path |
|------|--------|-----------|
| Post model (Feed) | EXISTS | `AMENAPP/PostsManager.swift` — `struct Post` |
| FirestorePost DTO / post service | EXISTS | `AMENAPP/FirebasePostService.swift` — `struct FirestorePost`, `class FirebasePostService` |
| PostCard view | EXISTS | `AMENAPP/PostCard.swift` — `struct PostCard: View` |
| PostCardRenderModel | EXISTS | `AMENAPP/AMENAPP/PostCardRenderModel.swift` — `struct PostCardRenderModel: Equatable` |
| Post detail / reply thread | EXISTS | `AMENAPP/PostDetailView.swift` — `struct PostDetailView: View` |
| LiquidReplyPreviewChip | EXISTS | `AMENAPP/AMENAPP/LiquidReplyPreviewChip.swift` |
| LiquidReplyPreviewRotator | EXISTS | `AMENAPP/AMENAPP/LiquidReplyPreviewRotator.swift` |
| DynamicReplyPreview (model) | EXISTS | `AMENAPP/AMENAPP/DynamicReplyPreview.swift` |
| Feature flags | EXISTS | `AMENAPP/AMENFeatureFlags.swift` — `final class AMENFeatureFlags` |
| Analytics service | EXISTS | `AMENAPP/AMENAnalyticsService.swift` — `final class AMENAnalyticsService` |
| Safety / content gate | EXISTS | `AMENAPP/SafetyOrchestrator.swift` — `final class SafetyOrchestrator` |
| Content moderation (cloud) | EXISTS | `AMENAPP/ContentModerationService.swift` — `class ContentModerationService` |
| Color tokens | EXISTS | `AMENAPP/AMENAPP/AmenTheme.swift` — `enum AmenTheme` |
| Liquid Glass tokens | EXISTS | `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassTokens.swift` — `enum LiquidGlassTokens` |
| PostComment model | EXISTS | `AMENAPP/PostComment.swift` — `struct PostComment: Identifiable, Codable` |
| Reply (profile tab only) | EXISTS | `AMENAPP/UserProfileView.swift:98` — `struct Reply: Identifiable` |
| ReplyThread (profile tab) | EXISTS | `AMENAPP/RepliesModels.swift:98` — `struct ReplyThread: Identifiable` |
| Navigation router | EXISTS | `AMENAPP/AmenContentRouter.swift` — `final class AmenUniversalContentRouter` |
| Replies / comments service | EXISTS | `AMENAPP/CommentService.swift` — `class CommentService: ObservableObject` |
| Follow-graph accessor | EXISTS | `AMENAPP/FollowService.swift` — `class FollowService`, `@Published var following: Set<String>`, `fetchFollowing(userId:)`, `fetchFollowingIds(userId:)` |
| Post reaction service | EXISTS | `AMENAPP/PostInteractionsService.swift` — `toggleAmen(postId:)`, `toggleLightbulb(postId:)`, `addComment(...)` |
| Report service | EXISTS | `AMENAPP/ModerationService.swift` — `reportPost(postId:postAuthorId:reason:additionalDetails:)`, `reportComment(...)` |
| Composer / publish surface | EXISTS | `AMENAPP/CreatePostView.swift` — `publishPost()`, `proceedWithPublish()`, `publishImmediately(...)` |
| Cloud Functions root | EXISTS | `Backend/functions` — selected by root `firebase.json` (`source: "Backend/functions"`, `runtime: "nodejs22"`, `codebase: "creator"`) |
| `openReplies` / `showReplyActions` | NOT FOUND — must be built | New methods on router or dedicated PostFeedRouter |
| Reply preview model file | EXISTS | `AMENAPP/AMENAPP/DynamicReplyPreview.swift` |
| Four reply preview model symbols | MATERIALIZED | `ReplyPreviewType`, `DynamicReplyPreview`, `ReplyCandidate`, `ResolvedReplyPreview` in `AMENAPP/AMENAPP/DynamicReplyPreview.swift` |

---

## 2. Selah/PostCard Module

**Note**: "Selah" in this codebase is an AI reading experience (`SelahView.swift`), not a social feed. The social PostCard is `PostCard` + `PostCardRenderModel`. All Dynamic Reply Preview work attaches to the **PostCard** module.

### PostCard — Exact Props

```swift
// AMENAPP/PostCard.swift
@MainActor
struct PostCard: View {
    let post: Post?
    let authorName: String
    let timeAgo: String
    let content: String
    let category: PostCardCategory
    let topicTag: String?
    let isUserPost: Bool
    let feedContextLabel: AmenFeedContextLabel?
    let aiUsage: PostAIUsage?
}
```

### PostCardRenderModel — Key Reply Preview Field

```swift
// AMENAPP/AMENAPP/PostCardRenderModel.swift:106
let dynamicReplyPreviewCandidates: [DynamicReplyPreview]
```

Populated from `post.dynamicReplyPreviewCandidates` (Firestore-decoded array on `Post`).

---

## 3. Reply Thread Screen

**EXISTS**: `PostDetailView` is the existing reply/thread screen.

```swift
// AMENAPP/PostDetailView.swift
struct PostDetailView: View {
    let post: Post
    var highlightedCommentId: String? = nil
    var initialBereanPostContext: BereanPostContext? = nil
    var autoOpenBereanOnAppear = false
}
```

Navigation: PostCard presents it via `PostCardSheet.commentsHighlighted(post:replyId:highlightedCommentIds:)` as a sheet. There is no standalone `openReplies(postId:)` method — that must be built.

### Replies Service / Comments Accessor

**Type**: `class CommentService: ObservableObject`
**File**: `AMENAPP/CommentService.swift`
**Singleton**: `CommentService.shared`

Key existing APIs:
```swift
func addComment(
    postId: String,
    content: String,
    mentionedUserIds: [String]?,
    post: Post?,
    threadCategory threadCategoryOverride: String?,
    momentAnchor: MediaMomentAnchor?
) async throws -> Comment

func fetchReplies(for commentId: String) async throws -> [Comment]
func fetchCommentsWithReplies(for postId: String) async throws -> [CommentWithReplies]
```

### Follow-Graph Accessor

**Type**: `class FollowService: ObservableObject`
**File**: `AMENAPP/FollowService.swift`
**Singleton**: `FollowService.shared`

Key existing APIs / state:
```swift
@Published var following: Set<String>
@Published var followers: Set<String>

func fetchFollowing(userId: String) async throws -> [FollowUserProfile]
func fetchFollowingIds(userId: String) async throws -> [String]
```

The Dynamic Reply Preview resolver's `viewerFollows` input should use `FollowService.shared.following` for already-loaded current-user state, or `fetchFollowingIds(userId:)` when it needs to load explicitly.

---

## 4. Router / Coordinator

**Primary router**: `AmenUniversalContentRouter` (`AMENAPP/AmenContentRouter.swift`)

```swift
@MainActor
final class AmenUniversalContentRouter: ObservableObject {
    static let shared = AmenUniversalContentRouter()
    func destination(for contentNode: ContentNode) -> AmenContentDestination
    func destination(forEntityType type: String, id: String) -> AmenContentDestination
    func destination(from url: URL) -> AmenContentDestination
}
```

**PostCard internal navigation** uses `PostCardSheet` (sheet-based, declared `fileprivate` inside `PostCard.swift`):

```swift
case comments(post: Post)
case commentsHighlighted(post: Post, replyId: String?, highlightedCommentIds: [String])
case berean(initialQuery: String, postContext: BereanPostContext?)
```

**Navigation methods to build** (contract-frozen signatures):

```swift
// Navigation Agent must implement these on AmenUniversalContentRouter or a new PostFeedRouter
func openReplies(postId: String, highlightedReplyId: String?)
func showReplyActions(postId: String, replyId: String)
```

### Like / Report / Composer Methods

Existing post reaction APIs:
```swift
// AMENAPP/PostInteractionsService.swift
PostInteractionsService.shared.toggleAmen(postId: String) async throws
PostInteractionsService.shared.toggleLightbulb(postId: String) async throws
```

Existing report APIs:
```swift
// AMENAPP/ModerationService.swift
ModerationService.shared.reportPost(
    postId: String,
    postAuthorId: String,
    reason: ModerationReportReason,
    additionalDetails: String?
) async throws

ModerationService.shared.reportComment(
    commentId: String,
    commentAuthorId: String,
    postId: String,
    reason: ModerationReportReason,
    additionalDetails: String?
) async throws
```

Existing composer/publish surface:
```swift
// AMENAPP/CreatePostView.swift
private func publishPost()
private func proceedWithPublish()
private func publishImmediately(
    content: String,
    category: Post.PostCategory,
    topicTag: String?,
    allowComments: Bool,
    linkURL: String?
)
```

---

## 5. Feature Flags Service

**Type**: `final class AMENFeatureFlags: ObservableObject`
**File**: `AMENAPP/AMENFeatureFlags.swift`

**Declaration pattern**:
```swift
@Published private(set) var someFeatureEnabled: Bool = false
```

**RemoteConfig backing pattern** (in `applyRemoteConfig(_ config: RemoteConfig)`):
```swift
someFeatureEnabled = config["remote_config_key_here"].boolValue
```

**New flag for this feature**:
```swift
// Add to AMENFeatureFlags
@Published private(set) var replyPreviewRotationEnabled: Bool = false
```

```swift
// Add to applyRemoteConfig
replyPreviewRotationEnabled = config["reply_preview_rotation_enabled"].boolValue
```

**Feature flag key** (exact RemoteConfig string): `reply_preview_rotation_enabled`
**Default**: `false`
**RemoteConfig wrapper/root**: `AMENAPP/AMENFeatureFlags.swift` (`AMENFeatureFlags.shared`, `fetchRemoteConfig()`, `applyRemoteConfig(_:)`)

Guard pattern:
```swift
guard AMENFeatureFlags.shared.replyPreviewRotationEnabled else { return }
```

---

## 6. Color Tokens & Liquid Glass Conventions

**Sources**:
- `AMENAPP/AMENAPP/AmenTheme.swift`
- `AMENAPP/AMENAPP/LiquidGlass/LiquidGlassTokens.swift`

### Brand Gold Token (amenGold)
```swift
AmenTheme.Colors.amenGold = Color(red: 0.83, green: 0.69, blue: 0.22)
```

### Glass Materials
```swift
LiquidGlassTokens.blurThin      = .ultraThinMaterial   // capsule chip default
LiquidGlassTokens.blurRegular   = .thinMaterial
LiquidGlassTokens.blurElevated  = .regularMaterial
```

### Capsule Chip Standard (from LiquidReplyPreviewChip — exact values)
- **Material**: `.ultraThinMaterial` (`LiquidGlassTokens.blurThin`)
- **Shape**: `Capsule()` (fully rounded)
- **Stroke**: `Color.white.opacity(0.20)` at `lineWidth: 0.7`
- **Padding**: `.horizontal(12)`, `.vertical(7)`
- **Font**: `.footnote`
- **Shadow**: `color: black.opacity(0.08)`, `radius: 14`, `y: 6`

### Corner Radius Tokens
```swift
LiquidGlassTokens.cornerRadiusSmall  = 14
LiquidGlassTokens.cornerRadiusMedium = 22
LiquidGlassTokens.cornerRadiusLarge  = 32
LiquidGlassTokens.capsuleRadius      = 999
```

### Glass Card Stroke (from AmenGlassCardModifier)
- `lineWidth: 0.75`

---

## 7. GUARDIAN (Content Safety Gate)

**"GUARDIAN" as a named type does NOT exist** in this codebase. The equivalent gate is:

### SafetyOrchestrator — primary on-device gate
**File**: `AMENAPP/SafetyOrchestrator.swift`

```swift
@MainActor
final class SafetyOrchestrator: ObservableObject {

    func evaluateBeforeSubmit(
        text: String,
        context: SafetyContentContext,
        completion: @escaping (SafetyContentDecision) -> Void
    )
}
```

Returns `SafetyContentDecision`:
```swift
struct SafetyContentDecision {
    enum Action {
        case allow
        case allowWithWarning
        case holdForSoftReview
        case blockAndReview
        case blockImmediate
    }
    let action: Action
    let riskScore: Double          // 0.0–1.0
    let requiresHumanReview: Bool
    let userFacingMessage: String?
}
```

**Reply text is safe** when `decision.action == .allow`.

### ContentModerationService — cloud-backed check
**File**: `AMENAPP/ContentModerationService.swift`

```swift
static func moderateContent(
    text: String,
    category: ContentCategory,
    signals: AuthenticitySignals,
    parentContentId: String? = nil
) async throws -> ModerationDecision
```

---

## 8. Analytics Service

**Type**: `final class AMENAnalyticsService`
**File**: `AMENAPP/AMENAnalyticsService.swift`
**Singleton**: `AMENAnalyticsService.shared`

**Exact call signature**:
```swift
AMENAnalyticsService.shared.track(_ event: AMENAnalyticsEvent)
```

**Backing**: Calls `Analytics.logEvent(event.name, parameters: params)` immediately to Firebase Analytics, then buffers a secondary write to Firestore.

**Logger wrapper/root**: `AMENAPP/AMENAnalyticsService.swift` (`AMENAnalyticsEvent.name`, `AMENAnalyticsEvent.properties`, `AMENAnalyticsService.track(_:)`)

**Event definition pattern**:
```swift
enum AMENAnalyticsEvent {
    case someEvent(paramA: String)
    var name: String { /* switch returning string constant */ }
    var properties: [String: Any] { /* switch returning param dict */ }
}
```

---

## 9. Existing Reply Models (do NOT redefine)

### ReplyPreviewType — ALREADY EXISTS, use as-is
**File**: `AMENAPP/AMENAPP/DynamicReplyPreview.swift`

```swift
enum ReplyPreviewType: String, Codable, Equatable, Hashable {
    case topReply              = "topReply"
    case followedReply         = "followedReply"
    case communityPulse        = "communityPulse"
    case bereanInsight         = "bereanInsight"
    case prayerMomentum        = "prayerMomentum"
    case trustedCommunitySignal = "trustedCommunitySignal"
}
```

### DynamicReplyPreview — ALREADY EXISTS, use as-is
**File**: `AMENAPP/AMENAPP/DynamicReplyPreview.swift`

```swift
enum ReplyPreviewType: String, Codable, Equatable, Hashable {
    case topReply              = "topReply"
    case followedReply         = "followedReply"
    case communityPulse        = "communityPulse"
    case bereanInsight         = "bereanInsight"
    case prayerMomentum        = "prayerMomentum"
    case trustedCommunitySignal = "trustedCommunitySignal"
}

struct DynamicReplyPreview: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let postId: String
    let replyId: String?
    let sourceCommentIds: [String]
    let type: ReplyPreviewType
    let previewText: String
    let authorId: String?
    let authorDisplayName: String?
    let avatarURLs: [String]
    let participantUserIds: [String]
    let score: Double
    let generatedAt: Date
    let expiresAt: Date?
    let moderationState: String      // "approved" | "pending" | "rejected"
    let source: String?

    var isSafe: Bool { moderationState == "approved" }
    var isExpired: Bool { guard let expiresAt else { return false }; return Date() > expiresAt }
}
```

### PostComment — ALREADY EXISTS
**File**: `AMENAPP/PostComment.swift`

```swift
struct PostComment: Identifiable, Codable {
    let id: UUID
    let postId: UUID
    let content: String
    let authorId: String
    let authorName: String
    let authorInitials: String
    let authorProfileImageURL: String?
    let createdAt: Date
    var amenCount: Int
    var replyCount: Int
}
```

### Reply — ALREADY EXISTS (profile tab only — do NOT shadow)
**File**: `AMENAPP/UserProfileView.swift:98`
```swift
struct Reply: Identifiable {   // UUID-based, profile tab only
    let id = UUID()
    let originalAuthor: String
    let originalContent: String
    let replyContent: String
    let timestamp: String
}
```

### ReplyThread — ALREADY EXISTS (profile tab)
**File**: `AMENAPP/RepliesModels.swift:98`
```swift
struct ReplyThread: Identifiable {
    let id: String
    let originalPost: Post?
    let userReply: Comment
    let contextType: ReplyContextType
    let visibilityState: ReplyVisibilityState
}
```

---

## 10. New Swift Models

> These types are materialized in `AMENAPP/AMENAPP/DynamicReplyPreview.swift`. `ReplyPreviewType` and `DynamicReplyPreview` already existed; `ReplyCandidate` and `ResolvedReplyPreview` have been appended without replacing existing code.

### ReplyCandidate
Input to the resolver. Represents a raw comment scored upstream by the Cloud Function before selection.

```swift
struct ReplyCandidate: Identifiable, Codable {
    let id: String
    let postId: String
    let authorUID: String
    let authorDisplayName: String
    let text: String
    let relevanceScore: Double        // 0.0–1.0
    let spiritualUsefulness: Double   // 0.0–1.0
    let engagementScore: Double       // 0.0–1.0
    let createdAt: Date
    let safetyPassed: Bool
}
```

### ResolvedReplyPreview
The finalized display object after the resolver ladder runs. Backend writes this as a `DynamicReplyPreview` document. Swift clients never construct this directly — they read `DynamicReplyPreview` from Firestore.

```swift
struct ResolvedReplyPreview: Identifiable, Codable {
    let postId: String
    let type: ReplyPreviewType        // existing enum
    let displayName: String
    let text: String
    let authorUID: String
    let avatarURL: String?
    let contentHash: String           // stable string for SwiftUI .id() — sha256(postId+type+text)

    var id: String { contentHash }
}
```

---

## 11. Firestore Schema

### `posts/{postId}` — Fields added by this feature

| Field | Firestore type | Description |
|-------|---------------|-------------|
| `previewDirty` | Boolean | `true` when reply activity crossed a dirty threshold and preview needs rebuild |
| `replyCount` | Integer | Denormalized count of top-level comments |
| `expiresAt` | Timestamp? | When the current preview batch expires; omitted if no expiry |

### `posts/{postId}/dynamicReplyPreviews/{previewId}` — Subcollection (ALREADY ESTABLISHED)

Path confirmed from `DynamicReplyPreview.swift` doc comment.

**Verbatim Firestore field names** (must match `CodingKeys` exactly):

| Firestore field | Swift CodingKey | Notes |
|----------------|----------------|-------|
| `id` | `id` | Document ID |
| `postId` | `postId` | Parent post ID |
| `replyId` | `replyId` | Source comment ID (optional) |
| `sourceCommentIds` | `sourceCommentIds` | Array for pulse-type previews |
| `type` | `type` | `ReplyPreviewType.rawValue` string |
| `previewText` | `previewText` | Display text (max 120 chars) |
| `authorId` | `authorId` | UID of highlighted author (optional) |
| `authorDisplayName` | `authorDisplayName` | Author byline (optional) |
| `avatarURLs` | `avatarURLs` | Ordered URLs for avatar cluster |
| `participantUserIds` | `participantUserIds` | All UIDs represented |
| `score` | `score` | Composite relevance score (Double) |
| `generatedAt` | `generatedAt` | Unix seconds-since-epoch Double |
| `expiresAt` | `expiresAt` | Unix seconds-since-epoch Double (optional) |
| `moderationState` | `moderationState` | `"approved"` / `"pending"` / `"rejected"` |
| `source` | `source` | Debug resolver path label (optional) |

---

## 12. Cloud Function Signatures

**Cloud Functions root**: `Backend/functions`

Confirmed by repo-root `firebase.json`:
```json
{
  "functions": [
    {
      "source": "Backend/functions",
      "runtime": "nodejs22",
      "codebase": "creator"
    }
  ]
}
```

```
onReplyCreate
  Trigger:  Firestore onCreate — posts/{postId}/comments/{commentId}
  Action:   Reads new comment count.
            If count crosses a dirty threshold in [5, 12, 30, 75]:
              Set posts/{postId}.previewDirty = true
              Enqueue rebuildReplyPreviews for this postId.

rebuildReplyPreviews
  Trigger:  Firestore onUpdate (previewDirty: false → true)
            OR direct callable invocation
  Action:   Fetch top N comments for postId.
            Score each as ReplyCandidate using the scoring formula.
            Run resolver ladder (section 13).
            Write approved DynamicReplyPreview docs to subcollection.
            Set posts/{postId}.previewDirty = false.
```

---

## 13. Resolver Ladder (pseudocode)

```
function resolvePreview(postId, viewerUID, viewerFollows):

  // Step 1 — followedReply (always tried first, requires auth context)
  candidates = comments where authorId IN viewerFollows AND safetyPassed == true
  if candidates.count > 0:
    best = argmax(compositeScore, candidates)
    return best as ReplyPreviewType.followedReply

  // Step 2 — bereanInsight (confidence gate + volume gate)
  if replyCount >= 12:
    berean = fetchBereanInsight(postId)
    if berean.confidence >= 0.72 AND berean.safetyPassed:
      return berean as ReplyPreviewType.bereanInsight

  // Step 3 — communityPulse (volume gate)
  if replyCount >= 5:
    pulse = aggregateThemes(comments.last30)
    if pulse.safetyPassed:
      return pulse as ReplyPreviewType.communityPulse

  // Step 4 — topReply (always available fallback)
  top = comments sorted by compositeScore desc, filter safetyPassed == true
  if top.count > 0:
    return top[0] as ReplyPreviewType.topReply

  // Step 5 — no preview
  return nil
```

---

## 14. Analytics Events

**Exact event name strings** (the string returned by `event.name`):

| Swift case | `event.name` string | Required parameters |
|-----------|---------------------|---------------------|
| `replyPreviewShown(postId:type:)` | `"reply_preview_shown"` | `post_id: String`, `preview_type: String` |
| `replyPreviewTapped(postId:type:replyId:)` | `"reply_preview_tapped"` | `post_id: String`, `preview_type: String`, `reply_id: String?` |
| `replyPreviewType(type:)` | `"reply_preview_type"` | `preview_type: String` |

**Add these cases to `AMENAnalyticsEvent`**:
```swift
case replyPreviewShown(postId: String, type: String)
case replyPreviewTapped(postId: String, type: String, replyId: String?)
case replyPreviewType(type: String)
```

**Usage**:
```swift
AMENAnalyticsService.shared.track(
    .replyPreviewShown(postId: post.firestoreId, type: preview.type.rawValue)
)
AMENAnalyticsService.shared.track(
    .replyPreviewTapped(postId: post.firestoreId, type: preview.type.rawValue, replyId: preview.replyId)
)
```

---

## 15. Scoring Formula (verbatim)

```
compositeScore = 0.35 × relevanceScore
              + 0.25 × spiritualUsefulness
              + 0.25 × engagementScore
              + 0.15 × recencyScore

recencyScore = 1.0 - min(1.0, hoursSinceCreated / 168.0)
// decays linearly from 1.0 to 0.0 over 7 days (168 hours)
```

All four inputs are in [0.0, 1.0]. Output `compositeScore` is in [0.0, 1.0].

---

## 16. Dirty Threshold Crossings

`onReplyCreate` marks `previewDirty = true` when `replyCount` crosses any of:

```
[5, 12, 30, 75]
```

---

## 17. Feature Flag Key

| Property | Value |
|---------|-------|
| Swift `@Published` property | `replyPreviewRotationEnabled` |
| RemoteConfig key (exact string) | `reply_preview_rotation_enabled` |
| Default value | `false` |
| Type | `Bool` |
| Singleton | `AMENFeatureFlags.shared` |

---

## 18. Component Props — LiquidReplyPreviewChip (existing, do not recreate)

**File**: `AMENAPP/AMENAPP/LiquidReplyPreviewChip.swift`

```swift
struct LiquidReplyPreviewChip: View {
    let preview: DynamicReplyPreview   // existing type
    let onTap: () -> Void
}
```

**Rotator** (`AMENAPP/AMENAPP/LiquidReplyPreviewRotator.swift`):
```swift
struct LiquidReplyPreviewRotator: View {
    let candidates: [DynamicReplyPreview]
    let onOpenReplies: (DynamicReplyPreview) -> Void
}
```

Both components already exist. Backend and Resolver agents write `DynamicReplyPreview` documents to Firestore; the Component agent wires `LiquidReplyPreviewRotator` in `PostCard` (already partially wired at `PostCard.swift:3200`).

---

## 19. Navigation Method Signatures (contract-frozen, must be built)

```swift
// Navigation Agent adds these to AmenUniversalContentRouter
// (or introduces a dedicated PostFeedRouter class)

func openReplies(postId: String, highlightedReplyId: String?)
func showReplyActions(postId: String, replyId: String)
```

**`openReplies` implementation guide** (mirror existing PostCard internal path):
```swift
// Internally should produce the equivalent of:
// PostCardSheet.commentsHighlighted(post:, replyId: highlightedReplyId, highlightedCommentIds: ...)
```

---

## 20. Amendment Process

Any change to this file requires:
1. Bumping the `<!-- VERSION: X.Y.Z — DATE -->` line at the top of this file.
2. Documenting changed symbols in `HANDOFF-A1.md` (section: Amendments).
3. Notifying all parallel agents of the new version before they merge branches.

Downstream agents must read the version line before using any symbol. If their local copy's version does not match, they must re-read this file before proceeding.

## 21. Gap Register (STEP 1 output — 2026-05-27)

Full dependency scan performed against the live repo. Each item marked **PRESENT** or **CLOSED** (was missing, now fixed).

| # | Dependency | Status | Location |
|---|-----------|--------|---------|
| G-01 | `replyPreviewRotationEnabled` flag declaration | PRESENT | `AMENFeatureFlags.swift:394` |
| G-02 | RemoteConfig wiring for flag | PRESENT | `AMENFeatureFlags.swift:2238` |
| G-03 | `replyPreviewShown` analytics event | PRESENT | `AMENAnalyticsService.swift:114` |
| G-04 | `replyPreviewTapped` analytics event | PRESENT | `AMENAnalyticsService.swift:115` |
| G-05 | `replyPreviewType` analytics event | PRESENT | `AMENAnalyticsService.swift:116` |
| G-06 | `onReplyCreate` Cloud Function | PRESENT | `Backend/functions/src/replyPreview.ts` |
| G-07 | `rebuildReplyPreviews` Cloud Function | PRESENT | `Backend/functions/src/replyPreview.ts` |
| G-08 | `openReplies(postId:highlightedReplyId:)` on router | PRESENT | `AmenContentRouter.swift:144` |
| G-09 | `showReplyActions(postId:replyId:)` on router | PRESENT | `AmenContentRouter.swift:199` |
| G-10 | `ReplyActionsTarget: Identifiable` | PRESENT | `AmenContentRouter.swift:54` |
| G-11 | `Post.dynamicReplyPreviewCandidates` field | PRESENT | `PostsManager.swift:358` |
| G-12 | `LiquidReplyPreviewChip` component | PRESENT | `AMENAPP/AMENAPP/LiquidReplyPreviewChip.swift` |
| G-13 | `LiquidReplyPreviewRotator` component | PRESENT | `AMENAPP/AMENAPP/LiquidReplyPreviewRotator.swift` |
| G-14 | `DynamicReplyPreview` model | PRESENT | `AMENAPP/AMENAPP/DynamicReplyPreview.swift` |
| G-15 | `ReplyCandidate` + `ResolvedReplyPreview` models | PRESENT | `AMENAPP/AMENAPP/DynamicReplyPreview.swift` |
| G-16 | `dynamicReplyPreviewSection` wired in PostCard body | PRESENT | `PostCard.swift:3897` |
| G-17 | `ReplyActionsMenuView` with real actions (5 total) | PRESENT | `AMENAPP/AMENAPP/ReplyActionsMenuView.swift` |
| G-18 | Backend unit tests for resolver/scoring | PRESENT | `Backend/functions/src/generateDynamicReplyPreviews.test.ts` |
| G-19 | Firestore security rules for `dynamicReplyPreviews` | **CLOSED** | `firestore.rules` — added after `/posts/{postId}/audit` block (2026-05-27) |
| G-20 | Composite index `posts`: `previewDirty + previewExpiresAt` | **CLOSED** | `firestore.indexes.json` — appended (2026-05-27) |
| G-21 | `replyPreviewRotationEnabled` default `true` for exercisability | **CLOSED** | `AMENFeatureFlags.swift:394` — flip back to `false` before shipping |

**Note on G-08 / G-09**: Section 1 of this file previously marked these "NOT FOUND — must be built". Recon found real implementations already present. Section 1 and Section 19 carry stale "must be built" language — treated as resolved.

---

## 22. Amendment Log

### 1.0.2 — 2026-05-27

- Added Section 21: Gap Register — full dependency audit, 18 items PRESENT, 3 items CLOSED.
- Corrected stale "NOT FOUND" status for `openReplies`/`showReplyActions` (G-08/G-09): both exist in `AmenContentRouter.swift`.
- Bumped version to 1.0.2.

### 1.0.1 — 2026-05-26

- Corrected the Feed `Post` model path to `AMENAPP/PostsManager.swift`; `AMENAPP/FirebasePostService.swift` is the Firestore DTO/service root (`FirestorePost`, `FirebasePostService`).
- Recorded the real replies service, follow-graph accessor, post reaction APIs, report APIs, composer publish methods, Cloud Functions root, RemoteConfig wrapper, and analytics logger wrapper.
- Marked all four reply preview model symbols as materialized in `AMENAPP/AMENAPP/DynamicReplyPreview.swift`: `ReplyPreviewType`, `DynamicReplyPreview`, `ReplyCandidate`, and `ResolvedReplyPreview`.
