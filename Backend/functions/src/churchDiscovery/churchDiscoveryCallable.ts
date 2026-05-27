import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { enforceRateLimit, RATE_LIMITS } from "../rateLimit";
import { ChurchSearchRequest, UserLocationContext } from "./churchDiscoveryModels";
import { googleMapsApiKey, googlePlacesApiKey, searchGooglePlacesForChurches } from "./googlePlacesChurchSearch";
import { loadAmenChurchProfiles, mergeAndRankChurchResults } from "./churchMatchingEngine";
import { enforceGroundedSummaries } from "./churchDiscoverySummaries";
import { openaiApiKey, parseIntentWithStructuredOutputs, sanitizeChurchQuery } from "./parseChurchSearchIntent";

const db = admin.firestore();
const REGION = "us-central1";
const LIMITS = [RATE_LIMITS.CHURCH_DISCOVERY_PER_MINUTE, RATE_LIMITS.CHURCH_DISCOVERY_PER_DAY];

type CallableRequest = {
    auth?: { uid?: string };
    app?: { appId?: string };
    data?: Record<string, unknown>;
};

function requireAuth(request: CallableRequest): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return uid;
}

function requireAppCheck(request: CallableRequest): void {
    if (process.env.FUNCTIONS_EMULATOR === "true") return;
    if (!request.app?.appId) throw new HttpsError("failed-precondition", "App Check required.");
}

function readLocation(value: unknown): UserLocationContext | null {
    if (!value || typeof value !== "object") return null;
    const raw = value as Record<string, unknown>;
    const latitude = Number(raw.latitude);
    const longitude = Number(raw.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        throw new HttpsError("invalid-argument", "Invalid coordinates.");
    }
    return {
        latitude,
        longitude,
        label: typeof raw.label === "string" ? raw.label.slice(0, 120) : null,
    };
}

function readRequest(data: Record<string, unknown> | undefined): ChurchSearchRequest {
    const rawQuery = sanitizeChurchQuery(String(data?.rawQuery ?? data?.query ?? ""));
    if (rawQuery.length > 400) throw new HttpsError("invalid-argument", "Query is too long.");
    const approximateLocation = readLocation(data?.approximateLocation ?? data?.location);
    return {
        rawQuery,
        approximateLocation,
        filters: typeof data?.filters === "object" && data?.filters ? data.filters as Record<string, unknown> : {},
    };
}

export const parseChurchSearchIntent = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB", secrets: [openaiApiKey] },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        const uid = requireAuth(request as CallableRequest);
        await enforceRateLimit(uid, LIMITS);
        const input = readRequest((request as CallableRequest).data);
        if (!input.rawQuery) throw new HttpsError("invalid-argument", "Search query is required.");
        const intent = await parseIntentWithStructuredOutputs({
            rawQuery: input.rawQuery,
            approximateLocation: input.approximateLocation,
        });
        return { intent };
    }
);

export const searchChurchesAndCommunities = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 45, memory: "512MiB", secrets: [openaiApiKey, googlePlacesApiKey, googleMapsApiKey] },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        const uid = requireAuth(request as CallableRequest);
        await enforceRateLimit(uid, LIMITS);
        const input = readRequest((request as CallableRequest).data);
        if (!input.rawQuery) throw new HttpsError("invalid-argument", "Search query is required.");
        const intent = await parseIntentWithStructuredOutputs({
            rawQuery: input.rawQuery,
            approximateLocation: input.approximateLocation,
        });
        const [googleCandidates, amenCandidates] = await Promise.all([
            searchGooglePlacesForChurches({
                intent,
                rawQuery: input.rawQuery,
                location: input.approximateLocation,
            }),
            loadAmenChurchProfiles(input.approximateLocation),
        ]);
        const results = enforceGroundedSummaries(mergeAndRankChurchResults({
            intent,
            googleCandidates,
            amenCandidates,
            location: input.approximateLocation,
        }));
        const searchRef = db.collection("users").doc(uid).collection("churchDiscovery").doc("searches").collection("items").doc();
        await searchRef.set({
            queryCategory: deriveQueryCategory(intent),
            resultCount: results.length,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { searchId: searchRef.id, intent, results };
    }
);

export const getChurchDiscoveryDetails = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB" },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        requireAuth(request as CallableRequest);
        const churchId = String((request as CallableRequest).data?.churchId ?? "").trim();
        if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");
        const doc = await db.collection("churches").doc(churchId).get();
        if (!doc.exists) throw new HttpsError("not-found", "Church not found.");
        return { churchId, profile: doc.data() ?? {} };
    }
);

export const saveChurchDiscoveryPreference = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        const uid = requireAuth(request as CallableRequest);
        await db.collection("users").doc(uid).collection("churchDiscovery").doc("preferences").collection("items").doc("main").set({
            preferences: (request as CallableRequest).data?.preferences ?? {},
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ok: true };
    }
);

export const saveChurchCandidate = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        const uid = requireAuth(request as CallableRequest);
        const data = (request as CallableRequest).data ?? {};
        const churchId = String(data.churchId ?? data.googlePlaceId ?? "").trim();
        if (!churchId) throw new HttpsError("invalid-argument", "churchId or googlePlaceId is required.");
        await db.collection("users").doc(uid).collection("churchDiscovery").doc("savedChurches").collection("items").doc(churchId).set({
            churchId: data.churchId ?? null,
            googlePlaceId: data.googlePlaceId ?? null,
            name: String(data.name ?? "").slice(0, 160),
            savedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ok: true };
    }
);

export const logChurchDiscoveryInteraction = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 20, memory: "256MiB" },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        const uid = requireAuth(request as CallableRequest);
        const data = (request as CallableRequest).data ?? {};
        const event = String(data.event ?? data.action ?? "").trim().slice(0, 80);
        if (!event) throw new HttpsError("invalid-argument", "event is required.");
        await db.collection("users").doc(uid).collection("churchDiscovery").doc("interactions").collection("items").add({
            event,
            churchId: data.churchId ?? null,
            googlePlaceId: data.googlePlaceId ?? null,
            metadata: data.metadata ?? {},
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { ok: true };
    }
);

export const refreshChurchPlaceDetails = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 30, memory: "256MiB", secrets: [googlePlacesApiKey, googleMapsApiKey] },
    async (request) => {
        requireAppCheck(request as CallableRequest);
        const uid = requireAuth(request as CallableRequest);
        await enforceRateLimit(uid, [RATE_LIMITS.CHURCH_DISCOVERY_PER_DAY]);
        const googlePlaceId = String((request as CallableRequest).data?.googlePlaceId ?? "").trim();
        if (!googlePlaceId) throw new HttpsError("invalid-argument", "googlePlaceId is required.");
        return { googlePlaceId, refreshed: false, reason: "Use search results field masks until details refresh policy is finalized." };
    }
);

function deriveQueryCategory(intent: { denominationPreferences: string[]; communityNeeds: string[]; lifeStage: string[]; groupNeeds: string[] }): string {
    if (intent.denominationPreferences.length) return "denomination";
    if (intent.lifeStage.length) return "life_stage";
    if (intent.groupNeeds.length) return "groups";
    if (intent.communityNeeds.length) return "community";
    return "general";
}
