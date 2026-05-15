import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// generateCatchUpSummary
// Available from Covenant Home, Room Detail, Thread Drawer, Creator Hub, Digest.
// Reads messages/activities since a given timestamp and produces a structured summary.

export const generateCatchUpSummary = onCall(
    { enforceAppCheck: true, region: "us-central1", secrets: ["ANTHROPIC_API_KEY"] },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { covenantId, roomId, since } = request.data;

        if (!covenantId || !since) {
            throw new HttpsError("invalid-argument", "covenantId and since are required.");
        }

        const db = admin.firestore();

        // Verify membership
        const memberSnap = await db.collection("covenantMemberships")
            .where("covenantId", "==", covenantId)
            .where("userId", "==", uid)
            .where("status", "in", ["active", "trialing"])
            .limit(1).get();
        if (memberSnap.empty) {
            throw new HttpsError("permission-denied", "Not a member of this community.");
        }

        const sinceTimestamp = admin.firestore.Timestamp.fromMillis(Number(since));
        let messagesText = "";

        if (roomId) {
            const msgsSnap = await db.collection("covenants").doc(covenantId)
                .collection("rooms").doc(roomId)
                .collection("messages")
                .where("createdAt", ">=", sinceTimestamp)
                .orderBy("createdAt", "asc")
                .limit(80)
                .get();
            messagesText = msgsSnap.docs
                .map(d => `${d.data().authorDisplayName}: ${d.data().body}`)
                .join("\n");
        } else {
            // Covenant-wide: pull digest from activity events
            const activitySnap = await db.collection("users").doc(uid)
                .collection("covenantActivity")
                .where("covenantId", "==", covenantId)
                .where("createdAt", ">=", sinceTimestamp)
                .orderBy("createdAt", "desc")
                .limit(40)
                .get();
            messagesText = activitySnap.docs
                .map(d => `[${d.data().type}] ${d.data().title}: ${d.data().body}`)
                .join("\n");
        }

        if (!messagesText.trim()) {
            return {
                summary: "Nothing new since you were last active.",
                decisions: [],
                prayerUpdates: [],
                unansweredQuestions: [],
                upcomingEvents: [],
                suggestedActions: [],
            };
        }

        const prompt = `You are a helpful assistant for a Christian community app. Based on the following community messages/activity, provide a brief structured catch-up summary in JSON format with these exact keys: summary (string, 1-2 sentences), decisions (array of strings), prayerUpdates (array of strings), unansweredQuestions (array of strings), upcomingEvents (array of strings), suggestedActions (array of strings). Keep each array to at most 3 items. Be concise and encouraging.\n\nMessages:\n${messagesText}`;

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

        if (!response.ok) {
            throw new HttpsError("internal", "Failed to generate catch-up summary.");
        }

        const data = await response.json() as { content: { text: string }[] };
        const raw = data.content?.[0]?.text ?? "{}";

        try {
            // Extract JSON from possible markdown code block
            const jsonMatch = raw.match(/\{[\s\S]*\}/);
            const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};
            return {
                summary: parsed.summary ?? "Here's what happened while you were away.",
                decisions: Array.isArray(parsed.decisions) ? parsed.decisions : [],
                prayerUpdates: Array.isArray(parsed.prayerUpdates) ? parsed.prayerUpdates : [],
                unansweredQuestions: Array.isArray(parsed.unansweredQuestions) ? parsed.unansweredQuestions : [],
                upcomingEvents: Array.isArray(parsed.upcomingEvents) ? parsed.upcomingEvents : [],
                suggestedActions: Array.isArray(parsed.suggestedActions) ? parsed.suggestedActions : [],
            };
        } catch {
            return { summary: raw.slice(0, 200), decisions: [], prayerUpdates: [], unansweredQuestions: [], upcomingEvents: [], suggestedActions: [] };
        }
    }
);
