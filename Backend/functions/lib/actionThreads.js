"use strict";
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
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.inviteThreadParticipant = exports.archiveActionThread = exports.completeActionStep = exports.activateActionThread = exports.createActionThread = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const aclHelper_1 = require("./aclHelper");
const db = admin.firestore();
// ─── Helpers ─────────────────────────────────────────────────────────────────
function requireAuth(context) {
    if (!context.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    return context.auth.uid;
}
function assertOwner(uid, userId) {
    if (uid !== userId) {
        throw new https_1.HttpsError("permission-denied", "User mismatch");
    }
}
// isBlocked imported from shared aclHelper — do not duplicate inline.
async function areMutualFollows(userA, userB) {
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
function isActionThreadsEnabled() {
    return db.collection("serverFeatureFlags").doc("actionThreads")
        .get()
        .then(doc => doc.data()?.enabled === true)
        .catch(() => false);
}
// ─── Create Action Thread ─────────────────────────────────────────────────────
exports.createActionThread = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!(await isActionThreadsEnabled())) {
        throw new https_1.HttpsError("failed-precondition", "Action threads not enabled");
    }
    const { postId, postAuthorId, threadId, type, sensitivityLevel, title, description, visibility, suggestedSteps, suggestionId, } = data;
    if (!postId || !postAuthorId || !threadId) {
        throw new https_1.HttpsError("invalid-argument", "postId, postAuthorId, threadId required");
    }
    // Server-validate: caller must be the post author
    assertOwner(uid, postAuthorId);
    // Verify the post exists
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) {
        throw new https_1.HttpsError("not-found", "Post not found");
    }
    if (postDoc.data()?.authorId !== uid) {
        throw new https_1.HttpsError("permission-denied", "You are not the post author");
    }
    // Rate limit: max 10 action threads per post
    const existingThreads = await db.collection("posts").doc(postId)
        .collection("actionThreads")
        .limit(11)
        .get();
    if (existingThreads.size >= 10) {
        throw new https_1.HttpsError("resource-exhausted", "Too many threads on this post");
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
    const steps = suggestedSteps ?? [];
    steps.forEach((step, index) => {
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
exports.activateActionThread = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!(await isActionThreadsEnabled())) {
        throw new https_1.HttpsError("failed-precondition", "Action threads not enabled");
    }
    const { postId, threadId } = data;
    if (!postId || !threadId) {
        throw new https_1.HttpsError("invalid-argument", "postId, threadId required");
    }
    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const threadDoc = await threadRef.get();
    if (!threadDoc.exists) {
        throw new https_1.HttpsError("not-found", "Thread not found");
    }
    const thread = threadDoc.data();
    if (thread.creatorUserId !== uid) {
        throw new https_1.HttpsError("permission-denied", "Only the thread creator can activate it");
    }
    if (thread.state !== "draft") {
        throw new https_1.HttpsError("failed-precondition", "Thread must be in draft state");
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
exports.completeActionStep = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!(await isActionThreadsEnabled())) {
        throw new https_1.HttpsError("failed-precondition", "Action threads not enabled");
    }
    const { postId, threadId, stepId } = data;
    if (!postId || !threadId || !stepId) {
        throw new https_1.HttpsError("invalid-argument", "postId, threadId, stepId required");
    }
    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const stepRef = threadRef.collection("steps").doc(stepId);
    const [threadDoc, stepDoc] = await Promise.all([threadRef.get(), stepRef.get()]);
    if (!threadDoc.exists || !stepDoc.exists) {
        throw new https_1.HttpsError("not-found", "Thread or step not found");
    }
    const thread = threadDoc.data();
    const step = stepDoc.data();
    // Authorization: owner, coordinator, or assigned user
    const participantDoc = await threadRef.collection("participants").doc(uid).get();
    const participantRole = participantDoc.data()?.role;
    const isAuthorized = thread.creatorUserId === uid ||
        participantRole === "coordinator" ||
        step.assignedTo === uid;
    if (!isAuthorized) {
        throw new https_1.HttpsError("permission-denied", "Not authorized to complete this step");
    }
    if (thread.state !== "active") {
        throw new https_1.HttpsError("failed-precondition", "Thread must be active");
    }
    if (step.state === "completed") {
        throw new https_1.HttpsError("already-exists", "Step already completed");
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
exports.archiveActionThread = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!(await isActionThreadsEnabled())) {
        throw new https_1.HttpsError("failed-precondition", "Action threads not enabled");
    }
    const { postId, threadId } = data;
    if (!postId || !threadId) {
        throw new https_1.HttpsError("invalid-argument", "postId, threadId required");
    }
    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const threadDoc = await threadRef.get();
    if (!threadDoc.exists) {
        throw new https_1.HttpsError("not-found", "Thread not found");
    }
    const thread = threadDoc.data();
    if (thread.creatorUserId !== uid) {
        throw new https_1.HttpsError("permission-denied", "Only the thread creator can archive it");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const isComplete = thread.completedStepCount >= thread.totalStepCount && thread.totalStepCount > 0;
    const newState = isComplete ? "completed" : "archived";
    const batch = db.batch();
    const update = { state: newState, updatedAt: now };
    if (isComplete)
        update["completedAt"] = now;
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
exports.inviteThreadParticipant = (0, https_1.onCall)(async (request) => {
    const data = request.data;
    const context = { auth: request.auth, app: request.app };
    const uid = requireAuth(context);
    // 5.1 FIX: App Check enforcement.
    if (context.app == undefined) {
        throw new https_1.HttpsError("failed-precondition", "The function must be called from an App Check verified app.");
    }
    if (!(await isActionThreadsEnabled())) {
        throw new https_1.HttpsError("failed-precondition", "Action threads not enabled");
    }
    const { postId, threadId, targetUserId, role } = data;
    if (!postId || !threadId || !targetUserId) {
        throw new https_1.HttpsError("invalid-argument", "postId, threadId, targetUserId required");
    }
    if (targetUserId === uid) {
        throw new https_1.HttpsError("invalid-argument", "Cannot invite yourself");
    }
    const threadRef = db.collection("posts").doc(postId)
        .collection("actionThreads").doc(threadId);
    const threadDoc = await threadRef.get();
    if (!threadDoc.exists) {
        throw new https_1.HttpsError("not-found", "Thread not found");
    }
    const thread = threadDoc.data();
    if (thread.creatorUserId !== uid) {
        throw new https_1.HttpsError("permission-denied", "Only the thread owner can invite participants");
    }
    if (thread.state !== "active") {
        throw new https_1.HttpsError("failed-precondition", "Thread must be active to invite participants");
    }
    if (thread.participantCount >= 50) {
        throw new https_1.HttpsError("resource-exhausted", "Max participants reached");
    }
    // Server-side block check
    if (await (0, aclHelper_1.isBlocked)(uid, targetUserId)) {
        throw new https_1.HttpsError("permission-denied", "Cannot invite a blocked user");
    }
    // For sensitive threads: mutual follow required
    const sensitivity = thread.sensitivityLevel;
    if (sensitivity === "high" || sensitivity === "critical") {
        if (!(await areMutualFollows(uid, targetUserId))) {
            throw new https_1.HttpsError("permission-denied", "Sensitive support flows require mutual connections");
        }
    }
    // Check if already a participant
    const existingParticipant = await threadRef.collection("participants").doc(targetUserId).get();
    if (existingParticipant.exists && existingParticipant.data()?.status === "active") {
        throw new https_1.HttpsError("already-exists", "User is already a participant");
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
//# sourceMappingURL=actionThreads.js.map