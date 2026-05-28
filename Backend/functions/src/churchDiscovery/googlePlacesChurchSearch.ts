import { defineSecret } from "firebase-functions/params";
import { ChurchSearchIntent, GooglePlaceChurchCandidate, UserLocationContext } from "./churchDiscoveryModels";

export const googlePlacesApiKey = defineSecret("GOOGLE_PLACES_API_KEY");
export const googleMapsApiKey = defineSecret("GOOGLE_MAPS_API_KEY");

const TEXT_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText";
const NEARBY_SEARCH_URL = "https://places.googleapis.com/v1/places:searchNearby";
const PLACE_DETAILS_FIELD_MASK = [
    "id",
    "displayName",
    "formattedAddress",
    "location",
    "rating",
    "userRatingCount",
    "websiteUri",
    "nationalPhoneNumber",
    "regularOpeningHours",
    "photos",
    "googleMapsUri",
    "businessStatus",
].join(",");
const FIELD_MASK = [
    "places.id",
    "places.displayName",
    "places.formattedAddress",
    "places.location",
    "places.rating",
    "places.userRatingCount",
    "places.websiteUri",
    "places.nationalPhoneNumber",
    "places.regularOpeningHours",
    "places.photos",
    "places.googleMapsUri",
    "places.businessStatus",
].join(",");

type GooglePlace = Record<string, unknown>;

export function buildGoogleChurchQueries(intent: ChurchSearchIntent, location?: UserLocationContext | null): string[] {
    const near = location ? ` near ${location.latitude},${location.longitude}` : " near me";
    const terms = new Set<string>(["church"]);
    for (const denom of intent.denominationPreferences) terms.add(`${denom} church`);
    for (const style of [...intent.teachingStyle, ...intent.worshipStyle, ...intent.communityNeeds, ...intent.lifeStage, ...intent.groupNeeds]) {
        const lowered = style.toLowerCase();
        if (lowered.includes("bible")) terms.add("Bible church");
        if (lowered.includes("young")) terms.add("young adult church");
        if (lowered.includes("small")) terms.add("church small groups");
        if (lowered.includes("recovery")) terms.add("church recovery group");
        if (lowered.includes("worship")) terms.add("worship night church");
    }
    return Array.from(terms).slice(0, 6).map((term) => `${term}${near}`);
}

export async function searchGooglePlacesForChurches(input: {
    intent: ChurchSearchIntent;
    rawQuery: string;
    location?: UserLocationContext | null;
    apiKey?: string;
}): Promise<GooglePlaceChurchCandidate[]> {
    const apiKey = input.apiKey ?? googlePlacesApiKey.value() ?? googleMapsApiKey.value();
    if (!apiKey || apiKey.startsWith("mock-")) return [];

    const queries = buildGoogleChurchQueries(input.intent, input.location);
    const candidates: GooglePlaceChurchCandidate[] = [];
    const seen = new Set<string>();

    if (input.location) {
        const nearby = await callGooglePlaces(NEARBY_SEARCH_URL, apiKey, {
            includedTypes: ["church"],
            maxResultCount: 10,
            locationRestriction: {
                circle: {
                    center: { latitude: input.location.latitude, longitude: input.location.longitude },
                    radius: radiusFor(input.intent),
                },
            },
        });
        for (const place of nearby) addCandidate(place, candidates, seen);
    }

    for (const textQuery of queries) {
        const places = await callGooglePlaces(TEXT_SEARCH_URL, apiKey, {
            textQuery,
            maxResultCount: 8,
            locationBias: input.location ? {
                circle: {
                    center: { latitude: input.location.latitude, longitude: input.location.longitude },
                    radius: radiusFor(input.intent),
                },
            } : undefined,
        });
        for (const place of places) addCandidate(place, candidates, seen);
        if (candidates.length >= 24) break;
    }

    return candidates;
}

export async function loadGooglePlaceDetails(input: {
    googlePlaceId: string;
    apiKey?: string;
}): Promise<GooglePlaceChurchCandidate | null> {
    const apiKey = input.apiKey ?? googlePlacesApiKey.value() ?? googleMapsApiKey.value();
    if (!apiKey || apiKey.startsWith("mock-")) return null;
    const safePlaceId = input.googlePlaceId.replace(/^places\//, "");
    const response = await fetch(`https://places.googleapis.com/v1/places/${encodeURIComponent(safePlaceId)}`, {
        method: "GET",
        headers: {
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": PLACE_DETAILS_FIELD_MASK,
        },
    });
    if (!response.ok) return null;
    const place = await response.json() as GooglePlace;
    return normalizeGooglePlace(place);
}

async function callGooglePlaces(url: string, apiKey: string, body: Record<string, unknown>): Promise<GooglePlace[]> {
    const response = await fetch(url, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": FIELD_MASK,
        },
        body: JSON.stringify(body),
    });
    if (!response.ok) return [];
    const json = await response.json() as { places?: GooglePlace[] };
    return json.places ?? [];
}

function radiusFor(intent: ChurchSearchIntent): number {
    switch (intent.distancePreference) {
    case "nearby": return 8_000;
    case "within_10_miles": return 16_094;
    case "within_25_miles": return 40_234;
    case "online_ok":
    case "unspecified":
    default: return 24_140;
    }
}

function addCandidate(place: GooglePlace, candidates: GooglePlaceChurchCandidate[], seen: Set<string>): void {
    const candidate = normalizeGooglePlace(place);
    if (!candidate.placeId || seen.has(candidate.placeId)) return;
    seen.add(candidate.placeId);
    candidates.push(candidate);
}

export function normalizeGooglePlace(place: GooglePlace): GooglePlaceChurchCandidate {
    const displayName = place.displayName as { text?: string } | undefined;
    const location = place.location as { latitude?: number; longitude?: number } | undefined;
    const hours = place.regularOpeningHours as { weekdayDescriptions?: string[] } | undefined;
    const photos = Array.isArray(place.photos) ? place.photos as Array<Record<string, unknown>> : [];
    return {
        source: "google",
        placeId: String(place.id ?? ""),
        displayName: String(displayName?.text ?? ""),
        formattedAddress: String(place.formattedAddress ?? ""),
        latitude: typeof location?.latitude === "number" ? location.latitude : null,
        longitude: typeof location?.longitude === "number" ? location.longitude : null,
        rating: typeof place.rating === "number" ? place.rating : null,
        userRatingCount: typeof place.userRatingCount === "number" ? place.userRatingCount : null,
        websiteUri: typeof place.websiteUri === "string" ? place.websiteUri : null,
        nationalPhoneNumber: typeof place.nationalPhoneNumber === "string" ? place.nationalPhoneNumber : null,
        regularOpeningHours: hours?.weekdayDescriptions ?? [],
        photos: photos.map((photo) => ({
            name: String(photo.name ?? ""),
            widthPx: typeof photo.widthPx === "number" ? photo.widthPx : undefined,
            heightPx: typeof photo.heightPx === "number" ? photo.heightPx : undefined,
        })).filter((photo) => photo.name),
        googleMapsUri: typeof place.googleMapsUri === "string" ? place.googleMapsUri : null,
        businessStatus: typeof place.businessStatus === "string" ? place.businessStatus : null,
    };
}
