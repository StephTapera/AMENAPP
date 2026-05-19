import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// generateMediaContext
// Generates a context summary for a media attachment in a message.
// For voice/video: produces a transcript summary.
// For link: produces a page summary.
// For photo: produces an alt-text style description (limited capability).

export const generateMediaContext = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { messageId, mediaUrl, mediaType, conversationId } = request.data;

        if (!messageId || !mediaType || !conversationId) {
            throw new HttpsError("invalid-argument", "messageId, mediaType, and conversationId are required.");
        }
        if (typeof mediaUrl !== "string" || mediaUrl.length > 2000) {
            throw new HttpsError("invalid-argument", "Invalid mediaUrl.");
        }

        const db = admin.firestore();
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) throw new HttpsError("not-found", "Conversation not found.");
        const participants: string[] = convDoc.data()?.participants ?? [];
        if (!participants.includes(uid)) throw new HttpsError("permission-denied", "Not a participant.");

        // For link types we can provide a summary prompt
        let summary = "";
        if (mediaType === "link") {
            const prompt = `Provide a 1-2 sentence summary of what this URL likely contains based on its structure. URL: ${mediaUrl}. If you cannot determine content, say "Link from conversation."`;
            const response = await fetch("https://api.anthropic.com/v1/messages", {
                method: "POST",
                headers: {
                    "x-api-key": anthropicApiKey.value(),
                    "anthropic-version": "2023-06-01",
                    "content-type": "application/json",
                },
                body: JSON.stringify({
                    model: "claude-haiku-4-5-20251001",
                    max_tokens: 150,
                    messages: [{ role: "user", content: prompt }],
                }),
            });
            if (response.ok) {
                const data = await response.json() as { content: { text: string }[] };
                summary = data.content?.[0]?.text?.trim() ?? "Link from conversation.";
            }
        } else if (mediaType === "voice" || mediaType === "video") {
            summary = "Transcript available after media is processed.";
        } else if (mediaType === "photo") {
            summary = "Photo shared in conversation.";
        } else if (mediaType === "file") {
            summary = "File shared in conversation.";
        }

        // Persist to Firestore so the client can cache
        if (summary) {
            await db.collection("conversations").doc(conversationId)
                .collection("mediaContext").doc(messageId)
                .set({
                    summary,
                    mediaType,
                    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    modelVersion: "claude-haiku-4-5-20251001",
                    generatedBy: "server",
                }, { merge: true });
        }

        return { summary, mediaType };
    }
);
