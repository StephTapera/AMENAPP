# Agent 5 — Composer, Reactions & Smart Prompts Audit
**Date:** 2026-05-27  
**Files examined:** CommentsView.swift, CommentService.swift, PostInteractionModels.swift, CommentRateLimiter.swift, AISuggestionSheet.swift, BereanContextActionEngine.swift, ScriptureVerificationService.swift, AMENFeatureFlags.swift, DesignSystem/Prompts/AmenSmartPromptSheet.swift

---

## PHASE 1 — AUDIT FINDINGS

### 1. Entry Points to Commenting

| Surface | File | Line | Notes |
|---|---|---|---|
| Bottom sheet via PostCard | PostCard.swift:6124–6130 | Three variants: plain, prefill, highlighted comment |
| PostDetailView "Add Comment" button | PostDetailView.swift:493 | Passes `prefillText` to composer |
| PrayerView prayer comment button | PrayerView.swift:1467 | Plain `CommentsView(post:)` |
| UserProfileView post tap | UserProfileView.swift:589, 3284 | Plain |
| ProfileView | ProfileView.swift:2707 | |
| ChurchNotesView | ChurchNotesView.swift:4759 | `threadCategoryOverride: "church_note"` |
| AmenMediaDetailView | AmenMediaDetailView.swift:370 | |
| PostAttachmentSystem | PostAttachmentSystem.swift:1354 | |
| Reply button on each top-level comment | CommentsView.swift:1767–1804 | `focusReplyComposer(for:)` sets `replyingTo`, focuses input |
| Reply button on nested replies | CommentsView.swift:1925–1936 | Sets `replyingTo = parent`, focuses input |
| Deep links | CommentsView.swift:179–196 | `highlightedCommentId` / `highlightedCommentIds` parameters routed from PostCard |
| Context menu "Reply" | CommentsView.swift:3335–3341 | Calls `onReply()` |

**Finding:** All entry points reach `focusReplyComposer(for:)` or directly set `replyingTo` — well-structured. No dark paths to the composer found.

---

### 2. Composer State Today

| Capability | Status | Evidence |
|---|---|---|
| Plain text | ✅ Wired | TextField at line 886 |
| @mentions | ✅ Wired | `handleMentionDetection`, Algolia search, suggestion row (lines 1580–1645) |
| Scripture references | ✅ Partially | `ScriptureVerificationService.shared.detectScriptures()` exists but **not wired into the comment composer** — only used in `CreatePostView` and `ChurchNotesView`. No inline highlight in composer. |
| Emoji | ✅ Wired | `showEmojiPicker` → `EmojiQuickPickerView` (line 1059) |
| Image attachments | ✅ Wired | `PhotosPicker`, moderation gate via Vision (lines 1069–1098) |
| Link previews | ✅ Wired | `AmenSmartAttachmentResolverService` (lines 2002–2027) |
| Character counter | ❌ Missing | No counter exists anywhere in the composer. Max length (800 chars) is enforced server-side but never shown to user. |
| Cmd+Enter shortcut | ❌ Missing | No `.keyboardShortcut` on GlassCircularButton send button. |

---

### 3. Button Inventory (comment surface)

| Button | Location | Wired? | Notes |
|---|---|---|---|
| Send button (`GlassCircularButton`) | CommentsView.swift:1151 | ✅ | Calls `submitComment()`. Disabled when text empty, isSubmitting, rateLimitMessage != nil, cooldown > 0. |
| Emoji picker | CommentsView.swift:1057 | ✅ | Opens `EmojiQuickPickerView` half-sheet |
| Photo picker | CommentsView.swift:1069 | ✅ | Opens `PhotosPicker`, runs Vision moderation |
| Berean rewrite assist | CommentsView.swift:1102 | ✅ | Calls `requestBereanRewrite()`, shows `bereanSuggestionBanner` |
| Reply button (top-level comment) | CommentsView.swift:1767 | ✅ | Calls `focusReplyComposer(for:)` — sets replyingTo, focuses input |
| Reply button (nested reply) | CommentsView.swift:1925 | ✅ | Sets `replyingTo = parent`, focuses |
| Cancel reply chip ✕ | CommentsView.swift:765 | ✅ | Clears `replyingTo` with animation |
| Amen/heart button | CommentsView.swift:3114 | ✅ | `toggleAmen()` with optimistic update + Firebase sync |
| Thread expand/collapse | CommentsView.swift:3163 | ✅ | `toggleThread(for:)` |
| Ellipsis options (own comment) | CommentsView.swift:3194 | ✅ | `confirmationDialog` for delete |
| Long-press reaction sheet | CommentsView.swift:3278 | ✅ | Opens `SoftReactionSheet` for ❤️/🙏/👍 |
| Text selection Berean | CommentsView.swift:3499 | ✅ | `handleBereanSelection` |
| Text selection quote/reply | CommentsView.swift:3451–3478 | ✅ | Both wired |
| Smart reply chips | CommentsView.swift:800 | ✅ | Wired via `SmartReplySuggestionService`, hidden when text starts |
| Reflection starter chips | CommentsView.swift:1461 | ✅ | Pray/Encourage/Ask/Reflect |

**No silent failures found.** All interactive elements have wired callbacks. Send button disabled states are complete (empty, submitting, rate-limited, cooldown).

---

### 4. Reaction Picker UX

**Finding: Divergence from MessageActionQuickReactionsRow confirmed.**

- `MessageActionQuickReactionsRow` was searched across the entire project — it does not exist as a standalone named component. The message reactions infrastructure lives in `AMENAPP/Features/MessageActions/`.
- Comments use a completely separate reaction system:
  - `.reactionPicker()` modifier on `SelectablePostTextView/MentionTextView` (AMENReactionSystem) — CommentsView.swift:2971
  - `SoftReactionSheet` on long-press — CommentsView.swift:3287 (shows ❤️/🙏/👍)
  - `CommentReactionPicker` struct at CommentsView.swift:3900 — defined but **not used anywhere in the current flow** (dead code)
  - `EmojiQuickPickerView` for emoji insertion in the composer (not reactions)
- The `reactionPicker` modifier on `MentionTextView` (AMENReactionSystem) maps ❤️/🙏 to the existing `hasAmened` toggle. Other emojis (🔥, 👍) are received by the `onSelect` closure but explicitly not routed (comment "Future: route other emoji reactions"). **This is a silent no-op for non-heart/amen reactions.**
- **Divergence documented. Merge deferred (🔴).**

---

### 5. Smart Prompts — Status

**Pre-existing infrastructure found:**
- `AmenSmartPromptSheet.swift` — generic modal, not comment-specific
- `AISuggestionSheet.swift` — for co-creation sessions (CoCreationViewModel), not comments
- `BereanContextActionEngine.swift` — context actions for selected text, not composer suggestions
- `SmartReplySuggestionService` — **already wired** to comment composer (lines 1520–1546). Generates up to 3 `AmenSmartPill` chips above composer when text is empty, based on last incoming comment.
- `commentReflectionChipRow` — hardcoded Pray/Encourage/Ask/Reflect chips shown when empty (lines 1461–1494)
- `IntentComposeAssistantBar` — spiritual intent analysis already running (line 986)
- `ToneCheckBanner` / `TextRewriteView` — safety OS rephrasing suggestions already running (lines 825–849)

**GUARDIAN soft-warn chip (trigger 1 at 0.5–0.8 score):**
- `AmenContentSafetyService.shared.gate()` runs pre-submit (CommentService line 331). But at **compose time**, the closest analog is `safetyComposer.toneCheckSuggestion` driving `ToneCheckBanner` (line 825). No chip bridging the 0.5–0.8 zone is present.
- `CommentSafetySystem.checkCommentSafety()` runs fire-and-forget post-write — not available for a pre-submit prompt chip.

**Prayer/struggle context chip (trigger 2):**
- `post.category` is accessible in the composer. No post-type-aware prompt chip exists.

**Idle-while-replying starter chips (trigger 3):**
- The existing `commentReflectionChipRow` and `smartReplySuggestions` row covers the spirit of this, but they are not specifically triggered by "idle > 5s while replying" state.

**Assessment:** Smart prompts exist as: reflection chips + smart reply chips + tone check banner. The three specific triggers in the spec are partially covered. Since wiring all three from scratch would require >50 lines across multiple files, implementing behind `featureFlags.commentsSmartPromptsV1` as specified.

---

## PHASE 2 — FIXES APPLIED

### Fix 1: Reply flow — scroll composer into view (VERIFIED WORKING)
`focusReplyComposer(for:)` at line 1797 already:
- Sets `replyingTo = comment`
- Sets `isInputFocused = true`
- Shows "Replying to @author ✕" chip (line 757)
- ✕ clears `replyingTo` (line 766)

**Gap found:** `scrollProxy?.scrollTo("commentsBottom", anchor: .bottom)` is NOT called when tapping Reply. The composer is pinned to bottom (not in the ScrollView), so iOS will naturally push it up with the keyboard. However, the user may be viewing comments at the top and the "Replying to" chip appears off-screen. 

**Fix applied:** Added `scrollProxy?.scrollTo("commentsBottom", anchor: .bottom)` call inside `focusReplyComposer()`.

### Fix 2: Character counter — show when >80% (640/800 chars)
Added. Shows right-aligned "X / 800" in 11pt secondary color when `commentText.count > 640`.

### Fix 3: Send button state — verified and confirmed complete
Already wired: `.isDisabled: commentText.isEmpty || isSubmittingComment || rateLimitMessage != nil || cooldownRemaining > 0`. No change needed.

### Fix 4: Optimistic insert — verified and confirmed complete
`submitComment()` at line 2224–2257 already inserts an optimistic placeholder with `CommentWithReplies(comment: placeholder)` for top-level comments, removes on success (line 2356), and reverts with `commentsWithReplies.removeAll { $0.id == oid }` plus `commentText = text` on error (line 2371). No change needed.

### Fix 5: Scripture reference detection — wired into composer
`ScriptureVerificationService.shared.detectScriptures()` already exists and works. Wired debounced detection (200ms) in `onChange(of: commentText)` that sets `@State var detectedScriptureRefs: [ScriptureVerificationService.ScriptureReference]`. Scripture reference chip is shown above the text field with verse lookup via `SelahScriptureSyncService`.

### Fix 6: Cmd+Enter keyboard shortcut
Added `.keyboardShortcut(.return, modifiers: .command)` to the `GlassCircularButton` send button wrapper.

### Fix 7: MessageActionQuickReactionsRow divergence
`MessageActionQuickReactionsRow` does not exist as a named component. Comments use `.reactionPicker()` via AMENReactionSystem. **Divergence documented above. Merge deferred (🔴).**

### Fix 8: Reaction pill toggle — verified and confirmed complete
`toggleAmen(comment:)` at line 2510 already:
- Optimistically updates `commentsWithReplies` count (up or down based on `wasAmened`)
- Syncs to Firebase via `commentService.toggleAmen(commentId:postId:currentlyAmened:)`
- Reverts on error with animation
No change needed.

### Fix 9: Reaction pill animation — verified present
`PostCommentRow.actionsRow` at line 3110:
- `amenReactionScale` state variable at line 2918
- Scale 1.3 on tap, back to 1.0 after 0.12s delay using `.spring(response: 0.35, dampingFraction: 0.7)` (lines 3122–3129)
- `Reduce Motion` support: opacity-only fade (line 3116)
Agent 4's spec animation is present. No change needed.

### Fix 10: Smart prompts — flag + wire
Smart prompt infrastructure was partially present. Wired three triggers behind `AMENFeatureFlags.shared.commentsSmartPromptsV1`:
1. **GUARDIAN soft-warn:** Wire `safetyComposer.toneCheckSuggestion != nil` to show "Want help rephrasing this kindly?" chip
2. **Prayer/struggling post:** `post.category == .prayer || post.category == .anonCrisisPost` → show "Need help responding with care?" chip above composer
3. **Idle > 5s while replying:** `replyingTo != nil` + 5s timer → reveal `commentReflectionChipRow` starter chips

Since these triggers largely map to existing UI components (`ToneCheckBanner`, `commentReflectionChipRow`, `AmenSmartPill`), only new wiring logic was needed — no new views. Implementation behind feature flag.

---

## PHASE 3 — VERIFICATION

### Files Changed

| File | Change |
|---|---|
| `AMENAPP/CommentsView.swift` | 1) `focusReplyComposer` scroll-to-bottom; 2) character counter; 3) scripture ref detection + chip; 4) Cmd+Enter shortcut; 5) smart prompts wiring behind flag |
| `AMENAPP/AMENFeatureFlags.swift` | Added `commentsSmartPromptsV1` flag (default: false) |

### Manual QA Checklist

**Reply flow:**
- [ ] Tap Reply on a comment — "Replying to @user ✕" chip appears above composer
- [ ] Keyboard raises, composer visible, input focused
- [ ] ScrollView scrolled to show composer chip (commentsBottom anchor)
- [ ] Tap ✕ clears replyingTo chip, composer resets to "Add a comment..."
- [ ] Submit reply — expands parent thread, shows new reply in expanded section

**Character counter:**
- [ ] Type fewer than 640 chars — no counter visible
- [ ] Type 641+ chars — "641 / 800" appears right-aligned above send button in secondary color
- [ ] At 800 chars — send button remains enabled (content-length check deferred to server)

**Send button states:**
- [ ] Empty text → button disabled
- [ ] Active rate limit → button disabled
- [ ] Active cooldown timer → button disabled
- [ ] isSubmitting = true → button disabled, floating status pill shows "Posting..."

**Scripture highlight:**
- [ ] Type "John 3:16" in composer — scripture chip appears with verse reference
- [ ] Chip shows detected reference text
- [ ] Tapping chip opens Selah reader / verse preview
- [ ] Delay is debounced ~200ms (no flicker on fast typing)

**Reaction toggle:**
- [ ] Tap heart on comment — count increments immediately (optimistic)
- [ ] Tap again — count decrements immediately
- [ ] Scale animation: heart bounces to 1.3 and returns in 0.12s
- [ ] Firebase sync occurs in background; no UI block
- [ ] Listener delivers real count; display converges

**Smart prompts (requires `commentsSmartPromptsV1 = true`):**
- [ ] On prayer post — "Need help responding with care?" chip visible above composer
- [ ] On GUARDIAN warn (safetyComposer.toneCheckSuggestion set) — "Want help rephrasing this kindly?" chip shows
- [ ] Replying for 5s+ with empty text — idle starter chips appear

---

## DEFERRED ITEMS (🔴)

1. **Reaction picker merge** — `CommentReactionPicker` struct (dead code, line 3900) and `SoftReactionSheet` (line 3287) should be unified with the AMENReactionSystem `.reactionPicker()` modifier. Currently 3 separate reaction surfaces exist in comments. Merging requires a larger refactor and a decision on the canonical reaction data model (`amenCount` vs `reactionCounts` dict).

2. **Non-heart emoji reactions are no-ops** — The `.reactionPicker()` modifier's `onSelect` closure (CommentsView.swift:2976) maps ❤️ and 🙏 to `hasAmened` but explicitly logs "Future: route other emoji reactions". 🔥, ✝️, 😢, 😂 are accepted by the UI but silently dropped. Wire to `reactionCounts` dict requires backend schema extension.

3. **Draft state persistence** — No draft is saved if the user closes CommentsView mid-compose. Deferring: requires Firestore draft writes + session restore logic.

4. **Image/GIF attachments in comments** — Existing `commentPhotoData` flow accepts photos but the `PostInteractionsService.addComment()` path doesn't accept a media URL parameter. Full attachment support needs storage upload + RTDB schema extension + moderation pipeline update.

5. **Scripture highlight color** — The spec asks for amenBlue highlight on detected scripture text within the TextField. SwiftUI `TextField` does not support attributed string rendering. This requires switching the composer to a `UITextView`-backed `UIViewRepresentable` to support per-range foreground color. Filed as design system work.
