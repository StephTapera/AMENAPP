import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireAuthAndAppCheck } from "../amenAI/common";
import { enforceRateLimit, RateLimitConfig } from "../rateLimit";

type SourceSurface = "messaging";

interface BaseMessageActionRequest {
    conversationId: unknown;
    messageId: unknown;
}

interface SaveMessageToNotesRequest extends BaseMessageActionRequest {
    title?: unknown;
    userEditedBody?: unknown;
    sourceSurface?: unknown;
}

interface CreateMessageReminderRequest extends BaseMessageActionRequest {
    dueAt?: unknown;
    title?: unknown;
    note?: unknown;
}

interface CreateSelahReflectionRequest extends BaseMessageActionRequest {
    reflectionTitle?: unknown;
    userEditedReflection?: unknown;
}

interface ConversationData {
    participants?: unknown;
}

interface MessageData {
    text?: unknown;
    body?: unknown;
    senderId?: unknown;
    senderName?: unknown;
    createdAt?: unknown;
    timestamp?: unknown;
    isDeleted?: unknown;
    deletedAt?: unknown;
    isBlocked?: unknown;
    blocked?: unknown;
    isRestricted?: unknown;
    restricted?: unknown;
    moderationStatus?: unknown;
    status?: unknown;
}

const PRIVATE_ACTION_LIMITS: RateLimitConfig[] = [
    { name: "messaging_private_action_1min", windowMs: 60_000, maxCalls: 20 },
    { name: "messaging_private_action_1day", windowMs: 86_400_000, maxCalls: 200 },
];

const REGION = "us-central1";
const MAX_TITLE_LENGTH = 120;
const MAX_BODY_LENGTH = 20_000;
const MAX_REMINDER_NOTE_LENGTH = 2_000;

function requireString(value: unknown, field: string, maxLength = 160): string {
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", `${field} must be a string.`);
    }
    const trimmed = value.trim();
    if (!trimmed || trimmed.length > maxLength) {
        throw new HttpsError("invalid-argument", `${field} is invalid.`);
    }
    return trimmed;
}

function optionalString(value: unknown, maxLength: number): string | null {
    if (value === undefined || value === null) {
        return null;
    }
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", "Optional text fields must be strings.");
    }
    const trimmed = value.trim();
    if (!trimmed) {
        return null;
    }
    return trimmed.slice(0, maxLength);
}

function requireSourceSurface(value: unknown): SourceSurface {
    if (value === undefined || value === null || value === "messaging") {
        return "messaging";
    }
    throw new HttpsError("invalid-argument", "sourceSurface must be messaging.");
}

function participantsArray(data: ConversationData): string[] {
    return Array.isArray(data.participants)
        ? data.participants.filter((participant): participant is string => typeof participant === "string")
        : [];
}

function isMessageRestricted(message: MessageData): boolean {
    const moderationStatus = typeof message.moderationStatus === "string"
        ? message.moderationStatus.toLowerCase()
        : "";
    const status = typeof message.status === "string" ? message.status.toLowerCase() : "";

    return message.isDeleted === true ||
        message.deletedAt !== undefined ||
        message.isBlocked === true ||
        message.blocked === true ||
        message.isRestricted === true ||
        message.restricted === true ||
        ["blocked", "deleted", "hidden", "removed", "restricted"].includes(moderationStatus) ||
        ["blocked", "deleted", "hidden", "removed", "restricted"].includes(status);
}

function messageText(message: MessageData): string {
    const raw = typeof message.text === "string"
        ? message.text
        : typeof message.body === "string"
            ? message.body
            : "";
    return raw.trim().slice(0, MAX_BODY_LENGTH);
}

function parseDueAt(value: unknown): admin.firestore.Timestamp {
    let millis: number | null = null;

    if (typeof value === "number" && Number.isFinite(value)) {
        millis = value;
    } else if (typeof value === "string") {
        const parsed = Date.parse(value);
        millis = Number.isFinite(parsed) ? parsed : null;
    } else if (
        typeof value === "object" &&
        value !== null &&
        "seconds" in value &&
        typeof (value as { seconds: unknown }).seconds === "number"
    ) {
        millis = (value as { seconds: number }).seconds * 1000;
    }

    if (millis === null) {
        throw new HttpsError("invalid-argument", "dueAt must be a future timestamp.");
    }

    const now = Date.now();
    if (millis <= now) {
        throw new HttpsError("invalid-argument", "dueAt must be in the future.");
    }

    return admin.firestore.Timestamp.fromMillis(millis);
}

async function getAuthorizedMessage(
    uid: string,
    conversationId: string,
    messageId: string,
): Promise<{ message: MessageData; conversationId: string; messageId: string }> {
    const db = admin.firestore();
    const conversationRef = db.collection("conversations").doc(conversationId);
    const conversationSnap = await conversationRef.get();

    if (!conversationSnap.exists) {
        throw new HttpsError("not-found", "Conversation not found.");
    }

    const conversation = conversationSnap.data() as ConversationData;
    if (!participantsArray(conversation).includes(uid)) {
        throw new HttpsError("permission-denied", "You are not a participant in this conversation.");
    }

    const messageSnap = await conversationRef.collection("messages").doc(messageId).get();
    if (!messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
    }

    const message = messageSnap.data() as MessageData;
    if (isMessageRestricted(message)) {
        throw new HttpsError("permission-denied", "This message cannot be saved.");
    }

    return { message, conversationId, messageId };
}

function sourceMetadata(
    message: MessageData,
    conversationId: string,
    messageId: string,
) {
    return {
        surface: "messaging",
        conversationId,
        messageId,
        senderId: typeof message.senderId === "string" ? message.senderId : null,
        senderName: typeof message.senderName === "string" ? message.senderName : null,
        sentAt: message.createdAt ?? message.timestamp ?? null,
    };
}

async function withPrivateActionGuard<T>(
    request: { auth?: { uid?: string } | null; app?: unknown; data: unknown },
    actionName: string,
    handler: (uid: string, data: Record<string, unknown>) => Promise<T>,
): Promise<T> {
    const uid = await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);
    await enforceRateLimit(uid, PRIVATE_ACTION_LIMITS);

    if (typeof request.data !== "object" || request.data === null || Array.isArray(request.data)) {
        throw new HttpsError("invalid-argument", "Request body must be an object.");
    }

    logger.info("Messaging private action requested", { uid, actionName });
    return handler(uid, request.data as Record<string, unknown>);
}

export const saveMessageToNotes = onCall(
    { enforceAppCheck: true, region: REGION },
    async (request) => withPrivateActionGuard(request, "saveMessageToNotes", async (uid, data) => {
        const body = data as unknown as SaveMessageToNotesRequest;
        const conversationId = requireString(body.conversationId, "conversationId");
        const messageId = requireString(body.messageId, "messageId");
        requireSourceSurface(body.sourceSurface);

        const { message } = await getAuthorizedMessage(uid, conversationId, messageId);
        const noteBody = optionalString(body.userEditedBody, MAX_BODY_LENGTH) ?? messageText(message);
        if (!noteBody) {
            throw new HttpsError("failed-precondition", "Message has no text to save.");
        }

        const now = admin.firestore.Timestamp.now();
        const noteRef = admin.firestore()
            .collection("users").doc(uid)
            .collection("privateMessageNotes").doc();

        await noteRef.set({
            noteId: noteRef.id,
            ownerUid: uid,
            title: optionalString(body.title, MAX_TITLE_LENGTH) ?? "Message note",
            body: noteBody,
            visibility: "private",
            aiAssisted: false,
            source: sourceMetadata(message, conversationId, messageId),
            createdAt: now,
            updatedAt: now,
        });

        logger.info("Messaging private note created", { uid, noteId: noteRef.id, conversationId, messageId });
        return {
            noteId: noteRef.id,
            createdAt: now.toMillis(),
            sourceMessageId: messageId,
            sourceConversationId: conversationId,
        };
    }),
);

export const createMessageReminder = onCall(
    { enforceAppCheck: true, region: REGION },
    async (request) => withPrivateActionGuard(request, "createMessageReminder", async (uid, data) => {
        const body = data as unknown as CreateMessageReminderRequest;
        const conversationId = requireString(body.conversationId, "conversationId");
        const messageId = requireString(body.messageId, "messageId");
        const dueAt = parseDueAt(body.dueAt);
        const { message } = await getAuthorizedMessage(uid, conversationId, messageId);

        const now = admin.firestore.Timestamp.now();
        const reminderRef = admin.firestore()
            .collection("users").doc(uid)
            .collection("messageReminders").doc();

        await reminderRef.set({
            reminderId: reminderRef.id,
            ownerUid: uid,
            title: optionalString(body.title, MAX_TITLE_LENGTH) ?? "Message reminder",
            note: optionalString(body.note, MAX_REMINDER_NOTE_LENGTH),
            dueAt,
            completedAt: null,
            visibility: "private",
            source: sourceMetadata(message, conversationId, messageId),
            createdAt: now,
            updatedAt: now,
        });

        logger.info("Messaging reminder created", { uid, reminderId: reminderRef.id, conversationId, messageId });
        return {
            reminderId: reminderRef.id,
            dueAt: dueAt.toMillis(),
            sourceMessageId: messageId,
            sourceConversationId: conversationId,
        };
    }),
);

export const createSelahReflectionFromMessage = onCall(
    { enforceAppCheck: true, region: REGION },
    async (request) => withPrivateActionGuard(request, "createSelahReflectionFromMessage", async (uid, data) => {
        const body = data as unknown as CreateSelahReflectionRequest;
        const conversationId = requireString(body.conversationId, "conversationId");
        const messageId = requireString(body.messageId, "messageId");

        const { message } = await getAuthorizedMessage(uid, conversationId, messageId);
        const reflectionText = optionalString(body.userEditedReflection, MAX_BODY_LENGTH) ?? messageText(message);
        if (!reflectionText) {
            throw new HttpsError("failed-precondition", "Message has no text to reflect on.");
        }

        const now = admin.firestore.Timestamp.now();
        const reflectionRef = admin.firestore()
            .collection("users").doc(uid)
            .collection("selahMessageReflections").doc();

        await reflectionRef.set({
            reflectionId: reflectionRef.id,
            ownerUid: uid,
            title: optionalString(body.reflectionTitle, MAX_TITLE_LENGTH) ?? "Message reflection",
            text: reflectionText,
            visibility: "private",
            aiAssisted: false,
            source: sourceMetadata(message, conversationId, messageId),
            createdAt: now,
            updatedAt: now,
        });

        logger.info("Messaging Selah reflection created", {
            uid,
            reflectionId: reflectionRef.id,
            conversationId,
            messageId,
        });
        return {
            reflectionId: reflectionRef.id,
            createdAt: now.toMillis(),
            sourceMessageId: messageId,
            sourceConversationId: conversationId,
        };
    }),
);
