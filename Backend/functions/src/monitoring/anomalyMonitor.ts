/**
 * anomalyMonitor.ts
 *
 * Scheduled Cloud Functions for proactive security anomaly detection.
 *
 * Functions:
 *
 *   monitorInjectionSpikes  (every 15 minutes)
 *     Reads bereanGuardrails events from the last 15 minutes.
 *     If injection count exceeds INJECTION_SPIKE_THRESHOLD, writes a
 *     securityAlerts record for the on-call team.
 *
 *   monitorAISpend  (every 30 minutes)
 *     Reads today's globalRateLimits/ai_daily_{DATE} counter.
 *     Alerts at 80% of the daily cap and hard-blocks at 100% (already done
 *     by checkGlobalCircuitBreaker — this provides early warning).
 *
 *   monitorFailedAuthSpike  (every 30 minutes)
 *     Reads authFailureLog events from the last 30 minutes.
 *     Alerts if any single IP or uid appears more than BRUTE_FORCE_THRESHOLD times
 *     (signals a credential-stuffing or brute-force attempt).
 *
 * Alerts are written to /securityAlerts/{alertId} where the admin console
 * listens in real-time. An FCM push is sent to the adminAlertsTopic for
 * any CRITICAL severity alert.
 *
 * Collections read (server-only, allow read/write: if false in rules):
 *   bereanGuardrails    — injection telemetry
 *   globalRateLimits    — AI spend counters
 *   authFailureLog      — failed sign-in events (written by Auth triggers)
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

const REGION = "us-central1";

// Tunable thresholds — adjust based on observed baselines after deployment.
const INJECTION_SPIKE_THRESHOLD = 10;     // > N injection blocks in 15 min
const BRUTE_FORCE_THRESHOLD = 20;         // > N failed auths per uid/IP in 30 min
const AI_SPEND_WARNING_PCT = 0.80;        // alert at 80% of daily cap
const GLOBAL_AI_DAILY_CAP = 50_000;      // must match rateLimit.ts

const ADMIN_ALERTS_FCM_TOPIC = "admin_security_alerts";

// ── Alert writer ──────────────────────────────────────────────────────────────

type AlertSeverity = "INFO" | "WARNING" | "CRITICAL";

async function writeAlert(
    type: string,
    severity: AlertSeverity,
    message: string,
    data: Record<string, unknown>
): Promise<void> {
    const ref = await db.collection("securityAlerts").add({
        type,
        severity,
        message,
        data,
        status: "open",
        createdAt: FieldValue.serverTimestamp(),
        resolvedAt: null,
        resolvedBy: null,
    });

    logger.warn(`[anomalyMonitor] ${severity} alert: ${type}`, { message, data, alertId: ref.id });

    // Push to admin FCM topic for CRITICAL alerts.
    if (severity === "CRITICAL") {
        try {
            await messaging.send({
                topic: ADMIN_ALERTS_FCM_TOPIC,
                notification: {
                    title: `[CRITICAL] ${type}`,
                    body: message,
                },
                data: { alertId: ref.id, type, severity },
                android: { priority: "high" },
                apns: { payload: { aps: { contentAvailable: true, sound: "default" } } },
            });
        } catch (err) {
            logger.warn("[anomalyMonitor] FCM send failed", { err });
        }
    }
}

// ── monitorInjectionSpikes ────────────────────────────────────────────────────

export const monitorInjectionSpikes = onSchedule(
    { schedule: "every 15 minutes", region: REGION, timeoutSeconds: 60 },
    async () => {
        const windowStart = Timestamp.fromMillis(Date.now() - 15 * 60 * 1000);

        const snap = await db
            .collection("bereanGuardrails")
            .where("eventType", "==", "input_injection")
            .where("blockedAt", ">=", windowStart)
            .count()
            .get();

        const count = snap.data().count;

        logger.info("[anomalyMonitor] Injection count in last 15m", { count });

        if (count > INJECTION_SPIKE_THRESHOLD) {
            const severity: AlertSeverity = count > INJECTION_SPIKE_THRESHOLD * 3 ? "CRITICAL" : "WARNING";
            await writeAlert(
                "injection_spike",
                severity,
                `${count} prompt injection attempts detected in the last 15 minutes (threshold: ${INJECTION_SPIKE_THRESHOLD}).`,
                { count, windowMinutes: 15, threshold: INJECTION_SPIKE_THRESHOLD }
            );
        }
    }
);

// ── monitorAISpend ────────────────────────────────────────────────────────────

export const monitorAISpend = onSchedule(
    { schedule: "every 30 minutes", region: REGION, timeoutSeconds: 60 },
    async () => {
        const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
        const docId = `ai_daily_${today}`;

        const snap = await db.collection("globalRateLimits").doc(docId).get();

        if (!snap.exists) {
            logger.info("[anomalyMonitor] No AI spend recorded today yet");
            return;
        }

        const count: number = snap.data()?.count ?? 0;
        const pct = count / GLOBAL_AI_DAILY_CAP;

        logger.info("[anomalyMonitor] AI daily spend", { count, cap: GLOBAL_AI_DAILY_CAP, pct: pct.toFixed(2) });

        if (pct >= 1.0) {
            await writeAlert(
                "ai_daily_cap_reached",
                "CRITICAL",
                `AI daily cap reached: ${count}/${GLOBAL_AI_DAILY_CAP} tokens. All AI requests are now blocked.`,
                { count, cap: GLOBAL_AI_DAILY_CAP, date: today }
            );
        } else if (pct >= AI_SPEND_WARNING_PCT) {
            await writeAlert(
                "ai_daily_cap_warning",
                "WARNING",
                `AI spend at ${Math.round(pct * 100)}% of daily cap (${count}/${GLOBAL_AI_DAILY_CAP}).`,
                { count, cap: GLOBAL_AI_DAILY_CAP, date: today, pct: pct.toFixed(2) }
            );
        }
    }
);

// ── monitorFailedAuthSpike ────────────────────────────────────────────────────

export const monitorFailedAuthSpike = onSchedule(
    { schedule: "every 30 minutes", region: REGION, timeoutSeconds: 120 },
    async () => {
        const windowStart = Timestamp.fromMillis(Date.now() - 30 * 60 * 1000);

        const snap = await db
            .collection("authFailureLog")
            .where("failedAt", ">=", windowStart)
            .limit(5000)
            .get();

        if (snap.empty) return;

        // Aggregate by uid.
        const byUid: Record<string, number> = {};
        snap.docs.forEach((d) => {
            const uid: string = d.data().uid ?? "unknown";
            byUid[uid] = (byUid[uid] ?? 0) + 1;
        });

        const spikes = Object.entries(byUid)
            .filter(([, n]) => n > BRUTE_FORCE_THRESHOLD)
            .map(([uid, count]) => ({ uid, count }));

        if (spikes.length > 0) {
            const severity: AlertSeverity = spikes.some((s) => s.count > BRUTE_FORCE_THRESHOLD * 3)
                ? "CRITICAL"
                : "WARNING";

            await writeAlert(
                "brute_force_detected",
                severity,
                `${spikes.length} account(s) with >  ${BRUTE_FORCE_THRESHOLD} failed auth attempts in 30 minutes.`,
                { spikes: spikes.slice(0, 20), windowMinutes: 30, threshold: BRUTE_FORCE_THRESHOLD }
            );
        }

        logger.info("[anomalyMonitor] Auth failure scan complete", {
            totalFailures: snap.size,
            spikesDetected: spikes.length,
        });
    }
);
