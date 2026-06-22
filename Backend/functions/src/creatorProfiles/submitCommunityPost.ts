// submitCommunityPost.ts
// AMEN — Creator Profiles: submit a community post to a creator hub's moderated community.
//
// SAFETY INVARIANT (MEDIA-GATE / moderation lifecycle):
//   UGC is created with status="pending" and is NEVER public on write. Only an
//   owner/moderator/admin moderation action (moderateCreatorContent) may set
//   status="approved". This function FORCES status="pending" server-side and
//   ignores any client-supplied status. A pending post is never servable.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
    requireAuth,
    subCol,
    SUB,
    nowISO,
    reqString,
    optString,
    db,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    CREATOR_HUB_FLAGS,
    CreatorHubCommunityPost,
    CreatorHubCommunityKind,
    CreatorHubModerationStatus,
} from "./creatorProfileTypes";

interface SubmitCommunityPostResult {
    ok: true;
    id: string;
    status: CreatorHubModerationStatus;
}

const COMMUNITY_KINDS: readonly CreatorHubCommunityKind[] = [
    "question",
    "testimony",
    "studyNote",
    "eventDiscussion",
];

function reqCommunityKind(data: unknown): CreatorHubCommunityKind {
    const v = (data as { kind?: unknown })?.kind;
    if (typeof v !== "string" || !COMMUNITY_KINDS.includes(v as CreatorHubCommunityKind)) {
        throw new HttpsError("invalid-argument", "Missing or invalid 'kind'.");
    }
    return v as CreatorHubCommunityKind;
}

export const submitCommunityPost = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<SubmitCommunityPostResult> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.communityEnabled);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        const kind = reqCommunityKind(data);
        const body = reqString(data, "body");
        const parentRef = optString(data, "parentRef");

        const postRef = subCol(creatorId, SUB.communityPosts).doc();
        const id = postRef.id;
        const createdAt = nowISO();

        // Server FORCES the moderation lifecycle — never public on write.
        const post: CreatorHubCommunityPost = {
            id,
            creatorId,
            authorId: uid,
            kind,
            body,
            status: "pending",
            ...(parentRef ? { parentRef } : {}),
        };

        const queueRef = subCol(creatorId, SUB.moderationQueue).doc(id);
        const queueDoc = {
            id,
            kind: "communityPost" as const,
            refId: id,
            authorId: uid,
            createdAt,
            status: "pending" as CreatorHubModerationStatus,
        };

        const batch = db().batch();
        batch.set(postRef, { ...post, createdAt });
        batch.set(queueRef, queueDoc);
        await batch.commit();

        return { ok: true, id, status: "pending" };
    }
);
