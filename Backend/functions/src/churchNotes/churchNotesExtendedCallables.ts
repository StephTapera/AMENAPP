import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { requireAuthAndAppCheck } from "../amenAI/common";
import { enforceRateLimit, RateLimitConfig } from "../rateLimit";

const db = admin.firestore();

const CHURCH_NOTES_RATE_LIMITS: RateLimitConfig[] = [
    { name: "cn_extended_1min", windowMs: 60_000, maxCalls: 8 },
    { name: "cn_extended_1day", windowMs: 86_400_000, maxCalls: 80 },
];

const VALID_ROLES = new Set(["owner", "editor", "commenter", "viewer"]);
const WRITABLE_ROLES = new Set(["owner", "editor"]);

type CollaboratorRole = "owner" | "editor" | "commenter" | "viewer";

async function getFlags(): Promise<Record<string, unknown>> {
    const snap = await db.collection("system").doc("amenAIFlags").get();
    return snap.data() ?? {};
}

async function assertFlagEnabled(flagName: string): Promise<void> {
    const flags = await getFlags();
    if (flags["churchNotesProcessingKillSwitch"] === true) {
        throw new HttpsError("failed-precondition", "Church Notes Intelligence is temporarily unavailable.");
    }
    if (flags[flagName] !== true) {
        throw new HttpsError("failed-precondition", "This Church Notes feature is not enabled.");
    }
}

async function getNote(noteId: string): Promise<admin.firestore.DocumentSnapshot> {
    const noteSnap = await db.collection("churchNotes").doc(noteId).get();
    if (!noteSnap.exists) {
        throw new HttpsError("not-found", "Church note not found.");
    }
    return noteSnap;
}

async function getRole(uid: string, noteId: string): Promise<CollaboratorRole | null> {
    const noteSnap = await getNote(noteId);
    if (noteSnap.data()?.userId === uid) {
        return "owner";
    }

    const collaboratorSnap = await db.collection("churchNotes")
        .doc(noteId)
        .collection("collaborators")
        .doc(uid)
        .get();

    const role = collaboratorSnap.data()?.role;
    return VALID_ROLES.has(role) ? role as CollaboratorRole : null;
}

async function assertRole(uid: string, noteId: string, allowedRoles: Set<string>): Promise<CollaboratorRole> {
    const role = await getRole(uid, noteId);
    if (!role || !allowedRoles.has(role)) {
        throw new HttpsError("permission-denied", "You do not have permission for this church note.");
    }
    return role;
}

async function getJobText(uid: string, noteId: string, jobId: string): Promise<{
    text: string;
    sourceType: string;
    storagePath: string;
}> {
    await assertRole(uid, noteId, WRITABLE_ROLES);

    const jobSnap = await db.collection("churchNotes")
        .doc(noteId)
        .collection("processingJobs")
        .doc(jobId)
        .get();

    if (!jobSnap.exists) {
        throw new HttpsError("not-found", "Processing job not found.");
    }

    const job = jobSnap.data() ?? {};
    const text = String(job.transcriptText ?? job.ocrText ?? "").trim();
    if (text.length < 5) {
        throw new HttpsError("failed-precondition", "No transcript or OCR text is available for this job.");
    }

    return {
        text,
        sourceType: String(job.sourceType ?? "manual"),
        storagePath: String(job.storagePath ?? ""),
    };
}

async function updateJobDraft(
    noteId: string,
    jobId: string,
    fields: Record<string, unknown>,
): Promise<void> {
    await db.collection("churchNotes")
        .doc(noteId)
        .collection("processingJobs")
        .doc(jobId)
        .update({
            ...fields,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
}

async function audit(noteId: string, uid: string, eventType: string, data: Record<string, unknown> = {}): Promise<void> {
    await db.collection("churchNotes")
        .doc(noteId)
        .collection("events")
        .add({
            eventType,
            actorUid: uid,
            data,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
}

function extractActionItems(text: string): string[] {
    const actionPattern = /\b(call|text|email|schedule|meet|follow up|pray for|invite|prepare|bring|assign|visit)\b/i;
    return text
        .split(/\n|(?<=[.!?])\s+/)
        .map((line) => line.trim())
        .filter((line) => line.length >= 8 && actionPattern.test(line))
        .slice(0, 12);
}

function detectScriptureReferences(text: string): Array<{
    reference: string;
    confidence: number;
    isPossible: boolean;
    source: string;
}> {
    const books = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
        "Samuel", "Kings", "Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalm", "Psalms",
        "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
        "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum",
        "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi", "Matthew", "Mark", "Luke",
        "John", "Acts", "Romans", "Corinthians", "Galatians", "Ephesians", "Philippians",
        "Colossians", "Thessalonians", "Timothy", "Titus", "Philemon", "Hebrews", "James",
        "Peter", "Jude", "Revelation",
    ];
    const bookAlternation = books.map((book) => book.replace(/\s+/g, "\\s+")).join("|");
    const referenceRegex = new RegExp(`\\b(?:[1-3]\\s*)?(?:${bookAlternation})\\s+\\d{1,3}:\\d{1,3}(?:-\\d{1,3})?\\b`, "gi");
    const matches = new Set<string>();
    let match = referenceRegex.exec(text);
    while (match) {
        matches.add(match[0].replace(/\s+/g, " ").trim());
        match = referenceRegex.exec(text);
    }

    return Array.from(matches).slice(0, 30).map((reference) => ({
        reference,
        confidence: 0.92,
        isPossible: false,
        source: "transcript_or_ocr",
    }));
}

export const generateChurchNoteActionItems = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("sermonActionExtractionEnabled");

        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId = String(request.data?.jobId ?? "").trim();
        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const { text } = await getJobText(uid, noteId, jobId);
        const actionItems = extractActionItems(text);
        await updateJobDraft(noteId, jobId, {
            actionItemsDraft: actionItems,
            actionItemsDraftLabel: "Suggested action items - review before using",
        });
        await audit(noteId, uid, "action_items_generated", { jobId, count: actionItems.length });

        return { noteId, jobId, actionItems, draftField: "actionItemsDraft" };
    },
);

export const detectChurchNoteScriptures = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("scriptureDetectionEnabled");

        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId = String(request.data?.jobId ?? "").trim();
        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const { text } = await getJobText(uid, noteId, jobId);
        const scriptureReferences = detectScriptureReferences(text);
        await updateJobDraft(noteId, jobId, {
            scriptureReferencesDraft: scriptureReferences,
            scriptureReferencesDraftLabel: "Suggested scripture references - verify before approving",
        });
        await audit(noteId, uid, "scripture_references_detected", { jobId, count: scriptureReferences.length });

        return { noteId, jobId, scriptureReferences, draftField: "scriptureReferencesDraft" };
    },
);

export const translateChurchNoteContent = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("churchNotesTranslationEnabled");

        throw new HttpsError(
            "failed-precondition",
            "Translation provider is not configured for Church Notes Intelligence.",
        );
    },
);

export const regenerateChurchNoteSection = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("churchNotesIntelligenceEnabled");

        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId = String(request.data?.jobId ?? "").trim();
        const draftField = String(request.data?.draftField ?? "").trim();
        if (!noteId || !jobId || !draftField) {
            throw new HttpsError("invalid-argument", "noteId, jobId, and draftField are required.");
        }

        await assertRole(uid, noteId, WRITABLE_ROLES);
        await updateJobDraft(noteId, jobId, {
            [`regenerationRequested_${draftField}`]: true,
            [`regenerationRequestedAt_${draftField}`]: admin.firestore.FieldValue.serverTimestamp(),
        });
        await audit(noteId, uid, "regeneration_requested", { jobId, draftField });

        return { noteId, jobId, draftField, status: "queued_for_regeneration" };
    },
);

export const createChurchNoteClipSuggestions = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("sermonClipSuggestionEnabled");

        const noteId = String(request.data?.noteId ?? "").trim();
        const jobId = String(request.data?.jobId ?? "").trim();
        if (!noteId || !jobId) {
            throw new HttpsError("invalid-argument", "noteId and jobId are required.");
        }

        const job = await getJobText(uid, noteId, jobId);
        if (!["audio", "video"].includes(job.sourceType) || !job.storagePath.startsWith("churchNotes/")) {
            throw new HttpsError("failed-precondition", "Clip suggestions require real uploaded or recorded media.");
        }

        const suggestions = extractActionItems(job.text).slice(0, 5).map((label, index) => ({
            label,
            source: "real_uploaded_media",
            confidence: 0.62,
            requiresUserTimestampReview: true,
            ordinal: index,
        }));

        await updateJobDraft(noteId, jobId, {
            clipSuggestionsDraft: suggestions,
            clipSuggestionsDraftLabel: "Suggested clip moments from real media - review timestamps before publishing",
        });
        await audit(noteId, uid, "clip_suggestions_generated", { jobId, count: suggestions.length });

        return { noteId, jobId, clipSuggestions: suggestions, draftField: "clipSuggestionsDraft" };
    },
);

export const shareChurchNoteWithCollaborators = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("churchNotesCollaborationEnabled");

        const noteId = String(request.data?.noteId ?? "").trim();
        const collaboratorUid = String(request.data?.collaboratorUid ?? "").trim();
        const role = String(request.data?.role ?? "viewer").trim();
        if (!noteId || !collaboratorUid || !VALID_ROLES.has(role) || role === "owner") {
            throw new HttpsError("invalid-argument", "Valid noteId, collaboratorUid, and non-owner role are required.");
        }

        await assertRole(uid, noteId, new Set(["owner"]));
        await db.collection("churchNotes").doc(noteId).collection("collaborators").doc(collaboratorUid).set({
            uid: collaboratorUid,
            role,
            addedBy: uid,
            addedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await audit(noteId, uid, "collaborator_added", { collaboratorUid, role });

        return { noteId, collaboratorUid, role, status: "shared" };
    },
);

export const updateChurchNotePermissions = onCall(
    { enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        const uid = await requireAuthAndAppCheck(request.auth, request.app);
        await enforceRateLimit(uid, CHURCH_NOTES_RATE_LIMITS);
        await assertFlagEnabled("churchNotesCollaborationEnabled");

        const noteId = String(request.data?.noteId ?? "").trim();
        const collaboratorUid = String(request.data?.collaboratorUid ?? "").trim();
        const role = String(request.data?.role ?? "").trim();
        const remove = request.data?.remove === true;
        if (!noteId || !collaboratorUid) {
            throw new HttpsError("invalid-argument", "noteId and collaboratorUid are required.");
        }
        if (!remove && (!VALID_ROLES.has(role) || role === "owner")) {
            throw new HttpsError("invalid-argument", "A valid non-owner role is required.");
        }

        await assertRole(uid, noteId, new Set(["owner"]));
        const collaboratorRef = db.collection("churchNotes").doc(noteId).collection("collaborators").doc(collaboratorUid);
        if (remove) {
            await collaboratorRef.delete();
            await audit(noteId, uid, "collaborator_removed", { collaboratorUid });
            return { noteId, collaboratorUid, status: "removed" };
        }

        await collaboratorRef.set({
            uid: collaboratorUid,
            role,
            updatedBy: uid,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await audit(noteId, uid, "permission_changed", { collaboratorUid, role });

        return { noteId, collaboratorUid, role, status: "updated" };
    },
);
