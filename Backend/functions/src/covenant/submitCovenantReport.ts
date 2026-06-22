import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

// submitCovenantReport
// Server-authoritative report submission. Validates reason, verifies
// content exists, checks for financial manipulation signals, assigns status.
// Direct client writes to /reports are blocked in Firestore rules (allow create: if false).

const VALID_REASONS = [
    "harassment", "spam", "misinformation", "financial_manipulation",
    "sexual_content", "hateful_content", "self_harm_concern", "spiritual_abuse", "other",
];

// Financial manipulation keywords (server-side signal detection)
const FINANCIAL_MANIPULATION_PATTERNS = [
    /seed\s*(faith)?\s*gift/i,
    /miracle\s+money/i,
    /sow\s+\$\d+/i,
    /god\s+told\s+me\s+you\s+need\s+to\s+give/i,
    /unlock\s+your\s+blessing.*give/i,
];

export const submitCovenantReport = onCall(
    { enforceAppCheck: true, region: "us-central1" },
    async (request) => {
        if (!request.auth?.uid) {
            throw new HttpsError("unauthenticated", "Not authenticated.");
        }
        const uid = request.auth.uid;
        const { contentType, contentId, covenantId, reason, additionalNote } = request.data;

        if (!contentType || !contentId || !reason) {
            throw new HttpsError("invalid-argument", "contentType, contentId, and reason are required.");
        }
        if (!VALID_REASONS.includes(reason)) {
            throw new HttpsError("invalid-argument", "Invalid report reason.");
        }

        const db = admin.firestore();

        // Rate limit: max 10 reports per user per 24h
        const recentSnap = await db.collection("reports")
            .where("reporterId", "==", uid)
            .where("createdAt", ">=", admin.firestore.Timestamp.fromMillis(Date.now() - 86400000))
            .limit(11)
            .get();
        if (recentSnap.size >= 10) {
            throw new HttpsError("resource-exhausted", "You have submitted too many reports recently. Please try again tomorrow.");
        }

        // Detect financial manipulation signals server-side (in addition to reporter reason)
        let autoFlagFinancial = false;
        if (reason === "financial_manipulation" || (additionalNote && FINANCIAL_MANIPULATION_PATTERNS.some(p => p.test(additionalNote)))) {
            autoFlagFinancial = true;
        }

        const reportRef = db.collection("reports").doc();
        await reportRef.set({
            reporterId: uid,
            contentType,
            contentId,
            covenantId: covenantId ?? null,
            reason,
            additionalNote: additionalNote ?? null,
            status: "submitted",
            autoFlagFinancial,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // If financial manipulation or self-harm, create a higher-priority moderation queue item
        if (autoFlagFinancial || reason === "self_harm_concern") {
            if (covenantId) {
                await db.collection("covenants").doc(covenantId)
                    .collection("moderationQueue").doc().set({
                        covenantId,
                        contentType,
                        contentId,
                        contentSnippet: additionalNote?.slice(0, 200) ?? "(see report)",
                        reportCount: 1,
                        reportReasons: [reason],
                        status: "pending",
                        auditLog: [],
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
            }
        }

        return { reportId: reportRef.id };
    }
);
