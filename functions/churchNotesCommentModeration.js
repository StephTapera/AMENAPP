/**
 * churchNotesCommentModeration.js
 * AMEN App — Server-side moderation for Church Notes comments.
 *
 * Trigger: Firestore onDocumentCreated "churchNotes/{noteId}/comments/{commentId}"
 *
 * Pipeline:
 *   1. Pull comment text and authorUid from the new doc.
 *   2. Run Google Cloud Natural Language toxicity detection (same API used by
 *      contentModeration.js for posts).
 *   3. Decision:
 *      - toxicity >= 0.70  → delete doc, write moderationLogs, no notification
 *      - toxicity  0.40–0.69 → set moderationState = "pending", no notification
 *      - toxicity <  0.40  → set moderationState = "approved", notify note author
 *   4. Log every blocked/pending outcome to moderationLogs/{auto-id}.
 *
 * Exported: onChurchNoteCommentCreate
 */

"use strict";

const admin = require("firebase-admin");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { LanguageServiceClient } = require("@google-cloud/language");

let _languageClient = null;
function getLanguageClient() {
  if (!_languageClient) {
    _languageClient = new LanguageServiceClient();
  }
  return _languageClient;
}

const BLOCK_THRESHOLD = 0.70;
const PENDING_THRESHOLD = 0.40;

// ── Toxicity check via Cloud Natural Language API ────────────────────────────
async function getToxicityScore(text) {
  if (!text || text.trim().length === 0) return 0;

  try {
    const client = getLanguageClient();
    const [result] = await client.moderateText({
      document: {
        type: "PLAIN_TEXT",
        content: text.slice(0, 1000), // API limit-safe
      },
    });

    // moderateText returns categoryScores; pick the worst category score.
    const categories = result.moderationCategories ?? [];
    if (categories.length === 0) return 0;

    return Math.max(...categories.map((c) => c.confidence ?? 0));
  } catch (err) {
    // NL API failure → fail open (don't block), but log.
    console.warn("[churchNotesCommentModeration] NL API error — defaulting to approved:", err.message);
    return 0;
  }
}

// ── Write a moderation audit record ─────────────────────────────────────────
async function writeModerationLog(commentId, noteId, authorUid, outcome, score, text) {
  await admin.firestore().collection("moderationLogs").add({
    commentId,
    noteId,
    authorUid,
    outcome,
    surface: "church_note_comment",
    toxicityScore: score,
    textSnippet: text.slice(0, 100), // store only first 100 chars for audit
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ── Notify the church note author ────────────────────────────────────────────
async function notifyNoteAuthor(noteId, commentId, commenterUid, commentText) {
  const noteDoc = await admin.firestore().collection("churchNotes").doc(noteId).get();
  if (!noteDoc.exists) return;

  const noteAuthorId = noteDoc.data()?.authorUid ?? noteDoc.data()?.userId;
  if (!noteAuthorId || noteAuthorId === commenterUid) return;

  const commenterDoc = await admin.firestore().collection("users").doc(commenterUid).get();
  const commenterData = commenterDoc.data() ?? {};
  const commenterName = commenterData.displayName || "Someone";

  // Firestore notification record
  await admin.firestore()
    .collection("users").doc(noteAuthorId)
    .collection("notifications")
    .add({
      type: "church_note_comment",
      actorId: commenterUid,
      actorName: commenterName,
      actorUsername: commenterData.username ?? "",
      actorProfileImageURL: commenterData.profileImageURL ?? commenterData.profilePictureURL ?? "",
      noteId,
      commentId,
      commentText: commentText.slice(0, 120),
      userId: noteAuthorId,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  // FCM push
  const fcmToken = (await admin.firestore().collection("users").doc(noteAuthorId).get()).data()?.fcmToken;
  if (fcmToken) {
    await admin.messaging().send({
      notification: {
        title: "New comment on your church note",
        body: `${commenterName}: ${commentText.slice(0, 80)}`,
      },
      data: {
        type: "church_note_comment",
        noteId,
        commentId,
        actorId: commenterUid,
      },
      token: fcmToken,
    });
  }
}

// ── Main trigger ─────────────────────────────────────────────────────────────
exports.onChurchNoteCommentCreate = onDocumentCreated(
  {
    document: "churchNotes/{noteId}/comments/{commentId}",
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const noteId = event.params.noteId;
    const commentId = event.params.commentId;
    const data = event.data.data();

    const rawText = (data?.body ?? data?.text ?? data?.content ?? "").trim();
    const authorUid = data?.authorUid ?? data?.userId ?? "";

    console.log(`[ChurchNote] New comment ${commentId} on note ${noteId} by ${authorUid}`);

    try {
      const score = await getToxicityScore(rawText);

      if (score >= BLOCK_THRESHOLD) {
        // Hard block — client-side guard may have been bypassed
        await event.data.ref.delete();
        await writeModerationLog(commentId, noteId, authorUid, "blocked", score, rawText);
        console.log(`[ChurchNote] Blocked comment ${commentId} (score ${score.toFixed(2)})`);
        return null;
      }

      if (score >= PENDING_THRESHOLD) {
        // Needs human review — hide from other users until reviewed
        await event.data.ref.update({ moderationState: "pending" });
        await writeModerationLog(commentId, noteId, authorUid, "pending", score, rawText);
        console.log(`[ChurchNote] Comment ${commentId} queued for review (score ${score.toFixed(2)})`);
        return null;
      }

      // Clean — approve and notify the note author
      await event.data.ref.update({ moderationState: "approved" });
      await notifyNoteAuthor(noteId, commentId, authorUid, rawText);
      console.log(`[ChurchNote] Approved comment ${commentId} (score ${score.toFixed(2)})`);

      return null;
    } catch (err) {
      console.error(`[ChurchNote] Error moderating comment ${commentId}:`, err);
      // Fail-safe: approve rather than silently block legitimate comments
      await event.data.ref.update({ moderationState: "approved" }).catch(() => {});
      return null;
    }
  }
);
