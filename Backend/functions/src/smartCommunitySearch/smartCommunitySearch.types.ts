// All type definitions for Smart Community Search

export type CommunityResultType = "church" | "space" | "group" | "event" | "discussion" | "creator" | "mentor";
export type SmartSearchSurface = "find_church" | "spaces" | "discovery" | "global_search";
export type SafetySensitivity = "standard" | "high";
export type SmartSearchActionType = "view" | "save" | "directions" | "rsvp" | "message" | "join" | "askBerean" | "refineSearch";

export interface SmartCommunityLocationContext {
    lat: number;
    lng: number;
    accuracyMeters?: number;
}

export interface SmartCommunitySearchRequest {
    queryText: string;
    location?: SmartCommunityLocationContext;
    filters?: Record<string, unknown>;
    context?: {
        surface: SmartSearchSurface;
        previousSearchId?: string;
    };
}

export interface SmartCommunitySearchIntent {
    rawQuery: string;
    communityType: CommunityResultType | "mixed";
    denominations: string[];
    worshipStyle: string[];
    ageGroups: string[];
    languages: string[];
    accessibilityNeeds: string[];
    childcareNeeded: boolean;
    distancePreferenceMiles: number | null;
    schedulePreference: string | null;
    vibe: string[];
    spiritualNeed: string[];
    safetySensitivity: SafetySensitivity;
    searchExpansionTerms: string[];
    confidence: number;
    needsClarification: boolean;
    clarifyingQuestion: string | null;
}

export interface SmartCommunityAction {
    type: SmartSearchActionType;
    label: string;
    payload?: Record<string, unknown>;
}

export interface SmartCommunityRankedResult {
    id: string;
    source: "amen" | "google_maps";
    type: CommunityResultType;
    title: string;
    subtitle?: string;
    distanceLabel?: string;
    tags: string[];
    matchScore: number;
    reasons: string[];
    cautions?: string[];
    actions: SmartCommunityAction[];
    locationCoord?: { lat: number; lng: number };
    imageUrl?: string;
    primaryUrl?: string;
}

export interface SmartCommunitySearchResponse {
    searchId: string;
    interpretedIntent: SmartCommunitySearchIntent;
    results: SmartCommunityRankedResult[];
    refinementSuggestions: string[];
    safetyNotice?: string;
    usedExternalPlaces: boolean;
    usedAI: boolean;
}

export interface AmenInternalResult {
    id: string;
    type: CommunityResultType;
    title: string;
    subtitle?: string;
    description?: string;
    lat?: number;
    lng?: number;
    distanceMeters?: number;
    tags: string[];
    safetyStatus: "approved" | "limited" | "blocked";
    freshnessScore: number;
    activityScore: number;
    sourcePath: string;
    primaryAction: SmartSearchActionType;
    imageUrl?: string;
    primaryUrl?: string;
    isVerified?: boolean;
}

export const EMPTY_SMART_INTENT: SmartCommunitySearchIntent = {
    rawQuery: "",
    communityType: "mixed",
    denominations: [],
    worshipStyle: [],
    ageGroups: [],
    languages: [],
    accessibilityNeeds: [],
    childcareNeeded: false,
    distancePreferenceMiles: null,
    schedulePreference: null,
    vibe: [],
    spiritualNeed: [],
    safetySensitivity: "standard",
    searchExpansionTerms: [],
    confidence: 0.35,
    needsClarification: false,
    clarifyingQuestion: null,
};
