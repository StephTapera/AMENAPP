import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
    callClaudeJson,
    getAuthorizedConversation,
    loadRecentMessages,
    requireMessagingBudget,
    sourceMessageIds,
} from "./threadIntelligenceUtils";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const extractThreadActions = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId } = request.data;
        await requireMessagingBudget(uid);

        const { ref } = await getAuthorizedConversation(uid, conversationId);
        const messages = await loadRecentMessages(ref, 80);
        if (messages.length === 0) return { actions: [] };

        const allowedIds = new Set(messages.map((message) => message.id));
        const prompt = [
            "Analyze this conversation and extract suggested tasks or follow-ups.",
            "Return strict JSON: {\"actions\":[{\"id\":\"string\",\"title\":\"string\",\"description\":\"string|null\",\"sourceMessageIds\":[\"message-id\"],\"assignedToUid\":null,\"dueDate\":null,\"confidence\":0.0,\"status\":\"suggested\"}]}",
            "Never invent assignees or deadlines. Use assignedToUid only if an explicit UID appears in input; otherwise null.",
            `Messages JSON: ${JSON.stringify(messages)}`,
        ].join("\n");

        const parsed = await callClaudeJson(anthropicApiKey.value(), prompt, 800);
        const actions = Array.isArray(parsed.actions) ? parsed.actions.slice(0, 8).map((action: Record<string, unknown>, index: number) => {
            const title = String(action.title ?? action.action ?? "").slice(0, 180);
            const sources = sourceMessageIds(action.sourceMessageIds, allowedIds, 10);
            return {
                id: String(action.id ?? `action_${index}`),
                title,
                action: title,
                description: typeof action.description === "string" ? action.description.slice(0, 500) : null,
                sourceMessageIds: sources,
                assignedToUid: typeof action.assignedToUid === "string" ? action.assignedToUid : null,
                dueDate: null,
                confidence: typeof action.confidence === "number" ? Math.max(0, Math.min(1, action.confidence)) : 0.5,
                status: "suggested",
                createdBy: "system",
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
        }).filter((action) => action.title.length > 0 && action.sourceMessageIds.length > 0) : [];

        const batch = admin.firestore().batch();
        actions.forEach((action) => {
            batch.set(ref.collection("actions").doc(action.id), action, { merge: true });
        });
        batch.set(ref.collection("smartContext").doc("main"), {
            actionCount: actions.length,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: "system",
        }, { merge: true });
        await batch.commit();

        return { actions };
    }
);
