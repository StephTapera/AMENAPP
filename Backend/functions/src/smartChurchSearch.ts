import * as admin from "firebase-admin";
import { createHash } from "crypto";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import { enforceRateLimit, RATE_LIMITS } from "./rateLimit";

const db = admin.firestore();
const REGION = "us-central1";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const openaiApiKey = defineSecret("OPENAI_API_KEY");
const googleMapsKey = defineSecret("GOOGLE_MAPS_KEY");
const pineconeApiKey = defineSecret("PINECONE_API_KEY");
const algoliaAdminKey = defineSecret("ALGOLIA_ADMIN_KEY");

const CLAUDE_MODEL = "claude-haiku-4-5-20251001";
const OPENAI_EMBEDDING_MODEL = "text-embedding-3-small";
const CHURCHES_INDEX = "churches";
const PINECONE_NAMESPACE = "churches-v1";
const EMBEDDING_VERSION = 1;

type ChurchSize = "small" | "medium" | "large" | "mega";

interface SmartChurchParse {
    filters: {
        denomination: string | null;
        denominationFamily: string | null;
        size: ChurchSize | null;
        language: string | null;
        worshipStyles: string[];
        ministries: string[];
        serviceDay: string | null;
    };
    semanticIntent: string;
    radiusMiles: number;
}

interface SmartChurchSearchRequest {
    query: string;
    userLat: number;
    userLng: number;
    radiusMiles?: number;
}

interface PineconeMatch {
    id: string;
    score?: number;
    metadata?: Record<string, unknown>;
}

interface ChurchSearchCandidate {
    churchId: string;
    semanticScore: number;
    distanceMiles: number;
    filterMatchScore: number;
    blendedScore: number;
}

const QUERY_PARSE_SYSTEM_PROMPT = `You parse a person's natural-language description of the church they're looking for
into a structured search object. Output ONLY minified JSON — no preamble, no markdown,
no code fences.

Schema:
{
  "filters": {
    "denomination": string | null,
    "denominationFamily": string | null,
    "size": "small"|"medium"|"large"|"mega"|null,
    "language": string | null,
    "worshipStyles": string[],
    "ministries": string[],
    "serviceDay": string | null
  },
  "semanticIntent": string,
  "radiusMiles": number
}

Rules:
- Only populate hard filters (denomination, size, language) when the user is explicit.
  Put soft preferences (vibe, community feel, theology leanings, "not judgmental",
  "good for families") into semanticIntent instead.
- Choose worshipStyles/ministries ONLY from the allowed values above; omit if unclear.
- semanticIntent must be self-contained prose that another model could embed without the
  original query.
- Never invent constraints the user did not express.`;

function requireAuth(request: { auth?: { uid?: string } }): string {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
    return uid;
}

function requireAdmin(request: { auth?: { token?: Record<string, unknown> } }): void {
    if (request.auth?.token?.admin !== true) {
        throw new HttpsError("permission-denied", "Admin privileges required.");
    }
}

function readSearchRequest(data: unknown): SmartChurchSearchRequest {
    const raw = (data ?? {}) as Record<string, unknown>;
    const query = String(raw.query ?? "").trim().slice(0, 400);
    const userLat = Number(raw.userLat ?? raw.latitude);
    const userLng = Number(raw.userLng ?? raw.longitude);
    const radiusMiles = raw.radiusMiles === undefined ? undefined : Number(raw.radiusMiles);
    if (!query) throw new HttpsError("invalid-argument", "query is required.");
    if (!Number.isFinite(userLat) || userLat < -90 || userLat > 90) {
        throw new HttpsError("invalid-argument", "Valid userLat is required.");
    }
    if (!Number.isFinite(userLng) || userLng < -180 || userLng > 180) {
        throw new HttpsError("invalid-argument", "Valid userLng is required.");
    }
    return {
        query,
        userLat,
        userLng,
        radiusMiles: Number.isFinite(radiusMiles) ? Math.max(1, Math.min(100, radiusMiles as number)) : undefined,
    };
}

function normalizeParse(value: Partial<SmartChurchParse>, fallbackQuery: string, fallbackRadius?: number): SmartChurchParse {
    const allowedWorship = new Set(["contemporary", "traditional", "blended", "liturgical", "charismatic"]);
    const allowedMinistries = new Set(["youth", "young_adults", "kids", "men", "women", "recovery", "missions", "college", "seniors", "marriage"]);
    const size = value.filters?.size;
    return {
        filters: {
            denomination: cleanNullable(value.filters?.denomination),
            denominationFamily: cleanNullable(value.filters?.denominationFamily),
            size: size === "small" || size === "medium" || size === "large" || size === "mega" ? size : null,
            language: cleanNullable(value.filters?.language),
            worshipStyles: cleanList(value.filters?.worshipStyles).filter((item) => allowedWorship.has(item)),
            ministries: cleanList(value.filters?.ministries).filter((item) => allowedMinistries.has(item)),
            serviceDay: cleanNullable(value.filters?.serviceDay),
        },
        semanticIntent: String(value.semanticIntent ?? fallbackQuery).trim().slice(0, 1200) || fallbackQuery,
        radiusMiles: Math.max(1, Math.min(100, Number(value.radiusMiles ?? fallbackRadius ?? 15))),
    };
}

function cleanNullable(value: unknown): string | null {
    const text = String(value ?? "").trim();
    return text ? text.slice(0, 120) : null;
}

function cleanList(value: unknown): string[] {
    return Array.isArray(value)
        ? Array.from(new Set(value.map((item) => String(item ?? "").trim().toLowerCase()).filter(Boolean))).slice(0, 12)
        : [];
}

async function parseSmartChurchQuery(query: string, radiusMiles?: number): Promise<SmartChurchParse> {
    const key = anthropicApiKey.value();
    if (!key || key.startsWith("mock-")) return heuristicParse(query, radiusMiles);

    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
            model: CLAUDE_MODEL,
            max_tokens: 800,
            temperature: 0,
            system: QUERY_PARSE_SYSTEM_PROMPT,
            messages: [{ role: "user", content: query }],
        }),
    });
    if (!response.ok) return heuristicParse(query, radiusMiles);

    const json = await response.json() as { content?: Array<{ type: string; text?: string }> };
    const text = json.content?.find((part) => part.type === "text")?.text ?? "{}";
    try {
        return normalizeParse(JSON.parse(text) as Partial<SmartChurchParse>, query, radiusMiles);
    } catch {
        return heuristicParse(query, radiusMiles);
    }
}

function heuristicParse(query: string, radiusMiles?: number): SmartChurchParse {
    const lowered = query.toLowerCase();
    const worshipStyles = [
        lowered.includes("contemporary") ? "contemporary" : null,
        lowered.includes("traditional") ? "traditional" : null,
        lowered.includes("liturgical") ? "liturgical" : null,
        lowered.includes("charismatic") || lowered.includes("spirit-filled") ? "charismatic" : null,
    ].filter(Boolean) as string[];
    const ministries = [
        lowered.includes("young adult") ? "young_adults" : null,
        lowered.includes("college") ? "college" : null,
        lowered.includes("kid") || lowered.includes("famil") ? "kids" : null,
        lowered.includes("youth") ? "youth" : null,
        lowered.includes("recover") ? "recovery" : null,
        lowered.includes("mission") ? "missions" : null,
        lowered.includes("marriage") ? "marriage" : null,
    ].filter(Boolean) as string[];
    const denomination = lowered.includes("non-denom") || lowered.includes("non denom")
        ? "Non-denominational"
        : lowered.includes("baptist") ? "Baptist"
        : lowered.includes("methodist") ? "Methodist"
        : lowered.includes("presbyterian") ? "Presbyterian"
        : lowered.includes("catholic") ? "Catholic"
        : null;
    return normalizeParse({
        filters: { denomination, denominationFamily: null, size: null, language: null, worshipStyles, ministries, serviceDay: null },
        semanticIntent: query,
        radiusMiles: radiusMiles ?? 15,
    }, query, radiusMiles);
}

async function embedText(text: string): Promise<number[] | null> {
    const key = openaiApiKey.value();
    if (!key || key.startsWith("mock-")) return null;
    const response = await fetch("https://api.openai.com/v1/embeddings", {
        method: "POST",
        headers: {
            "authorization": `Bearer ${key}`,
            "content-type": "application/json",
        },
        body: JSON.stringify({ model: OPENAI_EMBEDDING_MODEL, input: text.slice(0, 8000) }),
    });
    if (!response.ok) {
        logger.warn("[smartChurchSearch] embedding failed", { status: response.status });
        return null;
    }
    const json = await response.json() as { data?: Array<{ embedding?: number[] }> };
    return json.data?.[0]?.embedding ?? null;
}

function pineconeHost(): string {
    return process.env.PINECONE_CHURCHES_INDEX_HOST ?? process.env.PINECONE_INDEX_HOST ?? "";
}

async function queryPinecone(vector: number[], parsed: SmartChurchParse): Promise<PineconeMatch[]> {
    const key = pineconeApiKey.value();
    const host = pineconeHost();
    if (!key || !host) return [];
    const filter = buildPineconeFilter(parsed);
    const response = await fetch(`https://${host}/query`, {
        method: "POST",
        headers: {
            "api-key": key,
            "content-type": "application/json",
        },
        body: JSON.stringify({
            vector,
            topK: 100,
            namespace: PINECONE_NAMESPACE,
            includeMetadata: true,
            ...(Object.keys(filter).length ? { filter } : {}),
        }),
    });
    if (!response.ok) {
        logger.warn("[smartChurchSearch] pinecone query failed", { status: response.status });
        return [];
    }
    const json = await response.json() as { matches?: PineconeMatch[] };
    return json.matches ?? [];
}

function buildPineconeFilter(parsed: SmartChurchParse): Record<string, unknown> {
    const filter: Record<string, unknown> = {};
    if (parsed.filters.denomination) filter.denomination = { "$eq": parsed.filters.denomination };
    if (parsed.filters.denominationFamily) filter.denominationFamily = { "$eq": parsed.filters.denominationFamily };
    if (parsed.filters.size) filter.size = { "$eq": parsed.filters.size };
    if (parsed.filters.language) filter.languages = { "$in": [parsed.filters.language] };
    return filter;
}

async function hydrateChurches(ids: string[]): Promise<Array<{ id: string; data: FirebaseFirestore.DocumentData }>> {
    if (!ids.length) return [];
    const refs = ids.map((id) => db.collection("churches").doc(id));
    const snapshots = await db.getAll(...refs);
    return snapshots
        .filter((snapshot) => snapshot.exists)
        .map((snapshot) => ({ id: snapshot.id, data: snapshot.data() ?? {} }));
}

async function firestoreFallback(parsed: SmartChurchParse, input: SmartChurchSearchRequest): Promise<ChurchSearchCandidate[]> {
    let query: FirebaseFirestore.Query = db.collection("churches").limit(100);
    if (parsed.filters.denomination) query = query.where("denomination", "==", parsed.filters.denomination);
    if (parsed.filters.size) query = query.where("size", "==", parsed.filters.size);
    const snapshot = await query.get();
    return snapshot.docs.map((doc) => {
        const distanceMiles = distanceFrom(input.userLat, input.userLng, doc.data());
        return {
            churchId: doc.id,
            semanticScore: textSimilarity(parsed.semanticIntent, doc.data()),
            distanceMiles,
            filterMatchScore: filterMatchScore(parsed, doc.data()),
            blendedScore: 0,
        };
    });
}

function rankCandidates(matches: PineconeMatch[], parsed: SmartChurchParse, input: SmartChurchSearchRequest): ChurchSearchCandidate[] {
    return matches.map((match) => {
        const distanceMiles = distanceFrom(input.userLat, input.userLng, match.metadata ?? {});
        const semanticScore = Math.max(0, Math.min(1, Number(match.score ?? 0)));
        const filterScore = metadataFilterScore(parsed, match.metadata ?? {});
        const distanceScore = 1 - Math.min(1, distanceMiles / parsed.radiusMiles);
        return {
            churchId: String(match.metadata?.churchId ?? match.id),
            semanticScore,
            distanceMiles,
            filterMatchScore: filterScore,
            blendedScore: 0.6 * semanticScore + 0.25 * distanceScore + 0.15 * filterScore,
        };
    });
}

function finishRanking(candidates: ChurchSearchCandidate[], radiusMiles: number): ChurchSearchCandidate[] {
    return candidates
        .map((candidate) => {
            const distanceScore = 1 - Math.min(1, candidate.distanceMiles / radiusMiles);
            return {
                ...candidate,
                blendedScore: candidate.blendedScore || (0.6 * candidate.semanticScore + 0.25 * distanceScore + 0.15 * candidate.filterMatchScore),
            };
        })
        .filter((candidate) => candidate.distanceMiles <= radiusMiles)
        .sort((lhs, rhs) => rhs.blendedScore - lhs.blendedScore)
        .slice(0, 12);
}

function distanceFrom(userLat: number, userLng: number, data: Record<string, unknown>): number {
    const location = data.location as { lat?: number; lng?: number; latitude?: number; longitude?: number } | undefined;
    const lat = numberValue(location?.lat ?? location?.latitude ?? data.lat ?? data.latitude);
    const lng = numberValue(location?.lng ?? location?.longitude ?? data.lng ?? data.longitude);
    if (lat === null || lng === null) return 9999;
    const toRad = (value: number) => value * Math.PI / 180;
    const dLat = toRad(lat - userLat);
    const dLng = toRad(lng - userLng);
    const a = Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(userLat)) * Math.cos(toRad(lat)) * Math.sin(dLng / 2) ** 2;
    return 3958.8 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function numberValue(value: unknown): number | null {
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
}

function filterMatchScore(parsed: SmartChurchParse, data: FirebaseFirestore.DocumentData): number {
    const checks = [
        parsed.filters.denomination ? equals(data.denomination, parsed.filters.denomination) : null,
        parsed.filters.denominationFamily ? equals(data.denominationFamily, parsed.filters.denominationFamily) : null,
        parsed.filters.size ? equals(data.size, parsed.filters.size) : null,
        parsed.filters.language ? listHas(data.languages, parsed.filters.language) : null,
        ...parsed.filters.worshipStyles.map((style) => listHas(data.worshipStyles, style)),
        ...parsed.filters.ministries.map((ministry) => listHas(data.ministries, ministry)),
    ].filter((value) => value !== null) as boolean[];
    if (!checks.length) return 0.7;
    return checks.filter(Boolean).length / checks.length;
}

function metadataFilterScore(parsed: SmartChurchParse, metadata: Record<string, unknown>): number {
    return filterMatchScore(parsed, metadata as FirebaseFirestore.DocumentData);
}

function equals(lhs: unknown, rhs: string): boolean {
    return String(lhs ?? "").toLowerCase() === rhs.toLowerCase();
}

function listHas(value: unknown, wanted: string): boolean {
    return Array.isArray(value) && value.map((item) => String(item).toLowerCase()).includes(wanted.toLowerCase());
}

function textSimilarity(intent: string, data: FirebaseFirestore.DocumentData): number {
    const haystack = compositeChurchText(data).toLowerCase();
    const terms = intent.toLowerCase().split(/[^a-z0-9_]+/).filter((term) => term.length > 3);
    if (!terms.length) return 0.35;
    const matched = terms.filter((term) => haystack.includes(term)).length;
    return Math.max(0.2, Math.min(0.85, matched / terms.length));
}

function compositeChurchText(data: FirebaseFirestore.DocumentData): string {
    return [
        data.name,
        data.denomination,
        data.denominationFamily,
        ...(Array.isArray(data.worshipStyles) ? data.worshipStyles : []),
        ...(Array.isArray(data.ministries) ? data.ministries : []),
        ...(Array.isArray(data.languages) ? data.languages : []),
        data.description,
        data.statementOfFaith,
    ].filter(Boolean).join("\n");
}

async function explainMatches(originalQuery: string, churches: Array<{ id: string; data: FirebaseFirestore.DocumentData }>): Promise<Record<string, string>> {
    const fallback = Object.fromEntries(churches.map((church) => [church.id, fallbackReason(church.data)]));
    const key = anthropicApiKey.value();
    if (!key || !churches.length) return fallback;
    const payload = churches.map((church) => ({
        id: church.id,
        name: church.data.name ?? "",
        denomination: church.data.denomination ?? "",
        worshipStyles: church.data.worshipStyles ?? [],
        ministries: church.data.ministries ?? [],
        description: church.data.description ?? "",
        serviceTimes: church.data.serviceTimes ?? [],
    }));
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
            model: CLAUDE_MODEL,
            max_tokens: 1000,
            temperature: 0,
            system: "Return ONLY minified JSON mapping church id to one grounded sentence under 140 characters. Use only provided fields. Do not invent facts.",
            messages: [{ role: "user", content: JSON.stringify({ originalQuery, results: payload }) }],
        }),
    });
    if (!response.ok) return fallback;
    const json = await response.json() as { content?: Array<{ type: string; text?: string }> };
    const text = json.content?.find((part) => part.type === "text")?.text ?? "{}";
    try {
        return { ...fallback, ...JSON.parse(text) as Record<string, string> };
    } catch {
        return fallback;
    }
}

function fallbackReason(data: FirebaseFirestore.DocumentData): string {
    const bits = [
        data.denomination,
        Array.isArray(data.worshipStyles) ? data.worshipStyles.slice(0, 2).join(", ") : "",
        Array.isArray(data.ministries) ? data.ministries.slice(0, 2).join(", ") : "",
    ].filter(Boolean);
    return bits.length ? `Matches on ${bits.join(" with ")} from stored church fields.` : "Matches nearby church profile signals.";
}

export const smartChurchSearch = onCall(
    {
        region: REGION,
        enforceAppCheck: true,
        timeoutSeconds: 60,
        memory: "1GiB",
        secrets: [anthropicApiKey, openaiApiKey, pineconeApiKey],
    },
    async (request) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [RATE_LIMITS.CHURCH_DISCOVERY_PER_MINUTE, RATE_LIMITS.CHURCH_DISCOVERY_PER_DAY]);
        const input = readSearchRequest(request.data);
        const parsed = await parseSmartChurchQuery(input.query, input.radiusMiles);
        const embedding = await embedText(parsed.semanticIntent);
        const pineconeMatches = embedding ? await queryPinecone(embedding, parsed) : [];
        const initial = pineconeMatches.length
            ? rankCandidates(pineconeMatches, parsed, input)
            : await firestoreFallback(parsed, input);
        const ranked = finishRanking(initial, parsed.radiusMiles);
        const hydrated = await hydrateChurches(ranked.map((candidate) => candidate.churchId));
        const churchById = new Map(hydrated.map((church) => [church.id, church]));
        const reasons = await explainMatches(input.query, hydrated);
        const results = ranked.flatMap((candidate) => {
            const church = churchById.get(candidate.churchId);
            if (!church) return [];
            return [{
                church: { id: church.id, ...church.data },
                distanceMiles: Number(candidate.distanceMiles.toFixed(2)),
                matchReason: String(reasons[church.id] ?? fallbackReason(church.data)).slice(0, 180),
                score: Number(candidate.blendedScore.toFixed(4)),
            }];
        });
        return { results, parsed };
    }
);

export const searchChurchesByKeyword = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 30, memory: "512MiB", secrets: [algoliaAdminKey] },
    async (request) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [RATE_LIMITS.CHURCH_DISCOVERY_PER_MINUTE, RATE_LIMITS.CHURCH_DISCOVERY_PER_DAY]);
        const query = String(request.data?.query ?? "").trim().slice(0, 200);
        if (!query) throw new HttpsError("invalid-argument", "query is required.");
        const hits = await algoliaChurchSearch(query);
        if (hits.length) return { results: hits };
        const snapshot = await db.collection("churches").orderBy("name").limit(20).get();
        return {
            results: snapshot.docs
                .filter((doc) => String(doc.data().name ?? "").toLowerCase().includes(query.toLowerCase()))
                .map((doc) => ({ church: { id: doc.id, ...doc.data() }, matchReason: "Keyword match from Firestore.", score: 0.4 })),
        };
    }
);

async function algoliaChurchSearch(query: string): Promise<Array<Record<string, unknown>>> {
    const key = algoliaAdminKey.value();
    const appId = process.env.ALGOLIA_APP_ID ?? "182SCN7O9S";
    if (!key || !appId) return [];
    const response = await fetch(`https://${appId}-dsn.algolia.net/1/indexes/${CHURCHES_INDEX}/query`, {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-algolia-application-id": appId,
            "x-algolia-api-key": key,
        },
        body: JSON.stringify({ query, hitsPerPage: 20 }),
    });
    if (!response.ok) return [];
    const json = await response.json() as { hits?: Array<Record<string, unknown>> };
    return (json.hits ?? []).map((hit) => ({
        church: { id: hit.objectID, ...hit },
        matchReason: "Keyword match from Algolia.",
        score: 0.5,
    }));
}

export const enrichChurchesFromPlaces = onCall(
    { region: REGION, enforceAppCheck: true, timeoutSeconds: 120, memory: "1GiB", secrets: [googleMapsKey] },
    async (request) => {
        requireAuth(request);
        requireAdmin(request);
        const data = request.data ?? {};
        const lat = Number(data.lat);
        const lng = Number(data.lng);
        const radiusMeters = Math.max(500, Math.min(50_000, Number(data.radiusMeters ?? 15_000)));
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) throw new HttpsError("invalid-argument", "lat/lng are required.");
        const query = String(data.query ?? "church").trim().slice(0, 120) || "church";
        const places = await searchPlacesForIngestion(query, lat, lng, radiusMeters);
        let written = 0;
        for (const place of places) {
            const docId = stableChurchId(place.id, place.displayName?.text);
            await db.collection("churches").doc(docId).set(placeToChurchDoc(docId, place), { merge: true });
            written += 1;
        }
        return { written };
    }
);

type Place = Record<string, any>;

async function searchPlacesForIngestion(query: string, lat: number, lng: number, radiusMeters: number): Promise<Place[]> {
    const key = googleMapsKey.value();
    if (!key) return [];
    const fieldMask = [
        "places.id",
        "places.displayName",
        "places.formattedAddress",
        "places.location",
        "places.nationalPhoneNumber",
        "places.websiteUri",
        "places.regularOpeningHours",
        "places.photos",
    ].join(",");
    const response = await fetch("https://places.googleapis.com/v1/places:searchText", {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-goog-api-key": key,
            "x-goog-fieldmask": fieldMask,
        },
        body: JSON.stringify({
            textQuery: query,
            includedType: "church",
            maxResultCount: 20,
            locationBias: { circle: { center: { latitude: lat, longitude: lng }, radius: radiusMeters } },
        }),
    });
    if (!response.ok) throw new HttpsError("internal", `Google Places returned ${response.status}.`);
    const json = await response.json() as { places?: Place[] };
    return json.places ?? [];
}

function stableChurchId(placeId: unknown, name: unknown): string {
    const source = String(placeId || name || Date.now());
    return createHash("sha1").update(source).digest("hex").slice(0, 24);
}

function placeToChurchDoc(id: string, place: Place): FirebaseFirestore.DocumentData {
    const lat = Number(place.location?.latitude ?? 0);
    const lng = Number(place.location?.longitude ?? 0);
    const address = String(place.formattedAddress ?? "");
    const cityStateZip = parseCityStateZip(address);
    return {
        id,
        name: String(place.displayName?.text ?? "Church"),
        address,
        city: cityStateZip.city,
        state: cityStateZip.state,
        zip: cityStateZip.zip,
        location: { lat, lng },
        geoPoint: new admin.firestore.GeoPoint(lat, lng),
        denomination: "Unknown",
        denominationFamily: "Unknown",
        worshipStyles: [],
        ministries: [],
        size: "medium",
        serviceTimes: openingHoursToServiceTimes(place.regularOpeningHours?.weekdayDescriptions ?? []),
        languages: ["English"],
        statementOfFaith: "",
        doctrinalTags: [],
        description: "",
        website: place.websiteUri ?? null,
        phone: place.nationalPhoneNumber ?? null,
        email: null,
        photos: Array.isArray(place.photos) ? place.photos.map((photo: Place) => String(photo.name ?? "")).filter(Boolean) : [],
        googlePlaceId: String(place.id ?? ""),
        source: "google_places",
        claimed: false,
        embeddingVersion: EMBEDDING_VERSION,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

function parseCityStateZip(address: string): { city: string; state: string; zip: string } {
    const parts = address.split(",").map((part) => part.trim());
    const city = parts.length >= 2 ? parts[parts.length - 3] ?? "" : "";
    const stateZip = parts.length >= 2 ? parts[parts.length - 2] ?? "" : "";
    const match = stateZip.match(/\b([A-Z]{2})\s+(\d{5})/);
    return { city, state: match?.[1] ?? "", zip: match?.[2] ?? "" };
}

function openingHoursToServiceTimes(hours: string[]): Array<Record<string, string>> {
    return hours
        .filter((line) => /^Sunday:/i.test(line))
        .slice(0, 2)
        .map((line) => ({ day: "Sunday", time: line.replace(/^Sunday:\s*/i, ""), language: "English", type: "main" }));
}

export const onChurchWrite = onDocumentWritten(
    {
        document: "churches/{churchId}",
        region: REGION,
        timeoutSeconds: 120,
        memory: "1GiB",
        secrets: [anthropicApiKey, openaiApiKey, pineconeApiKey, algoliaAdminKey],
    },
    async (event) => {
        const after = event.data?.after;
        if (!after?.exists) return;
        const data = after.data() ?? {};
        const text = compositeChurchText(data);
        const textHash = createHash("sha256").update(text).digest("hex");
        const needsEmbedding = data.embeddingTextHash !== textHash || data.embeddingVersion !== EMBEDDING_VERSION;
        const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {};
        if (needsEmbedding) {
            const embedding = await embedText(text);
            if (embedding) {
                await Promise.all([
                    upsertPinecone(after.id, embedding, data),
                    saveAlgoliaChurch(after.id, data),
                ]);
                updates.embeddingTextHash = textHash;
                updates.embeddingVersion = EMBEDDING_VERSION;
                updates.indexedAt = admin.firestore.FieldValue.serverTimestamp();
            }
        }
        if (String(data.statementOfFaith ?? "").trim() && (!Array.isArray(data.doctrinalTags) || data.doctrinalTags.length === 0)) {
            updates.doctrinalTags = await extractDoctrinalTags(String(data.statementOfFaith));
        }
        if (Object.keys(updates).length) {
            await after.ref.set(updates, { merge: true });
        }
    }
);

async function upsertPinecone(id: string, vector: number[], data: FirebaseFirestore.DocumentData): Promise<void> {
    const key = pineconeApiKey.value();
    const host = pineconeHost();
    if (!key || !host) return;
    const metadata = {
        churchId: id,
        lat: data.location?.lat ?? null,
        lng: data.location?.lng ?? null,
        denomination: data.denomination ?? null,
        denominationFamily: data.denominationFamily ?? null,
        size: data.size ?? null,
        worshipStyles: data.worshipStyles ?? [],
        ministries: data.ministries ?? [],
        languages: data.languages ?? [],
        state: data.state ?? null,
    };
    await fetch(`https://${host}/vectors/upsert`, {
        method: "POST",
        headers: { "api-key": key, "content-type": "application/json" },
        body: JSON.stringify({ namespace: PINECONE_NAMESPACE, vectors: [{ id, values: vector, metadata }] }),
    });
}

async function saveAlgoliaChurch(id: string, data: FirebaseFirestore.DocumentData): Promise<void> {
    const key = algoliaAdminKey.value();
    const appId = process.env.ALGOLIA_APP_ID ?? "182SCN7O9S";
    if (!key || !appId) return;
    await fetch(`https://${appId}.algolia.net/1/indexes/${CHURCHES_INDEX}/${encodeURIComponent(id)}`, {
        method: "PUT",
        headers: {
            "content-type": "application/json",
            "x-algolia-application-id": appId,
            "x-algolia-api-key": key,
        },
        body: JSON.stringify({
            objectID: id,
            name: data.name ?? "",
            description: data.description ?? "",
            ministries: data.ministries ?? [],
            denomination: data.denomination ?? "",
            denominationFamily: data.denominationFamily ?? "",
            worshipStyles: data.worshipStyles ?? [],
            languages: data.languages ?? [],
            size: data.size ?? "",
            state: data.state ?? "",
            city: data.city ?? "",
            _geoloc: data.location ? { lat: data.location.lat, lng: data.location.lng } : undefined,
        }),
    });
}

// ─── bereanChurchChat ────────────────────────────────────────────────────────
// Callable used by the Berean Church Finder conversational UI.
// Runs the full search pipeline then returns a conversational narrative so
// the iOS client can emit status → results → message events from one response.

async function buildBereanNarrative(
    originalQuery: string,
    results: Array<{ id: string; data: FirebaseFirestore.DocumentData }>,
    radiusMiles: number,
): Promise<string> {
    const fallback = results.length === 0
        ? "I searched within the radius but did not find grounded church matches. Try widening the radius or clarifying your priorities."
        : `I found ${results.length} church${results.length === 1 ? "" : "es"} that match your priorities. Each one is grounded in verified profile data — no invented details.`;

    const key = anthropicApiKey.value();
    if (!key || !results.length) return fallback;

    const payload = results.slice(0, 6).map((church) => ({
        name: church.data.name ?? "",
        denomination: church.data.denomination ?? "",
        worshipStyles: church.data.worshipStyles ?? [],
        ministries: church.data.ministries ?? [],
        size: church.data.size ?? "",
        city: church.data.city ?? "",
    }));

    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
            model: CLAUDE_MODEL,
            max_tokens: 400,
            temperature: 0.2,
            system: `You are a warm church-finder assistant. Given the user's search and a list of matching churches,
write 2-3 sentences explaining what you found and what these churches have in common that fits the request.
Only reference fields you were given. Never invent facts about real churches. Sound helpful and grounded.`,
            messages: [{ role: "user", content: JSON.stringify({ query: originalQuery, radiusMiles, churches: payload }) }],
        }),
    });
    if (!response.ok) return fallback;

    const json = await response.json() as { content?: Array<{ type: string; text?: string }> };
    const text = (json.content?.find((part) => part.type === "text")?.text ?? "").trim();
    return text.length > 20 ? text.slice(0, 600) : fallback;
}

export const bereanChurchChat = onCall(
    {
        region: REGION,
        enforceAppCheck: true,
        timeoutSeconds: 60,
        memory: "1GiB",
        secrets: [anthropicApiKey, openaiApiKey, pineconeApiKey],
    },
    async (request) => {
        const uid = requireAuth(request);
        await enforceRateLimit(uid, [RATE_LIMITS.CHURCH_DISCOVERY_PER_MINUTE, RATE_LIMITS.CHURCH_DISCOVERY_PER_DAY]);
        const input = readSearchRequest(request.data);
        const parsed = await parseSmartChurchQuery(input.query, input.radiusMiles);
        const embedding = await embedText(parsed.semanticIntent);
        const pineconeMatches = embedding ? await queryPinecone(embedding, parsed) : [];
        const initial = pineconeMatches.length
            ? rankCandidates(pineconeMatches, parsed, input)
            : await firestoreFallback(parsed, input);
        const ranked = finishRanking(initial, parsed.radiusMiles);
        const hydrated = await hydrateChurches(ranked.map((candidate) => candidate.churchId));
        const churchById = new Map(hydrated.map((church) => [church.id, church]));
        const reasons = await explainMatches(input.query, hydrated);
        const results = ranked.flatMap((candidate) => {
            const church = churchById.get(candidate.churchId);
            if (!church) return [];
            return [{
                church: { id: church.id, ...church.data },
                distanceMiles: Number(candidate.distanceMiles.toFixed(2)),
                matchReason: String(reasons[church.id] ?? fallbackReason(church.data)).slice(0, 180),
                score: Number(candidate.blendedScore.toFixed(4)),
            }];
        });
        const message = await buildBereanNarrative(input.query, hydrated, parsed.radiusMiles);
        return {
            status: results.length > 0
                ? `Found ${results.length} grounded church match${results.length === 1 ? "" : "es"} within ${parsed.radiusMiles} miles.`
                : "No grounded matches found in that radius.",
            results,
            message,
        };
    }
);

// ─── getChurchVisitReadiness ─────────────────────────────────────────────────
// Callable used by SmartChurchDetailView to populate the "What To Expect" card.
// Grounds all advice in stored church fields — never invents facts.

const VISIT_READINESS_FALLBACK = {
    dress: "Come as you are.",
    serviceLength: "Confirm service length with the church.",
    parking: "Check the address before leaving.",
    kidsCheckIn: "Kids check-in details are not verified yet.",
    whatToBring: "Bring anything you normally need for church.",
};

async function generateVisitReadiness(
    data: FirebaseFirestore.DocumentData,
): Promise<typeof VISIT_READINESS_FALLBACK> {
    const key = anthropicApiKey.value();
    if (!key) return VISIT_READINESS_FALLBACK;

    const churchContext = JSON.stringify({
        name: data.name ?? "",
        denomination: data.denomination ?? "",
        worshipStyles: data.worshipStyles ?? [],
        ministries: data.ministries ?? [],
        size: data.size ?? "",
        serviceTimes: data.serviceTimes ?? [],
        description: data.description ?? "",
        statementOfFaith: data.statementOfFaith ?? "",
    });

    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
            model: CLAUDE_MODEL,
            max_tokens: 500,
            temperature: 0,
            system: `Given stored church profile data, return ONLY minified JSON describing a first-time visitor experience.
Use only what the profile tells you. If a field is unknown, give a warm general default (no invented specifics).
Schema: {"dress":string,"serviceLength":string,"parking":string,"kidsCheckIn":string,"whatToBring":string}
Each value under 100 characters. Do not use church-specific claims unless they appear in the provided data.`,
            messages: [{ role: "user", content: churchContext }],
        }),
    });
    if (!response.ok) return VISIT_READINESS_FALLBACK;

    const json = await response.json() as { content?: Array<{ type: string; text?: string }> };
    const text = json.content?.find((part) => part.type === "text")?.text ?? "{}";
    try {
        const parsed = JSON.parse(text) as Partial<typeof VISIT_READINESS_FALLBACK>;
        return {
            dress: (parsed.dress ?? "").slice(0, 120) || VISIT_READINESS_FALLBACK.dress,
            serviceLength: (parsed.serviceLength ?? "").slice(0, 120) || VISIT_READINESS_FALLBACK.serviceLength,
            parking: (parsed.parking ?? "").slice(0, 120) || VISIT_READINESS_FALLBACK.parking,
            kidsCheckIn: (parsed.kidsCheckIn ?? "").slice(0, 120) || VISIT_READINESS_FALLBACK.kidsCheckIn,
            whatToBring: (parsed.whatToBring ?? "").slice(0, 120) || VISIT_READINESS_FALLBACK.whatToBring,
        };
    } catch {
        return VISIT_READINESS_FALLBACK;
    }
}

export const getChurchVisitReadiness = onCall(
    {
        region: REGION,
        enforceAppCheck: true,
        timeoutSeconds: 30,
        memory: "512MiB",
        secrets: [anthropicApiKey],
    },
    async (request) => {
        requireAuth(request);
        const churchId = String(request.data?.churchId ?? "").trim().slice(0, 80);
        if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");
        const snapshot = await db.collection("churches").doc(churchId).get();
        if (!snapshot.exists) {
            return VISIT_READINESS_FALLBACK;
        }
        const data = snapshot.data() ?? {};
        return generateVisitReadiness(data);
    }
);

// ─── extractDoctrinalTags ────────────────────────────────────────────────────
async function extractDoctrinalTags(statementOfFaith: string): Promise<string[]> {
    const key = anthropicApiKey.value();
    if (!key) return [];
    const allowed = ["trinitarian", "nicene_orthodox", "biblical_inerrancy", "evangelical", "continuationist", "cessationist", "sacramental", "credobaptism", "paedobaptism", "complementarian", "egalitarian", "missional", "charismatic", "reformed", "wesleyan", "baptist", "catholic", "orthodox", "pentecostal", "non_denominational"];
    const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
            model: CLAUDE_MODEL,
            max_tokens: 300,
            temperature: 0,
            system: `Choose only tags from this enum and return minified JSON array: ${allowed.join(", ")}`,
            messages: [{ role: "user", content: statementOfFaith.slice(0, 6000) }],
        }),
    });
    if (!response.ok) return [];
    const json = await response.json() as { content?: Array<{ type: string; text?: string }> };
    const text = json.content?.find((part) => part.type === "text")?.text ?? "[]";
    try {
        const parsed = JSON.parse(text) as string[];
        return parsed.filter((tag) => allowed.includes(tag)).slice(0, 12);
    } catch {
        return [];
    }
}
