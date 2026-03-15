/**
 * eventFunctions.js
 * Cloud Functions for the AMEN Calendar & Events system.
 *
 * Handles:
 * - RSVP counter management (atomic increments via server)
 * - RSVP notification to event organizer
 * - Event reminder notifications (scheduled)
 * - Post-event follow-up reminders
 *
 * Firestore collections:
 *   faithEvents, eventRSVPs, savedCalendarEvents
 */

const admin = require("firebase-admin");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {isSundayForUser} = require("./shabbatMiddleware");

const db = () => admin.firestore();

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function sendEventNotification(recipientId, {title, body, data}) {
  const userDoc = await db().collection("users").doc(recipientId).get();
  if (!userDoc.exists) return;

  const userData = userDoc.data();

  // In-app notification
  await db()
      .collection("users")
      .doc(recipientId)
      .collection("notifications")
      .add({
        type: data.type || "event",
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

// ─── Trigger: New RSVP Created ───────────────────────────────────────────────

/**
 * When a user RSVPs to an event:
 * 1. Atomically increment the event's rsvpCount
 * 2. Notify the event organizer
 */
const onEventRSVPCreated = onDocumentCreated(
    {
      document: "eventRSVPs/{rsvpId}",
      region: "us-central1",
    },
    async (event) => {
      const rsvpData = event.data.data();
      const {eventId, userId, status} = rsvpData;

      if (!eventId || !userId) return null;

      // Only count "going" and "maybe" toward rsvpCount
      const countable = status === "going" || status === "maybe";

      try {
        // Atomic counter increment
        if (countable) {
          await db().collection("faithEvents").doc(eventId).update({
            rsvpCount: admin.firestore.FieldValue.increment(1),
          });
        }

        // Get event to find organizer
        const eventDoc = await db().collection("faithEvents").doc(eventId).get();
        if (!eventDoc.exists) return null;

        const eventData = eventDoc.data();
        const organizerId = eventData.organizerId;

        // Don't notify organizer about their own RSVP
        if (!organizerId || organizerId === userId) return null;

        // Shabbat guard
        if (await isSundayForUser(userId)) return null;

        const userDoc = await db().collection("users").doc(userId).get();
        const userName = userDoc.data()?.displayName || "Someone";
        const userPhoto = userDoc.data()?.profileImageURL || "";

        const statusLabel = status === "going" ? "is going to" :
          status === "maybe" ? "is interested in" : "responded to";

        await sendEventNotification(organizerId, {
          title: "New RSVP",
          body: `${userName} ${statusLabel} ${eventData.title || "your event"}`,
          data: {
            type: "event_rsvp",
            actorId: userId,
            actorName: userName,
            actorProfileImageURL: userPhoto,
            eventId,
            rsvpStatus: status,
          },
        });

        return {success: true};
      } catch (error) {
        console.error("Error in onEventRSVPCreated:", error);
        return null;
      }
    },
);

// ─── Trigger: RSVP Status Updated ───────────────────────────────────────────

/**
 * When a user changes their RSVP (e.g. going → not going), adjust the counter.
 */
const onEventRSVPUpdated = onDocumentUpdated(
    {
      document: "eventRSVPs/{rsvpId}",
      region: "us-central1",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (before.status === after.status) return null;

      const {eventId} = after;
      if (!eventId) return null;

      const wasCountable = before.status === "going" || before.status === "maybe";
      const isCountable = after.status === "going" || after.status === "maybe";

      try {
        if (wasCountable && !isCountable) {
          // Decrement (floor at 0 via transaction)
          const eventRef = db().collection("faithEvents").doc(eventId);
          await db().runTransaction(async (txn) => {
            const doc = await txn.get(eventRef);
            const current = doc.data()?.rsvpCount || 0;
            txn.update(eventRef, {rsvpCount: Math.max(0, current - 1)});
          });
        } else if (!wasCountable && isCountable) {
          // Increment
          await db().collection("faithEvents").doc(eventId).update({
            rsvpCount: admin.firestore.FieldValue.increment(1),
          });
        }
        // If both countable (going↔maybe), no count change needed

        return {success: true};
      } catch (error) {
        console.error("Error in onEventRSVPUpdated:", error);
        return null;
      }
    },
);

// ─── Scheduled: Event Reminder Notifications ─────────────────────────────────

/**
 * Runs every 15 minutes. Finds events starting within the next 15-60 minutes
 * and sends reminder pushes to users who have saved those events.
 */
const sendEventReminders = onSchedule(
    {schedule: "*/15 * * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const now = new Date();
      const in15Min = new Date(now.getTime() + 15 * 60 * 1000);
      const in60Min = new Date(now.getTime() + 60 * 60 * 1000);

      try {
        // Find events starting in the next 15-60 minutes
        const eventsSnap = await db()
            .collection("faithEvents")
            .where("startDate", ">=", admin.firestore.Timestamp.fromDate(in15Min))
            .where("startDate", "<=", admin.firestore.Timestamp.fromDate(in60Min))
            .get();

        if (eventsSnap.empty) return;

        let remindersSent = 0;

        for (const eventDoc of eventsSnap.docs) {
          const eventData = eventDoc.data();
          const eventId = eventDoc.id;

          // Find users who RSVP'd "going" to this event
          const rsvpsSnap = await db()
              .collection("eventRSVPs")
              .where("eventId", "==", eventId)
              .where("status", "==", "going")
              .where("reminderEnabled", "==", true)
              .get();

          for (const rsvpDoc of rsvpsSnap.docs) {
            const rsvp = rsvpDoc.data();
            const userId = rsvp.userId;
            if (!userId) continue;

            // Check if we already sent a reminder (idempotency)
            const reminderKey = `${eventId}_${userId}_reminder`;
            const existingReminder = await db()
                .collection("sentReminders")
                .doc(reminderKey)
                .get();

            if (existingReminder.exists) continue;

            // Calculate minutes until event
            const startTime = eventData.startDate?.toDate?.() || new Date(eventData.startDate);
            const minutesUntil = Math.round((startTime - now) / 60000);

            await sendEventNotification(userId, {
              title: `Starting in ${minutesUntil} min`,
              body: eventData.title || "Your event is starting soon",
              data: {
                type: "event_reminder",
                eventId,
                eventTitle: eventData.title || "",
                minutesUntil: String(minutesUntil),
              },
            });

            // Mark reminder as sent (idempotency)
            await db().collection("sentReminders").doc(reminderKey).set({
              eventId,
              userId,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              // Auto-expire after 24 hours (use TTL policy on this collection)
              expiresAt: admin.firestore.Timestamp.fromDate(
                  new Date(now.getTime() + 24 * 60 * 60 * 1000),
              ),
            });

            remindersSent++;
          }
        }

        if (remindersSent > 0) {
          console.log(`Sent ${remindersSent} event reminder(s)`);
        }
      } catch (error) {
        console.error("Error in sendEventReminders:", error);
      }
    },
);

// ─── Scheduled: Post-Event Follow-Up ─────────────────────────────────────────

/**
 * Runs daily at 9:00 AM UTC.
 * Sends follow-up notifications for events that ended yesterday.
 */
const sendPostEventFollowUp = onSchedule(
    {schedule: "0 9 * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const now = new Date();
      const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
      yesterday.setUTCHours(0, 0, 0, 0);
      const today = new Date(now);
      today.setUTCHours(0, 0, 0, 0);

      try {
        // Find events that ended yesterday
        const eventsSnap = await db()
            .collection("faithEvents")
            .where("endDate", ">=", admin.firestore.Timestamp.fromDate(yesterday))
            .where("endDate", "<", admin.firestore.Timestamp.fromDate(today))
            .get();

        if (eventsSnap.empty) return;

        let followUpsSent = 0;

        for (const eventDoc of eventsSnap.docs) {
          const eventData = eventDoc.data();
          const eventId = eventDoc.id;

          // Find attendees who went
          const rsvpsSnap = await db()
              .collection("eventRSVPs")
              .where("eventId", "==", eventId)
              .where("status", "==", "going")
              .get();

          for (const rsvpDoc of rsvpsSnap.docs) {
            const rsvp = rsvpDoc.data();
            if (!rsvp.userId) continue;

            // Check if follow-up already sent
            const followUpKey = `${eventId}_${rsvp.userId}_followup`;
            const existing = await db().collection("sentReminders").doc(followUpKey).get();
            if (existing.exists) continue;

            // Update the saved calendar event to mark follow-up sent
            const savedSnap = await db()
                .collection("savedCalendarEvents")
                .where("amenEventId", "==", eventId)
                .where("userId", "==", rsvp.userId)
                .limit(1)
                .get();

            if (!savedSnap.empty) {
              await savedSnap.docs[0].ref.update({followUpSent: true});
            }

            await sendEventNotification(rsvp.userId, {
              title: "How was it?",
              body: `Share your experience from ${eventData.title || "yesterday's event"}`,
              data: {
                type: "event_followup",
                eventId,
                eventTitle: eventData.title || "",
              },
            });

            // Idempotency marker
            await db().collection("sentReminders").doc(followUpKey).set({
              eventId,
              userId: rsvp.userId,
              sentAt: admin.firestore.FieldValue.serverTimestamp(),
              expiresAt: admin.firestore.Timestamp.fromDate(
                  new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000),
              ),
            });

            followUpsSent++;
          }
        }

        if (followUpsSent > 0) {
          console.log(`Sent ${followUpsSent} post-event follow-up(s)`);
        }
      } catch (error) {
        console.error("Error in sendPostEventFollowUp:", error);
      }
    },
);

module.exports = {
  onEventRSVPCreated,
  onEventRSVPUpdated,
  sendEventReminders,
  sendPostEventFollowUp,
};
