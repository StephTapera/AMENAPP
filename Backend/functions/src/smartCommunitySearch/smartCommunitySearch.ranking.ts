import {
    AmenInternalResult,
    SmartCommunityAction,
    SmartCommunityRankedResult,
    SmartCommunitySearchIntent,
    SmartSearchActionType,
} from "./smartCommunitySearch.types";

function distanceLabel(distanceMeters?: number): string | undefined {
    if (typeof distanceMeters !== "number") return undefined;
    const miles = distanceMeters / 1609.34;
    return miles < 10 ? `${miles.toFixed(1)} mi` : `${Math.round(miles)} mi`;
}

function textMatchScore(text: string, intent: SmartCommunitySearchIntent): number {
    const haystack = text.toLowerCase();
    const terms = [intent.rawQuery, ...intent.searchExpansionTerms]
        .map((term) => term.toLowerCase())
        .filter((term) => term.length > 2);
    if (terms.length === 0) return 0.2;
    return terms.reduce((score, term) => score + (haystack.includes(term) ? 1 : 0), 0) / terms.length;
}

function proximityScore(distanceMeters?: number, preferenceMiles: number | null = null): number {
    if (typeof distanceMeters !== "number") return 0.25;
    const preferredMeters = (preferenceMiles ?? 15) * 1609.34;
    return Math.max(0, 1 - distanceMeters / Math.max(preferredMeters, 1));
}

function actionLabel(type: SmartSearchActionType): string {
    switch (type) {
    case "view": return "View Details";
    case "save": return "Save";
    case "directions": return "Directions";
    case "rsvp": return "RSVP";
    case "message": return "Message";
    case "join": return "Join";
    case "askBerean": return "Ask Berean";
    case "refineSearch": return "Refine";
    }
}

function actionsForAmen(result: AmenInternalResult) {
    const actions: SmartCommunityAction[] = [
        { type: "view" as SmartSearchActionType, label: actionLabel("view"), payload: { sourcePath: result.sourcePath } },
        { type: "save" as SmartSearchActionType, label: actionLabel("save"), payload: { sourcePath: result.sourcePath } },
        { type: "askBerean" as SmartSearchActionType, label: actionLabel("askBerean"), payload: { sourcePath: result.sourcePath } },
    ];
    if (typeof result.lat === "number" && typeof result.lng === "number") {
        actions.push({
            type: "directions",
            label: actionLabel("directions"),
            payload: { mapsUrl: `maps://?daddr=${result.lat},${result.lng}` },
        });
    }
    if (result.type === "event") actions.push({ type: "rsvp", label: actionLabel("rsvp"), payload: { sourcePath: result.sourcePath } });
    if (result.type === "space" || result.type === "group") actions.push({ type: "join", label: actionLabel("join"), payload: { sourcePath: result.sourcePath } });
    if (result.type === "mentor") actions.push({ type: "message", label: actionLabel("message"), payload: { sourcePath: result.sourcePath } });
    return actions;
}

export function rankAmenInternalResults(
    results: AmenInternalResult[],
    intent: SmartCommunitySearchIntent
): SmartCommunityRankedResult[] {
    return results.map((result): SmartCommunityRankedResult => {
        const textScore = textMatchScore(`${result.title} ${result.subtitle ?? ""} ${result.description ?? ""} ${result.tags.join(" ")}`, intent);
        const activity = Math.min(result.activityScore > 1 ? result.activityScore / 100 : result.activityScore, 1);
        const score = (
            textScore * 0.38 +
            proximityScore(result.distanceMeters, intent.distancePreferenceMiles) * 0.22 +
            (result.safetyStatus === "approved" ? 1 : 0.3) * 0.16 +
            Math.min(result.freshnessScore, 1) * 0.12 +
            activity * 0.08 +
            (result.isVerified ? 0.04 : 0)
        );

        return {
            id: result.id,
            source: "amen",
            type: result.type,
            title: result.title,
            subtitle: result.subtitle,
            distanceLabel: distanceLabel(result.distanceMeters),
            tags: result.tags,
            matchScore: Math.max(0, Math.min(score, 1)),
            reasons: [
                textScore > 0.5 ? "Strong match for your search terms." : "Possible match based on available profile details.",
                result.distanceMeters ? "Close enough to compare with nearby options." : "Distance is not confirmed yet.",
                result.isVerified ? "Verified Amen profile information is available." : "Uses available Amen profile details.",
            ],
            cautions: result.safetyStatus === "limited" ? ["Some safety or visibility limits apply."] : undefined,
            actions: actionsForAmen(result),
            locationCoord: typeof result.lat === "number" && typeof result.lng === "number" ? { lat: result.lat, lng: result.lng } : undefined,
            imageUrl: result.imageUrl,
            primaryUrl: result.primaryUrl,
        };
    }).sort((a, b) => b.matchScore - a.matchScore);
}

export function combineAndDedupeRankedResults(
    amenResults: SmartCommunityRankedResult[],
    externalResults: SmartCommunityRankedResult[]
): SmartCommunityRankedResult[] {
    const seen = new Set<string>();
    return [...amenResults, ...externalResults]
        .filter((result) => {
            const key = `${result.source}:${result.id}`;
            if (seen.has(key)) return false;
            seen.add(key);
            return true;
        })
        .sort((a, b) => b.matchScore - a.matchScore)
        .slice(0, 20);
}

export function refinementSuggestions(intent: SmartCommunitySearchIntent, resultCount: number): string[] {
    const base = ["Closer", "Has childcare", "Young adults", "Bible study this week", "More diverse"];
    if (resultCount === 0) return ["Try a nearby city", "Expand distance", "Search churches only", "Search groups this week"];
    if (intent.communityType === "church") return ["Find a small group too", ...base.slice(0, 4)];
    return base;
}
