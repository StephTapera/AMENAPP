// computeKingdomMetrics.ts
// AMEN — Creator Profiles: derive a creator's "Kingdom Metrics" dashboard.
//
// Privacy: aggregate-only, no per-user tracking (NSPrivacyTracking stays false).
// Every value is computed from aggregate counts/sums over the creator's own
// subcollections. There is NO per-viewer/per-user analytics anywhere in this path.
// retentionSignal / communityHealthSignal are bounded 0..1 heuristics over
// approved-vs-total ratios, not behavioral tracking.

import { onCall } from "firebase-functions/v2/https";
import {
    requireAuth,
    requireManage,
    subCol,
    SUB,
    COLL,
    reqString,
    nowISO,
    db,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import { CREATOR_HUB_FLAGS, CreatorHubMetrics } from "./creatorProfileTypes";

const SCAN_CAP = 1000; // aggregate scan bound per subcollection

function clamp01(n: number): number {
    if (!Number.isFinite(n)) return 0;
    if (n < 0) return 0;
    if (n > 1) return 1;
    return n;
}

function ratio(part: number, whole: number): number {
    if (whole <= 0) return 0;
    return clamp01(part / whole);
}

export const computeKingdomMetrics = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB" },
    async (request): Promise<CreatorHubMetrics> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.profilesEnabled);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        void uid;

        // Creator-facing dashboard — manage role required.
        await requireManage(request, creatorId);

        const [
            prayerSnap,
            teachingsSnap,
            resourcesSnap,
            coursesSnap,
            communitySnap,
        ] = await Promise.all([
            subCol(creatorId, SUB.prayerRequests).limit(SCAN_CAP).get(),
            subCol(creatorId, SUB.teachings).limit(SCAN_CAP).get(),
            subCol(creatorId, SUB.resources).limit(SCAN_CAP).get(),
            subCol(creatorId, SUB.courses).limit(SCAN_CAP).get(),
            subCol(creatorId, SUB.communityPosts).limit(SCAN_CAP).get(),
        ]);

        // ── Prayer aggregates (approved-only for public-facing counts) ──────────
        let prayersReceived = 0; // approved prayer requests
        let prayersPrayed = 0;   // sum of prayedCount across approved requests
        let answeredReports = 0; // approved requests carrying a praise report
        for (const doc of prayerSnap.docs) {
            const p = doc.data();
            if (p.status !== "approved") continue;
            prayersReceived += 1;
            const pc = Number(p.prayedCount);
            if (Number.isFinite(pc) && pc > 0) prayersPrayed += Math.floor(pc);
            if (typeof p.praiseReport === "string" && p.praiseReport.trim()) {
                answeredReports += 1;
            }
        }

        // ── Content aggregates ──────────────────────────────────────────────────
        const teachingCount = teachingsSnap.size;
        const resourceCount = resourcesSnap.size;
        const courseCount = coursesSnap.size;

        // Proxies (aggregate-only; no per-user download/session events exist yet):
        //   studySessions       → teachings + courses (study surfaces published)
        //   resourcesDownloaded → resources published (downloadable artifacts available)
        const studySessions = teachingCount + courseCount;
        const resourcesDownloaded = resourceCount;

        // ── Community aggregates ────────────────────────────────────────────────
        const communityTotal = communitySnap.size;
        let communityApproved = 0;
        for (const doc of communitySnap.docs) {
            if (doc.data().status === "approved") communityApproved += 1;
        }

        // ── Bounded 0..1 signals from approved-vs-total ratios ──────────────────
        const prayerApprovedRatio = ratio(prayersReceived, prayerSnap.size);
        const communityApprovedRatio = ratio(communityApproved, communityTotal);
        // retentionSignal: how much published study material backs the hub (saturates).
        const retentionSignal = clamp01((studySessions + resourcesDownloaded) / 50);
        // communityHealthSignal: blend of approved-prayer and approved-community ratios.
        const communityHealthSignal = clamp01((prayerApprovedRatio + communityApprovedRatio) / 2);

        const metrics: CreatorHubMetrics = {
            creatorId,
            peopleDiscipled: 0,          // no per-user tracking source — aggregate-only stays 0
            prayersReceived,
            prayersPrayed,
            answeredReports,
            plansCompleted: 0,           // no completion-event source yet
            notesCreated: 0,             // no notes source in hub subcollections
            studySessions,
            groupsLaunched: 0,           // no group source yet
            resourcesDownloaded,
            retentionSignal,
            communityHealthSignal,
        };

        // Server-write only: creatorHubMetrics/{creatorId}.
        await db()
            .collection(COLL.metrics)
            .doc(creatorId)
            .set({ ...metrics, updatedAt: nowISO() }, { merge: true });

        return metrics;
    }
);
