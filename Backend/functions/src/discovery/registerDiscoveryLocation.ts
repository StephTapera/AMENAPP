/**
 * registerDiscoveryLocation.ts
 *
 * Callable Cloud Function: "registerDiscoveryLocation"
 * Called when the user opts in to the "Find people near me" feature.
 *
 * Input:
 *   { geoHash: string, expiresAt?: Timestamp }
 *
 * Behaviour:
 *   - Validates and sanitises the geoHash (alphanumeric, 4–12 chars)
 *   - Writes to users/{uid} → merges { discoveryGeoHash, discoveryLocationExpiresAt }
 *   - TTL: expiresAt is optional; defaults to 30 days from now.
 *     The field is used by getSuggestedFollows to exclude stale locations.
 *   - Rate-limited: max 10 calls/hour per user.
 *
 * Privacy design:
 *   - Only the geoHash prefix (first 4 chars ≈ city-level) is used for matching.
 *   - Full geoHash is stored on the user doc and never returned to other users.
 *   - The user can opt out by calling this function with geoHash="" or by
 *     deleting the field via clearDiscoveryLocation (see below).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { enforceRateLimit, RateLimitConfig } from "../rateLimit";

const db = admin.firestore();

// ─── Rate limit: 10 calls / hour ─────────────────────────────────────────────

const DISCOVERY_LOCATION_PER_HOUR: RateLimitConfig = {
    name: "discovery_location_1hr",
    windowMs: 60 * 60 * 1000,  // 1 hour
    maxCalls: 10,
};

// ─── TTL default ─────────────────────────────────────────────────────────────

const DEFAULT_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

// ─── Validation ──────────────────────────────────────────────────────────────

/**
 * A valid geoHash is 4–12 base-32 characters (alphanumeric, lower-case subset).
 * We accept upper or lower case and normalise to lower.
 * An empty string signals an opt-out (clears the location).
 */
function validateGeoHash(raw: unknown): string | null {
    if (typeof raw !== "string") return null;
    const trimmed = raw.trim().toLowerCase();
    if (trimmed === "") return "";  // opt-out
    if (/^[0-9a-z]{4,12}$/.test(trimmed)) return trimmed;
    return null;
}

// ─── Main Cloud Function ──────────────────────────────────────────────────────

interface RegisterDiscoveryLocationRequest {
    geoHash: string;
    /** Optional: iOS can pass a Firestore Timestamp or ISO-8601 string */
    expiresAt?: admin.firestore.Timestamp | { _seconds: number; _nanoseconds: number } | string;
}

export const registerDiscoveryLocation = functions.https.onCall(
    async (data: RegisterDiscoveryLocationRequest, context) => {
        // Auth guard
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
        }

        // App Check guard
        if (context.app == null) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Must be called from an App Check verified app."
            );
        }

        // Rate limit: 10 calls per hour
        await enforceRateLimit(context.auth.uid, [DISCOVERY_LOCATION_PER_HOUR]);

        const uid = context.auth.uid;

        // Validate geoHash
        const geoHash = validateGeoHash(data.geoHash);
        if (geoHash === null) {
            throw new functions.https.HttpsError(
                "invalid-argument",
                "geoHash must be a 4–12 character alphanumeric string, or empty string to opt out."
            );
        }

        const userRef = db.collection("users").doc(uid);

        // Opt-out path: clear the discovery location entirely
        if (geoHash === "") {
            await userRef.update({
                discoveryGeoHash: admin.firestore.FieldValue.delete(),
                discoveryLocationExpiresAt: admin.firestore.FieldValue.delete(),
                discoveryLocationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            functions.logger.info(`[DiscoveryLocation] uid=${uid} opted out`);
            return { ok: true, optedOut: true };
        }

        // Resolve expiresAt — accept Timestamp-like objects, ISO strings, or default
        let expiresAtMs: number = Date.now() + DEFAULT_TTL_MS;

        if (data.expiresAt != null) {
            if (
                typeof data.expiresAt === "object" &&
                "_seconds" in data.expiresAt
            ) {
                expiresAtMs = data.expiresAt._seconds * 1000;
            } else if (
                data.expiresAt instanceof admin.firestore.Timestamp
            ) {
                expiresAtMs = data.expiresAt.toMillis();
            } else if (typeof data.expiresAt === "string") {
                const parsed = Date.parse(data.expiresAt);
                if (!isNaN(parsed)) expiresAtMs = parsed;
            }

            // Clamp: must not be in the past, and no more than 90 days ahead
            const now = Date.now();
            if (expiresAtMs <= now) expiresAtMs = now + DEFAULT_TTL_MS;
            const MAX_TTL_MS = 90 * 24 * 60 * 60 * 1000;
            if (expiresAtMs > now + MAX_TTL_MS) expiresAtMs = now + MAX_TTL_MS;
        }

        const expiresAt = admin.firestore.Timestamp.fromMillis(expiresAtMs);

        // Write location to user document (merge so nothing else is overwritten)
        await userRef.set(
            {
                discoveryGeoHash: geoHash,
                discoveryLocationExpiresAt: expiresAt,
                discoveryLocationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
        );

        functions.logger.info(
            `[DiscoveryLocation] uid=${uid} geoHash=${geoHash.substring(0, 4)}**** ` +
            `expires=${new Date(expiresAtMs).toISOString()}`
        );

        return { ok: true, optedOut: false, expiresAt: expiresAt.toDate().toISOString() };
    }
);

// ─── clearDiscoveryLocation ───────────────────────────────────────────────────
// Convenience callable for iOS "Opt out" button — identical to passing geoHash="".

export const clearDiscoveryLocation = functions.https.onCall(
    async (_data: unknown, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
        }
        if (context.app == null) {
            throw new functions.https.HttpsError(
                "failed-precondition",
                "Must be called from an App Check verified app."
            );
        }

        const uid = context.auth.uid;
        const userRef = db.collection("users").doc(uid);

        await userRef.update({
            discoveryGeoHash: admin.firestore.FieldValue.delete(),
            discoveryLocationExpiresAt: admin.firestore.FieldValue.delete(),
            discoveryLocationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        functions.logger.info(`[DiscoveryLocation] uid=${uid} cleared via clearDiscoveryLocation`);
        return { ok: true };
    }
);
