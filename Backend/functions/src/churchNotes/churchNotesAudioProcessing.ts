import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import axios from "axios";
import FormData from "form-data";
import { requireAuthAndAppCheck, lightweightModeration } from "../amenAI/common";

const db      = admin.firestore();
const storage = admin.storage();

const openAiApiKey = defineSecret("OPENAI_API_KEY");

const MAX_TRANSCRIPT_CHARS = 80_000;

async function assertJobOwner(uid: string, noteId: string, jobId: string): Promise<admin.firestore.DocumentSnapshot> {
    const jobRef  = db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId);
    const jobSnap = await jobRef.get();
    if (!jobSnap.exists)           throw new HttpsError("not-found",         "Processing job not found.");
    if (jobSnap.data()?.userId !== uid) throw new HttpsError("permission-denied", "Not your processing job.");
    return jobSnap;
}

async function updateJob(noteId: string, jobId: string, fields: Record<string, unknown>): Promise<void> {
    await db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId).update({
        ...fields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

/**
 * Transcribes the audio file referenced by a processing job using OpenAI Whisper.
 * Ownership and kill-switch are validated server-side.
 * Raw transcript text is stored server-side only and never logged.
 */
export const processChurchNoteAudio = onCall(
    {
        enforceAppCheck: true,
        timeoutSeconds: 540,
        memory: "1GiB",
        secrets: [openAiApiKey],
    },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId  = String(request.data?.jobId  ?? "").trim();
        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)  throw new HttpsError("invalid-argument", "jobId required.");

        // Feature flag / kill switch — re-checked server-side on every call.
        const flagSnap = await db.collection("system").doc("amenAIFlags").get();
        const flags    = flagSnap.data() ?? {};
        if (flags["churchNotesProcessingKillSwitch"] === true) {
            throw new HttpsError("failed-precondition", "Audio processing is temporarily unavailable.");
        }
        if (flags["churchNotesAudioCaptureEnabled"] !== true) {
            throw new HttpsError("failed-precondition", "Audio capture is not enabled.");
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

        await updateJob(noteId, jobId, { status: "processing", progress: 5 });

        let transcript: string;
        try {
            const [signedUrls] = await storage.bucket().file(storagePath).getSignedUrl({
                action:  "read",
                expires: Date.now() + 10 * 60 * 1000, // 10-minute URL
            });
            const signedUrl = signedUrls;

            // Download audio bytes so Whisper receives the actual file.
            const audioResponse = await axios.get(signedUrl, { responseType: "arraybuffer", timeout: 120_000 });
            const audioBuffer   = Buffer.from(audioResponse.data as ArrayBuffer);

            await updateJob(noteId, jobId, { progress: 20 });

            // Determine content type from path extension.
            const ext         = storagePath.split(".").pop()?.toLowerCase() ?? "m4a";
            const contentType = ext === "mp3" ? "audio/mpeg" : ext === "wav" ? "audio/wav" : "audio/mp4";

            const form = new FormData();
            form.append("file", audioBuffer, { filename: `audio.${ext}`, contentType });
            form.append("model",          "whisper-1");
            form.append("response_format", "verbose_json");
            form.append("temperature",    "0");

            const whisperRes = await axios.post(
                "https://api.openai.com/v1/audio/transcriptions",
                form,
                {
                    headers: {
                        ...form.getHeaders(),
                        Authorization: `Bearer ${openAiApiKey.value()}`,
                    },
                    timeout: 420_000,
                    maxBodyLength: Infinity,
                }
            );

            const text: string = whisperRes.data?.text ?? "";
            transcript = text.substring(0, MAX_TRANSCRIPT_CHARS);
        } catch (err) {
            functions.logger.error("[churchNotes] Audio transcription failed", {
                noteId,
                jobId,
                errorCode: (err as NodeJS.ErrnoException)?.code ?? "unknown",
            });
            await updateJob(noteId, jobId, {
                status:       "failed",
                errorCode:    "transcription_failed",
                errorMessage: "Audio could not be transcribed. Please try again.",
                completedAt:  admin.firestore.FieldValue.serverTimestamp(),
            });
            throw new HttpsError("internal", "Audio transcription failed.");
        }

        await updateJob(noteId, jobId, { progress: 80 });

        // Lightweight safety check on the transcript before storing.
        const safetyCheck = lightweightModeration(transcript);
        const safetyStatus = safetyCheck.ok ? "passed" : "flagged";

        // Store transcript server-side only. Never log raw content.
        await updateJob(noteId, jobId, {
            status:        "draftReady",
            progress:      100,
            transcriptText: transcript,
            safetyStatus,
            moderationStatus: "reviewed",
            completedAt:   admin.firestore.FieldValue.serverTimestamp(),
        });

        functions.logger.info("[churchNotes] Audio processed", { noteId, jobId, safetyStatus });

        return { jobId, noteId, status: "draftReady" };
    }
);
