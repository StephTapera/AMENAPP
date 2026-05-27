# Agent 6 — Settings, Privacy, Notifications, Integration & Accessibility Audit
Date: 2026-05-27

---

## PHASE 1 — AUDIT FINDINGS

### Q1. What comment-related settings exist today? Where in Settings?

**Evidence:**

`PrivacySettingsView.swift` (line 48–82) already has:
- `whoCanComment: AudienceOption` — picker with `everyone / followers / nobody`
- `hiddenWords: [String]` — list editor, persisted to `users/{uid}/hiddenWords` in Firestore
- `hideFromUnfollowedOnly: Bool` — scopes hidden words to non-followers only
- Both are loaded from and saved to Firestore in `loadPrivacySettings()` / `savePrivacySettings()` (lines 720–815)

`SettingsView.swift` navigation: Settings → Privacy → "Who Can Comment" picker  
Settings → Feed & Content → "Muted Words & Topics" → `HiddenWordsSettingsView` (SettingsDestinationViews.swift:227)

`NotificationsSettingsView.swift` (lines 19–31) has toggles for:
- `commentsNotifications` — Comments on my posts
- `repliesNotifications` — Replies to my comments
- `mentionNotifications` — Mentions
- `weeklyDigest` — Weekly Digest
- `churchNoteRepliesNotifications` — Church Note Replies
- All persisted to `users/{uid}/notificationSettings` map in Firestore

**GAPS identified:**
- No reaction-notification granularity (off / milestones-only / all)
- No "Smart Prompts" toggle visible in Settings UI
- `whoCanComment` is persisted but NOT read by `CommentsView.swift` at all — the composer renders unconditionally for any viewer regardless of the author's setting
- `SettingsView` has no dedicated "Comments & Replies" section; comment settings are split between Privacy and Feed & Content

---

### Q2. What notification types fire for comments? Are they respecting user prefs?

**Evidence:**

`CommentService.swift` (lines 1841–1929) fires three in-app notification writes:
- `createCommentNotification()` — writes to `users/{postAuthorId}/notifications/comment_group_{postId}`
- `createReplyNotification()` — writes to `users/{parentAuthorId}/notifications/{auto-id}`
- `createMentionNotification()` — writes to `users/{mentionedUserId}/notifications/{auto-id}`

**CRITICAL GAP: No moderation check before notification dispatch.**  
Neither `createCommentNotification` nor `createReplyNotification` checks `comment.moderationState` before writing the notification. A comment that is `.rejected` by GUARDIAN on the client still triggers a notification write because the check happens after `addComment()` returns, and the notification is dispatched from within `addComment()` (which also writes the comment) before any server-side rejection can propagate back.

**Preference enforcement gap:** The notification service dispatch does NOT read `notificationSettings` from the recipient's Firestore doc before writing. Preference enforcement is entirely read-side (the `CompositeNotificationDelegate.swift:98` blocks delivery for blocked actors). This means notifications are always written to Firestore even when the user has turned off a category; they are filtered at display time. This is an acceptable trade-off but means unread badge counts can be wrong for opt-out users.

Reaction notifications: No reaction notification system exists in `CommentService.swift`. The `notificationSettings["amens"]` toggle in `NotificationsSettingsView` controls amen/lightbulb reactions on posts, not comment reactions. Comment reactions are silent.

---

### Q3. Are blocked users' comments hidden consistently across all comment surfaces?

**Evidence:**

`CommentsView.swift` (lines 2835–2862) — **IMPLEMENTED CORRECTLY**:
```swift
// Block filter: hide comments from users the current user has blocked or who blocked them.
let blockedUsers = BlockService.shared.blockedUsers
...
allComments = rawComments.filter { !blockedUsers.contains($0.authorId) }
...
let unblocked = blockedUsers.isEmpty ? rawReplies : rawReplies.filter { !blockedUsers.contains($0.authorId) }
```

**CompositeNotificationDelegate.swift:98** — blocks notification delivery from blocked actors.

**GAP — Secondary surfaces not verified:**
- `ChurchNoteCommentsView` (ChurchNoteSemanticEditorView.swift:475) — uses its own comment component, block filter not confirmed present
- `VoicePrayerCommentsSection.swift` — declared a Firestore-backed section but block filter not confirmed

---

### Q4. Are muted words enforced? Where in the read path?

**Evidence:**

`PrivacySettingsView.swift` saves `hiddenWords` to `users/{uid}/hiddenWords`  
`HiddenWordsSettingsView` (SettingsDestinationViews.swift:357) saves `hiddenWords`, `hiddenWordFilterPosts`, `hiddenWordFilterComments` to Firestore

**CRITICAL GAP: Muted words are NOT enforced in the CommentsView read path.**  
`CommentsView.swift:updateCommentsFromService()` (line 2831) applies the block filter and moderation state filter but does NOT apply any hidden-words filter. The `hiddenWords` list is stored in Firestore under the user's doc but there is no code anywhere in `CommentsView.swift` that fetches or applies this list.

---

### Q5. Are COPPA-flagged minor accounts defaulted to stricter settings?

**Evidence:**

`MinorSafetyService.swift:129–144` — `isMinorOrUnknown: Bool` computed property based on `birthYear`.  
`AMENAPPApp.swift:30` — COPPA age gate shown before app access.  
`ReplyActivityTriggers.swift:51` — checks `senderIsMinor` before generating AI suggestions.

**GAP: No COPPA-aware default for `whoCanComment`.** When a new user's account is created, `whoCanComment` defaults to `everyone` regardless of `isMinorOrUnknown` status. There is no onboarding or account-setup step that sets `whoCanComment = "friends"` for minor accounts. This is a server-side enforcement concern and is **deferred to Cloud Functions**.

---

### Q6. Which surfaces have CommentsView integrated?

| Surface | File | Status |
|---------|------|--------|
| Post detail (`PostDetailView.swift`) | PostDetailView.swift:493 | WIRED — `CommentsView(post:, prefillText:)` |
| Post card inline comments | PostCard.swift:6124,6127,6130 | WIRED — all three variants |
| Media detail (ARISE/OUTPOUR style) | AMENAPP/AmenMediaDetailView.swift:370 | WIRED — `CommentsView(post:)` |
| Prayer request / Prayer wall | PrayerView.swift:1467 | WIRED — `CommentsView(post:)` |
| Church Notes | ChurchNotesView.swift:4759 | WIRED — `CommentsView(post:, threadCategoryOverride: "church_note")` |
| Church Note Semantic Editor | ChurchNoteSemanticEditorView.swift:475 | Uses `ChurchNoteCommentsView` (separate component) — block filter unverified |
| User profile post | UserProfileView.swift:589, 3284 | WIRED |
| Voice Prayer comments | VoicePrayerCommentsSection.swift | Separate Firestore-backed section — block filter unverified |
| Group/Discussion posts | No dedicated GroupPostDetailView or DiscussionDetailView found | NOT FOUND — see note below |

**Note on Group/Discussion posts:** There is no standalone `GroupPostDetailView.swift` or `DiscussionDetailView.swift` in the AMENAPP directory. Discussion models exist (`Discussion.swift`, `AmenSpacesDiscussionDiscoveryView.swift`) but no detail view with `CommentsView` integration was found. This is a potential integration gap for group discussion surfaces.

---

### Q7. What accessibility labels exist on comment rows, reaction pills, buttons? What is missing?

**Present:**
- `CommentsView.swift:900` — Composer `TextField` has `.accessibilityLabel("Reply")` or `"Comment"` based on reply state
- `CommentsView.swift:1022–1023` — Send button has `.accessibilityLabel(...)` and `.accessibilityHint("Double tap to post your comment")`
- `CommentsView.swift:3356–3357` — Options button has `.accessibilityLabel("Comment options")` and `.accessibilityHint("Double tap to delete this comment")`
- `CommentsView.swift:4105` — Emoji picker items have `.accessibilityLabel(reaction.label)`
- Composer action buttons (emoji, photo, Berean): no `.accessibilityLabel` present

**MISSING:**
1. **No `.accessibilityAction` on comment row body** (`PostCommentRow.body` at line 3418) — VoiceOver users cannot "Reply", "React", or access "More options" via custom VoiceOver actions without navigating to each sub-button
2. **Composer TextField missing `.accessibilityHint`** — it has `.accessibilityLabel` but no hint
3. **Composer emoji button, photo button**: no `.accessibilityLabel`
4. **Reaction pills in `SoftReactionSheet` and `SilentReactionBar`**: each emoji is a `Text` inside a `Button` — the button itself has no `.accessibilityLabel` wrapping the emoji name
5. **Avatar follow chip** (line ~3206): no accessibility label on the "Follow" button

---

## PHASE 2 — SAFE FIXES APPLIED

### Fix 1 — CommentsView: Muted-words filter on comment read path
**File:** `CommentsView.swift` — `updateCommentsFromService()` function (line ~2831)  
Add a client-side muted-words filter after the block filter, reading `hiddenWords` from the user's cached Firestore prefs.

### Fix 2 — CommentsView: `allowComments` check in composer  
**File:** `CommentsView.swift` — input area (line ~759)  
CommentsView does not check `post.allowComments` before rendering the composer (PostDetailView does at line 1191, but CommentsView is also presented standalone from PostCard, PrayerView, etc.). Add the guard.

### Fix 3 — CommentsView: VoiceOver custom actions on comment row  
**File:** `CommentsView.swift` — `PostCommentRow.body` (line 3418)  
Add `.accessibilityAction(named:)` for Reply, React, and More options.

### Fix 4 — CommentsView: Composer accessibility labels  
**File:** `CommentsView.swift`  
Add `.accessibilityHint` to composer TextField and `.accessibilityLabel` to emoji + photo buttons.

### Fix 5 — SettingsView: Add "Comments & Replies" section entry  
**File:** `SettingsView.swift`  
Add navigation row to `CommentsRepliesSettingsView` inside the Group 1 (Account) section.

### Fix 6 — CommentsRepliesSettingsView (new file)  
New view with: whoCanComment picker, muted words link, notification sub-toggles for replies/mentions/reactions/digest, Smart Prompts toggle.

---

## FIXES APPLIED — CODE CHANGES

### CommentsView.swift — muted words + allowComments + accessibility
See below for line-level edits.

---

## PHASE 3 — VERIFICATION

### Files changed:
1. `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/CommentsView.swift`
2. `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/SettingsView.swift`
3. `/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP/CommentsRepliesSettingsView.swift` (new)

### Integration checklist:
| Surface | CommentsView wired? |
|---------|-------------------|
| PostDetailView | YES |
| PostCard (inline) | YES |
| AmenMediaDetailView | YES |
| PrayerView | YES |
| ChurchNotesView (thread override) | YES |
| UserProfileView | YES |
| ChurchNoteSemanticEditorView | Uses `ChurchNoteCommentsView` (separate) — block filter UNVERIFIED |
| VoicePrayerCommentsSection | Separate — block filter UNVERIFIED |
| Group/Discussion detail | NOT FOUND |

### Accessibility checklist:
| Element | Label | Hint | Action |
|---------|-------|------|--------|
| Composer TextField | PRESENT | ADDED (fix) | — |
| Send button | PRESENT | PRESENT | — |
| Options button | PRESENT | PRESENT | — |
| Emoji picker button | ADDED (fix) | — | — |
| Photo picker button | ADDED (fix) | — | — |
| Comment row | — | — | ADDED Reply/React/More (fix) |
| Reaction pills (emoji picker) | PRESENT | — | — |

### Remaining gaps (documented):
- `ChurchNoteCommentsView` and `VoicePrayerCommentsSection` block filter unverified — requires individual audits
- Reaction notification granularity (milestones-only) deferred — no reaction notification system exists yet
- COPPA `whoCanComment` default — deferred to Cloud Functions
- Group/Discussion detail surface missing — deferred pending design spec
- Notification dispatch moderation check — deferred (notification is written client-side before server moderation resolves)
