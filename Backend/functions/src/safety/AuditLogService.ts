/**
 * AuditLogService.ts
 *
 * Structured audit logging for the Amen Safety OS.
 * Writes compliance-grade decision records for every moderation action.
 *
 * Compliance requirement: all moderation decisions must be auditable
 * for 90 days minimum, with no gaps in coverage.
 *
 * Collections:
 *   moderationAuditLog/{docId}  — one doc per moderation decision (text, image, video, audio)
 *   trustAuditLog/{docId}       — one doc per admin trust grant (referenced but not written elsewhere)
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export interface AuditEntry {
  uid: string;
  contentType: string;
  contentId?: string | null;
  mediaType: "text" | "image" | "video" | "audio" | "link";
  decision: "allowed" | "content_warning" | "blocked" | "escalated" | "needs_human_review";
  harmCategoryId: string | null;
  enforcement: string;
  borderlineScore?: number | null;
  perspectiveScores?: Record<string, number> | null;
  isMinor: boolean;
  policyVersion: string;
  createdAt: admin.firestore.FieldValue;
}

// ─── Core Write Function ──────────────────────────────────────────────────────

/**
 * writeAuditEntry — write a single moderation decision to moderationAuditLog.
 * Called internally by moderation callables; never exposed to client directly.
 * Non-fatal: failures are logged but never propagated to the caller.
 */
export async function writeAuditEntry(entry: Omit<AuditEntry, "createdAt">): Promise<void> {
  try {
    await db.collection("moderationAuditLog").add({
      ...entry,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.error("[AuditLogService] Failed to write audit entry — this is a compliance gap.", err);
  }
}

/**
 * writeTrustAuditEntry — write an admin trust grant to trustAuditLog.
 * Called from adminGrantTrustEvent in ProgressiveTrustService.
 */
export async function writeTrustAuditEntry(params: {
  uid: string;
  eventType: string;
  reason: string;
  grantedBy: string;
}): Promise<void> {
  try {
    await db.collection("trustAuditLog").add({
      ...params,
      grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.error("[AuditLogService] Failed to write trust audit entry.", err);
  }
}

// ─── Admin Query Callable ─────────────────────────────────────────────────────

/**
 * queryModerationAuditLog
 *
 * Admin-only callable. Returns recent moderation decisions with optional filters.
 * Requires custom claim: moderator, admin, or trustSafetyReviewer.
 *
 * Input: { uid?: string, harmCategoryId?: string, decision?: string, limit?: number }
 */
export const queryModerationAuditLog = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    uid?: string;
    harmCategoryId?: string;
    decision?: string;
    limit?: number;
  }>) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const claims = request.auth.token as Record<string, unknown>;
    const isAuthorized =
      claims.admin === true ||
      claims.moderator === true ||
      claims.trustSafetyReviewer === true;
    if (!isAuthorized) {
      throw new HttpsError("permission-denied", "Insufficient permissions.");
    }

    const { uid, harmCategoryId, decision, limit = 50 } = request.data;
    const safeLimit = Math.min(Math.max(1, limit), 200);

    let query: admin.firestore.Query = db
      .collection("moderationAuditLog")
      .orderBy("createdAt", "desc")
      .limit(safeLimit);

    if (uid) query = query.where("uid", "==", uid);
    if (harmCategoryId) query = query.where("harmCategoryId", "==", harmCategoryId);
    if (decision) query = query.where("decision", "==", decision);

    const snap = await query.get();
    return {
      entries: snap.docs.map((d) => ({ id: d.id, ...d.data() })),
      count: snap.size,
    };
  }
);
