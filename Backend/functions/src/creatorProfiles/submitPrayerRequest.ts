// submitPrayerRequest.ts
// AMEN — Creator Profiles: submit a prayer request to a creator hub's moderated prayer board.
//
// SAFETY INVARIANT (MEDIA-GATE / moderation lifecycle):
//   UGC is created with status="pending" and is NEVER public on write. Only an
//   owner/moderator/admin moderation action (moderateCreatorContent) may set
//   status="approved". This function FORCES status="pending" server-side and
//   ignores any client-supplied status. A pending request is never servable.

import { onCall } from "firebase-functions/v2/https";
import {
    requireAuth,
    subCol,
    SUB,
    nowISO,
    reqString,
    db,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    CREATOR_HUB_FLAGS,
    CreatorHubPrayerRequest,
    CreatorHubModerationStatus,
} from "./creatorProfileTypes";

interface SubmitPrayerRequestResult {
    ok: true;
    id: string;
    status: CreatorHubModerationStatus;
}

export const submitPrayerRequest = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<SubmitPrayerRequestResult> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.prayerBoardEnabled);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        const body = reqString(data, "body");
        const isPrivate = data?.isPrivate === true;

        const prayerRef = subCol(creatorId, SUB.prayerRequests).doc();
        const id = prayerRef.id;
        const createdAt = nowISO();

        // Server FORCES the moderation lifecycle — never public on write.
        const prayer: CreatorHubPrayerRequest = {
            id,
            creatorId,
            authorId: uid,
            body,
            isPrivate,
            status: "pending",
            prayedCount: 0,
        };

        const queueRef = subCol(creatorId, SUB.moderationQueue).doc(id);
        const queueDoc = {
            id,
            kind: "prayerRequest" as const,
            refId: id,
            authorId: uid,
            createdAt,
            status: "pending" as CreatorHubModerationStatus,
        };

        const batch = db().batch();
        batch.set(prayerRef, { ...prayer, createdAt });
        batch.set(queueRef, queueDoc);
        await batch.commit();

        return { ok: true, id, status: "pending" };
    }
);
