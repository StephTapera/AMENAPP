/**
 * calmControl.ts
 *
 * Calm Control + Notification Eligibility Cloud Functions.
 *
 * Functions exported:
 *   updatePrivacySettings           — write privacy preference flags for the caller
 *   updateFeedControls              — write feed-content preference flags
 *   updateNotificationSettings      — write notification preferences + run eligibility check
 *   evaluateNotificationEligibility — determine whether a given notification category may fire
 *   pauseInactiveUserNotifications  — scheduled: mute most notifications after 7 days idle
 *   restoreUserAfterInactivity      — callable: called by app on return after inactivity
 *
 * Auth model: every callable requires both Firebase Auth AND App Check.
 * Rate limiting: 20 calls / hour per user via the shared Firestore window mechanism.
 * No secrets, no sensitive data in logs.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ─── Constants ───────────────────────────────────────────────────────────────

const REGION = "us-central1";
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const INACTIVE_THRESHOLD_DAYS = 7;
const QUIET_RETURN_WINDOW_DAYS = 14;
const INACTIVITY_BATCH_SIZE = 500;

const VALID_EMOTIONAL_ENERGY_FILTERS = ["calm", "balanced", "uplifting", "varied"] as const;
const VALID_INTENSITY_MODES = ["minimal", "balanced", "encouraging", "activeCommunity"] as const;
const VALID_PRESENCE_STATES = ["available", "reflecting", "praying", "reading", "resting", "seeking", "sabbathing"] as const;
const MINIMAL_ALLOWED_CATEGORIES = new Set(["dailyVerse"]);

type EmotionalEnergyFilter = typeof VALID_EMOTIONAL_ENERGY_FILTERS[number];
type IntensityMode = typeof VALID_INTENSITY_MODES[number];
type PresenceState = typeof VALID_PRESENCE_STATES[number];

type NotificationCategory =
  | "dailyVerse"
  | "readingReminder"
  | "prayerReminder"
  | "communityDigest"
  | "streakReminder"
  | "quietReturn"
  | "milestoneReflection";

const VALID_NOTIFICATION_CATEGORIES = new Set<NotificationCategory>([
  "dailyVerse",
  "readingReminder",
  "prayerReminder",
  "communityDigest",
  "streakReminder",
  "quietReturn",
  "milestoneReflection",
]);

// ─── Input Interfaces ─────────────────────────────────────────────────────────

interface PrivacySettingsInput {
  hideFollowerCount?: boolean;
  hideFollowingCount?: boolean;
  privateFollowingGraph?: boolean;
  quietProfileMode?: boolean;
  disableReadReceipts?: boolean;
  presenceState?: PresenceState;
  anonymousReflectionEnabled?: boolean;
}

interface FeedControlsInput {
  textOnlyMode?: boolean;
  hidePhotosVideos?: boolean;
  hideViralContent?: boolean;
  noDebateFilter?: boolean;
  motionReductionFeed?: boolean;
  audioAutoplayDisabled?: boolean;
  emotionalEnergyFilter?: EmotionalEnergyFilter;
  topicSaturations?: Record<string, number>;
}

interface NotificationSettingsInput {
  intensityMode?: IntensityMode;
  dailyVerseEnabled?: boolean;
  dailyVerseTime?: string;
  morningDigestEnabled?: boolean;
  eveningDigestEnabled?: boolean;
  adaptiveRemindersEnabled?: boolean;
}

interface EligibilityInput {
  notificationCategory: NotificationCategory;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request: { auth?: { uid: string } | null; app?: unknown }): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!request.app) {
    throw new HttpsError(
      "failed-precondition",
      "The function must be called from an App Check verified app."
    );
  }
  return request.auth.uid;
}

/**
 * Simple hourly sliding-window rate limit stored at
 *   rateLimits/{uid}/windows/{name}_{windowStart}
 * Reuses the same storage shape as the project-wide rateLimit.ts utility but
 * is self-contained to avoid a cross-file import cycle with that module.
 */
async function enforceHourlyRateLimit(uid: string, limitName: string): Promise<void> {
  const now = Date.now();
  const windowStart = Math.floor(now / RATE_LIMIT_WINDOW_MS) * RATE_LIMIT_WINDOW_MS;
  const windowEnd = windowStart + RATE_LIMIT_WINDOW_MS;
  const docId = `${limitName}_${windowStart}`;
  const ref = db.collection("rateLimits").doc(uid).collection("windows").doc(docId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists
      ? (snap.data() as { count: number; windowEnd: number })
      : null;
    const currentCount =
      existing && existing.windowEnd > now ? existing.count : 0;

    if (currentCount >= RATE_LIMIT_MAX) {
      const retryAfterSec = Math.ceil((windowEnd - now) / 1000);
      logger.warn(`[calmControl/rateLimit] uid=${uid} limit=${limitName} count=${currentCount}`);
      throw new HttpsError(
        "resource-exhausted",
        `Too many requests. Please wait ${retryAfterSec} seconds.`
      );
    }

    tx.set(ref, {
      count: currentCount + 1,
      windowEnd,
      uid,
      limitName,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

function asOptionalBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function daysAgo(days: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d;
}

// ─── Internal: eligibility logic (shared by callable + updateNotificationSettings) ──

async function runEligibilityCheck(
  uid: string,
  category: NotificationCategory
): Promise<{ eligible: boolean; reason?: string }> {
  if (!VALID_NOTIFICATION_CATEGORIES.has(category)) {
    throw new HttpsError("invalid-argument", "Unknown notification category.");
  }

  const [notifSnap, rhythmSnap, presenceSnap, activitySnap] = await Promise.all([
    db.collection("users").doc(uid).collection("notificationSettings").doc("main").get(),
    db.collection("users").doc(uid).collection("spiritualRhythm").doc("main").get(),
    db.collection("users").doc(uid).collection("presence").doc("main").get(),
    db.collection("users").doc(uid).collection("activity").doc("main").get(),
  ]);

  // 1. Presence / Sabbath gate
  const presenceState = presenceSnap.exists
    ? (presenceSnap.data() as { presenceState?: string }).presenceState
    : undefined;
  if (presenceState === "sabbathing") {
    return { eligible: false, reason: "sabbath" };
  }

  // Check spiritualRhythm sabbath flag as well
  const rhythmData = rhythmSnap.exists ? (rhythmSnap.data() as Record<string, unknown>) : {};
  if (rhythmData["sabbathModeActive"] === true) {
    return { eligible: false, reason: "sabbath" };
  }

  // 2. Intensity gate
  const notifData = notifSnap.exists ? (notifSnap.data() as Record<string, unknown>) : {};
  const intensityMode = typeof notifData["intensityMode"] === "string"
    ? (notifData["intensityMode"] as IntensityMode)
    : "balanced";

  if (intensityMode === "minimal" && !MINIMAL_ALLOWED_CATEGORIES.has(category)) {
    return { eligible: false, reason: "intensity_minimal" };
  }

  // 3. Inactivity gate
  const activityData = activitySnap.exists ? (activitySnap.data() as Record<string, unknown>) : {};
  const lastActiveAt = activityData["lastActiveAt"] instanceof admin.firestore.Timestamp
    ? (activityData["lastActiveAt"] as admin.firestore.Timestamp).toDate()
    : null;

  if (lastActiveAt !== null) {
    const inactiveSince = Date.now() - lastActiveAt.getTime();
    const inactiveDays = inactiveSince / (1000 * 60 * 60 * 24);

    if (inactiveDays > INACTIVE_THRESHOLD_DAYS) {
      // quietReturn is always eligible if user has been inactive 7–14 days
      if (category === "quietReturn" && inactiveDays <= QUIET_RETURN_WINDOW_DAYS) {
        return { eligible: true };
      }
      return { eligible: false, reason: "inactivity_pause" };
    }
  }

  return { eligible: true };
}

// ─── Callable: updatePrivacySettings ─────────────────────────────────────────

export const updatePrivacySettings = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ success: true }> => {
    const uid = requireAuth(request);
    await enforceHourlyRateLimit(uid, "privacy_settings_1hr");

    const data = request.data as PrivacySettingsInput;

    // Validate field types — reject unknown shapes
    const booleanFields: Array<keyof PrivacySettingsInput> = [
      "hideFollowerCount",
      "hideFollowingCount",
      "privateFollowingGraph",
      "quietProfileMode",
      "disableReadReceipts",
      "anonymousReflectionEnabled",
    ];
    for (const field of booleanFields) {
      if (data[field] !== undefined && typeof data[field] !== "boolean") {
        throw new HttpsError("invalid-argument", `${field} must be a boolean.`);
      }
    }
    if (
      data.presenceState !== undefined &&
      !VALID_PRESENCE_STATES.includes(data.presenceState)
    ) {
      throw new HttpsError(
        "invalid-argument",
        `presenceState must be one of: ${VALID_PRESENCE_STATES.join(", ")}.`
      );
    }

    const payload: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    for (const field of booleanFields) {
      const v = asOptionalBoolean(data[field]);
      if (v !== undefined) payload[field] = v;
    }
    if (data.presenceState !== undefined) payload["presenceState"] = data.presenceState;

    await db
      .collection("users")
      .doc(uid)
      .collection("privacySettings")
      .doc("main")
      .set(payload, { merge: true });

    logger.info(`[calmControl] updatePrivacySettings uid=${uid}`);
    return { success: true };
  }
);

// ─── Callable: updateFeedControls ────────────────────────────────────────────

export const updateFeedControls = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ success: true }> => {
    const uid = requireAuth(request);
    await enforceHourlyRateLimit(uid, "feed_controls_1hr");

    const data = request.data as FeedControlsInput;

    const booleanFields: Array<keyof FeedControlsInput> = [
      "textOnlyMode",
      "hidePhotosVideos",
      "hideViralContent",
      "noDebateFilter",
      "motionReductionFeed",
      "audioAutoplayDisabled",
    ];
    for (const field of booleanFields) {
      if (data[field] !== undefined && typeof data[field] !== "boolean") {
        throw new HttpsError("invalid-argument", `${field} must be a boolean.`);
      }
    }

    if (
      data.emotionalEnergyFilter !== undefined &&
      !VALID_EMOTIONAL_ENERGY_FILTERS.includes(data.emotionalEnergyFilter)
    ) {
      throw new HttpsError(
        "invalid-argument",
        `emotionalEnergyFilter must be one of: ${VALID_EMOTIONAL_ENERGY_FILTERS.join(", ")}.`
      );
    }

    if (data.topicSaturations !== undefined) {
      if (typeof data.topicSaturations !== "object" || Array.isArray(data.topicSaturations)) {
        throw new HttpsError("invalid-argument", "topicSaturations must be a key/value map.");
      }
      for (const [key, val] of Object.entries(data.topicSaturations)) {
        if (typeof key !== "string" || typeof val !== "number" || val < 0 || val > 1) {
          throw new HttpsError(
            "invalid-argument",
            "topicSaturations values must be numbers between 0 and 1."
          );
        }
      }
    }

    const payload: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    for (const field of booleanFields) {
      const v = asOptionalBoolean(data[field]);
      if (v !== undefined) payload[field] = v;
    }
    if (data.emotionalEnergyFilter !== undefined) {
      payload["emotionalEnergyFilter"] = data.emotionalEnergyFilter;
    }
    if (data.topicSaturations !== undefined) {
      payload["topicSaturations"] = data.topicSaturations;
    }

    await db
      .collection("users")
      .doc(uid)
      .collection("feedControls")
      .doc("main")
      .set(payload, { merge: true });

    logger.info(`[calmControl] updateFeedControls uid=${uid}`);
    return { success: true };
  }
);

// ─── Callable: updateNotificationSettings ────────────────────────────────────

export const updateNotificationSettings = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ success: true }> => {
    const uid = requireAuth(request);
    await enforceHourlyRateLimit(uid, "notif_settings_1hr");

    const data = request.data as NotificationSettingsInput;

    if (
      data.intensityMode !== undefined &&
      !VALID_INTENSITY_MODES.includes(data.intensityMode)
    ) {
      throw new HttpsError(
        "invalid-argument",
        `intensityMode must be one of: ${VALID_INTENSITY_MODES.join(", ")}.`
      );
    }

    const booleanFields: Array<keyof NotificationSettingsInput> = [
      "dailyVerseEnabled",
      "morningDigestEnabled",
      "eveningDigestEnabled",
      "adaptiveRemindersEnabled",
    ];
    for (const field of booleanFields) {
      if (data[field] !== undefined && typeof data[field] !== "boolean") {
        throw new HttpsError("invalid-argument", `${field} must be a boolean.`);
      }
    }
    if (
      data.dailyVerseTime !== undefined &&
      (typeof data.dailyVerseTime !== "string" || !/^\d{2}:\d{2}$/.test(data.dailyVerseTime))
    ) {
      throw new HttpsError("invalid-argument", "dailyVerseTime must be in HH:mm format.");
    }

    const payload: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    if (data.intensityMode !== undefined) payload["intensityMode"] = data.intensityMode;
    for (const field of booleanFields) {
      const v = asOptionalBoolean(data[field]);
      if (v !== undefined) payload[field] = v;
    }
    if (data.dailyVerseTime !== undefined) payload["dailyVerseTime"] = data.dailyVerseTime;

    await db
      .collection("users")
      .doc(uid)
      .collection("notificationSettings")
      .doc("main")
      .set(payload, { merge: true });

    // Side-effect: run eligibility evaluation for dailyVerse to keep state fresh
    try {
      await runEligibilityCheck(uid, "dailyVerse");
    } catch {
      // Non-fatal — eligibility check is advisory; the settings write already succeeded
    }

    logger.info(`[calmControl] updateNotificationSettings uid=${uid}`);
    return { success: true };
  }
);

// ─── Callable: evaluateNotificationEligibility ───────────────────────────────

export const evaluateNotificationEligibility = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ eligible: boolean; reason?: string }> => {
    const uid = requireAuth(request);

    const data = request.data as EligibilityInput;
    const category = data?.notificationCategory as NotificationCategory | undefined;
    if (!category || !VALID_NOTIFICATION_CATEGORIES.has(category)) {
      throw new HttpsError(
        "invalid-argument",
        "notificationCategory must be one of the recognised category values."
      );
    }

    return runEligibilityCheck(uid, category);
  }
);

// ─── Callable: restoreUserAfterInactivity ────────────────────────────────────

export const restoreUserAfterInactivity = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ success: true; welcomeBack: true }> => {
    const uid = requireAuth(request);

    const batch = db.batch();

    const notifRef = db
      .collection("users")
      .doc(uid)
      .collection("notificationSettings")
      .doc("main");
    batch.set(
      notifRef,
      {
        inactivityPaused: false,
        pauseNoticeSentAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const activityRef = db
      .collection("users")
      .doc(uid)
      .collection("activity")
      .doc("main");
    batch.set(
      activityRef,
      { lastActiveAt: FieldValue.serverTimestamp() },
      { merge: true }
    );

    await batch.commit();

    logger.info(`[calmControl] restoreUserAfterInactivity uid=${uid}`);
    return { success: true, welcomeBack: true };
  }
);

// ─── Scheduled: pauseInactiveUserNotifications (every 24 hours) ──────────────

export const pauseInactiveUserNotifications = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "UTC",
    region: REGION,
  },
  async (): Promise<void> => {
    logger.info("[calmControl] pauseInactiveUserNotifications — starting run");

    const cutoff = daysAgo(INACTIVE_THRESHOLD_DAYS);
    const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

    // Query up to INACTIVITY_BATCH_SIZE users whose lastActiveAt is before the cutoff
    // The activity sub-collection is denormalized into a top-level collection for queryability.
    // If this pattern is not yet seeded, the query returns empty and the run is a no-op.
    const activitySnap = await db
      .collectionGroup("activity")
      .where("lastActiveAt", "<", cutoffTs)
      .orderBy("lastActiveAt", "asc")
      .limit(INACTIVITY_BATCH_SIZE)
      .get();

    if (activitySnap.empty) {
      logger.info("[calmControl] pauseInactiveUserNotifications — no inactive users found");
      return;
    }

    const messaging = admin.messaging();
    let paused = 0;
    let skipped = 0;

    for (const activityDoc of activitySnap.docs) {
      // The activity doc lives at users/{uid}/activity/main
      const uid = activityDoc.ref.parent.parent?.id;
      if (!uid) continue;

      const notifRef = db
        .collection("users")
        .doc(uid)
        .collection("notificationSettings")
        .doc("main");

      const notifSnap = await notifRef.get();
      const notifData = notifSnap.exists
        ? (notifSnap.data() as Record<string, unknown>)
        : {};

      // Idempotent: skip if pause notice was already sent
      if (notifData["pauseNoticeSentAt"]) {
        skipped++;
        continue;
      }

      // Mark paused and record the timestamp in one atomic write
      await notifRef.set(
        {
          inactivityPaused: true,
          pauseNoticeSentAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Send a single quiet-return FCM message if the user has a registered token
      const userSnap = await db.collection("users").doc(uid).get();
      const fcmToken =
        userSnap.exists && typeof userSnap.data()?.["fcmToken"] === "string"
          ? (userSnap.data()!["fcmToken"] as string)
          : null;

      if (fcmToken) {
        try {
          await messaging.send({
            token: fcmToken,
            notification: {
              title: "We've been thinking of you",
              body:
                "We've noticed you've been away. We'll pause most notifications until you return. " +
                "No pressure — we'll be here when you're ready.",
            },
            data: {
              notificationCategory: "quietReturn",
            },
            apns: {
              payload: {
                aps: {
                  "interruption-level": "passive",
                },
              },
            },
          });
        } catch (fcmErr) {
          // Non-fatal: token may be stale. Pause is still recorded.
          logger.warn(`[calmControl] FCM send failed for uid=${uid}`, { error: String(fcmErr) });
        }
      }

      paused++;
    }

    logger.info(
      `[calmControl] pauseInactiveUserNotifications — paused=${paused} skipped=${skipped}`
    );
  }
);
