// moderateCreatorContent.ts
// AMEN — Creator Profiles: the ONLY path that can change a UGC item's moderation status.
//
// SAFETY INVARIANT (MEDIA-GATE / moderation lifecycle):
//   Content is submitted as status="pending" and is never public on write. This
//   callable is the single seam that may transition an item to "approved" — and it
//   requires owner/moderator/admin (requireManage throws permission-denied otherwise).
//   No other write path can make pending content public.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
    requireAuth,
    requireManage,
    subCol,
    SUB,
    nowISO,
    reqString,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    CREATOR_HUB_FLAGS,
    CreatorHubModerationStatus,
} from "./creatorProfileTypes";

type ModerationTarget = "prayerRequest" | "communityPost";
type ModerationAction = "approve" | "reject" | "hide";

interface ModerateCreatorContentResult {
    ok: true;
    refId: string;
    status: CreatorHubModerationStatus;
}

const ACTION_TO_STATUS: Record<ModerationAction, CreatorHubModerationStatus> = {
    approve: "approved",
    reject: "rejected",
    hide: "hidden",
};

function reqTarget(data: unknown): ModerationTarget {
    const v = (data as { target?: unknown })?.target;
    if (v !== "prayerRequest" && v !== "communityPost") {
        throw new HttpsError("invalid-argument", "Missing or invalid 'target'.");
    }
    return v;
}

function reqAction(data: unknown): ModerationAction {
    const v = (data as { action?: unknown })?.action;
    if (v !== "approve" && v !== "reject" && v !== "hide") {
        throw new HttpsError("invalid-argument", "Missing or invalid 'action'.");
    }
    return v;
}

export const moderateCreatorContent = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<ModerateCreatorContentResult> => {
        const uid = requireAuth(request);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        const target = reqTarget(data);
        const refId = reqString(data, "refId");
        const action = reqAction(data);

        // Gate on the relevant feature flag for the target kind.
        await assertCreatorHubFlag(
            target === "prayerRequest"
                ? CREATOR_HUB_FLAGS.prayerBoardEnabled
                : CREATOR_HUB_FLAGS.communityEnabled
        );

        // ONLY owner/moderator/admin may moderate — throws permission-denied otherwise.
        await requireManage(request, creatorId);

        const status = ACTION_TO_STATUS[action];
        const moderatedAt = nowISO();

        const sub =
            target === "prayerRequest" ? SUB.prayerRequests : SUB.communityPosts;
        const targetRef = subCol(creatorId, sub).doc(refId);
        const queueRef = subCol(creatorId, SUB.moderationQueue).doc(refId);

        const snap = await targetRef.get();
        if (!snap.exists) {
            throw new HttpsError("not-found", "Target content not found.");
        }

        // Only the status + moderation audit fields change. We never override
        // isPrivate on approve — a prayer request stays private if the author asked.
        const moderationUpdate = {
            status,
            moderatedBy: uid,
            moderatedAt,
        };

        await targetRef.update(moderationUpdate);
        await queueRef.set(
            { status, moderatedBy: uid, moderatedAt },
            { merge: true }
        );

        return { ok: true, refId, status };
    }
);
