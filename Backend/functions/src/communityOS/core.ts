import * as admin from "firebase-admin";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const VALID_OBJECT_TYPES = new Set([
    "user", "organization", "church", "team", "space", "post", "prayer",
    "discussion", "study", "event", "volunteerOpportunity", "mentorship",
    "job", "churchNote", "bereanInsight", "mediaObject", "moment", "actionThread",
]);
const VALID_INTENTS = new Set([
    "share", "discuss", "pray", "study", "teach", "ask", "invite",
    "volunteer", "hire", "mentor", "announce",
]);
const VALID_EDGE_TYPES = new Set(["belongsTo", "spawnedFrom", "links", "follows", "praysFor"]);
const VALID_VISIBILITY = new Set(["public", "members", "private"]);
const VALID_ROLES = new Set([
    "owner", "executive_admin", "pastor", "leader", "moderator",
    "volunteer_lead", "content_manager", "event_manager", "member", "visitor", "minor",
]);

function requireAuth(request: CallableRequest): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function cleanPath(path: unknown, field: string): string {
    const value = String(path ?? "").trim().replace(/^\/+/, "");
    if (!value || value.includes("//") || value.split("/").length < 2) {
        throw new HttpsError("invalid-argument", `${field} must be a Firestore document path.`);
    }
    return value;
}

function cleanEnum(value: unknown, allowed: Set<string>, field: string): string {
    const raw = String(value ?? "").trim();
    if (!allowed.has(raw)) {
        throw new HttpsError("invalid-argument", `${field} is invalid.`);
    }
    return raw;
}

function stableEdgeId(fromRef: string, toRef: string, edgeType: string): string {
    return Buffer.from(`${fromRef}|${toRef}|${edgeType}`).toString("base64url").slice(0, 120);
}

function uidFromRef(ref: string): string | null {
    const parts = ref.split("/");
    return parts[0] === "users" && parts[1] ? parts[1] : null;
}

function collectionForObjectType(type: string): string {
    switch (type) {
    case "churchNote": return "churchNotes";
    case "bereanInsight": return "bereanInsights";
    case "mediaObject": return "mediaObjects";
    case "actionThread": return "actionThreads";
    case "volunteerOpportunity": return "volunteerOpportunities";
    default: return `${type}s`;
    }
}

function resultTypeForIntent(intent: string): string {
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

function moderationTierFor(sourceType: string, intent: string): string {
    if (intent === "announce" || intent === "hire") {
        return "high";
    }
    if (sourceType === "prayer" || intent === "pray" || intent === "mentor") {
        return "medium";
    }
    return "low";
}

function audienceFor(intent: string, override: unknown): { appliedAudience: string; warnings: string[] } {
    const requested = typeof override === "string" && override.trim() ? override.trim() : null;
    const ceilingByIntent: Record<string, string[]> = {
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
    const allowed = ceilingByIntent[intent] ?? ["private"];
    if (requested && allowed.includes(requested)) {
        return { appliedAudience: requested, warnings: [] };
    }
    const fallback = allowed[0];
    return {
        appliedAudience: fallback,
        warnings: requested ? [`Audience clamped from ${requested} to ${fallback}.`] : [],
    };
}

function suggestedActions(intent: string, sourceType: string, role: string): Array<Record<string, string>> {
    const actions: Array<Record<string, string>> = [];
    if (intent === "discuss") {
        actions.push({ id: "summarize_context", label: "Summarize context", kind: "berean_summary" });
        actions.push({ id: "invite_relevant_people", label: "Invite relevant people", kind: "relationship_graph" });
    }
    if (intent === "pray" || sourceType === "prayer") {
        actions.push({ id: "set_prayer_nudge", label: "Set prayer nudge", kind: "gentle_follow_up" });
    }
    if (intent === "study" || sourceType === "bereanInsight" || sourceType === "churchNote") {
        actions.push({ id: "continue_study", label: "Continue study", kind: "berean_recall" });
    }
    if (["leader", "pastor", "owner", "executive_admin"].includes(role)) {
        actions.push({ id: "share_with_team", label: "Share with team", kind: "role_aware" });
    }
    return actions.slice(0, 3);
}

async function resolveRoleFor(uid: string, resourceRef: string): Promise<string> {
    const user = await db.collection("users").doc(uid).get();
    const userData = user.data() ?? {};
    const profileRole = String(userData.role ?? userData.amenRole ?? "member");
    if (VALID_ROLES.has(profileRole)) {
        return profileRole;
    }
    const resourceParts = resourceRef.split("/");
    const churchId = resourceParts[0] === "churches" ? resourceParts[1] : String(userData.churchId ?? "");
    if (churchId) {
        const member = await db.doc(`churches/${churchId}/members/${uid}`).get();
        const memberRole = String(member.data()?.role ?? "");
        if (VALID_ROLES.has(memberRole)) {
            return memberRole;
        }
    }
    return "member";
}

export const resolveRBACRole = onCall(
    { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
    async (request: CallableRequest) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [{ ...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_rbac_1min", maxCalls: 30 }]);
        const requestedUserId = String(request.data?.userId ?? uid);
        if (requestedUserId !== uid) {
            throw new HttpsError("permission-denied", "Cannot resolve another user's role.");
        }
        const resourceRef = cleanPath(request.data?.resourceRef, "resourceRef");
        return { role: await resolveRoleFor(uid, resourceRef) };
    }
);

export const createEdge = onCall(
    { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
    async (request: CallableRequest) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [{ ...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_edge_1min", maxCalls: 30 }]);
        const body = request.data ?? {};
        const fromRef = cleanPath(body.fromRef, "fromRef");
        const toRef = cleanPath(body.toRef, "toRef");
        const fromType = cleanEnum(body.fromType, VALID_OBJECT_TYPES, "fromType");
        const toType = cleanEnum(body.toType, VALID_OBJECT_TYPES, "toType");
        const edgeType = cleanEnum(body.edgeType, VALID_EDGE_TYPES, "edgeType");
        const visibility = cleanEnum(body.visibility, VALID_VISIBILITY, "visibility");
        const fromUid = uidFromRef(fromRef) ?? uid;
        const toUid = uidFromRef(toRef) ?? "";
        if (fromUid !== uid && edgeType === "follows") {
            throw new HttpsError("permission-denied", "Cannot create a follow edge for another user.");
        }

        const edgeId = stableEdgeId(fromRef, toRef, edgeType);
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
            createdAtMillis: Date.now(),
            isDeleted: false,
            provenance: {
                sourceType: fromType,
                sourceRef: fromRef,
                sourceOwnerId: fromUid,
                intent: edgeType,
                createdAt: FieldValue.serverTimestamp(),
            },
        };
        await db.collection("edges").doc(edgeId).set(doc, { merge: true });
        return { edgeId, edge: doc };
    }
);

export const getEdges = onCall(
    { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
    async (request: CallableRequest) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [{ ...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_get_edges_1min", maxCalls: 30 }]);
        const ref = cleanPath(request.data?.ref, "ref");
        const direction = String(request.data?.direction ?? "out");
        const edgeType = request.data?.edgeType ? cleanEnum(request.data.edgeType, VALID_EDGE_TYPES, "edgeType") : null;
        const field = direction === "in" ? "toRef" : "fromRef";
        let query: FirebaseFirestore.Query = db.collection("edges")
            .where(field, "==", ref)
            .where("isDeleted", "==", false)
            .limit(50);
        if (edgeType) {
            query = query.where("edgeType", "==", edgeType);
        }
        const snap = await query.get();
        return { edges: snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })) };
    }
);

export const transformObject = onCall(
    { region: "us-central1", enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request: CallableRequest) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [
            { ...RATE_LIMITS.SUGGEST_PER_MINUTE, name: "community_transform_1min", maxCalls: 20 },
            { ...RATE_LIMITS.SUGGEST_PER_DAY, name: "community_transform_1day", maxCalls: 120 },
        ]);

        const sourceRef = cleanPath(request.data?.sourceRef, "sourceRef");
        const sourceType = cleanEnum(request.data?.sourceType, VALID_OBJECT_TYPES, "sourceType");
        const intent = cleanEnum(request.data?.intent, VALID_INTENTS, "intent");
        const actorId = String(request.data?.actorId ?? uid);
        if (actorId !== uid) {
            throw new HttpsError("permission-denied", "Cannot transform as another user.");
        }

        const role = await resolveRoleFor(uid, sourceRef);
        const { appliedAudience, warnings } = audienceFor(intent, request.data?.audienceOverride);
        const newObjectType = resultTypeForIntent(intent);
        const collection = collectionForObjectType(newObjectType);
        const objectRef = db.collection(collection).doc();
        const transformRef = db.collection("communityTransforms").doc();
        const provenance = {
            sourceType,
            sourceRef,
            sourceOwnerId: uidFromRef(sourceRef),
            intent,
            createdAt: FieldValue.serverTimestamp(),
        };
        const baseObject = {
            id: objectRef.id,
            _type: newObjectType,
            title: String(request.data?.title ?? `${intent} from ${sourceType}`).slice(0, 160),
            createdBy: uid,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
            isDeleted: false,
            privacyLevel: appliedAudience,
            provenance,
            moderationTier: moderationTierFor(sourceType, intent),
        };
        const smartSuggestions = suggestedActions(intent, sourceType, role);

        await db.runTransaction(async (tx) => {
            tx.set(objectRef, baseObject);
            tx.set(transformRef, {
                actorId: uid,
                actorRole: role,
                sourceRef,
                sourceType,
                intent,
                newObjectId: objectRef.id,
                newObjectType,
                newObjectRef: `${collection}/${objectRef.id}`,
                appliedAudience,
                moderationTier: baseObject.moderationTier,
                warnings,
                smartSuggestions,
                createdAt: FieldValue.serverTimestamp(),
            });
        });

        return {
            newObjectId: objectRef.id,
            newObjectType,
            newObjectRef: `${collection}/${objectRef.id}`,
            provenance: { ...provenance, createdAt: Date.now() / 1000 },
            appliedAudience,
            moderationTier: baseObject.moderationTier,
            roomId: newObjectType === "discussion" ? objectRef.id : null,
            actionThreadId: newObjectType === "actionThread" ? objectRef.id : null,
            smartSuggestions,
            warnings,
        };
    }
);
