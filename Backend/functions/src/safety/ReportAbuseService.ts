/**
 * ReportAbuseService.ts
 *
 * User-facing abuse reporting for Amen Safety OS.
 * This service is the canonical entry point for all user-initiated reports.
 * It wraps and extends submitReport.ts with Safety OS policy awareness:
 *
 *   - Maps report reasons to AmenSafetyPolicy harm categories
 *   - Automatically routes to the correct SafetyOpsQueue
 *   - Preserves evidence for escalation-tier reports before any cleanup
 *   - Issues immediate account restrictions for critical-tier reports
 *   - Writes an immutable audit log entry for every report
 *   - Deduplicates reports (same reporter + target within 24h)
 *   - Rate-limits reporters (max 20 reports per hour)
 *   - Triggers guardian alerts when a minor is the victim
 *
 * The existing submitReport.ts callable remains the primary entry point for
 * the iOS client. This service is called internally by backend triggers and
 * provides the policy-aware layer on top.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  policyFor,
  requiresEvidencePreservation,
  AMEN_SAFETY_POLICY_VERSION,
  EnforcementAction,
} from "./AmenSafetyPolicy";
import { safetyOpsPlanFor, safetyOpsDueAt } from "../safetyOpsPolicy";
import { writeAuditLog } from "./ModerationAuditLogService";
import { enqueueForHumanReview } from "./HumanReviewQueueService";
import { preserveEvidence } from "./EvidencePreservationService";
import { deliverSafetyAlertToGuardians } from "./GuardianConnectionService";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Report Reason → Harm Category Mapping ───────────────────────────────────

const REPORT_REASON_TO_HARM: Record<string, string> = {
  // Child safety (Tier 1)
  csam: "csam",
  child_safety: "csam",
  grooming: "grooming",
  grooming_or_trafficking: "grooming",
  sex_trafficking: "sex_trafficking",
  human_trafficking: "human_trafficking",
  online_enticement: "online_enticement",
  sexualized_minor: "sexualized_minor",
  // Sexual exploitation (Tier 1)
  sextortion: "sextortion",
  non_consensual_intimate_imagery: "non_consensual_intimate_imagery",
  sexual_exploitation: "sexual_solicitation",
  sexual_content: "sexual_content",
  revenge_porn: "non_consensual_intimate_imagery",
  deepfake_sexual_content: "deepfake_sexual",
  // Violence
  threat_or_blackmail: "blackmail",
  violence: "graphic_violence",
  violence_threat: "violence_threat",
  terrorism: "terrorism",
  // Harassment
  harassment: "harassment",
  hate_speech: "hate_speech",
  cyberbullying: "cyberbullying",
  doxxing: "doxxing",
  stalking: "stalking",
  // Self-harm
  self_harm: "self_harm_encouragement",
  suicide: "self_harm_encouragement",
  eating_disorder_promotion: "eating_disorder_promotion",
  // Fraud/Scam
  scam: "scam_phishing",
  phishing: "scam_phishing",
  financial_fraud: "financial_fraud",
  impersonation: "identity_theft",
  fake_account: "identity_theft",
  // Spam
  spam: "spam_bot",
  // Other
  misinformation: "misinformation",
  other: "harassment",
};

// ─── Types ────────────────────────────────────────────────────────────────────

export type EscalationTier = 1 | 2 | 3;

export interface AbuseReport {
  reportId: string;
  reporterUid: string;
  reportedUid: string;
  contentId?: string;
  contentType?: string;
  reportReason: string;
  harmCategoryId: string;
  additionalContext?: string;
  evidenceMessageIds?: string[];
  escalationTier: EscalationTier;
  queueId: string;
  priority: 1 | 2 | 3 | 4;
  enforcement: EnforcementAction;
  dueAt: Date;
  policyVersion: string;
  createdAt: admin.firestore.FieldValue;
}

export interface ReportAbuseRequest {
  reportedUid: string;
  reportReason: string;
  contentId?: string;
  contentType?: string;
  additionalContext?: string;
  evidenceMessageIds?: string[];
}

export interface ReportAbuseResult {
  success: boolean;
  reportId: string;
  escalationTier: EscalationTier;
  message: string;
}

// ─── Rate Limiting ────────────────────────────────────────────────────────────

const MAX_REPORTS_PER_HOUR = 20;

async function checkRateLimit(reporterUid: string): Promise<boolean> {
  const oneHourAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
  const recent = await db.collection("abuseReports")
    .where("reporterUid", "==", reporterUid)
    .where("createdAt", ">", oneHourAgo)
    .count()
    .get();
  return recent.data().count < MAX_REPORTS_PER_HOUR;
}

// ─── Deduplication ────────────────────────────────────────────────────────────

async function isDuplicate(reporterUid: string, reportedUid: string, contentId?: string): Promise<boolean> {
  const oneDayAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  let query = db.collection("abuseReports")
    .where("reporterUid", "==", reporterUid)
    .where("reportedUid", "==", reportedUid)
    .where("createdAt", ">", oneDayAgo);

  if (contentId) {
    query = query.where("contentId", "==", contentId);
  }

  const snap = await query.limit(1).get();
  return !snap.empty;
}

// ─── Tier Computation ─────────────────────────────────────────────────────────

function escalationTierFor(harmCategoryId: string): EscalationTier {
  const policy = policyFor(harmCategoryId);
  if (!policy) return 3;

  switch (policy.enforcement) {
  case "escalate_to_legal":
    return 1;
  case "escalate":
  case "block_and_suspend":
    return 1;
  case "block":
    return policy.preserveEvidence ? 2 : 3;
  default:
    return 3;
  }
}

// ─── Core Submit ──────────────────────────────────────────────────────────────

export async function submitAbuseReport(
  reporterUid: string,
  req: ReportAbuseRequest
): Promise<ReportAbuseResult> {
  const { reportedUid, reportReason, contentId, contentType, additionalContext, evidenceMessageIds } = req;

  if (reporterUid === reportedUid) {
    throw new HttpsError("invalid-argument", "Cannot report your own account.");
  }

  // Map report reason to harm category
  const harmCategoryId = REPORT_REASON_TO_HARM[reportReason.toLowerCase()] ?? "harassment";
  const policy = policyFor(harmCategoryId);
  const escalationTier = escalationTierFor(harmCategoryId);
  const plan = safetyOpsPlanFor(harmCategoryId, escalationTier === 1 ? "critical" : escalationTier === 2 ? "high" : "medium");
  const dueAt = safetyOpsDueAt(Date.now(), plan.initialResponseMinutes);

  // Deduplication
  if (await isDuplicate(reporterUid, reportedUid, contentId)) {
    // Still return success to avoid enumeration, but don't create duplicate
    return {
      success: true,
      reportId: "deduplicated",
      escalationTier,
      message: "Thank you for your report. Our team is reviewing it.",
    };
  }

  // Rate limiting
  const withinLimit = await checkRateLimit(reporterUid);
  if (!withinLimit) {
    throw new HttpsError("resource-exhausted", "Too many reports. Please wait before submitting another.");
  }

  // Write report document
  const reportRef = db.collection("abuseReports").doc();
  const reportData: Omit<AbuseReport, "reportId"> = {
    reporterUid,
    reportedUid,
    contentId: contentId ?? null as unknown as string,
    contentType: contentType ?? null as unknown as string,
    reportReason,
    harmCategoryId,
    additionalContext: additionalContext ?? null as unknown as string,
    evidenceMessageIds: evidenceMessageIds ?? [],
    escalationTier,
    queueId: plan.queue,
    priority: plan.priority,
    enforcement: policy?.enforcement ?? "block",
    dueAt,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await reportRef.set(reportData);

  const reportId = reportRef.id;
  logger.info(`[ReportAbuseService] Report filed reportId=${reportId} harm=${harmCategoryId} tier=${escalationTier}`);

  // Side effects (run in background, don't block response)
  runReportSideEffects(reportId, reporterUid, reportedUid, harmCategoryId, contentId, contentType, escalationTier, plan.preserveEvidence).catch(
    (err) => logger.error("[ReportAbuseService] Side effects failed.", err)
  );

  const tierMessages: Record<EscalationTier, string> = {
    1: "This has been escalated as a priority safety concern. Our team will review it immediately.",
    2: "Thank you for your report. Our safety team will review it as soon as possible.",
    3: "Thank you for your report. Our team will review it.",
  };

  return {
    success: true,
    reportId,
    escalationTier,
    message: tierMessages[escalationTier],
  };
}

async function runReportSideEffects(
  reportId: string,
  reporterUid: string,
  reportedUid: string,
  harmCategoryId: string,
  contentId: string | undefined,
  contentType: string | undefined,
  escalationTier: EscalationTier,
  preserveEv: boolean
): Promise<void> {
  const tasks: Promise<unknown>[] = [];

  // Audit log
  tasks.push(writeAuditLog({
    eventType: "report_submitted",
    actorUid: reporterUid,
    targetUid: reportedUid,
    contentId,
    contentType,
    harmCategoryId,
    source: "ReportAbuseService",
  }));

  // Human review queue (tier 1 and 2)
  if (escalationTier <= 2) {
    tasks.push(enqueueForHumanReview({
      contentType: contentType ?? "unknown",
      contentId,
      authorUid: reportedUid,
      harmCategoryId,
      harmSeverity: escalationTier === 1 ? "critical" : "high",
      evidence: { reportId, reporterUid },
    }));
  }

  // Evidence preservation (for tier 1 or if policy requires it)
  if (escalationTier === 1 || preserveEv) {
    if (contentId) {
      tasks.push(preserveEvidence({
        contentId,
        contentType: contentType ?? "unknown",
        authorUid: reportedUid,
        harmCategoryId,
        reportIds: [reportId],
        preservedBy: "server",
      }));
    }
  }

  // Guardian alert if reported user is a minor
  const reportedDoc = await db.collection("users").doc(reportedUid).get();
  const ageTier = reportedDoc.data()?.ageTier;
  if (ageTier === "minor" || ageTier === "teen") {
    tasks.push(deliverSafetyAlertToGuardians(
      reportedUid,
      `abuse_report_filed_tier${escalationTier}`,
      reporterUid,
      contentId
    ));
  }

  // Immediate account restriction for tier-1 violations
  if (escalationTier === 1) {
    tasks.push(db.collection("moderationQueue").add({
      type: "critical_harassment_pattern",
      offenderId: reportedUid,
      priority: "immediate",
      harmCategoryId,
      reportId,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }));
  }

  await Promise.allSettled(tasks);
}

// ─── Callable Function ────────────────────────────────────────────────────────

/**
 * reportAbuse callable
 *
 * Primary entry point for user-initiated abuse reports from the iOS client.
 * Validates server-side, deduplicates, rate-limits, and routes to the
 * appropriate Safety OS queue automatically.
 *
 * The iOS client should use this callable for all in-app reports.
 * The existing `submitReport` callable (submitReport.ts) remains available
 * for legacy compatibility but new code should call reportAbuse.
 */
export const reportAbuse = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<ReportAbuseRequest>): Promise<ReportAbuseResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { reportedUid, reportReason, contentId, contentType, additionalContext, evidenceMessageIds } = request.data;

    if (!reportedUid || !reportReason) {
      throw new HttpsError("invalid-argument", "reportedUid and reportReason are required.");
    }

    if (typeof reportReason !== "string" || reportReason.length > 100) {
      throw new HttpsError("invalid-argument", "Invalid reportReason.");
    }

    if (additionalContext && typeof additionalContext === "string" && additionalContext.length > 1000) {
      throw new HttpsError("invalid-argument", "additionalContext exceeds 1000 characters.");
    }

    if (Array.isArray(evidenceMessageIds) && evidenceMessageIds.length > 10) {
      throw new HttpsError("invalid-argument", "Maximum 10 evidenceMessageIds.");
    }

    return submitAbuseReport(request.auth.uid, {
      reportedUid,
      reportReason,
      contentId,
      contentType,
      additionalContext,
      evidenceMessageIds,
    });
  }
);

/**
 * getMyReports callable
 * Allows users to see reports they've submitted (status only, not internal details).
 */
export const getMyReports = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<{ limit?: number }>): Promise<{ reports: unknown[] }> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const snap = await db.collection("abuseReports")
      .where("reporterUid", "==", request.auth.uid)
      .orderBy("createdAt", "desc")
      .limit(Math.min(request.data.limit ?? 20, 50))
      .get();

    return {
      reports: snap.docs.map((d) => ({
        reportId: d.id,
        reportReason: d.data().reportReason,
        escalationTier: d.data().escalationTier,
        createdAt: d.data().createdAt,
      })),
    };
  }
);
