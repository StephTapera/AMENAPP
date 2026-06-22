import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

// createCovenantThreadReply
//
// Callable function invoked by iOS CovenantService.sendThreadReply().
//
// Writes a reply to:
//   covenants/{covenantId}/rooms/{roomId}/messages/{parentMessageId}/replies/{replyId}
//
// Enforces in order:
//   1. Authentication + App Check (enforceAppCheck option)
//   2. Input validation (non-empty strings, body ≤ 4000 chars, ≤ 5 mentions)
//   3. Active membership in the covenant
//   4. Parent message existence, not deleted, not thread-locked
//
// Atomically (single Firestore batch):
//   - Creates reply document with all required fields
//   - Increments replyCount + lastReplyAt + updatedAt on the parent message
//
// Fire-and-forget: emits covenantActivityEvents record (failure does not fail the reply).

interface ThreadReplyInput {
    covenantId: string;
    roomId: string;
    parentMessageId: string;
    body: string;
    mentions?: string[];
}

export const createCovenantThreadReply = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        // ── 1. Auth ────────────────────────────────────────────────────────────
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;

        // ── 2. Input validation ────────────────────────────────────────────────
        const {
            covenantId,
            roomId,
            parentMessageId,
            body,
            mentions,
        } = (request.data ?? {}) as Partial<ThreadReplyInput>;

        if (
            typeof covenantId !== "string" || !covenantId.trim() ||
            typeof roomId !== "string" || !roomId.trim() ||
            typeof parentMessageId !== "string" || !parentMessageId.trim() ||
            typeof body !== "string" || !body.trim()
        ) {
            throw new HttpsError(
                "invalid-argument",
                "covenantId, roomId, parentMessageId, and body are required non-empty strings."
            );
        }

        const trimmedBody = body.trim();
        if (trimmedBody.length > 4000) {
            throw new HttpsError("invalid-argument", "Reply body exceeds 4000 characters.");
        }
        if (Array.isArray(mentions) && mentions.length > 5) {
            throw new HttpsError("invalid-argument", "Replies may not contain more than 5 mentions.");
        }

        const db = admin.firestore();

        // ── 3. Membership check ────────────────────────────────────────────────
        const memberSnap = await db
            .collection("covenantMemberships")
            .where("covenantId", "==", covenantId)
            .where("userId", "==", uid)
            .where("status", "in", ["active", "trialing"])
            .limit(1)
            .get();
        if (memberSnap.empty) {
            throw new HttpsError("permission-denied", "Not a member of this community.");
        }

        // ── 4. Parent message validation ──────────────────────────────────────
        const parentRef = db
            .collection("covenants").doc(covenantId)
            .collection("rooms").doc(roomId)
            .collection("messages").doc(parentMessageId);

        const parentSnap = await parentRef.get();
        if (!parentSnap.exists) {
            throw new HttpsError("not-found", "Parent message not found.");
        }
        const parentData = parentSnap.data()!;

        // Support both isDeleted (CovenantMessage Swift model) and deleted field conventions
        if (parentData.isDeleted === true || parentData.deleted === true) {
            throw new HttpsError("failed-precondition", "Cannot reply to a deleted message.");
        }
        if (parentData.threadLocked === true) {
            throw new HttpsError("failed-precondition", "This thread is locked.");
        }

        // ── 5. Fetch caller profile for denormalized display fields ───────────
        const userSnap = await db.collection("users").doc(uid).get();
        const userData = userSnap.data() ?? {};

        // ── 6. Atomic write ───────────────────────────────────────────────────
        const now = admin.firestore.FieldValue.serverTimestamp();
        const replyRef = parentRef.collection("replies").doc();

        const batch = db.batch();

        batch.set(replyRef, {
            id: replyRef.id,
            covenantId,
            roomId,
            parentMessageId,
            authorId: uid,
            authorDisplayName: (userData.displayName as string) ?? "Member",
            authorAvatarURL: (userData.avatarURL as string) ?? null,
            body: trimmedBody,
            mentions: mentions ?? [],
            isMarkedAnswer: false,
            moderationStatus: "clean",
            deleted: false,
            hidden: false,
            replyDepth: 1,
            createdAt: now,
            updatedAt: now,
        });

        batch.update(parentRef, {
            replyCount: admin.firestore.FieldValue.increment(1),
            lastReplyAt: now,
            updatedAt: now,
        });

        await batch.commit();

        // ── 7. Activity event (fire-and-forget, non-blocking) ─────────────────
        db.collection("covenantActivityEvents").add({
            type: "covenant_thread_reply_created",
            covenantId,
            roomId,
            parentMessageId,
            replyId: replyRef.id,
            authorId: uid,
            createdAt: now,
        }).catch(() => {
            // Activity event failure must not fail the reply write.
        });

        return { ok: true, replyId: replyRef.id };
    }
);
