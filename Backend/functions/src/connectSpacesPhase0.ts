import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

const roomTypes = ["smallGroup", "prayer", "worship", "missions", "staff", "cohort", "accountability"] as const;
const messageIntents = ["prayerRequest", "struggling", "leadSunday", "volunteerNeed", "testimony", "confession", "grief", "decision", "task", "risk", "question", "careFollowUp"] as const;
const beforeShareWarnings = ["gossip", "slander", "divisiveness", "pii", "phi", "financial"] as const;
const surfaces = ["spaces", "connect", "liquidIntelligenceSearch", "upload", "comments", "directMessage"] as const;
const actions = ["allow", "label", "warn", "routeToCare", "routeToHumanReview", "block"] as const;
const scriptureLayers = ["canonicalReference", "translationSource", "contextWindow", "bereanStudySheet"] as const;
const commentTypes = ["question", "correction", "experience", "citation", "encouragement", "respectfulDisagree"] as const;

export const amenConnectSpacesPhase0CallableNames = [
    "createMinistrySpace",
    "postMinistryMessage",
    "detectMessageIntents",
    "routeCareSignal",
    "updateSpiritualPresence",
    "runConvictionCheck",
    "runBeforeShareCheck",
    "fetchConnectVideoContext",
    "verifyScriptureProvenance",
    "recordKnowledgeGraphEvent",
    "scoreEdifyingComment",
    "runAegisInputGate",
    "runAegisOutputGate",
    "scanUploadForFamilySafety",
    "searchMinistryMemory",
] as const;

export const amenConnectSpacesAegisCapabilityRefs = Array.from({ length: 58 }, (_, index) => `C${index + 1}`);
const capabilityRefSet = new Set(amenConnectSpacesAegisCapabilityRefs);

type Surface = typeof surfaces[number];
type AegisAction = typeof actions[number];
type CallableRequest = { auth?: { uid: string } | null; data: unknown };

type AegisGateDecision = {
    ok: true;
    action: AegisAction;
    flags: Array<Record<string, unknown>>;
    humanResourceRefs: string[];
    canContinue: boolean;
    stubbed: true;
};

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Auth required");
    }
    return request.auth.uid;
}

function dataMap(data: unknown): Record<string, unknown> {
    if (typeof data !== "object" || data == null || Array.isArray(data)) {
        return {};
    }
    return data as Record<string, unknown>;
}

function stringField(data: Record<string, unknown>, key: string, maxLength: number, fallback = ""): string {
    const value = data[key];
    if (value == null) return fallback;
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", `Invalid ${key}`);
    }
    const trimmed = value.trim();
    if (trimmed.length > maxLength) {
        throw new HttpsError("invalid-argument", `${key} is too long`);
    }
    return trimmed;
}

function stringArray(value: unknown, maxItems: number, maxLength = 160): string[] {
    if (!Array.isArray(value)) return [];
    return value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter((item) => item.length > 0 && item.length <= maxLength)
        .slice(0, maxItems);
}

function enumField<T extends readonly string[]>(data: Record<string, unknown>, key: string, allowed: T, fallback: T[number]): T[number] {
    const raw = stringField(data, key, 120, fallback);
    if (!allowed.includes(raw)) {
        throw new HttpsError("invalid-argument", `Invalid ${key}`);
    }
    return raw;
}

function boolField(data: Record<string, unknown>, key: string, fallback = false): boolean {
    const value = data[key];
    return typeof value === "boolean" ? value : fallback;
}

function requireOwnerOrSelf(uid: string, userId: string): void {
    if (uid !== userId) {
        throw new HttpsError("permission-denied", "User mismatch");
    }
}

async function requireSpaceMember(spaceId: string, uid: string): Promise<void> {
    if (!spaceId) throw new HttpsError("invalid-argument", "spaceId is required");
    const space = await db.collection("spaces").doc(spaceId).get();
    if (!space.exists) throw new HttpsError("not-found", "Space not found");
    const memberIds = Array.isArray(space.data()?.memberIds) ? space.data()?.memberIds as string[] : [];
    if (space.data()?.createdBy !== uid && !memberIds.includes(uid)) {
        throw new HttpsError("permission-denied", "Space membership required");
    }
}

function requestedCapabilities(data: Record<string, unknown>): string[] {
    const refs = stringArray(data.capabilityRefs, 58, 4);
    return refs.length > 0 ? refs : amenConnectSpacesAegisCapabilityRefs;
}

function validateCapabilityRefs(refs: string[]): void {
    const invalid = refs.filter((ref) => !capabilityRefSet.has(ref));
    if (invalid.length > 0) {
        throw new HttpsError("invalid-argument", `Unsupported Aegis capabilities: ${invalid.join(",")}`);
    }
}

function aegisStubDecision(data: Record<string, unknown>, surface: Surface, subjectRef: string, action: AegisAction = "allow"): AegisGateDecision {
    const capabilityRefs = requestedCapabilities(data);
    validateCapabilityRefs(capabilityRefs);
    const shouldFlag = action !== "allow";
    return {
        ok: true,
        action,
        flags: shouldFlag ? [{
            id: db.collection("_ids").doc().id,
            capabilityRef: capabilityRefs[0] ?? "C1",
            surface,
            severity: "stub",
            action,
            subjectRef,
            createdAt: new Date().toISOString(),
        }] : [],
        humanResourceRefs: action === "routeToCare" || action === "routeToHumanReview" ? ["careQueue"] : [],
        canContinue: action !== "block",
        stubbed: true,
    };
}

function warningKindsForText(body: string): string[] {
    const lower = body.toLowerCase();
    const warnings: string[] = [];
    if (/(gossip|rumor|heard that)/.test(lower)) warnings.push("gossip");
    if (/(slander|liar|fraud)/.test(lower)) warnings.push("slander");
    if (/(divide|against them|take sides)/.test(lower)) warnings.push("divisiveness");
    if (/(ssn|social security|phone|address|email)/.test(lower)) warnings.push("pii");
    if (/(diagnosis|medical|therapy|medication)/.test(lower)) warnings.push("phi");
    if (/(bank|routing|cashapp|venmo|wire)/.test(lower)) warnings.push("financial");
    return warnings.filter((warning) => beforeShareWarnings.includes(warning));
}

function intentsForText(body: string): string[] {
    const lower = body.toLowerCase();
    const intents: string[] = [];
    if (/(pray|prayer)/.test(lower)) intents.push("prayerRequest");
    if (/(struggling|hard time|overwhelmed)/.test(lower)) intents.push("struggling");
    if (/(grief|grieving|passed away)/.test(lower)) intents.push("grief");
    if (/(confess|confession)/.test(lower)) intents.push("confession");
    if (/(decision|decide)/.test(lower)) intents.push("decision");
    if (/(task|todo|follow up)/.test(lower)) intents.push("task");
    if (/(risk|unsafe|self harm|suicide)/.test(lower)) intents.push("risk");
    if (/(question|\?)/.test(lower)) intents.push("question");
    return intents.filter((intent) => messageIntents.includes(intent));
}

function allScriptureLayersPresent(refs: unknown): boolean {
    if (!Array.isArray(refs)) return false;
    const layers = new Set(refs
        .filter((ref): ref is Record<string, unknown> => typeof ref === "object" && ref != null && !Array.isArray(ref))
        .map((ref) => String(ref.sourceLayer ?? "")));
    return scriptureLayers.every((layer) => layers.has(layer));
}

export const createMinistrySpace = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const name = stringField(data, "name", 100);
    if (!name) throw new HttpsError("invalid-argument", "name is required");
    const type = enumField(data, "type", roomTypes, "smallGroup");
    const memberIds = Array.from(new Set([uid, ...stringArray(data.memberIds, 500)]));
    const spaceRef = db.collection("spaces").doc();
    await spaceRef.set({
        name,
        type,
        memberIds,
        careSensitivity: boolField(data, "careSensitivity"),
        createdBy: uid,
        createdAt: now(),
        updatedAt: now(),
    });
    return { ok: true, spaceId: spaceRef.id, stubbed: true };
});

export const postMinistryMessage = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireSpaceMember(spaceId, uid);
    const body = stringField(data, "body", 8000);
    if (!body) throw new HttpsError("invalid-argument", "body is required");
    const messageRef = db.collection("spaces").doc(spaceId).collection("messages").doc();
    await messageRef.set({
        body,
        authorId: uid,
        detectedIntents: [],
        convictionCheck: { enabled: false, suggestedPause: false, warningKinds: [], checkedAt: null },
        careRouted: false,
        createdAt: now(),
        updatedAt: now(),
    });
    return { ok: true, messageId: messageRef.id, stubbed: true };
});

export const detectMessageIntents = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireSpaceMember(spaceId, uid);
    const detectedIntents = intentsForText(stringField(data, "body", 8000));
    return { ok: true, detectedIntents, stubbed: true };
});

export const routeCareSignal = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireSpaceMember(spaceId, uid);
    const messageId = stringField(data, "messageId", 160);
    await db.collection("spaces").doc(spaceId).collection("careSignals").add({
        messageId,
        routedBy: uid,
        detectedIntents: stringArray(data.detectedIntents, 12),
        createdAt: now(),
        status: "stub_pending_human_review",
    });
    return { ok: true, careRouted: true, humanResourceRefs: ["careQueue"], stubbed: true };
});

export const updateSpiritualPresence = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const userId = stringField(data, "userId", 160, uid);
    requireOwnerOrSelf(uid, userId);
    await db.collection("presence").doc(userId).set({
        spiritualState: stringField(data, "spiritualState", 80, "inPrayer"),
        urgentReachable: boolField(data, "urgentReachable"),
        sabbathUntil: data.sabbathUntil ?? null,
        updatedAt: now(),
    }, { merge: true });
    return { ok: true, userId, stubbed: true };
});

export const runConvictionCheck = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const data = dataMap(request.data);
    const warningKinds = warningKindsForText(stringField(data, "body", 8000));
    return { ok: true, enabled: true, suggestedPause: warningKinds.length > 0, warningKinds, checkedAt: new Date().toISOString(), stubbed: true };
});

export const runBeforeShareCheck = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const data = dataMap(request.data);
    const warningKinds = warningKindsForText(stringField(data, "body", 8000));
    return { ok: true, warningKinds, action: warningKinds.length > 0 ? "warn" : "allow", stubbed: true };
});

export const fetchConnectVideoContext = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const data = dataMap(request.data);
    const videoId = stringField(data, "videoId", 160);
    const snap = await db.collection("connectVideos").doc(videoId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Video context not found");
    return { ok: true, videoId, context: snap.data(), stubbed: true };
});

export const verifyScriptureProvenance = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const data = dataMap(request.data);
    const verified = allScriptureLayersPresent(data.scriptureRefs ?? data.refs);
    return { ok: true, verified, requiredLayers: scriptureLayers, stubbed: true };
});

export const recordKnowledgeGraphEvent = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const userId = stringField(data, "userId", 160, uid);
    requireOwnerOrSelf(uid, userId);
    const event = stringField(data, "event", 80);
    const itemRef = stringField(data, "itemRef", 240);
    await db.collection("knowledgeGraph").doc(userId).collection("events").add({ event, itemRef, createdAt: now() });
    await db.collection("knowledgeGraph").doc(userId).set({ updatedAt: now() }, { merge: true });
    return { ok: true, userId, stubbed: true };
});

export const scoreEdifyingComment = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const data = dataMap(request.data);
    enumField(data, "type", commentTypes, "encouragement");
    const body = stringField(data, "body", 4000);
    const score = body.length === 0 ? 0 : Math.min(1, Math.max(0.1, body.length / 500));
    return { ok: true, edificationScore: score, privateMetric: true, stubbed: true };
});

export const runAegisInputGate = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const userId = stringField(data, "userId", 160, uid);
    requireOwnerOrSelf(uid, userId);
    const surface = enumField(data, "surface", surfaces, "spaces");
    return aegisStubDecision(data, surface, stringField(data, "inputRef", 240, "input"));
});

export const runAegisOutputGate = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const userId = stringField(data, "userId", 160, uid);
    requireOwnerOrSelf(uid, userId);
    const surface = enumField(data, "surface", surfaces, "spaces");
    return aegisStubDecision(data, surface, stringField(data, "inputRef", 240, "output"));
});

export const scanUploadForFamilySafety = onCall({ enforceAppCheck: true }, async (request) => {
    requireAuth(request);
    const data = dataMap(request.data);
    const surface = enumField(data, "surface", surfaces, "upload");
    return aegisStubDecision({ ...data, capabilityRefs: stringArray(data.capabilityRefs, 58, 4).length ? data.capabilityRefs : amenConnectSpacesAegisCapabilityRefs.slice(0, 13) }, surface, stringField(data, "uploadRef", 240, "upload"));
});

export const searchMinistryMemory = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireSpaceMember(spaceId, uid);
    return { ok: true, results: [], stubbed: true, backendRequired: "Pinecone/Algolia ministry memory implementation" };
});
