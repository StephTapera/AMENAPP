/**
 * findChurch2/ingestion.ts
 *
 * Wave 2 Find-a-Church backend: national church data ingestion.
 *
 * Exports
 * -------
 * - ingestChurchesFromGooglePlaces   onCall  — pull churches from Google Places Nearby Search
 * - computeAvailabilityStatus         onCall  — compute + cache open/service status for one church
 * - scheduleAvailabilityRefresh       onSchedule (every 30 min) — batch-refresh stale caches
 *
 * Environment
 * -----------
 * GOOGLE_PLACES_API_KEY — required for ingestChurchesFromGooglePlaces; warning logged if absent.
 *
 * TODO(pinecone): upsert newly ingested church embeddings to Pinecone index once
 *   PINECONE_API_KEY + PINECONE_INDEX_HOST env vars are wired in deployment config.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as https from "https";

const db = admin.firestore();
const REGION = "us-central1";
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

// ─── Shared types ─────────────────────────────────────────────────────────────

type AuthContext = {
    auth?: { uid?: string; token?: Record<string, unknown> };
    app?: { appId?: string };
};

type CallableRequest<T = Record<string, unknown>> = AuthContext & {
    data: T;
};

type DayOfWeek = "sunday" | "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday";

interface ServiceTime {
    day: DayOfWeek;
    /** 24-hour local time, e.g. "10:30" */
    startTime: string;
    /** 24-hour local time, e.g. "12:00" */
    endTime?: string;
    label?: string; // e.g. "Morning Worship", "Bible Study"
    isStudy?: boolean;
    hasLivestream?: boolean;
}

interface ChurchObject {
    placeId: string;
    name: string;
    address?: string;
    city?: string;
    state?: string;
    zip?: string;
    phone?: string;
    website?: string;
    latitude?: number;
    longitude?: number;
    denomination?: string;
    tags?: string[];
    serviceTimes?: ServiceTime[];
    youtubeChannelURL?: string;
    availabilityCache?: AvailabilityStatus;
    availabilityCachedAt?: admin.firestore.Timestamp;
    createdAt?: admin.firestore.Timestamp;
    updatedAt?: admin.firestore.Timestamp;
}

interface AvailabilityStatus {
    openNow: boolean;
    serviceToday: boolean;
    /** Human-readable next service time, e.g. "Sunday 10:30 AM" */
    serviceTime: string | null;
    studyTonight: boolean;
    livestreamActive: boolean;
    /** True when there are no service times in Firestore and the user should contact the church */
    contactNeeded: boolean;
}

interface PlacesResult {
    place_id: string;
    name: string;
    vicinity?: string;
    geometry?: {
        location: { lat: number; lng: number };
    };
    formatted_phone_number?: string;
    website?: string;
    types?: string[];
}

interface PlacesNearbyResponse {
    results: PlacesResult[];
    next_page_token?: string;
    status: string;
    error_message?: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request: AuthContext): string {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return uid;
}

function requireAppCheck(request: AuthContext): void {
    if (IS_EMULATOR) return;
    if (!request.app?.appId) {
        throw new HttpsError("failed-precondition", "App Check token required.");
    }
}

/** Firestore lock document path used for per-function rate limiting. */
const INGEST_LOCK_DOC = "_systemLocks/ingestChurches";
/** Minimum milliseconds between ingestChurchesFromGooglePlaces calls. */
const INGEST_RATE_LIMIT_MS = 5_000;
/** Maximum Places results consumed per call (API max is 20 per page, we cap at 50 across pages). */
const MAX_PLACES_PER_CALL = 50;

/**
 * Minimal promisified HTTPS GET that returns parsed JSON.
 * We avoid axios/node-fetch to keep dependencies minimal.
 */
function httpsGetJson<T>(url: string): Promise<T> {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let raw = "";
            res.on("data", (chunk: Buffer) => { raw += chunk.toString(); });
            res.on("end", () => {
                try {
                    resolve(JSON.parse(raw) as T);
                } catch (e) {
                    reject(new Error(`JSON parse error: ${(e as Error).message}`));
                }
            });
            res.on("error", reject);
        }).on("error", reject);
    });
}

/** Parse a Google Places vicinity string into a partial ChurchObject address. */
function parseVicinity(vicinity: string | undefined): Pick<ChurchObject, "address" | "city" | "state"> {
    if (!vicinity) return {};
    const parts = vicinity.split(",").map((s) => s.trim());
    return {
        address: parts[0] ?? undefined,
        city: parts[1] ?? undefined,
        state: parts[2] ?? undefined,
    };
}

/**
 * Compute AvailabilityStatus from a serviceTimes array.
 * All time comparisons use the server's wall-clock time (UTC) adjusted by a
 * rough day-of-week mapping — for production accuracy the church timezone
 * should be stored and used instead.
 */
function computeAvailabilityFromServiceTimes(serviceTimes: ServiceTime[]): AvailabilityStatus {
    if (!serviceTimes || serviceTimes.length === 0) {
        return {
            openNow: false,
            serviceToday: false,
            serviceTime: null,
            studyTonight: false,
            livestreamActive: false,
            contactNeeded: true,
        };
    }

    const now = new Date();
    const dayNames: DayOfWeek[] = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
    const todayName = dayNames[now.getDay()];
    const nowMinutes = now.getHours() * 60 + now.getMinutes();

    const todayServices = serviceTimes.filter((s) => s.day === todayName);

    let openNow = false;
    let studyTonight = false;
    let livestreamActive = false;
    let nearestServiceLabel: string | null = null;
    let nearestMinutesAhead = Infinity;

    for (const service of todayServices) {
        const [startH, startM] = service.startTime.split(":").map(Number);
        const startMinutes = (startH ?? 0) * 60 + (startM ?? 0);
        const endMinutes = service.endTime
            ? (() => {
                const [endH, endM] = service.endTime.split(":").map(Number);
                return (endH ?? 0) * 60 + (endM ?? 0);
            })()
            : startMinutes + 90; // default 90-minute service window

        if (nowMinutes >= startMinutes && nowMinutes < endMinutes) {
            openNow = true;
            if (service.hasLivestream) livestreamActive = true;
        }
        if (service.isStudy && nowMinutes < endMinutes) {
            studyTonight = true;
        }
        const ahead = startMinutes - nowMinutes;
        if (ahead > 0 && ahead < nearestMinutesAhead) {
            nearestMinutesAhead = ahead;
            const ampm = (startH ?? 0) >= 12 ? "PM" : "AM";
            const displayH = (startH ?? 0) % 12 || 12;
            const displayM = String(startM ?? 0).padStart(2, "0");
            nearestServiceLabel = `Today ${displayH}:${displayM} ${ampm}`;
        }
    }

    // If no service found today, find the next upcoming day
    if (!nearestServiceLabel && !openNow) {
        for (let i = 1; i <= 7; i++) {
            const nextDay = dayNames[(now.getDay() + i) % 7];
            const nextDayServices = serviceTimes.filter((s) => s.day === nextDay);
            if (nextDayServices.length > 0) {
                const first = nextDayServices.sort((a, b) => a.startTime.localeCompare(b.startTime))[0];
                const [startH, startM] = first.startTime.split(":").map(Number);
                const ampm = (startH ?? 0) >= 12 ? "PM" : "AM";
                const displayH = (startH ?? 0) % 12 || 12;
                const displayM = String(startM ?? 0).padStart(2, "0");
                const capitalizedDay = nextDay.charAt(0).toUpperCase() + nextDay.slice(1);
                nearestServiceLabel = `${capitalizedDay} ${displayH}:${displayM} ${ampm}`;
                break;
            }
        }
    }

    return {
        openNow,
        serviceToday: todayServices.length > 0,
        serviceTime: nearestServiceLabel,
        studyTonight,
        livestreamActive,
        contactNeeded: false,
    };
}

// ─── 1. ingestChurchesFromGooglePlaces ────────────────────────────────────────

interface IngestRequest {
    location: { lat: number; lng: number };
    radiusMeters: number;
    pageToken?: string;
}

interface IngestResponse {
    inserted: number;
    skipped: number;
    nextPageToken?: string;
}

export const ingestChurchesFromGooglePlaces = onCall(
    { region: REGION, enforceAppCheck: !IS_EMULATOR },
    async (request: CallableRequest<IngestRequest>): Promise<IngestResponse> => {
        requireAuth(request);
        requireAppCheck(request);

        // Admin-only guard: only users with admin custom claim may trigger ingestion.
        if (request.auth?.token?.admin !== true) {
            throw new HttpsError("permission-denied", "Admin privileges required for church ingestion.");
        }

        const apiKey = process.env.GOOGLE_PLACES_API_KEY;
        if (!apiKey) {
            logger.warn("ingestChurchesFromGooglePlaces: GOOGLE_PLACES_API_KEY not set — skipping.");
            return { inserted: 0, skipped: 0 };
        }

        const { location, radiusMeters, pageToken } = request.data ?? {};
        if (!location?.lat || !location?.lng) {
            throw new HttpsError("invalid-argument", "location.lat and location.lng are required.");
        }
        if (!radiusMeters || radiusMeters <= 0 || radiusMeters > 50_000) {
            throw new HttpsError("invalid-argument", "radiusMeters must be between 1 and 50000.");
        }

        // ── Rate-limit check (Firestore lock doc) ────────────────────────────
        const lockRef = db.doc(INGEST_LOCK_DOC);
        const lockSnap = await lockRef.get();
        if (lockSnap.exists) {
            const lastCallMs: number = (lockSnap.data()?.lastCallAt as admin.firestore.Timestamp)
                ?.toMillis() ?? 0;
            const elapsed = Date.now() - lastCallMs;
            if (elapsed < INGEST_RATE_LIMIT_MS) {
                throw new HttpsError(
                    "resource-exhausted",
                    `Rate limit: wait ${Math.ceil((INGEST_RATE_LIMIT_MS - elapsed) / 1000)}s before retrying.`
                );
            }
        }
        await lockRef.set({ lastCallAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

        // ── Google Places Nearby Search ───────────────────────────────────────
        let url =
            `https://maps.googleapis.com/maps/api/place/nearbysearch/json` +
            `?location=${location.lat},${location.lng}` +
            `&radius=${radiusMeters}` +
            `&type=church` +
            `&key=${encodeURIComponent(apiKey)}`;
        if (pageToken) {
            url += `&pagetoken=${encodeURIComponent(pageToken)}`;
        }

        let placesResponse: PlacesNearbyResponse;
        try {
            placesResponse = await httpsGetJson<PlacesNearbyResponse>(url);
        } catch (err) {
            logger.error("ingestChurchesFromGooglePlaces: Places API network error", err);
            return { inserted: 0, skipped: 0 };
        }

        if (
            placesResponse.status !== "OK" &&
            placesResponse.status !== "ZERO_RESULTS"
        ) {
            logger.error(
                "ingestChurchesFromGooglePlaces: Places API error",
                placesResponse.status,
                placesResponse.error_message
            );
            return { inserted: 0, skipped: 0 };
        }

        const results = (placesResponse.results ?? []).slice(0, MAX_PLACES_PER_CALL);
        let inserted = 0;
        let skipped = 0;

        for (const place of results) {
            if (!place.place_id) { skipped++; continue; }

            // Dedup: check if placeId already exists in churches/
            const existing = await db
                .collection("churches")
                .where("placeId", "==", place.place_id)
                .limit(1)
                .get();

            if (!existing.empty) {
                skipped++;
                continue;
            }

            const addressParts = parseVicinity(place.vicinity);
            const churchDoc: ChurchObject = {
                placeId: place.place_id,
                name: place.name ?? "Unknown Church",
                address: addressParts.address,
                city: addressParts.city,
                state: addressParts.state,
                latitude: place.geometry?.location?.lat,
                longitude: place.geometry?.location?.lng,
                website: place.website,
                phone: place.formatted_phone_number,
                serviceTimes: [],
                tags: [],
                createdAt: admin.firestore.Timestamp.now(),
                updatedAt: admin.firestore.Timestamp.now(),
            };

            try {
                await db.collection("churches").add(churchDoc);
                inserted++;
                // TODO(pinecone): upsert churchDoc embedding to Pinecone index using
                //   PINECONE_API_KEY + PINECONE_INDEX_HOST once those secrets are available.
            } catch (writeErr) {
                logger.error("ingestChurchesFromGooglePlaces: Firestore write error", writeErr);
                skipped++;
            }
        }

        logger.info(
            `ingestChurchesFromGooglePlaces: inserted=${inserted} skipped=${skipped}`,
            { lat: location.lat, lng: location.lng, radiusMeters }
        );

        return {
            inserted,
            skipped,
            ...(placesResponse.next_page_token
                ? { nextPageToken: placesResponse.next_page_token }
                : {}),
        };
    }
);

// ─── 2. computeAvailabilityStatus ─────────────────────────────────────────────

interface ComputeAvailabilityRequest {
    churchId: string;
}

export const computeAvailabilityStatus = onCall(
    { region: REGION, enforceAppCheck: !IS_EMULATOR },
    async (request: CallableRequest<ComputeAvailabilityRequest>): Promise<AvailabilityStatus> => {
        requireAuth(request);
        requireAppCheck(request);

        const churchId = String(request.data?.churchId ?? "").trim();
        if (!churchId) {
            throw new HttpsError("invalid-argument", "churchId is required.");
        }

        const snap = await db.collection("churches").doc(churchId).get();
        if (!snap.exists) {
            throw new HttpsError("not-found", `Church ${churchId} not found.`);
        }

        const data = snap.data() as ChurchObject;
        const serviceTimes: ServiceTime[] = Array.isArray(data.serviceTimes)
            ? (data.serviceTimes as ServiceTime[])
            : [];

        const status = computeAvailabilityFromServiceTimes(serviceTimes);

        // Write-back cache
        await snap.ref.update({
            availabilityCache: status,
            availabilityCachedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return status;
    }
);

// ─── 3. scheduleAvailabilityRefresh ───────────────────────────────────────────

/** Max churches refreshed per scheduler run. */
const REFRESH_BATCH_SIZE = 100;
/** Cache TTL in milliseconds — churches older than this are re-computed. */
const CACHE_TTL_MS = 4 * 60 * 60 * 1000; // 4 hours

export const scheduleAvailabilityRefresh = onSchedule(
    {
        schedule: "every 30 minutes",
        region: REGION,
        timeZone: "America/New_York",
    },
    async (): Promise<void> => {
        const staleThreshold = admin.firestore.Timestamp.fromMillis(
            Date.now() - CACHE_TTL_MS
        );

        // Query churches with stale or absent availability cache
        const staleQuery = await db
            .collection("churches")
            .where("availabilityCachedAt", "<=", staleThreshold)
            .limit(REFRESH_BATCH_SIZE)
            .get();

        // Also fetch churches that have never had their cache set (field absent)
        const neverCachedQuery = await db
            .collection("churches")
            .where("availabilityCachedAt", "==", null)
            .limit(REFRESH_BATCH_SIZE - staleQuery.size)
            .get();

        const toRefresh = [
            ...staleQuery.docs,
            ...neverCachedQuery.docs,
        ].slice(0, REFRESH_BATCH_SIZE);

        if (toRefresh.length === 0) {
            logger.info("scheduleAvailabilityRefresh: all availability caches are fresh.");
            return;
        }

        let successCount = 0;
        let errorCount = 0;

        for (const doc of toRefresh) {
            try {
                const data = doc.data() as ChurchObject;
                const serviceTimes: ServiceTime[] = Array.isArray(data.serviceTimes)
                    ? (data.serviceTimes as ServiceTime[])
                    : [];

                const status = computeAvailabilityFromServiceTimes(serviceTimes);

                await doc.ref.update({
                    availabilityCache: status,
                    availabilityCachedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                successCount++;
            } catch (err) {
                errorCount++;
                logger.error(`scheduleAvailabilityRefresh: failed for church ${doc.id}`, err);
            }
        }

        logger.info(
            `scheduleAvailabilityRefresh: refreshed=${successCount} errors=${errorCount}`,
            { batchSize: toRefresh.length }
        );
    }
);
