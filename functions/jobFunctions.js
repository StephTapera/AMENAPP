/**
 * jobFunctions.js
 * Cloud Functions for the AMEN Jobs Platform.
 *
 * Handles:
 * - Notification fan-out (new application → recruiter, status change → seeker)
 * - Job alert matching (new job posted → notify matching seekers)
 * - Counter management (views, applications, saves)
 * - Job listing moderation trigger
 *
 * Firestore collections:
 *   jobListings, jobApplications, jobSeekerProfiles, employerProfiles,
 *   jobAlerts, jobModerationFlags, jobNotifications
 */

const admin = require("firebase-admin");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {checkRateLimit} = require("./rateLimiter");
const {isSundayForUser} = require("./shabbatMiddleware");

const db = () => admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Send an FCM push + create in-app notification for a user.
 */
async function sendJobNotification(recipientId, {title, body, data}) {
  const userDoc = await db().collection("users").doc(recipientId).get();
  if (!userDoc.exists) return;

  const userData = userDoc.data();

  // Create in-app notification
  await db()
      .collection("users")
      .doc(recipientId)
      .collection("notifications")
      .add({
        type: data.type || "job",
        ...data,
        userId: recipientId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

  // Send FCM push
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

// ─── Trigger: New Job Application ────────────────────────────────────────────

/**
 * When a seeker submits an application, notify the recruiter/employer.
 */
const onJobApplicationCreated = onDocumentCreated(
    {
      document: "jobApplications/{applicationId}",
      region: "us-central1",
    },
    async (event) => {
      const applicationData = event.data.data();
      const {jobId, seekerId, employerId} = applicationData;

      if (!jobId || !seekerId || !employerId) {
        console.log("Missing required fields in job application");
        return null;
      }

      try {
        // Shabbat guard
        if (await isSundayForUser(seekerId)) {
          console.log(`Shabbat active for ${seekerId} — skipping notification`);
          return null;
        }

        // Get seeker profile for display name
        const seekerDoc = await db().collection("users").doc(seekerId).get();
        const seekerName = seekerDoc.data()?.displayName || "Someone";
        const seekerPhoto = seekerDoc.data()?.profileImageURL || "";

        // Get job title
        const jobDoc = await db().collection("jobListings").doc(jobId).get();
        const jobTitle = jobDoc.data()?.title || "your job listing";

        // Notify the employer/recruiter
        await sendJobNotification(employerId, {
          title: "New Application",
          body: `${seekerName} applied for ${jobTitle}`,
          data: {
            type: "job_application",
            actorId: seekerId,
            actorName: seekerName,
            actorProfileImageURL: seekerPhoto,
            jobId,
            applicationId: event.params.applicationId,
          },
        });

        console.log(`Job application notification sent to employer ${employerId}`);
        return {success: true};
      } catch (error) {
        console.error("Error in onJobApplicationCreated:", error);
        return null;
      }
    },
);

// ─── Trigger: Application Status Updated ─────────────────────────────────────

/**
 * When a recruiter updates application status, notify the seeker.
 */
const onJobApplicationUpdated = onDocumentUpdated(
    {
      document: "jobApplications/{applicationId}",
      region: "us-central1",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      // Only fire when status changes
      if (before.status === after.status) return null;

      const {seekerId, jobId, employerId} = after;
      if (!seekerId || !jobId) return null;

      try {
        // Get job title
        const jobDoc = await db().collection("jobListings").doc(jobId).get();
        const jobTitle = jobDoc.data()?.title || "a job listing";

        // Get employer name
        const employerDoc = await db().collection("users").doc(employerId).get();
        const employerName = employerDoc.data()?.displayName || "An employer";

        const statusMessages = {
          viewed: `${employerName} viewed your application for ${jobTitle}`,
          shortlisted: `You've been shortlisted for ${jobTitle}`,
          interviewing: `${employerName} wants to interview you for ${jobTitle}`,
          offered: `You received an offer for ${jobTitle}!`,
          hired: `Congratulations! You've been hired for ${jobTitle}!`,
          declined: `Your application for ${jobTitle} was not selected`,
        };

        const body = statusMessages[after.status];
        if (!body) return null; // No notification for unknown statuses

        await sendJobNotification(seekerId, {
          title: "Application Update",
          body,
          data: {
            type: "job_application_update",
            actorId: employerId,
            actorName: employerName,
            jobId,
            applicationId: event.params.applicationId,
            newStatus: after.status,
          },
        });

        console.log(`Application status notification (${after.status}) sent to ${seekerId}`);
        return {success: true};
      } catch (error) {
        console.error("Error in onJobApplicationUpdated:", error);
        return null;
      }
    },
);

// ─── Trigger: New Job Posted → Match Alerts ──────────────────────────────────

/**
 * When a new job is posted, check all active job alerts and notify matching seekers.
 */
const onJobListingCreated = onDocumentCreated(
    {
      document: "jobListings/{jobId}",
      region: "us-central1",
    },
    async (event) => {
      const jobData = event.data.data();
      const jobId = event.params.jobId;

      if (!jobData.isActive) return null;

      try {
        // Fetch active job alerts (instant frequency)
        const alertsSnap = await db()
            .collection("jobAlerts")
            .where("isActive", "==", true)
            .where("frequency", "==", "instant")
            .get();

        if (alertsSnap.empty) return null;

        let matchCount = 0;

        for (const alertDoc of alertsSnap.docs) {
          const alert = alertDoc.data();

          // Simple keyword matching against job title and description
          const keywords = (alert.keywords || "").toLowerCase().split(/\s+/).filter(Boolean);
          const jobText = `${jobData.title} ${jobData.description}`.toLowerCase();

          const matches = keywords.length === 0 ||
              keywords.some((kw) => jobText.includes(kw));

          // Category match (if alert specifies categories)
          const categoryMatch = !alert.categories || alert.categories.length === 0 ||
              alert.categories.includes(jobData.category);

          // Location match (if alert specifies arrangement)
          const arrangementMatch = !alert.workArrangement ||
              alert.workArrangement === jobData.workArrangement;

          if (matches && categoryMatch && arrangementMatch) {
            // Don't notify the poster about their own job
            if (alert.userId === jobData.employerId) continue;

            await sendJobNotification(alert.userId, {
              title: "Job Alert Match",
              body: `New job matching your alert: ${jobData.title}`,
              data: {
                type: "job_alert",
                jobId,
                alertId: alertDoc.id,
              },
            });
            matchCount++;
          }
        }

        console.log(`Job alert notifications sent to ${matchCount} seeker(s) for job ${jobId}`);
        return {success: true};
      } catch (error) {
        console.error("Error in onJobListingCreated:", error);
        return null;
      }
    },
);

// ─── Callable: Report a Job Listing ──────────────────────────────────────────

/**
 * Rate-limited callable for reporting a suspicious job listing.
 */
const reportJobListing = onCall(
    {region: "us-central1"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

      const {jobId, reason, details} = request.data;
      if (!jobId || !reason) {
        throw new HttpsError("invalid-argument", "jobId and reason are required");
      }

      // Rate limit: 10 reports per hour
      await checkRateLimit(uid, "job_report", 10, 3600);

      await db().collection("jobModerationFlags").add({
        jobId,
        reporterId: uid,
        reason,
        details: details || "",
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // If 3+ unique reporters, auto-derank the listing
      const reportsSnap = await db()
          .collection("jobModerationFlags")
          .where("jobId", "==", jobId)
          .where("status", "==", "pending")
          .get();

      const uniqueReporters = new Set(reportsSnap.docs.map((d) => d.data().reporterId));
      if (uniqueReporters.size >= 3) {
        await db().collection("jobListings").doc(jobId).update({
          moderationState: "under_review",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Job ${jobId} auto-flagged for review (${uniqueReporters.size} reports)`);
      }

      return {success: true};
    },
);

module.exports = {
  onJobApplicationCreated,
  onJobApplicationUpdated,
  onJobListingCreated,
  reportJobListing,
};
