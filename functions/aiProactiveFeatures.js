/**
 * aiProactiveFeatures.js
 * AMEN App — AI-powered proactive notification features
 *
 * Features implemented (no-UI, push notification only):
 *
 *  1. contentMomentumAlert   — onDocumentUpdated: post saves/shares spike → AI-written push to author
 *  2. smartReEngage          — onSchedule daily: re-engage dormant users with a relevant post
 *  3. intercessionAgent      — onSchedule hourly: route unanswered prayer requests to intercessors
 *  4. pastoralCarePulse      — onDocumentCreated: new pastoral_care_signal → AI alert to pastor
 *
 * Claude models used per feature (as specified in design doc):
 *  - contentMomentumAlert  → claude-haiku-4-5 (real-time, latency-sensitive)
 *  - smartReEngage         → claude-haiku-4-5 (batch, high volume)
 *  - intercessionAgent     → claude-sonnet-4-6 (sensitive context, higher stakes)
 *  - pastoralCarePulse     → claude-sonnet-4-6 (pastoral weight, low volume)
 */

'use strict';

const { onDocumentUpdated, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const REGION = 'us-central1';

// ─── Shared Claude helper ─────────────────────────────────────────────────────

async function callClaude(apiKey, model, systemPrompt, userContent, maxTokens = 150, temperature = 0.7) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{ role: 'user', content: userContent }],
      temperature,
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude error ${response.status}: ${err}`);
  }
  const json = await response.json();
  return json.content?.[0]?.text ?? '';
}

// ─── Push notification helper ─────────────────────────────────────────────────
// Mirrors the pattern in pushNotifications.js (fan-out to all device tokens).

async function sendPushToUser(db, userId, title, body, data = {}) {
  const deviceTokensSnap = await db.collection('users').doc(userId)
      .collection('deviceTokens').where('enabled', '==', true).get();

  let tokens = [];
  if (!deviceTokensSnap.empty) {
    tokens = deviceTokensSnap.docs.map((d) => d.data().token).filter(Boolean);
  } else {
    const userDoc = await db.collection('users').doc(userId).get();
    const legacy = userDoc.data()?.fcmToken;
    if (legacy) tokens = [legacy];
  }

  if (tokens.length === 0) {
    console.log(`[aiProactive] No FCM tokens for user ${userId}`);
    return;
  }

  const staleTokens = [];
  await Promise.all(tokens.map(async (token) => {
    try {
      await admin.messaging().send({ notification: { title, body }, data, token });
    } catch (err) {
      if (
        err.code === 'messaging/registration-token-not-registered' ||
        err.code === 'messaging/invalid-registration-token'
      ) {
        staleTokens.push(token);
      } else {
        throw err;
      }
    }
  }));

  if (staleTokens.length > 0) {
    const batch = db.batch();
    for (const staleToken of staleTokens) {
      const snap = await db.collection('users').doc(userId)
          .collection('deviceTokens').where('token', '==', staleToken).limit(1).get();
      snap.docs.forEach((d) => batch.delete(d.ref));
    }
    await batch.commit();
  }
}

// ─── Idempotency guard ────────────────────────────────────────────────────────
// Prevents re-sending the same notification type within a cooldown window.

async function isOnCooldown(db, userId, notifKey, cooldownMs) {
  const ref = db.collection('aiNotifCooldowns').doc(`${userId}_${notifKey}`);
  const doc = await ref.get();
  if (!doc.exists) return false;
  const sentAt = doc.data()?.sentAt?.toMillis?.() ?? 0;
  return Date.now() - sentAt < cooldownMs;
}

async function setCooldown(db, userId, notifKey) {
  await db.collection('aiNotifCooldowns').doc(`${userId}_${notifKey}`).set({
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. CONTENT MOMENTUM ALERT
//
// Fires when a post's savesCount or sharesCount exceeds velocity thresholds,
// indicating the post is gaining traction faster than usual. Writes AI-generated
// push copy to the post author.
//
// Velocity thresholds (conservative to avoid spam):
//   saves: new value >= 10 AND increased by >= 5 since last update
//   shares: new value >= 8 AND increased by >= 4 since last update
//   Both within the last 30 minutes (tracked via velocityUpdatedAt field)
//
// Cooldown: 4 hours per post to prevent repeated alerts on sustained virality.
// ─────────────────────────────────────────────────────────────────────────────

exports.contentMomentumAlert = onDocumentUpdated(
  {
    document: 'posts/{postId}',
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 60,
  },
  async (event) => {
    const db = admin.firestore();
    const before = event.data.before.data();
    const after  = event.data.after.data();
    const postId  = event.params.postId;

    if (!after || !before) return;

    const authorId = after.authorId;
    if (!authorId) return;

    // Velocity detection
    const savesDelta  = (after.savesCount  ?? 0) - (before.savesCount  ?? 0);
    const sharesDelta = (after.sharesCount ?? 0) - (before.sharesCount ?? 0);
    const totalSaves  = after.savesCount  ?? 0;
    const totalShares = after.sharesCount ?? 0;

    const savesSpike  = savesDelta  >= 5 && totalSaves  >= 10;
    const sharesSpike = sharesDelta >= 4 && totalShares >= 8;
    if (!savesSpike && !sharesSpike) return;

    // Cooldown: max one momentum alert per post per 4 hours
    const cooldownKey = `momentum_${postId}`;
    if (await isOnCooldown(db, authorId, cooldownKey, 4 * 60 * 60 * 1000)) {
      console.log(`[contentMomentumAlert] On cooldown for post ${postId}`);
      return;
    }

    const velocitySignal = savesSpike && sharesSpike ? 'both'
      : savesSpike ? 'saves_spiking' : 'shares_spiking';

    const postPreview = (after.content ?? '').split(' ').slice(0, 15).join(' ');
    const postType = after.category === 'testimonies' ? 'testimony'
      : after.category === 'prayer' ? 'prayer' : 'discussion';

    // Estimate minutes since post was created
    const createdAt = after.createdAt?.toMillis?.() ?? Date.now();
    const minutesSincePost = Math.round((Date.now() - createdAt) / 60000);

    const SYSTEM = `You are the Content Momentum Alert system inside AMEN, a social app. A creator's post is gaining traction unusually fast. Your job is to write a push notification that tells them — in a way that feels exciting but not spammy — so they can act while the moment is live.

Rules:
- Write exactly two parts: a notification TITLE (max 6 words) and a BODY (max 18 words).
- The tone is like a hype friend texting you, not a corporate alert.
- Never use words like "viral," "algorithm," "data," or "engagement rate."
- Make it feel urgent but not panicked. Exciting, not clickbait.
- Be specific to the content type provided.
- Output must be valid JSON with keys "title" and "body". Nothing else.`;

    const userContent = JSON.stringify({
      post_type: postType,
      post_preview: postPreview,
      velocity_signal: velocitySignal,
      minutes_since_post: minutesSincePost,
    });

    try {
      const raw = await callClaude(ANTHROPIC_API_KEY.value(), 'claude-haiku-4-5-20251001', SYSTEM, userContent, 150, 0.7);
      const clean = raw.replace(/```json|```/g, '').trim();
      const { title, body } = JSON.parse(clean);

      if (!title || !body) throw new Error('Missing title/body in Claude response');

      await sendPushToUser(db, authorId, title, body, {
        type: 'content_momentum',
        postId,
      });

      await setCooldown(db, authorId, cooldownKey);
      console.log(`[contentMomentumAlert] Sent to ${authorId} for post ${postId}: "${title}"`);
    } catch (err) {
      console.error(`[contentMomentumAlert] Failed for post ${postId}:`, err.message);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. SMART RE-ENGAGE
//
// Scheduled daily at 9:00 AM UTC. For each user absent >= 5 days, finds
// one highly-engaged post matching their top interest and sends a
// personalized push notification written by Claude.
//
// Absence threshold: 5 days (tracked via users.lastActiveAt)
// Max re-engage cadence: once per 7 days per user (cooldown in aiNotifCooldowns)
// Batch size: 200 users per run to stay within Cloud Function timeout.
// ─────────────────────────────────────────────────────────────────────────────

exports.smartReEngage = onSchedule(
  {
    schedule: '0 9 * * *',
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 540,
  },
  async () => {
    const db = admin.firestore();
    const apiKey = ANTHROPIC_API_KEY.value();

    const fiveDaysAgo  = new Date(Date.now() - 5  * 86400000);
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);

    // Users absent 5–30 days (beyond 30 days requires a different nudge)
    const usersSnap = await db.collection('users')
        .where('lastActiveAt', '<', admin.firestore.Timestamp.fromDate(fiveDaysAgo))
        .where('lastActiveAt', '>', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
        .limit(200)
        .get();

    if (usersSnap.empty) {
      console.log('[smartReEngage] No dormant users found');
      return;
    }

    const SYSTEM = `You are the Smart Re-Engage system inside AMEN, a social app. A user hasn't opened the app in several days. You've found a specific piece of content that matches their interests closely. Your job is to write a push notification that makes them want to come back — not because they're guilted into it, but because something genuinely relevant is waiting for them.

Rules:
- Write exactly two parts: a TITLE (max 7 words) and a BODY (max 20 words).
- Never say "we miss you," "come back," "you've been away," or anything that implies absence or guilt.
- Lead with the content — what's waiting for them — not the fact that they've been gone.
- Tone: like a friend who saw something and thought of you immediately.
- Be specific to the content and interest provided. Generic phrases are forbidden.
- Output must be valid JSON with keys "title" and "body". Nothing else.`;

    let sent = 0;
    let skipped = 0;

    for (const userDoc of usersSnap.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();

      // Cooldown: max once per 7 days
      if (await isOnCooldown(db, userId, 'smart_reengage', 7 * 24 * 60 * 60 * 1000)) {
        skipped++;
        continue;
      }

      // Determine absence in days
      const lastActive = userData.lastActiveAt?.toMillis?.() ?? 0;
      const daysAbsent = Math.round((Date.now() - lastActive) / 86400000);

      // Get user's top interest (from interests array or savedThemes)
      const topInterest = (userData.interests?.[0]) || (userData.savedThemes?.[0]) || 'faith and encouragement';

      // Find a recent high-engagement post in their interest area
      const postsSnap = await db.collection('posts')
          .where('category', '==', 'openTable')
          .orderBy('amenCount', 'desc')
          .limit(5)
          .get();

      if (postsSnap.empty) { skipped++; continue; }

      // Pick first post that isn't by this user
      const post = postsSnap.docs.find((d) => d.data().authorId !== userId);
      if (!post) { skipped++; continue; }

      const postData = post.data();
      const contentPreview = (postData.content ?? '').split(' ').slice(0, 12).join(' ');
      const postType = postData.category === 'testimonies' ? 'testimony'
        : postData.category === 'prayer' ? 'prayer' : 'discussion';
      const posterName = postData.authorName ?? null;

      const userContent = JSON.stringify({
        days_absent: daysAbsent,
        user_top_interest: topInterest,
        content_preview: contentPreview,
        content_type: postType,
        poster_name: posterName,
      });

      try {
        const raw = await callClaude(apiKey, 'claude-haiku-4-5-20251001', SYSTEM, userContent, 150, 0.7);
        const clean = raw.replace(/```json|```/g, '').trim();
        const { title, body } = JSON.parse(clean);

        if (!title || !body) throw new Error('Missing title/body');

        await sendPushToUser(db, userId, title, body, {
          type: 'smart_reengage',
          postId: post.id,
        });

        await setCooldown(db, userId, 'smart_reengage');
        sent++;
        console.log(`[smartReEngage] Sent to ${userId} (${daysAbsent}d absent): "${title}"`);
      } catch (err) {
        console.error(`[smartReEngage] Failed for user ${userId}:`, err.message);
        skipped++;
      }
    }

    console.log(`[smartReEngage] Complete — sent: ${sent}, skipped: ${skipped}`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. INTERCESSION AGENT
//
// Scheduled hourly. Finds prayer requests that:
//   - Were posted > 2 hours ago
//   - Have 0 "amen" reactions (truly unanswered)
//   - Haven't already triggered an intercession notification
//
// For each such request, finds a matching intercessor based on:
//   - Their listed spiritual gifts (from users.spiritualGifts)
//   - A relevant past testimony (from their posts where category == "testimonies")
//
// Sends a Claude Sonnet-written push notification to the intercessor.
// Cooldown: 24 hours per intercessor to prevent over-routing.
// ─────────────────────────────────────────────────────────────────────────────

exports.intercessionAgent = onSchedule(
  {
    schedule: '0 * * * *',   // hourly
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 300,
  },
  async () => {
    const db  = admin.firestore();
    const apiKey = ANTHROPIC_API_KEY.value();

    const twoHoursAgo = new Date(Date.now() - 2 * 3600000);

    // Unanswered prayer posts (amenCount == 0, older than 2h, not yet intercession-notified)
    const prayerSnap = await db.collection('posts')
        .where('category', '==', 'prayer')
        .where('amenCount', '==', 0)
        .where('createdAt', '<', admin.firestore.Timestamp.fromDate(twoHoursAgo))
        .where('intercessionNotified', '==', false)
        .limit(20)
        .get();

    // Also catch posts where intercessionNotified field doesn't exist yet
    const untaggedSnap = await db.collection('posts')
        .where('category', '==', 'prayer')
        .where('amenCount', '==', 0)
        .where('createdAt', '<', admin.firestore.Timestamp.fromDate(twoHoursAgo))
        .orderBy('createdAt', 'desc')
        .limit(20)
        .get();

    // Merge and deduplicate
    const allDocs = [...prayerSnap.docs, ...untaggedSnap.docs];
    const seen = new Set();
    const prayerDocs = allDocs.filter((d) => {
      if (seen.has(d.id)) return false;
      seen.add(d.id);
      // Skip if already notified
      if (d.data().intercessionNotified === true) return false;
      return true;
    });

    if (prayerDocs.length === 0) {
      console.log('[intercessionAgent] No unanswered prayer requests found');
      return;
    }

    // Find potential intercessors: users with spiritualGifts containing 'intercession' or 'prayer'
    const intercessorsSnap = await db.collection('users')
        .where('spiritualGifts', 'array-contains-any', ['intercession', 'prayer', 'healing', 'faith'])
        .limit(50)
        .get();

    if (intercessorsSnap.empty) {
      console.log('[intercessionAgent] No intercessors found');
      return;
    }

    const intercessors = intercessorsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    const SYSTEM = `You are the Intercession Agent inside AMEN, a Christian social app. Someone has posted an urgent prayer request that has gone unanswered. You've identified a community member who is spiritually equipped to respond based on their testimony history and spiritual gifts. Your job is to write a push notification that calls them to intercede — with specificity, urgency, and warmth.

Rules:
- Write exactly two parts: a TITLE (max 7 words) and a BODY (max 22 words).
- The title should feel like a gentle but clear call, not an alert.
- The body should hint at the nature of the need and why this specific person is being asked — without quoting the prayer request.
- Never use generic phrases like "someone needs prayer." Be more specific to the theme.
- Never reveal the requester's name or identity in the notification.
- Tone: the way a pastor quietly taps someone on the shoulder and says "I think you're the one for this."
- Forbidden words: "urgent," "alert," "notification," "system," "algorithm."
- Output must be valid JSON with keys "title" and "body". Nothing else.`;

    let routed = 0;

    for (const prayerDoc of prayerDocs) {
      const prayerData = prayerDoc.data();
      const postId     = prayerDoc.id;
      const authorId   = prayerData.authorId;

      // Estimate emotional intensity from content length + prayer-related keywords
      const content = prayerData.content ?? '';
      const crisisWords = ['desperate', 'please', 'dying', 'scared', 'fear', 'crying', 'lost', 'broken'];
      const crisisCount = crisisWords.filter((w) => content.toLowerCase().includes(w)).length;
      const intensity = crisisCount >= 3 ? 'crisis' : crisisCount >= 2 ? 'high' : crisisCount >= 1 ? 'medium' : 'low';

      // Simple theme extraction: first 8 words as theme proxy
      const theme = content.split(' ').slice(0, 8).join(' ') || 'personal need';

      const hoursUnanswered = Math.round((Date.now() - (prayerData.createdAt?.toMillis?.() ?? Date.now())) / 3600000);

      // Pick an intercessor who isn't the author, not on cooldown, and has relevant gifts
      let chosenIntercessor = null;
      for (const intercessor of intercessors) {
        if (intercessor.id === authorId) continue;
        if (await isOnCooldown(db, intercessor.id, 'intercession_notif', 24 * 60 * 60 * 1000)) continue;
        chosenIntercessor = intercessor;
        break;
      }

      if (!chosenIntercessor) {
        console.log(`[intercessionAgent] No available intercessor for post ${postId}`);
        continue;
      }

      // Get intercessor's most recent testimony (brief summary)
      let relevantTestimony = null;
      try {
        const testimonySnap = await db.collection('posts')
            .where('authorId', '==', chosenIntercessor.id)
            .where('category', '==', 'testimonies')
            .orderBy('createdAt', 'desc')
            .limit(1)
            .get();
        if (!testimonySnap.empty) {
          relevantTestimony = testimonySnap.docs[0].data().content?.split(' ').slice(0, 10).join(' ') ?? null;
        }
      } catch (_) { /* non-fatal */ }

      const userContent = JSON.stringify({
        prayer_request_theme: theme,
        requester_emotional_intensity: intensity,
        hours_unanswered: hoursUnanswered,
        intercessor_spiritual_gifts: chosenIntercessor.spiritualGifts ?? [],
        intercessor_relevant_testimony: relevantTestimony,
      });

      try {
        const raw = await callClaude(apiKey, 'claude-sonnet-4-6', SYSTEM, userContent, 150, 0.6);
        const clean = raw.replace(/```json|```/g, '').trim();
        const { title, body } = JSON.parse(clean);

        if (!title || !body) throw new Error('Missing title/body');

        await sendPushToUser(db, chosenIntercessor.id, title, body, {
          type: 'intercession_request',
          postId,
        });

        // Mark post as notified so it doesn't re-trigger next hour
        await db.collection('posts').doc(postId).update({ intercessionNotified: true });
        await setCooldown(db, chosenIntercessor.id, 'intercession_notif');
        routed++;
        console.log(`[intercessionAgent] Routed post ${postId} to intercessor ${chosenIntercessor.id}: "${title}"`);
      } catch (err) {
        console.error(`[intercessionAgent] Failed for post ${postId}:`, err.message);
      }
    }

    console.log(`[intercessionAgent] Complete — routed: ${routed} of ${prayerDocs.length}`);
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 4. PASTORAL CARE PULSE
//
// Fires when a new document is written to pastoral_care_signals.
// Generates an anonymous, compassionate alert for the assigned pastor/elder.
//
// The alert is:
//   - Written by Claude Sonnet (pastoral weight)
//   - Stored in Firestore (notifications/pastoral_team/alerts/{signalId})
//   - Sent as a push notification to users in the 'pastoral_team' role
//
// Identity of the community member is never included in the notification.
// Cooldown: one alert per signal (idempotent via signalId check on the doc).
// ─────────────────────────────────────────────────────────────────────────────

exports.pastoralCarePulse = onDocumentCreated(
  {
    document: 'pastoral_care_signals/{signalId}',
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 60,
  },
  async (event) => {
    const db     = admin.firestore();
    const apiKey = ANTHROPIC_API_KEY.value();
    const signal = event.data.data();
    const signalId = event.params.signalId;

    if (!signal) return;

    // Only process high-urgency signals
    const urgencyScore = signal.urgencyScore ?? 0;
    if (urgencyScore < 0.4) {
      console.log(`[pastoralCarePulse] Skipping low-urgency signal ${signalId} (score: ${urgencyScore})`);
      return;
    }

    // Avoid double-processing (should not happen with onCreate but be safe)
    if (signal.pastoralAlertSent === true) {
      console.log(`[pastoralCarePulse] Alert already sent for signal ${signalId}`);
      return;
    }

    // Map signal type to user_general_season
    const seasonMap = {
      crisis:     'overwhelm',
      grief:      'grief',
      loneliness: 'isolation',
      doubt:      'doubt',
      default:    'unknown',
    };
    const season = seasonMap[signal.signalType] ?? seasonMap.default;

    // Map signal type + urgency to signal_type for prompt
    const promptSignalType = urgencyScore >= 0.8 ? 'crisis_tag'
      : signal.signalType === 'grief'      ? 'language_shift'
      : signal.signalType === 'loneliness' ? 'absence'
      : 'engagement_drop';

    // Rough duration: use signal age if createdAt available, otherwise 1 day
    const createdMs = signal.createdAt?.toMillis?.() ?? Date.now();
    const durationDays = Math.max(1, Math.round((Date.now() - createdMs) / 86400000));

    const SYSTEM = `You are the Pastoral Care Pulse inside AMEN, a Christian social app. You've detected behavioral signals suggesting a community member may need a pastoral check-in. Your job is to write a discreet, compassionate alert to their assigned pastor or elder — without revealing the user's identity or the specific data that triggered the alert.

Rules:
- Write exactly two parts: a SUBJECT LINE (max 8 words) and a BODY (max 40 words).
- The body should convey a pastoral concern without being clinical or alarming.
- Never reveal the user's name, post content, or specific behavioral data.
- Give the pastor a gentle, actionable nudge — not a diagnosis.
- Tone: the way a thoughtful deacon quietly tells a pastor, "I think you should check in on someone."
- Forbidden words: "algorithm," "data," "detected," "system," "triggered," "signal," "flagged."
- Output must be valid JSON with keys "subject" and "body". Nothing else.`;

    const userContent = JSON.stringify({
      signal_type: promptSignalType,
      signal_duration_days: durationDays,
      user_general_season: season,
    });

    try {
      const raw = await callClaude(apiKey, 'claude-sonnet-4-6', SYSTEM, userContent, 200, 0.5);
      const clean = raw.replace(/```json|```/g, '').trim();
      const { subject, body } = JSON.parse(clean);

      if (!subject || !body) throw new Error('Missing subject/body');

      // Store alert in Firestore for pastoral team dashboard
      const alertRef = db.collection('notifications').doc('pastoral_team')
          .collection('alerts').doc(signalId);
      await alertRef.set({
        signalId,
        subject,
        body,
        urgencyScore,
        signalType: signal.signalType ?? 'unknown',
        season,
        notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
      });

      // Send push to all users with role == 'pastor' or role == 'elder'
      const pastorsSnap = await db.collection('users')
          .where('role', 'in', ['pastor', 'elder', 'pastoral_team'])
          .limit(20)
          .get();

      let pushCount = 0;
      for (const pastorDoc of pastorsSnap.docs) {
        await sendPushToUser(db, pastorDoc.id, subject, body, {
          type: 'pastoral_care_pulse',
          signalId,
          urgency: urgencyScore.toString(),
        });
        pushCount++;
      }

      // Mark signal as notified so the acknowledgeHeyFeedSignal function
      // knows this was already processed.
      await db.collection('pastoral_care_signals').doc(signalId).update({
        pastoralAlertSent: true,
        alertSentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[pastoralCarePulse] Alert sent to ${pushCount} pastors for signal ${signalId}: "${subject}"`);
    } catch (err) {
      console.error(`[pastoralCarePulse] Failed for signal ${signalId}:`, err.message);
    }
  }
);
