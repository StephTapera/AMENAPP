import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { ImageAnnotatorClient } from "@google-cloud/vision";
import { requireAuthAndAppCheck, lightweightModeration } from "../amenAI/common";

const db        = admin.firestore();
const storage   = admin.storage();
const visionClient = new ImageAnnotatorClient();

const MAX_OCR_CHARS      = 40_000;
const ALLOWED_IMAGE_EXTS = new Set(["jpg", "jpeg", "png", "heic", "heif", "webp"]);

async function assertJobOwner(uid: string, noteId: string, jobId: string): Promise<admin.firestore.DocumentSnapshot> {
    const jobRef  = db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId);
    const jobSnap = await jobRef.get();
    if (!jobSnap.exists)                throw new HttpsError("not-found",         "Processing job not found.");
    if (jobSnap.data()?.userId !== uid)  throw new HttpsError("permission-denied", "Not your processing job.");
    return jobSnap;
}

async function updateJob(noteId: string, jobId: string, fields: Record<string, unknown>): Promise<void> {
    await db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId).update({
        ...fields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

/**
 * Runs OCR on a church photo (whiteboard, projector screen, slide, handout).
 * Uses Google Cloud Vision text detection. All ownership and safety
 * checks are performed server-side. Raw OCR text is never logged.
 */
export const processChurchNoteImageOCR = onCall(
    { enforceAppCheck: true, timeoutSeconds: 120, memory: "512MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId  = String(request.data?.jobId  ?? "").trim();
        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)  throw new HttpsError("invalid-argument", "jobId required.");

        // Feature flag / kill switch — re-checked server-side.
        const flagSnap = await db.collection("system").doc("amenAIFlags").get();
        const flags    = flagSnap.data() ?? {};
        if (flags["churchNotesProcessingKillSwitch"] === true) {
            throw new HttpsError("failed-precondition", "Image processing is temporarily unavailable.");
        }
        if (flags["churchNotesPhotoOCREnabled"] !== true) {
            throw new HttpsError("failed-precondition", "Photo OCR is not enabled.");
        }

        const jobSnap = await assertJobOwner(uid, noteId, jobId);
        const job     = jobSnap.data()!;

        if (!["queued", "failed"].includes(job.status)) {
            throw new HttpsError("failed-precondition", `Job is already in status: ${job.status}.`);
        }

        const storagePath: string = job.storagePath;
        if (!storagePath.startsWith(`churchNotes/${uid}/`)) {
            throw new HttpsError("permission-denied", "Storage path does not belong to this user.");
        }

        const ext = storagePath.split(".").pop()?.toLowerCase() ?? "";
        if (!ALLOWED_IMAGE_EXTS.has(ext)) {
            await updateJob(noteId, jobId, {
                status:       "failed",
                errorCode:    "unsupported_format",
                errorMessage: "Unsupported image format.",
                completedAt:  admin.firestore.FieldValue.serverTimestamp(),
            });
            throw new HttpsError("invalid-argument", "Unsupported image format.");
        }

        await updateJob(noteId, jobId, { status: "processing", progress: 10 });

        let ocrText: string;
        try {
            // Use gs:// URI so Vision API reads directly from Storage without download.
            const bucketName = storage.bucket().name;
            const gcsUri     = `gs://${bucketName}/${storagePath}`;

            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const [result] = await (visionClient as any).textDetection({ image: { source: { imageUri: gcsUri } } });
            const fullText = (result.fullTextAnnotation?.text ?? result.textAnnotations?.[0]?.description ?? "") as string;
            ocrText = fullText.substring(0, MAX_OCR_CHARS);
        } catch (err) {
            functions.logger.error("[churchNotes] OCR failed", {
                noteId,
                jobId,
                errorCode: (err as NodeJS.ErrnoException)?.code ?? "unknown",
            });
            await updateJob(noteId, jobId, {
                status:       "failed",
                errorCode:    "ocr_failed",
                errorMessage: "Text could not be extracted. Please try again.",
                completedAt:  admin.firestore.FieldValue.serverTimestamp(),
            });
            throw new HttpsError("internal", "OCR processing failed.");
        }

        await updateJob(noteId, jobId, { progress: 80 });

        // Safety check on extracted text.
        const safetyCheck  = lightweightModeration(ocrText);
        const safetyStatus = safetyCheck.ok ? "passed" : "flagged";

        // Store OCR output server-side only. Never log raw content.
        await updateJob(noteId, jobId, {
            status:           "draftReady",
            progress:         100,
            ocrText,
            safetyStatus,
            moderationStatus: "reviewed",
            completedAt:      admin.firestore.FieldValue.serverTimestamp(),
        });

        functions.logger.info("[churchNotes] OCR processed", { noteId, jobId, safetyStatus });

        return { jobId, noteId, status: "draftReady" };
    }
);

/**
 * Stub for video processing. Feature flag defaults off until
 * audio + OCR are stable. Never exposes incomplete UI.
 */
export const processChurchNoteVideo = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        await requireAuthAndAppCheck(request.auth, request.app);

        // Video processing is intentionally disabled until audio + OCR are stable.
        throw new HttpsError("failed-precondition", "Video processing is not available yet.");
    }
);
