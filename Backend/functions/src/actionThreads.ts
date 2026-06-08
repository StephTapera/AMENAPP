/**
 * actionThreads.ts
 *
 * Server-authoritative Cloud Functions for Action Thread workflows.
 *
 * WHY SERVER-SIDE:
 *   - Thread creation and state transitions must be validated server-side to prevent
 *     client-side tampering (e.g., forging postAuthorId, bypassing participant limits)
 *   - Sensitive care workflows (crisis escalation, high-sensitivity threads) require
 *     server-side audit logging that cannot be bypassed
 *   - Block/follow checks for participant invitations must happen server-side
 *
 * FUNCTIONS:
 *   createActionThread      — validates + creates thread + initial participants + steps + audit
 *   activateActionThread    — state transition: draft → active
 *   completeActionStep      — marks a step complete, updates thread counters
 *   archiveActionThread     — state transition to archived/completed
 *   inviteThreadParticipant — adds participant with server-validated block + follow checks
 *   scheduleActionReminder  — writes a reminder document for the FCM scheduler
 *
 * SECURITY:
 *   - All functions require Firebase Auth
 *   - Thread creation requires caller to be the post author (verified server-side)
 *   - State transitions require caller to be the thread creator
 *   - Participant invitations check block relationships server-side
 *   - Rate limiting: max 10 threads per post, max 50 participants per thread
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

function requireAuth(context: functions.https.CallableContext): string {
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Authentication required");
    }
    return context.auth.uid;
}

function assertOwner(uid: string, userId: string): void {
    if (uid !== userId) {
        throw new HttpsError("permission-denied", "User mismatch");
    }
}

async function isBlocked(userA: string, userB: string): Promise<boolean> {
    const [ab, ba] = await Promise.all([
        db.collection("blockedUsers").doc(`${userA}_${userB}`).get(),
        db.collection("blockedUsers").doc(`${userB}_${userA}`).get(),
    ]);
    return ab.exists || ba.exists;
}

async function areMutualFollows(userA: string, userB: string): Promise<boolean> {
    const [ab, ba] = await Promise.all([
        db.collection("follows")
            .where("followerId", "==", userA)
            .where("followedId", "==", userB)
            .limit(1)
            .get(),
        db.collection("follows")
            .where("followerId", "==", userB)
            .where("followedId", "==", userA)
            .limit(1)
            .get(),
    ]);
    return !ab.empty && !ba.empty;
}

function isActionThreadsEnabled(): Promise<boolean> {
    return db.collection("serverFeatureFlags").doc("actionThreads")
        .get()
        .then(doc => doc.data()?.enabled === true)
        .catch(() => false);
}

// ─── Create Action Thread ─────────────────────────────────────────────────────

export const createActionThread = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    if (!(await isActionThreadsEnabled())) {
        throw new HttpsError("failed-precondition", "Action threads not enabled");
    }

    const {
        postId,
        postAuthorId,
        threadId,
        type,
        sensitivityLevel,
        title,
        description,
        visibility,
        suggestedSteps,
        suggestionId,
    } = data;

    if (!postId || !postAuthorId || !threadId) {
        throw new HttpsError("invalid-argument", "postId, postAuthorId, threadId required");
    }

    // Server-validate: caller must be the post author
    assertOwner(uid, postAuthorId);

    // Verify the post exists
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) {
        throw new HttpsError("not-found", "Post not found");
    }
    if (postDoc.data()?.authorId !== uid) {
        throw new HttpsError("permission-denied", "You are not the post author");
    }

    // Rate limit: max 10 action threads per post
    const existingThreads = await db.collection("posts").doc(postId)
        .collection("actionThreads")
        .limit(11)
        .get();
    if (existingThreads.size >= 10) {
        throw new HttpsError("resource-exhausted", "Too many threads on this post");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

    const batch = db.batch();

    // Thread document
    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);

    batch.set(threadRef, {
        id: threadId,
        postId,
        postAuthorId,
        creatorUserId: uid,
        type: type ?? "prayer_circle",
        visibility: visibility ?? "owner_only",
        state: "draft",
        sensitivityLevel: sensitivityLevel ?? "standard",
        title: title ?? null,
        description: description ?? null,
        createdAt: now,
        updatedAt: now,
        expiresAt,
        participantCount: 1,
        completedStepCount: 0,
        totalStepCount: (suggestedSteps ?? []).length,
    });

    // Owner participant
    const participantRef = threadRef.collection("participants").doc(uid);
    batch.set(participantRef, {
        id: uid,
        userId: uid,
        role: "owner",
        status: "active",
        joinedAt: now,
        lastActiveAt: now,
    });

    // Steps
    const steps: Array<object> = suggestedSteps ?? [];
    steps.forEach((step: any, index: number) => {
        const stepId = db.collection("_").doc().id;
        const stepRef = threadRef.collection("steps").doc(stepId);
        const scheduledFor = step.scheduledOffset
            ? new Date(Date.now() + step.scheduledOffset * 1000)
            : null;
        batch.set(stepRef, {
            id: stepId,
            threadId,
            title: step.title ?? "Step",
            type: step.type ?? "custom",
            state: "pending",
            sortOrder: index,
            createdAt: now,
            scheduledFor,
            expiresAt,
            assignedTo: uid,
        });
    });

    // Audit entry
    const auditId = db.collection("_").doc().id;
    const auditRef = threadRef.collection("audit").doc(auditId);
    batch.set(auditRef, {
        id: auditId,
        threadId,
        actorUserId: uid,
        action: "thread_created",
        detail: suggestionId ? `From suggestion: ${suggestionId}` : "Manual creation",
        timestamp: now,
        metadata: { suggestionId: suggestionId ?? null },
    });

    await batch.commit();

    // Trust signal: thread creation = positive human signal
    await db.collection("users").doc(uid)
        .collection("trust").doc("events")
        .collection("items").doc(db.collection("_").doc().id)
        .set({
            userId: uid,
            eventType: "post_created",
            category: "human",
            value: 0.2,
            source: "createActionThread",
            relatedEntityId: threadId,
            timestamp: now,
        });

    return { ok: true, threadId };
});

// ─── Activate Action Thread ───────────────────────────────────────────────────

export const activateActionThread = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    if (!(await isActionThreadsEnabled())) {
        throw new HttpsError("failed-precondition", "Action threads not enabled");
    }

    const { postId, threadId } = data;
    if (!postId || !threadId) {
        throw new HttpsError("invalid-argument", "postId, threadId required");
    }

    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const threadDoc = await threadRef.get();

    if (!threadDoc.exists) {
        throw new HttpsError("not-found", "Thread not found");
    }

    const thread = threadDoc.data()!;
    if (thread.creatorUserId !== uid) {
        throw new HttpsError("permission-denied", "Only the thread creator can activate it");
    }
    if (thread.state !== "draft") {
        throw new HttpsError("failed-precondition", "Thread must be in draft state");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();

    batch.update(threadRef, { state: "active", updatedAt: now });

    const auditId = db.collection("_").doc().id;
    batch.set(threadRef.collection("audit").doc(auditId), {
        id: auditId,
        threadId,
        actorUserId: uid,
        action: "thread_activated",
        timestamp: now,
    });

    await batch.commit();
    return { ok: true };
});

// ─── Complete Action Step ─────────────────────────────────────────────────────

export const completeActionStep = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    if (!(await isActionThreadsEnabled())) {
        throw new HttpsError("failed-precondition", "Action threads not enabled");
    }

    const { postId, threadId, stepId } = data;
    if (!postId || !threadId || !stepId) {
        throw new HttpsError("invalid-argument", "postId, threadId, stepId required");
    }

    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const stepRef = threadRef.collection("steps").doc(stepId);

    const [threadDoc, stepDoc] = await Promise.all([threadRef.get(), stepRef.get()]);

    if (!threadDoc.exists || !stepDoc.exists) {
        throw new HttpsError("not-found", "Thread or step not found");
    }

    const thread = threadDoc.data()!;
    const step = stepDoc.data()!;

    // Authorization: owner, coordinator, or assigned user
    const participantDoc = await threadRef.collection("participants").doc(uid).get();
    const participantRole = participantDoc.data()?.role;
    const isAuthorized =
        thread.creatorUserId === uid ||
        participantRole === "coordinator" ||
        step.assignedTo === uid;

    if (!isAuthorized) {
        throw new HttpsError("permission-denied", "Not authorized to complete this step");
    }
    if (thread.state !== "active") {
        throw new HttpsError("failed-precondition", "Thread must be active");
    }
    if (step.state === "completed") {
        throw new HttpsError("already-exists", "Step already completed");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();

    batch.update(stepRef, {
        state: "completed",
        completedAt: now,
        completedBy: uid,
        updatedAt: now,
    });

    batch.update(threadRef, {
        completedStepCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });

    const auditId = db.collection("_").doc().id;
    batch.set(threadRef.collection("audit").doc(auditId), {
        id: auditId,
        threadId,
        actorUserId: uid,
        action: "step_completed",
        detail: stepId,
        timestamp: now,
        metadata: { stepId },
    });

    await batch.commit();

    // Care trust event: completing a step = positive care signal
    await db.collection("users").doc(uid)
        .collection("trust").doc("events")
        .collection("items").doc(db.collection("_").doc().id)
        .set({
            userId: uid,
            eventType: "action_step_completed",
            category: "care",
            value: 0.3,
            source: "completeActionStep",
            relatedEntityId: threadId,
            timestamp: now,
        });

    return { ok: true };
});

// ─── Archive Action Thread ────────────────────────────────────────────────────

export const archiveActionThread = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    if (!(await isActionThreadsEnabled())) {
        throw new HttpsError("failed-precondition", "Action threads not enabled");
    }

    const { postId, threadId } = data;
    if (!postId || !threadId) {
        throw new HttpsError("invalid-argument", "postId, threadId required");
    }

    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const threadDoc = await threadRef.get();

    if (!threadDoc.exists) {
        throw new HttpsError("not-found", "Thread not found");
    }

    const thread = threadDoc.data()!;
    if (thread.creatorUserId !== uid) {
        throw new HttpsError("permission-denied", "Only the thread creator can archive it");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const isComplete = thread.completedStepCount >= thread.totalStepCount && thread.totalStepCount > 0;
    const newState = isComplete ? "completed" : "archived";

    const batch = db.batch();
    const update: Record<string, any> = { state: newState, updatedAt: now };
    if (isComplete) update["completedAt"] = now;
    batch.update(threadRef, update);

    const auditId = db.collection("_").doc().id;
    batch.set(threadRef.collection("audit").doc(auditId), {
        id: auditId,
        threadId,
        actorUserId: uid,
        action: isComplete ? "thread_completed" : "thread_archived",
        timestamp: now,
    });

    await batch.commit();

    if (isComplete) {
        // Completing a full thread is a strong care signal
        await db.collection("users").doc(uid)
            .collection("trust").doc("events")
            .collection("items").doc(db.collection("_").doc().id)
            .set({
                userId: uid,
                eventType: "action_step_completed",
                category: "care",
                value: 0.5,
                source: "archiveActionThread",
                relatedEntityId: threadId,
                timestamp: now,
            });
    }

    return { ok: true, finalState: newState };
});

// ─── Invite Participant ───────────────────────────────────────────────────────

export const inviteThreadParticipant = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }

    if (!(await isActionThreadsEnabled())) {
        throw new HttpsError("failed-precondition", "Action threads not enabled");
    }

    const { postId, threadId, targetUserId, role } = data;
    if (!postId || !threadId || !targetUserId) {
        throw new HttpsError("invalid-argument", "postId, threadId, targetUserId required");
    }

    if (targetUserId === uid) {
        throw new HttpsError("invalid-argument", "Cannot invite yourself");
    }

    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const threadDoc = await threadRef.get();

    if (!threadDoc.exists) {
        throw new HttpsError("not-found", "Thread not found");
    }

    const thread = threadDoc.data()!;
    if (thread.creatorUserId !== uid) {
        throw new HttpsError("permission-denied", "Only the thread owner can invite participants");
    }
    if (thread.state !== "active") {
        throw new HttpsError("failed-precondition", "Thread must be active to invite participants");
    }
    if (thread.participantCount >= 50) {
        throw new HttpsError("resource-exhausted", "Max participants reached");
    }

    // Server-side block check
    if (await isBlocked(uid, targetUserId)) {
        throw new HttpsError("permission-denied", "Cannot invite a blocked user");
    }

    // For sensitive threads: mutual follow required
    const sensitivity = thread.sensitivityLevel;
    if (sensitivity === "high" || sensitivity === "critical") {
        if (!(await areMutualFollows(uid, targetUserId))) {
            throw new HttpsError(
                "permission-denied",
                "Sensitive support flows require mutual connections"
            );
        }
    }

    // Check if already a participant
    const existingParticipant = await threadRef.collection("participants").doc(targetUserId).get();
    if (existingParticipant.exists && existingParticipant.data()?.status === "active") {
        throw new HttpsError("already-exists", "User is already a participant");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();

    const participantRef = threadRef.collection("participants").doc(targetUserId);
    batch.set(participantRef, {
        id: targetUserId,
        userId: targetUserId,
        role: role ?? "supporter",
        status: "invited",
        joinedAt: now,
    });

    batch.update(threadRef, {
        participantCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
    });

    const auditId = db.collection("_").doc().id;
    batch.set(threadRef.collection("audit").doc(auditId), {
        id: auditId,
        threadId,
        actorUserId: uid,
        action: "participant_added",
        detail: targetUserId,
        timestamp: now,
        metadata: { targetUserId, role: role ?? "supporter" },
    });

    await batch.commit();

    // Trust event for the inviter: joining support = care signal
    await db.collection("users").doc(uid)
        .collection("trust").doc("events")
        .collection("items").doc(db.collection("_").doc().id)
        .set({
            userId: uid,
            eventType: "support_thread_joined",
            category: "care",
            value: 0.2,
            source: "inviteThreadParticipant",
            relatedEntityId: threadId,
            timestamp: now,
        });

    return { ok: true };
});
