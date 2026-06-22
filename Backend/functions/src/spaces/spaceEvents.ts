// spaces/spaceEvents.ts
//
// Space event RSVP callable for AMEN Spaces.
//
// Callable:
//   rsvpToSpaceEvent — RSVP to (or cancel RSVP for) a space event

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

export const rsvpToSpaceEvent = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
        const data = (request.data ?? {}) as { eventId?: string; rsvp?: boolean };
        if (typeof data.eventId !== "string" || !data.eventId.trim()) {
            throw new HttpsError("invalid-argument", "eventId is required.");
        }
        const db = getFirestore();
        const rsvpRef = db.doc(`spaceEvents/${data.eventId.trim()}/rsvps/${uid}`);
        // `userId` mirrors the doc id so the account-deletion cascade
        // (collectionGroup("rsvps").where("userId","==",uid)) hard-deletes these on
        // account removal. `status` lets readers distinguish active vs cancelled RSVPs.
        if (data.rsvp === false) {
            // Soft-cancel: preserve the RSVP record for organizer/audit history
            // rather than hard-deleting. Account deletion still purges it via cascade.
            await rsvpRef.set(
                { uid, userId: uid, status: "cancelled", cancelledAt: Timestamp.now() },
                { merge: true }
            );
        } else {
            await rsvpRef.set({ uid, userId: uid, status: "going", rsvpedAt: Timestamp.now() });
        }
        return { success: true };
    }
);
