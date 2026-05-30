/**
 * smartCommunitySearch.analytics.ts
 *
 * Analytics logging for Smart Community Search.
 *
 * Design principles:
 *  - Raw query text is NEVER stored in analytics events (privacy).
 *  - All errors are silenced — analytics must never break the main flow.
 *  - Events are written to a per-user sub-collection for easy deletion on
 *    account removal.
 *
 * Storage layout:
 *   users/{uid}/smartSearch/analytics/events/{autoId}
 */

import * as admin from "firebase-admin";
import { SmartCommunitySearchIntent } from "./smartCommunitySearch.types";

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Event name constants
// ---------------------------------------------------------------------------

export const SMART_SEARCH_EVENTS = {
    opened: "smart_search_opened",
    submitted: "smart_search_submitted",
    resultViewed: "smart_search_result_viewed",
    refined: "smart_search_refined",
    directionsTapped: "smart_search_directions_tapped",
    saved: "smart_search_saved",
    joinTapped: "smart_search_join_tapped",
    noResults: "smart_search_no_results",
    error: "smart_search_error",
} as const;

export type SmartSearchEventName = typeof SMART_SEARCH_EVENTS[keyof typeof SMART_SEARCH_EVENTS];

// ---------------------------------------------------------------------------
// Event interface
// ---------------------------------------------------------------------------

/**
 * Analytics event payload.
 *
 * Raw query text is intentionally excluded — only `queryCategory` (e.g. "church",
 * "event", "mixed") is stored so we can measure search patterns without retaining
 * PII.
 */
export interface SmartSearchAnalyticsEvent {
    eventName: SmartSearchEventName;
    queryCategory: string;
    resultCount: number;
    surface: string;
    latencyMs: number;
    externalPlacesUsed: boolean;
    aiParserUsed: boolean;
    safetyBlocked: boolean;
    uid: string;
}

// ---------------------------------------------------------------------------
// Low-level writer shared by both callsites
// ---------------------------------------------------------------------------

async function writeEvent(uid: string, payload: Record<string, unknown>): Promise<void> {
    try {
        await db
            .collection("users")
            .doc(uid)
            .collection("smartSearch")
            .doc("analytics")
            .collection("events")
            .add({
                ...payload,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
    } catch {
        // Silently ignore — analytics must never break the main search flow.
    }
}

// ---------------------------------------------------------------------------
// Public API — new shape
// ---------------------------------------------------------------------------

/**
 * Write a strongly-typed analytics event.
 * Silently swallows all errors.
 */
export async function logSmartSearchEvent(
    uid: string,
    event: SmartSearchAnalyticsEvent
): Promise<void> {
    await writeEvent(uid, {
        eventName: event.eventName,
        queryCategory: event.queryCategory,
        resultCount: event.resultCount,
        surface: event.surface,
        latencyMs: event.latencyMs,
        externalPlacesUsed: event.externalPlacesUsed,
        aiParserUsed: event.aiParserUsed,
        safetyBlocked: event.safetyBlocked,
    });
}

// ---------------------------------------------------------------------------
// Public API — backward-compatible shape (used by the index callable)
// ---------------------------------------------------------------------------

/**
 * Record a search analytics event using the legacy flat-object shape.
 * Accepts both old field names (usedExternalPlaces/usedAI) and new names
 * (externalPlacesUsed/aiParserUsed) for forward compatibility.
 *
 * Silently swallows all errors.
 */
export async function recordSmartSearchAnalytics(input: {
    searchId?: string;
    uid: string;
    surface: string;
    intent?: SmartCommunitySearchIntent;
    queryCategory?: string;
    resultCount: number;
    latencyMs: number;
    externalPlacesUsed?: boolean;
    usedExternalPlaces?: boolean;
    aiParserUsed?: boolean;
    usedAI?: boolean;
    safetyBlocked: boolean;
    eventName?: SmartSearchEventName;
}): Promise<void> {
    const queryCategory =
        input.queryCategory ??
        input.intent?.communityType ??
        "general";

    const externalPlacesUsed =
        input.externalPlacesUsed ??
        input.usedExternalPlaces ??
        false;

    const aiParserUsed =
        input.aiParserUsed ??
        input.usedAI ??
        false;

    await writeEvent(input.uid, {
        eventName: input.eventName ?? SMART_SEARCH_EVENTS.submitted,
        queryCategory,
        resultCount: input.resultCount,
        surface: input.surface,
        latencyMs: input.latencyMs,
        externalPlacesUsed,
        aiParserUsed,
        safetyBlocked: input.safetyBlocked,
    });
}
