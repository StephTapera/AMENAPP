import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
    callClaudeJson,
    getAuthorizedConversation,
    loadRecentMessages,
    requireMessagingBudget,
} from "./threadIntelligenceUtils";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const searchConversationMemory = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId, threadId, query } = request.data;
        const resolvedConversationId = typeof conversationId === "string" ? conversationId : threadId;

        if (!resolvedConversationId || typeof resolvedConversationId !== "string") {
            throw new HttpsError("invalid-argument", "conversationId or threadId is required.");
        }
        if (!query || typeof query !== "string" || query.trim().length === 0) {
            throw new HttpsError("invalid-argument", "query is required.");
        }
        if (query.length > 500) {
            throw new HttpsError("invalid-argument", "query too long.");
        }
        await requireMessagingBudget(uid);

        const { ref } = await getAuthorizedConversation(uid, resolvedConversationId);
        const messages = await loadRecentMessages(ref, 200);
        if (messages.length === 0) return { results: [] };

        const allowedIds = new Set(messages.map((message) => message.id));
        const prompt = [
            "Search this permission-scoped conversation history.",
            "Return strict JSON: {\"results\":[{\"id\":\"message-id\",\"type\":\"message|decision|task|file|media|meeting|person\",\"title\":\"string\",\"snippet\":\"string\",\"sourceMessageId\":\"message-id\",\"relevanceScore\":0.0}],\"aiSummary\":\"string|null\"}",
            "Only return sourceMessageId values present in input. Never return inaccessible data.",
            `Query: ${query.trim()}`,
            `Messages JSON: ${JSON.stringify(messages.slice(0, 120))}`,
        ].join("\n");

        const parsed = await callClaudeJson(anthropicApiKey.value(), prompt, 900);
        const results = Array.isArray(parsed.results) ? parsed.results.slice(0, 8).map((result: Record<string, unknown>) => {
            const sourceMessageId = typeof result.sourceMessageId === "string"
                ? result.sourceMessageId
                : typeof result.id === "string" ? result.id : "";
            if (!allowedIds.has(sourceMessageId)) return null;
            const original = messages.find((message) => message.id === sourceMessageId);
            const type = ["message", "decision", "task", "file", "media", "meeting", "person"].includes(String(result.type))
                ? String(result.type)
                : "message";
            return {
                id: sourceMessageId,
                type,
                title: String(result.title ?? type).slice(0, 120),
                snippet: String(result.snippet ?? original?.text ?? "").slice(0, 220),
                sourcePath: `conversations/${resolvedConversationId}/messages/${sourceMessageId}`,
                sourceMessageId,
                messageId: sourceMessageId,
                relevanceScore: typeof result.relevanceScore === "number" ? Math.max(0, Math.min(1, result.relevanceScore)) : 0.5,
                timestamp: original?.timestamp ?? null,
            };
        }).filter((result): result is NonNullable<typeof result> => result !== null && result.snippet.length > 0) : [];

        const memoryRef = ref.collection("memoryIndex").doc();
        await memoryRef.set({
            query: query.trim().slice(0, 500),
            resultCount: results.length,
            createdByUid: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
            results,
            aiSummary: typeof parsed.aiSummary === "string" ? parsed.aiSummary.slice(0, 500) : undefined,
        };
    }
);
