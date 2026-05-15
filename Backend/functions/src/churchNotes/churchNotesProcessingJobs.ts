import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAuthAndAppCheck, enforceAmenGuards } from "../amenAI/common";
import { enforceRateLimit, RateLimitConfig } from "../rateLimit";

const db = admin.firestore();

const PROCESSING_RATE_LIMITS: RateLimitConfig[] = [
    { name: "cn_process_1min", windowMs: 60_000,      maxCalls: 3  },
    { name: "cn_process_1day", windowMs: 86_400_000,  maxCalls: 20 },
];

const VALID_SOURCE_TYPES = ["audio", "image", "video", "manual"] as const;
type SourceType = typeof VALID_SOURCE_TYPES[number];

const FILE_LIMITS: Record<SourceType, { maxSizeBytes: number; maxDurationSec?: number }> = {
    audio:  { maxSizeBytes: 100 * 1024 * 1024, maxDurationSec: 7200  },
    image:  { maxSizeBytes:  20 * 1024 * 1024                        },
    video:  { maxSizeBytes: 500 * 1024 * 1024, maxDurationSec: 10800 },
    manual: { maxSizeBytes:   1 * 1024 * 1024                        },
};

/**
 * Creates a processing job for a Church Notes media upload.
 * The job document is the source of truth for all processing status —
 * the client must listen to this document and never trust local state.
 */
export const createChurchNoteProcessingJob = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        await enforceAmenGuards({
            uid,
            taskType: "createChurchNoteProcessingJob",
            featureFlag: "churchNotesMediaIntelligenceEnabled",
            killSwitch: "churchNotesProcessingKillSwitch",
        });

        await enforceRateLimit(uid, PROCESSING_RATE_LIMITS);

        const noteId       = String(request.data?.noteId       ?? "").trim();
        const sourceType   = String(request.data?.sourceType   ?? "") as SourceType;
        const storagePath  = String(request.data?.storagePath  ?? "").trim();
        const fileSizeBytes = Number(request.data?.fileSizeBytes  ?? 0);
        const durationSec   = Number(request.data?.durationSeconds ?? 0);

        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!VALID_SOURCE_TYPES.includes(sourceType)) {
            throw new HttpsError("invalid-argument", "Invalid sourceType. Must be audio, image, video, or manual.");
        }
        if (!storagePath) throw new HttpsError("invalid-argument", "storagePath required.");

        // Storage path must be scoped to this user to prevent path-traversal.
        if (!storagePath.startsWith(`churchNotes/${uid}/`)) {
            throw new HttpsError("permission-denied", "Storage path does not belong to this user.");
        }

        const limits = FILE_LIMITS[sourceType];
        if (fileSizeBytes > limits.maxSizeBytes) {
            throw new HttpsError("invalid-argument", "File exceeds maximum allowed size.");
        }
        if (limits.maxDurationSec && durationSec > limits.maxDurationSec) {
            throw new HttpsError("invalid-argument", "Media exceeds maximum allowed duration.");
        }

        // Server-side ownership check — never trust the client.
        const noteRef  = db.collection("churchNotes").doc(noteId);
        const noteSnap = await noteRef.get();
        if (!noteSnap.exists) {
            throw new HttpsError("not-found", "Church note not found.");
        }
        if (noteSnap.data()?.userId !== uid) {
            throw new HttpsError("permission-denied", "You do not own this church note.");
        }

        // Prevent duplicate in-flight jobs for the same note + sourceType.
        const existingSnap = await noteRef.collection("processingJobs")
            .where("userId", "==", uid)
            .where("sourceType", "==", sourceType)
            .where("status", "in", ["queued", "processing"])
            .limit(1)
            .get();
        if (!existingSnap.empty) {
            const existing = existingSnap.docs[0];
            return { jobId: existing.id, noteId, status: "queued", duplicate: true };
        }

        const jobRef = noteRef.collection("processingJobs").doc();
        await jobRef.set({
            jobId:             jobRef.id,
            userId:            uid,
            churchNoteId:      noteId,
            sourceType,
            storagePath,
            fileSizeBytes,
            durationSeconds:   durationSec || null,
            status:            "queued",
            progress:          0,
            // Server-owned output fields — clients cannot write these.
            transcriptText:    null,
            ocrText:           null,
            extractedOutline:  null,
            summaryDraft:      null,
            studyGuideDraft:   null,
            prayerPromptsDraft: null,
            safetyStatus:      "pending",
            moderationStatus:  "pending",
            errorCode:         null,
            errorMessage:      null,
            createdAt:         admin.firestore.FieldValue.serverTimestamp(),
            updatedAt:         admin.firestore.FieldValue.serverTimestamp(),
            completedAt:       null,
        });

        return { jobId: jobRef.id, noteId, status: "queued" };
    }
);
