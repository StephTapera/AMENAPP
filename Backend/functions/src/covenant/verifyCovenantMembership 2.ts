// covenant/verifyCovenantMembership.ts
//
// Server-authoritative membership verification for the Covenant OS.
//
// Callable:
//   verifyCovenantMembership — checks that a covenantMembership doc exists,
//   belongs to the calling user, and has status "active".

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

export const verifyCovenantMembership = onCall(
    { region: "us-central1" },
    async (request): Promise<{ verified: boolean; membershipId: string }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
        const data = (request.data ?? {}) as { membershipId?: string };
        if (typeof data.membershipId !== "string" || !data.membershipId.trim()) {
            throw new HttpsError("invalid-argument", "membershipId is required.");
        }
        const db = getFirestore();
        const membershipSnap = await db.doc(`covenantMemberships/${data.membershipId.trim()}`).get();
        if (!membershipSnap.exists) {
            throw new HttpsError("not-found", "Membership not found.");
        }
        const membershipData = membershipSnap.data()!;
        if (membershipData.userId !== uid) {
            throw new HttpsError("permission-denied", "Membership does not belong to this user.");
        }
        if (membershipData.status !== "active") {
            throw new HttpsError("failed-precondition", "Membership is not active.");
        }
        return { verified: true, membershipId: data.membershipId.trim() };
    }
);
