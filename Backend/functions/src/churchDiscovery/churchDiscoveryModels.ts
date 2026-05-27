export type DistancePreference = "nearby" | "within_10_miles" | "within_25_miles" | "online_ok" | "unspecified";

export type ChurchNextBestAction =
    "view_details"
    | "get_directions"
    | "visit_website"
    | "save"
    | "ask_berean"
    | "find_group"
    | "contact_church";

export interface UserLocationContext {
    latitude: number;
    longitude: number;
    label?: string | null;
}

export interface ChurchSearchIntent {
    denominationPreferences: string[];
    traditionPreferences: string[];
    worshipStyle: string[];
    teachingStyle: string[];
    communityNeeds: string[];
    lifeStage: string[];
    servicePreferences: string[];
    groupNeeds: string[];
    accessibilityNeeds: string[];
    languagePreferences: string[];
    distancePreference: DistancePreference;
    mustHave: string[];
    niceToHave: string[];
    avoid: string[];
    confidence: number;
    needsClarification: boolean;
    clarifyingQuestion: string | null;
}

export interface ChurchSearchRequest {
    rawQuery: string;
    approximateLocation?: UserLocationContext | null;
    filters?: Record<string, unknown>;
}

export interface GooglePlaceChurchCandidate {
    source: "google";
    placeId: string;
    displayName: string;
    formattedAddress: string;
    latitude: number | null;
    longitude: number | null;
    rating: number | null;
    userRatingCount: number | null;
    websiteUri: string | null;
    nationalPhoneNumber: string | null;
    regularOpeningHours: string[];
    photos: Array<{ name: string; widthPx?: number; heightPx?: number }>;
    googleMapsUri: string | null;
    businessStatus: string | null;
}

export interface AmenChurchProfileCandidate {
    source: "amen";
    churchId: string;
    name: string;
    denomination: string | null;
    traditionTags: string[];
    worshipStyleTags: string[];
    teachingStyleTags: string[];
    communityTags: string[];
    smallGroups: string[];
    ministries: string[];
    address: string;
    latitude: number | null;
    longitude: number | null;
    website: string | null;
    phone: string | null;
    googlePlaceId: string | null;
    hours: string[];
    photos: string[];
    accessibility: string[];
    verifiedByAmen: boolean;
    lastVerifiedAt: string | null;
    safetyStatus: string | null;
    sourceAttribution: string[];
    completeness: number;
}

export interface ChurchMatchScore {
    overall: number;
    confidence: number;
    categories: {
        intentMatch: number;
        communityFit: number;
        distanceTravelFit: number;
        ministryGroupFit: number;
        verifiedAmenData: number;
        freshnessCompleteness: number;
        accessibilityLanguageFit: number;
    };
}

export interface ChurchMatchExplanation {
    whyThisMayFit: string[];
    possibleMismatch: string[];
    verifiedFacts: string[];
    missingInfo: string[];
    sources: string[];
}

export interface ChurchSearchResult {
    id: string;
    churchId: string | null;
    googlePlaceId: string | null;
    name: string;
    denomination: string | null;
    address: string;
    latitude: number | null;
    longitude: number | null;
    distanceMiles: number | null;
    website: string | null;
    phone: string | null;
    googleMapsUri: string | null;
    verifiedByAmen: boolean;
    matchScore: ChurchMatchScore;
    explanation: ChurchMatchExplanation;
    summary: {
        thisMayFitBecause: string;
        checkThisFirst: string;
        bestNextStep: string;
    };
    nextBestAction: ChurchNextBestAction;
}

export interface ChurchDiscoveryAuditEvent {
    uid: string | null;
    event: string;
    searchId?: string;
    churchId?: string | null;
    googlePlaceId?: string | null;
    queryCategory?: string;
    createdAt?: FirebaseFirestore.FieldValue;
}

export const EMPTY_INTENT: ChurchSearchIntent = {
    denominationPreferences: [],
    traditionPreferences: [],
    worshipStyle: [],
    teachingStyle: [],
    communityNeeds: [],
    lifeStage: [],
    servicePreferences: [],
    groupNeeds: [],
    accessibilityNeeds: [],
    languagePreferences: [],
    distancePreference: "unspecified",
    mustHave: [],
    niceToHave: [],
    avoid: [],
    confidence: 0.35,
    needsClarification: false,
    clarifyingQuestion: null,
};
