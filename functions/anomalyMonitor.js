// anomalyMonitor.js
// Scheduled Cloud Function that checks for spend and auth anomalies.
// Fires every hour. Writes alerts to Firestore at meta/anomalyAlerts/{alertId}.
// TODO: Wire alerts to Slack/email via a notification channel of your choice.

'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const { logger } = require('firebase-functions');

// ── Thresholds ──────────────────────────────────────────────────────────────
const THRESHOLDS = {
  // AI spend: alert if today's calls exceed 80% of the configured daily cap
  anthropicSpendWarning: 0.80,   // 80% of cap
  openaiSpendWarning: 0.80,

  // Auth: alert if sign-ins in the last hour exceed this count globally
  globalSignInsPerHour: 500,

  // Per-user: alert if a single user has >50 Berean calls in the last hour
  perUserBereanHourly: 50,
};

exports.hourlyAnomalyCheck = onSchedule('every 60 minutes', async () => {
  const db = admin.firestore();
  const now = new Date();
  const dayKey = now.toISOString().slice(0, 10);
  const hourKey = now.toISOString().slice(0, 13);
  const alerts = [];

  // ── 1. AI Spend anomaly ────────────────────────────────────────────────
  try {
    const [limitsSnap, costsSnap] = await Promise.all([
      db.doc('config/aiLimits').get(),
      db.doc(`meta/globalAICosts/daily/${dayKey}`).get(),
    ]);

    const limits = limitsSnap.exists ? limitsSnap.data() : {};
    const costs = costsSnap.exists ? costsSnap.data() : {};

    const anthropicCap = limits.anthropicDailyGlobalCap ?? 2000;
    const anthropicCalls = costs.anthropicCalls ?? 0;
    if (anthropicCalls >= anthropicCap * THRESHOLDS.anthropicSpendWarning) {
      alerts.push({
        type: 'ai_spend_warning',
        service: 'anthropic',
        current: anthropicCalls,
        cap: anthropicCap,
        pct: Math.round(anthropicCalls / anthropicCap * 100),
      });
    }

    const openaiCap = limits.openaiDailyGlobalCap ?? 5000;
    const openaiCalls = costs.openaiCalls ?? 0;
    if (openaiCalls >= openaiCap * THRESHOLDS.openaiSpendWarning) {
      alerts.push({
        type: 'ai_spend_warning',
        service: 'openai',
        current: openaiCalls,
        cap: openaiCap,
        pct: Math.round(openaiCalls / openaiCap * 100),
      });
    }
  } catch (e) {
    logger.error('[anomalyMonitor] spend check failed', e);
  }

  // ── 2. Auth rate anomaly ───────────────────────────────────────────────
  try {
    // We check the last 60 1-minute buckets by querying the collection
    const minuteSnap = await db.collection('meta/authMetrics/minutely')
      .where(admin.firestore.FieldPath.documentId(), '>=', `${dayKey}T${hourKey.slice(11)}:00`)
      .limit(60)
      .get();
    const totalSignIns = minuteSnap.docs.reduce((sum, d) => sum + (d.data().count ?? 0), 0);
    if (totalSignIns >= THRESHOLDS.globalSignInsPerHour) {
      alerts.push({
        type: 'auth_rate_anomaly',
        signInsLastHour: totalSignIns,
        threshold: THRESHOLDS.globalSignInsPerHour,
      });
    }
  } catch (e) {
    logger.error('[anomalyMonitor] auth rate check failed', e);
  }

  // ── 3. Per-user Berean call anomaly ────────────────────────────────────
  try {
    const oneHourAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60 * 60 * 1000)
    );
    const bereanCallsSnap = await db.collectionGroup('aiUsage')
      .where('service', '==', 'berean')
      .where('createdAt', '>=', oneHourAgo)
      .get();

    // Aggregate by userId
    const perUserCounts = {};
    for (const doc of bereanCallsSnap.docs) {
      const uid = doc.data().userId;
      if (!uid) continue;
      perUserCounts[uid] = (perUserCounts[uid] ?? 0) + 1;
    }

    for (const [uid, count] of Object.entries(perUserCounts)) {
      if (count >= THRESHOLDS.perUserBereanHourly) {
        alerts.push({
          type: 'per_user_berean_spike',
          userId: uid,
          callsLastHour: count,
          threshold: THRESHOLDS.perUserBereanHourly,
        });
      }
    }
  } catch (e) {
    logger.error('[anomalyMonitor] per-user Berean check failed', e);
  }

  // ── 4. Write alerts to Firestore ──────────────────────────────────────
  if (alerts.length > 0) {
    const batch = db.batch();
    for (const alert of alerts) {
      const ref = db.collection('meta/anomalyAlerts/alerts').doc();
      batch.set(ref, {
        ...alert,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'new',
        hourKey,
        dayKey,
      });
    }
    await batch.commit();
    logger.warn('[anomalyMonitor] alerts created', {
      count: alerts.length,
      types: alerts.map((a) => a.type),
    });
    // TODO: Send to Slack/email/PagerDuty webhook
    // Example:
    // await fetch(process.env.SLACK_WEBHOOK_URL, {
    //   method: 'POST',
    //   headers: { 'Content-Type': 'application/json' },
    //   body: JSON.stringify({
    //     text: `AMEN Anomaly Alert: ${alerts.length} alert(s) detected`,
    //     attachments: alerts.map(a => ({ text: JSON.stringify(a) })),
    //   }),
    // });
  } else {
    logger.info('[anomalyMonitor] no anomalies detected', { dayKey, hourKey });
  }
});
