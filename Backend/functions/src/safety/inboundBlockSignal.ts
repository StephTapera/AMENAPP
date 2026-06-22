/**
 * inboundBlockSignal.ts — "blocked by multiple people" advisory signal.
 *
 * WHY THIS EXISTS (Trust & Safety Remediation item 21, follow-on gap):
 *   When an account has been blocked by several distinct users, a person about to
 *   open a DM with that account benefits from a quiet caution. This is a known
 *   harassment / grooming early-warning pattern: serial bad actors accumulate
 *   blocks before being formally reported.
 *
 * PRIVACY POSTURE (this is the whole point — get it wrong and it becomes its own
 * harassment vector):
 *   - The caller NEVER learns the raw block count, and NEVER learns WHO blocked
 *     the target. The callable returns only a coarse bucket ("none" | "elevated")
 *     and a boolean `shouldWarn`. That is the minimum information needed to render
 *     "This account has been blocked by several people — proceed with care."
 *   - A user cannot probe their own popularity-of-blocking beyond that one bit.
 *
 * SAFETY POSTURE:
 *   - Ships DARK: gated behind INBOUND_BLOCK_WARNING_ENABLED (default OFF). When
 *     off, the callable returns `enabled:false, shouldWarn:false` WITHOUT querying.
 *   - FAIL-OPEN: this is an advisory hint, not an access gate. If the count cannot
 *     be read, we return no warning rather than block messaging or cry wolf. (The
 *     real block enforcement still lives in antiHarassmentEnforcement.ts; this
 *     module never affects message delivery.)
 *   - Self-target and unauthenticated callers get no warning.
 *
 * DATA SOURCE:
 *   Counts the top-level `blockedUsers` collection (doc id `{blockerId}_{blockedId}`,
 *   field `blockedId`) with an aggregation count query — equality on a single field
 *   uses Firestore's automatic single-field index, so no composite index is needed.
 *   Each top-level doc is one distinct (blocker, blocked) pair, so the count is the
 *   number of distinct blockers.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

const db = () => admin.firestore();

/** Master switch. Default OFF: callable answers "not enabled" without querying. */
const WARNING_ENABLED =
    (process.env.INBOUND_BLOCK_WARNING_ENABLED ?? "false") === "true";

/** Distinct-blocker count at or above which we surface the caution. */
const WARNING_THRESHOLD = (() => {
    const raw = Number(process.env.INBOUND_BLOCK_WARNING_THRESHOLD ?? "3");
    return Number.isFinite(raw) && raw >= 1 ? Math.floor(raw) : 3;
})();

export type InboundBlockBucket = "none" | "elevated";

export interface InboundBlockSignal {
    enabled: boolean;
    signal: InboundBlockBucket;
    shouldWarn: boolean;
    /** The threshold used, for client display ("blocked by several people"). */
    threshold: number;
}

/**
 * Map a raw distinct-blocker count to the coarse public bucket. Pure + exported
 * so the bucketing contract can be unit-tested without Firestore.
 */
export function bucketInboundBlocks(
    count: number,
    threshold: number = WARNING_THRESHOLD
): InboundBlockBucket {
    return count >= threshold ? "elevated" : "none";
}

const NO_WARNING = (enabled: boolean): InboundBlockSignal => ({
    enabled,
    signal: "none",
    shouldWarn: false,
    threshold: WARNING_THRESHOLD,
});

/**
 * Count distinct blockers of `targetUid` and reduce to a coarse signal. Returns
 * NO_WARNING(true) on any read failure (fail-open — advisory only).
 */
export async function evaluateInboundBlockSignal(
    targetUid: string
): Promise<InboundBlockSignal> {
    try {
        const agg = await db()
            .collection("blockedUsers")
            .where("blockedId", "==", targetUid)
            .count()
            .get();
        const count = agg.data().count;
        const signal = bucketInboundBlocks(count);
        return {
            enabled: true,
            signal,
            shouldWarn: signal === "elevated",
            threshold: WARNING_THRESHOLD,
        };
    } catch (err) {
        logger.warn(
            `[InboundBlockSignal] count failed for ${targetUid}; failing open (no warning): ${(err as Error).message}`
        );
        return NO_WARNING(true);
    }
}

/**
 * getInboundBlockSignal — advisory caution for "this account has been blocked by
 * several people." Returns only a coarse bucket; never the count or identities.
 */
export const getInboundBlockSignal = onCall(
    { enforceAppCheck: true },
    async (request): Promise<InboundBlockSignal> => {
        const callerUid = request.auth?.uid;
        if (!callerUid) {
            throw new HttpsError("unauthenticated", "Auth required");
        }

        // Ships dark — no query, no signal, until deliberately enabled.
        if (!WARNING_ENABLED) {
            return NO_WARNING(false);
        }

        const data = (request.data ?? {}) as Record<string, unknown>;
        const targetUid =
            typeof data["targetUid"] === "string" ? (data["targetUid"] as string).trim() : "";
        if (!targetUid) {
            throw new HttpsError("invalid-argument", "targetUid required");
        }

        // You cannot probe your own block-count.
        if (targetUid === callerUid) {
            return NO_WARNING(true);
        }

        return evaluateInboundBlockSignal(targetUid);
    }
);
