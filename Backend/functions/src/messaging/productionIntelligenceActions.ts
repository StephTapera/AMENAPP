import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { requireAuthAndAppCheck } from "../amenAI/common";
import { enforceRateLimit, RateLimitConfig } from "../rateLimit";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const REGION = "us-central1";
const MAX_MESSAGE_TEXT = 5_000;
const MAX_TRANSLATION_TEXT = 4_000;
const MAX_CATCH_UP_MESSAGES = 60;

const INTELLIGENCE_LIMITS: RateLimitConfig[] = [
    { name: "messaging_intelligence_1min", windowMs: 60_000, maxCalls: 12 },
    { name: "messaging_intelligence_1day", windowMs: 86_400_000, maxCalls: 120 },
];

const SAFETY_LIMITS: RateLimitConfig[] = [
    { name: "messaging_safety_1min", windowMs: 60_000, maxCalls: 30 },
    { name: "messaging_safety_1day", windowMs: 86_400_000, maxCalls: 500 },
];

type SafetyDecision = "allow" | "softWarn" | "requireEdit" | "block" | "unavailable";

interface ConversationData {
    participants?: unknown;
    type?: unknown;
    blockedUserIds?: unknown;
}

interface MessageData {
    text?: unknown;
    body?: unknown;
    senderId?: unknown;
    senderName?: unknown;
    timestamp?: unknown;
    createdAt?: unknown;
    isDeleted?: unknown;
    deletedAt?: unknown;
    isBlocked?: unknown;
    blocked?: unknown;
    isRestricted?: unknown;
    restricted?: unknown;
    moderationStatus?: unknown;
    status?: unknown;
    kind?: unknown;
    messageType?: unknown;
}

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
    if (value === undefined || value === null) return null;
    if (typeof value !== "string") {
        throw new HttpsError("invalid-argument", "Optional text fields must be strings.");
    }
    const trimmed = value.trim();
    return trimmed ? trimmed.slice(0, maxLength) : null;
}

function participantsArray(data: ConversationData): string[] {
    return Array.isArray(data.participants)
        ? data.participants.filter((participant): participant is string => typeof participant === "string")
        : [];
}

function isRestrictedMessage(message: MessageData): boolean {
    const moderationStatus = typeof message.moderationStatus === "string"
        ? message.moderationStatus.toLowerCase()
        : "";
    const status = typeof message.status === "string" ? message.status.toLowerCase() : "";
    const type = typeof message.messageType === "string"
        ? message.messageType.toLowerCase()
        : typeof message.kind === "string"
            ? message.kind.toLowerCase()
            : "";

    return message.isDeleted === true ||
        message.deletedAt !== undefined ||
        message.isBlocked === true ||
        message.blocked === true ||
        message.isRestricted === true ||
        message.restricted === true ||
        ["blocked", "deleted", "hidden", "removed", "restricted"].includes(moderationStatus) ||
        ["blocked", "deleted", "hidden", "removed", "restricted"].includes(status) ||
        ["moderation", "legal", "enforcement", "system_enforcement"].includes(type);
}

function messageText(message: MessageData, maxLength = MAX_MESSAGE_TEXT): string {
    const raw = typeof message.text === "string"
        ? message.text
        : typeof message.body === "string"
            ? message.body
            : "";
    return raw.trim().slice(0, maxLength);
}

function validateLanguage(code: unknown, field: string): string {
    const language = requireString(code, field, 16).toLowerCase();
    if (!/^[a-z]{2,3}(-[a-z]{2})?$/.test(language) && language !== "auto") {
        throw new HttpsError("invalid-argument", `${field} must be a valid language code.`);
    }
    return language;
}

async function getConversationForParticipant(uid: string, conversationId: string) {
    const conversationRef = admin.firestore().collection("conversations").doc(conversationId);
    const conversationSnap = await conversationRef.get();
    if (!conversationSnap.exists) {
        throw new HttpsError("not-found", "Conversation not found.");
    }
    const conversation = conversationSnap.data() as ConversationData;
    if (!participantsArray(conversation).includes(uid)) {
        throw new HttpsError("permission-denied", "Not a participant in this conversation.");
    }
    return { conversationRef, conversation };
}

async function getAuthorizedMessage(uid: string, conversationId: string, messageId: string) {
    const { conversationRef } = await getConversationForParticipant(uid, conversationId);
    const messageSnap = await conversationRef.collection("messages").doc(messageId).get();
    if (!messageSnap.exists) {
        throw new HttpsError("not-found", "Message not found.");
    }
    const message = messageSnap.data() as MessageData;
    if (isRestrictedMessage(message)) {
        throw new HttpsError("permission-denied", "This message is not eligible for intelligence actions.");
    }
    return { message, messageId, conversationId };
}

async function requireGuardedRequest<T>(
    request: { auth?: { uid?: string } | null; app?: unknown; data: unknown },
    limits: RateLimitConfig[],
    actionName: string,
    handler: (uid: string, data: Record<string, unknown>) => Promise<T>,
): Promise<T> {
    const uid = await requireAuthAndAppCheck(request.auth ?? null, request.app ?? null);
    await enforceRateLimit(uid, limits);
    if (typeof request.data !== "object" || request.data === null || Array.isArray(request.data)) {
        throw new HttpsError("invalid-argument", "Request body must be an object.");
    }
    logger.info("Messaging intelligence action requested", { uid, actionName });
    return handler(uid, request.data as Record<string, unknown>);
}

async function callClaudeJson(prompt: string, maxTokens: number): Promise<Record<string, unknown>> {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "x-api-key": anthropicApiKey.value(),
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        body: JSON.stringify({
            model: "claude-haiku-4-5-20251001",
            max_tokens: maxTokens,
            messages: [{ role: "user", content: prompt }],
        }),
    });

    if (!response.ok) {
        throw new HttpsError("unavailable", "Messaging intelligence is temporarily unavailable.");
    }

    const data = await response.json() as { content?: Array<{ text?: string }> };
    const raw = data.content?.[0]?.text ?? "";
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
        throw new HttpsError("internal", "Model returned an invalid response.");
    }
    try {
        return JSON.parse(jsonMatch[0]) as Record<string, unknown>;
    } catch {
        throw new HttpsError("internal", "Model returned malformed JSON.");
    }
}

function stringArray(value: unknown, limit: number): string[] {
    if (!Array.isArray(value)) return [];
    return value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean)
        .slice(0, limit);
}

function messageIdArray(value: unknown, allowedIds: Set<string>, limit: number): string[] {
    return stringArray(value, limit).filter((id) => allowedIds.has(id));
}

export const translateMessage = onCall(
    { enforceAppCheck: true, region: REGION, secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => requireGuardedRequest(request, INTELLIGENCE_LIMITS, "translateMessage", async (uid, data) => {
        const conversationId = requireString(data.conversationId, "conversationId");
        const messageId = requireString(data.messageId, "messageId");
        const targetLanguage = validateLanguage(data.targetLanguage, "targetLanguage");
        const sourceLanguage = optionalString(data.sourceLanguage, 16) ?? "auto";
        validateLanguage(sourceLanguage, "sourceLanguage");

        const { message } = await getAuthorizedMessage(uid, conversationId, messageId);
        const text = messageText(message, MAX_TRANSLATION_TEXT);
        if (!text) {
            throw new HttpsError("failed-precondition", "Message has no text to translate.");
        }

        const parsed = await callClaudeJson(
            [
                "Translate the private chat message into the target language.",
                "Return JSON only: {\"translatedText\":\"...\",\"detectedLanguage\":\"...\"}.",
                "Do not add commentary. Preserve meaning and tone. Do not store or reuse the content.",
                `Source language: ${sourceLanguage}`,
                `Target language: ${targetLanguage}`,
                `Message: ${text}`,
            ].join("\n"),
            800,
        );

        const translatedText = typeof parsed.translatedText === "string" ? parsed.translatedText.trim() : "";
        if (!translatedText) {
            throw new HttpsError("internal", "Translation response was empty.");
        }

        return {
            translatedText: translatedText.slice(0, MAX_TRANSLATION_TEXT * 2),
            detectedLanguage: typeof parsed.detectedLanguage === "string" ? parsed.detectedLanguage.slice(0, 16) : sourceLanguage,
            sourceMessageId: messageId,
            sourceConversationId: conversationId,
            aiAssisted: true,
            cached: false,
        };
    }),
);

export const analyzeMessageSafety = onCall(
    { enforceAppCheck: true, region: REGION, secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => requireGuardedRequest(request, SAFETY_LIMITS, "analyzeMessageSafety", async (uid, data) => {
        const conversationId = requireString(data.conversationId, "conversationId");
        const draftText = requireString(data.text, "text", 5_000);
        const destination = optionalString(data.destination, 80) ?? "currentConversation";
        const { conversation } = await getConversationForParticipant(uid, conversationId);
        const participantCount = participantsArray(conversation).length;

        const parsed = await callClaudeJson(
            [
                "Review this Amen private messaging draft for send safety.",
                "Return JSON only with keys: decision, reasons, userMessage.",
                "decision must be one of allow, softWarn, requireEdit, block.",
                "Use block only for clearly unsafe or policy-violating content.",
                "Use requireEdit for private info oversharing or harassment that should be changed.",
                "Use softWarn for ambiguous sensitivity where Send Anyway may be allowed.",
                "Do not quote the draft in the response.",
                `Participant count: ${participantCount}`,
                `Destination: ${destination}`,
                `Draft: ${draftText}`,
            ].join("\n"),
            500,
        );

        const rawDecision = typeof parsed.decision === "string" ? parsed.decision : "unavailable";
        const decision: SafetyDecision = ["allow", "softWarn", "requireEdit", "block"].includes(rawDecision)
            ? rawDecision as SafetyDecision
            : "unavailable";
        return {
            decision,
            reasons: stringArray(parsed.reasons, 4),
            message: typeof parsed.userMessage === "string" ? parsed.userMessage.slice(0, 240) : "",
            allowSendAnyway: decision === "softWarn",
            aiAssisted: true,
        };
    }),
);

export const summarizeConversationCatchUp = onCall(
    { enforceAppCheck: true, region: REGION, secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => requireGuardedRequest(request, INTELLIGENCE_LIMITS, "summarizeConversationCatchUp", async (uid, data) => {
        const conversationId = requireString(data.conversationId, "conversationId");
        const limit = Math.min(Math.max(Number(data.limit) || 40, 1), MAX_CATCH_UP_MESSAGES);
        const { conversationRef } = await getConversationForParticipant(uid, conversationId);

        const messagesSnap = await conversationRef
            .collection("messages")
            .orderBy("timestamp", "desc")
            .limit(limit)
            .get();

        const eligible = messagesSnap.docs
            .map((doc) => ({ id: doc.id, data: doc.data() as MessageData }))
            .filter(({ data: message }) => !isRestrictedMessage(message) && !!messageText(message, 800))
            .reverse();

        if (eligible.length === 0) {
            return {
                status: "empty",
                aiAssisted: false,
                keyDecisions: [],
                directAsks: [],
                timeDateChanges: [],
                actionItems: [],
                mediaShared: [],
                notesCreated: [],
                prayerRequests: [],
                referencedMessageIds: [],
            };
        }

        const allowedIds = new Set(eligible.map((item) => item.id));
        const transcript = eligible
            .map(({ id, data: message }) => `${id}: ${String(message.senderName ?? "Someone")}: ${messageText(message, 800)}`)
            .join("\n");

        const parsed = await callClaudeJson(
            [
                "Summarize this private conversation catch-up for an authorized participant.",
                "Return JSON only with keys: keyDecisions, directAsks, timeDateChanges, actionItems, mediaShared, notesCreated, prayerRequests, referencedMessageIds.",
                "Each list max 5. Include prayerRequests only when explicitly present. Do not invent spiritual context, owners, deadlines, or tasks.",
                "referencedMessageIds must only use IDs from the transcript.",
                transcript,
            ].join("\n"),
            900,
        );

        return {
            status: "ready",
            aiAssisted: true,
            keyDecisions: stringArray(parsed.keyDecisions, 5),
            directAsks: stringArray(parsed.directAsks, 5),
            timeDateChanges: stringArray(parsed.timeDateChanges, 5),
            actionItems: stringArray(parsed.actionItems, 5),
            mediaShared: stringArray(parsed.mediaShared, 5),
            notesCreated: stringArray(parsed.notesCreated, 5),
            prayerRequests: stringArray(parsed.prayerRequests, 5),
            referencedMessageIds: messageIdArray(parsed.referencedMessageIds, allowedIds, 10),
        };
    }),
);

