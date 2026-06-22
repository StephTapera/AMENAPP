// prayer/generatePrayerRecap.ts
//
// Generates a weekly prayer recap summary for the calling user.
//
// Callable:
//   generatePrayerRecap — fetches the user's last 7 days of prayer requests,
//   produces a short encouragement summary, and persists it to
//   users/{uid}/prayerRecaps/{recapId}.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

export const generatePrayerRecap = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<{ recapId: string; summary: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
        const db = getFirestore();
        // Fetch user's recent prayers (last 7 days)
        const cutoff = Timestamp.fromMillis(Date.now() - 7 * 24 * 3600 * 1000);
        const prayersSnap = await db.collection("prayerRequests")
            .where("uid", "==", uid)
            .where("createdAt", ">=", cutoff)
            .orderBy("createdAt", "desc")
            .limit(20)
            .get();
        const prayers = prayersSnap.docs.map(d => d.data().content as string).filter(Boolean);
        const summary = prayers.length > 0
            ? `You prayed about ${prayers.length} thing${prayers.length > 1 ? "s" : ""} this week. Keep seeking God faithfully.`
            : "Start your prayer journey — share what's on your heart.";
        const recapRef = await db.collection(`users/${uid}/prayerRecaps`).add({
            summary,
            prayerCount: prayers.length,
            generatedAt: Timestamp.now(),
        });
        return { recapId: recapRef.id, summary };
    }
);
