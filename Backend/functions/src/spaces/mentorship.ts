// spaces/mentorship.ts
// Mentor matching + mentorship request callables for AMEN Spaces.
//
// Callables:
//   findMentorMatches   — AI-powered match suggestions from space mentors
//   requestMentorship   — sends a mentorship request to a matched mentor

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

interface FindMentorMatchesInput {
    spaceId: string;
    interests: string[];
    mentorType: string;
    availability: string;
}

interface RequestMentorshipInput {
    spaceId: string;
    mentorUserId: string;
    message: string;
}

interface MentorMatchResult {
    id: string;
    userId: string;
    displayName: string;
    sharedInterests: string[];
    matchScore: number;
    availabilityNote: string;
}

export const findMentorMatches = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<MentorMatchResult[]> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const input = request.data as FindMentorMatchesInput;
        if (!input.spaceId) throw new HttpsError("invalid-argument", "spaceId required.");

        const db = getFirestore();

        // Fetch members who have opted in as mentors
        const membersSnap = await db
            .collection(`spaces/${input.spaceId}/members`)
            .where("isMentor", "==", true)
            .limit(20)
            .get();

        const matches: MentorMatchResult[] = membersSnap.docs
            .filter(doc => doc.id !== uid)
            .map(doc => {
                const data = doc.data();
                const mentorInterests: string[] = data.interests ?? [];
                const shared = mentorInterests.filter(i => input.interests.includes(i));
                const score = mentorInterests.length > 0
                    ? Math.min(1.0, shared.length / Math.max(input.interests.length, 1))
                    : 0.5;
                return {
                    id: doc.id,
                    userId: doc.id,
                    displayName: data.displayName ?? "Community Member",
                    sharedInterests: shared.slice(0, 4),
                    matchScore: Math.max(0.35, score),
                    availabilityNote: data.availabilityNote ?? input.availability,
                };
            })
            .sort((a, b) => b.matchScore - a.matchScore)
            .slice(0, 5);

        return matches;
    }
);

export const requestMentorship = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<{ success: boolean }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const input = request.data as RequestMentorshipInput;
        if (!input.spaceId || !input.mentorUserId) {
            throw new HttpsError("invalid-argument", "spaceId and mentorUserId required.");
        }
        if (input.mentorUserId === uid) {
            throw new HttpsError("invalid-argument", "Cannot request mentorship from yourself.");
        }

        const db = getFirestore();
        await db.collection(`spaces/${input.spaceId}/mentorshipRequests`).add({
            fromUserId: uid,
            toUserId: input.mentorUserId,
            message: (input.message ?? "").slice(0, 500),
            status: "pending",
            createdAt: Timestamp.now(),
        });

        return { success: true };
    }
);
