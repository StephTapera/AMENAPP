import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// extractThreadDecisions
// Identifies decisions reached in a conversation thread.
// Returns array of {id, summary, sourceSnippet, status} objects.
// Never fabricates decisions — only extracts from provided messages.

export const extractThreadDecisions = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { conversationId, messages } = request.data;

        if (!conversationId || !Array.isArray(messages)) {
            throw new HttpsError("invalid-argument", "conversationId and messages[] are required.");
        }
        if (messages.length === 0) return { decisions: [] };

        // Verify participation
        const db = admin.firestore();
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) throw new HttpsError("not-found", "Conversation not found.");
        const participants: string[] = convDoc.data()?.participants ?? [];
        if (!participants.includes(uid)) throw new HttpsError("permission-denied", "Not a participant.");

        // Sanitize input — only strings, max 40 messages, max 300 chars each
        const sanitized = messages
            .filter((m: unknown) => typeof m === "string")
            .slice(0, 40)
            .map((m: string) => m.slice(0, 300));

        const prompt = `Analyze these conversation messages and identify any decisions that were made or agreed upon. Return JSON with key "decisions" — an array of objects with: id (unique string), summary (the decision, stated neutrally), sourceSnippet (short quote from message that shows the decision), status ("proposed" or "confirmed"). Only include genuine decisions, not opinions. If unsure, use status "proposed". Return empty array if none found.\n\nMessages:\n${sanitized.join("\n")}`;

        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "x-api-key": anthropicApiKey.value(),
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model: "claude-haiku-4-5-20251001",
                max_tokens: 512,
                messages: [{ role: "user", content: prompt }],
            }),
        });

        if (!response.ok) throw new HttpsError("internal", "AI extraction failed.");

        const data = await response.json() as { content: { text: string }[] };
        const raw = data.content?.[0]?.text ?? "{}";

        try {
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};
            const decisions = Array.isArray(parsed.decisions) ? parsed.decisions.slice(0, 5).map((d: Record<string, unknown>, i: number) => ({
                id: String(d.id ?? `dec_${i}`),
                summary: String(d.summary ?? ""),
                sourceSnippet: d.sourceSnippet ? String(d.sourceSnippet).slice(0, 150) : undefined,
                status: ["proposed", "confirmed"].includes(String(d.status)) ? String(d.status) : "proposed",
            })).filter((d: { summary: string }) => d.summary.length > 0) : [];
            return { decisions };
        } catch {
            return { decisions: [] };
        }
    }
);
