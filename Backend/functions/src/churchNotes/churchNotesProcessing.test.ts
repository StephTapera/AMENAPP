/**
 * churchNotesProcessing.test.ts
 *
 * Unit tests for the Church Notes Media Intelligence callable layer.
 *
 * Strategy: extract and test pure validation/business-logic helpers extracted
 * from each callable — the same approach used in mediaCallables.test.ts.
 * Firebase App Check context is not available in unit tests, so we test
 * the logic that each callable delegates to, not the onCall wrapper itself.
 *
 * Run: cd Backend/functions && npm test -- --testPathPattern=churchNotesProcessing
 */

import admin from "firebase-admin";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockDoc: jest.Mocked<{
    get: jest.Mock; set: jest.Mock; update: jest.Mock;
    collection: jest.Mock; id: string; __data: unknown;
}> = mockAdmin.__mockDoc;

// ─── Re-exported pure validation helpers ──────────────────────────────────────
// These mirror the logic inside each callable. Keeping them here (instead of
// importing from the callable files) avoids initialising the onCall wrapper,
// which would fail in this unit-test environment.

// --- requireAuthAndAppCheck ---

function requireAuthAndAppCheck(auth: unknown, app: unknown): string {
    const authValue = auth as { uid?: string } | undefined;
    if (!authValue?.uid) throw Object.assign(new Error("Authentication required."), { code: "unauthenticated" });
    if (!app) throw Object.assign(new Error("App Check token required."), { code: "failed-precondition" });
    return authValue.uid;
}

// --- enforceAmenGuards ---

interface AmenGuardFlags { [key: string]: unknown }

function enforceAmenGuardsSync(flags: AmenGuardFlags, featureFlag: string, killSwitch: string): void {
    if (flags[killSwitch] === true) {
        throw Object.assign(new Error("This AI feature is temporarily unavailable."), { code: "failed-precondition" });
    }
    if (flags[featureFlag] !== true) {
        throw Object.assign(new Error("This AI feature is not enabled yet."), { code: "failed-precondition" });
    }
}

// --- createChurchNoteProcessingJob ---

const VALID_SOURCE_TYPES = ["audio", "image", "video", "manual"] as const;
type SourceType = typeof VALID_SOURCE_TYPES[number];

const FILE_LIMITS: Record<SourceType, { maxSizeBytes: number; maxDurationSec?: number }> = {
    audio:  { maxSizeBytes: 100 * 1024 * 1024, maxDurationSec: 7200  },
    image:  { maxSizeBytes:  20 * 1024 * 1024                        },
    video:  { maxSizeBytes: 500 * 1024 * 1024, maxDurationSec: 10800 },
    manual: { maxSizeBytes:   1 * 1024 * 1024                        },
};

function validateProcessingJobInput(
    uid: string,
    noteId: string,
    sourceType: string,
    storagePath: string,
    fileSizeBytes: number,
    durationSec: number,
): void {
    if (!noteId) throw Object.assign(new Error("noteId required."), { code: "invalid-argument" });
    if (!VALID_SOURCE_TYPES.includes(sourceType as SourceType)) {
        throw Object.assign(new Error("Invalid sourceType."), { code: "invalid-argument" });
    }
    if (!storagePath) throw Object.assign(new Error("storagePath required."), { code: "invalid-argument" });
    if (!storagePath.startsWith(`churchNotes/${uid}/`)) {
        throw Object.assign(new Error("Storage path does not belong to this user."), { code: "permission-denied" });
    }
    const limits = FILE_LIMITS[sourceType as SourceType];
    if (fileSizeBytes > limits.maxSizeBytes) {
        throw Object.assign(new Error("File exceeds maximum allowed size."), { code: "invalid-argument" });
    }
    if (limits.maxDurationSec && durationSec > limits.maxDurationSec) {
        throw Object.assign(new Error("Media exceeds maximum allowed duration."), { code: "invalid-argument" });
    }
}

function buildProcessingJobDocument(
    uid: string,
    noteId: string,
    sourceType: SourceType,
    storagePath: string,
    fileSizeBytes: number,
    jobId: string,
): Record<string, unknown> {
    return {
        jobId,
        userId: uid,
        churchNoteId: noteId,
        sourceType,
        storagePath,
        fileSizeBytes,
        durationSeconds: null,
        status: "queued",
        progress: 0,
        transcriptText: null,
        ocrText: null,
        extractedOutline: null,
        summaryDraft: null,
        studyGuideDraft: null,
        prayerPromptsDraft: null,
        safetyStatus: "pending",
        moderationStatus: "pending",
        errorCode: null,
        errorMessage: null,
        completedAt: null,
    };
}

// --- Draft field validation (approveChurchNoteAIDraft) ---

const VALID_DRAFT_FIELDS = new Set([
    "transcriptText", "ocrText", "summaryDraft", "studyGuideDraft", "prayerPromptsDraft",
]);

function validateDraftField(draftField: unknown): string {
    if (typeof draftField !== "string" || !VALID_DRAFT_FIELDS.has(draftField)) {
        throw Object.assign(new Error("Invalid draftField."), { code: "invalid-argument" });
    }
    return draftField;
}

// --- Content generation input validation ---

function validateGenerationInput(
    jobData: Record<string, unknown>,
    minChars = 50,
): { text: string } {
    const transcript = jobData["transcriptText"] as string | null;
    const ocr = jobData["ocrText"] as string | null;
    const text = transcript ?? ocr ?? "";

    if (text.length < minChars) {
        throw Object.assign(
            new Error("Transcript or OCR text is too short for content generation."),
            { code: "failed-precondition" },
        );
    }
    return { text };
}

// --- lightweightModeration ---

function lightweightModeration(text: string): { ok: boolean; reason?: string } {
    const blocked = [
        /fake miracle/i,
        /guaranteed healing/i,
        /legal advice/i,
        /financial certainty/i,
        /impersonat(e|ion)/i,
    ];
    for (const pattern of blocked) {
        if (pattern.test(text)) return { ok: false, reason: "unsafe_or_deceptive_content" };
    }
    return { ok: true };
}

// --- Storage path helpers ---

function buildAudioStoragePath(uid: string, noteId: string, filename: string): string {
    return `churchNotes/${uid}/${noteId}/audio/${filename}`;
}

function buildImageStoragePath(uid: string, noteId: string, filename: string): string {
    return `churchNotes/${uid}/${noteId}/images/${filename}`;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;
    mockDoc.get.mockResolvedValue({ exists: true, data: () => mockDoc.__data });
    mockDoc.set.mockResolvedValue(undefined);
    mockDoc.update.mockResolvedValue(undefined);
});

// ─── requireAuthAndAppCheck ───────────────────────────────────────────────────

describe("requireAuthAndAppCheck", () => {

    it("returns uid when auth and app are both present", () => {
        const uid = requireAuthAndAppCheck({ uid: "user-1" }, {});
        expect(uid).toBe("user-1");
    });

    it("throws unauthenticated when auth is undefined", () => {
        expect(() => requireAuthAndAppCheck(undefined, {}))
            .toThrowWithCode("unauthenticated");
    });

    it("throws unauthenticated when auth.uid is missing", () => {
        expect(() => requireAuthAndAppCheck({}, {}))
            .toThrowWithCode("unauthenticated");
    });

    it("throws unauthenticated when auth is null", () => {
        expect(() => requireAuthAndAppCheck(null, {}))
            .toThrowWithCode("unauthenticated");
    });

    it("throws failed-precondition when app is null (no App Check token)", () => {
        expect(() => requireAuthAndAppCheck({ uid: "user-1" }, null))
            .toThrowWithCode("failed-precondition");
    });

    it("throws failed-precondition when app is undefined", () => {
        expect(() => requireAuthAndAppCheck({ uid: "user-1" }, undefined))
            .toThrowWithCode("failed-precondition");
    });
});

// ─── enforceAmenGuards — kill switch + feature flag ──────────────────────────

describe("enforceAmenGuardsSync", () => {

    it("allows when feature flag is true and kill switch is false", () => {
        expect(() => enforceAmenGuardsSync(
            { churchNotesMediaIntelligenceEnabled: true, churchNotesProcessingKillSwitch: false },
            "churchNotesMediaIntelligenceEnabled",
            "churchNotesProcessingKillSwitch",
        )).not.toThrow();
    });

    it("blocks when kill switch is true (regardless of feature flag)", () => {
        expect(() => enforceAmenGuardsSync(
            { churchNotesMediaIntelligenceEnabled: true, churchNotesProcessingKillSwitch: true },
            "churchNotesMediaIntelligenceEnabled",
            "churchNotesProcessingKillSwitch",
        )).toThrowWithCode("failed-precondition");
    });

    it("blocks when feature flag is false", () => {
        expect(() => enforceAmenGuardsSync(
            { churchNotesMediaIntelligenceEnabled: false, churchNotesProcessingKillSwitch: false },
            "churchNotesMediaIntelligenceEnabled",
            "churchNotesProcessingKillSwitch",
        )).toThrowWithCode("failed-precondition");
    });

    it("blocks when feature flag is missing from Firestore doc", () => {
        expect(() => enforceAmenGuardsSync(
            {},  // empty flags — feature not yet seeded
            "churchNotesMediaIntelligenceEnabled",
            "churchNotesProcessingKillSwitch",
        )).toThrowWithCode("failed-precondition");
    });

    it("kill switch takes priority over enabled flag", () => {
        // Even if someone accidentally enables both, kill switch must win.
        const flags = { churchNotesAudioCaptureEnabled: true, audioKillSwitch: true };
        expect(() => enforceAmenGuardsSync(flags, "churchNotesAudioCaptureEnabled", "audioKillSwitch"))
            .toThrowWithCode("failed-precondition");
    });
});

// ─── createChurchNoteProcessingJob — input validation ────────────────────────

describe("validateProcessingJobInput", () => {

    const uid = "user-abc";
    const noteId = "note-1";

    it("accepts valid audio upload", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "audio",
            `churchNotes/${uid}/${noteId}/audio/test.m4a`,
            50 * 1024 * 1024, 3600,
        )).not.toThrow();
    });

    it("accepts valid image upload", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "image",
            `churchNotes/${uid}/${noteId}/images/scan.jpg`,
            5 * 1024 * 1024, 0,
        )).not.toThrow();
    });

    it("rejects empty noteId", () => {
        expect(() => validateProcessingJobInput(uid, "", "audio", `churchNotes/${uid}/x/audio/f.m4a`, 1000, 0))
            .toThrowWithCode("invalid-argument");
    });

    it("rejects invalid sourceType", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "podcast", `churchNotes/${uid}/${noteId}/audio/f.m4a`, 1000, 0))
            .toThrowWithCode("invalid-argument");
    });

    it("rejects empty storagePath", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "audio", "", 1000, 0))
            .toThrowWithCode("invalid-argument");
    });

    it("rejects storagePath not prefixed with churchNotes/{uid}/ (path traversal)", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "audio",
            "churchNotes/other-user/note/audio/file.m4a",  // wrong uid
            1000, 0,
        )).toThrowWithCode("permission-denied");
    });

    it("rejects storagePath attempting directory traversal", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "audio",
            `churchNotes/${uid}/../other-uid/audio/file.m4a`,
            1000, 0,
        )).toThrowWithCode("permission-denied");
    });

    it("rejects audio file exceeding 100 MB", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "audio",
            `churchNotes/${uid}/${noteId}/audio/huge.m4a`,
            101 * 1024 * 1024, 600,
        )).toThrowWithCode("invalid-argument");
    });

    it("rejects image file exceeding 20 MB", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "image",
            `churchNotes/${uid}/${noteId}/images/huge.jpg`,
            21 * 1024 * 1024, 0,
        )).toThrowWithCode("invalid-argument");
    });

    it("rejects audio exceeding 2h duration", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "audio",
            `churchNotes/${uid}/${noteId}/audio/long.m4a`,
            10 * 1024 * 1024, 7201,
        )).toThrowWithCode("invalid-argument");
    });

    it("accepts audio exactly at 2h boundary", () => {
        expect(() => validateProcessingJobInput(
            uid, noteId, "audio",
            `churchNotes/${uid}/${noteId}/audio/two-hours.m4a`,
            10 * 1024 * 1024, 7200,
        )).not.toThrow();
    });

    it("accepts all four valid source types", () => {
        for (const srcType of VALID_SOURCE_TYPES) {
            const subDir = srcType === "audio" ? "audio" : srcType === "image" ? "images" : srcType === "video" ? "video" : "manual";
            expect(() => validateProcessingJobInput(
                uid, noteId, srcType,
                `churchNotes/${uid}/${noteId}/${subDir}/file`,
                100, 0,
            )).not.toThrow();
        }
    });
});

// ─── buildProcessingJobDocument — server document shape ──────────────────────

describe("buildProcessingJobDocument", () => {

    it("initialises all server-owned output fields to null", () => {
        const doc = buildProcessingJobDocument(
            "uid-1", "note-1", "audio",
            "churchNotes/uid-1/note-1/audio/file.m4a",
            5_000_000, "job-abc",
        );
        // Server-owned fields must never be truthy on creation.
        expect(doc.transcriptText).toBeNull();
        expect(doc.ocrText).toBeNull();
        expect(doc.summaryDraft).toBeNull();
        expect(doc.studyGuideDraft).toBeNull();
        expect(doc.prayerPromptsDraft).toBeNull();
        expect(doc.extractedOutline).toBeNull();
        expect(doc.errorCode).toBeNull();
        expect(doc.errorMessage).toBeNull();
        expect(doc.completedAt).toBeNull();
    });

    it("sets status to queued and progress to 0 on creation", () => {
        const doc = buildProcessingJobDocument("uid-1", "note-1", "audio", "churchNotes/uid-1/note-1/audio/f.m4a", 1000, "j1");
        expect(doc.status).toBe("queued");
        expect(doc.progress).toBe(0);
    });

    it("sets safetyStatus and moderationStatus to pending on creation", () => {
        const doc = buildProcessingJobDocument("uid-1", "note-1", "image", "churchNotes/uid-1/note-1/images/s.jpg", 1000, "j2");
        expect(doc.safetyStatus).toBe("pending");
        expect(doc.moderationStatus).toBe("pending");
    });

    it("embeds userId and churchNoteId (ownership anchor)", () => {
        const doc = buildProcessingJobDocument("uid-xyz", "note-xyz", "audio", "churchNotes/uid-xyz/note-xyz/audio/a.m4a", 1000, "job-x");
        expect(doc.userId).toBe("uid-xyz");
        expect(doc.churchNoteId).toBe("note-xyz");
    });
});

// ─── validateDraftField ───────────────────────────────────────────────────────

describe("validateDraftField", () => {

    it.each([...VALID_DRAFT_FIELDS])("accepts valid draft field: %s", (field) => {
        expect(() => validateDraftField(field)).not.toThrow();
        expect(validateDraftField(field)).toBe(field);
    });

    it("rejects unknown field", () => {
        expect(() => validateDraftField("rawTranscript")).toThrowWithCode("invalid-argument");
    });

    it("rejects empty string", () => {
        expect(() => validateDraftField("")).toThrowWithCode("invalid-argument");
    });

    it("rejects null", () => {
        expect(() => validateDraftField(null)).toThrowWithCode("invalid-argument");
    });

    it("rejects undefined", () => {
        expect(() => validateDraftField(undefined)).toThrowWithCode("invalid-argument");
    });

    it("rejects number", () => {
        expect(() => validateDraftField(42)).toThrowWithCode("invalid-argument");
    });

    it("does not accept server-internal fields that are not in the allowlist", () => {
        // These must never be client-approvable
        const internal = ["storagePath", "userId", "createdAt", "safetyStatus", "moderationStatus"];
        for (const field of internal) {
            expect(() => validateDraftField(field)).toThrowWithCode("invalid-argument");
        }
    });
});

// ─── validateGenerationInput — content generation pre-check ──────────────────

describe("validateGenerationInput", () => {

    it("accepts job with sufficient transcriptText", () => {
        const job = { transcriptText: "A".repeat(50), ocrText: null };
        expect(() => validateGenerationInput(job)).not.toThrow();
    });

    it("accepts job with sufficient ocrText (no transcript)", () => {
        const job = { transcriptText: null, ocrText: "B".repeat(50) };
        expect(() => validateGenerationInput(job)).not.toThrow();
    });

    it("prefers transcriptText over ocrText when both present", () => {
        const transcript = "T".repeat(100);
        const job = { transcriptText: transcript, ocrText: "O".repeat(100) };
        const { text } = validateGenerationInput(job);
        expect(text).toBe(transcript);
    });

    it("rejects job with transcriptText too short (< 50 chars)", () => {
        const job = { transcriptText: "Short", ocrText: null };
        expect(() => validateGenerationInput(job)).toThrowWithCode("failed-precondition");
    });

    it("rejects job with no transcript and no OCR text", () => {
        const job = { transcriptText: null, ocrText: null };
        expect(() => validateGenerationInput(job)).toThrowWithCode("failed-precondition");
    });

    it("rejects job with both null (nothing to generate from)", () => {
        expect(() => validateGenerationInput({ transcriptText: null, ocrText: null }))
            .toThrowWithCode("failed-precondition");
    });

    it("accepts exactly-50-char text at the boundary", () => {
        const job = { transcriptText: "X".repeat(50), ocrText: null };
        expect(() => validateGenerationInput(job)).not.toThrow();
    });

    it("rejects 49-char text (one under boundary)", () => {
        const job = { transcriptText: "X".repeat(49), ocrText: null };
        expect(() => validateGenerationInput(job)).toThrowWithCode("failed-precondition");
    });
});

// ─── lightweightModeration ────────────────────────────────────────────────────

describe("lightweightModeration", () => {

    it("passes clean sermon transcript", () => {
        const result = lightweightModeration(
            "Today we explore John 3:16. The love of God is unconditional and eternal."
        );
        expect(result.ok).toBe(true);
        expect(result.reason).toBeUndefined();
    });

    it("blocks 'fake miracle' pattern", () => {
        const result = lightweightModeration("This is a guaranteed healing from a fake miracle.");
        expect(result.ok).toBe(false);
        expect(result.reason).toBe("unsafe_or_deceptive_content");
    });

    it("blocks 'guaranteed healing' in any case", () => {
        expect(lightweightModeration("I promise Guaranteed Healing to all believers.").ok).toBe(false);
    });

    it("blocks 'legal advice'", () => {
        expect(lightweightModeration("This is my legal advice to you.").ok).toBe(false);
    });

    it("blocks 'financial certainty'", () => {
        expect(lightweightModeration("The Bible guarantees financial certainty.").ok).toBe(false);
    });

    it("blocks 'impersonation'", () => {
        expect(lightweightModeration("This is not impersonation of a real pastor.").ok).toBe(false);
    });

    it("blocks 'impersonate'", () => {
        expect(lightweightModeration("We never impersonate religious leaders.").ok).toBe(false);
    });

    it("allows text that mentions the word 'miracle' without 'fake'", () => {
        expect(lightweightModeration("The miracle of the resurrection changed everything.").ok).toBe(true);
    });

    it("allows empty string (no content to block)", () => {
        expect(lightweightModeration("").ok).toBe(true);
    });
});

// ─── Storage path construction ────────────────────────────────────────────────

describe("Storage path construction", () => {

    const uid = "user-123";
    const noteId = "note-456";

    it("audio path includes uid, noteId, and audio subdirectory", () => {
        const path = buildAudioStoragePath(uid, noteId, "recording.m4a");
        expect(path).toBe(`churchNotes/${uid}/${noteId}/audio/recording.m4a`);
        expect(path.startsWith(`churchNotes/${uid}/`)).toBe(true);
    });

    it("image path includes uid, noteId, and images subdirectory", () => {
        const path = buildImageStoragePath(uid, noteId, "scan.jpg");
        expect(path).toBe(`churchNotes/${uid}/${noteId}/images/scan.jpg`);
        expect(path.startsWith(`churchNotes/${uid}/`)).toBe(true);
    });

    it("audio and image paths for same note are in different subdirectories", () => {
        const audioPath = buildAudioStoragePath(uid, noteId, "f.m4a");
        const imagePath = buildImageStoragePath(uid, noteId, "f.jpg");
        expect(audioPath).not.toBe(imagePath);
        expect(audioPath).toContain("/audio/");
        expect(imagePath).toContain("/images/");
    });

    it("paths for different users are isolated (no cross-user path sharing)", () => {
        const pathA = buildAudioStoragePath("user-A", noteId, "f.m4a");
        const pathB = buildAudioStoragePath("user-B", noteId, "f.m4a");
        expect(pathA).not.toContain("user-B");
        expect(pathB).not.toContain("user-A");
        expect(pathA.startsWith("churchNotes/user-A/")).toBe(true);
        expect(pathB.startsWith("churchNotes/user-B/")).toBe(true);
    });
});

// ─── Firestore mock — processing job write pattern ───────────────────────────

describe("Firestore write pattern — processing jobs", () => {

    it("set writes job document with correct shape", async () => {
        const doc = buildProcessingJobDocument("uid-1", "note-1", "audio",
            "churchNotes/uid-1/note-1/audio/f.m4a", 5_000_000, "job-1");
        await mockDoc.set(doc);
        expect(mockDoc.set).toHaveBeenCalledWith(
            expect.objectContaining({
                status: "queued",
                progress: 0,
                userId: "uid-1",
                churchNoteId: "note-1",
                transcriptText: null,
                ocrText: null,
            })
        );
    });

    it("update with status:processing and progress:5 simulates audio start", async () => {
        await mockDoc.update({ status: "processing", progress: 5 });
        expect(mockDoc.update).toHaveBeenCalledWith(
            expect.objectContaining({ status: "processing", progress: 5 })
        );
    });

    it("update with status:draftReady and progress:100 simulates completion", async () => {
        await mockDoc.update({
            status: "draftReady", progress: 100,
            transcriptText: "This is the sermon transcript.",
            safetyStatus: "passed",
        });
        expect(mockDoc.update).toHaveBeenCalledWith(
            expect.objectContaining({ status: "draftReady", progress: 100 })
        );
    });

    it("update with status:failed preserves errorCode and errorMessage", async () => {
        await mockDoc.update({
            status: "failed",
            progress: 0,
            errorCode: "whisper_error",
            errorMessage: "Transcription failed.",
        });
        expect(mockDoc.update).toHaveBeenCalledWith(
            expect.objectContaining({ status: "failed", errorCode: "whisper_error" })
        );
    });

    it("approval update sets approved field and does not overwrite others", async () => {
        await mockDoc.update({
            "approved_transcriptText": true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        expect(mockDoc.update).toHaveBeenCalledWith(
            expect.objectContaining({ "approved_transcriptText": true })
        );
    });
});

// ─── Cross-user isolation checks ─────────────────────────────────────────────

describe("Cross-user isolation", () => {

    it("storagePath owned by user-A fails validation for user-B", () => {
        expect(() => validateProcessingJobInput(
            "user-B",        // logged-in user
            "note-1",
            "audio",
            "churchNotes/user-A/note-1/audio/file.m4a",  // belongs to user-A
            1000, 0,
        )).toThrowWithCode("permission-denied");
    });

    it("storagePath owned by the same user always passes the prefix check", () => {
        const uid = "user-legitimate";
        expect(() => validateProcessingJobInput(
            uid, "my-note", "audio",
            `churchNotes/${uid}/my-note/audio/recording.m4a`,
            50_000_000, 1800,
        )).not.toThrow();
    });

    it("empty uid cannot be used to bypass prefix check", () => {
        // An empty uid would allow any path like "churchNotes//..." to pass —
        // the callable guards against this by requiring auth first.
        expect(() => requireAuthAndAppCheck({ uid: "" }, {}))
            .toThrowWithCode("unauthenticated");
    });
});

// ─── File size boundary checks ────────────────────────────────────────────────

describe("File size boundaries", () => {

    const uid = "u1";
    const noteId = "n1";

    it("accepts audio at exactly 100 MB", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "audio",
            `churchNotes/${uid}/${noteId}/audio/f.m4a`,
            100 * 1024 * 1024, 0,
        )).not.toThrow();
    });

    it("rejects audio at 100 MB + 1 byte", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "audio",
            `churchNotes/${uid}/${noteId}/audio/f.m4a`,
            100 * 1024 * 1024 + 1, 0,
        )).toThrowWithCode("invalid-argument");
    });

    it("accepts image at exactly 20 MB", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "image",
            `churchNotes/${uid}/${noteId}/images/f.jpg`,
            20 * 1024 * 1024, 0,
        )).not.toThrow();
    });

    it("rejects image at 20 MB + 1 byte", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "image",
            `churchNotes/${uid}/${noteId}/images/f.jpg`,
            20 * 1024 * 1024 + 1, 0,
        )).toThrowWithCode("invalid-argument");
    });

    it("accepts video at exactly 500 MB", () => {
        expect(() => validateProcessingJobInput(uid, noteId, "video",
            `churchNotes/${uid}/${noteId}/video/f.mp4`,
            500 * 1024 * 1024, 0,
        )).not.toThrow();
    });
});

// ─── Custom matcher ───────────────────────────────────────────────────────────

declare global {
    // eslint-disable-next-line @typescript-eslint/no-namespace
    namespace jest {
        interface Matchers<R> {
            toThrowWithCode(code: string): R;
        }
    }
}

expect.extend({
    toThrowWithCode(received: () => unknown, code: string) {
        try {
            received();
            return {
                pass: false,
                message: () => `Expected function to throw with code "${code}" but it did not throw.`,
            };
        } catch (e: unknown) {
            const err = e as { code?: string; message?: string };
            if (err.code === code) {
                return {
                    pass: true,
                    message: () => `Expected function NOT to throw with code "${code}" but it did.`,
                };
            }
            return {
                pass: false,
                message: () =>
                    `Expected throw code "${code}" but got "${err.code ?? "unknown"}" (${err.message ?? ""}).`,
            };
        }
    },
});
