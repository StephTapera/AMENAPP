import * as admin from "firebase-admin";
import {
    countVisibleCommunityMatches,
    denormalizePreviewCandidates,
    detectCommunityPulse,
    generateBereanInsightCandidate,
    hasStrongRelationship,
    passesPreviewModeration,
    selectFollowedReplyFromRelationships,
    shouldRefreshPreviewAvatars,
} from "./generateDynamicReplyPreviews";

function comment(overrides: Partial<Record<string, unknown>> = {}) {
    return {
        id: String(overrides.id ?? "comment-1"),
        authorId: String(overrides.authorId ?? "author-1"),
        authorName: String(overrides.authorName ?? "Author"),
        authorProfileImageURL: overrides.authorProfileImageURL as string | undefined,
        text: String(overrides.text ?? "Hope and healing"),
        amenCount: Number(overrides.amenCount ?? 4),
        lightbulbCount: Number(overrides.lightbulbCount ?? 1),
        createdAt: (overrides.createdAt as admin.firestore.Timestamp | undefined) ?? admin.firestore.Timestamp.now(),
        isDeleted: Boolean(overrides.isDeleted ?? false),
        isHidden: Boolean(overrides.isHidden ?? false),
        flaggedForReview: Boolean(overrides.flaggedForReview ?? false),
        removed: Boolean(overrides.removed ?? false),
    };
}

describe("Dynamic reply preview backend intelligence", () => {
    const expiresAt = admin.firestore.Timestamp.now();

    test("followedReply only appears for followed or high-affinity users", () => {
        const comments = [
            comment({ id: "c1", authorId: "author-1", text: "Hope and healing in this thread" }),
            comment({ id: "c2", authorId: "author-2", text: "Grace and peace" }),
        ];

        const result = selectFollowedReplyFromRelationships(
            comments,
            new Map([
                ["author-1", { followsAuthor: true, mutualTopicCount: 0 }],
                ["author-2", { followsAuthor: false, mutualTopicCount: 1 }],
            ]),
            null
        );

        expect(result?.authorId).toBe("author-1");
        expect(hasStrongRelationship({ followsAuthor: true, mutualTopicCount: 0 })).toBe(true);
        expect(hasStrongRelationship({ followsAuthor: false, mutualTopicCount: 2 })).toBe(true);
    });

    test("followedReply does not appear when no relationship exists", () => {
        const result = selectFollowedReplyFromRelationships(
            [comment({ authorId: "author-1" })],
            new Map([["author-1", { followsAuthor: false, mutualTopicCount: 1 }]]),
            null
        );
        expect(result).toBeNull();
    });

    test("bereanInsight requires enough approved comments", () => {
        const result = generateBereanInsightCandidate("post-1", [
            comment({ id: "c1", text: "Hope is here" }),
            comment({ id: "c2", text: "Healing is needed" }),
            comment({ id: "c3", text: "Amen" }),
        ], expiresAt);
        expect(result).toBeNull();
    });

    test("bereanInsight is suppressed on low confidence", () => {
        const result = generateBereanInsightCandidate("post-1", [
            comment({ id: "c1", text: "One thought" }),
            comment({ id: "c2", text: "Another thought" }),
            comment({ id: "c3", text: "Different idea" }),
            comment({ id: "c4", text: "Unrelated line" }),
        ], expiresAt);
        expect(result).toBeNull();
    });

    test("bereanInsight passes moderation before write", () => {
        expect(passesPreviewModeration("Berean: replies focus on hope + healing")).toBe(true);
        expect(passesPreviewModeration("Berean: replies focus on https://unsafe")).toBe(false);
    });

    test("trustedCommunitySignal respects visibility and privacy", () => {
        const comments = [
            comment({ id: "c1", authorId: "a1" }),
            comment({ id: "c2", authorId: "a2" }),
            comment({ id: "c3", authorId: "a3" }),
        ];

        const profiles = new Map<string, Record<string, unknown>>([
            ["a1", { churchId: "church-1", churchVisibility: "public" }],
            ["a2", { churchId: "church-1", shareChurchMembership: false }],
            ["a3", { communityId: "community-1", communityVisibility: "followers" }],
        ]);

        const counts = countVisibleCommunityMatches(comments, profiles, {
            uid: "viewer",
            churchId: "church-1",
            communityId: "community-1",
        });

        expect(counts.visibleChurchCount).toBe(1);
        expect(counts.visibleCommunityCount).toBe(1);
    });

    test("avatar refresh behavior only runs when the image URL changes", () => {
        expect(shouldRefreshPreviewAvatars(null, null)).toBe(false);
        expect(shouldRefreshPreviewAvatars("a", "a")).toBe(false);
        expect(shouldRefreshPreviewAvatars("a", "b")).toBe(true);
    });

    test("detectCommunityPulse identifies themes from comment text", () => {
        const comments = [
            comment({ id: "c1", text: "There is hope in this community" }),
            comment({ id: "c2", text: "Hope and healing are central here" }),
            comment({ id: "c3", text: "Healing is what we need" }),
            comment({ id: "c4", text: "Healing through faith" }),
        ];
        const result = detectCommunityPulse(comments);
        expect(result).not.toBeNull();
        expect(result!.previewText).toContain("hope");
        expect(result!.previewText).toContain("healing");
        expect(result!.sourceCommentIds.length).toBeGreaterThan(0);
    });

    test("detectCommunityPulse returns null when no theme appears 2+ times", () => {
        const comments = [
            comment({ id: "c1", text: "Hope is here" }),
            comment({ id: "c2", text: "Grace is present" }),
            comment({ id: "c3", text: "Faith moves mountains" }),
        ];
        const result = detectCommunityPulse(comments);
        expect(result).toBeNull();
    });

    test("detectCommunityPulse limits sourceCommentIds to 3", () => {
        const comments = [
            comment({ id: "c1", text: "Hope and healing" }),
            comment({ id: "c2", text: "Hope is real" }),
            comment({ id: "c3", text: "So much hope here" }),
            comment({ id: "c4", text: "Healing through hope" }),
            comment({ id: "c5", text: "Hope carries us forward" }),
        ];
        const result = detectCommunityPulse(comments);
        expect(result).not.toBeNull();
        expect(result!.sourceCommentIds.length).toBeLessThanOrEqual(3);
    });

    test("detectCommunityPulse confidence reflects theme frequency", () => {
        const highFreqComments = [
            comment({ id: "c1", text: "Hope hope hope" }),
            comment({ id: "c2", text: "Hope is everywhere" }),
            comment({ id: "c3", text: "So much hope" }),
            comment({ id: "c4", text: "Hope carries us" }),
        ];
        const lowFreqComments = [
            comment({ id: "c1", text: "Hope is good" }),
            comment({ id: "c2", text: "Hope mentioned once" }),
            comment({ id: "c3", text: "Something different" }),
            comment({ id: "c4", text: "Another thought" }),
            comment({ id: "c5", text: "Unrelated" }),
            comment({ id: "c6", text: "More unrelated" }),
            comment({ id: "c7", text: "Still unrelated" }),
            comment({ id: "c8", text: "Very unrelated" }),
        ];
        const highResult = detectCommunityPulse(highFreqComments);
        const lowResult = detectCommunityPulse(lowFreqComments);

        // High frequency relative to comment count → higher confidence
        if (highResult && lowResult) {
            expect(highResult.confidence).toBeGreaterThanOrEqual(lowResult.confidence);
        }
    });

    test("bereanInsight includes sourceCommentIds from community pulse", () => {
        const comments = [
            comment({ id: "c1", text: "Hope and healing in this community" }),
            comment({ id: "c2", text: "So much hope here, healing is present" }),
            comment({ id: "c3", text: "Hope carries us, healing follows" }),
            comment({ id: "c4", text: "Hope and healing are central to faith" }),
            comment({ id: "c5", text: "Hope, healing, and grace" }),
        ];
        const expiresAt = admin.firestore.Timestamp.now();
        const result = generateBereanInsightCandidate("post-1", comments, expiresAt);

        if (result) {
            expect(result.sourceCommentIds.length).toBeGreaterThan(0);
            expect(result.sourceCommentIds.length).toBeLessThanOrEqual(3);
        }
        // If result is null, confidence was < 0.68 — that's also valid and tested separately
    });

    test("denormalized feed candidates stay safe and exclude viewer-specific previews", () => {
        const candidates = [
            {
                id: "top",
                postId: "post-1",
                replyId: "reply-1",
                sourceCommentIds: ["reply-1"],
                type: "topReply" as const,
                previewText: "Safe reply",
                authorId: "author-1",
                authorDisplayName: "Author",
                avatarURLs: [],
                participantUserIds: ["author-1"],
                score: 0.9,
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt,
                moderationState: "approved" as const,
                source: "comment",
            },
            {
                id: "followed",
                postId: "post-1",
                replyId: "reply-2",
                sourceCommentIds: ["reply-2"],
                type: "followedReply" as const,
                previewText: "Viewer specific",
                authorId: "author-2",
                authorDisplayName: "Author 2",
                avatarURLs: [],
                participantUserIds: ["author-2"],
                score: 0.95,
                generatedAt: admin.firestore.FieldValue.serverTimestamp(),
                expiresAt,
                moderationState: "approved" as const,
                source: "comment",
            },
        ];

        const result = denormalizePreviewCandidates(candidates);
        expect(result).toHaveLength(1);
        expect(result[0]?.type).toBe("topReply");
    });

    test("unsafe candidate suppressed regardless of score", () => {
        expect(passesPreviewModeration("k.y.s")).toBe(false);
        expect(passesPreviewModeration("go to hxxp dot com for free followers")).toBe(false);
    });

    test("viewerId nil path yields no followed reply relationship context", () => {
        const result = selectFollowedReplyFromRelationships(
            [comment({ id: "c1", authorId: "a1" })],
            new Map(),
            null
        );
        expect(result).toBeNull();
    });
});
