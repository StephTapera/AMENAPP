import * as functions from "firebase-functions";
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

export const onPostCommentCreatedUpdateCount = functions.firestore
    .document("posts/{postId}/comments/{commentId}")
    .onCreate(async (_snap, context) => {
        await incrementPostCounter(context.params.postId, "commentCount", 1);
    });

export const onPostCommentDeletedUpdateCount = functions.firestore
    .document("posts/{postId}/comments/{commentId}")
    .onDelete(async (_snap, context) => {
        await incrementPostCounter(context.params.postId, "commentCount", -1);
    });

export const onPostRepostCreatedUpdateCount = functions.firestore
    .document("posts/{postId}/reposts/{repostId}")
    .onCreate(async (_snap, context) => {
        await incrementPostCounter(context.params.postId, "repostCount", 1);
    });

export const onPostRepostDeletedUpdateCount = functions.firestore
    .document("posts/{postId}/reposts/{repostId}")
    .onDelete(async (_snap, context) => {
        await incrementPostCounter(context.params.postId, "repostCount", -1);
    });
