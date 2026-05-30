import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const db = admin.firestore();
const managerRoles = new Set(["creator", "admin", "moderator", "owner"]);
const validKinds = new Set([
    "prayer",
    "discussion",
    "bibleStudy",
    "church",
    "creator",
    "voice",
    "event",
    "community",
    "selah",
    "berean",
]);

type SpatialRoomKind =
    | "prayer"
    | "discussion"
    | "bibleStudy"
    | "church"
    | "creator"
    | "voice"
    | "event"
    | "community"
    | "selah"
    | "berean";

type SpatialRoomDraft = {
    covenantId: string;
    name: string;
    purpose: string;
    kind: SpatialRoomKind;
    isPublic: boolean;
    voiceEnabled: boolean;
    prayerEnabled: boolean;
    aiModerationEnabled: boolean;
};

type SpatialTheme = {
    kind: SpatialRoomKind;
    artworkURL?: string;
    videoURL?: string;
    ambientAudioURL?: string;
    motionStyle: string;
    generatedPrompt: string;
    voiceEnabled: boolean;
    prayerEnabled: boolean;
    aiModerationEnabled: boolean;
    mediaStatus: "generated_metadata" | "pending_media_generation";
    updatedAt: FirebaseFirestore.FieldValue;
};

type AmbientState = {
    activeCount: number;
    activityText: string;
    secondaryText: string;
    isLive: boolean;
    momentum: number;
    updatedAt: FirebaseFirestore.FieldValue;
};

function requireUid(context: functions.https.CallableContext): string {
    const uid = context.auth?.uid;
    if (!uid) {
        throw new functions.https.HttpsError("unauthenticated", "Sign in before managing spatial rooms.");
    }
    return uid;
}

function readString(data: unknown, key: string, maxLength: number): string {
    const value = (data as Record<string, unknown>)[key];
    if (typeof value !== "string") {
        throw new functions.https.HttpsError("invalid-argument", `${key} is required.`);
    }
    const trimmed = value.trim();
    if (!trimmed || trimmed.length > maxLength) {
        throw new functions.https.HttpsError("invalid-argument", `${key} must be 1-${maxLength} characters.`);
    }
    return trimmed;
}

function readBoolean(data: unknown, key: string, fallback = false): boolean {
    const value = (data as Record<string, unknown>)[key];
    return typeof value === "boolean" ? value : fallback;
}

function readKind(data: unknown): SpatialRoomKind {
    const value = (data as Record<string, unknown>).kind;
    if (typeof value !== "string" || !validKinds.has(value)) {
        throw new functions.https.HttpsError("invalid-argument", "kind is not a supported spatial room kind.");
    }
    return value as SpatialRoomKind;
}

function readDraft(data: unknown): SpatialRoomDraft {
    return {
        covenantId: readString(data, "covenantId", 96),
        name: readString(data, "name", 80),
        purpose: readString(data, "purpose", 360),
        kind: readKind(data),
        isPublic: readBoolean(data, "isPublic", true),
        voiceEnabled: readBoolean(data, "voiceEnabled"),
        prayerEnabled: readBoolean(data, "prayerEnabled"),
        aiModerationEnabled: readBoolean(data, "aiModerationEnabled", true),
    };
}

async function assertCanManageCovenant(uid: string, covenantId: string): Promise<void> {
    const covenantRef = db.collection("covenants").doc(covenantId);
    const covenantSnap = await covenantRef.get();
    if (!covenantSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Covenant was not found.");
    }

    const covenant = covenantSnap.data() ?? {};
    if (covenant.creatorUid === uid || covenant.ownerUid === uid || covenant.createdByUid === uid) {
        return;
    }

    const membershipSnap = await db.collection("covenantMemberships")
        .where("covenantId", "==", covenantId)
        .where("userId", "==", uid)
        .limit(1)
        .get();

    const membership = membershipSnap.docs[0]?.data();
    const role = String(membership?.role ?? "member");
    const status = String(membership?.status ?? "inactive");
    if (!membership || !managerRoles.has(role) || !["active", "trialing"].includes(status)) {
        throw new functions.https.HttpsError("permission-denied", "Only covenant creators, admins, and moderators can manage spatial rooms.");
    }
}

function roomTypeForKind(kind: SpatialRoomKind): string {
    switch (kind) {
    case "prayer": return "prayer";
    case "bibleStudy": return "study";
    case "voice": return "community";
    case "event": return "events";
    case "creator": return "inner_circle";
    case "berean": return "q_and_a";
    default: return "community";
    }
}

function motionStyleForKind(kind: SpatialRoomKind): string {
    switch (kind) {
    case "prayer": return "slow_light_rays";
    case "bibleStudy": return "turning_pages";
    case "berean": return "scripture_highlights";
    case "voice": return "soft_waveform";
    case "event": return "arrival_lights";
    case "selah": return "night_breath";
    default: return "ambient_parallax";
    }
}

function promptForDraft(draft: SpatialRoomDraft): string {
    const atmosphere = draft.kind.replace(/([A-Z])/g, " $1").toLowerCase();
    return [
        `Create a calm cinematic ${atmosphere} room for Amen.`,
        `Room name: ${draft.name}.`,
        `Purpose: ${draft.purpose}.`,
        "Use spiritual warmth, real-world texture, readable negative space, and restrained motion.",
        "Avoid neon, gamer styling, clutter, heavy glass, or text baked into the artwork.",
    ].join(" ");
}

function buildTheme(draft: SpatialRoomDraft, media?: Record<string, unknown>): SpatialTheme {
    return {
        kind: draft.kind,
        artworkURL: typeof media?.artworkURL === "string" ? media.artworkURL : undefined,
        videoURL: typeof media?.videoURL === "string" ? media.videoURL : undefined,
        ambientAudioURL: typeof media?.ambientAudioURL === "string" ? media.ambientAudioURL : undefined,
        motionStyle: motionStyleForKind(draft.kind),
        generatedPrompt: promptForDraft(draft),
        voiceEnabled: draft.voiceEnabled,
        prayerEnabled: draft.prayerEnabled,
        aiModerationEnabled: draft.aiModerationEnabled,
        mediaStatus: media ? "generated_metadata" : "pending_media_generation",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

function buildAmbientState(draft: SpatialRoomDraft, activeCount = 0): AmbientState {
    const isLive = draft.voiceEnabled || activeCount > 0;
    return {
        activeCount,
        activityText: isLive ? "Room live now" : "Ready for first reflection",
        secondaryText: draft.voiceEnabled ? "Voice room enabled" : draft.isPublic ? "Open community space" : "Private room",
        isLive,
        momentum: draft.voiceEnabled ? 0.42 : 0.24,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

function draftFromRoom(room: FirebaseFirestore.DocumentData): SpatialRoomDraft {
    const type = String(room.type ?? "community");
    const kind: SpatialRoomKind = type === "prayer" ? "prayer" : type === "study" ? "bibleStudy" : type === "q_and_a" ? "berean" : type === "events" ? "event" : "community";
    return {
        covenantId: String(room.covenantId ?? ""),
        name: String(room.name ?? "Room"),
        purpose: String(room.description ?? "A living room for spiritually constructive community."),
        kind,
        isPublic: room.isLocked !== true,
        voiceEnabled: false,
        prayerEnabled: kind === "prayer",
        aiModerationEnabled: true,
    };
}

export const generateSpatialRoomTheme = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
    const draft = readDraft(data);
    await assertCanManageCovenant(uid, draft.covenantId);

    const media = (data as Record<string, unknown>).media;
    const theme = buildTheme(draft, typeof media === "object" && media !== null ? media as Record<string, unknown> : undefined);
    await db.collection("spatialRoomThemeRequests").add({
        covenantId: draft.covenantId,
        requestedByUid: uid,
        draftKind: draft.kind,
        generatedPrompt: theme.generatedPrompt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return theme;
});

export const createCovenantSpatialRoom = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
    const draft = readDraft(data);
    await assertCanManageCovenant(uid, draft.covenantId);

    const roomRef = db.collection("covenants").doc(draft.covenantId).collection("rooms").doc();
    const theme = buildTheme(draft);
    const ambientState = buildAmbientState(draft);

    await roomRef.set({
        covenantId: draft.covenantId,
        name: draft.name,
        description: draft.purpose,
        type: roomTypeForKind(draft.kind),
        isLocked: !draft.isPublic,
        requiredTierId: null,
        creatorOnly: false,
        slowModeSeconds: 0,
        unreadCount: 0,
        lastMessage: null,
        lastMessageAt: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdByUid: uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        spatialTheme: theme,
        ambientState,
        moderation: {
            aiModerationEnabled: draft.aiModerationEnabled,
            youthSafe: true,
            level: draft.aiModerationEnabled ? "standard" : "manual",
        },
        voice: {
            enabled: draft.voiceEnabled,
            currentSessionId: null,
        },
        presence: {
            activeCount: 0,
            prayingCount: draft.prayerEnabled ? 0 : null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    });

    await db.collection("spatialRoomAudit").add({
        action: "create",
        covenantId: draft.covenantId,
        roomId: roomRef.id,
        actorUid: uid,
        kind: draft.kind,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { roomId: roomRef.id, spatialTheme: theme, ambientState };
});

export const backfillCovenantSpatialRooms = functions.https.onCall(async (data, context) => {
    const uid = requireUid(context);
    if (context.app == undefined) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
    const covenantId = readString(data, "covenantId", 96);
    await assertCanManageCovenant(uid, covenantId);

    const roomIdsValue = (data as Record<string, unknown>).roomIds;
    const requestedRoomIds = Array.isArray(roomIdsValue)
        ? roomIdsValue.filter((value): value is string => typeof value === "string" && value.trim().length > 0).slice(0, 100)
        : [];

    const roomsCollection = db.collection("covenants").doc(covenantId).collection("rooms");
    const roomDocs = requestedRoomIds.length > 0
        ? (await Promise.all(requestedRoomIds.map((roomId) => roomsCollection.doc(roomId).get()))).filter((snap) => snap.exists)
        : (await roomsCollection.limit(100).get()).docs;

    const batch = db.batch();
    let count = 0;

    for (const roomDoc of roomDocs) {
        const room = roomDoc.data() ?? {};
        const draft = draftFromRoom({ ...room, covenantId });
        const update: Record<string, unknown> = {};
        if (!room.spatialTheme) {
            update.spatialTheme = buildTheme(draft);
        }
        if (!room.ambientState) {
            update.ambientState = buildAmbientState(draft, Number(room.activeCount ?? 0));
        }
        if (Object.keys(update).length > 0) {
            batch.set(roomDoc.ref, update, { merge: true });
            count += 1;
        }
    }

    if (count > 0) {
        await batch.commit();
    }

    await db.collection("spatialRoomAudit").add({
        action: "backfill",
        covenantId,
        actorUid: uid,
        count,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { count };
});

export const onCovenantRoomMessageCreatedUpdateAmbientState = functions.firestore
    .document("covenants/{covenantId}/rooms/{roomId}/messages/{messageId}")
    .onCreate(async (snapshot, context) => {
        const message = snapshot.data() ?? {};
        const roomRef = db.collection("covenants").doc(context.params.covenantId).collection("rooms").doc(context.params.roomId);
        const roomSnap = await roomRef.get();
        if (!roomSnap.exists) { return; }

        const room = roomSnap.data() ?? {};
        const theme = room.spatialTheme as Record<string, unknown> | undefined;
        const kind = typeof theme?.kind === "string" && validKinds.has(theme.kind) ? theme.kind as SpatialRoomKind : draftFromRoom({ ...room, covenantId: context.params.covenantId }).kind;
        const isPrayer = kind === "prayer";
        const isVoice = Boolean((room.voice as Record<string, unknown> | undefined)?.enabled);
        const authorName = typeof message.authorName === "string" ? message.authorName : "Someone";

        await roomRef.set({
            ambientState: {
                activeCount: admin.firestore.FieldValue.increment(1),
                activityText: isPrayer ? `${authorName} added a prayer reflection` : `${authorName} continued the room`,
                secondaryText: isVoice ? "Voice room enabled" : "New reflection just arrived",
                isLive: true,
                momentum: isPrayer ? 0.72 : 0.58,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
        }, { merge: true });
    });
