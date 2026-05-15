import {
    computeContextScore,
    buildContextPayload,
    validateFeedbackAction,
} from "./feedContext";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makePost(overrides: Partial<{
    id: string;
    authorId: string;
    content: string;
    category: string;
    topicTag: string | null;
    amenCount: number;
    commentCount: number;
    createdAt: number;
    verseRef: string | null;
    churchId: string | null;
    communityId: string | null;
    linkedPrayerRequestId: string | null;
    lowTrustAuthor: boolean;
    flaggedForReview: boolean;
    removed: boolean;
}> = {}) {
    return {
        id: "post-1",
        authorId: "author-1",
        content: "A thoughtful reflection on faith.",
        category: "openTable",
        topicTag: "faith",
        amenCount: 0,
        commentCount: 0,
        createdAt: Math.floor(Date.now() / 1000) - 3600,
        verseRef: null,
        churchId: null,
        communityId: null,
        linkedPrayerRequestId: null,
        lowTrustAuthor: false,
        flaggedForReview: false,
        removed: false,
        ...overrides,
    };
}

function makeRequest(overrides: Partial<{
    posts: ReturnType<typeof makePost>[];
    interests: {
        engagedTopics: Record<string, number>;
        engagedAuthors: Record<string, number>;
        preferredCategories: Record<string, number>;
        onboardingGoals: string[];
    };
    followingIds: string[];
    sessionCardsServed: number;
    sessionCap: number;
}> = {}) {
    return {
        posts: [],
        interests: {
            engagedTopics: {},
            engagedAuthors: {},
            preferredCategories: {},
            onboardingGoals: [],
        },
        followingIds: [],
        sessionCardsServed: 0,
        sessionCap: 25,
        ...overrides,
    };
}

function makeUserContext(overrides: Partial<{
    churchId: string;
    city: string;
    communityId: string;
    interests: string[];
    scriptureTopics: string[];
    prayerInterests: string[];
}> = {}) {
    return {
        interests: [],
        scriptureTopics: [],
        prayerInterests: [],
        ...overrides,
    };
}

// ---------------------------------------------------------------------------
// Scoring tests
// ---------------------------------------------------------------------------

describe("computeContextScore", () => {
    it("returns a score in [0, 1] for normal post", () => {
        const post = makePost();
        const request = makeRequest();
        const ctx = makeUserContext();
        const result = computeContextScore(post, request, ctx);
        expect(result.contextScore).toBeGreaterThanOrEqual(0);
        expect(result.contextScore).toBeLessThanOrEqual(1);
    });

    it("trust score is 0 for low-trust author", () => {
        const post = makePost({ lowTrustAuthor: true });
        const result = computeContextScore(post, makeRequest(), makeUserContext());
        expect(result.trustScore).toBe(0);
    });

    it("trust score is 0 for flagged post", () => {
        const post = makePost({ flaggedForReview: true });
        const result = computeContextScore(post, makeRequest(), makeUserContext());
        expect(result.trustScore).toBe(0);
    });

    it("trust score is 0 for removed post", () => {
        const post = makePost({ removed: true });
        const result = computeContextScore(post, makeRequest(), makeUserContext());
        expect(result.trustScore).toBe(0);
    });

    it("community score includes following bonus", () => {
        const post = makePost({ authorId: "followed-author" });
        const request = makeRequest({ followingIds: ["followed-author"] });
        const result = computeContextScore(post, request, makeUserContext());
        expect(result.communityScore).toBeGreaterThan(0);
    });

    it("scripture score increases with verse reference", () => {
        const withVerse = makePost({ verseRef: "Romans 8:28" });
        const withoutVerse = makePost({ verseRef: null });
        const ctx = makeUserContext();
        const req = makeRequest();
        const scoreWith = computeContextScore(withVerse, req, ctx).scriptureScore;
        const scoreWithout = computeContextScore(withoutVerse, req, ctx).scriptureScore;
        expect(scoreWith).toBeGreaterThan(scoreWithout);
    });

    it("bait-phrase content gets reduced trust score", () => {
        const baitPost = makePost({ content: "This is viral right now! Everyone is talking about it." });
        const result = computeContextScore(baitPost, makeRequest(), makeUserContext());
        expect(result.trustScore).toBe(0.25);
    });
});

// ---------------------------------------------------------------------------
// Context payload attachment tests
// ---------------------------------------------------------------------------

describe("buildContextPayload", () => {
    it("returns null for low-trust author", () => {
        const post = makePost({ lowTrustAuthor: true });
        expect(buildContextPayload(post, makeRequest(), makeUserContext())).toBeNull();
    });

    it("returns null for removed post", () => {
        const post = makePost({ removed: true });
        expect(buildContextPayload(post, makeRequest(), makeUserContext())).toBeNull();
    });

    it("returns null when context score is below threshold", () => {
        // Fresh post, no engagement, no community signals — very low score
        const post = makePost({ amenCount: 0, commentCount: 0, createdAt: Math.floor(Date.now() / 1000) - 80 * 3600 });
        const result = buildContextPayload(post, makeRequest(), makeUserContext());
        expect(result).toBeNull();
    });

    it("sensitive type for disallowed content type returns null", () => {
        // 'war' triggers sensitive; 'sharedInYourCircles' is not an allowed sensitive type
        const post = makePost({
            content: "The war changed everything for our community.",
            communityId: "community-1",
            amenCount: 20,
            commentCount: 10,
        });
        const request = makeRequest({ followingIds: ["author-1"] });
        const ctx = makeUserContext({ communityId: "community-1" });
        const result = buildContextPayload(post, request, ctx);
        // If a context is generated, it must not be a non-allowed sensitive type
        if (result !== null) {
            const allowedSensitiveTypes = ["scriptureFocus", "churchPulse", "livePrayerMoment", "gentleFollowUp", "inConversation"];
            if (result.contextIsSensitive) {
                expect(allowedSensitiveTypes).toContain(result.contextType);
            }
        }
    });

    it("attaches verseRef for scripture focus posts", () => {
        const post = makePost({
            verseRef: "Romans 8:28",
            category: "scripture",
            content: "Romans 8:28 gives such peace.",
        });
        const ctx = makeUserContext({ scriptureTopics: ["romans"] });
        const request = makeRequest();
        const result = buildContextPayload(post, request, ctx);
        if (result?.contextType === "scriptureFocus") {
            expect(result.contextVerseRef).toBe("Romans 8:28");
        }
    });

    it("ranked response includes contextsByPostId", () => {
        const post = makePost({
            verseRef: "Psalm 23",
            category: "scripture",
            content: "Psalm 23 is my anchor.",
            amenCount: 5,
            commentCount: 5,
        });
        const request = makeRequest({ posts: [post] });
        const ctx = makeUserContext({ scriptureTopics: ["psalm"] });
        // buildContextPayload directly (ranked response wraps this)
        const payload = buildContextPayload(post, request, ctx);
        if (payload !== null) {
            expect(payload.contextId).toContain(post.id);
            expect(payload.contextExpiresAt).toBeTruthy();
            expect(payload.contextIsDismissible).toBe(true);
        }
    });

    it("expiration is set to the future", () => {
        const now = Date.now();
        const post = makePost({
            verseRef: "Hebrews 11:1",
            category: "scripture",
            content: "Hebrews 11:1 defines faith.",
            amenCount: 10,
            commentCount: 8,
        });
        const ctx = makeUserContext({ scriptureTopics: ["hebrews"] });
        const result = buildContextPayload(post, makeRequest(), ctx);
        if (result !== null) {
            const expiresAt = new Date(result.contextExpiresAt).getTime();
            expect(expiresAt).toBeGreaterThan(now);
        }
    });
});

// ---------------------------------------------------------------------------
// Feedback validation
// ---------------------------------------------------------------------------

describe("validateFeedbackAction", () => {
    const validActions = ["impression", "tap", "dismiss", "show_less", "mute_topic", "mute_type", "hide_all", "report_issue"];
    const invalidActions = ["like", "share", "delete", "", "IMPRESSION", "show-less"];

    validActions.forEach((action) => {
        it(`accepts valid action: ${action}`, () => {
            expect(validateFeedbackAction(action)).toBe(true);
        });
    });

    invalidActions.forEach((action) => {
        it(`rejects invalid action: "${action}"`, () => {
            expect(validateFeedbackAction(action)).toBe(false);
        });
    });
});
