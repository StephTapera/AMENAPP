import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { enforceRateLimit, RateLimitConfig } from "./rateLimit";

const db = admin.firestore();
const options = { region: "us-central1", enforceAppCheck: true };

type AnyMap = Record<string, unknown>;

interface SourcePayload {
    sourceId: string;
    sourceType: string;
    sourceText: string;
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
    dueAt?: string;
    locationName?: string;
    scriptureReference?: string;
    resourceUrl?: string;
}

interface AnalysisPayload {
    id?: string;
    sourceId?: string;
    surface?: string;
    privacyTier: string;
    intentKind: string;
    objectClass: string;
    confidence: number;
    sensitivityLevel: string;
    detectedSignals: string[];
    explanation?: string;
    shouldSuppressCapsule: boolean;
}

function stringValue(value: unknown): string | undefined {
    return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function requireUid(request: CallableRequest<AnyMap>): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to use Amen Action Intelligence.");
    return uid;
}

function requireAppCheck(request: CallableRequest<AnyMap>): void {
    if (!request.app) {
        throw new HttpsError("failed-precondition", "App Check is required for Action Intelligence.");
    }
}

async function guard(request: CallableRequest<AnyMap>, actionName: string, maxCalls: number): Promise<string> {
    requireAppCheck(request);
    const uid = requireUid(request);
    const limit: RateLimitConfig = {
        name: `action_intelligence_${actionName}`,
        windowMs: 3_600_000,
        maxCalls,
    };
    await enforceRateLimit(uid, [limit]);
    return uid;
}

function sourceFrom(data: AnyMap): SourcePayload {
    const raw = (typeof data.source === "object" && data.source !== null ? data.source : data) as AnyMap;
    const sourceId = stringValue(raw.sourceId);
    const sourceType = stringValue(raw.sourceType);
    const sourceText = stringValue(raw.sourceText);
    if (!sourceId || !sourceType || !sourceText) {
        throw new HttpsError("invalid-argument", "sourceId, sourceType, and sourceText are required.");
    }
    return {
        sourceId,
        sourceType,
        sourceText,
        conversationId: stringValue(raw.conversationId),
        roomId: stringValue(raw.roomId),
        postId: stringValue(raw.postId),
        commentId: stringValue(raw.commentId),
        churchId: stringValue(raw.churchId),
        spaceId: stringValue(raw.spaceId),
        organizationId: stringValue(raw.organizationId),
        authorId: stringValue(raw.authorId),
        targetUserId: stringValue(raw.targetUserId),
        targetDisplayName: stringValue(raw.targetDisplayName),
        title: stringValue(raw.title),
        dueAt: stringValue(raw.dueAt),
        locationName: stringValue(raw.locationName),
        scriptureReference: stringValue(raw.scriptureReference),
        resourceUrl: stringValue(raw.resourceUrl),
    };
}

function analysisFrom(data: AnyMap): AnalysisPayload {
    const raw = (typeof data.analysis === "object" && data.analysis !== null ? data.analysis : {}) as AnyMap;
    return {
        id: stringValue(raw.id),
        sourceId: stringValue(raw.sourceId),
        surface: stringValue(raw.surface),
        privacyTier: stringValue(raw.privacyTier) ?? "tier_c",
        intentKind: stringValue(raw.intentKind) ?? "follow_up",
        objectClass: stringValue(raw.objectClass) ?? "commitment",
        confidence: typeof raw.confidence === "number" ? raw.confidence : 0,
        sensitivityLevel: stringValue(raw.sensitivityLevel) ?? "standard",
        detectedSignals: Array.isArray(raw.detectedSignals)
            ? raw.detectedSignals.filter((item): item is string => typeof item === "string")
            : [],
        explanation: stringValue(raw.explanation),
        shouldSuppressCapsule: raw.shouldSuppressCapsule === true,
    };
}

async function assertNotBlocked(uid: string, source: SourcePayload): Promise<void> {
    const otherId = source.targetUserId ?? source.authorId;
    if (!otherId || otherId === uid) return;
    const [blockedByMe, blockedMe] = await Promise.all([
        db.collection("users").doc(uid).collection("blockedUsers").doc(otherId).get(),
        db.collection("users").doc(otherId).collection("blockedUsers").doc(uid).get(),
    ]);
    if (blockedByMe.exists || blockedMe.exists) {
        throw new HttpsError("permission-denied", "Action blocked by user privacy settings.");
    }
}

async function createActionObject(
    uid: string,
    actionVerb: string,
    source: SourcePayload,
    analysis: AnalysisPayload,
    state = "active"
): Promise<string> {
    const ref = db.collection("actionIntelligenceObjects").doc();
    await ref.set({
        ownerId: uid,
        actionVerb,
        source,
        analysis,
        objectClass: analysis.objectClass,
        intentKind: analysis.intentKind,
        privacyTier: analysis.privacyTier,
        state,
        provenance: {
            createdBy: uid,
            createdVia: "amen_action_intelligence",
            sourceId: source.sourceId,
            sourceType: source.sourceType,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return ref.id;
}

async function audit(uid: string, actionVerb: string, source: SourcePayload, objectId: string | undefined, workflow: string): Promise<void> {
    await db.collection("actionIntelligenceAudit").add({
        uid,
        actionVerb,
        sourceId: source.sourceId,
        sourceType: source.sourceType,
        objectId: objectId ?? null,
        workflow,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function createInitiativeWorkflow(uid: string, actionVerb: string, source: SourcePayload, analysis: AnalysisPayload) {
    const objectId = await createActionObject(uid, actionVerb, source, analysis, "proposed");
    const initiativeRef = db.collection("amenInitiatives").doc();
    await initiativeRef.set({
        ownerId: uid,
        source,
        actionObjectId: objectId,
        title: source.title ?? "Community initiative",
        summary: source.sourceText,
        status: "draft_pending_leader_review",
        fundraisingStatus: actionVerb === "start_fundraiser" ? "stripe_model_required" : "not_requested",
        volunteerRoleCount: actionVerb === "create_volunteer_event" ? 1 : 0,
        prayerUpdateCount: 0,
        milestoneCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await initiativeRef.collection("milestones").add({
        title: "Initiative proposed",
        state: "pending_leader_review",
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { workflow: "initiative", objectId, result: { initiativeId: initiativeRef.id }, message: "Initiative draft saved for the right leaders." };
}

async function volunteerWorkflow(uid: string, actionVerb: string, source: SourcePayload, analysis: AnalysisPayload) {
    const objectId = await createActionObject(uid, actionVerb, source, analysis);
    const assignmentRef = db.collection("amenVolunteerAssignments").doc();
    await assignmentRef.set({
        ownerId: uid,
        assigneeId: source.targetUserId ?? uid,
        targetDisplayName: source.targetDisplayName ?? null,
        actionObjectId: objectId,
        source,
        status: actionVerb === "assign_volunteer" ? "pending_acceptance" : "offered",
        actionVerb,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { workflow: "volunteer_assignment", objectId, result: { assignmentId: assignmentRef.id }, message: "Volunteer workflow saved." };
}

async function memoryWorkflow(uid: string, actionVerb: string, source: SourcePayload, analysis: AnalysisPayload) {
    const objectId = await createActionObject(uid, actionVerb, source, analysis);
    await db.collection("users").doc(uid).collection("amenMemoryGraph").doc(objectId).set({
        ownerId: uid,
        actionObjectId: objectId,
        actionVerb,
        source,
        intentKind: analysis.intentKind,
        objectClass: analysis.objectClass,
        topics: analysis.detectedSignals,
        framing: "ebenezer_memory",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { workflow: "memory_graph", objectId, result: { memoryId: objectId }, message: "Amen saved this to your memory layer." };
}

async function relationshipWorkflow(uid: string, actionVerb: string, source: SourcePayload, analysis: AnalysisPayload) {
    const objectId = await createActionObject(uid, actionVerb, source, analysis);
    const signalRef = db.collection("amenRelationshipSignals").doc();
    await signalRef.set({
        ownerId: uid,
        targetUserId: source.targetUserId ?? source.authorId ?? null,
        targetDisplayName: source.targetDisplayName ?? null,
        actionObjectId: objectId,
        actionVerb,
        source,
        signalType: "care_connection",
        lastSignalAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { workflow: "relationship_signal", objectId, result: { signalId: signalRef.id }, message: "Relationship follow-up saved." };
}

async function knowledgeWorkflow(uid: string, actionVerb: string, source: SourcePayload, analysis: AnalysisPayload) {
    const objectId = await createActionObject(uid, actionVerb, source, analysis);
    const graphRef = db.collection("amenKnowledgeGraph").doc();
    const scopeId = source.spaceId ?? source.churchId ?? source.organizationId ?? source.roomId ?? source.conversationId ?? uid;
    const scopeType = source.spaceId ? "space" : source.churchId ? "church" : source.organizationId ? "organization" : source.roomId ? "room" : source.conversationId ? "conversation" : "user";
    await graphRef.set({
        ownerId: uid,
        actionObjectId: objectId,
        actionVerb,
        source,
        scopeId,
        scopeType,
        title: source.title ?? analysis.intentKind,
        text: source.sourceText,
        scriptureReference: source.scriptureReference ?? null,
        resourceUrl: source.resourceUrl ?? null,
        topics: analysis.detectedSignals,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { workflow: "knowledge_graph", objectId, result: { knowledgeNodeId: graphRef.id }, message: "Knowledge graph updated." };
}

async function routeWorkflow(uid: string, actionVerb: string, source: SourcePayload, analysis: AnalysisPayload) {
    if (analysis.shouldSuppressCapsule) {
        throw new HttpsError("failed-precondition", "This content is routed to human care instead of automated actions.");
    }
    if (["create_initiative", "invite_leaders", "start_fundraiser", "create_volunteer_event"].includes(actionVerb)) {
        return createInitiativeWorkflow(uid, actionVerb, source, analysis);
    }
    if (["volunteer", "assign_volunteer", "add_to_team"].includes(actionVerb)) {
        return volunteerWorkflow(uid, actionVerb, source, analysis);
    }
    if (["message_user", "send_encouragement", "schedule_follow_up"].includes(actionVerb)) {
        return relationshipWorkflow(uid, actionVerb, source, analysis);
    }
    if (["pray_now", "commit_to_pray", "set_prayer_reminder", "follow_updates", "add_to_prayer_list", "mark_complete", "release_commitment"].includes(actionVerb)) {
        return memoryWorkflow(uid, actionVerb, source, analysis);
    }
    return knowledgeWorkflow(uid, actionVerb, source, analysis);
}

export const executeAmenAction = onCall<AnyMap>(options, async (request) => {
    const uid = await guard(request, "execute", 120);
    const actionVerb = stringValue(request.data.actionVerb);
    if (!actionVerb) throw new HttpsError("invalid-argument", "actionVerb is required.");
    const source = sourceFrom(request.data);
    const analysis = analysisFrom(request.data);
    await assertNotBlocked(uid, source);
    const response = await routeWorkflow(uid, actionVerb, source, analysis);
    await audit(uid, actionVerb, source, response.objectId, response.workflow);
    return response;
});

export const createAmenInitiative = onCall<AnyMap>(options, async (request) => {
    const uid = await guard(request, "create_initiative", 30);
    const source = sourceFrom(request.data);
    const analysis = analysisFrom(request.data);
    await assertNotBlocked(uid, source);
    const response = await createInitiativeWorkflow(uid, stringValue(request.data.actionVerb) ?? "create_initiative", source, analysis);
    await audit(uid, "create_initiative", source, response.objectId, response.workflow);
    return response;
});

export const assignAmenVolunteer = onCall<AnyMap>(options, async (request) => {
    const uid = await guard(request, "assign_volunteer", 60);
    const source = sourceFrom(request.data);
    const analysis = analysisFrom(request.data);
    await assertNotBlocked(uid, source);
    const response = await volunteerWorkflow(uid, stringValue(request.data.actionVerb) ?? "assign_volunteer", source, analysis);
    await audit(uid, "assign_volunteer", source, response.objectId, response.workflow);
    return response;
});

export const indexAmenMemoryGraph = onCall<AnyMap>(options, async (request) => {
    const uid = await guard(request, "memory_graph", 120);
    const source = sourceFrom(request.data);
    const analysis = analysisFrom(request.data);
    const response = await memoryWorkflow(uid, stringValue(request.data.actionVerb) ?? "follow_updates", source, analysis);
    await audit(uid, "memory_graph", source, response.objectId, response.workflow);
    return response;
});

export const recordAmenRelationshipSignal = onCall<AnyMap>(options, async (request) => {
    const uid = await guard(request, "relationship_signal", 90);
    const source = sourceFrom(request.data);
    const analysis = analysisFrom(request.data);
    await assertNotBlocked(uid, source);
    const response = await relationshipWorkflow(uid, stringValue(request.data.actionVerb) ?? "schedule_follow_up", source, analysis);
    await audit(uid, "relationship_signal", source, response.objectId, response.workflow);
    return response;
});

export const writeAmenKnowledgeGraph = onCall<AnyMap>(options, async (request) => {
    const uid = await guard(request, "knowledge_graph", 120);
    const source = sourceFrom(request.data);
    const analysis = analysisFrom(request.data);
    const response = await knowledgeWorkflow(uid, stringValue(request.data.actionVerb) ?? "save_resource", source, analysis);
    await audit(uid, "knowledge_graph", source, response.objectId, response.workflow);
    return response;
});
