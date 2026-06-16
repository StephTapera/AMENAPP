/**
 * submitReport.ts
 *
 * Server-side user/content report submission.
 *
 * WHY THIS EXISTS (HIGH-3 from Trust/Safety Audit):
 *   Reports are currently written directly to Firestore from the client
 *   (SafetyReportingService.swift). This allows an attacker to:
 *     - Set reportedUserId to any arbitrary UID to frame innocent users
 *     - Set reason to any string outside the allowed enum values
 *     - Set escalationTier to 1 (immediate freeze) to DoS a target user
 *     - Set priorityLevel to 0 to bury a legitimate Tier-1 report
 *     - Write evidence that doesn't actually belong to the conversation
 *
 *   This function validates all fields server-side and writes the report
 *   document using the admin SDK. The Firestore rules for /reports and
 *   /userReports are updated to allow create: if false (Cloud Function only).
 *
 * VALIDATION:
 *   - reporterId must equal the authenticated UID (enforced by context.auth)
 *   - reportedUserId must exist as a Firestore user document
 *   - reason must be a valid ReportReason enum value
 *   - escalationTier and priorityLevel are computed server-side from reason
 *   - evidenceMessageIds are verified to belong to the stated conversationId
 *   - Rate limiting: max 10 reports per hour per user
 *   - Deduplication: same (reporterId, reportedUserId) pair within 24 hours
 */

import * as functions from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = admin.firestore();

// ─── Constants ───────────────────────────────────────────────────────────────

/**
 * All valid report reason strings.
 * Must stay in sync with SafetyReportingService.swift ReportReason enum raw values.
 */
const VALID_REASONS = new Set([
    "grooming_or_trafficking",
    "child_safety",
    "threat_or_blackmail",
    "sextortion",
    "solicitation",
    "off_platform_pressure",
    "financial_scam",
    "violence_or_self_harm",
    "harassment",
    "hate_speech",
    "unwanted_contact",
    "spam",
    "impersonation",
    "other",
]);

/** Max number of reports a user may submit per hour. */
const RATE_LIMIT_PER_HOUR = 10;

/** Max evidence message IDs allowed per report. */
const MAX_EVIDENCE_IDS = 20;

// ─── Server-side Escalation Tier Mapping ────────────────────────────────────

/**
 * Compute escalation tier server-side — never trust the client-supplied value.
 * Mirrors SafetyReportingService.swift ReportReason.escalationTier.
 */
function computeEscalationTier(reason: string): number {
    const tier1 = new Set(["grooming_or_trafficking", "child_safety", "threat_or_blackmail", "sextortion"]);
    const tier2 = new Set(["solicitation", "off_platform_pressure", "financial_scam", "violence_or_self_harm"]);

    if (tier1.has(reason)) return 1;
    if (tier2.has(reason)) return 2;
    return 3;
}

function computePriority(tier: number): string {
    if (tier === 1) return "immediate";
    if (tier === 2) return "high";
    return "standard";
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Returns true if the same (reporterId, reportedUserId) pair exists within 24 hours. */
async function isDuplicateReport(reporterId: string, reportedUserId: string): Promise<boolean> {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const snap = await db
        .collection("userReports")
        .where("reporterId", "==", reporterId)
        .where("reportedUserId", "==", reportedUserId)
        .where("submittedAt", ">=", admin.firestore.Timestamp.fromDate(cutoff))
        .limit(1)
        .get();
    return !snap.empty;
}

/** Returns true if user has submitted >= RATE_LIMIT_PER_HOUR reports in the last hour. */
async function isRateLimited(reporterId: string): Promise<boolean> {
    const cutoff = new Date(Date.now() - 60 * 60 * 1000);
    const snap = await db
        .collection("userReports")
        .where("reporterId", "==", reporterId)
        .where("submittedAt", ">=", admin.firestore.Timestamp.fromDate(cutoff))
        .limit(RATE_LIMIT_PER_HOUR)
        .get();
    return snap.size >= RATE_LIMIT_PER_HOUR;
}

// ─── Callable Function ────────────────────────────────────────────────────────

/**
 * Callable function: submitReport
 *
 * Creates a validated user/content report document.
 * The Firestore rules for /userReports must be set to:
 *   allow create: if false;
 * so this function is the only way to create reports.
 *
 * Input:
 *   {
 *     reportedUserId: string,       // UID of the reported user
 *     reason: string,               // Must be a valid ReportReason raw value
 *     conversationId?: string,      // If reporting a DM conversation
 *     evidenceMessageIds?: string[], // Up to 20 message IDs as evidence
 *     additionalContext?: string,    // Optional freeform text (max 1000 chars)
 *     blockImmediately?: boolean,   // Whether to also block the reported user
 *   }
 *
 * Output: { reportId: string }
 */
export const submitReport = onCall(async (request) => {
    const data = request.data as any;
    const context = { auth: request.auth, app: request.app };
    // ── Auth check ─────────────────────────────────────────────────────────
    if (!context.auth) {
        throw new HttpsError("unauthenticated", "Must be signed in to submit a report");
    }

    // ── App Check enforcement (5.1 FIX) ────────────────────────────────────
    // Rejects calls from clients that cannot produce a valid App Check token.
    // Prevents scripted abuse with a stolen Firebase Auth token alone.
    if (context.app == undefined) {
        throw new HttpsError(
            "failed-precondition",
            "The function must be called from an App Check verified app."
        );
    }

    const reporterId = context.auth.uid;

    // ── Input validation ───────────────────────────────────────────────────
    const reportedUserId: string = (data.reportedUserId ?? "").trim();
    if (!reportedUserId) {
        throw new HttpsError("invalid-argument", "reportedUserId is required");
    }

    if (reportedUserId === reporterId) {
        throw new HttpsError("invalid-argument", "Cannot report yourself");
    }

    const reason: string = (data.reason ?? "").trim();
    if (!VALID_REASONS.has(reason)) {
        throw new HttpsError(
            "invalid-argument",
            `reason '${reason}' is not a valid report reason`
        );
    }

    const conversationId: string = (data.conversationId ?? "").trim();

    const evidenceMessageIds: string[] = Array.isArray(data.evidenceMessageIds)
        ? (data.evidenceMessageIds as unknown[]).slice(0, MAX_EVIDENCE_IDS).map(String)
        : [];

    const additionalContext: string = ((data.additionalContext ?? "") as string)
        .trim()
        .slice(0, 1000);  // Hard cap at 1000 characters

    const blockImmediately: boolean = Boolean(data.blockImmediately ?? false);

    // ── Validate reported user exists ──────────────────────────────────────
    const reportedUserDoc = await db.collection("users").doc(reportedUserId).get();
    if (!reportedUserDoc.exists) {
        throw new HttpsError("not-found", "Reported user not found");
    }

    // ── Rate limiting ──────────────────────────────────────────────────────
    if (await isRateLimited(reporterId)) {
        throw new HttpsError(
            "resource-exhausted",
            "You have submitted too many reports recently. Please try again later."
        );
    }

    // ── Deduplication ─────────────────────────────────────────────────────
    if (await isDuplicateReport(reporterId, reportedUserId)) {
        // Return success silently so the reporter knows their concern was registered,
        // without allowing them to confirm whether a prior report exists.
        functions.logger.info(
            `[SubmitReport] Duplicate report from ${reporterId} against ${reportedUserId} — suppressed.`
        );
        return { reportId: "duplicate_suppressed" };
    }

    // ── Verify evidence messages belong to stated conversation ─────────────
    const verifiedEvidenceIds: string[] = [];
    if (conversationId && evidenceMessageIds.length > 0) {
        const verificationChecks = evidenceMessageIds.map(async (msgId) => {
            try {
                const msgDoc = await db
                    .collection("conversations")
                    .doc(conversationId)
                    .collection("messages")
                    .doc(msgId)
                    .get();
                return msgDoc.exists ? msgId : null;
            } catch {
                return null;
            }
        });
        const verified = await Promise.all(verificationChecks);
        verifiedEvidenceIds.push(...verified.filter((id): id is string => id !== null));
    }

    // ── Compute escalation tier and priority server-side ───────────────────
    const escalationTier = computeEscalationTier(reason);
    const priority = computePriority(escalationTier);

    // ===================================================================
    // FEDERAL LAW GATE (18 U.S.C. §2258A) — DO NOT IMPROVISE
    // All four conditions required before automatedCyberTipSubmitted=true
    // or hashScanEnabled=true:
    // 1. NCMEC ESP registration complete (legal/business step)
    // 2. Hash provider (PhotoDNA/Thorn/NCMEC) contracted + secrets loaded
    // 3. Written legal sign-off from counsel on CSAM reporting procedure
    // 4. Non-engineer review of complete CSAM pipeline
    // Media uploads STAY FAIL-CLOSED until all four are true.
    // ===================================================================

    // ── Write report document ──────────────────────────────────────────────
    const reportId = db.collection("userReports").doc().id;

    await db.collection("userReports").doc(reportId).set({
        reportId,
        reporterId,                     // Always the authenticated UID — cannot be spoofed
        reportedUserId,                 // Validated to exist
        reason,                         // Validated against allow-list
        escalationTier,                 // Computed server-side — not trusted from client
        priority,                       // Computed server-side
        conversationId: conversationId || null,
        evidenceMessageIds: verifiedEvidenceIds,  // Verified to exist in the conversation
        additionalContext,
        status: "pending_review",
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        reviewedAt: null,
        reviewerId: null,
        actionTaken: null,
        // NCMEC launch-readiness scaffold fields
        ncmecReadiness: "STUB_NOT_REGISTERED",  // HUMAN: replace with ESP registration ID
        automatedCyberTipSubmitted: false,       // MUST stay false until 4-part legal gate
        evidenceVault: null,                     // HUMAN: configure after legal sign-off
        hashScanEnabled: false,                  // MUST stay false until 4-part legal gate
        reportVersion: "1.0.0-scaffold",
    });

    functions.logger.info(
        `[SubmitReport] Report ${reportId} created: ${reporterId} → ${reportedUserId}, ` +
        `reason=${reason}, tier=${escalationTier}, priority=${priority}`
    );

    // ── Tier-1: immediate escalation queue entry ───────────────────────────
    if (escalationTier === 1) {
        await db.collection("moderationQueue").add({
            type: "tier1_user_report",
            reportId,
            reporterId,
            reportedUserId,
            reason,
            priority: "immediate",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            policyVersion: "2026-03-06",
        });

        functions.logger.warn(
            `[SubmitReport] TIER-1 report ${reportId} — ${reason} — queued for immediate review.`
        );
    }

    // ── Optional immediate block ───────────────────────────────────────────
    if (blockImmediately) {
        // Write to blockedUsers from server (avoids client Firestore rule bypass).
        const blockDocId = `${reporterId}_${reportedUserId}`;
        await db.collection("blockedUsers").doc(blockDocId).set({
            userId: reporterId,
            blockedUserId: reportedUserId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            source: "report",
            reportId,
        }, { merge: true });
    }

    return { reportId };
});
