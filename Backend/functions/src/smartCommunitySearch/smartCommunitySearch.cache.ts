/**
 * smartCommunitySearch.cache.ts
 *
 * Short-lived Firestore cache for Smart Community Search results.
 * TTL: 5 minutes. Cache misses and write failures are treated as non-fatal —
 * the main search flow must never depend on this succeeding.
 *
 * Storage layout:
 *   smartSearchCache/{cacheKey}
 *     - data:      the serialised SmartCommunitySearchResponse
 *     - cachedAt:  server timestamp
 *     - expiresAt: client timestamp (ms) — checked on read
 */

import * as admin from "firebase-admin";

const db = admin.firestore();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const CACHE_COLLECTION = "smartSearchCache";

// ---------------------------------------------------------------------------
// Cache key
// ---------------------------------------------------------------------------

/**
 * Build a deterministic, URL-safe cache key from a query text and optional
 * coordinates rounded to 2 decimal places (≈ 1.1 km precision).
 *
 * Uses `btoa` (available in Node 16+) to produce an ASCII-safe string and
 * slices to 32 chars to keep Firestore document IDs manageable.
 */
export function buildCacheKey(queryText: string, lat?: number, lng?: number): string {
    const latPart = typeof lat === "number" ? lat.toFixed(2) : "";
    const lngPart = typeof lng === "number" ? lng.toFixed(2) : "";
    const raw = `${queryText.toLowerCase().trim()}|${latPart}|${lngPart}`;
    // btoa is safe in Node 16+ (global) and Firebase Functions Node 22 runtime.
    const encoded = Buffer.from(raw).toString("base64");
    // Replace base64 characters that are invalid in Firestore document IDs.
    return encoded.replace(/[+/=]/g, "_").slice(0, 32);
}

// ---------------------------------------------------------------------------
// Read
// ---------------------------------------------------------------------------

/**
 * Return cached search data for the given key, or `null` if absent or expired.
 */
export async function getCachedSearch(key: string): Promise<unknown | null> {
    try {
        const snap = await db.collection(CACHE_COLLECTION).doc(key).get();
        if (!snap.exists) return null;
        const data = snap.data() as Record<string, unknown> | undefined;
        if (!data) return null;
        const expiresAt = typeof data.expiresAt === "number" ? data.expiresAt : 0;
        if (Date.now() > expiresAt) return null;
        return data.data ?? null;
    } catch {
        // Cache read failure must not break the main flow.
        return null;
    }
}

// ---------------------------------------------------------------------------
// Write
// ---------------------------------------------------------------------------

/**
 * Store search data under the given cache key with a 5-minute TTL.
 * Write failures are silenced — callers must not await this for correctness.
 */
export async function setCachedSearch(key: string, data: unknown): Promise<void> {
    try {
        await db.collection(CACHE_COLLECTION).doc(key).set({
            data,
            cachedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: Date.now() + CACHE_TTL_MS,
        });
    } catch {
        // Silently ignore — cache write failure is non-fatal.
    }
}
