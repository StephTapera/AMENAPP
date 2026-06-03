/**
 * NCMEC CyberTipline Mandatory Reporting Pipeline
 *
 * Legal requirement: any platform that detects CSAM must file a report with
 * the National Center for Missing & Exploited Children (NCMEC) CyberTipline.
 * See: 18 U.S.C. § 2258A (PROTECT Our Children Act)
 *
 * This module:
 *   1. Writes a tamper-evident legal-hold record to ncmecReports/{reportId}
 *   2. Queues the report for human operator action in ncmecSubmissionQueue/{entryId}
 *   3. Fires onCSAMDetected (Firestore trigger) to alert admins via FCM + moderatorAlerts
 *
 * TODO — CyberTipline API integration (requires NCMEC Electronic Service Provider agreement):
 *   Endpoint: https://www.ncmec.org/cybertiplinedata/
 *   Auth: HTTPS Basic + ESP ID + API key issued by NCMEC after registration agreement
 *   Payload shape (ESP Report submission):
 *     {
 *       reportType: "Child Pornography (possession, manufacture, and distribution)",
 *       incidentDateTime: <ISO8601>,
 *       espName: "Amen",
 *       espUserId: <authorId>,
 *       espUserEmail: <if available>,
 *       reportedContent: [{ value: <url>, type: "url" }],
 *       additionalInfo: <detectedCategories joined>
 *     }
 *   Once credentials are obtained, replace the queue-only approach below with a
 *   live HTTPS POST to the above endpoint, and store the NCMEC report ID returned
 *   in the ncmecReports document alongside the local reportId.
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const db = getFirestore();

/**
 * fileNCMECReport — internal helper (not a Cloud Function).
 *
 * Writes a tamper-evident record and queues the report for human operator review.
 * Does NOT make a live HTTP call to NCMEC (credentials required — see TODO above).
 *
 * @param {{
 *   contentRef: string,
 *   contentType: string,
 *   contentUrl: string,
 *   authorId: string,
 *   detectedCategories: string[],
 *   detectedBy: string,
 *   textPreview?: string
 * }} payload
 * @returns {Promise<{ reportId: string, queued: boolean }>}
 */
async function fileNCMECReport(payload) {
    const {
        contentRef,
        contentType,
        contentUrl,
        authorId,
        detectedCategories,
        detectedBy,
        textPreview = "",
    } = payload;

    const reportRef = db.collection("ncmecReports").doc();
    const reportId = reportRef.id;

    // Tamper-evident legal-hold record. Never delete or modify this document.
    await reportRef.set({
        contentRef,
        contentType,
        contentUrl,
        authorId,
        detectedCategories,
        detectedBy,
        status: "pending_submission",
        createdAt: FieldValue.serverTimestamp(),
        legalHold: true,
        preservedAt: FieldValue.serverTimestamp(),
    });

    // Submission queue for human operator (or future automated CyberTipline API).
    const preview = textPreview
        ? String(textPreview).slice(0, 100)
        : "image";

    const entryRef = db.collection("ncmecSubmissionQueue").doc();
    await entryRef.set({
        reportId,
        contentRef,
        authorId,
        preview,
        urgency: "critical",
        status: "queued",
        createdAt: FieldValue.serverTimestamp(),
    });

    console.log(`[NCMEC] Report queued: ${reportId}`);

    return { reportId, queued: true };
}

/**
 * onCSAMDetected — Firestore trigger on ncmecSubmissionQueue/{entryId}.
 *
 * Alerts all admin users via FCM and writes a high-priority moderatorAlert.
 * Fails closed: all errors are caught and logged; the trigger is never re-thrown
 * (avoids infinite Cloud Function retry loops on a poisoned document).
 */
exports.onCSAMDetected = onDocumentCreated(
    {
        document: "ncmecSubmissionQueue/{entryId}",
        region: "us-central1",
    },
    async (event) => {
        const queueEntryId = event.params.entryId;

        try {
            const entry = event.data.data();
            if (!entry) {
                console.error("[NCMEC] onCSAMDetected: empty document — entryId:", queueEntryId);
                return null;
            }

            // Find all users with admin: true custom claim.
            // Custom claims are set via Admin SDK: admin.auth().setCustomUserClaims(uid, { admin: true })
            // We store a mirror in users/{uid}.isAdmin so we can query without listing all Auth users.
            const adminsSnap = await db.collection("users")
                .where("isAdmin", "==", true)
                .get();

            const tokens = [];
            adminsSnap.forEach((doc) => {
                const t = doc.data().fcmToken;
                if (t) tokens.push(t);
            });

            if (tokens.length > 0) {
                const messaging = getMessaging();
                await Promise.all(
                    tokens.map((token) =>
                        messaging.send({
                            token,
                            notification: {
                                title: "CSAM Report Queued",
                                body: "A critical child safety item requires immediate review.",
                            },
                            data: {
                                type: "csam_mandatory_report",
                                queueEntryId,
                                urgency: "critical",
                            },
                            apns: {
                                payload: {
                                    aps: {
                                        sound: "default",
                                        "content-available": 1,
                                    },
                                },
                                headers: {
                                    "apns-priority": "10",
                                },
                            },
                        }).catch((err) =>
                            console.error(`[NCMEC] FCM send failed for token ${token.slice(0, 10)}…:`, err.message)
                        )
                    )
                );
                console.log(`[NCMEC] Admin FCM alerts sent to ${tokens.length} device(s)`);
            } else {
                console.warn("[NCMEC] No admin FCM tokens found — alert not delivered");
            }

            // High-priority alert record for the moderation dashboard.
            await db.collection("moderatorAlerts").add({
                type: "csam_mandatory_report",
                queueEntryId,
                urgency: "critical",
                createdAt: FieldValue.serverTimestamp(),
                read: false,
            });

            console.log(`[NCMEC] moderatorAlert written for queue entry: ${queueEntryId}`);
        } catch (err) {
            // Fail closed: log but never re-throw to avoid Cloud Function retry storms.
            console.error("[NCMEC] onCSAMDetected error:", err);
        }

        return null;
    }
);

exports.fileNCMECReport = fileNCMECReport;
