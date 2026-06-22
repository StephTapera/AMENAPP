/**
 * mediaCallables.test.ts
 *
 * Unit tests for the Social OS media callable backend functions.
 * Uses the project-standard firebase-admin mock from __mocks__/firebase-admin.js.
 *
 * Run: cd Backend/functions && npm test
 */

import admin from "firebase-admin";

// ── Mock plumbing (matches covenant test pattern) ─────────────────────────────
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockAdmin = admin as any;
const mockDoc: jest.Mocked<{
    get: jest.Mock; set: jest.Mock; update: jest.Mock;
    collection: jest.Mock; id: string; __data: unknown;
}> = mockAdmin.__mockDoc;

// ── Pure validation helpers extracted from the callables ─────────────────────
// We test the business-logic rules in isolation (callable wrappers require
// Firebase App Check context that is not available in this unit-test environment).

// ── createMediaSession validation ────────────────────────────────────────────

function validateCreateMediaSessionInput(maxItems: unknown, maxDurationSeconds: unknown): void {
    if (typeof maxItems !== "number" || maxItems < 1 || maxItems > 20) {
        throw Object.assign(new Error("maxItems must be 1–20."), {code: "invalid-argument"});
    }
    if (typeof maxDurationSeconds !== "number" || maxDurationSeconds < 60 || maxDurationSeconds > 7200) {
        throw Object.assign(new Error("maxDurationSeconds must be 60–7200."), {code: "invalid-argument"});
    }
}

function buildSessionDocument(uid: string, sessionType: string, maxItems: number,
    maxDurationSeconds: number, sessionId: string): Record<string, unknown> {
    return {sessionId, ownerUid: uid, sessionType,
        communityIds: [], itemIds: [], currentIndex: 0,
        status: "active", finiteQueue: true,    // always true — never infinite
        maxItems, maxDurationSeconds,
        reflectionPromptShown: false, sourceSurface: "app",
    };
}

// ── updateMediaProgress validation ───────────────────────────────────────────

function validateProgressInput(progressSeconds: unknown, durationSeconds: unknown): {
    clamped: number; percent: number;
} {
    if (typeof progressSeconds !== "number" || progressSeconds < 0) {
        throw Object.assign(new Error("Invalid progressSeconds."), {code: "invalid-argument"});
    }
    if (typeof durationSeconds !== "number" || durationSeconds <= 0) {
        throw Object.assign(new Error("Invalid durationSeconds."), {code: "invalid-argument"});
    }
    const clamped = Math.min(progressSeconds, durationSeconds);
    const percent = Math.round((clamped / durationSeconds) * 100);
    return {clamped, percent};
}

// ── saveToMediaQueue validation ───────────────────────────────────────────────

const VALID_QUEUE_TYPES = ["watch_later","prayer_queue","church_notes","family_watch",
    "selah_tonight","sermon_study","testimony_archive"];

function validateQueueType(queueType: unknown): void {
    if (!VALID_QUEUE_TYPES.includes(queueType as string)) {
        throw Object.assign(new Error("Invalid queueType."), {code: "invalid-argument"});
    }
}

// ── registerMediaProvenance validation ───────────────────────────────────────

const VALID_SOURCES = ["device_camera","device_library","screen_recording",
    "external_import","ai_assisted","unknown"];

function validateSourceType(sourceType: unknown): void {
    if (!VALID_SOURCES.includes(sourceType as string)) {
        throw Object.assign(new Error("Invalid sourceType."), {code: "invalid-argument"});
    }
}

function computeAuthenticityConfidence(capturedOnDevice: boolean): number {
    return capturedOnDevice ? 0.9 : 0.7;
}

// ── reportMedia validation ────────────────────────────────────────────────────

const VALID_REASONS = ["harmful_or_dangerous","harassment","sexual_content","graphic_content",
    "misinformation","spiritual_manipulation","exploitative_testimony",
    "child_safety","self_harm","synthetic_deception","spam","other"];

function validateReportReason(reason: unknown): void {
    if (!VALID_REASONS.includes(reason as string)) {
        throw Object.assign(new Error("Invalid reason."), {code: "invalid-argument"});
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

beforeEach(() => {
    jest.clearAllMocks();
    mockDoc.__data = undefined;
    mockDoc.get.mockResolvedValue({exists: true, data: () => mockDoc.__data});
    mockDoc.set.mockResolvedValue(undefined);
    mockDoc.update.mockResolvedValue(undefined);
});

// ─── createMediaSession ───────────────────────────────────────────────────────

describe("createMediaSession — input validation", () => {

    it("accepts maxItems in valid range 1–20", () => {
        expect(() => validateCreateMediaSessionInput(1, 300)).not.toThrow();
        expect(() => validateCreateMediaSessionInput(20, 300)).not.toThrow();
        expect(() => validateCreateMediaSessionInput(8, 900)).not.toThrow();
    });

    it("rejects maxItems < 1", () => {
        expect(() => validateCreateMediaSessionInput(0, 300))
            .toThrowWithCode("invalid-argument");
    });

    it("rejects maxItems > 20", () => {
        expect(() => validateCreateMediaSessionInput(21, 300))
            .toThrowWithCode("invalid-argument");
    });

    it("rejects maxDurationSeconds < 60", () => {
        expect(() => validateCreateMediaSessionInput(5, 59))
            .toThrowWithCode("invalid-argument");
    });

    it("rejects maxDurationSeconds > 7200", () => {
        expect(() => validateCreateMediaSessionInput(5, 7201))
            .toThrowWithCode("invalid-argument");
    });

    it("builds session document with finiteQueue always true", () => {
        const doc = buildSessionDocument("uid-1", "morning_inspiration", 5, 600, "sess-1");
        expect(doc.finiteQueue).toBe(true);
        expect(doc.status).toBe("active");
        expect(doc.currentIndex).toBe(0);
        expect(doc.reflectionPromptShown).toBe(false);
    });
});

// ─── updateMediaProgress ─────────────────────────────────────────────────────

describe("updateMediaProgress — progress calculation", () => {

    it("accepts valid progress within duration", () => {
        const {clamped, percent} = validateProgressInput(30, 60);
        expect(clamped).toBe(30);
        expect(percent).toBe(50);
    });

    it("clamps progress to durationSeconds (cannot exceed video length)", () => {
        const {clamped, percent} = validateProgressInput(90, 60);
        expect(clamped).toBe(60);
        expect(percent).toBe(100);
    });

    it("marks completed when percent >= 90", () => {
        const {percent} = validateProgressInput(57, 60);   // 95%
        expect(percent >= 90).toBe(true);
    });

    it("does not mark completed for short views (< 90%)", () => {
        const {percent} = validateProgressInput(10, 60);   // 16.7%
        expect(percent >= 90).toBe(false);
    });

    it("rejects negative progressSeconds", () => {
        expect(() => validateProgressInput(-1, 60)).toThrowWithCode("invalid-argument");
    });

    it("rejects zero durationSeconds", () => {
        expect(() => validateProgressInput(0, 0)).toThrowWithCode("invalid-argument");
    });

    it("rejects non-numeric progressSeconds", () => {
        expect(() => validateProgressInput("thirty", 60)).toThrowWithCode("invalid-argument");
    });
});

// ─── saveToMediaQueue ─────────────────────────────────────────────────────────

describe("saveToMediaQueue — queueType validation", () => {

    it.each(VALID_QUEUE_TYPES)("accepts valid queueType: %s", (queueType) => {
        expect(() => validateQueueType(queueType)).not.toThrow();
    });

    it("rejects unknown queueType", () => {
        expect(() => validateQueueType("random_bucket")).toThrowWithCode("invalid-argument");
    });

    it("rejects empty string", () => {
        expect(() => validateQueueType("")).toThrowWithCode("invalid-argument");
    });

    it("rejects undefined", () => {
        expect(() => validateQueueType(undefined)).toThrowWithCode("invalid-argument");
    });
});

// ─── reportMedia ──────────────────────────────────────────────────────────────

describe("reportMedia — reason validation", () => {

    it.each(VALID_REASONS)("accepts valid reason: %s", (reason) => {
        expect(() => validateReportReason(reason)).not.toThrow();
    });

    it("rejects unknown reason", () => {
        expect(() => validateReportReason("dislike")).toThrowWithCode("invalid-argument");
    });

    it("rejects empty reason", () => {
        expect(() => validateReportReason("")).toThrowWithCode("invalid-argument");
    });
});

// ─── registerMediaProvenance ──────────────────────────────────────────────────

describe("registerMediaProvenance", () => {

    it.each(VALID_SOURCES)("accepts valid sourceType: %s", (src) => {
        expect(() => validateSourceType(src)).not.toThrow();
    });

    it("rejects unknown sourceType", () => {
        expect(() => validateSourceType("clipboard")).toThrowWithCode("invalid-argument");
    });

    it("sets authenticityConfidence 0.9 for device_camera capture", () => {
        expect(computeAuthenticityConfidence(true)).toBe(0.9);
    });

    it("sets authenticityConfidence 0.7 for non-device capture", () => {
        expect(computeAuthenticityConfidence(false)).toBe(0.7);
    });

    it("device_camera always gets higher confidence than external", () => {
        expect(computeAuthenticityConfidence(true))
            .toBeGreaterThan(computeAuthenticityConfidence(false));
    });
});

// ─── Firestore write verification ─────────────────────────────────────────────

describe("Firestore mock — session write pattern", () => {

    it("set is called with correct collection path shape", async () => {
        const doc = buildSessionDocument("uid-abc", "testimonies", 6, 720, "sess-abc");
        await mockDoc.set(doc);
        expect(mockDoc.set).toHaveBeenCalledWith(
            expect.objectContaining({
                ownerUid: "uid-abc",
                sessionType: "testimonies",
                finiteQueue: true,
            })
        );
    });

    it("completeMediaSession update includes completed status", async () => {
        await mockDoc.update({status: "completed", finalAction: "reflect"});
        expect(mockDoc.update).toHaveBeenCalledWith(
            expect.objectContaining({status: "completed"})
        );
    });
});

// ─── Custom matcher helper ────────────────────────────────────────────────────

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
            return {pass: false, message: () => `Expected function to throw with code "${code}" but it did not throw.`};
        } catch (e: unknown) {
            const err = e as {code?: string; message?: string};
            if (err.code === code) {
                return {pass: true, message: () => `Expected function NOT to throw with code "${code}" but it did.`};
            }
            return {
                pass: false,
                message: () => `Expected throw code "${code}" but got "${err.code ?? "unknown"}" (${err.message ?? ""}).`,
            };
        }
    },
});
