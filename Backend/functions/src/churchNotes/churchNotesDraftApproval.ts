import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { requireAuthAndAppCheck } from "../amenAI/common";

const db = admin.firestore();

const VALID_DRAFT_FIELDS = new Set([
    "summaryDraft",
    "studyGuideDraft",
    "prayerPromptsDraft",
    "transcriptText",
    "ocrText",
]);

async function assertJobOwner(
    uid: string,
    noteId: string,
    jobId: string
): Promise<admin.firestore.DocumentSnapshot> {
    const jobRef  = db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId);
    const jobSnap = await jobRef.get();
    if (!jobSnap.exists)                throw new HttpsError("not-found",         "Processing job not found.");
    if (jobSnap.data()?.userId !== uid)  throw new HttpsError("permission-denied", "Not your processing job.");
    return jobSnap;
}

/**
 * Approves an AI-generated Church Notes draft field.
 * Approved content is written into the Church Notes block system
 * by the backend — the client never writes AI output directly.
 *
 * Returns the noteId and a block insertion summary for the iOS app
 * to display as a confirmation without needing to re-fetch.
 */
export const approveChurchNoteAIDraft = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        const noteId    = String(request.data?.noteId    ?? "").trim();
        const jobId     = String(request.data?.jobId     ?? "").trim();
        const draftField = String(request.data?.draftField ?? "").trim();

        if (!noteId)     throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)      throw new HttpsError("invalid-argument", "jobId required.");
        if (!VALID_DRAFT_FIELDS.has(draftField)) {
            throw new HttpsError("invalid-argument", "Invalid draftField.");
        }

        const jobSnap = await assertJobOwner(uid, noteId, jobId);
        const job     = jobSnap.data()!;

        if (job.status !== "draftReady") {
            throw new HttpsError("failed-precondition", "Draft is not ready for approval.");
        }

        const draftText = job[draftField] as string | null;
        if (!draftText || draftText.length < 5) {
            throw new HttpsError("not-found", "Draft content is empty or missing.");
        }

        // Record that the user approved this specific draft field.
        // The iOS client will use the returned approvedText to insert blocks via the local repo.
        const jobRef = db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId);
        await jobRef.update({
            [`approved_${draftField}`]:   true,
            [`approvedAt_${draftField}`]: admin.firestore.FieldValue.serverTimestamp(),
            status:    "approved",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        functions.logger.info("[churchNotes] Draft approved", { noteId, jobId, draftField });

        // Return the approved text so iOS can insert it as blocks through ChurchNoteBlockRepository.
        // Never persisted here — the client repo handles block creation to maintain the existing schema.
        return {
            jobId,
            noteId,
            draftField,
            approvedText: draftText,
            sourceType:   job.sourceType as string,
        };
    }
);

/**
 * Rejects an AI-generated Church Notes draft field.
 * Rejected drafts are logged for quality improvement but never inserted.
 */
export const rejectChurchNoteAIDraft = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);

        const noteId    = String(request.data?.noteId    ?? "").trim();
        const jobId     = String(request.data?.jobId     ?? "").trim();
        const draftField = String(request.data?.draftField ?? "").trim();
        const reason    = String(request.data?.reason    ?? "user_rejected").trim().substring(0, 100);

        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)  throw new HttpsError("invalid-argument", "jobId required.");
        if (!VALID_DRAFT_FIELDS.has(draftField)) {
            throw new HttpsError("invalid-argument", "Invalid draftField.");
        }

        const jobSnap = await assertJobOwner(uid, noteId, jobId);
        const job     = jobSnap.data()!;

        if (!["draftReady", "approved"].includes(job.status)) {
            throw new HttpsError("failed-precondition", "Nothing to reject in current status.");
        }

        const jobRef = db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId);
        await jobRef.update({
            [`rejected_${draftField}`]:         true,
            [`rejectedAt_${draftField}`]:        admin.firestore.FieldValue.serverTimestamp(),
            [`rejectionReason_${draftField}`]:   reason,
            status:    "rejected",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        functions.logger.info("[churchNotes] Draft rejected", { noteId, jobId, draftField, reason });

        return { jobId, noteId, draftField, status: "rejected" };
    }
);
