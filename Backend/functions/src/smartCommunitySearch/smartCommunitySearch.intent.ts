/**
 * smartCommunitySearch.intent.ts
 *
 * Intent parser for Smart Community Search.
 *
 * Primary path: delegates to the existing church-discovery structured-output
 * parser (`parseIntentWithStructuredOutputs`) and maps the result into the
 * broader `SmartCommunitySearchIntent` shape (which covers churches, spaces,
 * groups, events, creators, and mentors — not just churches).
 *
 * Fallback path: `heuristicSmartIntent` — fast, deterministic, zero external
 * calls. Used when the API key is absent/mocked, the OpenAI call fails, or the
 * query is too short to parse meaningfully.
 */

import { parseIntentWithStructuredOutputs, openaiApiKey } from "../churchDiscovery/parseChurchSearchIntent";
import {
    CommunityResultType,
    EMPTY_SMART_INTENT,
    SmartCommunityLocationContext,
    SmartCommunitySearchIntent,
} from "./smartCommunitySearch.types";

// ---------------------------------------------------------------------------
// Vocabulary lists for heuristic detection
// ---------------------------------------------------------------------------

const DENOMINATION_TERMS = [
    "baptist", "catholic", "methodist", "presbyterian", "pentecostal",
    "lutheran", "anglican", "episcopal", "orthodox", "non-denominational",
    "nondenominational", "assemblies of god", "reformed", "bible church",
    "church of christ",
];

const AGE_GROUP_TERMS = [
    "young adult", "young adults", "college", "youth", "students", "teen",
    "senior", "seniors", "families", "family", "kids", "children", "toddler",
    "nursery", "millennial",
];

const WORSHIP_STYLE_TERMS = [
    "worship", "contemporary", "traditional", "gospel", "liturgical",
    "acoustic", "charismatic", "spirit-filled", "spirit filled", "praise",
    "hymns",
];

const VIBE_TERMS = [
    "diverse", "quiet", "small", "large", "welcoming", "inclusive",
    "modern", "historic", "intimate", "multicultural", "vibrant",
    "community", "close-knit",
];

const SPIRITUAL_NEED_TERMS = [
    "prayer", "healing", "grief", "recovery", "support", "new believer",
    "discipleship", "accountability", "mentor", "mentorship", "bible study",
    "faith formation",
];

const LANGUAGE_TERMS = [
    "english", "spanish", "french", "korean", "chinese", "mandarin",
    "arabic", "portuguese", "haitian creole", "vietnamese", "tagalog",
];

// ---------------------------------------------------------------------------
// Community type detection
// ---------------------------------------------------------------------------

function detectCommunityType(query: string): CommunityResultType | "mixed" {
    const q = query.toLowerCase();

    // Check for non-church types first; church keywords are used as a fallback.
    if (/\b(event|rsvp|tonight|this week|calendar|happening)\b/.test(q)) return "event";
    if (/\b(podcast|creator|teacher|speaker|content)\b/.test(q)) return "creator";
    if (/\b(mentor|coach|discipleship|one on one|1:1|spiritual director)\b/.test(q)) return "mentor";
    if (/\b(community space|room|venue|gathering space)\b/.test(q) && !/\b(church|service|worship)\b/.test(q)) return "space";
    if (/\b(small group|bible study|study group|life group|connect group)\b/.test(q) && !/\b(church|worship|service)\b/.test(q)) return "group";
    if (/\b(church|service|worship|denomination|congregation|pastor|ministry)\b/.test(q)) return "church";

    return "mixed";
}

// ---------------------------------------------------------------------------
// Distance preference helpers
// ---------------------------------------------------------------------------

function extractDistanceMiles(query: string): number | null {
    const distanceMatch = query.match(/(\d{1,3})\s*(mi(?:les?)?|km)\b/i);
    if (!distanceMatch) return null;
    const value = Number(distanceMatch[1]);
    const unit = distanceMatch[2].toLowerCase();
    // Convert km to miles if needed.
    return unit.startsWith("km") ? Math.round(value * 0.621371) : value;
}

function includesAny(query: string, terms: string[]): string[] {
    const q = query.toLowerCase();
    return terms.filter((term) => q.includes(term.toLowerCase()));
}

// ---------------------------------------------------------------------------
// Heuristic fallback
// ---------------------------------------------------------------------------

/**
 * Fast deterministic intent parser. No network calls.
 * Used when AI is unavailable or as a final fallback.
 */
export function heuristicSmartIntent(query: string): SmartCommunitySearchIntent {
    if (!query || query.trim().length < 3) {
        return {
            ...EMPTY_SMART_INTENT,
            needsClarification: true,
            clarifyingQuestion: "What kind of community are you looking for? A church, group, event, or something else?",
        };
    }

    const q = query.toLowerCase();

    const denominations = includesAny(q, DENOMINATION_TERMS).map((term) =>
        term === "nondenominational" ? "non-denominational" : term
    );
    const worshipStyle = includesAny(q, WORSHIP_STYLE_TERMS);
    const ageGroups = includesAny(q, AGE_GROUP_TERMS);
    const languages = includesAny(q, LANGUAGE_TERMS);
    const vibe = includesAny(q, VIBE_TERMS);
    const spiritualNeed = includesAny(q, SPIRITUAL_NEED_TERMS);

    const childcareNeeded =
        /\b(childcare|kids ministry|nursery|children's program|family friendly)\b/i.test(q);

    const accessibilityNeeds: string[] = [];
    if (/\b(wheelchair|accessible|mobility impaired|ada)\b/i.test(q)) {
        accessibilityNeeds.push("wheelchair accessible");
    }
    if (/\b(asl|sign language|deaf|hard of hearing)\b/i.test(q)) {
        accessibilityNeeds.push("ASL interpretation");
    }
    if (/\b(captions?|closed caption)\b/i.test(q)) {
        accessibilityNeeds.push("captioning");
    }

    const safetySensitivity =
        childcareNeeded || /\b(kids|children|family|safe|vetted|background check)\b/i.test(q)
            ? "high"
            : "standard";

    const scheduleMatch =
        /\b(this week|tonight|sunday|saturday|morning|evening|weekend|online)\b/i.exec(q);
    const schedulePreference = scheduleMatch ? scheduleMatch[0] : null;

    const distancePreferenceMiles = extractDistanceMiles(q);

    const expansionTerms = Array.from(new Set([
        ...denominations,
        ...ageGroups,
        ...worshipStyle,
        ...vibe,
        ...(childcareNeeded ? ["childcare"] : []),
        "church",
        "community",
    ].filter(Boolean)));

    const confidence = Math.min(
        0.9,
        0.35 +
        denominations.length * 0.07 +
        ageGroups.length * 0.05 +
        worshipStyle.length * 0.04 +
        spiritualNeed.length * 0.04
    );

    const needsClarification = query.trim().length < 12;
    const clarifyingQuestion = needsClarification
        ? "What matters most to you: denomination, worship style, community groups, location, or something else?"
        : null;

    return {
        rawQuery: query,
        communityType: detectCommunityType(q),
        denominations,
        worshipStyle,
        ageGroups,
        languages,
        accessibilityNeeds,
        childcareNeeded,
        distancePreferenceMiles,
        schedulePreference,
        vibe,
        spiritualNeed,
        safetySensitivity,
        searchExpansionTerms: expansionTerms,
        confidence,
        needsClarification,
        clarifyingQuestion,
    };
}

// ---------------------------------------------------------------------------
// Mapper: ChurchSearchIntent → SmartCommunitySearchIntent
// ---------------------------------------------------------------------------

function mapChurchIntentToSmart(
    churchIntent: Awaited<ReturnType<typeof parseIntentWithStructuredOutputs>>,
    rawQuery: string,
    location?: SmartCommunityLocationContext | null
): SmartCommunitySearchIntent {
    const communityType = detectCommunityType(rawQuery);

    // Vibe derives from worshipStyle + traditionPreferences.
    const vibe = Array.from(new Set([
        ...churchIntent.worshipStyle,
        ...churchIntent.traditionPreferences,
    ])).slice(0, 8);

    // Spiritual need from communityNeeds (e.g., "Grief support", "Recovery", "Prayer").
    const spiritualNeed = churchIntent.communityNeeds.slice(0, 8);

    // Distance: map from church's enum to a numeric miles value.
    const distanceMap: Record<string, number | null> = {
        nearby: 5,
        within_10_miles: 10,
        within_25_miles: 25,
        online_ok: null,
        unspecified: null,
    };
    const distancePreferenceMiles = distanceMap[churchIntent.distancePreference] ?? null;

    // Accumulate expansion terms.
    const expansionTerms = Array.from(new Set([
        ...churchIntent.denominationPreferences,
        ...churchIntent.worshipStyle,
        ...churchIntent.lifeStage,
        ...churchIntent.groupNeeds,
        ...churchIntent.communityNeeds,
        "church",
        "community",
    ].filter(Boolean))).slice(0, 12);

    const childcareNeeded =
        churchIntent.lifeStage.some((s) => /famil|kids|children|nursery/i.test(s)) ||
        churchIntent.groupNeeds.some((g) => /childcare/i.test(g));

    const safetySensitivity = childcareNeeded ? "high" : "standard";

    void location; // location is available for context; downstream uses it separately.

    return {
        rawQuery,
        communityType,
        denominations: churchIntent.denominationPreferences,
        worshipStyle: churchIntent.worshipStyle,
        ageGroups: churchIntent.lifeStage,
        languages: churchIntent.languagePreferences,
        accessibilityNeeds: churchIntent.accessibilityNeeds,
        childcareNeeded,
        distancePreferenceMiles,
        schedulePreference: churchIntent.servicePreferences.length > 0
            ? churchIntent.servicePreferences[0]
            : null,
        vibe,
        spiritualNeed,
        safetySensitivity,
        searchExpansionTerms: expansionTerms,
        confidence: churchIntent.confidence,
        needsClarification: churchIntent.needsClarification,
        clarifyingQuestion: churchIntent.clarifyingQuestion,
    };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Parse a raw search query into a `SmartCommunitySearchIntent`.
 *
 * If an OpenAI API key is available, delegates to `parseIntentWithStructuredOutputs`
 * (the existing church-discovery AI parser) and maps the result. Falls back to
 * `heuristicSmartIntent` on any error or when no valid API key is present.
 *
 * Short queries (< 3 chars) skip AI and return a clarifying intent immediately.
 */
export async function parseSmartCommunityIntent(input: {
    rawQuery: string;
    location?: SmartCommunityLocationContext | null;
    apiKey?: string;
}): Promise<SmartCommunitySearchIntent> {
    const { rawQuery, location, apiKey } = input;

    if (!rawQuery || rawQuery.trim().length < 3) {
        return {
            ...EMPTY_SMART_INTENT,
            rawQuery,
            needsClarification: true,
            clarifyingQuestion: "What kind of community are you looking for? A church, group, event, or something else?",
        };
    }

    const resolvedKey = apiKey ?? (() => {
        try {
            return openaiApiKey.value();
        } catch {
            return undefined;
        }
    })();

    // If no usable API key, go straight to heuristic.
    if (!resolvedKey || resolvedKey.startsWith("mock-")) {
        return heuristicSmartIntent(rawQuery);
    }

    try {
        const churchIntent = await parseIntentWithStructuredOutputs({
            rawQuery,
            approximateLocation: location
                ? { latitude: location.lat, longitude: location.lng, label: null }
                : null,
            apiKey: resolvedKey,
        });
        return mapChurchIntentToSmart(churchIntent, rawQuery, location);
    } catch {
        return heuristicSmartIntent(rawQuery);
    }
}
