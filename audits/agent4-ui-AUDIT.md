# Agent 4 — Comments UI Audit
**Date:** 2026-05-27  
**Scope:** Display, animation, performance — no schema changes, no breaking layout changes

---

## PHASE 1 — AUDIT FINDINGS

### 1. Comment View Inventory

There are **5 distinct comment view implementations** in the iOS codebase. They are divergent and share no common base component.

| View | File | Backend | Use Case |
|---|---|---|---|
| `PostCommentRow` (private) + `CommentsView` | `AMENAPP/CommentsView.swift` | RTDB | Primary post comments (main app) |
| `CommentThreadCard` / `CommentCard` / `FullCommentsView` | `AMENAPP/AMENAPP/CommentsViews.swift` | RTDB | Secondary sheet (testimonies/legacy) |
| `ThreadedCommentsView` / `ThreadedCommentCell` | `AMENAPP/CommentThreadsEnhancement.swift` | Firestore | Enhancement layer (not wired to main flow) |
| `ChurchNoteCommentsView` | `AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteCommentsView.swift` | Firestore | Church notes feature |
| `VoicePrayerCommentsSection` / `VoicePrayerCommentRowView` | `AMENAPP/AMENAPP/VoicePrayer/*.swift` | Firestore | Voice prayer/testimony comments |

**Consistency verdict: DIVERGENT.** Each implementation has its own typography, avatar sizing, action rows, and animation behavior. No shared `CommentRowProtocol` or design token constants.

---

### 2. Threading Depth Limit

**Current behavior:** There is NO explicit depth cap.

- In `CommentsView.swift`: `expandedRepliesSection(for:)` at line 1943 renders `commentWithReplies.replies` as a flat array — all replies are rendered at the same visual level regardless of their `parentCommentId`.
- The data model (`Comment.parentCommentId`) supports arbitrary nesting, but the UI renders ALL replies to a top-level comment at one flat level — effectively a soft 2-level cap by data model convention.
- **Reply-to-reply is NOT visually distinguished** from reply-to-top-level. `replyRow(_:parent:)` at line 1897 always uses the top-level parent comment as the `parent` argument, so a reply-to-reply is displayed identically to a direct reply.
- In `CommentsViews.swift` (`CommentThreadCard`): replies are rendered via `ForEach(comment.replies)` with no depth tracking. No nesting cap exists — technically supports unlimited nesting if the `TestimonyComment.replies` array contains nested replies.
- **ThreadedCommentsView** (CommentThreadsEnhancement.swift line 330): Renders `commentWithReplies.replies` directly. The thread line visual is correct but there is no guard against nested replies within `replies`.

**Finding:** The primary CommentsView has implicit 2-level behavior (data model does it), but CommentsViews.swift and CommentThreadsEnhancement.swift have no guard. No visual hairline rail exists in the primary view.

---

### 3. Current Sizing vs. Spec

**Primary view (`PostCommentRow` in CommentsView.swift):**

| Element | Current Value | Spec | Match? |
|---|---|---|---|
| Body font | `OpenSans-Regular` size 14 (top-level), 13 (reply) | 15pt regular | ❌ Wrong (14 vs 15) |
| Body color | `.primary` | `.primary` | ✅ |
| Author name font | `OpenSans-SemiBold` size 14 (top-level), 13 (reply) | 13pt semibold | ❌ Wrong (14 vs 13 top-level) |
| Author name color | `.primary` | `.primary` | ✅ |
| Timestamp font | `OpenSans-Regular` size 12 (reply), 12 (top) | 12pt regular | ✅ |
| Timestamp color | `.black.opacity(0.5)` (not adaptive) | `.secondary` | ❌ Hardcoded, dark-mode broken |
| Avatar top-level | 36pt × 36pt | 36pt | ✅ |
| Avatar reply | 28pt × 28pt | 28pt | ✅ |
| Reply indent | `.padding(.horizontal, 12)` on reply + 28pt thread line leading | 12pt left + 1pt hairline | ✅ (indent ok, hairline = 2pt Rectangle filled black.opacity(0.1) — close but not spec color) |
| Reaction pills | `hands.sparkles` heart button — no pill shape | 24pt height, 12pt corner radius, 11pt semibold | ❌ No spec-compliant reaction pill; uses flat icon+count |
| Top-level comment padding | `.padding(.vertical, 8)` on the VStack wrapper (line 663) | 16pt between top-level | ❌ 8pt not 16pt |
| Reply padding | `spacing: 0` in `expandedRepliesSection` | 10pt | ❌ 0pt not 10pt |

**CommentsViews.swift (`CommentThreadCard.commentContentView`):**

| Element | Current Value | Spec | Match? |
|---|---|---|---|
| Body font | `OpenSans-Regular` 14/13 | 15pt | ❌ |
| Author font | `OpenSans-SemiBold` 14/13 | 13pt semibold | ❌ |
| Timestamp font | `AMENFont.regular(13)` | 12pt | ❌ |
| Avatar top-level | 40pt | 36pt | ❌ Over-sized |
| Avatar reply | 32pt | 28pt | ❌ Over-sized |

---

### 4. Animations

**CommentsView.swift (primary):**

| Event | Current Animation | Spec | Match? |
|---|---|---|---|
| New comment insert (optimistic) | `withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)))` — wraps array mutation. No `.transition()` on `LazyVStack` items. The `mainCommentRow` has `.transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .scale.combined(with: .opacity)))` | opacity 0→1 + offset y:12→0, spring(0.4, 0.85) | ❌ Uses `.scale` not `.offset(y:12)`. Response/damping close but not spec. |
| Real-time insert (RTDB push) | `updateCommentsFromService()` rebuilds `commentsWithReplies` array; SwiftUI diffs `LazyVStack`. No explicit animation wrapping the update. The notification handler at line 1403 uses `Task { @MainActor in }` with no `withAnimation`. | Animate in | ❌ No animation on real-time inserts |
| Comment delete | `withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8)))` wraps `deleteComment` | `.opacity` removal | ✅ (has animation) |
| Reaction tap (amen) | `.spring(response: 0.3, dampingFraction: 0.5)` scale + `.scaleEffect(hasAmened ? 1.15 : 1.0)` on heart icon | scale 1.0→1.3→1.0, spring(0.35, 0.7) | ❌ Only scale to 1.15, spring params differ |
| Reply expand/collapse | `withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.75)))` | Not specified | ✅ |
| Reduce Motion | NOT implemented in primary view. `@Environment(\.accessibilityReduceMotion)` is absent from `PostCommentRow`, `CommentsView`, `CommentThreadCard`. | All animations wrapped | ❌ Missing |

**VoicePrayerCommentRowView.swift:** Has `@Environment(\.accessibilityReduceMotion)` ✅ — this is the ONLY comment view that respects Reduce Motion.

---

### 5. Performance

**CommentsView.swift:** Uses `LazyVStack(spacing: 0)` inside `ScrollView` at line 630. ✅ Virtualized.

- Each top-level comment has `.id(commentWithReplies.comment.id ?? UUID().uuidString)` ✅
- `replyRow` entries use `.id(replyRowID(for: reply))` ✅
- **However:** The `expandedRepliesSection` renders ALL replies in a plain `VStack(spacing: 0)` (not lazy). If a thread has 200+ replies, all are materialized simultaneously. This is a **performance hazard for large threads**.
- **Participants rebuild** is debounced at 250ms via `participantsRebuildTask`. ✅
- `rebuildTopParticipants()` is O(n²) — iterates all comments × replies. At 200+ comments with 50+ replies each, this could be slow (10,000+ iterations). Acceptable at current scale.

**CommentsViews.swift (FullCommentsView):** Uses `LazyVStack(spacing: 16)` ✅ inside `ScrollView`.

**ChurchNoteCommentsView:** Uses `List` + `ForEach` inside sections. ✅ (List is virtualized).

**VoicePrayerCommentsSection:** Uses `VStack(spacing: 0)` — **not lazy**. Limited to 50 items by Firestore query `.limit(to: 50)` which is acceptable.

**200+ comment estimate:**
- Primary `CommentsView`: top-level list is lazy. Replies within an expanded thread are NOT lazy. For a typical thread of 200 comments each with 5 replies, the lazy list handles 200 rows. Once a thread is expanded, up to 200 reply rows materialize. Likely 30–45fps on A15+, drops to ~25fps on A13 with many expanded threads.

---

### 6. Pagination

**CommentsView.swift:** Starts a real-time RTDB listener via `startRealtimeListener()`. No explicit load-more / pagination UI exists. The RTDB listener at `CommentService.startListening()` uses `queryLimited(toLast:)` for the initial load, but `updateCommentsFromService()` at line 2000+ (not shown fully) replaces the full array each time. No "load more" button or cursor-based pagination is implemented. **All comments in the listener window load at once.** This is a scalability concern for posts with 500+ comments.

---

### 7. Real-time Inserts

**CommentsView.swift:**
- RTDB listener posts `Notification.Name("commentsUpdated")`.
- `onReceive` at line 1394 calls `updateCommentsFromService()` with no animation wrapper.
- New comments are tracked in `newCommentIds: Set<String>` — set in `updateCommentsFromService` — but the `PostCommentRow` only uses `isNew` to reflect a boolean prop; no animation is applied based on it in the view body.
- **Scroll position:** The `showJumpToLatest` state at line 1391 computes whether the user is at the bottom, and sets a pill visible. The `JumpToLatestPill` overlay exists at line 731 behind `LiquidGlassEffectsFlags.jumpToLatestPill`. **This flag IS used** — scroll hijack prevention already exists but is behind a feature flag.
- **"New comments" floating pill:** `JumpToLatestPill` at line 731 shows "↑ Jump to latest" when `showJumpToLatest` is true. This is close to spec but shows count only via `commentsWithReplies.count`. Does NOT show "↑ N new" with specific count.
- Real-time inserts do NOT animate in (no transition on `updateCommentsFromService` path).

---

## PHASE 2 — SAFE FIXES APPLIED

### Fix Summary

| # | Fix | File | Status |
|---|---|---|---|
| F1 | Typography: body 14→15pt, author 14→13pt (top-level), timestamp to `.secondary` | `CommentsView.swift` (PostCommentRow) | ✅ Applied |
| F2 | Reduce Motion support in PostCommentRow | `CommentsView.swift` (PostCommentRow) | ✅ Applied |
| F3 | Insert animation: `.offset(y:12)` + `.opacity`, spring(0.4, 0.85) | `CommentsView.swift` (mainCommentRow) | ✅ Applied |
| F4 | Real-time insert animation: wrap `updateCommentsFromService` call with animation | `CommentsView.swift` | ✅ Applied |
| F5 | Reaction tap scale 1.0→1.3→1.0, spring(0.35, 0.7) | `CommentsView.swift` (PostCommentRow.actionsRow) | ✅ Applied |
| F6 | Reply indent hairline rail: 1pt, adaptive color | `CommentsView.swift` (replyRow) | ✅ Applied |
| F7 | Top-level comment vertical padding: 8→16pt | `CommentsView.swift` (main LazyVStack) | ✅ Applied |
| F8 | Reply VStack spacing: 0→10pt | `CommentsView.swift` (expandedRepliesSection) | ✅ Applied |
| F9 | LazyVStack for replies (within expanded thread, behind featureFlag) | Flagged 🟡 — see DEFERRED |
| F10 | Typography fixes in CommentsViews.swift (CommentThreadCard) | `CommentsViews.swift` | ✅ Applied |

---

## PHASE 3 — VERIFICATION

### Files Changed
1. `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/CommentsView.swift`
2. `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/AMENAPP/CommentsViews.swift`

### Manual QA Checklist

#### Reduce Motion OFF (normal)
- [ ] Post a new comment → should animate in: opacity 0→1 AND slide up from y:12, spring(response:0.4, dampingFraction:0.85)
- [ ] Receive real-time comment from another device → same insert animation
- [ ] Tap heart/amen → heart icon should scale 1.0→1.3→1.0 with spring(response:0.35, dampingFraction:0.7)
- [ ] Expand a reply thread → replies slide down from top with spring(0.35, 0.75)
- [ ] Collapse a reply thread → replies fade + move to top
- [ ] Delete comment → fades out with spring removal

#### Reduce Motion ON (Settings > Accessibility > Reduce Motion)
- [ ] Post a new comment → opacity fade only (0.15s), no offset/slide
- [ ] Receive real-time comment → opacity fade only, no offset
- [ ] Tap heart/amen → opacity toggle only, no scale effect
- [ ] Expand reply thread → instant or short opacity fade, no slide

#### Typography verification
- [ ] Top-level comment body text: 15pt regular, `.primary` color
- [ ] Reply comment body text: 13pt, `.primary` color
- [ ] Author name top-level: 13pt semibold, `.primary`
- [ ] Timestamp: 12pt regular, `.secondary` (adaptive — must look correct in dark mode)
- [ ] Avatar top-level: 36pt circle ✅
- [ ] Avatar reply: 28pt circle ✅

#### Reply indent hairline rail
- [ ] Expanded reply rows have a 1pt vertical hairline to the left of the reply content
- [ ] Hairline is `Color.primary.opacity(0.08)` in light mode, `amenGold.opacity(0.2)` in dark mode

#### Spacing
- [ ] 16pt vertical gap between top-level comments
- [ ] 10pt vertical gap between replies within an expanded thread

#### Jump-to-Latest pill
- [ ] Scroll up while comments arrive → "Jump to latest" pill appears at bottom-right
- [ ] Tap pill → scrolls to bottom without interrupting reading position
- [ ] (Behind `LiquidGlassEffectsFlags.jumpToLatestPill` flag — must be ON to see)

---

## Deferred Items (flagged to DEFERRED_FIXES.md)

- **🟡 F9-LAZY-REPLIES:** Switch expanded reply `VStack` to `LazyVStack` behind `featureFlags.commentsLiquidGlassV2`. Requires testing to ensure `.id()` keying still works correctly with `LazyVStack` and reply insertions.
- **🟡 AVATAR-SIZE-COMMENTSVIEWS:** `CommentThreadCard` in `CommentsViews.swift` uses 40pt (top) / 32pt (reply) avatars vs spec 36pt / 28pt. Flagged behind `featureFlags.commentsLiquidGlassV2` to avoid breaking the secondary sheet layout.
- **🟡 NEW-COMMENTS-PILL-COUNT:** The existing `JumpToLatestPill` shows "Jump to latest" but not "↑ N new". Adding a new-comment count requires tracking insertions separately. Flag as `featureFlags.commentsNewCommentPill`.
- **🔴 UICOLLECTIONVIEW:** Switching to UIKit UICollectionView for infinite-scale comment lists. Defer until SwiftUI LazyVStack tuning is confirmed insufficient.
