// spaces/livestreamAI.ts
//
// Livestream AI assistant callables for AMEN Spaces.
//
// Callables:
//   askStreamTranscript      — answers a viewer question from the stream transcript
//   getHostAssistantSignals  — aggregates unanswered Q&A, prayer requests, and raised hands

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

// ── Interfaces ────────────────────────────────────────────────────────────────

interface AskStreamTranscriptInput {
    streamId: string;
    question: string;
}

interface GetHostAssistantSignalsInput {
    streamId: string;
}

interface TranscriptAnswer {
    answer: string;
    sourceQuote: string;
    sourceTimestamp: string;
    scriptureRefs: string[];
    confidence: number;
}

interface HostSignal {
    id: string;
    authorName: string;
    text: string;
    ageMinutes: number;
}

interface HostAssistantSignals {
    questions: HostSignal[];
    prayerRequests: HostSignal[];
    raisedHands: HostSignal[];
    aiSuggestion: string | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function validateStringField(value: unknown, fieldName: string): string {
    if (typeof value !== "string" || !value.trim()) {
        throw new HttpsError("invalid-argument", `${fieldName} is required.`);
    }
    return value.trim();
}

function ageMinutesFromTimestamp(createdAt: Timestamp | undefined): number {
    if (!createdAt) return 0;
    const diffMs = Date.now() - createdAt.toMillis();
    return Math.max(0, Math.floor(diffMs / 60000));
}

// ── askStreamTranscript ───────────────────────────────────────────────────────

export const askStreamTranscript = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<TranscriptAnswer> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<AskStreamTranscriptInput>;
        const streamId = validateStringField(data.streamId, "streamId");
        const question = validateStringField(data.question, "question");

        if (question.length > 500) {
            throw new HttpsError("invalid-argument", "question must not exceed 500 characters.");
        }

        const db = getFirestore();

        // Attempt to read transcript — search across all spaces that contain this streamId
        // by querying the top-level path pattern. Client should pass spaceId in future; for
        // now we resolve via the livestreams top-level collection if it exists.
        const transcriptSnap = await db
            .collection("livestreams")
            .doc(streamId)
            .collection("transcript")
            .limit(1)
            .get();

        // Stub response — real implementation calls Vertex AI / Gemini with transcript context
        const _transcriptExists = !transcriptSnap.empty;

        return {
            answer: `Based on the stream transcript, the discussion touched on: ${question}`,
            sourceQuote: "This is a placeholder quote from the transcript.",
            sourceTimestamp: "32:14",
            scriptureRefs: ["John 3:16", "Romans 8:28"],
            confidence: 0.85,
        };
    }
);

// ── getHostAssistantSignals ───────────────────────────────────────────────────

export const getHostAssistantSignals = onCall({ enforceAppCheck: true, region: "us-central1" }, async (request): Promise<HostAssistantSignals> => {
        const { uid } = request.auth ?? {};
        if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");

        const data = (request.data ?? {}) as Partial<GetHostAssistantSignalsInput>;
        const streamId = validateStringField(data.streamId, "streamId");

        const db = getFirestore();
        const streamRef = db.collection("livestreams").doc(streamId);

        // Fetch all three signal types in parallel
        const [qaSnap, prayerSnap, handsSnap] = await Promise.all([
            streamRef.collection("qaQueue").where("answered", "==", false).get(),
            streamRef.collection("prayerRequests").where("acknowledged", "==", false).get(),
            streamRef.collection("raisedHands").where("calledOn", "==", false).get(),
        ]);

        const toSignals = (
            docs: FirebaseFirestore.QueryDocumentSnapshot[]
        ): HostSignal[] =>
            docs.map((doc) => {
                const d = doc.data();
                return {
                    id: doc.id,
                    authorName: (d.authorName as string) ?? "Viewer",
                    text: (d.text as string) ?? (d.question as string) ?? "",
                    ageMinutes: ageMinutesFromTimestamp(d.createdAt as Timestamp | undefined),
                };
            });

        const questions = toSignals(qaSnap.docs);
        const prayerRequests = toSignals(prayerSnap.docs);
        const raisedHands = toSignals(handsSnap.docs);

        // Provide a simple AI suggestion stub based on signal counts
        let aiSuggestion: string | null = null;
        if (prayerRequests.length > 0) {
            aiSuggestion = `There ${prayerRequests.length === 1 ? "is" : "are"} ${prayerRequests.length} unanswered prayer request${prayerRequests.length === 1 ? "" : "s"} — consider pausing for a moment of prayer.`;
        } else if (questions.length > 3) {
            aiSuggestion = `${questions.length} questions are queued — consider opening a Q&A segment.`;
        }

        return { questions, prayerRequests, raisedHands, aiSuggestion };
    }
);
