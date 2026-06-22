import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// searchConversationMemory
// Natural-language search over conversation history.
// Does a semantic pass using Claude to rank and extract relevant snippets.

export const searchConversationMemory = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId, query } = request.data;

        if (!conversationId || typeof conversationId !== "string") {
            throw new HttpsError("invalid-argument", "conversationId is required.");
        }
        if (!query || typeof query !== "string" || query.trim().length === 0) {
            throw new HttpsError("invalid-argument", "query is required.");
        }
        if (query.length > 500) {
            throw new HttpsError("invalid-argument", "query too long.");
        }

        const db = admin.firestore();
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) throw new HttpsError("not-found", "Conversation not found.");
        const participants: string[] = convDoc.data()?.participants ?? [];
        if (!participants.includes(uid)) throw new HttpsError("permission-denied", "Not a participant.");

        // Fetch recent messages (last 200)
        const msgsSnap = await db.collection("conversations").doc(conversationId)
            .collection("messages")
            .orderBy("timestamp", "desc")
            .limit(200)
            .get();

        if (msgsSnap.empty) return { results: [] };

        const messages = msgsSnap.docs
            .filter(d => !d.data().isDeleted && d.data().text)
            .map(d => ({
                id: d.id,
                text: String(d.data().text ?? "").slice(0, 400),
                sender: String(d.data().senderName ?? "User"),
                timestamp: d.data().timestamp?.toDate()?.toISOString() ?? null,
                type: d.data().type ?? "text",
            }));

        // Ask Claude to find relevant snippets
        const prompt = `Given this conversation history and the search query, return JSON with key "results" — an array of matching message objects with: id (from input), snippet (relevant text, max 200 chars), type (message/decision/question/action). Only return messages that genuinely answer or relate to the query. Max 8 results.\n\nQuery: "${query.trim()}"\n\nMessages (JSON):\n${JSON.stringify(messages.slice(0, 80))}`;

        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "x-api-key": anthropicApiKey.value(),
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model: "claude-haiku-4-5-20251001",
                max_tokens: 600,
                messages: [{ role: "user", content: prompt }],
            }),
        });

        if (!response.ok) throw new HttpsError("internal", "Search failed.");

        const data = await response.json() as { content: { text: string }[] };
        const raw = data.content?.[0]?.text ?? "{}";

        try {
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};
            const results = Array.isArray(parsed.results) ? parsed.results.slice(0, 8).map((r: Record<string, unknown>) => {
                const original = messages.find(m => m.id === r.id);
                return {
                    id: String(r.id ?? ""),
                    snippet: String(r.snippet ?? "").slice(0, 200),
                    type: String(r.type ?? "message"),
                    messageId: String(r.id ?? ""),
                    timestamp: original?.timestamp ?? null,
                };
            }).filter((r: { snippet: string }) => r.snippet.length > 0) : [];
            return { results };
        } catch {
            return { results: [] };
        }
    }
);
