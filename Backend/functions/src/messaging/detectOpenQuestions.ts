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

export const detectOpenQuestions = onCall(
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
        if (messages.length === 0) return { questions: [] };

        const allowedIds = new Set(messages.map((message) => message.id));
        const prompt = [
            "Analyze this conversation and identify open questions that lack a clear answer.",
            "Return strict JSON: {\"questions\":[{\"id\":\"string\",\"question\":\"string\",\"askedByUid\":null,\"sourceMessageIds\":[\"message-id\"],\"answeredByMessageId\":null,\"status\":\"open|answered|stale\",\"confidence\":0.0}]}",
            "Only include genuine questions. Do not infer private inaccessible context.",
            `Messages JSON: ${JSON.stringify(messages)}`,
        ].join("\n");

        const parsed = await callClaudeJson(anthropicApiKey.value(), prompt, 800);
        const questions = Array.isArray(parsed.questions) ? parsed.questions.slice(0, 8).map((question: Record<string, unknown>, index: number) => {
            const text = String(question.question ?? "").slice(0, 500);
            const sources = sourceMessageIds(question.sourceMessageIds, allowedIds, 10);
            const sourceMessageId = sources[0] ?? "";
            const status = ["open", "answered", "stale"].includes(String(question.status)) ? String(question.status) : "open";
            return {
                id: String(question.id ?? `question_${index}`),
                question: text,
                askedByUid: typeof question.askedByUid === "string" ? question.askedByUid : null,
                sourceMessageId,
                sourceMessageIds: sources,
                answeredByMessageId: typeof question.answeredByMessageId === "string" && allowedIds.has(question.answeredByMessageId) ? question.answeredByMessageId : null,
                status,
                isResolved: status === "answered",
                confidence: typeof question.confidence === "number" ? Math.max(0, Math.min(1, question.confidence)) : 0.5,
                createdBy: "system",
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
        }).filter((question) => question.question.length > 0 && question.sourceMessageIds.length > 0) : [];

        const batch = admin.firestore().batch();
        questions.forEach((question) => {
            batch.set(ref.collection("questions").doc(question.id), question, { merge: true });
        });
        batch.set(ref.collection("smartContext").doc("main"), {
            questionCount: questions.filter((question) => question.status === "open").length,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: "system",
        }, { merge: true });
        await batch.commit();

        return { questions };
    }
);
