/**
 * studioFunctions.js
 * Cloud Functions for the AMEN Creator Studio marketplace.
 *
 * Handles:
 * - Notification fan-out (commission/booking request → creator)
 * - Commission/booking status change → client notification
 * - Earnings tracking (monthly summary rollup)
 * - Studio content moderation trigger
 *
 * Firestore collections:
 *   studioProfiles, studioItems, studioServices, studioProducts,
 *   commissionRequests, bookingRequests, inquiryThreads,
 *   creatorEarnings, creatorTransactions, studioModerationFlags
 */

const admin = require("firebase-admin");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {checkRateLimit} = require("./rateLimiter");
const {isSundayForUser} = require("./shabbatMiddleware");

const db = () => admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function sendStudioNotification(recipientId, {title, body, data}) {
  const userDoc = await db().collection("users").doc(recipientId).get();
  if (!userDoc.exists) return;

  const userData = userDoc.data();

  // In-app notification
  await db()
      .collection("users")
      .doc(recipientId)
      .collection("notifications")
      .add({
        type: data.type || "studio",
        ...data,
        userId: recipientId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

  // FCM push
  const fcmToken = userData.fcmToken;
  if (fcmToken) {
    try {
      await admin.messaging().send({
        notification: {title, body},
        data: Object.fromEntries(
            Object.entries(data).map(([k, v]) => [k, String(v)]),
        ),
        token: fcmToken,
      });
    } catch (err) {
      if (err.code === "messaging/registration-token-not-registered") {
        console.log(`Stale FCM token for ${recipientId}`);
      }
    }
  }
}

// ─── Trigger: New Commission Request ─────────────────────────────────────────

const onCommissionRequestCreated = onDocumentCreated(
    {
      document: "commissionRequests/{requestId}",
      region: "us-central1",
    },
    async (event) => {
      const requestData = event.data.data();
      const {creatorId, clientId, commissionType, budgetAmount} = requestData;

      if (!creatorId || !clientId) return null;

      try {
        if (await isSundayForUser(clientId)) return null;

        const clientDoc = await db().collection("users").doc(clientId).get();
        const clientName = clientDoc.data()?.displayName || "Someone";
        const clientPhoto = clientDoc.data()?.profileImageURL || "";

        const budgetStr = budgetAmount ? ` ($${budgetAmount})` : "";

        await sendStudioNotification(creatorId, {
          title: "New Commission Request",
          body: `${clientName} requested a ${commissionType || "commission"}${budgetStr}`,
          data: {
            type: "commission_request",
            actorId: clientId,
            actorName: clientName,
            actorProfileImageURL: clientPhoto,
            requestId: event.params.requestId,
          },
        });

        console.log(`Commission request notification sent to creator ${creatorId}`);
        return {success: true};
      } catch (error) {
        console.error("Error in onCommissionRequestCreated:", error);
        return null;
      }
    },
);

// ─── Trigger: Commission Status Updated ──────────────────────────────────────

const onCommissionStatusUpdated = onDocumentUpdated(
    {
      document: "commissionRequests/{requestId}",
      region: "us-central1",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (before.status === after.status) return null;

      const {clientId, creatorId} = after;
      if (!clientId || !creatorId) return null;

      try {
        const creatorDoc = await db().collection("users").doc(creatorId).get();
        const creatorName = creatorDoc.data()?.displayName || "A creator";

        const statusMessages = {
          accepted: `${creatorName} accepted your commission request!`,
          declined: `${creatorName} declined your commission request`,
          inProgress: `${creatorName} started working on your commission`,
          completed: `${creatorName} completed your commission!`,
          cancelled: `Your commission with ${creatorName} was cancelled`,
        };

        const body = statusMessages[after.status];
        if (!body) return null;

        await sendStudioNotification(clientId, {
          title: "Commission Update",
          body,
          data: {
            type: "commission_update",
            actorId: creatorId,
            actorName: creatorName,
            requestId: event.params.requestId,
            newStatus: after.status,
          },
        });

        return {success: true};
      } catch (error) {
        console.error("Error in onCommissionStatusUpdated:", error);
        return null;
      }
    },
);

// ─── Trigger: New Booking Request ────────────────────────────────────────────

const onBookingRequestCreated = onDocumentCreated(
    {
      document: "bookingRequests/{requestId}",
      region: "us-central1",
    },
    async (event) => {
      const requestData = event.data.data();
      const {creatorId, clientId, eventType} = requestData;

      if (!creatorId || !clientId) return null;

      try {
        if (await isSundayForUser(clientId)) return null;

        const clientDoc = await db().collection("users").doc(clientId).get();
        const clientName = clientDoc.data()?.displayName || "Someone";
        const clientPhoto = clientDoc.data()?.profileImageURL || "";

        await sendStudioNotification(creatorId, {
          title: "New Booking Request",
          body: `${clientName} wants to book you for ${eventType || "an event"}`,
          data: {
            type: "booking_request",
            actorId: clientId,
            actorName: clientName,
            actorProfileImageURL: clientPhoto,
            requestId: event.params.requestId,
          },
        });

        console.log(`Booking request notification sent to creator ${creatorId}`);
        return {success: true};
      } catch (error) {
        console.error("Error in onBookingRequestCreated:", error);
        return null;
      }
    },
);

// ─── Trigger: Booking Status Updated ─────────────────────────────────────────

const onBookingStatusUpdated = onDocumentUpdated(
    {
      document: "bookingRequests/{requestId}",
      region: "us-central1",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (before.status === after.status) return null;

      const {clientId, creatorId} = after;
      if (!clientId || !creatorId) return null;

      try {
        const creatorDoc = await db().collection("users").doc(creatorId).get();
        const creatorName = creatorDoc.data()?.displayName || "A creator";

        const statusMessages = {
          confirmed: `${creatorName} confirmed your booking!`,
          declined: `${creatorName} declined your booking request`,
          completed: `Your booking with ${creatorName} is complete`,
          cancelled: `Your booking with ${creatorName} was cancelled`,
        };

        const body = statusMessages[after.status];
        if (!body) return null;

        await sendStudioNotification(clientId, {
          title: "Booking Update",
          body,
          data: {
            type: "booking_update",
            actorId: creatorId,
            actorName: creatorName,
            requestId: event.params.requestId,
            newStatus: after.status,
          },
        });

        return {success: true};
      } catch (error) {
        console.error("Error in onBookingStatusUpdated:", error);
        return null;
      }
    },
);

// ─── Trigger: New Inquiry Thread ─────────────────────────────────────────────

const onInquiryCreated = onDocumentCreated(
    {
      document: "inquiryThreads/{threadId}",
      region: "us-central1",
    },
    async (event) => {
      const threadData = event.data.data();
      const {creatorId, inquirerId} = threadData;

      if (!creatorId || !inquirerId) return null;

      try {
        if (await isSundayForUser(inquirerId)) return null;

        const inquirerDoc = await db().collection("users").doc(inquirerId).get();
        const inquirerName = inquirerDoc.data()?.displayName || "Someone";
        const inquirerPhoto = inquirerDoc.data()?.profileImageURL || "";

        await sendStudioNotification(creatorId, {
          title: "New Inquiry",
          body: `${inquirerName} sent you an inquiry`,
          data: {
            type: "studio_inquiry",
            actorId: inquirerId,
            actorName: inquirerName,
            actorProfileImageURL: inquirerPhoto,
            threadId: event.params.threadId,
          },
        });

        return {success: true};
      } catch (error) {
        console.error("Error in onInquiryCreated:", error);
        return null;
      }
    },
);

// ─── Callable: Report Studio Content ─────────────────────────────────────────

const reportStudioContent = onCall(
    {region: "us-central1"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {contentId, contentType, reason, details} = request.data;
      if (!contentId || !reason) {
        throw new HttpsError("invalid-argument", "contentId and reason required");
      }

      await checkRateLimit(uid, "studio_report", 10, 3600);

      await db().collection("studioModerationFlags").add({
        contentId,
        contentType: contentType || "unknown",
        reporterId: uid,
        reason,
        details: details || "",
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Auto-flag after 3+ unique reports
      const reportsSnap = await db()
          .collection("studioModerationFlags")
          .where("contentId", "==", contentId)
          .where("status", "==", "pending")
          .get();

      const uniqueReporters = new Set(reportsSnap.docs.map((d) => d.data().reporterId));
      if (uniqueReporters.size >= 3) {
        // Try to flag in whichever collection the content lives in
        const collections = ["studioItems", "studioServices", "studioProducts"];
        for (const coll of collections) {
          const doc = await db().collection(coll).doc(contentId).get();
          if (doc.exists) {
            await doc.ref.update({
              moderationState: "under_review",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            break;
          }
        }
        console.log(`Studio content ${contentId} auto-flagged (${uniqueReporters.size} reports)`);
      }

      return {success: true};
    },
);

// ─── Scheduled: Monthly Earnings Rollup ──────────────────────────────────────

/**
 * Runs on the 1st of each month at 2:00 AM UTC.
 * Summarizes the previous month's completed transactions into an earnings doc.
 */
const monthlyEarningsRollup = onSchedule(
    {schedule: "0 2 1 * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      console.log("Running monthly earnings rollup...");

      try {
        const now = new Date();
        const lastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const thisMonth = new Date(now.getFullYear(), now.getMonth(), 1);

        const monthKey = `${lastMonth.getFullYear()}-${String(lastMonth.getMonth() + 1).padStart(2, "0")}`;

        // Find all completed transactions from last month
        const txSnap = await db()
            .collection("creatorTransactions")
            .where("status", "==", "completed")
            .where("completedAt", ">=", admin.firestore.Timestamp.fromDate(lastMonth))
            .where("completedAt", "<", admin.firestore.Timestamp.fromDate(thisMonth))
            .get();

        if (txSnap.empty) {
          console.log("No completed transactions last month");
          return;
        }

        // Group by creator
        const creatorTotals = {};
        for (const doc of txSnap.docs) {
          const tx = doc.data();
          const cid = tx.creatorId;
          if (!cid) continue;

          if (!creatorTotals[cid]) {
            creatorTotals[cid] = {
              grossAmount: 0,
              platformFees: 0,
              netAmount: 0,
              transactionCount: 0,
              byCategory: {},
            };
          }

          const t = creatorTotals[cid];
          t.grossAmount += tx.grossAmount || 0;
          t.platformFees += tx.platformFee || 0;
          t.netAmount += tx.netAmount || 0;
          t.transactionCount++;

          const cat = tx.category || "other";
          t.byCategory[cat] = (t.byCategory[cat] || 0) + (tx.netAmount || 0);
        }

        // Write earnings summary for each creator
        const batch = db().batch();
        for (const [creatorId, totals] of Object.entries(creatorTotals)) {
          const earningsRef = db()
              .collection("creatorEarnings")
              .doc(`${creatorId}_${monthKey}`);

          batch.set(earningsRef, {
            creatorId,
            month: monthKey,
            ...totals,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();

        console.log(`Earnings rollup complete for ${Object.keys(creatorTotals).length} creator(s)`);
      } catch (error) {
        console.error("Error in monthlyEarningsRollup:", error);
      }
    },
);

module.exports = {
  onCommissionRequestCreated,
  onCommissionStatusUpdated,
  onBookingRequestCreated,
  onBookingStatusUpdated,
  onInquiryCreated,
  reportStudioContent,
  monthlyEarningsRollup,
};
