/**
 * calmControlFunctions.js
 * Calm Control + Spiritual Rhythm OS — server-side enforcement layer.
 *
 * Callable functions:
 *   evaluateNotificationEligibility  — policy check before sending a push
 *   updateCalmControlSettings        — persist privacy/feed/presence snapshot
 *   updateRhythmSettings             — persist rhythm prefs (sabbath, reminders)
 *   recordSpiritualActivity          — log an activity and update streak
 *   calculateStreakState             — compute or recover a streak
 *   pauseInactiveUserNotifications   — suppress non-essential push after 7 days idle
 *   restoreUserAfterInactivity       — re-enable push and reset idle flags
 *
 * Scheduled:
 *   checkSpiritualRhythmInactivity   — daily Cloud Scheduler job (00:00 UTC)
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const db = admin.firestore();

// ─── Constants ───────────────────────────────────────────────────────────────

const ESSENTIAL_CATEGORIES = new Set([
  "dailyVerse",
  "readingReminder",
  "prayerReminder",
]);

const INTENSITY_ALLOW = {
  minimal: (cat) => cat === "dailyVerse" || cat === "quietReturn",
  balanced: (cat) => cat !== "streakReminder" && cat !== "communityDigest",
  encouraging: (cat) => cat !== "communityDigest",
  activeCommunity: () => true,
};

const INACTIVITY_DAYS = 7;
const GRACE_RECOVERY_LIMIT = 2;

// ─── evaluateNotificationEligibility ─────────────────────────────────────────

exports.evaluateNotificationEligibility = onCall(async (request) => {
  const { userId, category } = request.data;
  if (!userId || !category) {
    throw new HttpsError("invalid-argument", "userId and category required.");
  }

  const [settingsSnap, rhythmSnap] = await Promise.all([
    db.collection("users").doc(userId)
      .collection("calmControl").doc("notificationSettings").get(),
    db.collection("users").doc(userId)
      .collection("spiritualRhythm").doc("main").get(),
  ]);

  const settings = settingsSnap.exists ? settingsSnap.data() : {};
  const rhythm = rhythmSnap.exists ? rhythmSnap.data() : {};

  // Master push kill-switch
  if (settings.masterPushEnabled === false) {
    return { eligible: false, reason: "Push notifications are disabled." };
  }

  // Sabbath suppresses non-essential
  if (rhythm.sabbathModeEnabled && !ESSENTIAL_CATEGORIES.has(category)) {
    return { eligible: false, reason: "Sabbath mode is active." };
  }

  // Inactivity pause suppresses non-essential
  if (rhythm.notificationsPausedDueToInactivity && !ESSENTIAL_CATEGORIES.has(category)) {
    return { eligible: false, reason: "Notifications paused after 7 days of inactivity." };
  }

  // Quiet hours (22:00–07:00 UTC — client sends local hour if desired)
  if (settings.quietHoursEnabled) {
    const hour = new Date().getUTCHours();
    if (hour >= 22 || hour < 7) {
      if (!ESSENTIAL_CATEGORIES.has(category)) {
        return { eligible: false, reason: "Quiet hours are active." };
      }
    }
  }

  // Per-category toggle
  const enabledCategories = settings.enabledCategories || {};
  if (enabledCategories[category] === false) {
    return { eligible: false, reason: "This notification category is turned off." };
  }

  // Intensity gate
  const intensity = settings.intensity || "balanced";
  const allowFn = INTENSITY_ALLOW[intensity] || INTENSITY_ALLOW.balanced;
  if (!allowFn(category)) {
    return { eligible: false, reason: "Current notification intensity setting." };
  }

  return { eligible: true };
});

// ─── updateCalmControlSettings ───────────────────────────────────────────────

exports.updateCalmControlSettings = onCall(async (request) => {
  const { userId, privacy, feedControls, presence, notificationSettings } = request.data;
  if (!userId) throw new HttpsError("invalid-argument", "userId required.");

  const base = db.collection("users").doc(userId).collection("calmControl");
  const batch = db.batch();

  if (privacy) {
    batch.set(base.doc("privacy"), { ...privacy, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  }
  if (feedControls) {
    batch.set(base.doc("feedControls"), { ...feedControls, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  }
  if (presence) {
    batch.set(base.doc("presence"), { ...presence, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  }
  if (notificationSettings) {
    batch.set(base.doc("notificationSettings"), { ...notificationSettings, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  }

  await batch.commit();
  return { success: true };
});

// ─── updateRhythmSettings ────────────────────────────────────────────────────

exports.updateRhythmSettings = onCall(async (request) => {
  const { userId, settings } = request.data;
  if (!userId || !settings) throw new HttpsError("invalid-argument", "userId and settings required.");

  await db.collection("users").doc(userId)
    .collection("spiritualRhythm").doc("main")
    .set({ ...settings, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

  return { success: true };
});

// ─── recordSpiritualActivity ─────────────────────────────────────────────────

exports.recordSpiritualActivity = onCall(async (request) => {
  const { userId, activityType } = request.data;
  if (!userId || !activityType) {
    throw new HttpsError("invalid-argument", "userId and activityType required.");
  }

  const streakRef = db.collection("users").doc(userId)
    .collection("streaks").doc(activityType);
  const rhythmRef = db.collection("users").doc(userId)
    .collection("spiritualRhythm").doc("main");

  const now = admin.firestore.Timestamp.now();

  await db.runTransaction(async (tx) => {
    const streakSnap = await tx.get(streakRef);
    const data = streakSnap.exists ? streakSnap.data() : {};

    const lastActivity = data.lastActivityAt ? data.lastActivityAt.toDate() : null;
    const isToday = lastActivity && isDateToday(lastActivity);
    if (isToday) return; // Already logged today — idempotent

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const wasYesterday = lastActivity && isSameDay(lastActivity, yesterday);

    const currentStreak = wasYesterday ? (data.currentStreak || 0) + 1 : 1;
    const longestStreak = Math.max(currentStreak, data.longestStreak || 0);

    tx.set(streakRef, {
      streakType: activityType,
      currentStreak,
      longestStreak,
      lastActivityAt: now,
      isInGracePeriod: false,
      graceRecoveriesRemaining: data.graceRecoveriesRemaining ?? GRACE_RECOVERY_LIMIT,
    }, { merge: true });

    tx.set(rhythmRef, {
      lastActivityAt: now,
      notificationsPausedDueToInactivity: false,
      inactiveNoticeSent: false,
    }, { merge: true });
  });

  return { success: true };
});

// ─── calculateStreakState ─────────────────────────────────────────────────────

exports.calculateStreakState = onCall(async (request) => {
  const { userId, streakType, action } = request.data;
  if (!userId || !streakType) {
    throw new HttpsError("invalid-argument", "userId and streakType required.");
  }

  const streakRef = db.collection("users").doc(userId)
    .collection("streaks").doc(streakType);

  if (action === "recover") {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(streakRef);
      const data = snap.exists ? snap.data() : {};
      const remaining = data.graceRecoveriesRemaining ?? 0;
      if (remaining <= 0) {
        throw new HttpsError("failed-precondition", "No grace recoveries remaining.");
      }
      tx.set(streakRef, {
        currentStreak: 1,
        graceRecoveriesRemaining: remaining - 1,
        isInGracePeriod: false,
        isRecovered: true,
        lastActivityAt: admin.firestore.Timestamp.now(),
      }, { merge: true });
    });
    return { success: true, action: "recovered" };
  }

  // Default: re-compute streak from lastActivityAt
  const snap = await streakRef.get();
  const data = snap.exists ? snap.data() : {};
  const lastActivity = data.lastActivityAt ? data.lastActivityAt.toDate() : null;

  if (!lastActivity) {
    return { currentStreak: 0, longestStreak: 0, isInGracePeriod: false };
  }

  const daysSinceLast = Math.floor((Date.now() - lastActivity.getTime()) / 86400000);
  const isInGracePeriod = daysSinceLast === 1 && (data.graceRecoveriesRemaining ?? 0) > 0;

  if (daysSinceLast > 1) {
    await streakRef.set({ currentStreak: 0, isInGracePeriod }, { merge: true });
    return { currentStreak: 0, longestStreak: data.longestStreak ?? 0, isInGracePeriod };
  }

  return {
    currentStreak: data.currentStreak ?? 0,
    longestStreak: data.longestStreak ?? 0,
    isInGracePeriod,
  };
});

// ─── pauseInactiveUserNotifications ─────────────────────────────────────────

exports.pauseInactiveUserNotifications = onCall(async (request) => {
  const { userId } = request.data;
  if (!userId) throw new HttpsError("invalid-argument", "userId required.");

  await db.collection("users").doc(userId)
    .collection("spiritualRhythm").doc("main")
    .set({
      notificationsPausedDueToInactivity: true,
      inactiveNoticeSent: true,
      pausedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

  // Send a single quiet-return push (best-effort)
  try {
    const userSnap = await db.collection("users").doc(userId).get();
    const fcmToken = userSnap.data()?.fcmToken;
    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "Still here when you are.",
          body: "We paused reminders while you were away. Come back whenever you're ready.",
        },
        apns: { payload: { aps: { "interruption-level": "passive" } } },
      });
    }
  } catch (_) { /* non-fatal */ }

  return { success: true };
});

// ─── restoreUserAfterInactivity ──────────────────────────────────────────────

exports.restoreUserAfterInactivity = onCall(async (request) => {
  const { userId } = request.data;
  if (!userId) throw new HttpsError("invalid-argument", "userId required.");

  await db.collection("users").doc(userId)
    .collection("spiritualRhythm").doc("main")
    .set({
      notificationsPausedDueToInactivity: false,
      inactiveNoticeSent: false,
      lastActivityAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

  return { success: true };
});

// ─── checkSpiritualRhythmInactivity (scheduled) ──────────────────────────────

exports.checkSpiritualRhythmInactivity = onSchedule(
  { schedule: "0 0 * * *", timeZone: "UTC" },
  async () => {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - INACTIVITY_DAYS);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

    // Find users whose lastActivityAt is older than cutoff and not yet paused
    const snap = await db.collectionGroup("spiritualRhythm")
      .where("lastActivityAt", "<", cutoffTs)
      .where("notificationsPausedDueToInactivity", "==", false)
      .where("inactiveNoticeSent", "==", false)
      .limit(500)
      .get();

    const batch = db.batch();
    const fcmJobs = [];

    for (const doc of snap.docs) {
      batch.set(doc.ref, {
        notificationsPausedDueToInactivity: true,
        inactiveNoticeSent: true,
        pausedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // Extract userId from path: users/{userId}/spiritualRhythm/main
      const userId = doc.ref.path.split("/")[1];
      fcmJobs.push(userId);
    }

    await batch.commit();

    // Send passive quiet-return push to each affected user
    await Promise.allSettled(fcmJobs.map(async (userId) => {
      const userSnap = await db.collection("users").doc(userId).get();
      const fcmToken = userSnap.data()?.fcmToken;
      if (!fcmToken) return;
      return admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "Still here when you are.",
          body: "We paused reminders while you were away. Come back whenever you're ready.",
        },
        apns: { payload: { aps: { "interruption-level": "passive" } } },
      });
    }));

    console.log(`checkSpiritualRhythmInactivity: paused ${fcmJobs.length} users`);
  }
);

// ─── Helpers ─────────────────────────────────────────────────────────────────

function isDateToday(date) {
  const now = new Date();
  return date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate();
}

function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate();
}
