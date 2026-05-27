/**
 * safetyAuditLog.ts — Amen Trust + Safety OS
 *
 * Immutable append-only audit log for all safety events.
 * Clients cannot write, update, or delete audit records.
 * Admin-only query surface.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import {
  SafetyAuditEvent,
  SafetyAuditEventType,
  SafetyDecisionOutcome,
  RiskCategory,
  ContentSurface,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const AUDIT_COLLECTION = "platformSafety/audit/events";

// ─── Internal writer (used by all other trustSafety modules) ─────────────

export async function writeSafetyAuditEvent(params: {
  eventType: SafetyAuditEventType;
  actorUid: string | "system";
  targetUid: string | null;
  contentId: string | null;
  contentType: ContentSurface | null;
  decision?: SafetyDecisionOutcome | null;
  category?: RiskCategory | null;
  metadata?: Record<string, unknown>;
}): Promise<string> {
  const eventId = db.collection(AUDIT_COLLECTION).doc().id;
  const event: SafetyAuditEvent = {
    eventId,
    eventType: params.eventType,
    actorUid: params.actorUid,
    targetUid: params.targetUid,
    contentId: params.contentId,
    contentType: params.contentType,
    decision: params.decision ?? null,
    category: params.category ?? null,
    metadata: params.metadata ?? {},
    createdAt: admin.firestore.Timestamp.now(),
    policyVersion: TRUST_SAFETY_OS_VERSION,
  };

  await db.doc(`${AUDIT_COLLECTION}/${eventId}`).set(event);
  return eventId;
}

// ─── Admin query callable ─────────────────────────────────────────────────

export const queryAuditLog = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    const claims = request.auth.token;
    if (!claims.admin && !claims.moderator && !claims.trustSafetyReviewer) {
      throw new HttpsError("permission-denied", "Reviewer role required.");
    }

    const { eventType, actorUid, contentId, limit = 50 } = request.data as {
      eventType?: SafetyAuditEventType;
      actorUid?: string;
      contentId?: string;
      limit?: number;
    };

    let query: FirebaseFirestore.Query = db.collection(AUDIT_COLLECTION)
      .orderBy("createdAt", "desc")
      .limit(Math.min(limit, 200));

    if (eventType) query = query.where("eventType", "==", eventType);
    if (actorUid) query = query.where("actorUid", "==", actorUid);
    if (contentId) query = query.where("contentId", "==", contentId);

    const snap = await query.get();
    return snap.docs.map((d) => d.data() as SafetyAuditEvent);
  }
);
