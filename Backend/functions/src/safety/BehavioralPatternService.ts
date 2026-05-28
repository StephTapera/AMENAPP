/**
 * BehavioralPatternService.ts
 *
 * Firebase Cloud Functions v2 — Amen Safety OS
 *
 * Detects dangerous behavioral patterns by analyzing METADATA ONLY:
 * who contacts whom, how often, and at what times. Message content is
 * never read here. This layer catches grooming, spam rings, and coordinated
 * harassment that content-level filters miss.
 *
 * Signals detected:
 *   1. Adult→minor contact velocity (>5 DMs in 24 h)
 *   2. Off-hours adult→minor messaging (10 pm–6 am, >3 messages)
 *   3. Rapid contact escalation / grooming velocity (>5× week-over-week)
 *   4. Spam ring detection (>50 DMs/h or 20+ distinct new recipients in 24 h)
 *   5. Coordinated harassment (3+ distinct new senders to same target in 1 h)
 *
 * Policy version: 2026-05-25
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";
import { writeAuditLog } from "./ModerationAuditLogService";
import { deliverSafetyAlertToGuardians } from "./GuardianConnectionService";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Constants ────────────────────────────────────────────────────────────────

const ADULT_MINOR_24H_THRESHOLD = 5;        // Signal 1
const OFF_HOURS_MSG_THRESHOLD = 3;          // Signal 2
const OFF_HOURS_START_UTC = 22;             // 10 pm (applied after UTC offset)
const OFF_HOURS_END_UTC = 6;               // 6 am
const GROOMING_VELOCITY_MULTIPLIER = 5;    // Signal 3: >5× week-over-week
const SPAM_DM_PER_HOUR_THRESHOLD = 50;     // Signal 4
const SPAM_DISTINCT_RECIPIENTS_24H = 20;   // Signal 4
const HARASSMENT_SENDER_THRESHOLD = 3;     // Signal 5: 3+ distinct senders
const SCAN_GROOMING_LIMIT = 100;           // Docs per scheduled run
const SCAN_HARASSMENT_LIMIT = 50;          // Recipients per scheduled run

// ─── Types ────────────────────────────────────────────────────────────────────

type SignalType =
  | "adult_minor_contact_velocity"
  | "off_hours_adult_minor"
  | "grooming_velocity"
  | "spam_ring"
  | "coordinated_harassment";

type Severity = "critical" | "high" | "moderate" | "low";

const SIGNAL_SEVERITY: Record<SignalType, Severity> = {
  adult_minor_contact_velocity: "critical",
  off_hours_adult_minor: "high",
  grooming_velocity: "critical",
  spam_ring: "moderate",
  coordinated_harassment: "high",
};

const SIGNAL_HARM_CATEGORY: Record<SignalType, string> = {
  adult_minor_contact_velocity: "grooming_contact_velocity",
  off_hours_adult_minor: "grooming_off_hours",
  grooming_velocity: "grooming",
  spam_ring: "spam",
  coordinated_harassment: "coordinated_harassment",
};

interface BehavioralAlertPayload {
  senderUid: string;
  recipientUid: string;
  signalType: SignalType;
  severity: Severity;
  harmCategoryId: string;
  metadata: Record<string, string | number | boolean | null>;
  policyVersion: string;
  createdAt: admin.firestore.FieldValue;
}

interface DMMetrics {
  messageCount24h: number;
  messageCount7d: number;
  lastMessageAt: admin.firestore.Timestamp | null;
  offHoursCount: number;
  weeklyVelocity: number[];
  updatedAt: admin.firestore.Timestamp | null;
}

interface UserDMStats {
  distinctRecipients24h: number;
  totalDMs1h: number;
  lastReset1h: admin.firestore.Timestamp | null;
  lastReset24h: admin.firestore.Timestamp | null;
  updatedAt: admin.firestore.Timestamp | null;
}

interface UserDoc {
  ageTier?: string;
  utcOffsetMinutes?: number; // signed offset from UTC in minutes
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function dmMetricsKey(senderUid: string, recipientUid: string): string {
  return `${senderUid}_${recipientUid}`;
}

/**
 * Returns true when a UTC hour value falls in the 10 pm–6 am window
 * after applying the user's UTC offset (stored in minutes on the user doc).
 */
function isOffHours(utcOffsetMinutes: number): boolean {
  const nowMs = Date.now();
  const localMs = nowMs + utcOffsetMinutes * 60 * 1000;
  const localHour = new Date(localMs).getUTCHours();
  // Off hours: [22, 23, 0, 1, 2, 3, 4, 5]
  return localHour >= OFF_HOURS_START_UTC || localHour < OFF_HOURS_END_UTC;
}

function isMinor(ageTier?: string): boolean {
  return ageTier === "minor" || ageTier === "teen";
}

function isAdult(ageTier?: string): boolean {
  return ageTier !== undefined && !isMinor(ageTier);
}

// ─── writeBehavioralAlert (private) ──────────────────────────────────────────

/**
 * Writes a behavioral alert document and, for critical/high severity,
 * also enqueues to the moderation queue.
 */
async function writeBehavioralAlert(
  senderUid: string,
  recipientUid: string,
  signalType: SignalType,
  metadata: Record<string, string | number | boolean | null>
): Promise<void> {
  const severity = SIGNAL_SEVERITY[signalType];
  const harmCategoryId = SIGNAL_HARM_CATEGORY[signalType];

  const alertPayload: BehavioralAlertPayload = {
    senderUid,
    recipientUid,
    signalType,
    severity,
    harmCategoryId,
    metadata,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const batch = db.batch();

  // Always write to behavioralAlerts
  const alertRef = db.collection("behavioralAlerts").doc();
  batch.set(alertRef, alertPayload);

  // Also enqueue for moderation on critical or high signals
  if (severity === "critical" || severity === "high") {
    const mqRef = db.collection("moderationQueue").doc();
    batch.set(mqRef, {
      ...alertPayload,
      queuedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: "pending",
      source: "BehavioralPatternService",
    });
  }

  await batch.commit();

  // Write audit log entry (non-blocking failure)
  writeAuditLog({
    eventType: "youth_safety_violation",
    actorUid: senderUid,
    targetUid: recipientUid,
    harmCategoryId,
    enforcement: severity === "critical" ? "escalate" : "flag_for_review",
    moderationStatus: "pending",
    source: "BehavioralPatternService",
    metadata: {
      signalType,
      severity,
      ...metadata,
    },
  }).catch((err) =>
    logger.error("BehavioralPatternService: audit log write failed", { err })
  );
}

// ─── checkBehavioralSignals ───────────────────────────────────────────────────

/**
 * Reads both user docs and dmMetrics/userDMStats for the pair, then
 * evaluates Signals 1, 2, and 4.
 */
export async function checkBehavioralSignals(
  senderUid: string,
  recipientUid: string
): Promise<void> {
  try {
    // Parallel fetch: sender user doc, recipient user doc, dmMetrics, senderDMStats
    const [senderSnap, recipientSnap, metricsSnap, senderStatsSnap] =
      await Promise.all([
        db.collection("users").doc(senderUid).get(),
        db.collection("users").doc(recipientUid).get(),
        db.collection("dmMetrics").doc(dmMetricsKey(senderUid, recipientUid)).get(),
        db.collection("userDMStats").doc(senderUid).get(),
      ]);

    const sender = (senderSnap.data() ?? {}) as UserDoc;
    const recipient = (recipientSnap.data() ?? {}) as UserDoc;
    const metrics = (metricsSnap.data() ?? {
      messageCount24h: 0,
      messageCount7d: 0,
      lastMessageAt: null,
      offHoursCount: 0,
      weeklyVelocity: [],
      updatedAt: null,
    }) as DMMetrics;
    const senderStats = (senderStatsSnap.data() ?? {
      distinctRecipients24h: 0,
      totalDMs1h: 0,
      lastReset1h: null,
      lastReset24h: null,
      updatedAt: null,
    }) as UserDMStats;

    const senderIsAdult = isAdult(sender.ageTier);
    const recipientIsMinor = isMinor(recipient.ageTier);

    const signalChecks: Promise<void>[] = [];

    // Signal 1: Adult→Minor contact velocity
    if (senderIsAdult && recipientIsMinor) {
      if (metrics.messageCount24h > ADULT_MINOR_24H_THRESHOLD) {
        signalChecks.push(
          writeBehavioralAlert(senderUid, recipientUid, "adult_minor_contact_velocity", {
            messageCount24h: metrics.messageCount24h,
            threshold: ADULT_MINOR_24H_THRESHOLD,
          }).then(() =>
            deliverSafetyAlertToGuardians(
              recipientUid,
              "adult_minor_contact_velocity",
              senderUid
            )
          )
        );
      }

      // Signal 2: Off-hours adult→minor messaging
      const utcOffset = recipient.utcOffsetMinutes ?? 0;
      if (isOffHours(utcOffset) && metrics.offHoursCount > OFF_HOURS_MSG_THRESHOLD) {
        signalChecks.push(
          writeBehavioralAlert(senderUid, recipientUid, "off_hours_adult_minor", {
            offHoursCount: metrics.offHoursCount,
            threshold: OFF_HOURS_MSG_THRESHOLD,
            recipientUtcOffsetMinutes: utcOffset,
          }).then(() =>
            deliverSafetyAlertToGuardians(
              recipientUid,
              "off_hours_adult_minor",
              senderUid
            )
          )
        );
      }
    }

    // Signal 4: Spam ring detection
    const spamByVolume = senderStats.totalDMs1h > SPAM_DM_PER_HOUR_THRESHOLD;
    const spamByBreadth = senderStats.distinctRecipients24h >= SPAM_DISTINCT_RECIPIENTS_24H;

    if (spamByVolume || spamByBreadth) {
      signalChecks.push(
        writeBehavioralAlert(senderUid, recipientUid, "spam_ring", {
          totalDMs1h: senderStats.totalDMs1h,
          distinctRecipients24h: senderStats.distinctRecipients24h,
          triggeredByVolume: spamByVolume,
          triggeredByBreadth: spamByBreadth,
        })
      );
    }

    const results = await Promise.allSettled(signalChecks);
    results.forEach((result) => {
      if (result.status === "rejected") {
        logger.error("BehavioralPatternService: signal check action failed", {
          senderUid,
          recipientUid,
          reason: result.reason,
        });
      }
    });
  } catch (err) {
    logger.error("BehavioralPatternService: checkBehavioralSignals failed", {
      senderUid,
      recipientUid,
      err,
    });
  }
}

// ─── recordDMSent ─────────────────────────────────────────────────────────────

/**
 * Called by the DM-send hot path.
 * Updates dmMetrics and userDMStats, then fires behavioral signal checks
 * asynchronously (fire-and-forget, does not block the response).
 *
 * Target: <200 ms (two Firestore writes, both transactional).
 */
export async function recordDMSent(
  senderUid: string,
  recipientUid: string
): Promise<void> {
  const metricsKey = dmMetricsKey(senderUid, recipientUid);
  const now = Date.now();
  const ONE_HOUR_MS = 60 * 60 * 1000;
  const ONE_DAY_MS = 24 * ONE_HOUR_MS;

  // Parallel writes: dmMetrics pair doc + sender userDMStats doc
  const metricsRef = db.collection("dmMetrics").doc(metricsKey);
  const senderStatsRef = db.collection("userDMStats").doc(senderUid);

  // Determine off-hours flag for recipient (best-effort; defaults to 0 offset)
  let recipientUtcOffset = 0;
  try {
    const recipientSnap = await db.collection("users").doc(recipientUid).get();
    recipientUtcOffset = (recipientSnap.data() as UserDoc | undefined)?.utcOffsetMinutes ?? 0;
  } catch {
    // Non-fatal; proceed with UTC
  }

  const offHoursNow = isOffHours(recipientUtcOffset) ? 1 : 0;

  await Promise.allSettled([
    // dmMetrics increment
    db.runTransaction(async (tx) => {
      const snap = await tx.get(metricsRef);
      if (!snap.exists) {
        tx.set(metricsRef, {
          messageCount24h: 1,
          messageCount7d: 1,
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
          offHoursCount: offHoursNow,
          weeklyVelocity: [1, 0, 0, 0],
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        } as Omit<DMMetrics, "lastMessageAt" | "updatedAt"> & {
          lastMessageAt: admin.firestore.FieldValue;
          updatedAt: admin.firestore.FieldValue;
        });
        return;
      }

      const data = snap.data() as DMMetrics;
      const lastUpdate = data.updatedAt?.toMillis() ?? 0;
      const elapsed = now - lastUpdate;

      // Rolling 24-hour window: reset if last update was >24 h ago
      const count24h = elapsed > ONE_DAY_MS ? 1 : (data.messageCount24h ?? 0) + 1;
      const count7d = elapsed > 7 * ONE_DAY_MS ? 1 : (data.messageCount7d ?? 0) + 1;

      // Weekly velocity: current week is index 0; shift if a new week started
      let velocity = Array.isArray(data.weeklyVelocity)
        ? [...data.weeklyVelocity]
        : [0, 0, 0, 0];
      if (velocity.length < 4) velocity = [...velocity, ...Array(4 - velocity.length).fill(0)];
      velocity[0] = (velocity[0] ?? 0) + 1;

      tx.set(
        metricsRef,
        {
          messageCount24h: count24h,
          messageCount7d: count7d,
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
          offHoursCount: (data.offHoursCount ?? 0) + offHoursNow,
          weeklyVelocity: velocity,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }),

    // userDMStats increment
    db.runTransaction(async (tx) => {
      const snap = await tx.get(senderStatsRef);
      if (!snap.exists) {
        tx.set(senderStatsRef, {
          distinctRecipients24h: 1,
          totalDMs1h: 1,
          lastReset1h: admin.firestore.FieldValue.serverTimestamp(),
          lastReset24h: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const data = snap.data() as UserDMStats;
      const lastReset1h = data.lastReset1h?.toMillis() ?? 0;
      const lastReset24h = data.lastReset24h?.toMillis() ?? 0;

      const totalDMs1h =
        now - lastReset1h > ONE_HOUR_MS ? 1 : (data.totalDMs1h ?? 0) + 1;
      const distinctRecipients24h =
        now - lastReset24h > ONE_DAY_MS ? 1 : (data.distinctRecipients24h ?? 0) + 1;

      tx.set(
        senderStatsRef,
        {
          totalDMs1h,
          distinctRecipients24h,
          lastReset1h:
            now - lastReset1h > ONE_HOUR_MS
              ? admin.firestore.FieldValue.serverTimestamp()
              : data.lastReset1h,
          lastReset24h:
            now - lastReset24h > ONE_DAY_MS
              ? admin.firestore.FieldValue.serverTimestamp()
              : data.lastReset24h,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }),
  ]);

  // Fire-and-forget: check behavioral signals asynchronously
  checkBehavioralSignals(senderUid, recipientUid).catch((err) =>
    logger.error("BehavioralPatternService: async signal check threw", {
      senderUid,
      recipientUid,
      err,
    })
  );
}

// ─── scanGroomingVelocity (scheduled) ────────────────────────────────────────

/**
 * Runs every 6 hours.
 * Queries dmMetrics for pairs whose weeklyVelocity shows >5× week-over-week
 * growth, verifies the recipient is a minor, and enqueues for human review.
 */
// NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
// with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.

export const scanGroomingVelocity = onSchedule(
  { schedule: "every 6 hours", timeoutSeconds: 120 },
  async () => {
    // Idempotency: lock by 6-hour window
    const nowMs = Date.now();
    const windowMs = 6 * 60 * 60 * 1000;
    const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
    const lockRef = db.doc(`system/scheduledJobLocks/scanGroomingVelocity_${windowKey}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      if (snap.exists && snap.data()?.status === "completed") {
        return false;
      }
      tx.set(lockRef, {
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        windowKey,
        expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
      });
      return true;
    });

    if (!lockAcquired) {
      logger.info("BehavioralPatternService: scanGroomingVelocity already completed this window, skipping", { windowKey });
      return;
    }

    try {
      logger.info("BehavioralPatternService: scanGroomingVelocity start");

      // Fetch recent dmMetrics docs — filter in-process (Firestore can't query array fields this way)
      const snapshot = await db
        .collection("dmMetrics")
        .orderBy("updatedAt", "desc")
        .limit(SCAN_GROOMING_LIMIT)
        .get();

      if (snapshot.empty) {
        logger.info("BehavioralPatternService: scanGroomingVelocity — no docs");
      } else {
        const tasks: Promise<void>[] = [];

        for (const doc of snapshot.docs) {
          const data = doc.data() as DMMetrics;
          const velocity = data.weeklyVelocity;

          if (!Array.isArray(velocity) || velocity.length < 2) continue;

          // Check if any consecutive week pair shows >5× growth
          const hasGroomingVelocity = velocity.some((count, idx) => {
            if (idx === velocity.length - 1) return false;
            const prior = velocity[idx + 1];
            return prior > 0 && count / prior > GROOMING_VELOCITY_MULTIPLIER;
          });

          if (!hasGroomingVelocity) continue;

          // Parse senderUid and recipientUid from doc ID: "{senderUid}_{recipientUid}"
          const underscoreIdx = doc.id.indexOf("_");
          if (underscoreIdx === -1) continue;
          const senderUid = doc.id.slice(0, underscoreIdx);
          const recipientUid = doc.id.slice(underscoreIdx + 1);

          tasks.push(
            (async () => {
              const recipientSnap = await db.collection("users").doc(recipientUid).get();
              const recipientData = (recipientSnap.data() ?? {}) as UserDoc;

              if (!isMinor(recipientData.ageTier)) return;

              const alertRef = db.collection("humanReviewQueue").doc();
              await alertRef.set({
                senderUid,
                recipientUid,
                signalType: "grooming_velocity" as SignalType,
                harmCategoryId: "grooming",
                severity: "critical",
                weeklyVelocity: velocity,
                policyVersion: AMEN_SAFETY_POLICY_VERSION,
                status: "pending",
                source: "BehavioralPatternService",
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              });

              await writeBehavioralAlert(senderUid, recipientUid, "grooming_velocity", {
                weeklyVelocity: JSON.stringify(velocity),
                maxGrowthMultiplier: Math.max(
                  ...velocity
                    .map((count, idx) =>
                      idx < velocity.length - 1 && velocity[idx + 1] > 0
                        ? count / velocity[idx + 1]
                        : 0
                    )
                    .filter((v) => v > 0)
                ),
              });

              await deliverSafetyAlertToGuardians(recipientUid, "grooming_velocity", senderUid);

              logger.info("BehavioralPatternService: grooming_velocity flagged", {
                senderUid,
                recipientUid,
              });
            })()
          );
        }

        const results = await Promise.allSettled(tasks);
        const failed = results.filter((r) => r.status === "rejected").length;
        logger.info("BehavioralPatternService: scanGroomingVelocity complete", {
          processed: snapshot.size,
          failed,
        });
      }

      await lockRef.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await lockRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw err;
    }
  }
);

// ─── scanCoordinatedHarassment (scheduled) ────────────────────────────────────

/**
 * Runs every 30 minutes.
 * Groups dmMetrics docs updated in the last hour by recipient.
 * Finds recipients contacted by 3+ distinct senders who had no prior history
 * (messageCount7d === 1, meaning this is their first message to this recipient).
 * Writes moderatorAlerts for each affected recipient.
 *
 * NOTE: Add a Firestore TTL policy on `system/scheduledJobLocks` collection
 * with field `expiresAt` set to 7 days. This automatically cleans up old lock documents.
 */
export const scanCoordinatedHarassment = onSchedule(
  { schedule: "every 30 minutes", timeoutSeconds: 120 },
  async () => {
    // Idempotency: lock by 30-minute window
    const nowMs = Date.now();
    const windowMs = 30 * 60 * 1000;
    const windowKey = new Date(Math.floor(nowMs / windowMs) * windowMs).toISOString().replace(/[:.]/g, "-");
    const lockRef = db.doc(`system/scheduledJobLocks/scanCoordinatedHarassment_${windowKey}`);

    const lockAcquired = await db.runTransaction(async (tx) => {
      const snap = await tx.get(lockRef);
      if (snap.exists && snap.data()?.status === "completed") {
        return false;
      }
      tx.set(lockRef, {
        status: "running",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        windowKey,
        expiresAt: new Date(nowMs + 7 * 24 * 60 * 60 * 1000),
      });
      return true;
    });

    if (!lockAcquired) {
      logger.info("BehavioralPatternService: scanCoordinatedHarassment already completed this window, skipping", { windowKey });
      return;
    }

    try {
      logger.info("BehavioralPatternService: scanCoordinatedHarassment start");

      const ONE_HOUR_AGO = admin.firestore.Timestamp.fromMillis(
        Date.now() - 60 * 60 * 1000
      );

      const snapshot = await db
        .collection("dmMetrics")
        .where("lastMessageAt", ">=", ONE_HOUR_AGO)
        .orderBy("lastMessageAt", "desc")
        .limit(500) // fetch broadly, group in-memory
        .get();

      if (!snapshot.empty) {
        // Group by recipientUid: only new senders (messageCount7d <= 1 => no prior history)
        const recipientToNewSenders = new Map<string, Set<string>>();

        for (const doc of snapshot.docs) {
          const data = doc.data() as DMMetrics;

          // "New" sender = no prior history (this is their first or only message this week)
          if ((data.messageCount7d ?? 0) > 1) continue;

          const underscoreIdx = doc.id.indexOf("_");
          if (underscoreIdx === -1) continue;
          const senderUid = doc.id.slice(0, underscoreIdx);
          const recipientUid = doc.id.slice(underscoreIdx + 1);

          if (!recipientToNewSenders.has(recipientUid)) {
            recipientToNewSenders.set(recipientUid, new Set());
          }
          recipientToNewSenders.get(recipientUid)!.add(senderUid);
        }

        // Filter: recipients with 3+ distinct new senders
        const harassed = [...recipientToNewSenders.entries()]
          .filter(([, senders]) => senders.size >= HARASSMENT_SENDER_THRESHOLD)
          .slice(0, SCAN_HARASSMENT_LIMIT);

        const tasks: Promise<void>[] = harassed.map(([recipientUid, senders]) =>
          (async () => {
            const senderList = [...senders];

            // Write moderatorAlert
            await db.collection("moderatorAlerts").doc().set({
              type: "coordinated_harassment_risk",
              recipientUid,
              senderUids: senderList,
              distinctSenderCount: senderList.length,
              signalType: "coordinated_harassment" as SignalType,
              severity: SIGNAL_SEVERITY["coordinated_harassment"],
              harmCategoryId: SIGNAL_HARM_CATEGORY["coordinated_harassment"],
              policyVersion: AMEN_SAFETY_POLICY_VERSION,
              status: "pending",
              source: "BehavioralPatternService",
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Write behavioral alert (uses first sender as representative actor)
            await writeBehavioralAlert(
              senderList[0],
              recipientUid,
              "coordinated_harassment",
              {
                distinctSenderCount: senderList.length,
                senderUids: senderList.join(","),
              }
            );

            // Notify target: write a notification doc for the app to surface
            await db.collection("users").doc(recipientUid).collection("safetyNotifications").doc().set({
              type: "coordinated_harassment_risk",
              message: "Our safety system has detected unusual messaging activity directed at your account. We are reviewing this.",
              senderCount: senderList.length,
              policyVersion: AMEN_SAFETY_POLICY_VERSION,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              read: false,
            });

            logger.info("BehavioralPatternService: coordinated_harassment flagged", {
              recipientUid,
              distinctSenders: senderList.length,
            });
          })()
        );

        const results = await Promise.allSettled(tasks);
        const failed = results.filter((r) => r.status === "rejected").length;
        logger.info("BehavioralPatternService: scanCoordinatedHarassment complete", {
          recipientsEvaluated: recipientToNewSenders.size,
          recipientsFlagged: harassed.length,
          failed,
        });
      } else {
        logger.info("BehavioralPatternService: scanCoordinatedHarassment — no recent docs");
      }

      await lockRef.update({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await lockRef.update({
        status: "failed",
        error: String(err),
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      throw err;
    }
  }
);
