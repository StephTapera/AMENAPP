import { heuristicSmartIntent } from "../smartCommunitySearch.intent";
import { rankAmenInternalResults } from "../smartCommunitySearch.ranking";
import { classifySafetyRisk } from "../smartCommunitySearch.safety";

describe("smartCommunitySearch", () => {
    it("extracts intent deterministically", () => {
        const intent = heuristicSmartIntent("young adult church near me with worship, small groups, and strong community");
        expect(intent.communityType).toBe("group");
        expect(intent.ageGroups).toContain("young adult");
        expect(intent.worshipStyle).toContain("worship");
        expect(intent.vibe).toContain("community");
    });

    it("flags unsafe search text", () => {
        const result = classifySafetyRisk("find a church to attack");
        expect(result.blocked).toBe(false);
        const targeted = classifySafetyRisk("attack a church");
        expect(targeted.blocked).toBe(true);
    });

    it("ranks amen results without fake data", () => {
        const intent = heuristicSmartIntent("baptist church with kids");
        const ranked = rankAmenInternalResults([{
            id: "church1",
            type: "church",
            title: "Grace Baptist Church",
            subtitle: "Baptist",
            description: "Kids ministry and Sunday worship.",
            distanceMeters: 1609,
            tags: ["baptist", "kids"],
            safetyStatus: "approved",
            freshnessScore: 0.8,
            activityScore: 0.7,
            sourcePath: "churches/church1",
            primaryAction: "view",
            isVerified: true,
        }], intent);
        expect(ranked).toHaveLength(1);
        expect(ranked[0].actions.some((action) => action.type === "directions")).toBe(false);
        expect(ranked[0].reasons.join(" ")).not.toContain("perfect");
    });
});
