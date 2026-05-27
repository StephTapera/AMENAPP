import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = admin.firestore();
const now = () => admin.firestore.FieldValue.serverTimestamp();

type SpaceRole = "owner" | "admin" | "moderator" | "pastor" | "elder" | "teacher" | "mentor" | "member";
type GuardianStatus = "approved" | "pending_review" | "blocked";

const adminRoles: SpaceRole[] = ["owner", "admin"];
const moderatorRoles: SpaceRole[] = ["owner", "admin", "moderator", "pastor", "elder"];
const memberRoles: SpaceRole[] = ["owner", "admin", "moderator", "pastor", "elder", "teacher", "mentor", "member"];
const publicVisibility = ["open", "public", "discoverable"];

function requireAuth(request: { auth?: { uid: string } | null }): string {
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

function optionalString(value: unknown, maxLength: number): string | null {
    if (value == null) return null;
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", "Invalid optional string");
    }
    const trimmed = value.trim();
    if (trimmed.length > maxLength) {
        throw new HttpsError("invalid-argument", "Optional string is too long");
    }
    return trimmed.length === 0 ? null : trimmed;
}

function stringList(value: unknown, maxItems: number, maxItemLength = 80): string[] {
    if (!Array.isArray(value)) return [];
    return value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter((item) => item.length > 0 && item.length <= maxItemLength)
        .slice(0, maxItems);
}

async function enforceRateLimit(uid: string, action: string, maxPerMinute: number): Promise<void> {
    const ref = db.collection("_rateLimits").doc(`spaces_${uid}_${action}`);
    const nowMs = Date.now();
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const current = snap.data() ?? {};
        const windowStartedAt = Number(current.windowStartedAt ?? 0);
        const count = nowMs - windowStartedAt > 60_000 ? 0 : Number(current.count ?? 0);
        if (count >= maxPerMinute) {
            throw new HttpsError("resource-exhausted", "Please slow down and try again in a moment.");
        }
        tx.set(ref, {
            uid,
            action,
            windowStartedAt: count === 0 ? nowMs : windowStartedAt,
            count: count + 1,
            updatedAt: now(),
            expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + 120_000),
        }, { merge: true });
    });
}

async function spaceDoc(spaceId: string): Promise<admin.firestore.DocumentSnapshot> {
    const doc = await db.collection("spaces").doc(spaceId).get();
    if (!doc.exists) {
        throw new HttpsError("not-found", "Space not found");
    }
    return doc;
}

async function memberRole(spaceId: string, uid: string): Promise<SpaceRole | null> {
    const doc = await db.collection("spaces").doc(spaceId).collection("members").doc(uid).get();
    if (!doc.exists || doc.data()?.status !== "active") return null;
    return (doc.data()?.role ?? "member") as SpaceRole;
}

async function requireMember(spaceId: string, uid: string, allowed: SpaceRole[] = memberRoles): Promise<SpaceRole> {
    const role = await memberRole(spaceId, uid);
    if (!role || !allowed.includes(role)) {
        throw new HttpsError("permission-denied", "Space membership required");
    }
    return role;
}

function reviewText(text: string): { guardianStatus: GuardianStatus; reasons: string[] } {
    const lower = text.toLowerCase();
    const reasons: string[] = [];
    if (/(kill myself|suicide|self harm)/.test(lower)) reasons.push("crisis_language");
    if (/(hate|threat|doxx|explicit|send pics|minor alone|do not tell)/.test(lower)) reasons.push("safety_risk");
    if (/(cashapp|venmo|wire transfer|off platform|telegram|whatsapp|guaranteed blessing)/.test(lower)) reasons.push("coercion_or_off_platform_pressure");
    if (reasons.includes("safety_risk")) return { guardianStatus: "blocked", reasons };
    if (reasons.length > 0) return { guardianStatus: "pending_review", reasons };
    return { guardianStatus: "approved", reasons };
}

async function writeAudit(
    spaceId: string,
    actorId: string,
    action: string,
    targetType: string,
    targetId: string,
    metadata: Record<string, unknown> = {}
): Promise<void> {
    const payload = {
        actorId,
        action,
        targetType,
        targetId,
        metadata,
        createdAt: now(),
    };
    await Promise.all([
        db.collection("spaces").doc(spaceId).collection("auditLogs").add(payload),
        db.collection("spaceAuditLogs").add({ ...payload, spaceId }),
    ]);
}

async function ensureDefaultRoom(spaceId: string, uid: string): Promise<string> {
    const roomId = "general";
    const ref = db.collection("spaces").doc(spaceId).collection("rooms").doc(roomId);
    const snap = await ref.get();
    if (!snap.exists) {
        await ref.set({
            id: roomId,
            spaceId,
            name: "General",
            kind: "persistent",
            isArchived: false,
            createdBy: uid,
            createdAt: now(),
            updatedAt: now(),
        }, { merge: true });
    }
    return roomId;
}

export const createSpace = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "createSpace", 5);
    const data = dataMap(request.data);
    const name = stringField(data, "name", 100);
    const description = stringField(data, "description", 600);
    if (!name) throw new HttpsError("invalid-argument", "Space name is required");

    const spaceRef = db.collection("spaces").doc();
    const spaceId = spaceRef.id;
    const visibility = publicVisibility.includes(String(data.visibility)) ? String(data.visibility) : "open";
    const type = stringField(data, "type", 80, "churchMinistry");
    const topics = stringList(data.aiDetectedTopics, 12);
    const memberRef = spaceRef.collection("members").doc(uid);
    const legacyMembershipRef = db.collection("spaceMemberships").doc(`${uid}_${spaceId}`);

    const batch = db.batch();
    batch.set(spaceRef, {
        id: spaceId,
        name,
        description,
        type,
        visibility,
        aiDetectedTopics: topics,
        memberCount: 1,
        postCount: 0,
        coverImageURL: null,
        createdAt: now(),
        updatedAt: now(),
        createdBy: uid,
        isAutoGenerated: false,
        topPostIds: [],
        weeklyActiveUsers: 1,
        recentPosterPhotoURLs: [],
        memoryNamespace: `space_${spaceId}`,
        safetyStatus: "allowed",
        deletedAt: null,
    });
    batch.set(memberRef, {
        userId: uid,
        spaceId,
        role: "owner",
        roles: ["owner"],
        status: "active",
        joinedAt: now(),
        updatedAt: now(),
        scopedProfile: {},
    });
    batch.set(legacyMembershipRef, {
        userId: uid,
        spaceId,
        joinedAt: now(),
        notificationsEnabled: true,
        role: "owner",
        status: "active",
    });
    batch.set(spaceRef.collection("rooms").doc("general"), {
        id: "general",
        spaceId,
        name: "General",
        kind: "persistent",
        isArchived: false,
        createdBy: uid,
        createdAt: now(),
        updatedAt: now(),
    });
    await batch.commit();
    await writeAudit(spaceId, uid, "createSpace", "space", spaceId, { type, visibility });
    return { ok: true, spaceId };
});

export const joinSpace = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "joinSpace", 20);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const snap = await spaceDoc(spaceId);
    const visibility = String(snap.data()?.visibility ?? "open");
    if (!publicVisibility.includes(visibility)) {
        throw new HttpsError("permission-denied", "This Space requires an invitation or admin approval.");
    }

    const memberRef = db.collection("spaces").doc(spaceId).collection("members").doc(uid);
    const legacyMembershipRef = db.collection("spaceMemberships").doc(`${uid}_${spaceId}`);
    await db.runTransaction(async (tx) => {
        const existing = await tx.get(memberRef);
        const wasActive = existing.exists && existing.data()?.status === "active";
        tx.set(memberRef, {
            userId: uid,
            spaceId,
            role: existing.data()?.role ?? "member",
            roles: existing.data()?.roles ?? ["member"],
            status: "active",
            joinedAt: existing.data()?.joinedAt ?? now(),
            updatedAt: now(),
            scopedProfile: existing.data()?.scopedProfile ?? {},
        }, { merge: true });
        tx.set(legacyMembershipRef, {
            userId: uid,
            spaceId,
            joinedAt: now(),
            notificationsEnabled: true,
            role: existing.data()?.role ?? "member",
            status: "active",
        }, { merge: true });
        if (!wasActive) {
            tx.update(db.collection("spaces").doc(spaceId), {
                memberCount: admin.firestore.FieldValue.increment(1),
                updatedAt: now(),
            });
        }
    });
    await writeAudit(spaceId, uid, "joinSpace", "member", uid);
    return { ok: true, spaceId, status: "active" };
});

export const leaveSpace = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "leaveSpace", 20);
    const spaceId = stringField(dataMap(request.data), "spaceId", 160);
    const role = await requireMember(spaceId, uid);
    if (role === "owner") {
        throw new HttpsError("failed-precondition", "Transfer ownership before leaving this Space.");
    }
    const memberRef = db.collection("spaces").doc(spaceId).collection("members").doc(uid);
    const legacyMembershipRef = db.collection("spaceMemberships").doc(`${uid}_${spaceId}`);
    await db.runTransaction(async (tx) => {
        tx.set(memberRef, { status: "left", leftAt: now(), updatedAt: now() }, { merge: true });
        tx.delete(legacyMembershipRef);
        tx.update(db.collection("spaces").doc(spaceId), {
            memberCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: now(),
        });
    });
    await writeAudit(spaceId, uid, "leaveSpace", "member", uid);
    return { ok: true, spaceId };
});

export const postToRoom = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "postToRoom", 30);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid);
    const roomId = stringField(data, "roomId", 160, await ensureDefaultRoom(spaceId, uid));
    const body = stringField(data, "body", 8000);
    const mediaRefs = stringList(data.mediaRefs, 10, 2048);
    if (!body && mediaRefs.length === 0) {
        throw new HttpsError("invalid-argument", "Message body or media is required");
    }
    const moderation = reviewText(`${body} ${mediaRefs.join(" ")}`);
    if (moderation.guardianStatus === "blocked") {
        await writeAudit(spaceId, uid, "postToRoomBlocked", "room", roomId, { reasons: moderation.reasons });
        throw new HttpsError("failed-precondition", "Message blocked by safety review");
    }

    const messageRef = db.collection("spaces").doc(spaceId).collection("rooms").doc(roomId).collection("messages").doc();
    const legacyPostRef = db.collection("spacePosts").doc(messageRef.id);
    const payload = {
        id: messageRef.id,
        spaceId,
        roomId,
        authorId: uid,
        body,
        mediaRefs,
        mentionedUserIds: stringList(data.mentionedUserIds, 20),
        guardianStatus: moderation.guardianStatus,
        riskReasons: moderation.reasons,
        createdAt: now(),
        updatedAt: now(),
        deletedAt: null,
        provenance: { generatedBy: "user", sourceIds: [], visibility: "space" },
    };

    const batch = db.batch();
    batch.set(messageRef, payload);
    if (moderation.guardianStatus === "approved") {
        batch.set(legacyPostRef, {
            spaceId,
            authorId: uid,
            contentType: stringField(data, "contentType", 40, mediaRefs.length > 0 ? "photo" : "text"),
            textContent: body || null,
            mediaURLs: mediaRefs,
            aiConfidenceScore: 0,
            likes: 0,
            comments: 0,
            guardianStatus: "approved",
            createdAt: now(),
        });
        batch.update(db.collection("spaces").doc(spaceId), {
            postCount: admin.firestore.FieldValue.increment(1),
            updatedAt: now(),
        });
    }
    await batch.commit();
    await writeAudit(spaceId, uid, "postToRoom", "message", messageRef.id, { roomId, guardianStatus: moderation.guardianStatus });
    return { ok: true, messageId: messageRef.id, roomId, guardianStatus: moderation.guardianStatus };
});

export const updateScopedProfile = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "updateScopedProfile", 20);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid);
    const rawProfile = dataMap(data.scopedProfile);
    const scopedProfile = {
        displayName: optionalString(rawProfile.displayName, 80),
        bio: optionalString(rawProfile.bio, 300),
        visibleGifts: stringList(rawProfile.visibleGifts, 12, 80),
        isAnonymous: rawProfile.isAnonymous === true,
        showsPrayerActivity: rawProfile.showsPrayerActivity === true,
        showsStudyActivity: rawProfile.showsStudyActivity === true,
    };
    await db.collection("spaces").doc(spaceId).collection("members").doc(uid).set({
        scopedProfile,
        updatedAt: now(),
    }, { merge: true });
    await writeAudit(spaceId, uid, "updateScopedProfile", "member", uid);
    return { ok: true };
});

export const updatePresence = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "updatePresence", 60);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid);
    const mode = stringField(data, "mode", 60, "available");
    await db.collection("spaces").doc(spaceId).collection("presence").doc(uid).set({
        userId: uid,
        spaceId,
        mode,
        statusMessage: optionalString(data.statusMessage, 160),
        updatedAt: now(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60_000),
    }, { merge: true });
    return { ok: true };
});

export const createRoom = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "createRoom", 10);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid, adminRoles);
    const roomRef = db.collection("spaces").doc(spaceId).collection("rooms").doc();
    const name = stringField(data, "name", 80);
    if (!name) throw new HttpsError("invalid-argument", "Room name is required");
    await roomRef.set({
        id: roomRef.id,
        spaceId,
        name,
        kind: stringField(data, "kind", 40, "persistent"),
        isArchived: false,
        createdBy: uid,
        createdAt: now(),
        updatedAt: now(),
    });
    await writeAudit(spaceId, uid, "createRoom", "room", roomRef.id);
    return { ok: true, roomId: roomRef.id };
});

export const archiveRoom = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const roomId = stringField(data, "roomId", 160);
    await requireMember(spaceId, uid, adminRoles);
    await db.collection("spaces").doc(spaceId).collection("rooms").doc(roomId).set({
        isArchived: true,
        archivedAt: now(),
        archivedBy: uid,
        updatedAt: now(),
    }, { merge: true });
    await writeAudit(spaceId, uid, "archiveRoom", "room", roomId);
    return { ok: true };
});

export const updateMemberRole = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "updateMemberRole", 20);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const targetUid = stringField(data, "userId", 160);
    const role = stringField(data, "role", 40) as SpaceRole;
    if (!memberRoles.includes(role)) throw new HttpsError("invalid-argument", "Invalid role");
    await requireMember(spaceId, uid, adminRoles);
    await db.collection("spaces").doc(spaceId).collection("members").doc(targetUid).set({
        role,
        roles: [role],
        updatedAt: now(),
        updatedBy: uid,
    }, { merge: true });
    await writeAudit(spaceId, uid, "updateMemberRole", "member", targetUid, { role });
    return { ok: true };
});

export const createSpacePrayerRequest = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "createSpacePrayerRequest", 12);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid);
    const body = stringField(data, "body", 2000);
    if (!body) throw new HttpsError("invalid-argument", "Prayer request body is required");
    const moderation = reviewText(body);
    if (moderation.guardianStatus === "blocked") {
        throw new HttpsError("failed-precondition", "Prayer request blocked by safety review");
    }
    const ref = db.collection("spaces").doc(spaceId).collection("prayerRequests").doc();
    await ref.set({
        id: ref.id,
        spaceId,
        createdBy: uid,
        body,
        visibility: stringField(data, "visibility", 40, "private"),
        category: stringField(data, "category", 40, "message"),
        sourceMessageId: optionalString(data.sourceMessageId, 160),
        threadId: optionalString(data.threadId, 160),
        status: "open",
        guardianStatus: moderation.guardianStatus,
        riskReasons: moderation.reasons,
        createdAt: now(),
        updatedAt: now(),
    });
    await writeAudit(spaceId, uid, "createSpacePrayerRequest", "prayerRequest", ref.id, { guardianStatus: moderation.guardianStatus });
    return { ok: true, prayerRequestId: ref.id, guardianStatus: moderation.guardianStatus };
});

export const dismissSpaceAmbientSignal = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "dismissSpaceAmbientSignal", 60);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const signalId = stringField(data, "signalId", 160);
    await requireMember(spaceId, uid);
    await db.collection("spaces").doc(spaceId).collection("ambientSignals").doc(signalId).set({
        dismissedBy: admin.firestore.FieldValue.arrayUnion(uid),
        [`dismissals.${uid}`]: now(),
        updatedAt: now(),
    }, { merge: true });
    return { ok: true };
});

export const saveSpaceSemanticPin = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "saveSpaceSemanticPin", 20);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid);
    const pinType = stringField(data, "pinType", 60);
    if (["intelligent", "ai", "dynamic"].includes(pinType)) {
        throw new HttpsError("permission-denied", "Server-generated pins cannot be client-created.");
    }
    const pinId = stringField(data, "pinId", 160, db.collection("_ids").doc().id);
    await db.collection("spaces").doc(spaceId).collection("pins").doc(pinId).set({
        id: pinId,
        spaceId,
        threadId: optionalString(data.threadId, 160),
        messageId: optionalString(data.messageId, 160),
        pinnedBy: uid,
        pinType,
        title: stringField(data, "title", 120),
        preview: stringField(data, "preview", 500),
        tags: stringList(data.tags, 12),
        scriptureRef: optionalString(data.scriptureRef, 80),
        score: 1.0,
        isServerGenerated: false,
        createdAt: now(),
        updatedAt: now(),
        evolutionHistory: [],
    });
    await writeAudit(spaceId, uid, "saveSpaceSemanticPin", "pin", pinId, { pinType });
    return { ok: true, pinId };
});

export const deleteSpaceSemanticPin = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "deleteSpaceSemanticPin", 20);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const pinId = stringField(data, "pinId", 160);
    const role = await requireMember(spaceId, uid);
    const ref = db.collection("spaces").doc(spaceId).collection("pins").doc(pinId);
    const snap = await ref.get();
    const pin = snap.data();
    if (!snap.exists) throw new HttpsError("not-found", "Pin not found");
    if (pin?.pinnedBy !== uid && !moderatorRoles.includes(role)) {
        throw new HttpsError("permission-denied", "Only the pin author or a moderator may remove this pin.");
    }
    await ref.set({ deletedAt: now(), deletedBy: uid, updatedAt: now() }, { merge: true });
    await writeAudit(spaceId, uid, "deleteSpaceSemanticPin", "pin", pinId);
    return { ok: true };
});

export const dismissSpaceMemoryNode = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "dismissSpaceMemoryNode", 60);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const nodeId = stringField(data, "nodeId", 160);
    await requireMember(spaceId, uid);
    const batch = db.batch();
    batch.set(db.collection("spaces").doc(spaceId).collection("memory").doc(nodeId), {
        dismissedBy: admin.firestore.FieldValue.arrayUnion(uid),
        [`dismissals.${uid}`]: now(),
        updatedAt: now(),
    }, { merge: true });
    batch.set(db.collection("users").doc(uid).collection("spaceMemory").doc(nodeId), {
        dismissed: true,
        dismissedAt: now(),
        updatedAt: now(),
    }, { merge: true });
    await batch.commit();
    return { ok: true };
});

export const deleteRoomPost = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const roomId = stringField(data, "roomId", 160);
    const messageId = stringField(data, "messageId", 160);
    const role = await requireMember(spaceId, uid);
    const ref = db.collection("spaces").doc(spaceId).collection("rooms").doc(roomId).collection("messages").doc(messageId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Message not found");
    if (snap.data()?.authorId !== uid && !moderatorRoles.includes(role)) {
        throw new HttpsError("permission-denied", "Only the author or moderator may delete this message.");
    }
    await Promise.all([
        ref.set({ deletedAt: now(), deletedBy: uid, updatedAt: now() }, { merge: true }),
        db.collection("spacePosts").doc(messageId).set({ deletedAt: now(), deletedBy: uid }, { merge: true }),
    ]);
    await writeAudit(spaceId, uid, "deleteRoomPost", "message", messageId, { roomId });
    return { ok: true };
});

export const dissolveEphemeralRoom = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    const roomId = stringField(data, "roomId", 160);
    await requireMember(spaceId, uid, adminRoles);
    await db.collection("spaces").doc(spaceId).collection("rooms").doc(roomId).set({
        isArchived: true,
        dissolvedAt: now(),
        dissolvedBy: uid,
        updatedAt: now(),
    }, { merge: true });
    const memoryRef = db.collection("spaces").doc(spaceId).collection("memory").doc();
    await memoryRef.set({
        id: memoryRef.id,
        spaceId,
        sourceRoomId: roomId,
        layer: "group",
        title: "Ephemeral room summary pending",
        summary: "A server summarization job should replace this placeholder before user display.",
        confidence: 0,
        generatedAt: now(),
        dismissed: false,
        provenance: { generatedBy: "dissolveEphemeralRoom", sourceIds: [roomId] },
    });
    await writeAudit(spaceId, uid, "dissolveEphemeralRoom", "room", roomId, { memoryNodeId: memoryRef.id });
    return { ok: true, memoryNodeId: memoryRef.id };
});

export const bereanSpaceInvoke = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "bereanSpaceInvoke", 10);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid);
    await writeAudit(spaceId, uid, "bereanSpaceInvokeRejected", "space", spaceId, {
        reason: "model_proxy_not_configured",
    });
    throw new HttpsError("failed-precondition", "Berean Space member runtime is not configured on this backend yet.");
});

export const generateSpaceDNA = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    await enforceRateLimit(uid, "generateSpaceDNA", 5);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid, adminRoles);
    throw new HttpsError("failed-precondition", "Space DNA generation requires the AI proxy runtime to be configured.");
});

export const updateSpaceSettings = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid, adminRoles);
    const updates: Record<string, unknown> = { updatedAt: now(), updatedBy: uid };
    const name = optionalString(data.name, 100);
    const description = optionalString(data.description, 600);
    const visibility = optionalString(data.visibility, 40);
    if (name != null) updates.name = name;
    if (description != null) updates.description = description;
    if (visibility != null && publicVisibility.includes(visibility)) updates.visibility = visibility;
    await db.collection("spaces").doc(spaceId).set(updates, { merge: true });
    await writeAudit(spaceId, uid, "updateSpaceSettings", "space", spaceId, updates);
    return { ok: true };
});

export const updateSpaceDNA = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid, adminRoles);
    await db.collection("spaces").doc(spaceId).set({
        dna: dataMap(data.dna),
        updatedAt: now(),
        updatedBy: uid,
    }, { merge: true });
    await writeAudit(spaceId, uid, "updateSpaceDNA", "space", spaceId);
    return { ok: true };
});

export const updateSpaceCovenant = onCall({ enforceAppCheck: true }, async (request) => {
    const uid = requireAuth(request);
    const data = dataMap(request.data);
    const spaceId = stringField(data, "spaceId", 160);
    await requireMember(spaceId, uid, adminRoles);
    await db.collection("spaces").doc(spaceId).set({
        covenant: dataMap(data.covenant),
        updatedAt: now(),
        updatedBy: uid,
    }, { merge: true });
    await writeAudit(spaceId, uid, "updateSpaceCovenant", "space", spaceId);
    return { ok: true };
});
