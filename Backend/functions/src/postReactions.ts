import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {requireAuthAndAppCheck} from "./amenAI/common";
import {enforceRateLimit, RateLimitConfig} from "./rateLimit";

const db = admin.firestore();

const REACTION_LIMITS: RateLimitConfig[] = [
    {name: "post_reaction_1min", windowMs: 60_000, maxCalls: 60},
    {name: "post_reaction_1day", windowMs: 86_400_000, maxCalls: 1_000},
];

const REACTION_CONFIG = {
    amen: {collection: "amens", countField: "amenCount"},
    lightbulb: {collection: "lightbulbs", countField: "lightbulbCount"},
} as const;

type ReactionKind = keyof typeof REACTION_CONFIG;

function parseReactionKind(value: unknown): ReactionKind {
    const kind = String(value ?? "").trim();
    if (kind === "amen" || kind === "lightbulb") return kind;
    throw new HttpsError("invalid-argument", "reactionType must be amen or lightbulb.");
}

async function assertCallerActive(uid: string): Promise<void> {
    const userSnap = await db.collection("users").doc(uid).get();
    const data = userSnap.data() ?? {};
    if (data.isDeactivated === true || data.deletionStatus !== undefined && data.deletionStatus !== "none") {
        throw new HttpsError("permission-denied", "Account cannot react in its current state.");
    }
}

async function assertNotBlocked(uid: string, authorId: string): Promise<void> {
    const [blockedByCaller, blockedByAuthor, topLevelA, topLevelB] = await Promise.all([
        db.collection("users").doc(uid).collection("blockedUsers").doc(authorId).get(),
        db.collection("users").doc(authorId).collection("blockedUsers").doc(uid).get(),
        db.collection("blockedUsers").doc(`${uid}_${authorId}`).get(),
        db.collection("blockedUsers").doc(`${authorId}_${uid}`).get(),
    ]);
    if (blockedByCaller.exists || blockedByAuthor.exists || topLevelA.exists || topLevelB.exists) {
        throw new HttpsError("permission-denied", "Reaction is not available for this post.");
    }
}

export const togglePostReaction = onCall(
    {enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB"},
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await assertCallerActive(uid);
        await enforceRateLimit(uid, REACTION_LIMITS);

        const postId = String(request.data?.postId ?? "").trim();
        if (!postId) throw new HttpsError("invalid-argument", "postId required.");
        const reactionType = parseReactionKind(request.data?.reactionType);
        const config = REACTION_CONFIG[reactionType];

        const postRef = db.collection("posts").doc(postId);
        const reactionRef = postRef.collection(config.collection).doc(uid);

        let isActive = false;
        let count = 0;

        await db.runTransaction(async (tx) => {
            const [postSnap, reactionSnap] = await Promise.all([
                tx.get(postRef),
                tx.get(reactionRef),
            ]);
            if (!postSnap.exists) throw new HttpsError("not-found", "Post not found.");

            const post = postSnap.data() ?? {};
            if (post.removed === true || post.flaggedForReview === true) {
                throw new HttpsError("failed-precondition", "This post is not available for reactions.");
            }
            const moderationStatus = String(post.moderationStatus ?? "approved");
            if (!["approved", "passed", "reviewed", "clean"].includes(moderationStatus)) {
                throw new HttpsError("failed-precondition", "This post is not available for reactions.");
            }
            await assertNotBlocked(uid, String(post.authorId ?? ""));

            const current = Number(post[config.countField] ?? 0);
            if (reactionSnap.exists) {
                tx.delete(reactionRef);
                count = Math.max(0, current - 1);
                isActive = false;
            } else {
                tx.set(reactionRef, {
                    userId: uid,
                    reactionType,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                count = current + 1;
                isActive = true;
            }
            tx.update(postRef, {
                [config.countField]: count,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });

        return {postId, reactionType, isActive, count};
    }
);
