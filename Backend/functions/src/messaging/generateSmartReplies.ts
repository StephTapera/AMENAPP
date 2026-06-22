import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// generateSmartReplies
// Generates 3 contextually appropriate short reply suggestions for a conversation.
// Replies are grounded in conversation context and consistent with the app's
// Christian community values. Never generates harmful or manipulative content.

export const generateSmartReplies = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId, lastMessageText, context } = request.data;

        if (!conversationId || typeof conversationId !== "string") {
            throw new HttpsError("invalid-argument", "conversationId is required.");
        }
        if (!lastMessageText || typeof lastMessageText !== "string") {
            throw new HttpsError("invalid-argument", "lastMessageText is required.");
        }

        const db = admin.firestore();
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) throw new HttpsError("not-found", "Conversation not found.");
        const participants: string[] = convDoc.data()?.participants ?? [];
        if (!participants.includes(uid)) throw new HttpsError("permission-denied", "Not a participant.");

        const sanitizedLast = lastMessageText.slice(0, 500);
        const sanitizedContext = Array.isArray(context)
            ? context.filter((m: unknown) => typeof m === "string").slice(0, 5).map((m: string) => m.slice(0, 200)).join("\n")
            : "";

        const prompt = `Generate exactly 3 short, natural reply suggestions for this message in a Christian community app. Replies should be warm, genuine, and appropriate. Return JSON with key "replies" — an array of 3 strings, each 5-25 words. Do not be preachy or overly formal.\n\nConversation context:\n${sanitizedContext}\n\nLatest message to reply to: "${sanitizedLast}"`;

        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "x-api-key": anthropicApiKey.value(),
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model: "claude-haiku-4-5-20251001",
                max_tokens: 200,
                messages: [{ role: "user", content: prompt }],
            }),
        });

        if (!response.ok) throw new HttpsError("internal", "Failed to generate replies.");

        const data = await response.json() as { content: { text: string }[] };
        const raw = data.content?.[0]?.text ?? "{}";

        try {
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};
            const replies = Array.isArray(parsed.replies)
                ? parsed.replies.slice(0, 3).map((r: unknown) => String(r).slice(0, 200)).filter((r: string) => r.length > 0)
                : [];
            return { replies };
        } catch {
            return { replies: [] };
        }
    }
);
