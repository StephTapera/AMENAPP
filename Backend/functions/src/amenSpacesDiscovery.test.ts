import {
    canSurfaceDiscussion,
    joinAmenSpaceDiscussion,
    moderateAmenSpacesDiscussionPreview,
    moderatePreviewText,
    resolveJoinAction,
    safePreviewForDiscovery,
} from "./amenSpacesDiscovery";

function viewer(overrides: Record<string, unknown> = {}) {
    return {
        uid: "uid-1",
        isSpaceMember: false,
        isOrganizationMember: false,
        role: null,
        tierIds: new Set<string>(),
        canAccessYouthProtected: false,
        canViewConfidential: false,
        ...overrides,
    };
}

function discussion(overrides: Record<string, unknown> = {}) {
    return {
        id: "discussion-1",
        spaceId: "space-1",
        organizationId: "org-1",
        sourceType: "organization",
        title: "Open Discussion",
        subtitle: "Amen Space",
        descriptionPreview: "Safe public preview",
        category: "All",
        tags: [],
        visibility: "publicOpen",
        joinPolicy: "open",
        participantCount: 12,
        unreadCount: 0,
        trendingScore: 10,
        safetyStatus: "allowed",
        moderationStatus: "visible",
        trustBadges: ["Moderated"],
        isLive: false,
        isVerified: true,
        isYouthProtected: false,
        isConfidential: false,
        isAIExcluded: false,
        ...overrides,
    } as Parameters<typeof canSurfaceDiscussion>[0];
}

describe("Amen Spaces discovery safety helpers", () => {
    test("excludes private unauthorized discussions", () => {
        expect(canSurfaceDiscussion(discussion({ visibility: "privateRestricted" }), viewer())).toBe(false);
        expect(canSurfaceDiscussion(discussion({ visibility: "privateRestricted" }), viewer({ isSpaceMember: true }))).toBe(true);
    });

    test("paid discussion does not leak restricted preview for unpaid users", () => {
        const paid = discussion({
            visibility: "paidMemberOnly",
            joinPolicy: "paidOnly",
            requiresTier: "mentor-circle",
            descriptionPreview: "Restricted paid mentor details",
        });

        expect(resolveJoinAction(paid, viewer(), "notJoined")).toBe("Join");
        expect(safePreviewForDiscovery(paid, viewer())).not.toContain("Restricted paid");
        expect(safePreviewForDiscovery(paid, viewer())).toContain("Member-only");
    });

    test("confidential and youth-protected previews are permission gated", () => {
        const confidential = discussion({ visibility: "confidential", isConfidential: true, descriptionPreview: "Pastoral care names" });
        const youth = discussion({ visibility: "youthProtected", isYouthProtected: true, descriptionPreview: "Youth room details" });

        expect(canSurfaceDiscussion(confidential, viewer())).toBe(false);
        expect(safePreviewForDiscovery(confidential, viewer())).not.toContain("Pastoral care");
        expect(canSurfaceDiscussion(youth, viewer())).toBe(false);
        expect(canSurfaceDiscussion(youth, viewer({ canAccessYouthProtected: true }))).toBe(true);
    });

    test("reported or under-review style states are not surfaced", () => {
        expect(canSurfaceDiscussion(discussion({ moderationStatus: "underReview" }), viewer())).toBe(false);
        expect(canSurfaceDiscussion(discussion({ moderationStatus: "deleted" }), viewer())).toBe(false);
        expect(canSurfaceDiscussion(discussion({ safetyStatus: "needsReview" }), viewer())).toBe(false);
        expect(canSurfaceDiscussion(discussion({ safetyStatus: "blocked" }), viewer())).toBe(false);
    });

    test("join action maps from access policy", () => {
        expect(resolveJoinAction(discussion({ joinPolicy: "open" }), viewer(), "notJoined")).toBe("Join");
        expect(resolveJoinAction(discussion({ joinPolicy: "requestRequired" }), viewer(), "notJoined")).toBe("Request");
        expect(resolveJoinAction(discussion({ joinPolicy: "readOnly" }), viewer(), "notJoined")).toBe("View");
        expect(resolveJoinAction(discussion({ joinPolicy: "open", isLive: true }), viewer(), "joined")).toBe("Live");
        expect(resolveJoinAction(discussion({ joinPolicy: "open" }), viewer(), "joined")).toBe("Joined");
    });

    test("preview moderation catches unsafe preview text", () => {
        const result = moderatePreviewText("Do not tell anyone and meet at a secret meetup.");

        expect(result.moderationStatus).toBe("underReview");
        expect(result.reasons).toContain("youth_safety_risk");
    });
});

describe("Amen Spaces discovery callable contracts", () => {
    function callable<T>(fn: unknown, request: unknown): Promise<T> {
        return (fn as (request: unknown) => Promise<T>)(request);
    }

    test("join requires auth", async () => {
        await expect(callable(joinAmenSpaceDiscussion, { data: { spaceId: "space-1", discussionId: "discussion-1" }, auth: null }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });

    test("moderate preview requires auth", async () => {
        await expect(callable(moderateAmenSpacesDiscussionPreview, { data: { text: "safe" }, auth: null }))
            .rejects.toMatchObject({ code: "unauthenticated" });
    });
});
