import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// generateThreadSummary
// Reads last N replies from a thread and calls Claude to produce a concise summary.
// Result written to parent message.aiThreadSummary and returned to caller.

export const generateThreadSummary = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }

        const { covenantId, roomId, messageId } = request.data;
        if (!covenantId || !roomId || !messageId) {
            throw new HttpsError("invalid-argument", "covenantId, roomId, and messageId are required.");
        }

        const db = admin.firestore();

        // Fetch up to 50 replies
        const repliesSnap = await db.collection("covenants").doc(covenantId)
            .collection("rooms").doc(roomId)
            .collection("messages").doc(messageId)
            .collection("replies")
            .orderBy("createdAt", "asc")
            .limit(50)
            .get();

        if (repliesSnap.empty) return { summary: "No replies yet." };

        const text = repliesSnap.docs
            .map(d => d.data().body as string)
            .filter(Boolean)
            .join("\n");

        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "x-api-key": anthropicApiKey.value(),
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model: "claude-haiku-4-5-20251001",
                max_tokens: 256,
                messages: [
                    {
                        role: "user",
                        content: `Summarize this Christian community thread in 2-3 sentences. Focus on key discussion points, questions raised, and any consensus reached. Be concise and neutral.\n\n---\n${text}`,
                    },
                ],
            }),
        });

        if (!response.ok) {
            throw new HttpsError("internal", "Failed to generate thread summary.");
        }

        const data = await response.json() as { content: { text: string }[] };
        const summary = data.content?.[0]?.text ?? "Unable to generate summary.";

        // Write back to parent message
        await db.collection("covenants").doc(covenantId)
            .collection("rooms").doc(roomId)
            .collection("messages").doc(messageId)
            .update({ aiThreadSummary: summary });

        return { summary };
    }
);
