import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// generateDMCatchUp
// Produces a concise catch-up digest for a DM conversation.
// Reads the last N messages from conversations/{conversationId}/messages,
// verifies the caller is a participant, then calls Claude Haiku.

export const generateDMCatchUp = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId, since } = request.data;

        if (!conversationId || typeof conversationId !== "string") {
            throw new HttpsError("invalid-argument", "conversationId is required.");
        }

        const db = admin.firestore();

        // Verify participation
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) {
            throw new HttpsError("not-found", "Conversation not found.");
        }
        const convData = convDoc.data() ?? {};
        const participants: string[] = convData.participants ?? [];
        if (!participants.includes(uid)) {
            throw new HttpsError("permission-denied", "Not a participant in this conversation.");
        }

        const sinceTimestamp = admin.firestore.Timestamp.fromMillis(Number(since) || Date.now() - 86400000);
        const msgsSnap = await db.collection("conversations").doc(conversationId)
            .collection("messages")
            .where("timestamp", ">=", sinceTimestamp)
            .orderBy("timestamp", "asc")
            .limit(60)
            .get();

        if (msgsSnap.empty) {
            return {
                summary: "Nothing new since you were last active.",
                decisions: [],
                unansweredQuestions: [],
                suggestedActions: [],
            };
        }

        const messagesText = msgsSnap.docs
            .filter(d => !d.data().isDeleted)
            .map(d => {
                const data = d.data();
                const sender = data.senderName ?? "User";
                const text = data.text ?? "";
                return text.length > 0 ? `${sender}: ${text}` : null;
            })
            .filter(Boolean)
            .join("\n");

        if (!messagesText.trim()) {
            return { summary: "You're caught up.", decisions: [], unansweredQuestions: [], suggestedActions: [] };
        }

        const prompt = `You are a helpful assistant. Based on the following direct message conversation, provide a brief catch-up in JSON format with these exact keys: summary (string, 1-2 sentences), decisions (array of strings, max 3), unansweredQuestions (array of strings, max 3), suggestedActions (array of strings, max 3). Be concise. Do not invent owners or deadlines. Mark suggestions as suggestions.\n\nMessages:\n${messagesText}`;

        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "x-api-key": anthropicApiKey.value(),
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model: "claude-haiku-4-5-20251001",
                max_tokens: 400,
                messages: [{ role: "user", content: prompt }],
            }),
        });

        if (!response.ok) {
            throw new HttpsError("internal", "Failed to generate catch-up summary.");
        }

        const data = await response.json() as { content: { text: string }[] };
        const raw = data.content?.[0]?.text ?? "{}";

        try {
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};
            return {
                summary: parsed.summary ?? "Here's what happened while you were away.",
                decisions: Array.isArray(parsed.decisions) ? parsed.decisions.slice(0, 3) : [],
                unansweredQuestions: Array.isArray(parsed.unansweredQuestions) ? parsed.unansweredQuestions.slice(0, 3) : [],
                suggestedActions: Array.isArray(parsed.suggestedActions) ? parsed.suggestedActions.slice(0, 3) : [],
            };
        } catch {
            return { summary: raw.slice(0, 200), decisions: [], unansweredQuestions: [], suggestedActions: [] };
        }
    }
);
