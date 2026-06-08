import * as functions from "firebase-functions";
import { onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const db = admin.firestore();

async function incrementPostCounter(postId: string, field: string, delta: 1 | -1): Promise<void> {
    const postRef = db.collection("posts").doc(postId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(postRef);
        if (!snap.exists) return;
        const current = Number(snap.data()?.[field] ?? 0);
        tx.update(postRef, {
            [field]: Math.max(0, current + delta),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
}

export const onPostCommentCreatedUpdateCount = onDocumentCreated("posts/{postId}/comments/{commentId}", async (event) => {
    const context = { params: event.params };
        await incrementPostCounter(context.params.postId, "commentCount", 1);
    });

export const onPostCommentDeletedUpdateCount = onDocumentDeleted("posts/{postId}/comments/{commentId}", async (event) => {
    const context = { params: event.params };
        await incrementPostCounter(context.params.postId, "commentCount", -1);
    });

export const onPostRepostCreatedUpdateCount = onDocumentCreated("posts/{postId}/reposts/{repostId}", async (event) => {
    const context = { params: event.params };
        await incrementPostCounter(context.params.postId, "repostCount", 1);
    });

export const onPostRepostDeletedUpdateCount = onDocumentDeleted("posts/{postId}/reposts/{repostId}", async (event) => {
    const context = { params: event.params };
        await incrementPostCounter(context.params.postId, "repostCount", -1);
    });
