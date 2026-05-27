import { randomUUID } from "crypto";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { openaiApiKey } from "../churchDiscovery/parseChurchSearchIntent";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import { searchAmenInternal } from "./smartCommunitySearch.amenSearch";
import { recordSmartSearchAnalytics } from "./smartCommunitySearch.analytics";
import { searchExternalPlaces, googleMapsApiKey, googlePlacesApiKey } from "./smartCommunitySearch.googlePlaces";
import { heuristicSmartIntent, parseSmartCommunityIntent } from "./smartCommunitySearch.intent";
import {
    combineAndDedupeRankedResults,
    rankAmenInternalResults,
    refinementSuggestions,
} from "./smartCommunitySearch.ranking";
import { classifySafetyRisk, sanitizeSmartQuery } from "./smartCommunitySearch.safety";
import {
    EMPTY_SMART_INTENT,
    SmartCommunityLocationContext,
    SmartCommunitySearchRequest,
    SmartCommunitySearchResponse,
} from "./smartCommunitySearch.types";

const REGION = "us-central1";
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

function enabledFromEnv(name: string, fallback: boolean): boolean {
    const raw = process.env[name];
    if (raw === undefined || raw === "") return fallback;
    return raw.toLowerCase() === "true";
}

function readLocation(value: unknown): SmartCommunityLocationContext | undefined {
    if (!value || typeof value !== "object") return undefined;
    const record = value as Record<string, unknown>;
    const lat = record.lat;
    const lng = record.lng;
    if (typeof lat !== "number" || typeof lng !== "number") return undefined;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return undefined;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return undefined;
    return {
        lat,
        lng,
        accuracyMeters: typeof record.accuracyMeters === "number" ? record.accuracyMeters : undefined,
    };
}

function readQueryText(value: unknown): string {
    const query = sanitizeSmartQuery(String(value ?? ""));
    if (!query) {
        throw new HttpsError("invalid-argument", "queryText is required.");
    }
    return query;
}

export const smartCommunitySearch = onCall(
    {
        region: REGION,
        enforceAppCheck: true,
        timeoutSeconds: 30,
        memory: "512MiB",
        secrets: [openaiApiKey, googlePlacesApiKey, googleMapsApiKey],
    },
    async (request): Promise<SmartCommunitySearchResponse> => {
        const startedAt = Date.now();
        if (!IS_EMULATOR && !request.app?.appId) {
            throw new HttpsError("failed-precondition", "App Check token required.");
        }

        const uid = request.auth?.uid;
        if (!uid) {
            throw new HttpsError("unauthenticated", "Authentication required.");
        }

        if (!enabledFromEnv("SMART_COMMUNITY_SEARCH_ENABLED", true)) {
            throw new HttpsError("failed-precondition", "Smart community search is disabled.");
        }

        await enforceRateLimit(uid, [
            RATE_LIMITS.CHURCH_SUGGESTION_PER_MINUTE,
            RATE_LIMITS.CHURCH_SUGGESTION_PER_DAY,
        ]);

        const data = (request.data ?? {}) as Partial<SmartCommunitySearchRequest>;
        const queryText = readQueryText(data.queryText);
        const safety = classifySafetyRisk(queryText);
        const searchId = randomUUID();
        const surface = data.context?.surface ?? "find_church";

        if (safety.blocked) {
            await recordSmartSearchAnalytics({
                searchId,
                uid,
                surface,
                intent: { ...EMPTY_SMART_INTENT, safetySensitivity: "high" },
                resultCount: 0,
                latencyMs: Date.now() - startedAt,
                usedExternalPlaces: false,
                usedAI: false,
                safetyBlocked: true,
            });
            return {
                searchId,
                interpretedIntent: { ...EMPTY_SMART_INTENT, safetySensitivity: "high" },
                results: [],
                refinementSuggestions: [],
                safetyNotice: "This search cannot be completed because it may request unsafe or abusive content.",
                usedExternalPlaces: false,
                usedAI: false,
            };
        }

        const location = readLocation(data.location);
        const aiEnabled = enabledFromEnv("SMART_COMMUNITY_SEARCH_AI_ENABLED", false);
        const externalEnabled = enabledFromEnv("SMART_COMMUNITY_SEARCH_EXTERNAL_PLACES_ENABLED", false);
        const intent = aiEnabled
            ? await parseSmartCommunityIntent({ rawQuery: queryText, location })
            : heuristicSmartIntent(queryText);

        if (safety.isCrisis) {
            intent.safetySensitivity = "high";
        }

        const [amenInternal, externalRanked] = await Promise.all([
            searchAmenInternal({ intent, location, uid }),
            externalEnabled && !safety.isCrisis
                ? searchExternalPlaces({ intent, rawQuery: queryText, location })
                : Promise.resolve([]),
        ]);

        const ranked = combineAndDedupeRankedResults(
            rankAmenInternalResults(amenInternal, intent),
            externalRanked
        );

        await recordSmartSearchAnalytics({
            searchId,
            uid,
            surface,
            intent,
            resultCount: ranked.length,
            latencyMs: Date.now() - startedAt,
            usedExternalPlaces: externalRanked.length > 0,
            usedAI: aiEnabled,
            safetyBlocked: false,
        }).catch((error) => logger.warn("smartCommunitySearch analytics failed", { error }));

        return {
            searchId,
            interpretedIntent: intent,
            results: ranked,
            refinementSuggestions: refinementSuggestions(intent, ranked.length),
            safetyNotice: safety.safetyNotice,
            usedExternalPlaces: externalRanked.length > 0,
            usedAI: aiEnabled,
        };
    }
);

export { heuristicSmartIntent, parseSmartCommunityIntent } from "./smartCommunitySearch.intent";
export { classifySafetyRisk, sanitizeSmartQuery } from "./smartCommunitySearch.safety";
export {
    combineAndDedupeRankedResults,
    rankAmenInternalResults,
    refinementSuggestions,
} from "./smartCommunitySearch.ranking";
