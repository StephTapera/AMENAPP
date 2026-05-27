# CF Trigger Fix — Church Notes Comments Moderation Gap

**Date:** 2026-05-27
**Severity:** High — unmoderated Firestore writes, no server-side GUARDIAN enforcement

---

## What the bug is

There is NO Cloud Function that triggers on writes to the
`churchNotes/{noteId}/comments/{commentId}` Firestore subcollection.

Church Notes comments go directly to Firestore via `ChurchNotesCommentsService.writeComment()`.
As of this session, client-side GUARDIAN checks (LocalContentGuard + ContentRiskAnalyzer)
have been added to that method (FIX 1 in this audit pass), but there is still no
server-side enforcement layer. A bad actor who bypasses the iOS client (e.g. using the
Firebase console, REST API, or a modified client) can write unmoderated content directly
to `churchNotes/{noteId}/comments`.

### Clarification on the previously-described bug

The audit description originally stated: "moderateComment CF triggers on the wrong
top-level `comments/{commentId}` collection." That specific bug does NOT exist in this
repo. The only comment-related RTDB triggers in the codebase are:

- `index.js` → `exports.onRealtimeCommentCreate` → ref: `/postInteractions/{postId}/comments/{commentId}` (CORRECT)
- `index.js` → `exports.onRealtimeReplyCreate`   → ref: `/postInteractions/{postId}/comments/{commentId}` (CORRECT)
- `v2functions.js` → `exports.onRealtimeCommentCreate` → ref: `/postInteractions/{postId}/comments/{commentId}` (CORRECT)

None of these point at a wrong path. The real gap is the **missing trigger for
Firestore `churchNotes/{noteId}/comments`**.

---

## What the fix needs to be

Add a new Cloud Function in the Firebase Functions project that:

1. **Triggers on** Firestore document creation at `churchNotes/{noteId}/comments/{commentId}`:

```javascript
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

exports.onChurchNoteCommentCreate = onDocumentCreated(
  {
    document: "churchNotes/{noteId}/comments/{commentId}",
    region: "us-central1",
  },
  async (event) => {
    const noteId = event.params.noteId;
    const commentId = event.params.commentId;
    const data = event.data.data();
    const body = data?.body ?? "";
    const authorUid = data?.authorUid ?? "";

    // 1. Run server-side content moderation (reuse existing pipeline)
    const moderationResult = await moderateText(body, "church_note_comment");

    if (moderationResult.shouldBlock) {
      // Delete the doc — client-side guard may have been bypassed
      await event.data.ref.delete();
      // Log to moderationLogs for audit trail
      await admin.firestore().collection("moderationLogs").add({
        commentId,
        noteId,
        authorUid,
        outcome: "blocked",
        categories: moderationResult.reasons,
        surface: "church_note_comment",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`[ChurchNote] Blocked comment ${commentId} on note ${noteId}`);
      return null;
    }

    if (moderationResult.isPending) {
      // Set moderationState = "pending" so the UI hides it until reviewed
      await event.data.ref.update({ moderationState: "pending" });
      return null;
    }

    // Clean — confirm approval so Firestore rules can gate reads to approved-only
    await event.data.ref.update({ moderationState: "approved" });
    return null;
  }
);
```

2. **Export it from `index.js`**:

```javascript
const { onChurchNoteCommentCreate } = require("./churchNotesCommentModeration");
exports.onChurchNoteCommentCreate = onChurchNoteCommentCreate;
```

3. **Update Firestore security rules** to only allow reads of church note comments
   where `moderationState == "approved"` (unless the reader is the author):

```
match /churchNotes/{noteId}/comments/{commentId} {
  allow read: if resource.data.moderationState == "approved"
               || request.auth.uid == resource.data.authorUid;
  allow create: if request.auth != null;
  allow update, delete: if request.auth.uid == resource.data.authorUid;
}
```

---

## Why this cannot be applied from the iOS project root

The Firebase Functions source lives in a **separate project directory** that is deployed
independently via the Firebase CLI (`firebase deploy --only functions`). The iOS project
has no build step that touches the Functions code. Changes must be made in the Functions
project and deployed with:

```sh
cd /path/to/firebase-functions-project
firebase deploy --only functions:onChurchNoteCommentCreate
```

---

## Related files

- **iOS fix already applied:** `AMENAPP/AMENAPP/ChurchNotes/Services/ChurchNotesCommentsService.swift`
  — client-side GUARDIAN gate added in `writeComment()` (audit pass 2026-05-27)
- **Existing correct RTDB triggers:** `functions/index.js`, `functions/v2functions.js`
  — both correctly trigger on `/postInteractions/{postId}/comments/{commentId}`
- **No existing CF for churchNotes comments:** confirmed by full-text search of
  `functions/` directory on 2026-05-27
