import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import {
    callClaudeJson,
    getAuthorizedConversation,
    loadRecentMessages,
    requireMessagingBudget,
    stringArray,
} from "./threadIntelligenceUtils";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const generateGroupPulse = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId } = request.data;
        await requireMessagingBudget(uid);

        const { ref, data } = await getAuthorizedConversation(uid, conversationId);
        if (data.isGroup !== true) throw new HttpsError("invalid-argument", "Not a group conversation.");

        const since = admin.firestore.Timestamp.fromMillis(Date.now() - 172800000);
        const messages = await loadRecentMessages(ref, 100, since);
        if (messages.length === 0) {
            const emptyPulse = {
                activeTopic: "",
                activityLevel: "quiet",
                openQuestionsCount: 0,
                pendingDecisionCount: 0,
                taskCount: 0,
                recentMediaCount: 0,
                peopleNeedingResponse: [],
                suggestedNextAction: null,
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
                createdBy: "system",
            };
            await ref.collection("pulse").doc("main").set(emptyPulse, { merge: true });
            return emptyPulse;
        }

        const prompt = [
            "Analyze this group conversation and return a privacy-safe pulse.",
            "Return strict JSON with keys: activeTopic, activityLevel (quiet|active|high), openQuestionsCount, pendingDecisionCount, taskCount, recentMediaCount, peopleNeedingResponse, suggestedNextAction.",
            "Do not expose creepy behavioral details. Do not invent people or decisions.",
            `Messages JSON: ${JSON.stringify(messages)}`,
        ].join("\n");

        const parsed = await callClaudeJson(anthropicApiKey.value(), prompt, 700);
        const activityLevel = ["quiet", "active", "high"].includes(String(parsed.activityLevel)) ? String(parsed.activityLevel) : "active";
        const pulse = {
            activeTopic: typeof parsed.activeTopic === "string" ? parsed.activeTopic.slice(0, 160) : "",
            activityLevel,
            openQuestionsCount: boundedInt(parsed.openQuestionsCount, 0, 99),
            pendingDecisionCount: boundedInt(parsed.pendingDecisionCount, 0, 99),
            taskCount: boundedInt(parsed.taskCount, 0, 99),
            recentMediaCount: boundedInt(parsed.recentMediaCount, 0, 99),
            peopleNeedingResponse: stringArray(parsed.peopleNeedingResponse, 8),
            suggestedNextAction: typeof parsed.suggestedNextAction === "string" ? parsed.suggestedNextAction.slice(0, 180) : null,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: "system",
        };

        await ref.collection("pulse").doc("main").set(pulse, { merge: true });
        return pulse;
    }
);

function boundedInt(value: unknown, min: number, max: number): number {
    const numberValue = typeof value === "number" ? Math.round(value) : 0;
    return Math.max(min, Math.min(max, numberValue));
}
