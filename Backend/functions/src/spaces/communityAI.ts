// spaces/communityAI.ts
//
// Community AI intelligence callables for AMEN Spaces.
//
// Callables:
//   getCommunityAIDigest      — aggregated digest of space activity since last visit
//   getMemberInsights         — members needing attention (high attendance, no intro)
//   markMemberFollowedUp      — records follow-up action on a member
//   dismissCommunityInsight   — dismisses a community insight card
//   getSpaceHealthMetrics     — aggregated health/vitality stats for a space

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

// ── Interfaces ────────────────────────────────────────────────────────────────

interface GetCommunityAIDigestInput {
    spaceId: string;
}

interface GetMemberInsightsInput {
    spaceId: string;
}

interface MarkMemberFollowedUpInput {
    spaceId: string;
    userId: string;
}

interface DismissCommunityInsightInput {
    spaceId: string;
    insightId: string;
}

interface GetSpaceHealthMetricsInput {
    spaceId: string;
}

interface CommunityAIDigest {
    totalNewMessages: number;
    activeTopics: string[];
    unansweredQuestions: number;
    prayerRequestsNeedingAttention: number;
}

interface MemberInsightRecord {
    id: string;
    userId: string;
    displayName: string;
    reason: string;
    recommendedAction: "welcome" | "followUp" | "checkIn" | "recognizeLeadership";
}

interface SpaceHealthMetrics {
    retentionRate: number;
    avgEventAttendance: number;
    prayerEngagementRate: number;
    avgRepliesPerThread: number;
    mentorshipCompletions: number;
    vitalityScore: number;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function validateSpaceId(spaceId: unknown): string {
    if (typeof spaceId !== "string" || !spaceId.trim()) {
        throw new HttpsError("invalid-argument", "spaceId is required.");
    }
    return spaceId.trim();
}

// ── getCommunityAIDigest ──────────────────────────────────────────────────────

export const getCommunityAIDigest = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<CommunityAIDigest> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { spaceId: rawSpaceId } = (request.data ?? {}) as Partial<GetCommunityAIDigestInput>;
        const spaceId = validateSpaceId(rawSpaceId);

        const db = getFirestore();

        // Fetch user's last visit timestamp from member doc
        const memberRef = db.doc(`spaces/${spaceId}/members/${uid}`);
        const memberSnap = await memberRef.get();
        const lastVisit: Timestamp | null = (memberSnap.data()?.lastVisit as Timestamp) ?? null;

        // Fetch last 100 messages ordered by createdAt desc
        let messagesQuery = db
            .collection(`spaces/${spaceId}/messages`)
            .orderBy("createdAt", "desc")
            .limit(100);
        const messagesSnap = await messagesQuery.get();

        // Count messages since user's last visit
        let totalNewMessages = 0;
        if (lastVisit) {
            for (const doc of messagesSnap.docs) {
                const createdAt = doc.data().createdAt as Timestamp | undefined;
                if (createdAt && createdAt.toMillis() > lastVisit.toMillis()) {
                    totalNewMessages++;
                }
            }
        } else {
            totalNewMessages = messagesSnap.size;
        }

        // Unanswered prayer requests
        const prayerSnap = await db
            .collection(`spaces/${spaceId}/prayerRequests`)
            .where("respondedAt", "==", null)
            .get();

        // Unanswered discussions
        const discussionsSnap = await db
            .collection(`spaces/${spaceId}/discussions`)
            .where("answeredAt", "==", null)
            .get();

        return {
            totalNewMessages,
            activeTopics: ["Faith", "Prayer", "Community", "Scripture"],
            unansweredQuestions: discussionsSnap.size,
            prayerRequestsNeedingAttention: prayerSnap.size,
        };
    }
);

// ── getMemberInsights ─────────────────────────────────────────────────────────

export const getMemberInsights = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<MemberInsightRecord[]> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { spaceId: rawSpaceId } = (request.data ?? {}) as Partial<GetMemberInsightsInput>;
        const spaceId = validateSpaceId(rawSpaceId);

        const db = getFirestore();

        const activitySnap = await db
            .collection(`spaces/${spaceId}/memberActivity`)
            .where("eventAttendance", ">", 10)
            .where("hasIntroduced", "==", false)
            .get();

        const insights: MemberInsightRecord[] = activitySnap.docs.map((doc) => {
            const data = doc.data();
            const attendance = (data.eventAttendance as number) ?? 0;
            let recommendedAction: MemberInsightRecord["recommendedAction"] = "welcome";
            if (attendance > 30) {
                recommendedAction = "recognizeLeadership";
            } else if (attendance > 20) {
                recommendedAction = "followUp";
            } else if (attendance > 15) {
                recommendedAction = "checkIn";
            }
            return {
                id: doc.id,
                userId: (data.userId as string) ?? doc.id,
                displayName: (data.displayName as string) ?? "Member",
                reason: `Attended ${attendance} events but has not introduced themselves to the community.`,
                recommendedAction,
            };
        });

        return insights;
    }
);

// ── markMemberFollowedUp ──────────────────────────────────────────────────────

export const markMemberFollowedUp = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { spaceId: rawSpaceId, userId } =
            (request.data ?? {}) as Partial<MarkMemberFollowedUpInput>;
        const spaceId = validateSpaceId(rawSpaceId);

        if (typeof userId !== "string" || !userId.trim()) {
            throw new HttpsError("invalid-argument", "userId is required.");
        }

        const db = getFirestore();

        await db.doc(`spaces/${spaceId}/memberActivity/${userId.trim()}`).update({
            followedUpAt: Timestamp.now(),
        });

        return { success: true };
    }
);

// ── dismissCommunityInsight ───────────────────────────────────────────────────

export const dismissCommunityInsight = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<{ success: true }> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { spaceId: rawSpaceId, insightId } =
            (request.data ?? {}) as Partial<DismissCommunityInsightInput>;
        const spaceId = validateSpaceId(rawSpaceId);

        if (typeof insightId !== "string" || !insightId.trim()) {
            throw new HttpsError("invalid-argument", "insightId is required.");
        }

        const db = getFirestore();

        await db.doc(`spaces/${spaceId}/memberInsights/${insightId.trim()}`).update({
            dismissedAt: Timestamp.now(),
        });

        return { success: true };
    }
);

// ── getSpaceHealthMetrics ─────────────────────────────────────────────────────

export const getSpaceHealthMetrics = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<SpaceHealthMetrics> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const { spaceId: rawSpaceId } =
            (request.data ?? {}) as Partial<GetSpaceHealthMetricsInput>;
        const spaceId = validateSpaceId(rawSpaceId);

        const db = getFirestore();

        const healthSnap = await db.doc(`spaces/${spaceId}/analytics/health`).get();

        if (!healthSnap.exists) {
            return {
                retentionRate: 0,
                avgEventAttendance: 0,
                prayerEngagementRate: 0,
                avgRepliesPerThread: 0,
                mentorshipCompletions: 0,
                vitalityScore: 0,
            };
        }

        const data = healthSnap.data()!;
        return {
            retentionRate: (data.retentionRate as number) ?? 0,
            avgEventAttendance: (data.avgEventAttendance as number) ?? 0,
            prayerEngagementRate: (data.prayerEngagementRate as number) ?? 0,
            avgRepliesPerThread: (data.avgRepliesPerThread as number) ?? 0,
            mentorshipCompletions: (data.mentorshipCompletions as number) ?? 0,
            vitalityScore: (data.vitalityScore as number) ?? 0,
        };
    }
);
