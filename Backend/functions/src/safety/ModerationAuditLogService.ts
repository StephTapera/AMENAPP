/**
 * ModerationAuditLogService.ts
 *
 * Immutable audit logging for Amen Safety OS.
 * Every moderation decision — allow, block, escalate, human review outcome,
 * strike issue, account suspension, evidence preservation — is logged here.
 *
 * Audit logs are:
 *   - Immutable (Firestore rules prevent updates/deletes by all users and Cloud Functions)
 *   - Written with server timestamps
 *   - Queryable by moderators for incident reconstruction
 *   - Retained for the platform's legal retention period
 *   - Anonymized at the entry level: no raw content text, only content IDs
 *
 * Data model:
 *   moderationAuditLog/{logId}
 *     eventType: AuditEventType
 *     actorUid: string          (who triggered the event — user or "server")
 *     targetUid?: string        (whose content was affected)
 *     contentId?: string
 *     contentType?: string
 *     harmCategoryId?: string
 *     enforcement?: string
 *     moderationStatus?: string
 *     resolution?: string       (for human review resolutions)
 *     source: string            (which service wrote this log)
 *     policyVersion: string
 *     createdAt: Timestamp
 *
 * NOTE: Firestore rules must set:
 *   match /moderationAuditLog/{logId} {
 *     allow read: if isModerator() || isAdmin();
 *     allow create: if false;  // Server-written only
 *     allow update, delete: if false;
 *   }
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type AuditEventType =
  | "content_moderated"        // Text/image/video/audio moderation decision
  | "content_blocked"          // Content blocked by any moderation layer
  | "content_escalated"        // Content escalated to T&S queue
  | "content_approved_auto"    // Content auto-approved by pipeline
  | "content_approved_human"   // Content approved by human reviewer
  | "content_removed_human"    // Content removed by human reviewer
  | "content_false_positive"   // Human reviewer marked auto-block as false positive
  | "strike_issued"            // Strike recorded on account
  | "account_restricted"       // Account posting/visibility restricted
  | "account_suspended"        // Account Firebase Auth suspended
  | "account_reinstated"       // Account suspension lifted
  | "report_submitted"         // User reported content
  | "evidence_preserved"       // Evidence copied to secure storage
  | "evidence_provided"        // Evidence provided to law enforcement/NCMEC
  | "guardian_alert_sent"      // Guardian safety alert delivered
  | "youth_safety_violation"   // Youth safety rule triggered
  | "link_blocked"             // Unsafe link blocked
  | "media_quarantined"        // Media moved to quarantine
  | "user_blocked"             // User blocked another user
  | "dm_blocked"               // DM blocked by safety system
  | "dm_freeze_applied";       // DM freeze applied to account

export interface AuditLogEntry {
  logId?: string;
  eventType: AuditEventType;
  actorUid: string;
  targetUid?: string;
  contentId?: string;
  contentType?: string;
  harmCategoryId?: string;
  enforcement?: string;
  moderationStatus?: string;
  resolution?: string;
  source: string;
  policyVersion: string;
  metadata?: Record<string, string | number | boolean | null>;
  createdAt?: admin.firestore.FieldValue;
}

// ─── Core Write ───────────────────────────────────────────────────────────────

/**
 * writeAuditLog
 * Write a single, immutable audit log entry.
 * Used by all Safety OS services.
 */
export async function writeAuditLog(entry: Omit<AuditLogEntry, "logId" | "createdAt" | "policyVersion">): Promise<string> {
  try {
    const ref = db.collection("moderationAuditLog").doc();
    await ref.set({
      ...entry,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return ref.id;
  } catch (err) {
    logger.error("[ModerationAuditLogService] Failed to write audit log.", err);
    return "";
  }
}

/**
 * writeAuditLogBatch
 * Write multiple audit log entries in a single Firestore batch.
 * Use when multiple events occur atomically (e.g. block + strike + preserve evidence).
 */
export async function writeAuditLogBatch(
  entries: Omit<AuditLogEntry, "logId" | "createdAt" | "policyVersion">[]
): Promise<void> {
  if (entries.length === 0) return;
  if (entries.length > 500) {
    logger.warn("[ModerationAuditLogService] Batch exceeds 500 entries; splitting.");
  }

  const BATCH_SIZE = 499;
  for (let i = 0; i < entries.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = entries.slice(i, i + BATCH_SIZE);
    for (const entry of chunk) {
      const ref = db.collection("moderationAuditLog").doc();
      batch.set(ref, {
        ...entry,
        policyVersion: AMEN_SAFETY_POLICY_VERSION,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

// ─── Convenience Helpers ─────────────────────────────────────────────────────

export async function logContentModerated(params: {
  actorUid: string;
  targetUid?: string;
  contentId?: string;
  contentType?: string;
  harmCategoryId?: string;
  enforcement: string;
  moderationStatus: string;
  source: string;
}): Promise<void> {
  const eventType: AuditEventType =
    params.moderationStatus === "blocked" || params.moderationStatus === "escalated"
      ? "content_blocked"
      : params.moderationStatus === "needs_human_review"
        ? "content_escalated"
        : "content_approved_auto";

  await writeAuditLog({ ...params, eventType });
}

export async function logStrikeIssued(params: {
  targetUid: string;
  harmCategoryId: string;
  contentId?: string;
  issuedBy: string;
  newStrikePoints: number;
}): Promise<void> {
  await writeAuditLog({
    eventType: "strike_issued",
    actorUid: params.issuedBy,
    targetUid: params.targetUid,
    contentId: params.contentId,
    harmCategoryId: params.harmCategoryId,
    source: "TrustAndStrikeService",
    metadata: { newStrikePoints: params.newStrikePoints },
  });
}

export async function logAccountEvent(params: {
  eventType: "account_restricted" | "account_suspended" | "account_reinstated";
  targetUid: string;
  actorUid: string;
  reason?: string;
}): Promise<void> {
  await writeAuditLog({
    eventType: params.eventType,
    actorUid: params.actorUid,
    targetUid: params.targetUid,
    source: "AccountSuspension",
    metadata: { reason: params.reason ?? null },
  });
}

export async function logEvidenceEvent(params: {
  eventType: "evidence_preserved" | "evidence_provided";
  actorUid: string;
  targetUid: string;
  contentId?: string;
  harmCategoryId?: string;
  evidenceId?: string;
}): Promise<void> {
  await writeAuditLog({
    eventType: params.eventType,
    actorUid: params.actorUid,
    targetUid: params.targetUid,
    contentId: params.contentId,
    harmCategoryId: params.harmCategoryId,
    source: "EvidencePreservationService",
    metadata: { evidenceId: params.evidenceId ?? null },
  });
}

// ─── Callable: Query Audit Log (Moderator/Admin) ──────────────────────────────

export const queryAuditLog = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{
    targetUid?: string;
    eventType?: AuditEventType;
    contentId?: string;
    startAfterLogId?: string;
    limit?: number;
  }>): Promise<{ entries: unknown[]; hasMore: boolean }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator && !token.trustSafetyReviewer) {
      throw new HttpsError("permission-denied", "Trust & Safety reviewer access required.");
    }

    const { targetUid, eventType, contentId, startAfterLogId, limit: limitCount = 50 } = request.data;
    const safeLimit = Math.min(limitCount, 200);

    let query: admin.firestore.Query = db.collection("moderationAuditLog")
      .orderBy("createdAt", "desc");

    if (targetUid) query = query.where("targetUid", "==", targetUid);
    if (eventType) query = query.where("eventType", "==", eventType);
    if (contentId) query = query.where("contentId", "==", contentId);

    if (startAfterLogId) {
      const cursor = await db.collection("moderationAuditLog").doc(startAfterLogId).get();
      if (cursor.exists) query = query.startAfter(cursor);
    }

    query = query.limit(safeLimit + 1);

    const snap = await query.get();
    const hasMore = snap.size > safeLimit;
    const entries = snap.docs.slice(0, safeLimit).map((d) => ({ logId: d.id, ...d.data() }));

    return { entries, hasMore };
  }
);

/**
 * getAuditSummary
 * Returns aggregate counts for a given time window (moderator dashboard).
 */
export const getAuditSummary = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ windowHours?: number }>): Promise<{
    totalEvents: number;
    blocked: number;
    escalated: number;
    strikesIssued: number;
    accountsSuspended: number;
    evidencePreserved: number;
  }> => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Authentication required.");
    const token = request.auth.token as Record<string, unknown>;
    if (!token.admin && !token.moderator) {
      throw new HttpsError("permission-denied", "Admin or moderator access required.");
    }

    const hours = Math.min(request.data.windowHours ?? 24, 168); // Max 1 week
    const since = admin.firestore.Timestamp.fromMillis(Date.now() - hours * 60 * 60 * 1000);

    const snap = await db.collection("moderationAuditLog")
      .where("createdAt", ">", since)
      .get();

    const counts = {
      totalEvents: snap.size,
      blocked: 0,
      escalated: 0,
      strikesIssued: 0,
      accountsSuspended: 0,
      evidencePreserved: 0,
    };

    snap.forEach((d) => {
      const et: AuditEventType = d.data().eventType;
      if (et === "content_blocked") counts.blocked++;
      if (et === "content_escalated") counts.escalated++;
      if (et === "strike_issued") counts.strikesIssued++;
      if (et === "account_suspended") counts.accountsSuspended++;
      if (et === "evidence_preserved") counts.evidencePreserved++;
    });

    return counts;
  }
);
