/**
 * smartCommunitySearch.googlePlaces.ts
 *
 * Thin adapter layer between Smart Community Search and the existing
 * churchDiscovery Google Places integration. Reuses all the battle-tested
 * HTTP logic from `googlePlacesChurchSearch`; only the request shaping and
 * response normalization are specific to the broader community search surface.
 */

import {
    googleMapsApiKey,
    googlePlacesApiKey,
    searchGooglePlacesForChurches,
} from "../churchDiscovery/googlePlacesChurchSearch";
import {
    AmenInternalResult as _AmenInternalResult, // imported to ensure type file is referenced
    CommunityResultType,
    SmartCommunityAction,
    SmartCommunityLocationContext,
    SmartCommunityRankedResult,
    SmartCommunitySearchIntent,
} from "./smartCommunitySearch.types";

// Re-export secrets so index.ts can list them in the `secrets` array.
export { googleMapsApiKey, googlePlacesApiKey };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Approximate straight-line distance between two WGS-84 coordinate pairs.
 * Returns a formatted label string (e.g. "1.2 mi" or "14 mi") or undefined
 * if either coordinate pair is missing.
 */
function approxDistanceLabel(
    from: SmartCommunityLocationContext | null | undefined,
    toLat: number | null,
    toLng: number | null
): string | undefined {
    if (!from || toLat === null || toLng === null) return undefined;
    const R = 3958.8; // earth radius in miles
    const dLat = ((toLat - from.lat) * Math.PI) / 180;
    const dLng = ((toLng - from.lng) * Math.PI) / 180;
    const lat1 = (from.lat * Math.PI) / 180;
    const lat2 = (toLat * Math.PI) / 180;
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
    const miles = R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return miles < 10 ? `${miles.toFixed(1)} mi` : `${Math.round(miles)} mi`;
}

/**
 * Map a `SmartCommunitySearchIntent` to the narrower `ChurchSearchIntent`
 * shape that `searchGooglePlacesForChurches` expects.
 */
function toChurchSearchIntent(intent: SmartCommunitySearchIntent) {
    const distanceEnum = (() => {
        const miles = intent.distancePreferenceMiles;
        if (miles === null) return "unspecified" as const;
        if (miles <= 5) return "nearby" as const;
        if (miles <= 10) return "within_10_miles" as const;
        return "within_25_miles" as const;
    })();

    return {
        denominationPreferences: intent.denominations,
        traditionPreferences: intent.vibe,
        worshipStyle: intent.worshipStyle,
        teachingStyle: [] as string[],
        communityNeeds: intent.spiritualNeed,
        lifeStage: intent.ageGroups,
        servicePreferences: intent.schedulePreference ? [intent.schedulePreference] : [] as string[],
        groupNeeds: [] as string[],
        accessibilityNeeds: intent.accessibilityNeeds,
        languagePreferences: intent.languages,
        distancePreference: distanceEnum,
        mustHave: intent.searchExpansionTerms.slice(0, 4),
        niceToHave: [] as string[],
        avoid: [] as string[],
        confidence: intent.confidence,
        needsClarification: intent.needsClarification,
        clarifyingQuestion: intent.clarifyingQuestion,
    };
}

function buildActions(
    placeId: string,
    mapsUrl: string | null,
    website: string | null
): SmartCommunityAction[] {
    const actions: SmartCommunityAction[] = [];

    if (mapsUrl) {
        actions.push({ type: "directions", label: "Directions", payload: { mapsUrl } });
    }
    if (mapsUrl) {
        actions.push({ type: "view", label: "View on Maps", payload: { url: mapsUrl } });
    } else if (website) {
        actions.push({ type: "view", label: "View Website", payload: { url: website } });
    }

    actions.push({ type: "askBerean", label: "Ask Berean", payload: { placeId } });
    actions.push({ type: "save", label: "Save", payload: { placeId } });

    return actions;
}

function buildReasons(rating: number | null, userRatingCount: number | null): string[] {
    const reasons: string[] = ["Found nearby via Google Maps"];
    if (rating !== null && userRatingCount !== null && userRatingCount > 0) {
        reasons.push(`Rated ${rating.toFixed(1)} / 5 by ${userRatingCount} reviews`);
    } else if (rating !== null) {
        reasons.push(`Rated ${rating.toFixed(1)} / 5`);
    }
    return reasons;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Search Google Places for community results matching the given intent.
 *
 * Returns an empty array when:
 * - No API key is available (mock key or emulator without a real key)
 * - No location is provided (required by the nearby/text-search calls)
 * - Any network error (fails silently; Amen internal results are still shown)
 */
export async function searchExternalPlaces(input: {
    intent: SmartCommunitySearchIntent;
    rawQuery: string;
    location?: SmartCommunityLocationContext | null;
    apiKey?: string;
}): Promise<SmartCommunityRankedResult[]> {
    const { intent, rawQuery, location, apiKey } = input;

    // External search requires a location signal — without it queries degrade.
    if (!location) return [];

    const churchIntent = toChurchSearchIntent(intent);
    const locationContext = { latitude: location.lat, longitude: location.lng, label: null };

    const candidates = await searchGooglePlacesForChurches({
        intent: churchIntent,
        rawQuery,
        location: locationContext,
        apiKey,
    });

    return candidates.map((place): SmartCommunityRankedResult => {
        const distLabel = approxDistanceLabel(location, place.latitude, place.longitude);
        const locCoord =
            place.latitude !== null && place.longitude !== null
                ? { lat: place.latitude, lng: place.longitude }
                : undefined;

        const tags: string[] = ["church"];
        if (place.businessStatus) tags.push(place.businessStatus.toLowerCase());

        return {
            id: place.placeId,
            source: "google_maps",
            type: "church" as CommunityResultType,
            title: place.displayName,
            subtitle: place.formattedAddress || undefined,
            distanceLabel: distLabel,
            tags,
            matchScore: 0.5, // Baseline; ranking engine will adjust.
            reasons: buildReasons(place.rating, place.userRatingCount),
            cautions: ["Amen has not independently verified this listing."],
            actions: buildActions(place.placeId, place.googleMapsUri, place.websiteUri),
            locationCoord: locCoord,
            primaryUrl: place.websiteUri ?? place.googleMapsUri ?? undefined,
        };
    });
}
