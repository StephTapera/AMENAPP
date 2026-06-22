// creatorProfilesShared.ts
// AMEN — Creator Profiles: shared backend helpers (auth, App Check, roles, paths, serialization).
//
// Collection topology (namespaced `creatorHub*` to avoid colliding with the existing
// `follows` social graph and the `creator` video-studio domain):
//   creatorHubs/{creatorId}                      — profile (public fields readable)
//   creatorHubs/{creatorId}/events/{id}
//   creatorHubs/{creatorId}/teachings/{id}
//   creatorHubs/{creatorId}/resources/{id}
//   creatorHubs/{creatorId}/courses/{id}
//   creatorHubs/{creatorId}/prayerRequests/{id}  — public only when status==approved && !isPrivate
//   creatorHubs/{creatorId}/communityPosts/{id}  — public only when status==approved
//   creatorHubs/{creatorId}/moderationQueue/{id} — owner/mod/admin only
//   creatorHubs/{creatorId}/roles/{uid}          — moderator grants (server-written)
//   creatorHubs/{creatorId}/eventRsvps/{id}_{uid}
//   creatorHubMetrics/{creatorId}                — server-write only
//   creatorHubFollows/{userId}_{creatorId}       — owner read/write of own subscription

import * as admin from "firebase-admin";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";

// ── Collection / path helpers ───────────────────────────────────────────────

export const COLL = {
    hubs: "creatorHubs",
    metrics: "creatorHubMetrics",
    follows: "creatorHubFollows",
} as const;

export const SUB = {
    events: "events",
    teachings: "teachings",
    resources: "resources",
    courses: "courses",
    prayerRequests: "prayerRequests",
    communityPosts: "communityPosts",
    moderationQueue: "moderationQueue",
    roles: "roles",
    eventRsvps: "eventRsvps",
} as const;

export function db() {
    return admin.firestore();
}

export function hubRef(creatorId: string) {
    return db().collection(COLL.hubs).doc(creatorId);
}

export function subCol(creatorId: string, sub: (typeof SUB)[keyof typeof SUB]) {
    return hubRef(creatorId).collection(sub);
}

// ── Auth / App Check ────────────────────────────────────────────────────────

/** Requires a signed-in, App-Check-verified caller. Returns the uid. */
export function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    if (request.app === undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }
    return request.auth.uid;
}

// ── Roles (never trust client-asserted role fields) ─────────────────────────

export interface CreatorHubRole {
    isOwner: boolean;
    isModerator: boolean;
    isAdmin: boolean;
}

/** True if the caller may manage (write/moderate) this creator hub. */
export function canManage(role: CreatorHubRole): boolean {
    return role.isOwner || role.isModerator || role.isAdmin;
}

/**
 * Resolves the caller's role for a hub from server-trusted sources only:
 *   - platform admin: custom claim `admin === true`
 *   - owner: creatorHubs/{creatorId}.ownerUid === uid (server-set, immutable)
 *   - moderator: creatorHubs/{creatorId}/roles/{uid}.role === "moderator"
 */
export async function resolveRole(request: CallableRequest, creatorId: string): Promise<CreatorHubRole> {
    const uid = request.auth!.uid;
    const isAdmin = request.auth?.token?.admin === true;

    const [hubSnap, roleSnap] = await Promise.all([
        hubRef(creatorId).get(),
        subCol(creatorId, SUB.roles).doc(uid).get(),
    ]);

    const isOwner = hubSnap.exists && hubSnap.data()?.ownerUid === uid;
    const isModerator = roleSnap.exists && roleSnap.data()?.role === "moderator";
    return { isOwner, isModerator, isAdmin };
}

/** Throws permission-denied unless the caller may manage the hub. */
export async function requireManage(request: CallableRequest, creatorId: string): Promise<CreatorHubRole> {
    const role = await resolveRole(request, creatorId);
    if (!canManage(role)) {
        throw new HttpsError("permission-denied", "Not authorized to manage this creator hub.");
    }
    return role;
}

// ── Serialization (Firestore Timestamp ⇄ ISO-8601 wire strings) ─────────────

export function tsToISO(value: unknown): string | undefined {
    if (!value) return undefined;
    if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString();
    if (value instanceof Date) return value.toISOString();
    if (typeof value === "string") return value;
    return undefined;
}

export function nowISO(): string {
    return new Date().toISOString();
}

// ── Input validation helpers ────────────────────────────────────────────────

export function reqString(data: any, key: string): string {
    const v = data?.[key];
    if (typeof v !== "string" || !v.trim()) {
        throw new HttpsError("invalid-argument", `Missing or invalid '${key}'.`);
    }
    return v.trim();
}

export function optString(data: any, key: string): string | undefined {
    const v = data?.[key];
    return typeof v === "string" && v.trim() ? v.trim() : undefined;
}

/** Clamp a requested page size into a CalmCap-friendly bound. */
export function pageLimit(data: any, fallback = 12, max = 24): number {
    const n = Number(data?.limit);
    if (!Number.isFinite(n) || n <= 0) return fallback;
    return Math.min(Math.floor(n), max);
}
