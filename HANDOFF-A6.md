# HANDOFF-A6 — Integration Agent Output

**Agent**: A6 (Integration Agent)
**Date**: 2026-05-26
**Contract version read**: 1.0.1

---

## Summary

A6 audited all prior agent work (A3–A5) and made one targeted set of changes to `PostCard.swift`. `LiquidReplyPreviewRotator.swift` required no edits — A4 had already completed it correctly.

---

## Files Modified

### `AMENAPP/PostCard.swift`

#### Change 1 — Added `resolvedPreview` computed property (line ~3199)

New private computed property inserted directly above `dynamicReplyPreviewSection`:

```swift
private var resolvedPreview: DynamicReplyPreview? {
    guard AMENFeatureFlags.shared.replyPreviewRotationEnabled,
          let candidates = post?.dynamicReplyPreviewCandidates,
          !candidates.isEmpty else { return nil }
    return candidates
        .filter { $0.isSafe && !$0.isExpired }
        .sorted { $0.score > $1.score }
        .first
}
```

**Purpose**: Provides a stable, synchronous, render-time value that drives the `minHeight` frame slot without any async work, timer, or `@State` mutation. Returns `nil` when the flag is off, so the frame slot collapses to zero under flag-off conditions.

**Why `DynamicReplyPreview` rather than `ResolvedReplyPreview`**: `post.dynamicReplyPreviewCandidates` is `[DynamicReplyPreview]` — the already-backend-resolved Firestore documents. `ReplyPreviewResolver` (A3) takes `[ReplyCandidate]` (raw upstream-scored objects that exist only in the backend pipeline). These are different types at different pipeline stages. The client selection step (filter safe + unexpired, sort by score, take first) mirrors exactly what `LiquidReplyPreviewRotator.safeCandidates.first` computes, ensuring `resolvedPreview != nil` whenever the rotator will render a chip.

#### Change 2 — Added `.frame(minHeight:)` slot (line ~3237)

```swift
.frame(minHeight: resolvedPreview != nil ? 44 : 0)
```

Added directly after the `LiquidReplyPreviewRotator(...)` closing parenthesis, before the `.padding` chain. Reserves a stable 44-point vertical slot when a chip will render, preventing feed scroll jumps as chips crossfade.

#### Change 3 — Fixed `onLongPress` postId source (line ~3228)

Minor correction in the `onLongPress` closure: changed `preview.postId` to `post.firestoreId` as the `postId` argument to `AmenUniversalContentRouter.shared.showReplyActions`. Both resolve to the same string for well-formed candidates, but using `post.firestoreId` is authoritative at the card level and avoids relying on `DynamicReplyPreview.postId` being consistent with the card's identity.

---

## Files Confirmed (No Edits Needed)

### `AMENAPP/AMENAPP/LiquidReplyPreviewRotator.swift`

All A4-specified changes are present and correct:

| Item | Status |
|------|--------|
| Feature flag guard (`guard AMENFeatureFlags.shared.replyPreviewRotationEnabled else { return AnyView(EmptyView()) }`) | CONFIRMED at line 43 |
| Stable `contentHash` string (`"\(preview.postId)|\(preview.type.rawValue)|\(preview.previewText)"`) | CONFIRMED |
| `.id(hash).transition(.opacity)` crossfade | CONFIRMED |
| No client-side timer or async carousel loop | CONFIRMED — content hash changes are 100% server-driven |
| `onLongPress: (DynamicReplyPreview) -> Void = { _ in }` parameter | CONFIRMED |
| `LiquidReplyPreviewChip(preview:onTap:onLongPress:)` wiring | CONFIRMED |

### `AMENAPP/PostCard.swift` — A5-provided wiring

| Item | Status |
|------|--------|
| `@State private var localReplyActionsTarget: ReplyActionsTarget?` | CONFIRMED at line 133 |
| `onLongPress` closure calling `AmenUniversalContentRouter.shared.showReplyActions` | CONFIRMED |
| `.sheet(item: $localReplyActionsTarget)` presenting `ReplyActionsMenuView` | CONFIRMED |
| `.onReceive($replyActionsTarget)` scoped to `target.postId == post.firestoreId` | CONFIRMED |
| `.onDisappear` clearing `AmenUniversalContentRouter.shared.replyActionsTarget = nil` | CONFIRMED |

### `AMENAPP/AMENFeatureFlags.swift`

| Item | Status |
|------|--------|
| `@Published private(set) var replyPreviewRotationEnabled: Bool = false` | CONFIRMED at line 391 |
| `replyPreviewRotationEnabled = config["reply_preview_rotation_enabled"].boolValue` | CONFIRMED at line 2205 |

---

## `followedUserIds` Accessor

**Not used in PostCard directly.** `resolvedPreview` is computed from `DynamicReplyPreview` candidates (already-resolved Firestore documents), which does not require the viewer's follow graph at render time. The follow-graph ranking was performed by the backend `rebuildReplyPreviews` Cloud Function before writing these documents to Firestore.

If a future integration requires client-side follow-graph filtering (e.g., for a `followedReply`-preferencing override), the accessor to use is:

- **Property**: `FollowService.shared.following` — `@Published var following: Set<String>`
- **Source file**: `AMENAPP/FollowService.swift`, line 50

This is the value the CONTRACT.md §3 specifies for the resolver's `viewerFollows` parameter.

---

## Flag-Off Layout Invariant

When `AMENFeatureFlags.shared.replyPreviewRotationEnabled == false`:

1. `resolvedPreview` returns `nil` (first `guard` fails on the flag).
2. `dynamicReplyPreviewSection` exits the `if` block immediately (outer condition checks the flag), rendering nothing from `@ViewBuilder`.
3. The `.frame(minHeight: resolvedPreview != nil ? 44 : 0)` resolves to `.frame(minHeight: 0)` — which is only reached when the flag IS on (because it's inside the flag-gated `if` block). When the flag is off, the entire section renders nothing, so the frame modifier is not applied at all.
4. `LiquidReplyPreviewRotator.body` returns `AnyView(EmptyView())` via its own guard as a secondary defense.
5. No other layout changes occur — the `VStack` in `cardContent` at line 3852 emits nothing for `dynamicReplyPreviewSection`, exactly matching pre-feature behavior.

---

## Crossfade / Task Guard Audit

- No `.task` modifier is attached to `dynamicReplyPreviewSection` or the `LiquidReplyPreviewRotator` call.
- The card body calls `dynamicReplyPreviewSection` as a `@ViewBuilder` computed property inside a `VStack` — no async lifecycle method wraps it.
- The only `.task` modifiers in PostCard scope (lines 511, 2424, 2554, 2557, 6224, 6752) are for unrelated features (profile image sync, follow state, translation, safety OS analysis, interactions, prayer room). None of them write to `post.dynamicReplyPreviewCandidates`.
- `resolvedPreview` is a plain computed property with no storage — it is computed fresh each time SwiftUI evaluates `dynamicReplyPreviewSection`, which only happens when `post` itself changes (stable per Firestore document identity). There is no risk of re-creating the rotator with a new id mid-scroll.

---

## Deferred to A7 (Verification Agent)

| Item | Notes |
|------|-------|
| Confirm `ReplyActionsMenuView.swift` compiles cleanly against `ReplyActionsTarget` | A5 created both; A6 confirmed the wiring in PostCard but did not run a build |
| Confirm `ReplyPreviewResolver.swift` is added to the Xcode target (`project.pbxproj`) | A3 flagged this as outstanding |
| Confirm `ReplyPreviewResolverTests.swift` is added to `AMENAPPTests` target | A3 flagged this as outstanding |
| End-to-end: long-press chip → `ReplyActionsMenuView` sheet appears only for that card | Requires device/simulator run |
| Flag-off smoke test: toggle `replyPreviewRotationEnabled` to `false` via RemoteConfig and confirm no layout shift in feed | Requires device/simulator run |
| A5 Gap 2: `openReplies` uses NotificationCenter; no host view (`HomeView`, `ProfileView`) subscribes yet | Future work item for host view owners |
| A5 Gap 1: `reportComment` fallback to `reportPost` due to missing `replyAuthorId` on `ReplyActionsTarget` | Future: extend `ReplyActionsTarget` to carry `replyAuthorId: String?` |
