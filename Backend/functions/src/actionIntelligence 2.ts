import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();
const REGION = "us-central1";

type ActionVerb =
    | "pray_now"
    | "commit_to_pray"
    | "set_prayer_reminder"
    | "follow_updates"
    | "add_to_prayer_list"
    | "save_verse"
    | "compare_translations"
    | "hear_audio"
    | "add_to_study_plan"
    | "rsvp"
    | "add_to_calendar"
    | "invite_friend"
    | "get_directions"
    | "volunteer"
    | "assign_volunteer"
    | "message_user"
    | "add_to_team"
    | "schedule_follow_up"
    | "create_initiative"
    | "invite_leaders"
    | "start_fundraiser"
    | "create_volunteer_event"
    | "save_to_church_notes"
    | "create_reading_plan"
    | "create_discussion"
    | "generate_study_questions"
    | "save_resource"
    | "start_learning"
    | "follow_creator"
    | "mark_complete"
    | "send_encouragement"
    | "release_commitment"
    | "answer_question"
    | "dismiss_suggestion";

type IntentKind =
    | "prayer_need"
    | "prayer_commitment"
    | "scripture_reference"
    | "event"
    | "volunteer_offer"
    | "volunteer_need"
    | "initiative_idea"
    | "study_prompt"
    | "creator_resource"
    | "open_question"
    | "follow_up";

type ObjectClass = "moment" | "commitment" | "need" | "initiative";
type PrivacyTier = "tier_p" | "tier_c" | "tier_s";

interface ActionSourcePayload {
    sourceId?: string;
    sourceType?: string;
    sourceText?: string;
    conversationId?: string;
    roomId?: string;
    postId?: string;
    commentId?: string;
    churchId?: string;
    spaceId?: string;
    organizationId?: string;
    authorId?: string;
    targetUserId?: string;
    targetDisplayName?: string;
    title?: string;
    dueAtMillis?: number;
    locationName?: string;
    scriptureReference?: string;
    resourceUrl?: string;
}

interface ActionAnalysisPayload {
    intentKind?: IntentKind;
    objectClass?: ObjectClass;
    confidence?: number;
    privacyTier?: PrivacyTier;
    detectedSignals?: string[];
    explanation?: string;
    sensitivityLevel?: string;
}

interface ExecuteActionPayload {
    actionVerb: ActionVerb;
    source: ActionSourcePayload;
    analysis?: ActionAnalysisPayload;
}

function requireUid(request: { auth?: { uid?: string } }): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function nonEmpty(value: unknown, fallback = ""): string {
    return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback;
}

function truncate(value: unknown, max: number): string | null {
    if (typeof value !== "string") return null;
    const trimmed = value.trim();
    if (!trimmed) return null;
    return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

function now() {
    return admin.firestore.FieldValue.serverTimestamp();
}

function objectClassForIntent(intentKind?: IntentKind): ObjectClass {
    switch (intentKind) {
    case "initiative_idea":
        return "initiative";
    case "prayer_need":
    case "volunteer_need":
        return "need";
    case "prayer_commitment":
    case "volunteer_offer":
    case "follow_up":
        return "commitment";
    default:
        return "moment";
    }
}

function requireAppCheck(request: { app?: { appId?: string } }) {
    if (!request.app?.appId) {
        throw new HttpsError("failed-precondition", "App Check verified app required.");
    }
}

async function assertNotBlocked(actorId: string, targetUserId?: string) {
    if (!targetUserId || actorId === targetUserId) return;
    const [forward, reverse] = await Promise.all([
        db.collection("blockedUsers").doc(`${actorId}_${targetUserId}`).get(),
        db.collection("blockedUsers").doc(`${targetUserId}_${actorId}`).get(),
    ]);
    if (forward.exists || reverse.exists) {
        throw new HttpsError("permission-denied", "Blocked relationship prevents this action.");
    }
}

async function assertSourceAccess(uid: string, source: ActionSourcePayload) {
    if (source.postId) {
        const post = await db.collection("posts").doc(source.postId).get();
        if (!post.exists) throw new HttpsError("not-found", "Source post not found.");
        const data = post.data() ?? {};
        const isAuthor = data.authorId === uid || data.userId === uid;
        const visibility = data.privacyLevel ?? data.visibility ?? "public";
        if (!isAuthor && visibility !== "public" && visibility !== "Everyone") {
            throw new HttpsError("permission-denied", "No access to source post.");
        }
    }
    if (source.spaceId) {
        const member = await db.collection("spaces").doc(source.spaceId)
            .collection("members").doc(uid).get();
        if (!member.exists) {
            throw new HttpsError("permission-denied", "Space membership required.");
        }
    }
}

function baseSource(source: ActionSourcePayload) {
    return {
        sourceId: nonEmpty(source.sourceId, nonEmpty(source.postId, nonEmpty(source.commentId, "unknown"))),
        sourceType: nonEmpty(source.sourceType, "unknown"),
        conversationId: source.conversationId ?? null,
        roomId: source.roomId ?? null,
        postId: source.postId ?? null,
        commentId: source.commentId ?? null,
        churchId: source.churchId ?? null,
        spaceId: source.spaceId ?? null,
        organizationId: source.organizationId ?? null,
        authorId: source.authorId ?? null,
        excerpt: truncate(source.sourceText, 500),
    };
}

function baseAnalysis(analysis: ActionAnalysisPayload | undefined) {
    return {
        intentKind: analysis?.intentKind ?? "follow_up",
        objectClass: analysis?.objectClass ?? objectClassForIntent(analysis?.intentKind),
        confidence: typeof analysis?.confidence === "number" ? Math.max(0, Math.min(1, analysis.confidence)) : null,
        privacyTier: analysis?.privacyTier ?? "tier_c",
        detectedSignals: Array.isArray(analysis?.detectedSignals) ? analysis?.detectedSignals.slice(0, 12) : [],
        explanation: truncate(analysis?.explanation, 500),
        sensitivityLevel: analysis?.sensitivityLevel ?? "standard",
    };
}

async function writeAudit(uid: string, actionVerb: ActionVerb, objectId: string, source: ActionSourcePayload) {
    await db.collection("actionIntelligenceAudit").doc().set({
        actorId: uid,
        actionVerb,
        objectId,
        source: baseSource(source),
        createdAt: now(),
    });
}

async function createObject(uid: string, actionVerb: ActionVerb, source: ActionSourcePayload, analysis?: ActionAnalysisPayload) {
    const analysisData = baseAnalysis(analysis);
    const ref = db.collection("actionIntelligenceObjects").doc();
    await ref.set({
        id: ref.id,
        ownerId: uid,
        actionVerb,
        ...analysisData,
        source: baseSource(source),
        state: actionVerb === "dismiss_suggestion" ? "dismissed" : "active",
        title: truncate(source.title, 140) ?? titleForAction(actionVerb, analysisData.intentKind),
        dueAt: typeof source.dueAtMillis === "number" ? admin.firestore.Timestamp.fromMillis(source.dueAtMillis) : null,
        targetUserId: source.targetUserId ?? null,
        createdAt: now(),
        updatedAt: now(),
    });
    await writeAudit(uid, actionVerb, ref.id, source);
    return ref;
}

function titleForAction(actionVerb: ActionVerb, intentKind: string): string {
    switch (actionVerb) {
    case "create_initiative": return "Initiative";
    case "volunteer":
    case "assign_volunteer": return "Volunteer Commitment";
    case "commit_to_pray":
    case "pray_now": return "Prayer Commitment";
    case "add_to_calendar":
    case "rsvp": return "Event Moment";
    case "save_verse": return "Saved Scripture";
    case "create_reading_plan": return "Reading Plan";
    default: return intentKind.replace(/_/g, " ");
    }
}

async function createInitiativeWorkflow(uid: string, source: ActionSourcePayload, analysis?: ActionAnalysisPayload) {
    await assertSourceAccess(uid, source);
    const objectRef = await createObject(uid, "create_initiative", source, {
        ...analysis,
        intentKind: "initiative_idea",
        objectClass: "initiative",
    });
    const initiativeRef = db.collection("amenInitiatives").doc();
    const batch = db.batch();
    batch.set(initiativeRef, {
        id: initiativeRef.id,
        ownerId: uid,
        status: "draft",
        title: truncate(source.title, 140) ?? "Community Initiative",
        source: baseSource(source),
        actionObjectId: objectRef.id,
        volunteerCount: 0,
        prayerUpdateCount: 0,
        resourceCount: 0,
        donationStatus: "not_configured",
        createdAt: now(),
        updatedAt: now(),
    });
    batch.set(initiativeRef.collection("milestones").doc(), {
        title: "Initiative drafted",
        status: "complete",
        createdAt: now(),
        completedAt: now(),
    });
    await batch.commit();
    return { workflow: "initiative", objectId: objectRef.id, initiativeId: initiativeRef.id };
}

async function assignVolunteerWorkflow(uid: string, source: ActionSourcePayload, actionVerb: ActionVerb, analysis?: ActionAnalysisPayload) {
    await assertSourceAccess(uid, source);
    await assertNotBlocked(uid, source.targetUserId);
    const objectRef = await createObject(uid, actionVerb, source, {
        ...analysis,
        intentKind: actionVerb === "assign_volunteer" ? "volunteer_offer" : "volunteer_need",
        objectClass: actionVerb === "assign_volunteer" ? "commitment" : "need",
    });
    const assignmentRef = db.collection("amenVolunteerAssignments").doc();
    await assignmentRef.set({
        id: assignmentRef.id,
        ownerId: uid,
        assigneeId: source.targetUserId ?? uid,
        assigneeDisplayName: truncate(source.targetDisplayName, 100),
        status: actionVerb === "assign_volunteer" ? "pending_confirmation" : "accepted",
        actionVerb,
        source: baseSource(source),
        actionObjectId: objectRef.id,
        createdAt: now(),
        updatedAt: now(),
    });
    return { workflow: "volunteer", objectId: objectRef.id, assignmentId: assignmentRef.id };
}

async function indexMemoryGraphWorkflow(uid: string, source: ActionSourcePayload, actionVerb: ActionVerb, analysis?: ActionAnalysisPayload) {
    await assertSourceAccess(uid, source);
    const objectRef = await createObject(uid, actionVerb, source, analysis);
    const memoryRef = db.collection("users").doc(uid).collection("amenMemoryGraph").doc();
    await memoryRef.set({
        id: memoryRef.id,
        ownerId: uid,
        actionObjectId: objectRef.id,
        actionVerb,
        source: baseSource(source),
        topics: buildTopics(source, analysis),
        privacyTier: analysis?.privacyTier ?? "tier_c",
        milestoneState: "active",
        createdAt: now(),
        updatedAt: now(),
    });
    return { workflow: "memory", objectId: objectRef.id, memoryId: memoryRef.id };
}

async function relationshipSignalWorkflow(uid: string, source: ActionSourcePayload, actionVerb: ActionVerb, analysis?: ActionAnalysisPayload) {
    if (!source.targetUserId) {
        return indexMemoryGraphWorkflow(uid, source, actionVerb, analysis);
    }
    await assertNotBlocked(uid, source.targetUserId);
    const objectRef = await createObject(uid, actionVerb, source, analysis);
    const edgeId = `${uid}_${source.targetUserId}`;
    await db.collection("amenRelationshipSignals").doc(edgeId).set({
        id: edgeId,
        ownerId: uid,
        targetUserId: source.targetUserId,
        targetDisplayName: truncate(source.targetDisplayName, 100),
        lastSignalAt: now(),
        lastActionVerb: actionVerb,
        source: baseSource(source),
        actionObjectIds: admin.firestore.FieldValue.arrayUnion(objectRef.id),
        quietNudgeCount: admin.firestore.FieldValue.increment(actionVerb === "schedule_follow_up" ? 1 : 0),
        updatedAt: now(),
    }, { merge: true });
    return { workflow: "relationship", objectId: objectRef.id, relationshipId: edgeId };
}

async function knowledgeGraphWorkflow(uid: string, source: ActionSourcePayload, actionVerb: ActionVerb, analysis?: ActionAnalysisPayload) {
    await assertSourceAccess(uid, source);
    const objectRef = await createObject(uid, actionVerb, source, analysis);
    const nodeRef = db.collection("amenKnowledgeGraph").doc();
    await nodeRef.set({
        id: nodeRef.id,
        ownerId: uid,
        scopeId: source.spaceId ?? source.churchId ?? source.organizationId ?? uid,
        scopeType: source.spaceId ? "space" : source.churchId ? "church" : source.organizationId ? "organization" : "user",
        actionObjectId: objectRef.id,
        actionVerb,
        intentKind: analysis?.intentKind ?? null,
        source: baseSource(source),
        scriptureReference: truncate(source.scriptureReference, 80),
        resourceUrl: truncate(source.resourceUrl, 500),
        topics: buildTopics(source, analysis),
        citation: {
            sourceId: source.sourceId ?? source.postId ?? source.commentId ?? null,
            sourceType: source.sourceType ?? null,
        },
        createdAt: now(),
        updatedAt: now(),
    });
    return { workflow: "knowledge", objectId: objectRef.id, nodeId: nodeRef.id };
}

function buildTopics(source: ActionSourcePayload, analysis?: ActionAnalysisPayload): string[] {
    const text = `${source.title ?? ""} ${source.sourceText ?? ""} ${source.scriptureReference ?? ""}`.toLowerCase();
    const topics = new Set<string>();
    if (analysis?.intentKind) topics.add(analysis.intentKind);
    ["prayer", "volunteer", "romans", "acts", "marriage", "leadership", "sermon", "course", "event"].forEach((term) => {
        if (text.includes(term)) topics.add(term);
    });
    return Array.from(topics).slice(0, 20);
}

export const createAmenInitiative = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request);
    const uid = requireUid(request);
    return createInitiativeWorkflow(uid, request.data?.source ?? {}, request.data?.analysis);
});

export const assignAmenVolunteer = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request);
    const uid = requireUid(request);
    const actionVerb = (request.data?.actionVerb ?? "volunteer") as ActionVerb;
    if (actionVerb !== "volunteer" && actionVerb !== "assign_volunteer" && actionVerb !== "create_volunteer_event") {
        throw new HttpsError("invalid-argument", "Volunteer action expected.");
    }
    return assignVolunteerWorkflow(uid, request.data?.source ?? {}, actionVerb, request.data?.analysis);
});

export const indexAmenMemoryGraph = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request);
    const uid = requireUid(request);
    return indexMemoryGraphWorkflow(uid, request.data?.source ?? {}, request.data?.actionVerb ?? "save_resource", request.data?.analysis);
});

export const recordAmenRelationshipSignal = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request);
    const uid = requireUid(request);
    return relationshipSignalWorkflow(uid, request.data?.source ?? {}, request.data?.actionVerb ?? "schedule_follow_up", request.data?.analysis);
});

export const writeAmenKnowledgeGraph = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request);
    const uid = requireUid(request);
    return knowledgeGraphWorkflow(uid, request.data?.source ?? {}, request.data?.actionVerb ?? "save_resource", request.data?.analysis);
});

export const executeAmenAction = onCall({ region: REGION, enforceAppCheck: true }, async (request) => {
    requireAppCheck(request);
    const uid = requireUid(request);
    const payload = request.data as ExecuteActionPayload;
    const actionVerb = payload.actionVerb;
    const source = payload.source ?? {};
    const analysis = payload.analysis;
    if (!actionVerb) {
        throw new HttpsError("invalid-argument", "actionVerb required.");
    }

    switch (actionVerb) {
    case "create_initiative":
    case "invite_leaders":
    case "start_fundraiser":
        return createInitiativeWorkflow(uid, source, analysis);
    case "volunteer":
    case "assign_volunteer":
    case "create_volunteer_event":
    case "add_to_team":
        return assignVolunteerWorkflow(uid, source, actionVerb, analysis);
    case "message_user":
    case "schedule_follow_up":
    case "send_encouragement":
        return relationshipSignalWorkflow(uid, source, actionVerb, analysis);
    case "save_verse":
    case "compare_translations":
    case "hear_audio":
    case "add_to_study_plan":
    case "save_to_church_notes":
    case "create_reading_plan":
    case "create_discussion":
    case "generate_study_questions":
    case "save_resource":
    case "start_learning":
    case "follow_creator":
    case "answer_question":
        return knowledgeGraphWorkflow(uid, source, actionVerb, analysis);
    default:
        return indexMemoryGraphWorkflow(uid, source, actionVerb, analysis);
    }
});
