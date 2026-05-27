import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";

export interface ConversationMessageForAI {
    id: string;
    sender: string;
    text: string;
    timestamp: string | null;
    type: string;
}

export interface AuthorizedConversation {
    ref: admin.firestore.DocumentReference;
    data: admin.firestore.DocumentData;
    participantIds: string[];
}

export async function requireMessagingBudget(uid: string): Promise<void> {
    await enforceRateLimit(uid, [RATE_LIMITS.AI_PER_MINUTE, RATE_LIMITS.AI_PER_DAY]);
}

export async function getAuthorizedConversation(
    uid: string,
    conversationId: string,
): Promise<AuthorizedConversation> {
    if (!conversationId || typeof conversationId !== "string") {
        throw new HttpsError("invalid-argument", "conversationId is required.");
    }
    const ref = admin.firestore().collection("conversations").doc(conversationId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Conversation not found.");
    const data = snap.data() ?? {};
    const participantIds = Array.isArray(data.participantIds)
        ? data.participantIds.filter((id): id is string => typeof id === "string")
        : Array.isArray(data.participants)
            ? data.participants.filter((id): id is string => typeof id === "string")
            : [];
    if (!participantIds.includes(uid)) {
        throw new HttpsError("permission-denied", "Not a participant in this conversation.");
    }
    return { ref, data, participantIds };
}

export async function loadRecentMessages(
    conversationRef: admin.firestore.DocumentReference,
    limit = 80,
    since?: admin.firestore.Timestamp,
): Promise<ConversationMessageForAI[]> {
    let query: admin.firestore.Query = conversationRef.collection("messages");
    if (since) query = query.where("timestamp", ">=", since);
    const snap = await query.orderBy("timestamp", "desc").limit(limit).get();
    return snap.docs
        .map((doc) => {
            const data = doc.data();
            const text = typeof data.text === "string"
                ? data.text.trim()
                : typeof data.body === "string"
                    ? data.body.trim()
                    : "";
            if (!text || isRestrictedMessage(data)) return null;
            return {
                id: doc.id,
                sender: typeof data.senderName === "string" ? data.senderName : "User",
                text: text.slice(0, 800),
                timestamp: data.timestamp?.toDate?.()?.toISOString?.() ?? data.createdAt?.toDate?.()?.toISOString?.() ?? null,
                type: typeof data.type === "string" ? data.type : typeof data.messageType === "string" ? data.messageType : "message",
            };
        })
        .filter((item): item is ConversationMessageForAI => item !== null)
        .reverse();
}

export function isRestrictedMessage(data: admin.firestore.DocumentData): boolean {
    const status = typeof data.status === "string" ? data.status.toLowerCase() : "";
    const moderationStatus = typeof data.moderationStatus === "string" ? data.moderationStatus.toLowerCase() : "";
    return data.isDeleted === true ||
        data.deletedAt !== undefined ||
        data.isBlocked === true ||
        data.blocked === true ||
        data.isRestricted === true ||
        data.restricted === true ||
        ["blocked", "deleted", "hidden", "removed", "restricted"].includes(status) ||
        ["blocked", "deleted", "hidden", "removed", "restricted"].includes(moderationStatus);
}

export async function callClaudeJson(apiKey: string, prompt: string, maxTokens: number): Promise<Record<string, unknown>> {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        body: JSON.stringify({
            model: "claude-haiku-4-5-20251001",
            max_tokens: maxTokens,
            messages: [{ role: "user", content: prompt }],
        }),
    });
    if (!response.ok) throw new HttpsError("unavailable", "AI extraction failed.");
    const data = await response.json() as { content?: Array<{ text?: string }> };
    const raw = data.content?.[0]?.text ?? "{}";
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return {};
    try {
        return JSON.parse(jsonMatch[0]) as Record<string, unknown>;
    } catch {
        return {};
    }
}

export function sourceMessageIds(value: unknown, allowedIds: Set<string>, limit = 10): string[] {
    if (!Array.isArray(value)) return [];
    return value
        .filter((item): item is string => typeof item === "string")
        .filter((id) => allowedIds.has(id))
        .slice(0, limit);
}

export function stringArray(value: unknown, limit: number): string[] {
    if (!Array.isArray(value)) return [];
    return value
        .filter((item): item is string => typeof item === "string")
        .map((item) => item.trim())
        .filter(Boolean)
        .slice(0, limit);
}
