/**
 * reportAbuse.ts — Amen Trust + Safety OS
 *
 * Callable: submitAbuseReport
 * Callable: getMyAbuseReports
 * Callable: resolveAbuseReport (moderator)
 * Callable: escalateAbuseReport (moderator)
 *
 * On report submission:
 *   - Creates immutable report record
 *   - Quarantines content if severe category
 *   - Escalates high-risk categories immediately
 *   - Preserves evidence server-side
 *   - Creates audit log entry
 *
 * Categories that auto-quarantine:
 *   minor_safety, grooming, trafficking, violence, sexual_content
 *
 * Categories that auto-escalate:
 *   minor_safety, grooming, trafficking
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import {
  AbuseReport,
  ReportCategory,
  ReportSeverity,
  ReportStatus,
  ContentSurface,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";
import { writeSafetyAuditEvent } from "./safetyAuditLog";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Auto-quarantine + escalation rules ──────────────────────────────────

const AUTO_QUARANTINE_CATEGORIES: ReportCategory[] = [
  "minor_safety", "grooming", "trafficking", "violence", "sexual_content", "self_harm_concern",
];

const AUTO_ESCALATE_CATEGORIES: ReportCategory[] = [
  "minor_safety", "grooming", "trafficking",
];

const CATEGORY_SEVERITY: Record<ReportCategory, ReportSeverity> = {
  minor_safety:           "critical",
  grooming:               "critical",
  trafficking:            "critical",
  sexual_content:         "high",
  violence:               "high",
  self_harm_concern:      "high",
  harassment:             "medium",
  hate_extremism:         "high",
  impersonation:          "medium",
  scam:                   "medium",
  fake_ai_media:          "medium",
  misinformation:         "medium",
  privacy_violation:      "medium",
  fake_church_profile:    "medium",
  fake_review_testimonial:"low",
  bot_activity:           "low",
};

// ─── Types ───────────────────────────────────────────────────────────────

export interface SubmitReportRequest {
  targetUid?: string;
  contentId?: string;
  contentType?: ContentSurface;
  category: ReportCategory;
  details?: string;
}

export interface SubmitReportResponse {
  reportId: string;
  status: ReportStatus;
  contentQuarantined: boolean;
  escalated: boolean;
  policyVersion: string;
}

// ─── Submit report callable ───────────────────────────────────────────────

export const submitAbuseReport = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<SubmitReportResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const data = request.data as SubmitReportRequest;
    if (!data.category) throw new HttpsError("invalid-argument", "category required.");

    const reporterUid = request.auth.uid;
    const reportId = db.collection("platformSafety/queues/moderation").doc().id;

    const severity = CATEGORY_SEVERITY[data.category] ?? "medium";
    const autoQuarantine = AUTO_QUARANTINE_CATEGORIES.includes(data.category);
    const autoEscalate = AUTO_ESCALATE_CATEGORIES.includes(data.category);

    let contentQuarantined = false;

    // Quarantine reported content
    if (autoQuarantine && data.contentId && data.contentType) {
      const collection = data.contentType === "post" ? "posts"
        : data.contentType === "comment" ? "comments"
        : data.contentType === "dm" ? "messages"
        : null;

      if (collection) {
        await db.doc(`${collection}/${data.contentId}/safety/main`).set(
          {
            moderationStatus: "needs_human_review",
            quarantinedAt: admin.firestore.Timestamp.now(),
            quarantineReason: `reported:${data.category}`,
            policyVersion: TRUST_SAFETY_OS_VERSION,
          },
          { merge: true }
        );
        contentQuarantined = true;
      }
    }

    const report: AbuseReport = {
      reportId,
      reporterUid,
      targetUid: data.targetUid ?? null,
      contentId: data.contentId ?? null,
      contentType: data.contentType ?? null,
      category: data.category,
      severity,
      status: autoEscalate ? "escalated" : "submitted",
      details: data.details ?? null,
      evidencePreserved: severity === "critical" || severity === "high",
      contentQuarantined,
      escalated: autoEscalate,
      resolvedAt: null,
      createdAt: admin.firestore.Timestamp.now(),
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };

    // Write to platform moderation queue
    await db.doc(`platformSafety/queues/moderation/${reportId}`).set(report);

    // Write to per-content report subcollection
    if (data.contentId && data.contentType) {
      const collection = data.contentType === "post" ? "posts" : "comments";
      await db.doc(`${collection}/${data.contentId}/reports/${reportId}`).set({
        reportId,
        reporterUid,
        category: data.category,
        severity,
        createdAt: admin.firestore.Timestamp.now(),
      });
    }

    // Write to escalation queue if needed
    if (autoEscalate) {
      await db.doc(`platformSafety/queues/escalation/${reportId}`).set({
        ...report,
        escalatedAt: admin.firestore.Timestamp.now(),
      });
    }

    // Preserve evidence for high-severity reports
    if (report.evidencePreserved && data.contentId) {
      await db.doc(`platformSafety/audit/events/${reportId}_evidence`).set({
        type: "evidence_preserved",
        reportId,
        contentId: data.contentId,
        contentType: data.contentType,
        reporterUid,
        category: data.category,
        preservedAt: admin.firestore.Timestamp.now(),
        policyVersion: TRUST_SAFETY_OS_VERSION,
      });
    }

    await writeSafetyAuditEvent({
      eventType: "report_submitted",
      actorUid: reporterUid,
      targetUid: data.targetUid ?? null,
      contentId: data.contentId ?? null,
      contentType: data.contentType ?? null,
      category: data.category as never,
      metadata: { severity, autoQuarantine, autoEscalate, reportId },
    });

    return {
      reportId,
      status: report.status,
      contentQuarantined,
      escalated: autoEscalate,
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);

// ─── Get my reports ───────────────────────────────────────────────────────

export const getMyAbuseReports = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const uid = request.auth.uid;
    const snap = await db
      .collection("platformSafety/queues/moderation")
      .where("reporterUid", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();

    return snap.docs.map((d) => {
      const data = d.data() as AbuseReport;
      // Don't return internal fields to reporter
      const { reviewerReason: _, ...safe } = data as any;
      return safe;
    });
  }
);

// ─── Resolve report (moderator) ───────────────────────────────────────────

export const resolveAbuseReport = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.auth.token.admin && !request.auth.token.moderator) {
      throw new HttpsError("permission-denied", "Moderator role required.");
    }

    const { reportId, actioned, reviewerNotes } = request.data as {
      reportId: string;
      actioned: boolean;
      reviewerNotes?: string;
    };
    if (!reportId) throw new HttpsError("invalid-argument", "reportId required.");

    const status: ReportStatus = actioned ? "resolved_actioned" : "resolved_no_action";
    await db.doc(`platformSafety/queues/moderation/${reportId}`).update({
      status,
      resolvedAt: admin.firestore.Timestamp.now(),
      resolvedBy: request.auth.uid,
      reviewerNotes: reviewerNotes ?? null,
    });

    await writeSafetyAuditEvent({
      eventType: "report_resolved",
      actorUid: request.auth.uid,
      targetUid: null,
      contentId: reportId,
      contentType: null,
      metadata: { actioned, status },
    });

    return { success: true, status };
  }
);

// ─── Escalate report (moderator) ─────────────────────────────────────────

export const escalateAbuseReport = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.auth.token.admin && !request.auth.token.moderator) {
      throw new HttpsError("permission-denied", "Moderator role required.");
    }

    const { reportId, escalationTarget, reason } = request.data as {
      reportId: string;
      escalationTarget: string;
      reason?: string;
    };

    await db.doc(`platformSafety/queues/moderation/${reportId}`).update({
      status: "escalated",
      escalatedAt: admin.firestore.Timestamp.now(),
      escalatedBy: request.auth.uid,
      escalationTarget,
      escalationReason: reason ?? null,
    });

    await db.doc(`platformSafety/queues/escalation/${reportId}`).set(
      {
        reportId,
        escalatedAt: admin.firestore.Timestamp.now(),
        escalationTarget,
        reason: reason ?? null,
      },
      { merge: true }
    );

    await writeSafetyAuditEvent({
      eventType: "report_escalated",
      actorUid: request.auth.uid,
      targetUid: null,
      contentId: reportId,
      contentType: null,
      metadata: { escalationTarget, reason },
    });

    return { success: true };
  }
);
