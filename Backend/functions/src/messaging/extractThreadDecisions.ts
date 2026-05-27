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

export const extractThreadDecisions = onCall(
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
        if (messages.length === 0) return { decisions: [] };

        const allowedIds = new Set(messages.map((message) => message.id));
        const prompt = [
            "Analyze this conversation and extract only genuine decisions.",
            "Return strict JSON: {\"decisions\":[{\"id\":\"string\",\"title\":\"string\",\"summary\":\"string\",\"sourceMessageIds\":[\"message-id\"],\"decidedByUid\":null,\"confirmedByUids\":[],\"status\":\"proposed|confirmed|reversed|outdated\",\"confidence\":0.0}]}",
            "Never invent owners, consensus, or confirmations. Use proposed unless evidence is explicit.",
            `Messages JSON: ${JSON.stringify(messages)}`,
        ].join("\n");

        const parsed = await callClaudeJson(anthropicApiKey.value(), prompt, 800);
        const decisions = Array.isArray(parsed.decisions) ? parsed.decisions.slice(0, 8).map((decision: Record<string, unknown>, index: number) => {
            const summary = String(decision.summary ?? "").slice(0, 500);
            const sources = sourceMessageIds(decision.sourceMessageIds, allowedIds, 10);
            const status = ["proposed", "confirmed", "reversed", "outdated"].includes(String(decision.status))
                ? String(decision.status)
                : "proposed";
            return {
                id: String(decision.id ?? `decision_${index}`),
                title: String(decision.title ?? "Potential decision").slice(0, 160),
                summary,
                sourceMessageIds: sources,
                decidedByUid: typeof decision.decidedByUid === "string" ? decision.decidedByUid : null,
                confirmedByUids: Array.isArray(decision.confirmedByUids) ? decision.confirmedByUids.filter((id): id is string => typeof id === "string") : [],
                status,
                confidence: typeof decision.confidence === "number" ? Math.max(0, Math.min(1, decision.confidence)) : 0.5,
                createdBy: "system",
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
        }).filter((decision) => decision.summary.length > 0 && decision.sourceMessageIds.length > 0) : [];

        const batch = admin.firestore().batch();
        decisions.forEach((decision) => {
            batch.set(ref.collection("decisions").doc(decision.id), decision, { merge: true });
        });
        batch.set(ref.collection("smartContext").doc("main"), {
            decisionCount: decisions.length,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdBy: "system",
        }, { merge: true });
        await batch.commit();

        return { decisions };
    }
);
