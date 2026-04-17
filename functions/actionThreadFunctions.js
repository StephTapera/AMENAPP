/**
 * Action Thread Cloud Functions
 *
 * Server-side triggers for the Action Threads system (System 8).
 * Handles:
 *   1. onActionThreadCreated — Firestore trigger: validates thread, records trust event
 *   2. onActionStepCompleted — Firestore trigger: updates counters, notifies participants
 *   3. processActionThreadReminders — Scheduled (hourly): sends reminders for upcoming steps
 *   4. cleanupExpiredActionThreads — Scheduled (daily): transitions stale threads to expired
 */

const admin = require("firebase-admin");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const db = admin.firestore();

// ============================================================================
// 1. ON ACTION THREAD CREATED
//    Path: posts/{postId}/actionThreads/{threadId}
//    Validates the thread structure, records a trust event for the creator,
//    and ensures the post's denormalized fields are consistent.
// ============================================================================
exports.onActionThreadCreated = onDocumentCreated(
    {
      document: "posts/{postId}/actionThreads/{threadId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const threadId = event.params.threadId;
      const threadData = event.data.data();

      console.log(`🧵 Action thread created: ${threadId} on post ${postId}`);

      try {
        const ownerId = threadData.ownerId;
        if (!ownerId) {
          console.error("❌ Action thread missing ownerId — skipping");
          return null;
        }

        // Validate that the post exists
        const postDoc = await db.collection("posts").doc(postId).get();
        if (!postDoc.exists) {
          console.error(`❌ Post ${postId} not found — orphaned action thread`);
          return null;
        }

        // Record trust event: action_thread_created
        const trustEventRef = db
            .collection("users")
            .doc(ownerId)
            .collection("trust")
            .collection("events")
            .doc();

        await trustEventRef.set({
          eventType: "action_thread_created",
          category: "care",
          metadata: {
            postId,
            threadId,
            threadType: threadData.threadType || "unknown",
          },
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          idempotencyKey: `thread_created_${threadId}`,
        });

        // Ensure post denormalization is consistent (belt-and-suspenders)
        await db.collection("posts").doc(postId).update({
          actionThreadId: threadId,
          actionThreadType: threadData.threadType || null,
          hasActiveActionThread: true,
        });

        console.log(`✅ Action thread ${threadId} validated and trust event recorded`);
        return {success: true};
      } catch (error) {
        console.error("❌ Error in onActionThreadCreated:", error);
        return null;
      }
    },
);

// ============================================================================
// 2. ON ACTION STEP COMPLETED
//    Path: posts/{postId}/actionThreads/{threadId}
//    Fires when thread document is updated. Checks if completedStepCount
//    changed and sends notifications to participants.
// ============================================================================
exports.onActionStepCompleted = onDocumentUpdated(
    {
      document: "posts/{postId}/actionThreads/{threadId}",
      region: "us-central1",
    },
    async (event) => {
      const postId = event.params.postId;
      const threadId = event.params.threadId;
      const before = event.data.before.data();
      const after = event.data.after.data();

      // Only process when completedStepCount increases
      const prevCount = before.completedStepCount || 0;
      const newCount = after.completedStepCount || 0;

      if (newCount <= prevCount) {
        return null; // No step completion occurred
      }

      console.log(`✅ Step completed in thread ${threadId}: ${prevCount} → ${newCount}`);

      try {
        // Check for state transitions
        const prevState = before.state;
        const newState = after.state;

        if (prevState !== newState) {
          console.log(`🔄 Thread state changed: ${prevState} → ${newState}`);

          // If thread completed, clear the post's active thread flag
          if (newState === "completed" || newState === "archived") {
            await db.collection("posts").doc(postId).update({
              hasActiveActionThread: false,
            });
          }
        }

        // Notify participants about the step completion
        const membershipsSnap = await db
            .collection("actionThreadMemberships")
            .where("threadId", "==", threadId)
            .where("status", "in", ["active", "accepted"])
            .get();

        if (membershipsSnap.empty) {
          console.log("ℹ️ No active participants to notify");
          return null;
        }

        const batch = db.batch();
        const lastUpdatedBy = after.lastUpdatedBy || "unknown";

        for (const memberDoc of membershipsSnap.docs) {
          const memberData = memberDoc.data();
          const participantId = memberData.userId;

          // Don't notify the person who completed the step
          if (participantId === lastUpdatedBy) continue;

          const notifRef = db
              .collection("users")
              .doc(participantId)
              .collection("notifications")
              .doc();

          batch.set(notifRef, {
            type: "actionThreadUpdate",
            actorId: lastUpdatedBy,
            postId: postId,
            threadId: threadId,
            groupId: `action_thread_${threadId}`,
            message: `Step ${newCount} completed in your support flow`,
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            idempotencyKey: `thread_step_${threadId}_${newCount}`,
          });
        }

        await batch.commit();
        console.log(`✅ Step completion notifications sent for thread ${threadId}`);
        return {success: true};
      } catch (error) {
        console.error("❌ Error in onActionStepCompleted:", error);
        return null;
      }
    },
);

// ============================================================================
// 3. PROCESS ACTION THREAD REMINDERS
//    Scheduled: every hour
//    Finds threads with upcoming step deadlines and sends reminders to
//    assigned participants.
// ============================================================================
exports.processActionThreadReminders = onSchedule(
    {schedule: "0 * * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      console.log("⏰ Processing action thread reminders...");

      try {
        const now = new Date();
        const oneHourFromNow = new Date(now.getTime() + 60 * 60 * 1000);
        const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

        // Find active threads that have reminders due in the next hour
        // We query actionThreadMemberships for active members, then check their threads
        const activeThreadsSnap = await db
            .collectionGroup("actionThreads")
            .where("state", "in", ["active", "in_progress"])
            .where("nextReminderAt", ">=", admin.firestore.Timestamp.fromDate(oneHourAgo))
            .where("nextReminderAt", "<=", admin.firestore.Timestamp.fromDate(oneHourFromNow))
            .limit(100) // Process max 100 per run
            .get();

        if (activeThreadsSnap.empty) {
          console.log("ℹ️ No threads with pending reminders");
          return;
        }

        let remindersSent = 0;

        for (const threadDoc of activeThreadsSnap.docs) {
          const threadData = threadDoc.data();
          const threadId = threadDoc.id;
          const postId = threadDoc.ref.parent.parent.id;

          // Get participants for this thread
          const membersSnap = await db
              .collection("actionThreadMemberships")
              .where("threadId", "==", threadId)
              .where("status", "in", ["active", "accepted"])
              .get();

          const batch = db.batch();

          for (const memberDoc of membersSnap.docs) {
            const memberData = memberDoc.data();
            const userId = memberData.userId;

            // Create reminder notification
            const notifRef = db
                .collection("users")
                .doc(userId)
                .collection("notifications")
                .doc();

            batch.set(notifRef, {
              type: "actionThreadReminder",
              postId: postId,
              threadId: threadId,
              groupId: `action_thread_${threadId}`,
              message: `Reminder: You have a pending step in a support flow`,
              read: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              idempotencyKey: `thread_reminder_${threadId}_${now.toISOString().slice(0, 13)}`, // hourly dedup
            });

            remindersSent++;
          }

          // Clear the nextReminderAt to prevent re-firing
          batch.update(threadDoc.ref, {
            lastReminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
            nextReminderAt: null,
          });

          await batch.commit();
        }

        console.log(`✅ Sent ${remindersSent} action thread reminder(s)`);
      } catch (error) {
        console.error("❌ Error in processActionThreadReminders:", error);
      }
    },
);

// ============================================================================
// 4. CLEANUP EXPIRED ACTION THREADS
//    Scheduled: daily at 4 AM UTC
//    Transitions stale threads (no activity for 30 days) to "expired" state
//    and clears the post's denormalized flag.
// ============================================================================
exports.cleanupExpiredActionThreads = onSchedule(
    {schedule: "0 4 * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      console.log("🧹 Cleaning up expired action threads...");

      try {
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

        // Find active threads with no recent activity
        const staleThreadsSnap = await db
            .collectionGroup("actionThreads")
            .where("state", "in", ["active", "in_progress", "paused"])
            .where("updatedAt", "<=", admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
            .limit(200) // Process max 200 per run
            .get();

        if (staleThreadsSnap.empty) {
          console.log("ℹ️ No stale action threads found");
          return;
        }

        let expiredCount = 0;

        for (const threadDoc of staleThreadsSnap.docs) {
          const threadId = threadDoc.id;
          const postId = threadDoc.ref.parent.parent.id;

          const batch = db.batch();

          // Transition to expired
          batch.update(threadDoc.ref, {
            state: "expired",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Add audit entry
          const auditRef = threadDoc.ref.collection("audit").doc();
          batch.set(auditRef, {
            action: "state_transition",
            previousState: threadDoc.data().state,
            newState: "expired",
            reason: "auto_expiry_30_days_inactive",
            performedBy: "system",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
          });

          // Clear post denormalization
          batch.update(db.collection("posts").doc(postId), {
            hasActiveActionThread: false,
          });

          await batch.commit();
          expiredCount++;
        }

        console.log(`✅ Expired ${expiredCount} stale action thread(s)`);
      } catch (error) {
        console.error("❌ Error in cleanupExpiredActionThreads:", error);
      }
    },
);
