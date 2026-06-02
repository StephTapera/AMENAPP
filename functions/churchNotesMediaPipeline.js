/**
 * churchNotesMediaPipeline.js
 * AMEN App — Church Notes Media Ingestion Pipeline
 *
 * 5 onCall Cloud Functions (Firebase Functions v2) for ingesting church note
 * media: audio transcription, image OCR, video transcription, and PDF OCR.
 *
 * Firestore collection: churchNoteProcessingJobs
 * Job doc fields:
 *   noteId, userId, sourceType ("audio"|"image"|"video"|"document"),
 *   storagePath, fileSizeBytes, durationSeconds,
 *   status ("queued"|"processing"|"completed"|"failed"),
 *   transcribedText, errorMessage, createdAt, updatedAt
 *
 * Note: admin.initializeApp() is called once in index.js — not here.
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const vision = require("@google-cloud/vision");
const speech = require("@google-cloud/speech");

// ─── Lazy client init ─────────────────────────────────────────────────────────

let _visionClient = null;
function getVisionClient() {
    if (!_visionClient) {
        _visionClient = new vision.ImageAnnotatorClient();
    }
    return _visionClient;
}

let _speechClient = null;
function getSpeechClient() {
    if (!_speechClient) {
        _speechClient = new speech.SpeechClient();
    }
    return _speechClient;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";
const JOBS_COLLECTION = "churchNoteProcessingJobs";
const NOTES_COLLECTION = "churchNotes";

// ─── Shared helpers ───────────────────────────────────────────────────────────

/**
 * Verify the calling user is authenticated and owns the given note.
 * Returns { uid, jobDoc } after loading and verifying the job.
 */
async function requireAuthAndJobOwnership(request, noteId, jobId) {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;

    const db = getFirestore();
    const jobRef = db.collection(JOBS_COLLECTION).doc(jobId);
    const jobSnap = await jobRef.get();

    if (!jobSnap.exists) {
        throw new HttpsError("not-found", `Job ${jobId} not found.`);
    }

    const jobData = jobSnap.data();

    if (jobData.userId !== uid) {
        throw new HttpsError("permission-denied", "You do not own this job.");
    }

    if (jobData.noteId !== noteId) {
        throw new HttpsError("invalid-argument", "Job does not belong to the given note.");
    }

    return {uid, jobRef, jobData};
}

/**
 * Build a gs:// URI from a relative storagePath.
 */
function buildGcsUri(storagePath) {
    const bucketName = getStorage().bucket().name;
    return `gs://${bucketName}/${storagePath}`;
}

/**
 * Write the "completed" outcome back to the job and note documents.
 */
async function markJobCompleted(jobRef, noteId, transcript) {
    const db = getFirestore();
    const now = FieldValue.serverTimestamp();

    await jobRef.update({
        status: "completed",
        transcribedText: transcript,
        updatedAt: now,
    });

    await db.collection(NOTES_COLLECTION).doc(noteId).update({
        extractedText: transcript,
        lastProcessedAt: now,
        "aiDraftState.status": "ready_for_review",
    });
}

/**
 * Write the "failed" outcome back to the job document.
 */
async function markJobFailed(jobRef, errorMessage) {
    await jobRef.update({
        status: "failed",
        errorMessage: errorMessage,
        updatedAt: FieldValue.serverTimestamp(),
    });
}

// ─── 1. createChurchNoteProcessingJob ────────────────────────────────────────

/**
 * Create a new processing job in the queued state.
 *
 * Input:  { noteId, sourceType, storagePath, fileSizeBytes?, durationSeconds? }
 * Output: { jobId }
 */
exports.createChurchNoteProcessingJob = onCall(
    {region: REGION},
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Must be signed in.");
        }
        const uid = request.auth.uid;

        const {noteId, sourceType, storagePath, fileSizeBytes, durationSeconds} = request.data;

        if (!noteId || typeof noteId !== "string" || noteId.trim() === "") {
            throw new HttpsError("invalid-argument", "noteId is required.");
        }
        if (!sourceType || !["audio", "image", "video", "document"].includes(sourceType)) {
            throw new HttpsError(
                "invalid-argument",
                "sourceType must be one of: audio, image, video, document."
            );
        }
        if (!storagePath || typeof storagePath !== "string" || storagePath.trim() === "") {
            throw new HttpsError("invalid-argument", "storagePath is required.");
        }

        const db = getFirestore();

        // Verify the calling user owns the note.
        const noteSnap = await db.collection(NOTES_COLLECTION).doc(noteId).get();
        if (!noteSnap.exists) {
            throw new HttpsError("not-found", `Church note ${noteId} not found.`);
        }
        if (noteSnap.data().userId !== uid) {
            throw new HttpsError("permission-denied", "You do not own this note.");
        }

        const now = FieldValue.serverTimestamp();
        const jobData = {
            noteId,
            userId: uid,
            sourceType,
            storagePath,
            status: "queued",
            transcribedText: null,
            errorMessage: null,
            createdAt: now,
            updatedAt: now,
        };

        if (fileSizeBytes !== undefined && fileSizeBytes !== null) {
            jobData.fileSizeBytes = fileSizeBytes;
        }
        if (durationSeconds !== undefined && durationSeconds !== null) {
            jobData.durationSeconds = durationSeconds;
        }

        const jobRef = await db.collection(JOBS_COLLECTION).add(jobData);

        console.log(`[createChurchNoteProcessingJob] Created job ${jobRef.id} for note ${noteId}`);

        return {jobId: jobRef.id};
    }
);

// ─── 2. processChurchNoteAudio ────────────────────────────────────────────────

/**
 * Transcribe an audio attachment using Cloud Speech-to-Text.
 *
 * Input:  { noteId, jobId }
 * Output: { status: "completed", jobId }
 */
exports.processChurchNoteAudio = onCall(
    {region: REGION, timeoutSeconds: 300, memory: "512MiB"},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);

        await jobRef.update({
            status: "processing",
            updatedAt: FieldValue.serverTimestamp(),
        });

        const gcsUri = buildGcsUri(jobData.storagePath);

        try {
            const [operation] = await getSpeechClient().longRunningRecognize({
                config: {
                    encoding: "MP4",
                    sampleRateHertz: 16000,
                    languageCode: "en-US",
                    enableAutomaticPunctuation: true,
                    model: "latest_long",
                    useEnhanced: true,
                },
                audio: {uri: gcsUri},
            });

            const [response] = await operation.promise();

            const transcript = (response.results || [])
                .map((r) => r.alternatives[0]?.transcript || "")
                .join(" ")
                .trim();

            await markJobCompleted(jobRef, noteId, transcript);

            console.log(`[processChurchNoteAudio] Completed job ${jobId}, ${transcript.length} chars`);

            return {status: "completed", jobId};
        } catch (err) {
            console.error(`[processChurchNoteAudio] Failed job ${jobId}:`, err);
            await markJobFailed(jobRef, err.message);
            throw new HttpsError("internal", `Audio transcription failed: ${err.message}`);
        }
    }
);

// ─── 3. processChurchNoteImageOCR ─────────────────────────────────────────────

/**
 * Extract text from an image attachment using Cloud Vision document OCR.
 *
 * Input:  { noteId, jobId }
 * Output: { status: "completed", jobId }
 */
exports.processChurchNoteImageOCR = onCall(
    {region: REGION, timeoutSeconds: 120},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);

        await jobRef.update({
            status: "processing",
            updatedAt: FieldValue.serverTimestamp(),
        });

        const gcsUri = buildGcsUri(jobData.storagePath);

        try {
            const [result] = await getVisionClient().documentTextDetection(gcsUri);

            const transcript = (result.fullTextAnnotation?.text || "").trim();

            await markJobCompleted(jobRef, noteId, transcript);

            console.log(`[processChurchNoteImageOCR] Completed job ${jobId}, ${transcript.length} chars`);

            return {status: "completed", jobId};
        } catch (err) {
            console.error(`[processChurchNoteImageOCR] Failed job ${jobId}:`, err);
            await markJobFailed(jobRef, err.message);
            throw new HttpsError("internal", `Image OCR failed: ${err.message}`);
        }
    }
);

// ─── 4. processChurchNoteVideo ────────────────────────────────────────────────

/**
 * Transcribe a video attachment using Cloud Speech-to-Text (video model).
 *
 * Input:  { noteId, jobId }
 * Output: { status: "completed", jobId }
 */
exports.processChurchNoteVideo = onCall(
    {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);

        await jobRef.update({
            status: "processing",
            updatedAt: FieldValue.serverTimestamp(),
        });

        const gcsUri = buildGcsUri(jobData.storagePath);

        try {
            const [operation] = await getSpeechClient().longRunningRecognize({
                config: {
                    encoding: "MP4",
                    sampleRateHertz: 16000,
                    languageCode: "en-US",
                    enableAutomaticPunctuation: true,
                    model: "video",
                    useEnhanced: true,
                },
                audio: {uri: gcsUri},
            });

            const [response] = await operation.promise();

            const transcript = (response.results || [])
                .map((r) => r.alternatives[0]?.transcript || "")
                .join(" ")
                .trim();

            await markJobCompleted(jobRef, noteId, transcript);

            console.log(`[processChurchNoteVideo] Completed job ${jobId}, ${transcript.length} chars`);

            return {status: "completed", jobId};
        } catch (err) {
            console.error(`[processChurchNoteVideo] Failed job ${jobId}:`, err);
            await markJobFailed(jobRef, err.message);
            throw new HttpsError("internal", `Video transcription failed: ${err.message}`);
        }
    }
);

// ─── 5. processChurchNoteDocumentPDF ─────────────────────────────────────────

/**
 * Extract text from a PDF using Cloud Vision asyncBatchAnnotateFiles.
 * Output JSON is written to GCS prefix church_notes_ocr/{jobId}/,
 * then the first result file is downloaded and parsed.
 *
 * Input:  { noteId, jobId }
 * Output: { status: "completed", jobId }
 */
exports.processChurchNoteDocumentPDF = onCall(
    {region: REGION, timeoutSeconds: 300},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);

        await jobRef.update({
            status: "processing",
            updatedAt: FieldValue.serverTimestamp(),
        });

        const gcsUri = buildGcsUri(jobData.storagePath);
        const bucketName = getStorage().bucket().name;
        const outputPrefix = `church_notes_ocr/${jobId}/`;
        const outputGcsUri = `gs://${bucketName}/${outputPrefix}`;

        try {
            const [operation] = await getVisionClient().asyncBatchAnnotateFiles({
                requests: [
                    {
                        inputConfig: {
                            gcsSource: {uri: gcsUri},
                            mimeType: "application/pdf",
                        },
                        features: [{type: "DOCUMENT_TEXT_DETECTION"}],
                        outputConfig: {
                            gcsDestination: {uri: outputGcsUri},
                            batchSize: 100,
                        },
                    },
                ],
            });

            await operation.promise();

            // Download and parse the first output JSON file from Storage.
            const bucket = getStorage().bucket();
            const [files] = await bucket.getFiles({prefix: outputPrefix});

            const jsonFiles = files.filter((f) => f.name.endsWith(".json"));
            if (jsonFiles.length === 0) {
                throw new Error("Vision API produced no output files for this PDF.");
            }

            // Sort by name so we read output-1-to-N.json first.
            jsonFiles.sort((a, b) => a.name.localeCompare(b.name));

            const [contents] = await jsonFiles[0].download();
            const parsed = JSON.parse(contents.toString("utf8"));

            const textParts = (parsed.responses || [])
                .map((r) => r.fullTextAnnotation?.text || "")
                .filter(Boolean);

            const transcript = textParts.join("\n").trim();

            await markJobCompleted(jobRef, noteId, transcript);

            console.log(`[processChurchNoteDocumentPDF] Completed job ${jobId}, ${transcript.length} chars`);

            return {status: "completed", jobId};
        } catch (err) {
            console.error(`[processChurchNoteDocumentPDF] Failed job ${jobId}:`, err);
            await markJobFailed(jobRef, err.message);
            throw new HttpsError("internal", `PDF OCR failed: ${err.message}`);
        }
    }
);
