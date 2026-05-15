import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import axios from "axios";
import { requireAuthAndAppCheck, lightweightModeration } from "../amenAI/common";
import { enforceRateLimit, RateLimitConfig } from "../rateLimit";

const db = admin.firestore();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const GENERATION_RATE_LIMITS: RateLimitConfig[] = [
    { name: "cn_gen_1min", windowMs: 60_000,      maxCalls: 5  },
    { name: "cn_gen_1day", windowMs: 86_400_000,  maxCalls: 30 },
];

const MAX_INPUT_CHARS  = 60_000;
const MAX_OUTPUT_CHARS = 8_000;
const ANTHROPIC_MODEL  = "claude-haiku-4-5-20251001";

async function assertNoteOwner(uid: string, noteId: string): Promise<void> {
    const noteSnap = await db.collection("churchNotes").doc(noteId).get();
    if (!noteSnap.exists)                 throw new HttpsError("not-found",         "Church note not found.");
    if (noteSnap.data()?.userId !== uid)   throw new HttpsError("permission-denied", "Not your church note.");
}

async function assertApprovedDraftOrTranscript(noteId: string, jobId: string): Promise<string> {
    const jobRef  = db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId);
    const jobSnap = await jobRef.get();
    if (!jobSnap.exists) throw new HttpsError("not-found", "Processing job not found.");

    const job = jobSnap.data()!;
    // Require a user-approved draft OR a completed transcript/OCR before generating.
    const hasTranscript = typeof job.transcriptText === "string" && job.transcriptText.length > 50;
    const hasOCR        = typeof job.ocrText        === "string" && job.ocrText.length > 20;
    if (!hasTranscript && !hasOCR) {
        throw new HttpsError("failed-precondition", "Job has no usable transcript or OCR text yet.");
    }

    const sourceText = (job.transcriptText ?? job.ocrText) as string;
    return sourceText.substring(0, MAX_INPUT_CHARS);
}

async function callAnthropic(prompt: string, systemPrompt: string): Promise<string> {
    const response = await axios.post(
        "https://api.anthropic.com/v1/messages",
        {
            model:      ANTHROPIC_MODEL,
            max_tokens: 2048,
            system:     systemPrompt,
            messages:   [{ role: "user", content: prompt }],
        },
        {
            headers: {
                "x-api-key":         anthropicApiKey.value(),
                "anthropic-version": "2023-06-01",
                "Content-Type":      "application/json",
            },
            timeout: 60_000,
        }
    );

    const text: string = response.data?.content?.[0]?.text ?? "";
    return text.substring(0, MAX_OUTPUT_CHARS);
}

async function storeDraft(
    noteId: string,
    jobId: string,
    draftField: string,
    draftText: string
): Promise<void> {
    await db.collection("churchNotes").doc(noteId).collection("processingJobs").doc(jobId).update({
        [draftField]: draftText,
        updatedAt:    admin.firestore.FieldValue.serverTimestamp(),
    });
}

// ---------------------------------------------------------------------------
// generateChurchNoteSummary
// ---------------------------------------------------------------------------

export const generateChurchNoteSummary = onCall(
    { enforceAppCheck: true, timeoutSeconds: 90, memory: "512MiB", secrets: [anthropicApiKey] },
    async (request) => {
        const uid    = await requireAuthAndAppCheck(request.auth, request.app);
        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId  = String(request.data?.jobId  ?? "").trim();
        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)  throw new HttpsError("invalid-argument", "jobId required.");

        const flagSnap = await db.collection("system").doc("amenAIFlags").get();
        if (flagSnap.data()?.["churchNotesProcessingKillSwitch"] === true) {
            throw new HttpsError("failed-precondition", "Summary generation is temporarily unavailable.");
        }

        await enforceRateLimit(uid, GENERATION_RATE_LIMITS);
        await assertNoteOwner(uid, noteId);
        const sourceText = await assertApprovedDraftOrTranscript(noteId, jobId);

        const systemPrompt = [
            "You are a careful, humble assistant that helps Christians capture sermon insights.",
            "Your summaries are faithful to the source material. You do not add theological claims",
            "not present in the text. You label uncertainty clearly.",
            "Spiritual interpretation is always presented as suggestion, never as definitive truth.",
            "Never fabricate scripture references. If a reference seems present, note it with low confidence.",
            "Format as plain text with brief sections: Main Theme, Key Points (3-5), Reflection.",
        ].join(" ");

        const prompt = [
            "Summarize this sermon/study transcript. Keep it concise and faithful to what was said.",
            "Do not invent content. Clearly label any scripture references as 'possibly referenced'.",
            "\n\n--- SOURCE TRANSCRIPT START ---\n",
            sourceText,
            "\n--- SOURCE TRANSCRIPT END ---",
        ].join("");

        let draft: string;
        try {
            draft = await callAnthropic(prompt, systemPrompt);
        } catch (err) {
            functions.logger.error("[churchNotes] Summary generation failed", { noteId, jobId });
            throw new HttpsError("internal", "Summary generation failed. Please try again.");
        }

        const safety = lightweightModeration(draft);
        if (!safety.ok) {
            throw new HttpsError("failed-precondition", "Generated content did not pass safety review.");
        }

        await storeDraft(noteId, jobId, "summaryDraft", draft);

        functions.logger.info("[churchNotes] Summary generated", { noteId, jobId });
        return { jobId, noteId, draftField: "summaryDraft" };
    }
);

// ---------------------------------------------------------------------------
// generateChurchNoteStudyGuide
// ---------------------------------------------------------------------------

export const generateChurchNoteStudyGuide = onCall(
    { enforceAppCheck: true, timeoutSeconds: 90, memory: "512MiB", secrets: [anthropicApiKey] },
    async (request) => {
        const uid    = await requireAuthAndAppCheck(request.auth, request.app);
        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId  = String(request.data?.jobId  ?? "").trim();
        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)  throw new HttpsError("invalid-argument", "jobId required.");

        const flagSnap = await db.collection("system").doc("amenAIFlags").get();
        const flags    = flagSnap.data() ?? {};
        if (flags["churchNotesProcessingKillSwitch"] === true) {
            throw new HttpsError("failed-precondition", "Study guide generation is temporarily unavailable.");
        }
        if (flags["churchNotesStudyGuideEnabled"] !== true) {
            throw new HttpsError("failed-precondition", "Study guide generation is not enabled.");
        }

        await enforceRateLimit(uid, GENERATION_RATE_LIMITS);
        await assertNoteOwner(uid, noteId);
        const sourceText = await assertApprovedDraftOrTranscript(noteId, jobId);

        const systemPrompt = [
            "You are a thoughtful assistant helping small groups engage with sermon content.",
            "Create open-ended discussion questions that help people reflect — not debate.",
            "Do not present AI-generated content as Scripture. Label all theological content as suggested reflection.",
            "Format: Introduction (1-2 sentences), Discussion Questions (5-7), Personal Application (2-3 prompts),",
            "Closing Prayer Prompt (optional). Plain text only.",
        ].join(" ");

        const prompt = [
            "Create a small group study guide from this sermon/study transcript.",
            "Questions should be open-ended, pastoral in tone, and faithful to the source material.",
            "\n\n--- SOURCE TRANSCRIPT START ---\n",
            sourceText,
            "\n--- SOURCE TRANSCRIPT END ---",
        ].join("");

        let draft: string;
        try {
            draft = await callAnthropic(prompt, systemPrompt);
        } catch (err) {
            functions.logger.error("[churchNotes] Study guide generation failed", { noteId, jobId });
            throw new HttpsError("internal", "Study guide generation failed. Please try again.");
        }

        const safety = lightweightModeration(draft);
        if (!safety.ok) {
            throw new HttpsError("failed-precondition", "Generated content did not pass safety review.");
        }

        await storeDraft(noteId, jobId, "studyGuideDraft", draft);

        functions.logger.info("[churchNotes] Study guide generated", { noteId, jobId });
        return { jobId, noteId, draftField: "studyGuideDraft" };
    }
);

// ---------------------------------------------------------------------------
// generateChurchNotePrayerPrompts
// ---------------------------------------------------------------------------

export const generateChurchNotePrayerPrompts = onCall(
    { enforceAppCheck: true, timeoutSeconds: 90, memory: "512MiB", secrets: [anthropicApiKey] },
    async (request) => {
        const uid    = await requireAuthAndAppCheck(request.auth, request.app);
        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId  = String(request.data?.jobId  ?? "").trim();
        if (!noteId) throw new HttpsError("invalid-argument", "noteId required.");
        if (!jobId)  throw new HttpsError("invalid-argument", "jobId required.");

        const flagSnap = await db.collection("system").doc("amenAIFlags").get();
        const flags    = flagSnap.data() ?? {};
        if (flags["churchNotesProcessingKillSwitch"] === true) {
            throw new HttpsError("failed-precondition", "Prayer prompt generation is temporarily unavailable.");
        }
        if (flags["churchNotesPrayerPromptsEnabled"] !== true) {
            throw new HttpsError("failed-precondition", "Prayer prompt generation is not enabled.");
        }

        await enforceRateLimit(uid, GENERATION_RATE_LIMITS);
        await assertNoteOwner(uid, noteId);
        const sourceText = await assertApprovedDraftOrTranscript(noteId, jobId);

        const systemPrompt = [
            "You are a gentle, pastoral assistant creating personal prayer prompts from sermon content.",
            "Prayer prompts are personal and humble — they invite the user to bring themes to God themselves.",
            "Do not write prayers on the user's behalf. Write prompts like: 'Bring this to God...' or 'Ask Him...'",
            "Do not make theological claims. Keep language personal and reflective.",
            "Format: 3-5 prayer prompts, each 1-3 sentences. Plain text.",
        ].join(" ");

        const prompt = [
            "Generate personal prayer prompts inspired by this sermon/study transcript.",
            "Help the reader bring the themes personally to God. Do not write the prayer for them.",
            "\n\n--- SOURCE TRANSCRIPT START ---\n",
            sourceText,
            "\n--- SOURCE TRANSCRIPT END ---",
        ].join("");

        let draft: string;
        try {
            draft = await callAnthropic(prompt, systemPrompt);
        } catch (err) {
            functions.logger.error("[churchNotes] Prayer prompts generation failed", { noteId, jobId });
            throw new HttpsError("internal", "Prayer prompt generation failed. Please try again.");
        }

        const safety = lightweightModeration(draft);
        if (!safety.ok) {
            throw new HttpsError("failed-precondition", "Generated content did not pass safety review.");
        }

        await storeDraft(noteId, jobId, "prayerPromptsDraft", draft);

        functions.logger.info("[churchNotes] Prayer prompts generated", { noteId, jobId });
        return { jobId, noteId, draftField: "prayerPromptsDraft" };
    }
);
