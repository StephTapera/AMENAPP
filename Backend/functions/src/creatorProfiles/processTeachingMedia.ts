// processTeachingMedia.ts
// AMEN — Creator Profiles: teaching-media ingest pipeline (transcription → chunk → embed).
//
// PRIVACY INVARIANT: Raw media retention is NONE by default. This function NEVER copies
// the source media. It produces a transcript/embedding pipeline record only; transport
// (on-device vs server transcription) is a human-gated decision and stays "deferred"
// until a flag flips it on.

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
import { CREATOR_HUB_FLAGS } from "./creatorProfileTypes";

type TeachingTransport = "deferred";

interface TeachingMediaProcessing {
    transcriptRef?: string;
    chunkCount: number;
    embedded: boolean;
    transport: TeachingTransport;
    status: "processing" | "complete" | "failed";
    updatedAt: string;
}

interface ProcessTeachingMediaResult {
    ok: true;
    teachingId: string;
    mediaProcessing: TeachingMediaProcessing;
}

export const processTeachingMedia = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB" },
    async (request): Promise<ProcessTeachingMediaResult> => {
        const uid = requireAuth(request);
        // Teaching ingest is part of profiles.
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.profilesEnabled);

        const data = request.data;
        const creatorId = reqString(data, "creatorId");
        const teachingId = reqString(data, "teachingId");
        void uid;

        await requireManage(request, creatorId);

        const teachingRef = subCol(creatorId, SUB.teachings).doc(teachingId);
        const teachingSnap = await teachingRef.get();
        if (!teachingSnap.exists) {
            throw new HttpsError("not-found", "Teaching not found.");
        }
        const teaching = teachingSnap.data() ?? {};

        // Mark "processing" up front so the dashboard reflects in-flight state.
        const processingState: TeachingMediaProcessing = {
            chunkCount: 0,
            embedded: false,
            transport: "deferred",
            status: "processing",
            updatedAt: nowISO(),
        };
        await teachingRef.set({ mediaProcessing: processingState }, { merge: true });

        // Raw media retention: NONE by default (privacy).
        // TODO(transcription): transport (on-device vs server) is a human decision — gated.
        // TODO(pinecone): embed transcript chunks into creator-namespaced index.

        // Baseline deferred pipeline: we do not transcribe or embed in this build. If a
        // transcript already exists on the doc, surface its ref; otherwise leave undefined.
        const existingTranscriptRef =
            typeof teaching.transcriptRef === "string" ? teaching.transcriptRef : undefined;

        const result: TeachingMediaProcessing = {
            transcriptRef: existingTranscriptRef,
            chunkCount: 0,
            embedded: false,
            transport: "deferred",
            status: "complete",
            updatedAt: nowISO(),
        };

        await teachingRef.set({ mediaProcessing: result }, { merge: true });

        return { ok: true, teachingId, mediaProcessing: result };
    }
);
