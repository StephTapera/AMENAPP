/**
 * churchNotesCommentModeration.ts
 * AMEN App — Server-authoritative moderation for Church Notes comments.
 *
 * TRIGGER:
 *   Firestore onDocumentCreated on `churchNotes/{noteId}/comments/{commentId}`
 *
 * WHY THIS EXISTS:
 *   Church Notes comments bypass the RTDB comment pipeline (which has its own
 *   RTDB triggers). A bad actor who calls the Firestore SDK directly — or who
 *   uses the Firebase console — can write arbitrary content to this subcollection
 *   without hitting any client-side guard. This trigger is the server-side
 *   enforcement layer that runs regardless of how the document was created.
 *
 * PIPELINE:
 *   1. Extract comment text and authorUid from the new document.
 *   2. Run moderateText() from TextModerationService (banned-terms + Perspective API).
 *   3. Decision:
 *      - enforcement === "block"          → delete doc, write moderationLog, no notification
 *      - enforcement === "pending_review" → set moderationState = "pending", write moderationLog
 *      - enforcement === "allow"          → set moderationState = "approved", notify note author
 *   4. Write every non-allow outcome to moderationLogs/ for the human review queue.
 *
 * FAIL OPEN:
 *   If the moderation pipeline throws unexpectedly, we approve rather than silently
 *   block legitimate comments. The error is logged for monitoring.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { moderateText } from "../safety/TextModerationService";

const db = admin.firestore();

// ─── Notification helper ──────────────────────────────────────────────────────

async function notifyNoteAuthor(
    noteId: string,
    commentId: string,
    commenterUid: string,
    commentText: string
): Promise<void> {
    const noteSnap = await db.collection("churchNotes").doc(noteId).get();
    if (!noteSnap.exists) return;

    const noteData = noteSnap.data()!;
    const noteAuthorId: string | undefined = noteData.authorUid ?? noteData.userId;
    if (!noteAuthorId || noteAuthorId === commenterUid) return;

    const commenterSnap = await db.collection("users").doc(commenterUid).get();
    const commenter = commenterSnap.data() ?? {};
    const commenterName: string = commenter.displayName ?? "Someone";

    // Firestore notification record
    await db
        .collection("users")
        .doc(noteAuthorId)
        .collection("notifications")
        .add({
            type: "church_note_comment",
            actorId: commenterUid,
            actorName: commenterName,
            actorUsername: commenter.username ?? "",
            actorProfileImageURL: commenter.profileImageURL ?? commenter.profilePictureURL ?? "",
            noteId,
            commentId,
            commentText: commentText.slice(0, 120),
            userId: noteAuthorId,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

    // FCM push — fetch token from a single read
    const recipientSnap = await db.collection("users").doc(noteAuthorId).get();
    const fcmToken: string | undefined = recipientSnap.data()?.fcmToken;
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

// ─── Audit log helper ─────────────────────────────────────────────────────────

async function writeModerationLog(
    commentId: string,
    noteId: string,
    authorUid: string,
    outcome: "blocked" | "pending" | "approved",
    textSnippet: string,
    harmCategoryId: string | null
): Promise<void> {
    await db.collection("moderationLogs").add({
        commentId,
        noteId,
        authorUid,
        outcome,
        surface: "church_note_comment",
        harmCategoryId: harmCategoryId ?? null,
        textSnippet: textSnippet.slice(0, 100),
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
}

// ─── Main trigger ─────────────────────────────────────────────────────────────

export const onChurchNoteCommentCreate = onDocumentCreated(
    {
        document: "churchNotes/{noteId}/comments/{commentId}",
        region: "us-central1",
        timeoutSeconds: 30,
        memory: "256MiB",
    },
    async (event) => {
        const { noteId, commentId } = event.params;
        const data = event.data?.data();

        if (!data) {
            logger.warn("[churchNotesCommentModeration] Empty document snapshot — skipping.", { noteId, commentId });
            return null;
        }

        const rawText: string = (data.body ?? data.text ?? data.content ?? "").trim();
        const authorUid: string = data.authorUid ?? data.userId ?? "";

        logger.info("[churchNotesCommentModeration] Moderating", { noteId, commentId, authorUid });

        try {
            const result = await moderateText(rawText, "comment", false, commentId);

            if (result.enforcement === "block") {
                // Hard block — delete the document (client bypass scenario)
                await event.data!.ref.delete();
                await writeModerationLog(commentId, noteId, authorUid, "blocked", rawText, result.harmCategoryId);
                logger.warn("[churchNotesCommentModeration] Blocked", { commentId, harmCategoryId: result.harmCategoryId });
                return null;
            }

            if (!result.allowed) {
                // Needs human review — hide from other users until cleared
                await event.data!.ref.update({ moderationState: "pending" });
                await writeModerationLog(commentId, noteId, authorUid, "pending", rawText, result.harmCategoryId);
                logger.info("[churchNotesCommentModeration] Queued for review", { commentId });
                return null;
            }

            // Clean — approve and notify the note author
            await event.data!.ref.update({ moderationState: "approved" });
            await notifyNoteAuthor(noteId, commentId, authorUid, rawText);
            logger.info("[churchNotesCommentModeration] Approved", { commentId });

            return null;
        } catch (err) {
            // Fail open — log error but don't silently block a legitimate comment
            logger.error("[churchNotesCommentModeration] Unexpected error — failing open", err);
            await event.data?.ref.update({ moderationState: "approved" }).catch(() => undefined);
            return null;
        }
    }
);
