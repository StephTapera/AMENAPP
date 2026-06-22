import { logger } from "firebase-functions/v2";
import { logPreviewError, logPreviewEvent } from "./previewLogger";

describe("previewLogger", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("blocked candidates log suppression reason", () => {
        logPreviewEvent("preview_candidate_suppressed", {
            postId: "post-1",
            previewId: "preview-1",
            suppressionReason: "self_harm_encouragement",
            matchedRules: ["self_harm_kys"],
            normalizedText: "kys now",
        });
        expect((logger.info as jest.Mock).mock.calls[0][0]).toBe("preview_candidate_suppressed");
        const payload = (logger.info as jest.Mock).mock.calls[0][1];
        expect(payload.suppressionReason).toBe("self_harm_encouragement");
        expect(payload.normalizedTextHash).toBeDefined();
    });

    test("generation failure logs error", () => {
        logPreviewError("preview_generation_failed", {
            postId: "post-2",
            refreshReason: "scheduled_refresh",
            error: new Error("boom"),
        });
        expect((logger.error as jest.Mock).mock.calls[0][0]).toBe("preview_generation_failed");
    });

    test("write suppression logs reason", () => {
        logPreviewEvent("preview_write_suppressed", {
            postId: "post-3",
            refreshReason: "comment_created",
            suppressionReason: "min_refresh_interval",
        });
        const payload = (logger.info as jest.Mock).mock.calls[0][1];
        expect(payload.suppressionReason).toBe("min_refresh_interval");
    });

    test("scheduled refresh logs start/completion/failure events", () => {
        logPreviewEvent("scheduled_refresh_started", { refreshReason: "scheduled_refresh" });
        logPreviewEvent("scheduled_refresh_completed", { refreshReason: "scheduled_refresh", candidateCountIn: 10, candidateCountOut: 8 });
        logPreviewError("scheduled_refresh_failed", { refreshReason: "scheduled_refresh", error: "timeout" });

        expect((logger.info as jest.Mock).mock.calls.map((call) => call[0])).toContain("scheduled_refresh_started");
        expect((logger.info as jest.Mock).mock.calls.map((call) => call[0])).toContain("scheduled_refresh_completed");
        expect((logger.error as jest.Mock).mock.calls.map((call) => call[0])).toContain("scheduled_refresh_failed");
    });
});
