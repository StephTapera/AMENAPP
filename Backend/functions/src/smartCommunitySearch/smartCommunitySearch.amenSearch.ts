/**
 * smartCommunitySearch.amenSearch.ts
 *
 * Searches Amen's Firestore collections for community results matching a
 * parsed SmartCommunitySearchIntent. Covers churches, spaces, events, and
 * groups. Never returns blocked content. All field access is defensive.
 */

import * as admin from "firebase-admin";
import {
    AmenInternalResult,
    CommunityResultType,
    SmartCommunityLocationContext,
    SmartCommunitySearchIntent,
    SmartSearchActionType,
} from "./smartCommunitySearch.types";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Haversine distance
// ---------------------------------------------------------------------------

/**
 * Returns the great-circle distance in meters between two WGS-84 points.
 */
export function haversineMeters(
    lat1: number,
    lng1: number,
    lat2: number,
    lng2: number
): number {
    const R = 6_371_000; // Earth radius in metres
    const toRad = (degrees: number) => (degrees * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

// ---------------------------------------------------------------------------
// Firestore field helpers
// ---------------------------------------------------------------------------

function strVal(value: unknown): string | undefined {
    const text = String(value ?? "").trim();
    return text || undefined;
}

function numVal(value: unknown): number | undefined {
    const n = Number(value);
    return Number.isFinite(n) ? n : undefined;
}

function listVal(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value.map((item) => String(item ?? "").trim()).filter(Boolean).slice(0, 12);
}

/**
 * Derive a freshness score (0–1) from a Firestore timestamp field.
 * Freshness decays linearly over 90 days; older than 90 days → 0.1.
 */
function freshnessFromTimestamp(value: unknown): number {
    if (!value) return 0.35;
    let ms: number | null = null;
    if (typeof value === "object" && value !== null && "toMillis" in value) {
        ms = (value as admin.firestore.Timestamp).toMillis();
    } else if (typeof value === "number") {
        ms = value;
    }
    if (ms === null) return 0.35;
    const ageMs = Date.now() - ms;
    const ageDays = ageMs / 86_400_000;
    if (ageDays <= 0) return 1.0;
    if (ageDays >= 90) return 0.1;
    return Math.round((1 - ageDays / 90) * 100) / 100;
}

/**
 * Normalise an activity metric to 0–1.
 * Handles raw counts (e.g. memberCount = 3000) or pre-normalised values.
 */
function activityFromData(data: FirebaseFirestore.DocumentData): number {
    const preNorm = numVal(data.activityScore);
    if (preNorm !== undefined && preNorm >= 0 && preNorm <= 1) return preNorm;

    const memberCount = numVal(data.memberCount) ?? numVal(data.subscriberCount) ?? 0;
    const postCount = numVal(data.postCount) ?? numVal(data.totalPosts) ?? 0;

    // Clamp: 0 → 0, 1000+ → 1.0 for members; 0 → 0, 500+ → 1.0 for posts.
    const memberScore = Math.min(memberCount / 1000, 1);
    const postScore = Math.min(postCount / 500, 1);
    return Math.round((memberScore * 0.6 + postScore * 0.4) * 100) / 100;
}

function locationFromData(data: FirebaseFirestore.DocumentData): { lat: number; lng: number } | null {
    // Support multiple field naming conventions used across Amen collections.
    const geo = data.location ?? data.coordinate ?? data.geo ?? data.coordinates;
    if (geo && typeof geo.latitude === "number" && typeof geo.longitude === "number") {
        return { lat: geo.latitude, lng: geo.longitude };
    }
    if (typeof data.latitude === "number" && typeof data.longitude === "number") {
        return { lat: data.latitude, lng: data.longitude };
    }
    if (typeof data.lat === "number" && typeof data.lng === "number") {
        return { lat: data.lat, lng: data.lng };
    }
    return null;
}

function tagsFromData(data: FirebaseFirestore.DocumentData): string[] {
    const raw = [
        ...listVal(data.tags),
        ...listVal(data.traditionTags),
        ...listVal(data.worshipStyleTags),
        ...listVal(data.communityTags),
        ...listVal(data.spaceTags),
        ...listVal(data.topics),
        strVal(data.denomination),
    ].filter(Boolean) as string[];
    return Array.from(new Set(raw)).slice(0, 10);
}

function isBlocked(data: FirebaseFirestore.DocumentData): boolean {
    return (
        data.safetyStatus === "blocked" ||
        data.moderationStatus === "blocked" ||
        data.visibility === "private" ||
        data.isPrivate === true ||
        data.private === true
    );
}

// ---------------------------------------------------------------------------
// Collection mappers
// ---------------------------------------------------------------------------

function mapChurch(
    id: string,
    data: FirebaseFirestore.DocumentData,
    location: SmartCommunityLocationContext | null | undefined
): AmenInternalResult | null {
    if (isBlocked(data)) return null;
    if (data.safetyStatus && data.safetyStatus !== "approved" && data.safetyStatus !== "limited") return null;
    const title = strVal(data.name) ?? strVal(data.displayName);
    if (!title) return null;
    const loc = locationFromData(data);
    const distanceMeters =
        location && loc
            ? haversineMeters(location.lat, location.lng, loc.lat, loc.lng)
            : undefined;

    return {
        id,
        type: "church" as CommunityResultType,
        title,
        subtitle: strVal(data.denomination) ?? strVal(data.address),
        description: strVal(data.description) ?? strVal(data.bio),
        lat: loc?.lat,
        lng: loc?.lng,
        distanceMeters,
        tags: tagsFromData(data),
        safetyStatus: data.safetyStatus === "limited" ? "limited" : "approved",
        freshnessScore: freshnessFromTimestamp(data.updatedAt ?? data.lastUpdatedAt),
        activityScore: activityFromData(data),
        sourcePath: `churches/${id}`,
        primaryAction: "view" as SmartSearchActionType,
        imageUrl: strVal(data.photoUrl) ?? strVal(data.coverPhotoUrl),
        primaryUrl: strVal(data.website) ?? strVal(data.websiteUri),
        isVerified: data.verifiedByAmen === true || data.isVerified === true,
    };
}

function mapSpace(
    id: string,
    data: FirebaseFirestore.DocumentData,
    location: SmartCommunityLocationContext | null | undefined
): AmenInternalResult | null {
    if (isBlocked(data)) return null;
    const title = strVal(data.name) ?? strVal(data.title) ?? strVal(data.displayName);
    if (!title) return null;
    const loc = locationFromData(data);
    const distanceMeters =
        location && loc
            ? haversineMeters(location.lat, location.lng, loc.lat, loc.lng)
            : undefined;

    return {
        id,
        type: "space" as CommunityResultType,
        title,
        subtitle: strVal(data.subtitle) ?? strVal(data.tagline),
        description: strVal(data.description),
        lat: loc?.lat,
        lng: loc?.lng,
        distanceMeters,
        tags: Array.from(new Set([...listVal(data.spaceTags), ...listVal(data.topics)])).slice(0, 10),
        safetyStatus: "approved",
        freshnessScore: freshnessFromTimestamp(data.updatedAt),
        activityScore: activityFromData(data),
        sourcePath: `spaces/${id}`,
        primaryAction: "join" as SmartSearchActionType,
        imageUrl: strVal(data.coverPhotoUrl) ?? strVal(data.bannerUrl),
        primaryUrl: undefined,
        isVerified: false,
    };
}

function mapEvent(
    id: string,
    data: FirebaseFirestore.DocumentData,
    location: SmartCommunityLocationContext | null | undefined
): AmenInternalResult | null {
    if (isBlocked(data)) return null;
    const title = strVal(data.name) ?? strVal(data.title);
    if (!title) return null;
    const loc = locationFromData(data);
    const distanceMeters =
        location && loc
            ? haversineMeters(location.lat, location.lng, loc.lat, loc.lng)
            : undefined;

    return {
        id,
        type: "event" as CommunityResultType,
        title,
        subtitle: strVal(data.subtitle) ?? strVal(data.locationName),
        description: strVal(data.description),
        lat: loc?.lat,
        lng: loc?.lng,
        distanceMeters,
        tags: listVal(data.tags).slice(0, 10),
        safetyStatus: "approved",
        freshnessScore: freshnessFromTimestamp(data.startTime ?? data.updatedAt),
        activityScore: activityFromData(data),
        sourcePath: `events/${id}`,
        primaryAction: "rsvp" as SmartSearchActionType,
        imageUrl: strVal(data.imageUrl) ?? strVal(data.bannerUrl),
        primaryUrl: strVal(data.eventUrl),
        isVerified: false,
    };
}

function mapGroup(
    id: string,
    data: FirebaseFirestore.DocumentData,
    location: SmartCommunityLocationContext | null | undefined
): AmenInternalResult | null {
    if (isBlocked(data)) return null;
    const title = strVal(data.name) ?? strVal(data.title) ?? strVal(data.displayName);
    if (!title) return null;
    const loc = locationFromData(data);
    const distanceMeters =
        location && loc
            ? haversineMeters(location.lat, location.lng, loc.lat, loc.lng)
            : undefined;

    return {
        id,
        type: "group" as CommunityResultType,
        title,
        subtitle: strVal(data.subtitle) ?? strVal(data.tagline),
        description: strVal(data.description),
        lat: loc?.lat,
        lng: loc?.lng,
        distanceMeters,
        tags: listVal(data.tags).slice(0, 10),
        safetyStatus: "approved",
        freshnessScore: freshnessFromTimestamp(data.updatedAt),
        activityScore: activityFromData(data),
        sourcePath: `groups/${id}`,
        primaryAction: "join" as SmartSearchActionType,
        imageUrl: strVal(data.coverPhotoUrl),
        primaryUrl: undefined,
        isVerified: false,
    };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Search Amen's Firestore collections for community results.
 * Never returns blocked or private items.
 * Location is used to compute haversine distance where coordinates exist.
 */
export async function searchAmenInternal(input: {
    intent: SmartCommunitySearchIntent;
    location?: SmartCommunityLocationContext | null;
    uid: string;
}): Promise<AmenInternalResult[]> {
    const { intent, location } = input;

    const [churchSnap, spaceSnap, eventSnap, groupSnap] = await Promise.all([
        db
            .collection("churches")
            .where("safetyStatus", "==", "approved")
            .limit(40)
            .get(),
        db
            .collection("spaces")
            .where("visibility", "==", "public")
            .limit(20)
            .get(),
        db
            .collection("events")
            .where("visibility", "==", "public")
            .where("startTime", ">=", new Date())
            .limit(20)
            .get(),
        db
            .collection("groups")
            .where("visibility", "==", "public")
            .limit(20)
            .get(),
    ]);

    const results: AmenInternalResult[] = [];

    for (const doc of churchSnap.docs) {
        const mapped = mapChurch(doc.id, doc.data(), location);
        if (mapped) results.push(mapped);
    }

    // Include spaces/events/groups only when intent is mixed or explicitly matching type.
    const includeAll = intent.communityType === "mixed";

    if (includeAll || intent.communityType === "space") {
        for (const doc of spaceSnap.docs) {
            const mapped = mapSpace(doc.id, doc.data(), location);
            if (mapped) results.push(mapped);
        }
    }

    if (includeAll || intent.communityType === "event") {
        for (const doc of eventSnap.docs) {
            const mapped = mapEvent(doc.id, doc.data(), location);
            if (mapped) results.push(mapped);
        }
    }

    if (includeAll || intent.communityType === "group") {
        for (const doc of groupSnap.docs) {
            const mapped = mapGroup(doc.id, doc.data(), location);
            if (mapped) results.push(mapped);
        }
    }

    return results;
}
