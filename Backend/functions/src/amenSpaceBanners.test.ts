import {
    AmenSpaceBannerRecord,
    dedupeAmenSpaceBanners,
    isAmenSpaceBannerEligible,
    rankAmenSpaceBanners,
    resolveAmenSpaceBannerSize,
} from "./amenSpaceBanners";

function timestamp(date: Date) {
    return { toDate: () => date, toMillis: () => date.getTime() } as FirebaseFirestore.Timestamp;
}

function viewer(overrides: Record<string, unknown> = {}) {
    return {
        uid: "uid-1",
        spaceIds: new Set<string>(["space-1"]),
        organizationIds: new Set<string>(["org-1"]),
        dismissedBannerIds: new Set<string>(),
        ...overrides,
    };
}

function banner(overrides: Partial<AmenSpaceBannerRecord> = {}): AmenSpaceBannerRecord {
    return {
        id: "banner-1",
        type: "discussion",
        title: "Should churches use AI tools?",
        subtitle: "Active discussion",
        spaceId: "space-1",
        organizationId: "org-1",
        surfaces: ["spacesHome"],
        targetRoute: "amen://spaces/space-1/discussions/discussion-1",
        ctaLabel: "Open",
        priority: 10,
        moderationStatus: "approved",
        visibility: "authenticated",
        trustedContext: "trusted members are participating",
        rankingReason: "Because your space is active",
        safetyScore: 1,
        urgencyScore: 0,
        relevanceScore: 0,
        localScore: 0,
        trustedParticipationScore: 0,
        originalityScore: 0,
        usefulnessScore: 0,
        ...overrides,
    };
}

describe("Amen Space editorial banners", () => {
    test("eligibility blocks unapproved, wrong-surface, dismissed, and expired banners", () => {
        const current = new Date("2026-05-24T12:00:00Z");

        expect(isAmenSpaceBannerEligible(banner(), viewer(), "spacesHome", current)).toBe(true);
        expect(isAmenSpaceBannerEligible(banner({ moderationStatus: "pending" }), viewer(), "spacesHome", current)).toBe(false);
        expect(isAmenSpaceBannerEligible(banner({ surfaces: ["jobs"] }), viewer(), "spacesHome", current)).toBe(false);
        expect(isAmenSpaceBannerEligible(banner({ id: "dismissed" }), viewer({ dismissedBannerIds: new Set(["dismissed"]) }), "spacesHome", current)).toBe(false);
        expect(isAmenSpaceBannerEligible(banner({ endsAt: timestamp(new Date("2026-05-23T12:00:00Z")) }), viewer(), "spacesHome", current)).toBe(false);
    });

    test("visibility requires matching server-known memberships", () => {
        expect(isAmenSpaceBannerEligible(banner({ visibility: "spaceMembers", spaceId: "space-1" }), viewer(), "spacesHome")).toBe(true);
        expect(isAmenSpaceBannerEligible(banner({ visibility: "spaceMembers", spaceId: "space-2" }), viewer(), "spacesHome")).toBe(false);
        expect(isAmenSpaceBannerEligible(banner({ visibility: "organizationMembers", organizationId: "org-1" }), viewer(), "spacesHome")).toBe(true);
        expect(isAmenSpaceBannerEligible(banner({ visibility: "private" }), viewer(), "spacesHome")).toBe(false);
    });

    test("ranking weights relevance, safety, urgency, and usefulness", () => {
        const low = banner({ id: "low", priority: 2, targetRoute: "amen://low" });
        const high = banner({
            id: "high",
            priority: 2,
            targetRoute: "amen://high",
            relevanceScore: 4,
            urgencyScore: 3,
            usefulnessScore: 3,
            trustedParticipationScore: 2,
        });

        expect(rankAmenSpaceBanners([low, high]).map((item) => item.id)).toEqual(["high", "low"]);
    });

    test("duplicate target routes are removed before payload display", () => {
        const first = banner({ id: "first", targetRoute: "amen://same" });
        const duplicate = banner({ id: "duplicate", targetRoute: "amen://same" });
        const unique = banner({ id: "unique", targetRoute: "amen://unique" });

        expect(dedupeAmenSpaceBanners([first, duplicate, unique]).map((item) => item.id)).toEqual(["first", "unique"]);
    });

    test("size resolution honors user, admin, surface, then system fallback", () => {
        expect(resolveAmenSpaceBannerSize("hero", "compact", "standard")).toBe("hero");
        expect(resolveAmenSpaceBannerSize(undefined, "large", "standard")).toBe("large");
        expect(resolveAmenSpaceBannerSize(undefined, undefined, "compact")).toBe("compact");
        expect(resolveAmenSpaceBannerSize("massive", "wide", "bad")).toBe("standard");
    });
});
