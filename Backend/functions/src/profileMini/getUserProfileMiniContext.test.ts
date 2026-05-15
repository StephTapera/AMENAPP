/**
 * getUserProfileMiniContext.test.ts
 *
 * Unit tests for the getUserProfileMiniContext callable.
 * Uses jest + ts-jest with the project's firebase-admin mock.
 *
 * Run: npm test (matches *.test.ts pattern in package.json)
 */

import { scoreMutuals, scoreTopicOverlap, scorePrayerOverlap, scorePopularityFallback } from "./reasonScorers";
import { resolveOpenTableTrigger, resolvePrayerTrigger, resolveTestimonyTrigger } from "./triggerResolvers";

// ─── Helpers ────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const { __mockDoc, __mockCollection } = admin;

function makeDoc(data: object | null, id = "mock-id"): object {
    return {
        exists: data !== null,
        id,
        data: () => data,
    };
}

function makeCollection(docs: object[]): object {
    return {
        docs,
        empty: docs.length === 0,
    };
}

// ─── reasonScorers tests ─────────────────────────────────────────────

describe("scoreTopicOverlap", () => {
    it("returns null when no shared interests", () => {
        expect(scoreTopicOverlap(["faith"], ["music"])).toBeNull();
    });

    it("returns a reason when interests overlap", () => {
        const result = scoreTopicOverlap(["faith", "prayer"], ["faith", "worship"]);
        expect(result).not.toBeNull();
        expect(result!.kind).toBe("topicOverlap");
        expect(result!.score).toBeGreaterThan(0);
    });

    it("caps score at 1.0", () => {
        const viewer = Array.from({ length: 20 }, (_, i) => `topic_${i}`);
        const target = [...viewer];
        expect(scoreTopicOverlap(viewer, target)!.score).toBeLessThanOrEqual(1.0);
    });
});

describe("scorePrayerOverlap", () => {
    it("returns null on no overlap", () => {
        const { reason } = scorePrayerOverlap(["healing"], ["restoration"]);
        expect(reason).toBeNull();
    });

    it("scores prayer overlap and returns overlapCount", () => {
        const { reason, overlapCount } = scorePrayerOverlap(["healing", "faith"], ["healing", "peace"]);
        expect(reason).not.toBeNull();
        expect(overlapCount).toBe(1);
    });
});

describe("scorePopularityFallback", () => {
    it("returns null for low follower count", () => {
        expect(scorePopularityFallback(50)).toBeNull();
    });

    it("returns a reason for >= 100 followers", () => {
        const result = scorePopularityFallback(500);
        expect(result).not.toBeNull();
        expect(result!.kind).toBe("popularInArea");
    });

    it("caps score at 0.5", () => {
        expect(scorePopularityFallback(1_000_000)!.score).toBeLessThanOrEqual(0.5);
    });
});

// ─── triggerResolvers tests ──────────────────────────────────────────

describe("resolveOpenTableTrigger", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("returns null when no shared thread exists", async () => {
        __mockCollection.get.mockResolvedValue(makeCollection([]));
        const result = await resolveOpenTableTrigger("viewer1", "target1");
        expect(result).toBeNull();
    });

    it("returns unread state when viewer has no activity", async () => {
        const threadDoc = makeDoc({
            participantIds: ["viewer1", "target1"],
            title: "Test Thread",
            topic: "faith",
            participantActivity: {},
            lastActivityAt: new Date(),
        }, "thread_abc");

        // viewer query returns threadDoc; target query also contains it
        __mockCollection.get
            .mockResolvedValueOnce(makeCollection([threadDoc]))  // viewer
            .mockResolvedValueOnce(makeCollection([threadDoc])); // target

        const result = await resolveOpenTableTrigger("viewer1", "target1");
        expect(result).not.toBeNull();
        expect(result!.viewerState).toBe("unread");
        expect(result!.artifactType).toBe("openTableThread");
    });

    it("returns read state when viewer has lastSeenAt but no repliedAt", async () => {
        const threadDoc = makeDoc({
            participantIds: ["viewer1", "target1"],
            title: "Test Thread",
            topic: "faith",
            participantActivity: { viewer1: { lastSeenAt: new Date() } },
            lastActivityAt: new Date(),
        }, "thread_abc");

        __mockCollection.get
            .mockResolvedValueOnce(makeCollection([threadDoc]))
            .mockResolvedValueOnce(makeCollection([threadDoc]));

        const result = await resolveOpenTableTrigger("viewer1", "target1");
        expect(result!.viewerState).toBe("read");
    });

    it("returns replied state when viewer has repliedAt", async () => {
        const threadDoc = makeDoc({
            participantIds: ["viewer1", "target1"],
            title: "Test Thread",
            topic: "faith",
            participantActivity: { viewer1: { lastSeenAt: new Date(), repliedAt: new Date() } },
            lastActivityAt: new Date(),
        }, "thread_abc");

        __mockCollection.get
            .mockResolvedValueOnce(makeCollection([threadDoc]))
            .mockResolvedValueOnce(makeCollection([threadDoc]));

        const result = await resolveOpenTableTrigger("viewer1", "target1");
        expect(result!.viewerState).toBe("replied");
    });

    it("resolves directly when specificArtifactId is provided", async () => {
        const threadDoc = makeDoc({
            participantIds: ["viewer1", "target1"],
            title: "Direct Thread",
            topic: "leadership",
            participantActivity: {},
        }, "thread_xyz");
        __mockDoc.get.mockResolvedValue(threadDoc);

        const result = await resolveOpenTableTrigger("viewer1", "target1", "thread_xyz");
        expect(result).not.toBeNull();
        expect(result!.artifactId).toBe("thread_xyz");
    });

    it("returns null gracefully when specific artifact is missing", async () => {
        __mockDoc.get.mockResolvedValue(makeDoc(null));
        const result = await resolveOpenTableTrigger("viewer1", "target1", "nonexistent");
        expect(result).toBeNull();
    });
});

describe("resolvePrayerTrigger", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("returns null when target has no prayer posts", async () => {
        __mockCollection.get.mockResolvedValue(makeCollection([]));
        const result = await resolvePrayerTrigger("target1", "viewer1");
        expect(result).toBeNull();
    });

    it("returns unknown viewerState when viewer has not prayed", async () => {
        const prayerDoc = makeDoc({
            authorId: "target1",
            category: "prayer",
            title: "Pray for healing",
            tags: ["healing"],
            createdAt: new Date(),
        }, "prayer_001");

        __mockCollection.get.mockResolvedValue(makeCollection([prayerDoc]));
        __mockDoc.get.mockResolvedValue(makeDoc(null)); // viewer has not prayed

        const result = await resolvePrayerTrigger("target1", "viewer1");
        expect(result).not.toBeNull();
        expect(result!.viewerState).toBe("unknown");
        expect(result!.artifactType).toBe("prayerPost");
    });

    it("returns prayedToday when viewer prayed today", async () => {
        const today = new Date();
        const prayerDoc = makeDoc({
            authorId: "target1",
            category: "prayer",
            title: "Pray for healing",
            tags: ["healing"],
            createdAt: today,
        }, "prayer_001");

        __mockCollection.get.mockResolvedValue(makeCollection([prayerDoc]));
        __mockDoc.get.mockResolvedValue(makeDoc({
            createdAt: { toDate: () => today },
        }));

        const result = await resolvePrayerTrigger("target1", "viewer1");
        expect(result!.viewerState).toBe("prayedToday");
    });
});

describe("resolveTestimonyTrigger", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it("returns null when target has no testimony posts", async () => {
        __mockCollection.get.mockResolvedValue(makeCollection([]));
        const result = await resolveTestimonyTrigger("target1", "viewer1");
        expect(result).toBeNull();
    });

    it("returns unread viewerState when viewer has not viewed", async () => {
        const testimonyDoc = makeDoc({
            authorId: "target1",
            category: "testimony",
            title: "God Healed My Marriage",
            tags: ["healing"],
            createdAt: new Date(),
        }, "testimony_001");

        __mockCollection.get.mockResolvedValue(makeCollection([testimonyDoc]));
        __mockDoc.get.mockResolvedValue(makeDoc(null)); // no view record

        const result = await resolveTestimonyTrigger("target1", "viewer1");
        expect(result!.viewerState).toBe("unread");
        expect(result!.artifactType).toBe("testimonyPost");
    });

    it("returns viewed viewerState when testimonyViews record exists", async () => {
        const testimonyDoc = makeDoc({
            authorId: "target1",
            category: "testimony",
            title: "God Healed My Marriage",
            tags: ["healing"],
            createdAt: new Date(),
        }, "testimony_001");

        __mockCollection.get.mockResolvedValue(makeCollection([testimonyDoc]));
        __mockDoc.get.mockResolvedValue(makeDoc({ viewedAt: new Date() }));

        const result = await resolveTestimonyTrigger("target1", "viewer1");
        expect(result!.viewerState).toBe("viewed");
    });
});

// ─── Low signal fallback ─────────────────────────────────────────────

describe("low signal — only popularity fallback", () => {
    it("returns popularityFallback reason for popular user with no shared signals", () => {
        const topicResult = scoreTopicOverlap([], []);
        const { reason: prayerReason } = scorePrayerOverlap([], []);
        const popularity = scorePopularityFallback(5_000);

        expect(topicResult).toBeNull();
        expect(prayerReason).toBeNull();
        expect(popularity).not.toBeNull();
        expect(popularity!.kind).toBe("popularInArea");
    });
});
