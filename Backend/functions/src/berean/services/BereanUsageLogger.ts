/**
 * BereanUsageLogger.ts
 *
 * Structured observability logging for every Berean AI generation request.
 * Written to `bereanUsageLogs/{logId}` for monitoring, replay, and billing audits.
 *
 * All logging calls are fire-and-forget — never block the response on a log write.
 */

import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { BereanModelMode, BereanTier } from "./BereanEntitlementService";

// ---------------------------------------------------------------------------
// Log entry shape
// ---------------------------------------------------------------------------

export interface BereanUsageLogEntry {
  /** Firestore UID of the requesting user. */
  userId: string;
  /** Berean conversation session ID. */
  conversationId: string;
  /** The mode the client requested. */
  selectedMode: BereanModelMode;
  /** The mode the backend actually used after entitlement checks. */
  acceptedMode: BereanModelMode;
  /** Human-readable reason if selectedMode ≠ acceptedMode. */
  fallbackReason?: string;
  /** Server-validated subscription tier. */
  tier: BereanTier;
  /** True if the mode was rejected because the user's tier doesn't include it. */
  entitlementRequired: boolean;
  /** True if the mode was rejected because deep credits are exhausted. */
  quotaExceeded: boolean;
  /** Deep credits charged for this generation (0 for core). */
  unitsCharged: number;
  /** The Anthropic model ID used for generation. */
  providerModel: string;
  /** True if the response was blocked or short-circuited by the safety system. */
  responseBlocked: boolean;
  /** True if credits were charged (false if blocked before generation). */
  creditsCharged: boolean;
}

// ---------------------------------------------------------------------------
// Logger
// ---------------------------------------------------------------------------

/**
 * Persists a structured usage log entry to `bereanUsageLogs/{logId}`.
 * Fire-and-forget — never await this; call `.catch(() => {})` at the call site.
 */
export async function logBereanUsage(entry: BereanUsageLogEntry): Promise<void> {
  const logId = uuidv4();
  await admin.firestore()
    .collection("bereanUsageLogs")
    .doc(logId)
    .set({
      ...entry,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}
