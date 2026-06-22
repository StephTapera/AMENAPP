import { rankDynamicReplyCandidate } from "./dynamicReplyPreviewRanking";

function timestamp(hoursAgo: number) {
    return {
        toMillis: () => Date.now() - hoursAgo * 60 * 60 * 1000,
    };
}

describe("dynamicReplyPreviewRanking", () => {
    test("viewerId nil omits authorAffinity", () => {
        const result = rankDynamicReplyCandidate({
            comment: { id: "c1", text: "Hope and prayer", createdAt: timestamp(1) },
            safetyConfidence: 0.9,
        });
        expect(result.authorAffinity).toBe(0);
        expect(result.omittedWeights).toContain("authorAffinity");
    });

    test("viewerId present includes authorAffinity", () => {
        const result = rankDynamicReplyCandidate({
            comment: { id: "c1", text: "Hope and prayer", createdAt: timestamp(1) },
            viewerId: "viewer-1",
            authorAffinity: 0.9,
            safetyConfidence: 0.9,
        });
        expect(result.authorAffinity).toBeGreaterThan(0);
        expect(result.includedWeights).toContain("authorAffinity");
    });

    test("short high-quality engaged can beat long mediocre", () => {
        const shortHigh = rankDynamicReplyCandidate({
            comment: {
                id: "good",
                text: "Praying for you. Psalm 34:18. We are with you.",
                amenCount: 8,
                lightbulbCount: 5,
                prayerCount: 4,
                createdAt: timestamp(2),
            },
            safetyConfidence: 0.95,
        });
        const longMediocre = rankDynamicReplyCandidate({
            comment: {
                id: "long",
                text: "x".repeat(320),
                amenCount: 0,
                lightbulbCount: 0,
                reportCount: 1,
                createdAt: timestamp(2),
            },
            safetyConfidence: 0.8,
        });
        expect(shortHigh.finalScore).toBeGreaterThan(longMediocre.finalScore);
    });

    test("reported comment loses score", () => {
        const clean = rankDynamicReplyCandidate({
            comment: { id: "clean", text: "encouraging prayer", amenCount: 6, createdAt: timestamp(4) },
            safetyConfidence: 0.9,
        });
        const reported = rankDynamicReplyCandidate({
            comment: { id: "reported", text: "encouraging prayer", amenCount: 6, reportCount: 4, createdAt: timestamp(4) },
            safetyConfidence: 0.9,
        });
        expect(reported.engagementQuality).toBeLessThan(clean.engagementQuality);
        expect(reported.finalScore).toBeLessThan(clean.finalScore);
    });
});
