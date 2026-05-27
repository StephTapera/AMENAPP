# HANDOFF-A3 — reply-preview-component agent
<!-- DATE: 2026-05-26 -->
<!-- CONTRACT VERSION: 1.0.1 -->

## Summary

Wired `LiquidReplyPreviewRotator` into `PostCard.swift` as the component-agent (A3)
deliverable for the LiquidReplyPreviewRotation feature. All prerequisite infrastructure
(feature flag, analytics events, router methods, component views) was already present;
this agent applied targeted corrections and completions to the partial wiring.

---

## 1. Exact Line — Rotator Insertion Point

**File**: `AMENAPP/PostCard.swift`

| Symbol | Lines |
|--------|-------|
| `dynamicReplyPreviewSection` `@ViewBuilder` declaration | **3215–3279** |
| Called from `cardContent` VStack | **3870** |

Position in layout: after `safetyOSReactionSection` (line 3868), before `postInteractionSection`
(line 3872) — below all post content and above the action bar.

---

## 2. Flag Guard Expression

```swift
if AMENFeatureFlags.shared.replyPreviewRotationEnabled,
   let post {
    let candidates = post.dynamicReplyPreviewCandidates ?? []
    if !candidates.isEmpty {
        LiquidReplyPreviewRotator(...)
    } else {
        Color.clear.frame(height: 44) // reserved-height placeholder
    }
}
```

- **Flag property**: `AMENFeatureFlags.shared.replyPreviewRotationEnabled`
- **RemoteConfig key**: `reply_preview_rotation_enabled`
- **Default**: `false`
- **Location of declaration**: `AMENAPP/AMENFeatureFlags.swift` line 391

---

## 3. Analytics Calls Added

### Component level (LiquidReplyPreviewChip.swift — pre-existing, no edit required)

```swift
// .onAppear
AMENAnalyticsService.shared.track(
    .replyPreviewShown(postId: preview.postId, type: preview.type.rawValue)
)
AMENAnalyticsService.shared.track(
    .replyPreviewType(type: preview.type.rawValue)
)

// .onTapGesture
AMENAnalyticsService.shared.track(
    .replyPreviewTapped(postId: preview.postId, type: preview.type.rawValue, replyId: preview.replyId)
)
```

### PostCard level (openReplyPreview(_:for:) — pre-existing, retained)

```swift
AMENAnalyticsService.shared.track(
    .replyPreviewTapped(postId: preview.postId, type: preview.type.rawValue, replyId: preview.replyId)
)
```

All three `AMENAnalyticsEvent` cases (`replyPreviewShown`, `replyPreviewTapped`,
`replyPreviewType`) were already defined in `AMENAPP/AMENAnalyticsService.swift` — no
additions needed.

---

## 4. Layout Notes

### Reserved height

When `replyPreviewRotationEnabled == true` and `candidates` is empty (feature ON,
server not yet populated), a `Color.clear` placeholder holds the slot:

```swift
Color.clear
    .frame(height: 44)
    .padding(.horizontal, 16)
    .padding(.top, 6)
    .padding(.bottom, 2)
```

When candidates are present the rotator gets the same `44`-pt frame:

```swift
LiquidReplyPreviewRotator(...)
    .id(resolvedPreview?.generatedAt)
    .frame(height: 44)
    .padding(.horizontal, 16)
    .padding(.top, 6)
    .padding(.bottom, 2)
```

When the flag is `false` the entire `dynamicReplyPreviewSection` collapses to
`EmptyView` — no slot reserved, card layout is byte-identical to the pre-feature state.

### Crossfade mechanism

```swift
.id(resolvedPreview?.generatedAt)
```

`resolvedPreview` (computed property, line 3202) mirrors the rotator's own top-scored
candidate selection. When the server writes a newer `DynamicReplyPreview` with a new
`generatedAt` timestamp, SwiftUI tears down and recreates the rotator view, producing a
crossfade. The rotator additionally applies `.id(contentHash)` to the chip internally,
preventing spurious animations within the same server generation.

---

## 5. Stub Left for A4 — openReplies

The `onOpenReplies` callback routes through:

```swift
AmenUniversalContentRouter.shared.openReplies(
    postId: post.firestoreId,
    highlightedReplyId: preview.replyId
)
```

`openReplies(postId:highlightedReplyId:)` **was already implemented** by the Navigation
agent in `AMENAPP/AmenContentRouter.swift` (line 144). No stub was required.

Per contract instruction, if A4's implementation is absent on a parallel branch, replace
with:

```swift
// TODO(A4): openReplies — wired by navigation agent
```

---

## 6. Changes Made

### `AMENAPP/PostCard.swift` — `dynamicReplyPreviewSection` (lines 3215–3279)

| Before | After |
|--------|-------|
| `onOpenReplies` called `openReplyPreview(_:for:)` (local, sheet-based) | `onOpenReplies` calls `AmenUniversalContentRouter.shared.openReplies(postId:highlightedReplyId:)` |
| No `.id()` on the rotator | `.id(resolvedPreview?.generatedAt)` added for SwiftUI crossfade |
| `.frame(minHeight: resolvedPreview != nil ? 44 : 0)` — conditional | `.frame(height: 44)` — always 44 pt when candidates present |
| No reserved-height placeholder when candidates empty | `Color.clear.frame(height: 44)` `else` branch added |
| Single `if` with guard on `!candidates.isEmpty` | Two-branch `if`/`else` inside outer `if replyPreviewRotationEnabled` |

---

## 7. Files Read (no changes)

| File | Purpose |
|------|---------|
| `CONTRACT.md` | Feature spec, contract version 1.0.1 |
| `AMENAPP/AMENAPP/LiquidReplyPreviewChip.swift` | Component API + analytics already wired |
| `AMENAPP/AMENAPP/LiquidReplyPreviewRotator.swift` | Rotator API + internal crossfade mechanism |
| `AMENAPP/AMENAPP/PostCardRenderModel.swift` | Confirmed `dynamicReplyPreviewCandidates: [DynamicReplyPreview]` at line 106 |
| `AMENAPP/AMENFeatureFlags.swift` | Confirmed `replyPreviewRotationEnabled` flag + RemoteConfig binding |
| `AMENAPP/AMENAnalyticsService.swift` | Confirmed all three analytics events pre-exist |
| `AMENAPP/AmenContentRouter.swift` | Confirmed `openReplies` + `showReplyActions` already implemented |
| `AMENAPP/AMENAPP/ReplyActionsMenuView.swift` | Confirmed exists for long-press sheet |
