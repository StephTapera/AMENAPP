import * as admin from "firebase-admin";
import {
    AmenChurchProfileCandidate,
    ChurchDiscoveryFilters,
    ChurchMatchScore,
    ChurchSearchIntent,
    ChurchSearchResult,
    GooglePlaceChurchCandidate,
    UserLocationContext,
} from "./churchDiscoveryModels";

const db = admin.firestore();

export async function loadAmenChurchProfiles(location?: UserLocationContext | null, filters?: ChurchDiscoveryFilters): Promise<AmenChurchProfileCandidate[]> {
    const snapshot = await db.collection("churches")
        .where("isPublished", "==", true)
        .limit(location ? 300 : 120)
        .get();

    return snapshot.docs
        .map((doc) => normalizeAmenProfile(doc.id, doc.data(), location))
        .filter((profile) => passesAmenFilters(profile, filters))
        .sort((lhs, rhs) => {
            const lhsDistance = distanceFrom(location, lhs.latitude, lhs.longitude) ?? Number.MAX_SAFE_INTEGER;
            const rhsDistance = distanceFrom(location, rhs.latitude, rhs.longitude) ?? Number.MAX_SAFE_INTEGER;
            return lhsDistance - rhsDistance;
        })
        .slice(0, 120);
}

export function normalizeAmenProfile(
    churchId: string,
    data: FirebaseFirestore.DocumentData,
    _location?: UserLocationContext | null
): AmenChurchProfileCandidate {
    const list = (value: unknown): string[] => Array.isArray(value)
        ? value.map((item) => String(item ?? "").trim()).filter(Boolean)
        : [];
    const stringValue = (value: unknown): string | null => {
        const text = String(value ?? "").trim();
        return text || null;
    };
    const latitude = typeof data.latitude === "number" ? data.latitude : typeof data.coordinates?.latitude === "number" ? data.coordinates.latitude : null;
    const longitude = typeof data.longitude === "number" ? data.longitude : typeof data.coordinates?.longitude === "number" ? data.coordinates.longitude : null;
    const knownFields = [
        data.name, data.denomination, data.address, data.website, data.phone,
        latitude, longitude, data.googlePlaceId, data.updatedAt,
    ].filter((value) => value !== null && value !== undefined && String(value).trim() !== "").length;

    return {
        source: "amen",
        churchId,
        name: String(data.name ?? ""),
        denomination: stringValue(data.denomination),
        traditionTags: list(data.traditionTags),
        worshipStyleTags: list(data.worshipStyleTags ?? data.tags),
        teachingStyleTags: list(data.teachingStyleTags ?? data.tags),
        communityTags: list(data.communityTags ?? data.tags),
        smallGroups: list(data.smallGroups),
        ministries: list(data.ministries),
        address: String(data.address ?? ""),
        latitude,
        longitude,
        website: stringValue(data.website),
        phone: stringValue(data.phone ?? data.phoneNumber),
        googlePlaceId: stringValue(data.googlePlaceId),
        hours: list(data.hours),
        photos: list(data.photos),
        accessibility: list(data.accessibility),
        verifiedByAmen: Boolean(data.verifiedByAmen ?? data.isVerified ?? data.verified),
        lastVerifiedAt: stringValue(data.lastVerifiedAt),
        safetyStatus: stringValue(data.safetyStatus),
        sourceAttribution: list(data.sourceAttribution),
        completeness: Math.min(1, knownFields / 9),
    };
}

export function mergeAndRankChurchResults(input: {
    intent: ChurchSearchIntent;
    googleCandidates: GooglePlaceChurchCandidate[];
    amenCandidates: AmenChurchProfileCandidate[];
    location?: UserLocationContext | null;
    filters?: ChurchDiscoveryFilters;
}): ChurchSearchResult[] {
    const byKey = new Map<string, { google?: GooglePlaceChurchCandidate; amen?: AmenChurchProfileCandidate }>();

    for (const amen of input.amenCandidates) {
        const key = amen.googlePlaceId ?? `amen:${amen.churchId}`;
        byKey.set(key, { ...byKey.get(key), amen });
    }
    for (const google of input.googleCandidates) {
        const amenMatch = input.amenCandidates.find((amen) =>
            amen.googlePlaceId === google.placeId ||
            (amen.name && google.displayName && amen.name.toLowerCase() === google.displayName.toLowerCase())
        );
        const key = amenMatch?.googlePlaceId ?? google.placeId;
        byKey.set(key, { ...byKey.get(key), google, amen: amenMatch ?? byKey.get(key)?.amen });
    }

    return Array.from(byKey.values())
        .map((merged) => makeResult(input.intent, merged.google, merged.amen, input.location))
        .filter((result) => passesResultFilters(result, input.filters))
        .sort((lhs, rhs) => rhs.matchScore.overall - lhs.matchScore.overall)
        .slice(0, 30);
}

function makeResult(
    intent: ChurchSearchIntent,
    google?: GooglePlaceChurchCandidate,
    amen?: AmenChurchProfileCandidate,
    location?: UserLocationContext | null
): ChurchSearchResult {
    const latitude = amen?.latitude ?? google?.latitude ?? null;
    const longitude = amen?.longitude ?? google?.longitude ?? null;
    const distanceMiles = distanceFrom(location, latitude, longitude);
    const tags = [
        amen?.denomination,
        ...(amen?.traditionTags ?? []),
        ...(amen?.worshipStyleTags ?? []),
        ...(amen?.teachingStyleTags ?? []),
        ...(amen?.communityTags ?? []),
        ...(amen?.smallGroups ?? []),
        ...(amen?.ministries ?? []),
        ...(amen?.accessibility ?? []),
        google?.displayName,
    ].filter(Boolean).map((value) => String(value).toLowerCase());
    const semanticSimilarity = Math.max(amen?.semanticSimilarity ?? 0, google?.semanticSimilarity ?? 0);
    const score = scoreCandidate(intent, tags, amen, google, distanceMiles, semanticSimilarity);
    const why = makeWhy(intent, tags, amen, google, distanceMiles);
    const missing = [
        amen?.hours.length || google?.regularOpeningHours.length ? null : "Service times or hours are not verified yet.",
        amen?.smallGroups.length || amen?.ministries.length ? null : "Groups and ministries need confirmation.",
        amen?.accessibility.length ? null : "Accessibility details are not confirmed.",
    ].filter(Boolean) as string[];

    const verifiedFacts = [
        amen?.denomination ? `Denomination: ${amen.denomination}` : null,
        amen?.verifiedByAmen ? "Amen verified profile" : null,
        google?.formattedAddress ? `Address from Google: ${google.formattedAddress}` : null,
        google?.websiteUri ?? amen?.website ? "Website is listed" : null,
    ].filter(Boolean) as string[];

    return {
        id: amen?.churchId ?? google?.placeId ?? `candidate-${Math.random().toString(36).slice(2)}`,
        churchId: amen?.churchId ?? null,
        googlePlaceId: google?.placeId ?? amen?.googlePlaceId ?? null,
        name: amen?.name || google?.displayName || "Church",
        denomination: amen?.denomination ?? null,
        address: amen?.address || google?.formattedAddress || "",
        latitude,
        longitude,
        distanceMiles,
        website: amen?.website ?? google?.websiteUri ?? null,
        phone: amen?.phone ?? google?.nationalPhoneNumber ?? null,
        googleMapsUri: google?.googleMapsUri ?? null,
        verifiedByAmen: amen?.verifiedByAmen ?? false,
        matchScore: score,
        explanation: {
            whyThisMayFit: why,
            possibleMismatch: missing.slice(0, 2),
            verifiedFacts,
            missingInfo: missing,
            sources: [
                amen ? "Amen profile" : null,
                google ? "Google Places" : null,
            ].filter(Boolean) as string[],
        },
        summary: {
            thisMayFitBecause: why[0] ?? "This result has some matching location or profile signals.",
            checkThisFirst: missing[0] ?? "Confirm current service times before visiting.",
            bestNextStep: google?.googleMapsUri ? "Open directions or review the church website." : "Open details and verify the profile.",
        },
        nextBestAction: score.overall >= 72 ? "view_details" : google?.websiteUri || amen?.website ? "visit_website" : "ask_berean",
    };
}

export function scoreCandidate(
    intent: ChurchSearchIntent,
    tags: string[],
    amen?: AmenChurchProfileCandidate,
    google?: GooglePlaceChurchCandidate,
    distanceMiles?: number | null,
    semanticSimilarity = Math.max(amen?.semanticSimilarity ?? 0, google?.semanticSimilarity ?? 0)
): ChurchMatchScore {
    const contains = (need: string) => tags.some((tag) => tag.includes(need.toLowerCase()) || need.toLowerCase().includes(tag));
    const allIntentTerms = [
        ...intent.denominationPreferences,
        ...intent.traditionPreferences,
        ...intent.worshipStyle,
        ...intent.teachingStyle,
        ...intent.communityNeeds,
        ...intent.lifeStage,
        ...intent.groupNeeds,
    ];
    const matched = allIntentTerms.filter(contains).length;
    const lexicalIntentMatch = allIntentTerms.length ? matched / allIntentTerms.length : 0.45;
    const intentMatch = Math.max(lexicalIntentMatch, semanticSimilarity > 0 ? semanticSimilarity * 0.9 : 0);
    const communityFit = [...intent.communityNeeds, ...intent.lifeStage].some(contains) ? 1 : 0.35;
    const ministryGroupFit = intent.groupNeeds.some(contains) || (amen?.smallGroups.length ?? 0) > 0 ? 1 : 0.35;
    const distanceTravelFit = distanceScore(distanceMiles, intent.distancePreference);
    const verifiedAmenData = amen?.verifiedByAmen ? 1 : amen ? 0.45 : 0.15;
    const freshnessCompleteness = amen?.completeness ?? (google ? 0.45 : 0.2);
    const accessibilityLanguageFit = [...intent.accessibilityNeeds, ...intent.languagePreferences].length
        ? [...intent.accessibilityNeeds, ...intent.languagePreferences].some(contains) ? 1 : 0.15
        : 0.6;

    const overall = (
        intentMatch * 30 +
        communityFit * 20 +
        distanceTravelFit * 15 +
        ministryGroupFit * 15 +
        verifiedAmenData * 10 +
        freshnessCompleteness * 5 +
        accessibilityLanguageFit * 5
    );

    const confidence = Math.min(0.95, Math.max(0.2,
        (amen ? 0.3 : 0) +
        (google ? 0.2 : 0) +
        freshnessCompleteness * 0.25 +
        intent.confidence * 0.2
    ));

    return {
        overall: Math.round(overall),
        confidence,
        categories: {
            intentMatch,
            communityFit,
            distanceTravelFit,
            ministryGroupFit,
            verifiedAmenData,
            freshnessCompleteness,
            accessibilityLanguageFit,
        },
    };
}

function makeWhy(
    intent: ChurchSearchIntent,
    tags: string[],
    amen?: AmenChurchProfileCandidate,
    google?: GooglePlaceChurchCandidate,
    distanceMiles?: number | null
): string[] {
    const reasons: string[] = [];
    const wanted = [...intent.mustHave, ...intent.niceToHave];
    for (const need of wanted) {
        if (tags.some((tag) => tag.includes(need.toLowerCase()) || need.toLowerCase().includes(tag))) {
            reasons.push(`Matches your interest in ${need}.`);
        }
        if (reasons.length >= 3) break;
    }
    if (distanceMiles !== null && distanceMiles !== undefined) reasons.push(`About ${distanceMiles.toFixed(1)} miles away.`);
    if (amen?.verifiedByAmen) reasons.push("Amen has verified profile data for this church.");
    if (google?.formattedAddress) reasons.push("Google Places provides a current address.");
    return reasons.length ? reasons : ["This result matches general church discovery signals near your search area."];
}

function distanceScore(distanceMiles: number | null | undefined, preference: string): number {
    if (preference === "online_ok") return 0.75;
    if (distanceMiles === null || distanceMiles === undefined) return 0.35;
    const max = preference === "nearby" ? 5 : preference === "within_10_miles" ? 10 : 25;
    return Math.max(0.05, Math.min(1, 1 - distanceMiles / Math.max(max, 1)));
}

function distanceFrom(location: UserLocationContext | null | undefined, latitude: number | null, longitude: number | null): number | null {
    if (!location || latitude === null || longitude === null) return null;
    const toRadians = (degrees: number) => degrees * Math.PI / 180;
    const earthMiles = 3958.8;
    const dLat = toRadians(latitude - location.latitude);
    const dLon = toRadians(longitude - location.longitude);
    const a = Math.sin(dLat / 2) ** 2 +
        Math.cos(toRadians(location.latitude)) * Math.cos(toRadians(latitude)) *
        Math.sin(dLon / 2) ** 2;
    return earthMiles * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normalizedIncludes(haystack: string[], needle?: string | string[] | null): boolean {
    if (!needle || (Array.isArray(needle) && needle.length === 0)) return true;
    const needles = Array.isArray(needle) ? needle : [needle];
    return needles.some((n) => {
        const value = String(n ?? "").trim().toLowerCase();
        if (!value) return true;
        return haystack.some((item) => {
            const normalized = item.toLowerCase();
            if (!normalized) return false;
            return normalized.includes(value) || value.includes(normalized);
        });
    });
}

function passesAmenFilters(profile: AmenChurchProfileCandidate, filters?: ChurchDiscoveryFilters): boolean {
    if (!filters) return true;
    const searchable = [
        profile.denomination ?? "",
        ...profile.traditionTags,
        ...profile.worshipStyleTags,
        ...profile.teachingStyleTags,
        ...profile.communityTags,
        ...profile.smallGroups,
        ...profile.ministries,
        ...profile.accessibility,
        ...profile.hours,
    ];

    if (!normalizedIncludes([profile.denomination ?? ""], filters.denomination)) return false;
    if (!normalizedIncludes(profile.worshipStyleTags, filters.worshipStyle)) return false;
    if (!normalizedIncludes(profile.teachingStyleTags, filters.teachingStyle)) return false;
    if (!normalizedIncludes([...profile.smallGroups, ...profile.ministries, ...profile.communityTags], filters.groupNeed)) return false;
    if (!normalizedIncludes(profile.accessibility, filters.accessibilityNeed)) return false;
    if (!normalizedIncludes(searchable, filters.language)) return false;
    if (!normalizedIncludes(profile.hours, filters.serviceTime)) return false;
    return true;
}

function passesResultFilters(result: ChurchSearchResult, filters?: ChurchDiscoveryFilters): boolean {
    if (!filters) return true;
    if (typeof filters.distanceMiles === "number" && result.distanceMiles !== null && result.distanceMiles > filters.distanceMiles) return false;
    const resultText = [
        result.name,
        result.denomination ?? "",
        result.address,
        result.summary.thisMayFitBecause,
        result.summary.checkThisFirst,
        ...result.explanation.whyThisMayFit,
        ...result.explanation.verifiedFacts,
        ...result.explanation.missingInfo,
    ];
    if (!normalizedIncludes(resultText, filters.denomination)) return false;
    if (!normalizedIncludes(resultText, filters.worshipStyle)) return false;
    if (!normalizedIncludes(resultText, filters.teachingStyle)) return false;
    if (!normalizedIncludes(resultText, filters.groupNeed)) return false;
    if (!normalizedIncludes(resultText, filters.accessibilityNeed)) return false;
    if (!normalizedIncludes(resultText, filters.language)) return false;
    if (!normalizedIncludes(resultText, filters.serviceTime)) return false;
    return true;
}
