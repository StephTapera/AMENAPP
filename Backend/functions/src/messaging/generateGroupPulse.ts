import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// generateGroupPulse
// Generates a GroupPulse snapshot for a group conversation.
// Returns: {activeTopic, openQuestions[], pendingDecisions[], suggestedNextAction}.

export const generateGroupPulse = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId } = request.data;

        if (!conversationId || typeof conversationId !== "string") {
            throw new HttpsError("invalid-argument", "conversationId is required.");
        }

        const db = admin.firestore();

        // Verify participation
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) throw new HttpsError("not-found", "Conversation not found.");
        const convData = convDoc.data() ?? {};
        const participants: string[] = convData.participants ?? [];
        if (!participants.includes(uid)) throw new HttpsError("permission-denied", "Not a participant.");
        if (!convData.isGroup) throw new HttpsError("invalid-argument", "Not a group conversation.");

        // Last 48 hours of messages
        const since = admin.firestore.Timestamp.fromMillis(Date.now() - 172800000);
        const msgsSnap = await db.collection("conversations").doc(conversationId)
            .collection("messages")
            .where("timestamp", ">=", since)
            .orderBy("timestamp", "asc")
            .limit(80)
            .get();

        if (msgsSnap.empty) {
            return { activeTopic: null, openQuestions: [], pendingDecisions: [], suggestedNextAction: null };
        }

        const messagesText = msgsSnap.docs
            .filter(d => !d.data().isDeleted)
            .map(d => {
                const d2 = d.data();
                return d2.text ? `${d2.senderName ?? "User"}: ${d2.text}` : null;
            })
            .filter(Boolean)
            .join("\n");

        const prompt = `Analyze this group conversation and return a pulse summary as JSON with: activeTopic (string or null — the main topic being discussed), openQuestions (array of strings, max 3 unanswered questions), pendingDecisions (array of strings, max 3 decisions not yet confirmed), suggestedNextAction (string or null — one concrete recommended action for the group). Be concise. Do not invent information.\n\nMessages:\n${messagesText}`;

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

        if (!response.ok) throw new HttpsError("internal", "Failed to generate group pulse.");

        const data = await response.json() as { content: { text: string }[] };
        const raw = data.content?.[0]?.text ?? "{}";

        try {
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};
            return {
                activeTopic: parsed.activeTopic ?? null,
                openQuestions: Array.isArray(parsed.openQuestions) ? parsed.openQuestions.slice(0, 3) : [],
                pendingDecisions: Array.isArray(parsed.pendingDecisions) ? parsed.pendingDecisions.slice(0, 3) : [],
                suggestedNextAction: parsed.suggestedNextAction ?? null,
            };
        } catch {
            return { activeTopic: null, openQuestions: [], pendingDecisions: [], suggestedNextAction: null };
        }
    }
);
