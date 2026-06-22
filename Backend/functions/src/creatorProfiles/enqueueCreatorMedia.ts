// enqueueCreatorMedia.ts
// AMEN — Creator Profiles: fail-closed MEDIA-GATE entry point for creator media.
//
// MEDIA-GATE INVARIANT (fail-closed): every uploaded object enters QUARANTINED and is
// NEVER servable until the gate clears it. This function only records the object; it
// does not approve, transcode, or expose anything. Storage rules deny serve while the
// object's moderation status is "quarantined".

import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
    requireAuth,
    requireManage,
    hubRef,
    nowISO,
    reqString,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";
import {
    CREATOR_HUB_FLAGS,
    CreatorHubMediaRef,
    CreatorHubModerationStatus,
} from "./creatorProfileTypes";

type CreatorMediaKind = CreatorHubMediaRef["kind"]; // "image" | "video" | "audio"

const ALLOWED_KINDS: ReadonlySet<CreatorMediaKind> = new Set(["image", "video", "audio"]);

interface EnqueueCreatorMediaResult {
    ok: true;
    mediaId: string;
    moderation: CreatorHubModerationStatus;
}

export const enqueueCreatorMedia = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB" },
    async (request): Promise<EnqueueCreatorMediaResult> => {
        const uid = requireAuth(request);
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.profilesEnabled);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        const storagePath = reqString(data, "storagePath");
        const kindRaw = reqString(data, "kind");

        if (!ALLOWED_KINDS.has(kindRaw as CreatorMediaKind)) {
            throw new HttpsError("invalid-argument", "Invalid 'kind'. Expected image|video|audio.");
        }
        const kind = kindRaw as CreatorMediaKind;

        const aspectRatio =
            typeof data?.aspectRatio === "string" && data.aspectRatio.trim()
                ? data.aspectRatio.trim()
                : undefined;
        const durationSec =
            Number.isFinite(Number(data?.durationSec)) && Number(data.durationSec) > 0
                ? Number(data.durationSec)
                : undefined;

        await requireManage(request, creatorId);

        const queueRef = hubRef(creatorId).collection("mediaQueue").doc();
        const mediaId = queueRef.id;

        // MEDIA-GATE: object stays quarantined until the gate clears it; Storage rules deny serve while quarantined.
        // TODO(media-gate): hand off to MEDIA-GATE pipeline + on-device Vision pre-check (CSAM scan flag OFF).
        const record: CreatorHubMediaRef & {
            ownerUid: string;
            createdAt: string;
        } = {
            kind,
            storagePath,
            ...(aspectRatio ? { aspectRatio } : {}),
            ...(durationSec ? { durationSec } : {}),
            moderation: "quarantined", // NEVER servable until cleared
            ownerUid: uid,
            createdAt: nowISO(),
        };

        await queueRef.set(record);

        return { ok: true, mediaId, moderation: "quarantined" };
    }
);
