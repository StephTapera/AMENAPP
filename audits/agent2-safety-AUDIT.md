# Agent 2 — GUARDIAN Safety Pipeline Audit
**Date:** 2026-05-27  
**Auditor:** Agent 2 (comments-system 6-agent audit)  
**Scope:** GUARDIAN moderation pipeline for all comment creation, read, edit, and notification paths  

---

## PHASE 1 — AUDIT

---

### Q1. Comment Creation Code Paths & GUARDIAN Coverage

| Code Path | File | Lines | GUARDIAN pre-publish? |
|---|---|---|---|
| `CommentService.addComment()` | `AMENAPP/CommentService.swift` | 217–702 | **Partial (client + CF)** — see below |
| `CommentService.addReply()` | `AMENAPP/CommentService.swift` | 724–779 | Delegates to `addComment()` — same coverage |
| `CommentService.editComment()` | `AMENAPP/CommentService.swift` | 999–1128 | **Yes** — `LocalContentGuard` + `ContentModerationService.moderateContent` (CF) |
| `ChurchNotesCommentsService.addComment()` | `AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesCommentsService.swift` | 54–68 | **No** — no safety check at all |
| `ChurchNotesCommentsService.reply()` | `AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesCommentsService.swift` | 70–84 | **No** — no safety check |
| Voice comment (via `VoicePrayerRecorderView`) | `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerCommentsSection.swift` | 85–89 | Not auditable from client; server-side Cloud Function handles audio transcription |

**Detail — `CommentService.addComment()` pipeline (layers in order):**

1. **Layer 0 — Synchronous local guard** (offline, zero-latency): `LocalContentGuard.check(content)` at line 259. Blocks slurs, profanity, harassment, sexual content, hate speech, violence. ✅
2. **Layer 1 — BiblicalAlignmentService**: `checkBiblicalAlignment()` at line 269. Blocks `.blocked`, `.humanReview`, `.needsDiscernment` statuses. Calls `BiblicalAlignmentService.shared` (CF-backed). ✅
3. **Layer 2 — AmenContentSafetyService** (feature-flagged): `AmenContentSafetyService.shared.gate()` at line 302–329, gated on `socialSafetyOSEnabled || thinkFirstGuardEnabled`. ✅ (conditional)
4. **Post-write async pipeline (fire-and-forget)**: After RTDB write, runs `ContentModerationService.moderateContent` (calls `moderateContent` CF) + `CommentSafetySystem.checkCommentSafety` (client-side) + `AIContentDetectionService`. If any fires, the comment is removed from RTDB silently. ⚠️ **Race window: comment is briefly visible between write and async removal (milliseconds to seconds depending on CF latency).**

**GUARDIAN (channels-specific) is NOT invoked for comments.** `guardianModerator` (cloud-functions/guardian.ts) triggers only on `channels/{channelId}/messages/{messageId}` — it has **zero coverage of `postInteractions/{postId}/comments`**, church note comments, or voice comments.

**`CommentService.editComment()` GUARDIAN coverage:**
- `LocalContentGuard.check` runs at line 1013 ✅  
- `ContentModerationService.moderateContent` (CF) runs at line 1033 ✅  
- `AmenContentSafetyService.gate()` is **NOT run on edits** — only on creation. Gap: a user can post clean content, pass pre-submit, then edit to abusive content which only gets the local + CF layer (no AmenContentSafetyService).

**Church Notes comments (CRITICAL GAP):** `ChurchNotesCommentsService.writeComment()` at line 115–151 performs no pre-submit content check. The body is written directly to Firestore `churchNotes/{noteId}/comments/{docId}` with zero moderation. No GUARDIAN, no LocalContentGuard, no CF call.

---

### Q2. Comment Read/Display Paths — Hidden/Removed Filtering

| Surface | File | Filter Applied? |
|---|---|---|
| Main comments list (`CommentsView`) | `AMENAPP/CommentsView.swift` | **NO** — blocked-user filter only; no `moderationState` filter |
| RTDB listener (`CommentService.startListening`) | `AMENAPP/CommentService.swift` | **NO** — only blocked-user filter at line 1380 |
| Pagination (`CommentService.loadMoreComments`) | `AMENAPP/CommentService.swift` | **NO** — no `moderationState` filter |
| Church notes comments display | `AMENAPP/AMENAPP/ChurchNotes/Views/ChurchNoteCommentsView.swift` | **NO** — all Firestore docs shown |
| Voice comments display | `AMENAPP/AMENAPP/VoicePrayer/VoicePrayerCommentsSection.swift` | Partial — filters by `status == VoiceCommentStatus.published.rawValue` at line 224 |
| `fetchReplies()` | `AMENAPP/CommentService.swift` | **NO** — no `moderationState` filter |
| `fetchUserComments()` | `AMENAPP/CommentService.swift` | **NO** — collectionGroup query with no moderation filter |

**Finding:** Hidden and removed comments (with `moderationState.status` of `.rejected`, `.removed`, `.escalated`, `.flagged`, or `.limited`) **will display to general users** on all surfaces except voice comments. The `moderationState` field exists on the `Comment` model (since `PostInteractionModels.swift` line 70) but is never read at any display site.

---

### Q3. GUARDIAN Response Taxonomy

**Channels GUARDIAN** (`cloud-functions/guardian.ts`):  
- `decision`: `"allow" | "allow_with_support" | "block" | "escalate"`  
- `category`: Free-form string from the LLM (no enum enforcement on the server return)  
- `reason`: Free-form string  
- `route`: `"none" | "support" | "review" | "legal"`  
- **Category is LLM-generated** — no server-side enum constraint beyond what the system prompt describes.

**iOS GuardianModels.swift** (`AMENAPP/AMENAPP/AMENAPP/Guardian/GuardianModels.swift`):  
- `GuardianDecision` (referenced but defined in `ChannelModels.swift` — not audited here)  
- `GuardianRoute`: `.none | .support | .review | .legal`  

**Comment-path moderation categories** (`AMENAPP/ContentRiskAnalyzer.swift`):  
`none | emotional_distress | self_harm_crisis | violence_threat | illegal_activity | financial_distress | harassment_exploitation | grooming_trafficking | explicit_sexual | profanity_hate | spam_scam`

**Server-side Cloud Function moderation** (`cloud-functions/moderation.js`):  
Categories returned by Vertex AI: `["hate speech", "explicit content", "harassment or bullying", "violence or threats", "spam or scams", "self-harm mentions"]` (from the prompt literal at lines 32–38). These are free-form strings.

**Gap identified:** `scriptureMisuse` and `blasphemy` appear in the backend `alignmentPipeline.ts` and in `AdvancedModerationService.swift` but are **absent from `ContentRiskCategory`** (iOS) and absent from the channels GUARDIAN prompt. The channels GUARDIAN prompt acknowledges faith context (line 65) but provides no specific category for scripture weaponisation. The comment pipeline has no pathway to flag `scripture_misuse` as a distinct harm category on-device.

---

### Q4. Action Mapping / Threshold Consistency

**`ModerationPipeline.buildDecision()` thresholds** (`AMENAPP/ModerationPipeline.swift` lines 274–418):

| Category | Threshold | Action |
|---|---|---|
| groomingTrafficking | > 0.45 | `blockImmediate` |
| groomingTrafficking | 0.25–0.45 | `blockAndReview` |
| explicitSexual | > 0.55 | `blockImmediate` |
| explicitSexual | 0.35–0.55 | `blockAndReview` |
| selfHarmCrisis | > 0.75 | `holdForSoftReview` |
| selfHarmCrisis | 0.45–0.75 | `allowWithWarning` |
| violenceThreat | > 0.80 | `blockAndReview` |
| violenceThreat | 0.55–0.80 | `holdForSoftReview` |
| illegalActivity | > 0.70 | `blockImmediate` |
| illegalActivity | 0.45–0.70 | `holdForSoftReview` |
| harassmentExploitation | > 0.75 | `blockAndReview` |
| spamScam | > 0.60 | `blockImmediate` |
| spamScam | 0.40–0.60 | `holdForSoftReview` |
| profanityHate | > 0.70 | `blockAndReview` |
| profanityHate | 0.45–0.70 | `allowWithWarning` |

🟡 **Inconsistency:** `ModerationPipeline` is gated by `flags.moderationV2Enabled`. If this flag is off, `evaluate()` returns `.allow()` unconditionally (line 176). The flag is not shown to be enabled by default in any audited file.

🟡 **`CommentSafetySystem` thresholds** use different scale: pile-on at ≥10 comments/hour (line 358); repeat harassment at ≥5 interactions in 7 days (line 466); spam at >20 comments/hour (line 509). These heuristics are client-side only and cannot be tuned server-side.

**Consistency verdict:** Thresholds are not consistent across paths. `CommentSafetySystem`, `ModerationPipeline`, `ContentModerationService` (delegating to CF), and `LocalContentGuard` all apply different thresholds independently.

---

### Q5. Post-Publish Moderation / Report Flow

When a comment is **reported** via `UserReportService.reportContent()` (`AMENAPP/ModerationPipeline.swift` lines 523–531):
1. Calls `CloudFunctionsService.shared.submitTrustSafetyReport(contentType:contentId:reason:details:)` — a CF callable.
2. There is **no documented CF implementation** of `submitTrustSafetyReport` in the audited `cloud-functions/` directory. Only `moderateComment` (on the `comments/{commentId}` Firestore collection), `moderatePost`, and `checkContent` are present. `submitTrustSafetyReport` is unresolved at build time in the audited files.
3. The `moderateContent` CF callable (`cloud-functions/moderation.js` line 136) triggers on Firestore `comments/{commentId}` — **but the primary comment store is RTDB `postInteractions/{postId}/comments/`**, not Firestore. This CF will **never trigger for actual app comments**.

**Finding (critical):** The `moderateComment` Firestore trigger listens on the wrong collection (`comments/{commentId}` instead of `postInteractions/{postId}/comments`). No CF auto-moderates RTDB-backed comments post-publish.

---

### Q6. Shadow-Hide State Implementation

`ModerationState.allowsPublicDisplay` (`AMENAPP/ModerationState.swift` line 27) returns `true` only when `status == .approved`.

**Shadow-hide leak check:**
- **Reactions (amen/toggle):** `CommentService.toggleAmen()` at line 1260 reads the comment directly from RTDB by `commentId` without checking `moderationState`. A user who knows a `commentId` can amen a hidden comment via a direct RTDB transaction. **Visibility leak via reaction count exists.**
- **Notifications:** `createCommentNotification()` (line 1789) and `createReplyNotification()` (line 1851) are **never called** in the current `addComment()` or `addReply()` flow. The notification task fires via `NotificationService.shared.sendMentionNotifications()` — but that is guarded by `TrustByDesignService.shared.canMention()` (privacy check), not by moderation state. **A mention notification for a later-moderated comment could have already been sent.**
- **RTDB observer leak:** The RTDB listener subscribes to the full comments node without a `moderationState` query clause (RTDB does not support server-side field filtering of embedded object properties). All comments, regardless of moderation state, are delivered to the client's cache and must be filtered client-side.

---

### Q7. GUARDIAN on Edits vs. Creates

| Path | LocalContentGuard | CF Moderation | AmenContentSafetyService |
|---|---|---|---|
| Create (`addComment`) | ✅ line 259 | ✅ post-write async (line 566) | ✅ line 302 (feature-flagged) |
| Edit (`editComment`) | ✅ line 1013 | ✅ line 1033 (blocking) | ❌ **Not called on edits** |
| Reply (`addReply`) | Via `addComment` | Via `addComment` | Via `addComment` |
| Church Notes create | ❌ | ❌ | ❌ |
| Church Notes reply | ❌ | ❌ | ❌ |

**`editComment()` runs moderation synchronously and blocks the edit** if `moderationResult.shouldBlock` is true (line 1038) — this is better than `addComment()` which allows the write and removes async. However, `AmenContentSafetyService.gate()` is skipped on edits.

---

### Q8. GUARDIAN: Server-Side vs Client-Side

| Component | Location |
|---|---|
| `guardianModerator` CF | **Server-side** — Firestore trigger on `channels/{channelId}/messages/{messageId}` |
| `moderateComment` CF | **Server-side** — Firestore trigger on `comments/{commentId}` (wrong collection) |
| `moderateContent` callable CF | **Server-side** — callable; iOS calls it post-write for RTDB comments |
| `LocalContentGuard.check()` | **Client-side** — bypassable by direct RTDB writes |
| `CommentSafetySystem.checkCommentSafety()` | **Client-side** — bypassable |
| `BiblicalAlignmentService.checkBiblicalAlignment()` | **Client + CF** — CF-backed callable |
| `AmenContentSafetyService.gate()` | **Client-side** — orchestrates local + CF |
| `ContentRiskAnalyzer.analyze()` | **Client-side** — pattern matching only |

**Critical finding:** All pre-submit checks (`LocalContentGuard`, `CommentSafetySystem`, `AmenContentSafetyService`) are **client-side and bypassable** via direct RTDB writes. The only server-side enforcement for comments is the `moderateContent` CF callable (called post-write) and the `BiblicalAlignmentService` CF callable (called pre-write but after auth, so only protects against UI-submitted content, not direct API abuse). The canonical comment store in RTDB has **no Firestore-trigger-based server-side moderation** because RTDB triggers are not audited in this codebase.

---

## PHASE 2 — SAFE FIXES APPLIED

### Fix 1: Read-Path `moderationState` Filter (🟢)

**File:** `AMENAPP/CommentsView.swift`  
**Change:** Added `moderationState` filter in `updateCommentsFromService()`. General users now only see comments with `.approved` or `.pending` status. Both the top-level comment array and the replies array are filtered before display.

**Before (line ~2643):**
```swift
let allComments: [Comment]
if blockedUsers.isEmpty {
    allComments = rawComments
} else {
    allComments = rawComments.filter { !blockedUsers.contains($0.authorId) }
}
// No moderationState filter — hidden/removed comments displayed to all users
```

**After:**
```swift
let allComments: [Comment]
if blockedUsers.isEmpty {
    allComments = rawComments
} else {
    allComments = rawComments.filter { !blockedUsers.contains($0.authorId) }
}
// Moderation filter: only approved and pending comments visible to general users
let visibleComments = allComments.filter {
    $0.moderationState.status == .approved || $0.moderationState.status == .pending
}
// Replies also filtered
let replies = unblocked.filter {
    $0.moderationState.status == .approved || $0.moderationState.status == .pending
}
```

---

### Fix 2: `moderationLogs/{commentId}` Write on Flagged Outcomes (🟢)

**File:** `AMENAPP/CommentService.swift`  
**Change:** Added Firestore write to `moderationLogs/{commentId}` immediately after the async post-write moderation pipeline removes a comment. Fields written: `commentId`, `authorId`, `outcome` (one of `blocked | safety_blocked | ai_generated_blocked`), `categories` (reasons array), `scores` (empty dict — scores are server-owned), `timestamp`.

**Location:** Inside `Task.detached(priority: .utility)` block in `addComment()`, after the RTDB `removeValue()` succeeds.

---

### Fix 3: `scriptureMisuse` and `blasphemy` Added to iOS Taxonomy (🟢)

**File:** `AMENAPP/ContentRiskAnalyzer.swift`  
**Change:** Added two new cases to `ContentRiskCategory` enum:
- `.scriptureMisuse = "scripture_misuse"` — mirrors `alignmentPipeline.ts` flag
- `.blasphemy = "blasphemy"` — mirrors `AdvancedModerationService.analyzeWithFaithML()` detection

These categories are **not yet wired into scoring signals** (that requires a new signal table — deferred as 🟡 threshold/signal tuning). Adding them to the enum ensures type-safe use in future signal tables and audit log `categories` arrays without a mismatch against the server-side string values.

---

### Fix 4: Notification Guard (🟢) — Scope Assessment

**Finding:** `createCommentNotification()` and `createReplyNotification()` in `CommentService.swift` are **private helpers** that are **never called** in the current `addComment()` / `addReply()` flow. The only notification dispatch is `NotificationService.shared.sendMentionNotifications()` (lines 689, 1106) which fires for mentions. Mentions fire before the async moderation pipeline could remove the comment, creating a race where a mention notification may be received for a comment that is subsequently moderated away.

**Applied guard:** The moderation task already posts `commentRemovedByModeration` when it removes a comment (line 637). The CommentsView already handles this notification. However, the outbound push notification to the mentioned user has already been dispatched. A true fix requires server-side notification dispatch gated on moderation completion — deferred as 🔴 server-side migration.

**Partial client guard applied:** The `moderationLogs` write (Fix 2) serves as a post-hoc audit trail for the race window.

---

## PHASE 3 — VERIFICATION

### Files Changed

| File | Change |
|---|---|
| `AMENAPP/CommentsView.swift` | Added `moderationState` filter for general user comment visibility in `updateCommentsFromService()` |
| `AMENAPP/CommentService.swift` | Added `moderationLogs/{commentId}` Firestore write in async post-write moderation path |
| `AMENAPP/ContentRiskAnalyzer.swift` | Added `.scriptureMisuse` and `.blasphemy` to `ContentRiskCategory` enum |

### Gaps Where Tests Should Be Added

1. **`CommentsView.updateCommentsFromService` — moderation filter**: A contract test should verify that a `Comment` with `moderationState.status == .removed` is excluded from `commentsWithReplies` after calling `updateCommentsFromService()`. A comment with `.approved` status should pass.
2. **`CommentService.addComment` — moderationLogs write**: A test with a mock Firestore should verify that when `moderationResult.shouldBlock == true`, a document is written to `moderationLogs/{commentId}` with the correct `outcome`, `authorId`, and `categories` fields.
3. **`ContentRiskCategory` — scripture and blasphemy cases**: Unit test that `ContentRiskCategory.scriptureMisuse.rawValue == "scripture_misuse"` and `ContentRiskCategory.blasphemy.rawValue == "blasphemy"` to catch any future renaming.
4. **`ChurchNotesCommentsService.writeComment` — no moderation**: Integration test should verify that a comment with known harmful content is rejected (currently it would not be — this is a gap, not a test gap).
5. **Read-path for `fetchUserComments`**: `CommentService.fetchUserComments()` returns Firestore comments without a `moderationState` filter. Test and fix needed on the `collectionGroup("comments")` query.

### Diagnostic Run

**Requested:** `XcodeRefreshCodeIssuesInFile` on each changed file.
