import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {enforceRateLimit, RATE_LIMITS} from "../rateLimit";

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const VALID_OBJECT_TYPES = new Set([
    "user",
    "organization",
    "church",
    "team",
    "space",
    "post",
    "prayer",
    "discussion",
    "study",
    "event",
    "volunteerOpportunity",
    "mentorship",
    "job",
    "churchNote",
    "bereanInsight",
    "mediaObject",
    "moment",
    "actionThread",
]);

const VALID_INTENTS = new Set([
    "share",
    "discuss",
    "pray",
    "study",
    "teach",
    "ask",
    "invite",
    "volunteer",
    "hire",
    "mentor",
    "announce",
]);

const VALID_EDGE_TYPES = new Set(["belongsTo", "spawnedFrom", "links", "follows", "praysFor"]);
const VALID_VISIBILITY = new Set(["public", "members", "private"]);
const VALID_ROLES = new Set([
    "owner",
    "executive_admin",
    "pastor",
    "leader",
    "moderator",
    "volunteer_lead",
    "content_manager",
    "event_manager",
    "member",
    "visitor",
    "minor",
]);

type AmenObjectType =
    | "user"
    | "organization"
    | "church"
    | "team"
    | "space"
    | "post"
    | "prayer"
    | "discussion"
    | "study"
    | "event"
    | "volunteerOpportunity"
    | "mentorship"
    | "job"
    | "churchNote"
    | "bereanInsight"
    | "mediaObject"
    | "moment"
    | "actionThread";

type AmenIntent =
    | "share"
    | "discuss"
    | "pray"
    | "study"
    | "teach"
    | "ask"
    | "invite"
    | "volunteer"
    | "hire"
    | "mentor"
    | "announce";

type ModerationTier = "low" | "medium" | "high" | "severe";

interface TransformRequest {
    sourceRef: string;
    sourceType: AmenObjectType;
    intent: AmenIntent;
    actorId?: string;
    audienceOverride?: string;
}

interface EdgeRequest {
    fromRef: string;
    fromType: string;
    toRef: string;
    toType: string;
    edgeType: string;
    visibility: string;
}

function requireAuth(request: { auth?: { uid: string } }): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function requireApp(request: { app?: unknown }): void {
    if (!request.app) {
        throw new HttpsError("unauthenticated", "App Check required.");
    }
}

function cleanPath(path: unknown, field: string): string {
    const value = String(path ?? "").trim().replace(/^\/+/, "");
    if (!value || value.includes("//") || value.split("/").length < 2) {
        throw new HttpsError("invalid-argument", `${field} must be a Firestore document path.`);
    }
    return value;
}

function cleanEnum<T extends string>(value: unknown, allowed: Set<string>, field: string): T {
    const raw = String(value ?? "").trim();
    if (!allowed.has(raw)) {
        throw new HttpsError("invalid-argument", `${field} is invalid.`);
    }
    return raw as T;
}

function stableEdgeId(fromRef: string, toRef: string, edgeType: string): string {
    return Buffer.from(`${fromRef}|${toRef}|${edgeType}`)
        .toString("base64url")
        .slice(0, 120);
}

function uidFromRef(ref: string): string | null {
    const parts = ref.split("/");
    return parts[0] === "users" && parts[1] ? parts[1] : null;
}

function collectionForObjectType(type: AmenObjectType): string {
    switch (type) {
    case "churchNote": return "churchNotes";
    case "bereanInsight": return "bereanInsights";
    case "mediaObject": return "mediaObjects";
    case "actionThread": return "actionThreads";
    case "volunteerOpportunity": return "volunteerOpportunities";
    default: return `${type}s`;
    }
}

function resultTypeForIntent(intent: AmenIntent): AmenObjectType {
    switch (intent) {
    case "discuss": return "discussion";
    case "pray": return "actionThread";
    case "study": return "study";
    case "volunteer": return "volunteerOpportunity";
    case "mentor": return "mentorship";
    case "hire": return "job";
    default: return "post";
    }
}

function moderationTierFor(sourceType: AmenObjectType, intent: AmenIntent): ModerationTier {
    if (intent === "announce" || intent === "hire") return "high";
    if (sourceType === "prayer" || intent === "pray" || intent === "mentor") return "medium";
    return "low";
}

function audienceFor(intent: AmenIntent, override: unknown): { appliedAudience: string; warnings: string[] } {
    const requested = typeof override === "string" && override.trim() ? override.trim() : null;
    const ceilingByIntent: Record<AmenIntent, string[]> = {
        share: ["public", "members", "private"],
        discuss: ["members", "private"],
        pray: ["private"],
        study: ["members", "private"],
        teach: ["public", "members", "private"],
        ask: ["members", "private"],
        invite: ["members", "private"],
        volunteer: ["members", "private"],
        hire: ["members", "private"],
        mentor: ["private"],
        announce: ["public", "members", "private"],
    };

    const allowed = ceilingByIntent[intent];
    if (requested && allowed.includes(requested)) {
        return {appliedAudience: requested, warnings: []};
    }

    const fallback = allowed[0];
    return {
        appliedAudience: fallback,
        warnings: requested ? [`Audience clamped from ${requested} to ${fallback}.`] : [],
    };
}

function suggestedActions(intent: AmenIntent, sourceType: AmenObjectType, role: string): Array<Record<string, string>> {
    const actions: Array<Record<string, string>> = [];
    if (intent === "discuss") {
        actions.push({id: "summarize_context", label: "Summarize context", kind: "berean_summary"});
        actions.push({id: "invite_relevant_people", label: "Invite relevant people", kind: "relationship_graph"});
    }
    if (intent === "pray" || sourceType === "prayer") {
        actions.push({id: "set_prayer_nudge", label: "Set prayer nudge", kind: "gentle_follow_up"});
    }
    if (intent === "study" || sourceType === "bereanInsight" || sourceType === "churchNote") {
        actions.push({id: "continue_study", label: "Continue study", kind: "berean_recall"});
    }
    if (["leader", "pastor", "owner", "executive_admin"].includes(role)) {
        actions.push({id: "share_with_team", label: "Share with team", kind: "role_aware"});
    }
    return actions.slice(0, 3);
}

async function resolveRoleFor(uid: string, resourceRef: string): Promise<string> {
    const user = await db.collection("users").doc(uid).get();
    const userData = user.data() ?? {};
    const profileRole = String(userData.role ?? userData.amenRole ?? "member");
    if (VALID_ROLES.has(profileRole)) return profileRole;

    const resourceParts = resourceRef.split("/");
    const churchId = resourceParts[0] === "churches" ? resourceParts[1] : String(userData.churchId ?? "");
    if (churchId) {
        const member = await db.doc(`churches/${churchId}/members/${uid}`).get();
        const memberRole = String(member.data()?.role ?? "");
        if (VALID_ROLES.has(memberRole)) return memberRole;
    }

    return "member";
}

export const resolveRBACRole = onCall(
    {region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB"},
    async (request) => {
        const uid = requireAuth(request);
        requireApp(request);
        await enforceRateLimit(uid, [{...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_rbac_1min", maxCalls: 30}]);

        const requestedUserId = String(request.data?.userId ?? uid);
        if (requestedUserId !== uid) {
            throw new HttpsError("permission-denied", "Cannot resolve another user's role.");
        }

        const resourceRef = cleanPath(request.data?.resourceRef, "resourceRef");
        const role = await resolveRoleFor(uid, resourceRef);
        return {role};
    }
);

export const createEdge = onCall(
    {region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB"},
    async (request) => {
        const uid = requireAuth(request);
        requireApp(request);
        await enforceRateLimit(uid, [{...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_edge_1min", maxCalls: 30}]);

        const body = request.data as EdgeRequest;
        const fromRef = cleanPath(body.fromRef, "fromRef");
        const toRef = cleanPath(body.toRef, "toRef");
        const fromType = cleanEnum<string>(body.fromType, VALID_OBJECT_TYPES, "fromType");
        const toType = cleanEnum<string>(body.toType, VALID_OBJECT_TYPES, "toType");
        const edgeType = cleanEnum<string>(body.edgeType, VALID_EDGE_TYPES, "edgeType");
        const visibility = cleanEnum<string>(body.visibility, VALID_VISIBILITY, "visibility");
        const edgeId = stableEdgeId(fromRef, toRef, edgeType);
        const nowMillis = Date.now();
        const fromUid = uidFromRef(fromRef) ?? uid;
        const toUid = uidFromRef(toRef) ?? "";

        if (fromUid !== uid && edgeType === "follows") {
            throw new HttpsError("permission-denied", "Cannot create a follow edge for another user.");
        }

        const doc = {
            fromRef,
            fromType,
            toRef,
            toType,
            edgeType,
            createdBy: uid,
            fromUid,
            toUid,
            visibility,
            createdAt: FieldValue.serverTimestamp(),
            createdAtMillis: nowMillis,
            isDeleted: false,
            provenance: {
                sourceType: fromType,
                sourceRef: fromRef,
                sourceOwnerId: fromUid,
                intent: edgeType,
                createdAt: FieldValue.serverTimestamp(),
            },
        };

        await db.collection("edges").doc(edgeId).set(doc, {merge: false});
        return {
            ...doc,
            createdAt: Math.floor(nowMillis / 1000),
            provenance: {
                sourceType: fromType,
                sourceRef: fromRef,
                sourceOwnerId: fromUid,
                intent: edgeType,
                createdAt: Math.floor(nowMillis / 1000),
            },
        };
    }
);

export const getEdges = onCall(
    {region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB"},
    async (request) => {
        const uid = requireAuth(request);
        requireApp(request);
        await enforceRateLimit(uid, [{...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_get_edges_1min", maxCalls: 60}]);

        const ref = cleanPath(request.data?.ref, "ref");
        const direction = cleanEnum<string>(request.data?.direction, new Set(["outbound", "inbound", "both"]), "direction");
        const edgeType = request.data?.edgeType
            ? cleanEnum<string>(request.data.edgeType, VALID_EDGE_TYPES, "edgeType")
            : null;

        const queries: FirebaseFirestore.Query[] = [];
        if (direction === "outbound" || direction === "both") {
            queries.push(db.collection("edges").where("fromRef", "==", ref).where("isDeleted", "==", false));
        }
        if (direction === "inbound" || direction === "both") {
            queries.push(db.collection("edges").where("toRef", "==", ref).where("isDeleted", "==", false));
        }

        const snapshots = await Promise.all(queries.map((query) => edgeType ? query.where("edgeType", "==", edgeType).limit(50).get() : query.limit(50).get()));
        const byId = new Map<string, FirebaseFirestore.DocumentData>();
        for (const snap of snapshots) {
            for (const doc of snap.docs) {
                const data = doc.data();
                if (data.visibility === "private" && data.createdBy !== uid && data.fromUid !== uid && data.toUid !== uid) {
                    continue;
                }
                byId.set(doc.id, data);
            }
        }

        return Array.from(byId.values()).map((edge) => ({
            fromRef: edge.fromRef,
            fromType: edge.fromType,
            toRef: edge.toRef,
            toType: edge.toType,
            edgeType: edge.edgeType,
            createdBy: edge.createdBy,
            visibility: edge.visibility,
            createdAt: Math.floor((edge.createdAtMillis ?? Date.now()) / 1000),
        }));
    }
);

export const transformObject = onCall(
    {region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB"},
    async (request) => {
        const uid = requireAuth(request);
        requireApp(request);
        await enforceRateLimit(uid, [
            {...RATE_LIMITS.AI_PER_MINUTE, name: "community_transform_1min", maxCalls: 20},
            {...RATE_LIMITS.AI_PER_DAY, name: "community_transform_1day", maxCalls: 120},
        ]);

        const body = request.data as TransformRequest;
        const sourceRef = cleanPath(body.sourceRef, "sourceRef");
        const sourceType = cleanEnum<AmenObjectType>(body.sourceType, VALID_OBJECT_TYPES, "sourceType");
        const intent = cleanEnum<AmenIntent>(body.intent, VALID_INTENTS, "intent");
        if (body.actorId && body.actorId !== uid) {
            throw new HttpsError("permission-denied", "actorId must match authenticated user.");
        }

        const role = await resolveRoleFor(uid, sourceRef);
        if (role === "visitor" || role === "minor") {
            throw new HttpsError("permission-denied", "Your role cannot transform this object.");
        }

        const sourceSnap = await db.doc(sourceRef).get();
        if (!sourceSnap.exists) {
            throw new HttpsError("not-found", "Source object not found.");
        }

        const sourceData = sourceSnap.data() ?? {};
        const sourceOwnerId = String(sourceData.authorId ?? sourceData.userId ?? sourceData.ownerId ?? sourceData.createdBy ?? "");
        const newObjectType = resultTypeForIntent(intent);
        const collection = collectionForObjectType(newObjectType);
        const newRef = db.collection(collection).doc();
        const nowMillis = Date.now();
        const audience = audienceFor(intent, body.audienceOverride);
        const moderationTier = moderationTierFor(sourceType, intent);
        const provenance = {
            sourceType,
            sourceRef,
            sourceOwnerId,
            intent,
            createdAt: FieldValue.serverTimestamp(),
        };
        const smartSuggestions = suggestedActions(intent, sourceType, role);

        await db.runTransaction(async (tx) => {
            tx.set(newRef, {
                objectType: newObjectType,
                sourceType,
                sourceRef,
                sourceOwnerId,
                createdBy: uid,
                authorId: uid,
                audience: audience.appliedAudience,
                moderationTier,
                status: moderationTier === "high" ? "pending_review" : "active",
                title: `${intent} from ${sourceType}`,
                provenance,
                smartSuggestions,
                createdAt: FieldValue.serverTimestamp(),
                createdAtMillis: nowMillis,
                updatedAt: FieldValue.serverTimestamp(),
                isDeleted: false,
            });
            tx.set(db.collection("communityTransforms").doc(newRef.id), {
                transformId: newRef.id,
                sourceRef,
                sourceType,
                intent,
                actorId: uid,
                newObjectRef: newRef.path,
                newObjectType,
                appliedAudience: audience.appliedAudience,
                moderationTier,
                smartSuggestions,
                createdAt: FieldValue.serverTimestamp(),
                createdAtMillis: nowMillis,
            });
            tx.set(db.collection("edges").doc(stableEdgeId(newRef.path, sourceRef, "spawnedFrom")), {
                fromRef: newRef.path,
                fromType: newObjectType,
                toRef: sourceRef,
                toType: sourceType,
                edgeType: "spawnedFrom",
                fromUid: uid,
                toUid: sourceOwnerId,
                createdBy: uid,
                visibility: audience.appliedAudience === "public" ? "public" : "members",
                createdAt: FieldValue.serverTimestamp(),
                createdAtMillis: nowMillis,
                isDeleted: false,
                provenance,
            });
        });

        return {
            newObjectId: newRef.id,
            newObjectType,
            newObjectRef: newRef.path,
            provenance: {
                sourceType,
                sourceRef,
                sourceOwnerId,
                intent,
                createdAt: Math.floor(nowMillis / 1000),
            },
            appliedAudience: audience.appliedAudience,
            moderationTier,
            roomId: newObjectType === "discussion" ? newRef.id : null,
            actionThreadId: newObjectType === "actionThread" ? newRef.id : null,
            warnings: audience.warnings,
            smartSuggestions,
        };
    }
);
