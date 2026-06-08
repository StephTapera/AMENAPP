// spaces/spaceEvents.ts
//
// Space event RSVP callable for AMEN Spaces.
//
// Callable:
//   rsvpToSpaceEvent — RSVP to (or cancel RSVP for) a space event

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

export const rsvpToSpaceEvent = onCall(
    { region: "us-central1" },
    async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
        const data = (request.data ?? {}) as { eventId?: string; rsvp?: boolean };
        if (typeof data.eventId !== "string" || !data.eventId.trim()) {
            throw new HttpsError("invalid-argument", "eventId is required.");
        }
        const db = getFirestore();
        const rsvpRef = db.doc(`spaceEvents/${data.eventId.trim()}/rsvps/${uid}`);
        if (data.rsvp === false) {
            await rsvpRef.delete();
        } else {
            await rsvpRef.set({ uid, rsvpedAt: Timestamp.now() });
        }
        return { success: true };
    }
);
