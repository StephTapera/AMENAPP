import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// extractThreadActions
// Identifies follow-up actions, tasks, and commitments in a conversation thread.
// Returns array of {id, action, assignedTo, sourceSnippet, status: "suggested"}.
// Never invents assignees or deadlines not explicitly stated.

export const extractThreadActions = onCall(
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
        if (messages.length === 0) return { actions: [] };

        const db = admin.firestore();
        const convDoc = await db.collection("conversations").doc(conversationId).get();
        if (!convDoc.exists) throw new HttpsError("not-found", "Conversation not found.");
        const participants: string[] = convDoc.data()?.participants ?? [];
        if (!participants.includes(uid)) throw new HttpsError("permission-denied", "Not a participant.");

        const sanitized = messages
            .filter((m: unknown) => typeof m === "string")
            .slice(0, 40)
            .map((m: string) => m.slice(0, 300));

        const prompt = `Analyze these conversation messages and identify action items, follow-ups, or commitments. Return JSON with key "actions" — an array of objects with: id (unique string), action (the task, stated clearly), assignedTo (name ONLY if EXPLICITLY stated in message, else null — do NOT guess), sourceSnippet (short quote), status (always "suggested"). Never invent deadlines or assignees. Return empty array if none found.\n\nMessages:\n${sanitized.join("\n")}`;

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
            const actions = Array.isArray(parsed.actions) ? parsed.actions.slice(0, 5).map((a: Record<string, unknown>, i: number) => ({
                id: String(a.id ?? `act_${i}`),
                action: String(a.action ?? ""),
                assignedTo: a.assignedTo ? String(a.assignedTo) : null,
                sourceSnippet: a.sourceSnippet ? String(a.sourceSnippet).slice(0, 150) : undefined,
                status: "suggested",
            })).filter((a: { action: string }) => a.action.length > 0) : [];
            return { actions };
        } catch {
            return { actions: [] };
        }
    }
);
