/**
 * antiImpersonation.ts
 *
 * AMEN Catalog — Anti-Impersonation Engine
 *
 * Detects and routes impersonation reports without taking automated enforcement action.
 *
 * ABSOLUTE RULES:
 *   - Never auto-take action on impersonation reports — always route to human admin.
 *   - Never auto-suspend an account based on automated detection.
 *   - Public figure name matching = detection flag only, not enforcement.
 *   - handleImpersonationReport: 'remove_badge' and 'suspend' are admin actions only.
 *
 * Exports (callable):
 *   reportImpersonation — any signed-in user can file a report
 *   handleImpersonationReportClaim — admin-only enforcement action
 *
 * Region: us-east1 (us-central1 quota exhausted ~1007/1000 as of 2026-06-13).
 * Register in docs/FUNCTION_INVENTORY.md before deploying.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { Timestamp } from "firebase-admin/firestore";

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export type ImpersonationReportStatus =
    | "pending_review"
    | "under_review"
    | "dismissed"
    | "badge_removed"
    | "account_suspended";

export type ImpersonationReportAction =
    | "remove_badge"
    | "suspend"
    | "dismiss";

export interface ImpersonationFlag {
    profileId: string;
    targetId: string;
    similarity: number;            // 0.0–1.0
    flagReason: string;
    autoDetected: boolean;
    createdAt: Timestamp;
}

export interface ImpersonationReport {
    reportId: string;
    reporterId: string;
    suspectedProfileId: string;
    targetId: string;               // the profile being impersonated
    evidence: Record<string, unknown>;
    status: ImpersonationReportStatus;
    adminId?: string;
    adminNote?: string;
    actionTaken?: ImpersonationReportAction;
    createdAt: Timestamp;
    updatedAt: Timestamp;
}

// ─── Known public-figure name patterns ───────────────────────────────────────
//
// These are broad patterns that flag common impersonation targets.
// Detection = routing for human review, NOT enforcement.
// This list is intentionally conservative — false positives are bad.
// Only add patterns where impersonation risk is high and names are distinctive.

const PUBLIC_FIGURE_PATTERNS: RegExp[] = [
    // Major Christian leaders / public figures (first+last together, not common names)
    /\bjoel\s+osteen\b/i,
    /\bbeth\s+moore\b/i,
    /\btd\s+jakes\b/i,
    /\bcraig\s+groeschel\b/i,
    /\brick\s+warren\b/i,
    /\bjohn\s+piper\b/i,
    /\btim\s+keller\b/i,
    /\bbilly\s+graham\b/i,
    /\bfrancis\s+chan\b/i,
    /\bnick\s+vujicic\b/i,
    /\blouie\s+giglio\b/i,
    /\bpriscilla\s+shirer\b/i,
    /\bsteven\s+furtick\b/i,
    /\bmark\s+driscoll\b/i,
    /\bdavid\s+platt\b/i,
    /\bjim\s+daly\b/i,
    // Major ministry org handles (verbatim match)
    /^(billygrahamorg|focusonthefamily|lifeway|churchofgod)$/i,
];

/**
 * Check if a display name or handle matches a known public figure pattern.
 * Returns a list of matched pattern descriptions for logging.
 */
function matchesPublicFigurePattern(name: string): string[] {
    const matches: string[] = [];
    for (const pattern of PUBLIC_FIGURE_PATTERNS) {
        if (pattern.test(name)) {
            matches.push(pattern.source);
        }
    }
    return matches;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request: CallableRequest): string {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return request.auth.uid;
}

function requireAdmin(request: CallableRequest): string {
    const uid = requireAuth(request);
    const isAdmin = (request.auth?.token as Record<string, unknown>)?.admin === true;
    if (!isAdmin) {
        throw new HttpsError("permission-denied", "Admin access required.");
    }
    return uid;
}

/**
 * Compute a name similarity score between two display names.
 * Uses a simple normalized Levenshtein edit distance.
 * Returns 0.0 (completely different) to 1.0 (identical).
 *
 * This is intentionally a lightweight heuristic — not a semantic embedding.
 * It catches obvious copy-paste impersonation (e.g. "Joel Osteen" → "J0el 0steen")
 * but will miss sophisticated attempts. Human review is always required.
 */
function nameSimilarity(a: string, b: string): number {
    const normalize = (s: string) =>
        s
            .toLowerCase()
            .replace(/[^a-z0-9]/g, "") // strip symbols
            .replace(/0/g, "o")         // normalize leet substitutions
            .replace(/1/g, "i")
            .replace(/3/g, "e")
            .replace(/4/g, "a")
            .replace(/5/g, "s");

    const na = normalize(a);
    const nb = normalize(b);

    if (na === nb) return 1.0;
    if (na.length === 0 || nb.length === 0) return 0.0;

    // Levenshtein distance
    const m = na.length;
    const n = nb.length;
    const dp: number[][] = Array.from({ length: m + 1 }, (_, i) =>
        Array.from({ length: n + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0))
    );

    for (let i = 1; i <= m; i++) {
        for (let j = 1; j <= n; j++) {
            if (na[i - 1] === nb[j - 1]) {
                dp[i][j] = dp[i - 1][j - 1];
            } else {
                dp[i][j] = 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
            }
        }
    }

    const distance = dp[m][n];
    const maxLen = Math.max(m, n);
    return 1.0 - distance / maxLen;
}

// ─── Core engine functions (internal) ────────────────────────────────────────

/**
 * Compare two profiles for impersonation risk.
 * Returns a flag object if similarity exceeds the threshold, or null otherwise.
 *
 * Threshold = 0.85 (very high — only near-identical names flagged automatically).
 * Flags are INFORMATIONAL only. No action is taken automatically.
 */
export async function detectImpersonation(
    profileId: string,
    targetId: string
): Promise<ImpersonationFlag | null> {
    const SIMILARITY_THRESHOLD = 0.85;

    const [profileSnap, targetSnap] = await Promise.all([
        db.collection("users").doc(profileId).get(),
        db.collection("users").doc(targetId).get(),
    ]);

    if (!profileSnap.exists || !targetSnap.exists) {
        return null;
    }

    const profileData = profileSnap.data()!;
    const targetData = targetSnap.data()!;

    const profileName = (profileData.displayName ?? profileData.username ?? "") as string;
    const targetName = (targetData.displayName ?? targetData.username ?? "") as string;

    if (!profileName || !targetName) {
        return null;
    }

    const similarity = nameSimilarity(profileName, targetName);

    // Also check if profileName matches a public figure pattern that targetId is known for
    const publicFigureMatches = matchesPublicFigurePattern(profileName);

    const isHighSimilarity = similarity >= SIMILARITY_THRESHOLD;
    const isPublicFigureMatch = publicFigureMatches.length > 0;

    if (!isHighSimilarity && !isPublicFigureMatch) {
        return null;
    }

    const flag: ImpersonationFlag = {
        profileId,
        targetId,
        similarity,
        flagReason: isPublicFigureMatch
            ? `Public figure pattern matched: ${publicFigureMatches.join(", ")}`
            : `Name similarity ${(similarity * 100).toFixed(0)}% exceeds threshold`,
        autoDetected: true,
        createdAt: Timestamp.now(),
    };

    // Log the flag for admin visibility — NO enforcement action
    logger.warn("impersonation_flag_detected", {
        profileId,
        targetId,
        similarity,
        publicFigureMatches,
    });

    // Store flag in Firestore for admin review queue
    await db.collection("impersonationFlags").add(flag);

    return flag;
}

/**
 * File an impersonation report from a user.
 * Routes to admin review queue — NO automated enforcement.
 *
 * Input:
 *   reporterId — the user filing the report (from auth token)
 *   targetId — the profile being impersonated (the legitimate one)
 *   suspectedProfileId — the profile suspected of impersonating
 *   evidence — { description, screenshotUrls?, links? }
 */
export async function reportImpersonation(
    reporterId: string,
    suspectedProfileId: string,
    targetId: string,
    evidence: Record<string, unknown>
): Promise<{ reportId: string; status: ImpersonationReportStatus }> {
    // Rate-limit: max 5 reports per reporter per 24 hours
    const yesterday = Timestamp.fromDate(new Date(Date.now() - 24 * 60 * 60 * 1000));
    const recentSnap = await db
        .collection("impersonationReports")
        .where("reporterId", "==", reporterId)
        .where("createdAt", ">=", yesterday)
        .get();

    if (recentSnap.size >= 5) {
        throw new HttpsError(
            "resource-exhausted",
            "Too many impersonation reports filed recently. Please try again later."
        );
    }

    // Prevent self-reports
    if (suspectedProfileId === reporterId) {
        throw new HttpsError("invalid-argument", "You cannot report yourself for impersonation.");
    }

    const now = Timestamp.now();
    const reportRef = db.collection("impersonationReports").doc();

    const report: Omit<ImpersonationReport, "reportId"> = {
        reporterId,
        suspectedProfileId,
        targetId,
        evidence,
        status: "pending_review",
        createdAt: now,
        updatedAt: now,
    };

    await reportRef.set({ reportId: reportRef.id, ...report });

    // Run automated detection to enrich the report
    try {
        await detectImpersonation(suspectedProfileId, targetId);
    } catch (err) {
        // Detection failure does not block the report from being filed
        logger.warn("detectImpersonation failed during reportImpersonation", { err });
    }

    // TODO(deploy): notify admin via FCM or admin email that a new report is queued.
    // This requires a notification channel setup — HUMAN DEPLOY STEP.
    logger.info("impersonation_report_filed", {
        reportId: reportRef.id,
        reporterId,
        suspectedProfileId,
        targetId,
    });

    return { reportId: reportRef.id, status: "pending_review" };
}

/**
 * Admin action on an impersonation report.
 *
 * ABSOLUTE RULE: never auto-take enforcement. This function requires an admin
 * to explicitly choose an action and is restricted to admin-token callers.
 *
 * Actions:
 *   'remove_badge' — revokes the impersonating profile's verification badge
 *   'suspend'      — marks the account for suspension review (does NOT auto-suspend;
 *                    account suspension requires a separate human-initiated flow)
 *   'dismiss'      — dismisses the report as not actionable
 */
export async function handleImpersonationReport(
    reportId: string,
    adminId: string,
    action: ImpersonationReportAction,
    adminNote?: string
): Promise<{ success: boolean; actionTaken: ImpersonationReportAction }> {
    const reportRef = db.collection("impersonationReports").doc(reportId);
    const reportSnap = await reportRef.get();

    if (!reportSnap.exists) {
        throw new HttpsError("not-found", "Impersonation report not found.");
    }

    const report = reportSnap.data() as ImpersonationReport;

    if (report.status !== "pending_review" && report.status !== "under_review") {
        throw new HttpsError(
            "failed-precondition",
            `Report is already in terminal status '${report.status}'.`
        );
    }

    const now = Timestamp.now();
    let newStatus: ImpersonationReportStatus;

    if (action === "remove_badge") {
        newStatus = "badge_removed";

        // Revoke badge on the suspected impersonator's profile
        // This calls the verification engine's revoke path
        await db.collection("users").doc(report.suspectedProfileId).update({
            "catalog.verifiedOwnership": false,
            "catalog.badge": admin.firestore.FieldValue.delete(),
            "catalog.badgeRevokedAt": now,
            "catalog.badgeRevokedBy": adminId,
            "catalog.badgeRevokedReason": "impersonation_enforcement",
        });

        logger.info("impersonation_badge_removed", {
            reportId,
            suspectedProfileId: report.suspectedProfileId,
            adminId,
        });
    } else if (action === "suspend") {
        newStatus = "account_suspended";

        // Flag for suspension — does NOT execute account suspension automatically.
        // Account suspension requires a separate admin action in the accountSuspension flow.
        await db.collection("users").doc(report.suspectedProfileId).update({
            "accountFlags.impersonationSuspensionPending": true,
            "accountFlags.impersonationSuspensionFlaggedAt": now,
            "accountFlags.impersonationSuspensionFlaggedBy": adminId,
        });

        logger.warn("impersonation_suspension_flagged", {
            reportId,
            suspectedProfileId: report.suspectedProfileId,
            adminId,
            note: "Account flagged for suspension — requires separate human confirmation to execute.",
        });
    } else {
        // dismiss
        newStatus = "dismissed";
        logger.info("impersonation_report_dismissed", {
            reportId,
            adminId,
        });
    }

    await reportRef.update({
        status: newStatus,
        adminId,
        adminNote: adminNote ?? null,
        actionTaken: action,
        updatedAt: now,
    });

    return { success: true, actionTaken: action };
}

// ─── Firebase Callable Exports ────────────────────────────────────────────────

/**
 * reportImpersonation (callable)
 * Any signed-in user can file an impersonation report.
 * Routes to admin review queue only — no automated enforcement.
 *
 * Input:
 *   suspectedProfileId: string — profile suspected of impersonating
 *   targetId: string — the legitimate profile being impersonated
 *   evidence: { description: string; screenshotUrls?: string[]; links?: string[] }
 */
export const reportImpersonationClaim = onCall(
    { region: "us-east1" },
    async (request) => {
        const reporterId = requireAuth(request);

        const { suspectedProfileId, targetId, evidence } = request.data as {
            suspectedProfileId: string;
            targetId: string;
            evidence?: Record<string, unknown>;
        };

        if (!suspectedProfileId || !targetId) {
            throw new HttpsError(
                "invalid-argument",
                "suspectedProfileId and targetId are required."
            );
        }

        return reportImpersonation(
            reporterId,
            suspectedProfileId,
            targetId,
            evidence ?? {}
        );
    }
);

/**
 * handleImpersonationReportClaim (callable)
 * Admin-only action on a pending impersonation report.
 *
 * Input:
 *   reportId: string
 *   action: 'remove_badge' | 'suspend' | 'dismiss'
 *   adminNote?: string
 */
export const handleImpersonationReportClaim = onCall(
    { region: "us-east1" },
    async (request) => {
        const adminId = requireAdmin(request);

        const { reportId, action, adminNote } = request.data as {
            reportId: string;
            action: ImpersonationReportAction;
            adminNote?: string;
        };

        if (!reportId || !action) {
            throw new HttpsError("invalid-argument", "reportId and action are required.");
        }

        const validActions: ImpersonationReportAction[] = ["remove_badge", "suspend", "dismiss"];
        if (!validActions.includes(action)) {
            throw new HttpsError("invalid-argument", `Invalid action: ${action}`);
        }

        return handleImpersonationReport(reportId, adminId, action, adminNote);
    }
);

/**
 * detectImpersonationCheck (callable)
 * Admin utility to run impersonation detection between two profiles on demand.
 * Returns the flag object or null if no impersonation detected.
 * NEVER takes enforcement action.
 *
 * Input: { profileId: string; targetId: string }
 */
export const detectImpersonationCheck = onCall(
    { region: "us-east1" },
    async (request) => {
        requireAdmin(request);

        const { profileId, targetId } = request.data as {
            profileId: string;
            targetId: string;
        };

        if (!profileId || !targetId) {
            throw new HttpsError("invalid-argument", "profileId and targetId are required.");
        }

        const flag = await detectImpersonation(profileId, targetId);
        return { flag: flag ?? null, actionRequired: flag !== null };
    }
);
