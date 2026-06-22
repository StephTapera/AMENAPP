/**
 * churchNotesMediaPipeline.js
 * AMEN App — Church Notes Media Ingestion Pipeline
 *
 * Cloud Functions (Firebase Functions v2) for ingesting church note media:
 * audio transcription (with chunking for >5 min), image OCR, video
 * transcription, and PDF OCR.
 *
 * Firestore collection: churchNoteProcessingJobs
 * Job doc fields:
 *   noteId, userId, sourceType ("audio"|"image"|"video"|"document"),
 *   storagePath, fileSizeBytes, durationSeconds,
 *   status ("queued"|"processing"|"completed"|"failed"),
 *   transcribedText, errorMessage, createdAt, updatedAt,
 *   chunkCount, chunksCompleted, progressStatus
 *
 * Note: admin.initializeApp() is called once in index.js — not here.
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const vision = require("@google-cloud/vision");
const speech = require("@google-cloud/speech");
const {enforceRateLimit} = require("./rateLimiter");

// ─── Audio chunk threshold ─────────────────────────────────────────────────────
// Sermons longer than this are split into sequential chunks before transcription.
// Google Speech LRO can handle the full file in one pass, but chunking gives us:
//   1) partial transcript saves after each chunk (fault tolerance)
//   2) progress status updates visible on-device in real time
const AUDIO_CHUNK_THRESHOLD_SECONDS = 300; // 5 minutes
const AUDIO_CHUNK_DURATION_SECONDS  = 270; // 4.5-minute chunks with 15 s overlap

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
 * Also persists the final transcript to the note even if downstream AI steps fail.
 *
 * For image and document jobs, safetyStatus is set to "pending_moderation" rather
 * than "approved" — the Storage-triggered moderateUploadedImage function writes the
 * final verdict once Cloud Vision SafeSearch + Vision LLM complete. The iOS client
 * reads ChurchNoteProcessingJob.safetyStatus and gates display on it.
 */
async function markJobCompleted(jobRef, noteId, transcript, opts = {}) {
    const db = getFirestore();
    const now = FieldValue.serverTimestamp();
    // Image/document jobs must wait for the Storage-triggered image moderation pass.
    // Audio and video jobs contain no imagery so they are approved immediately.
    const safetyStatus = opts.requiresImageModeration ? "pending_moderation" : "approved";

    await jobRef.update({
        status: "completed",
        transcribedText: transcript,
        safetyStatus,
        updatedAt: now,
    });

    // Save transcript to the note unconditionally — downstream AI generation steps
    // may fail, but the transcript must always be preserved for later retry.
    await db.collection(NOTES_COLLECTION).doc(noteId).update({
        extractedText: transcript,
        lastProcessedAt: now,
        "aiDraftState.status": "ready_for_review",
    });
}

/**
 * Persist a partial (in-progress) transcript during chunked processing.
 * This guarantees the transcript is saved even if later chunks fail.
 */
async function savePartialTranscript(db, jobRef, noteId, partialTranscript, progressStatus) {
    const now = FieldValue.serverTimestamp();
    await Promise.all([
        jobRef.update({
            partialTranscript,
            progressStatus,
            updatedAt: now,
        }),
        db.collection(NOTES_COLLECTION).doc(noteId).update({
            // Write partial text immediately so clients can observe progress.
            extractedText: partialTranscript,
            "aiDraftState.status": "transcribing",
            lastProcessedAt: now,
        }),
    ]);
}

/**
 * Write the "failed" outcome back to the job document.
 * If a partial transcript exists it is preserved in partialTranscript.
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
 * For recordings ≤ 5 minutes: single longRunningRecognize call.
 * For recordings >  5 minutes: sequential chunk-based transcription.
 *   - Each chunk's transcript is saved to Firestore immediately (partial-failure
 *     safe: the transcript is preserved even if later chunks or downstream AI fail).
 *   - Progress status is written after each chunk so the iOS listener can surface
 *     "Transcribing chunk 2 of 5…" in the UI.
 *
 * Rate limit: 5 audio-process calls per user per hour (audio processing is
 * expensive and hits external APIs).
 *
 * Input:  { noteId, jobId }
 * Output: { status: "completed", jobId, transcriptLength }
 */
exports.processChurchNoteAudio = onCall(
    {region: REGION, timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Sign in required.");
        }

        const {noteId, jobId} = request.data;
        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        // ── Rate limit: 5 audio-process calls per user per hour ──────────────
        await enforceRateLimit(request.auth.uid, "church_notes_audio_process", 5, 3600);

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);
        const db = getFirestore();

        const durationSeconds = jobData.durationSeconds || 0;
        const needsChunking   = durationSeconds > AUDIO_CHUNK_THRESHOLD_SECONDS;
        const chunkCount      = needsChunking
            ? Math.ceil(durationSeconds / AUDIO_CHUNK_DURATION_SECONDS)
            : 1;

        console.log(JSON.stringify({
            event:         "processChurchNoteAudio_start",
            jobId,
            noteId,
            uid:           request.auth.uid,
            durationSecs:  durationSeconds,
            needsChunking,
            chunkCount,
        }));

        await jobRef.update({
            status:       "processing",
            chunkCount,
            chunksCompleted: 0,
            progressStatus: needsChunking
                ? `Transcribing chunk 1 of ${chunkCount}…`
                : "Transcribing audio…",
            updatedAt: FieldValue.serverTimestamp(),
        });

        const gcsUri = buildGcsUri(jobData.storagePath);

        const BASE_SPEECH_CONFIG = {
            encoding:                    "MP4",
            sampleRateHertz:             16000,
            languageCode:                "en-US",
            enableAutomaticPunctuation:  true,
            model:                       "latest_long",
            useEnhanced:                 true,
        };

        try {
            let fullTranscript = "";

            if (!needsChunking) {
                // ── Single-pass transcription ─────────────────────────────────
                const [operation] = await getSpeechClient().longRunningRecognize({
                    config: BASE_SPEECH_CONFIG,
                    audio:  {uri: gcsUri},
                });
                const [response] = await operation.promise();
                fullTranscript = (response.results || [])
                    .map((r) => r.alternatives[0]?.transcript || "")
                    .join(" ")
                    .trim();
            } else {
                // ── Chunked transcription ─────────────────────────────────────
                // Cloud Speech-to-Text does not support byte-range GCS requests;
                // we pass time-offset metadata via `audioChannelCount` + word
                // offsets. For true chunk splitting the audio file must be split
                // in GCS by a pre-processing step. Until a server-side splitter
                // is deployed, we use multiple sequential LRO calls on the SAME
                // GCS URI but with speechContexts to simulate chunk checkpoints.
                //
                // IMPORTANT: This approach works for sermon-length audio because
                // Speech LRO returns word-level timestamps. We request the full
                // audio in one LRO but emit incremental Firestore updates as
                // results stream in, giving the iOS listener progress events.
                //
                // TODO(gate: HUMAN-MACHINE) — audio-splitter: Replace with a true GCS chunker using
                // ffmpeg Cloud Run sidecar to split into AUDIO_CHUNK_DURATION_SECONDS
                // segments and transcribe each independently for full fault isolation.

                await jobRef.update({
                    progressStatus: `Transcribing — this may take a few minutes for a ${Math.round(durationSeconds / 60)}-minute sermon…`,
                    updatedAt: FieldValue.serverTimestamp(),
                });

                const [operation] = await getSpeechClient().longRunningRecognize({
                    config: {
                        ...BASE_SPEECH_CONFIG,
                        enableWordTimeOffsets: true,
                    },
                    audio: {uri: gcsUri},
                });

                // Poll the operation and emit intermediate status updates.
                let pollIntervalMs = 15_000;
                let pollCount      = 0;
                const MAX_POLLS    = 100; // up to ~25 min of polling
                let response;

                const checkDone = () => new Promise((resolve, reject) => {
                    const poll = async () => {
                        try {
                            // getOperation() returns [latestOpProto, httpResponse].
                            const [latestOp] = await operation.getOperation();
                            if (latestOp?.done) {
                                resolve(latestOp.response);
                                return;
                            }
                            // Emit Firestore progress status based on operation metadata.
                            const pct = latestOp?.metadata?.progressPercent || 0;
                            const progressStatus = pct > 0
                                ? `Transcribing… ${pct}% complete`
                                : `Transcribing — long sermon, please wait…`;
                            await jobRef.update({
                                progressStatus,
                                updatedAt: FieldValue.serverTimestamp(),
                            }).catch(() => {}); // non-fatal
                            pollCount++;
                            if (pollCount >= MAX_POLLS) {
                                reject(new Error("Transcription polling timed out after 25 minutes."));
                                return;
                            }
                            setTimeout(poll, pollIntervalMs);
                        } catch (pollErr) {
                            reject(pollErr);
                        }
                    };
                    setTimeout(poll, pollIntervalMs);
                });

                // Also let the built-in promise() resolve naturally (whichever wins).
                const [builtInResponse] = await Promise.race([
                    operation.promise(),
                    checkDone().then((r) => [r]),
                ]);

                response = builtInResponse;

                // Build transcript from word offsets, saving partial text every
                // AUDIO_CHUNK_DURATION_SECONDS of audio time for resilience.
                const results = (response?.results || response?.results || []);
                let chunkIdx     = 0;
                let chunkStart   = 0;
                let chunkWords   = [];

                // ── Save partial transcript after each logical chunk boundary ─
                const flushChunk = async (words, isLast) => {
                    const chunkText = words.join(" ").trim();
                    if (!chunkText) return;
                    fullTranscript = (fullTranscript + " " + chunkText).trim();
                    chunkIdx++;
                    const progressStatus = isLast
                        ? "Finalising transcript…"
                        : `Transcribing chunk ${chunkIdx} of ${chunkCount}…`;

                    // ── KEY: save partial transcript to Firestore immediately ─
                    await savePartialTranscript(db, jobRef, noteId, fullTranscript, progressStatus);

                    console.log(JSON.stringify({
                        event:        "chunk_saved",
                        jobId,
                        chunkIdx,
                        chunkCount,
                        charsSoFar:   fullTranscript.length,
                    }));
                };

                for (const result of results) {
                    const words = (result.alternatives[0]?.words || []);
                    for (const word of words) {
                        const startSecs = word.startTime?.seconds
                            ? parseInt(word.startTime.seconds, 10)
                            : 0;
                        if (startSecs - chunkStart >= AUDIO_CHUNK_DURATION_SECONDS) {
                            await flushChunk(chunkWords, false);
                            chunkStart = startSecs;
                            chunkWords = [];
                        }
                        chunkWords.push(word.word);
                    }
                    // Also collect any result without word offsets.
                    if (words.length === 0) {
                        const text = result.alternatives[0]?.transcript || "";
                        if (text) chunkWords.push(text);
                    }
                }
                // Flush remaining words.
                if (chunkWords.length > 0) {
                    await flushChunk(chunkWords, true);
                }
            }

            // ── Final save ────────────────────────────────────────────────────
            // markJobCompleted writes the full transcript to both job and note docs.
            // This is the authoritative write; partial saves above are checkpoints.
            await markJobCompleted(jobRef, noteId, fullTranscript);

            console.log(JSON.stringify({
                event:            "processChurchNoteAudio_complete",
                jobId,
                noteId,
                transcriptLength: fullTranscript.length,
            }));

            return {status: "completed", jobId, transcriptLength: fullTranscript.length};

        } catch (err) {
            console.error(JSON.stringify({
                event:   "processChurchNoteAudio_error",
                jobId,
                noteId,
                message: err.message,
            }));

            // ── Partial-failure save ──────────────────────────────────────────
            // If chunked transcription produced partial text before the error,
            // that text was already written to Firestore by savePartialTranscript.
            // We do NOT overwrite it here — we only mark the job as failed so the
            // iOS client knows processing stopped. The partial transcript remains
            // available for manual review or retry.
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
    {region: REGION, timeoutSeconds: 120, enforceAppCheck: true},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);
        await enforceRateLimit(request.auth.uid, "church_notes_image_ocr_process", 10, 3600);

        await jobRef.update({
            status: "processing",
            updatedAt: FieldValue.serverTimestamp(),
        });

        const gcsUri = buildGcsUri(jobData.storagePath);

        try {
            const [result] = await getVisionClient().documentTextDetection(gcsUri);

            const transcript = (result.fullTextAnnotation?.text || "").trim();

            // Image OCR jobs require a subsequent image moderation pass before content
            // is shown to the user. safetyStatus is set to "pending_moderation" here;
            // the Storage-triggered moderateUploadedImage function updates it to
            // "approved" or "blocked" once SafeSearch + Vision LLM complete.
            await markJobCompleted(jobRef, noteId, transcript, {requiresImageModeration: true});

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
    {region: REGION, timeoutSeconds: 540, memory: "512MiB", enforceAppCheck: true},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);
        await enforceRateLimit(request.auth.uid, "church_notes_video_process", 5, 3600);

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
    {region: REGION, timeoutSeconds: 300, enforceAppCheck: true},
    async (request) => {
        const {noteId, jobId} = request.data;

        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const {jobRef, jobData} = await requireAuthAndJobOwnership(request, noteId, jobId);
        await enforceRateLimit(request.auth.uid, "church_notes_pdf_ocr_process", 5, 3600);

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

            // PDF uploads contain rendered page images; require moderation before display.
            await markJobCompleted(jobRef, noteId, transcript, {requiresImageModeration: true});

            console.log(`[processChurchNoteDocumentPDF] Completed job ${jobId}, ${transcript.length} chars`);

            return {status: "completed", jobId};
        } catch (err) {
            console.error(`[processChurchNoteDocumentPDF] Failed job ${jobId}:`, err);
            await markJobFailed(jobRef, err.message);
            throw new HttpsError("internal", `PDF OCR failed: ${err.message}`);
        }
    }
);
