// generateEventReplayPackage.ts
// AMEN — Creator Profiles: assemble a deterministic "replay package" for an ended event.
//
// Callable:
//   generateEventReplayPackage — owner/moderator/admin-only. Reads an ended event,
//   assembles a replay package from existing fields + any linked teaching, and persists
//   it under creatorHubs/{creatorId}/events/{eventId}.replayPackage.
//
// No external AI call — assembly is deterministic from data already in Firestore.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
    CreatorHubEventStatus,
    CreatorHubEventType,
    CREATOR_HUB_FLAGS,
} from "./creatorProfileTypes";
import {
    requireAuth,
    requireManage,
    subCol,
    SUB,
    reqString,
} from "./creatorProfilesShared";
import { assertCreatorHubFlag } from "./creatorProfilesFlags";

interface GenerateReplayData {
    creatorId?: string;
    eventId?: string;
}

interface ReplayKeyMoment {
    label: string;
    timestampSec: number;
}

interface EventReplayPackage {
    recordingRef?: string;
    transcriptRef?: string;
    summary: string;
    keyMoments: ReplayKeyMoment[];
    scriptureRefs: string[];
    questions: string[];
}

function eventTypeLabel(type: CreatorHubEventType | undefined): string {
    switch (type) {
        case "sermon": return "sermon";
        case "bibleStudy": return "Bible study";
        case "worshipNight": return "worship night";
        case "conference": return "conference session";
        case "class": return "class";
        case "prayerMeeting": return "prayer meeting";
        case "livestream": return "livestream";
        case "revival": return "revival gathering";
        case "webinar": return "webinar";
        case "mentorship": return "mentorship session";
        case "smallGroup": return "small group";
        default: return "gathering";
    }
}

/** Look up a linked teaching for this event, if one references it via `eventRef`. */
async function findLinkedTeaching(
    creatorId: string,
    eventId: string
): Promise<admin.firestore.DocumentData | undefined> {
    const snap = await subCol(creatorId, SUB.teachings)
        .where("eventRef", "==", eventId)
        .limit(1)
        .get();
    if (snap.empty) return undefined;
    return snap.docs[0].data();
}

export const generateEventReplayPackage = onCall(
    { region: "us-east1", enforceAppCheck: true, timeoutSeconds: 15, memory: "256MiB" },
    async (request): Promise<{ ok: true; replayPackage: EventReplayPackage }> => {
        const uid = requireAuth(request);
        void uid;
        await assertCreatorHubFlag(CREATOR_HUB_FLAGS.eventsEnabled);

        const data = (request.data ?? {}) as GenerateReplayData;
        const creatorId = reqString(data, "creatorId");
        const eventId = reqString(data, "eventId");

        await requireManage(request, creatorId);

        const eventRef = subCol(creatorId, SUB.events).doc(eventId);
        const eventSnap = await eventRef.get();
        if (!eventSnap.exists) {
            throw new HttpsError("not-found", "Event does not exist.");
        }
        const event = eventSnap.data() ?? {};

        const status = event.status as CreatorHubEventStatus | undefined;
        if (status !== "ended") {
            throw new HttpsError(
                "failed-precondition",
                "Replay packages can only be generated for events with status 'ended'."
            );
        }

        const teaching = await findLinkedTeaching(creatorId, eventId);

        const title = typeof event.title === "string" ? event.title : "this gathering";
        const typeLabel = eventTypeLabel(event.type as CreatorHubEventType | undefined);

        // TODO(teaching-intelligence): enrich summary/keyMoments via processTeachingMedia transcript chunks.

        // Deterministic summary from existing data.
        const summaryParts: string[] = [`Replay of "${title}", a ${typeLabel}.`];
        if (teaching?.notes && typeof teaching.notes === "string" && teaching.notes.trim()) {
            summaryParts.push(teaching.notes.trim());
        } else if (Array.isArray(teaching?.outline) && teaching.outline.length > 0) {
            const points = (teaching.outline as unknown[])
                .filter((p): p is string => typeof p === "string" && p.trim().length > 0)
                .map((p) => p.trim());
            if (points.length > 0) {
                summaryParts.push(`Covered: ${points.join("; ")}.`);
            }
        }
        const summary = summaryParts.join(" ");

        // Key moments: derive from the teaching outline when present (evenly spaced
        // placeholders) so the replay scrubber has navigable anchors.
        const keyMoments: ReplayKeyMoment[] = [];
        const outline = Array.isArray(teaching?.outline)
            ? (teaching.outline as unknown[]).filter((p): p is string => typeof p === "string" && p.trim().length > 0)
            : [];
        const durationSec = typeof teaching?.durationSec === "number" && teaching.durationSec > 0
            ? teaching.durationSec
            : 0;
        if (outline.length > 0) {
            outline.forEach((label, index) => {
                const timestampSec = durationSec > 0
                    ? Math.floor((durationSec * index) / outline.length)
                    : index * 300; // fallback: 5-min spacing
                keyMoments.push({ label: label.trim(), timestampSec });
            });
        }

        // Scripture references: from the teaching when linked.
        const scriptureRefs = Array.isArray(teaching?.scriptureRefs)
            ? (teaching.scriptureRefs as unknown[]).filter((s): s is string => typeof s === "string" && s.trim().length > 0).map((s) => s.trim())
            : [];

        // Reflection questions: deterministic prompts seeded from scripture refs / topics.
        const questions: string[] = [];
        if (scriptureRefs.length > 0) {
            questions.push(`What stood out to you in ${scriptureRefs[0]}?`);
        }
        const topics = Array.isArray(teaching?.topics)
            ? (teaching.topics as unknown[]).filter((t): t is string => typeof t === "string" && t.trim().length > 0).map((t) => t.trim())
            : [];
        if (topics.length > 0) {
            questions.push(`How does the theme of ${topics[0]} apply to your week?`);
        }
        questions.push("What is one step you can take in response to this teaching?");

        const replayPackage: EventReplayPackage = {
            summary,
            keyMoments,
            scriptureRefs,
            questions,
        };

        const recordingRef = typeof event.livestreamRef === "string" && event.livestreamRef.trim()
            ? event.livestreamRef.trim()
            : (typeof teaching?.video === "object" && teaching?.video?.storagePath
                ? String(teaching.video.storagePath)
                : undefined);
        if (recordingRef) replayPackage.recordingRef = recordingRef;

        const transcriptRef = typeof teaching?.transcriptRef === "string" && teaching.transcriptRef.trim()
            ? teaching.transcriptRef.trim()
            : undefined;
        if (transcriptRef) replayPackage.transcriptRef = transcriptRef;

        await eventRef.set(
            {
                replayPackage,
                replayGeneratedAt: admin.firestore.Timestamp.now(),
            },
            { merge: true }
        );

        return { ok: true, replayPackage };
    }
);
