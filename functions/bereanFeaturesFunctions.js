/**
 * bereanFeaturesFunctions.js
 * AMEN App — Berean AI Feature Cloud Functions
 *
 * Features:
 *  1. dailyVerseDrop       — onSchedule daily 7am CT: personalized verse push to all users
 *  2. weeklyPrayerRecap    — onSchedule Sunday 8pm CT: AI prayer journal recap
 *  3. generatePrayerRecap  — onCall: on-demand prayer recap for current user
 */

'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const Anthropic = require('@anthropic-ai/sdk');

const CLAUDE_API_KEY = defineSecret('CLAUDE_API_KEY');
const db = admin.firestore;  // Use lazy accessor to avoid double-init

// ─── Helpers ──────────────────────────────────────────────────────────────────

function claudeClient(apiKey) {
  return new Anthropic({ apiKey });
}

async function callClaudeSDK(apiKey, system, userMessage, maxTokens = 1000) {
  const client = claudeClient(apiKey);
  const response = await client.messages.create({
    model: 'claude-opus-4-5',
    max_tokens: maxTokens,
    system,
    messages: [{ role: 'user', content: userMessage }],
  });
  return response.content[0].text;
}

function parseJSON(raw) {
  const cleaned = raw
    .replace(/```json/g, '')
    .replace(/```/g, '')
    .trim();
  return JSON.parse(cleaned);
}

async function sendPushNotificationToken(token, title, body, data = {}) {
  if (!token) return;
  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data,
      apns: { payload: { aps: { sound: 'default', badge: 1 } } },
    });
  } catch (err) {
    console.warn('Push failed for token:', token, err.message);
  }
}

function buildUserContext(user) {
  const parts = [];
  if (user.currentSeason) parts.push(`Current season: ${user.currentSeason}`);
  if (user.faithStage) parts.push(`Faith stage: ${user.faithStage}`);
  if (user.primaryNeed) parts.push(`Primary need: ${user.primaryNeed}`);
  if (user.feedTopics?.length) parts.push(`Interests: ${user.feedTopics.join(', ')}`);
  if (user.recentPrayerThemes?.length) parts.push(`Recent prayer themes: ${user.recentPrayerThemes.join(', ')}`);
  return parts.length > 0 ? parts.join('\n') : 'General user — no specific context available yet.';
}

function buildDailyVersePrompt(context) {
  return `You are AMEN Berean AI — a spiritually wise, deeply biblical, and culturally aware AI companion.

Your task is to generate a personalized daily Scripture drop for this user.

USER CONTEXT:
${context}

INSTRUCTIONS:
- Choose ONE Scripture verse that speaks directly to this user's current season, struggles, or themes.
- Do not pick generic, overused verses (avoid John 3:16, Jeremiah 29:11 unless truly fitting).
- Be specific. Be surprising. Be prophetic.
- Return ONLY valid JSON. No preamble, no markdown, no explanation.

RESPONSE FORMAT:
{
  "reference": "Book Chapter:Verse",
  "verse": "Full verse text (ESV preferred)",
  "hook": "One punchy sentence (max 12 words) that makes them HAVE to open the app",
  "reflection": "2-3 sentences of personal, warm, wisdom-rich reflection tied to their context",
  "prayer": "One short, honest, conversational prayer (2-3 sentences)"
}`;
}

function buildPrayerRecapPrompt(prayers, userName) {
  return `You are AMEN Berean AI — a gentle, wise, and spiritually perceptive companion who has been walking alongside ${userName} all week.

You have access to their prayer journal entries from the past 7 days. Your job is to synthesize their week into a meaningful, personalized spiritual recap.

PRAYER ENTRIES THIS WEEK:
${prayers}

INSTRUCTIONS:
- Read between the lines. Notice what they keep coming back to. Identify the emotional undercurrent.
- Be warm, personal, and pastoral — not clinical or generic.
- If prayers were answered or progressed, celebrate it specifically.
- Speak to them like a trusted mentor who has been praying WITH them all week.
- Return ONLY valid JSON. No preamble, no markdown, no explanation.

RESPONSE FORMAT:
{
  "greeting": "Personal, warm 1-sentence opener using their name",
  "themes": ["theme1", "theme2", "theme3"],
  "themesSummary": "2-3 sentences summarizing the spiritual thread of their week",
  "answeredPrayers": "1-2 sentences acknowledging any progress or answered prayers",
  "burden": "1-2 sentences naming the heaviest thing they carried this week, with empathy",
  "scripture": {
    "reference": "Book Chapter:Verse",
    "verse": "Full verse text",
    "connection": "1 sentence connecting this verse directly to their week"
  },
  "word": "A 2-3 sentence prophetic encouragement for the week ahead",
  "closingPrayer": "A short, sincere 3-4 sentence prayer for them going into the new week"
}`;
}

// ─── 1. Daily Verse Drop ──────────────────────────────────────────────────────

exports.dailyVerseDrop = onSchedule(
  {
    schedule: '0 7 * * *',
    timeZone: 'America/Chicago',
    secrets: [CLAUDE_API_KEY],
    timeoutSeconds: 300,
    memory: '512MiB',
    region: 'us-central1',
  },
  async () => {
    const apiKey = CLAUDE_API_KEY.value();
    const firestore = admin.firestore();
    console.log('🌅 Daily Verse Drop starting...');

    const usersSnap = await firestore.collection('users')
      .where('notificationsEnabled', '==', true)
      .where('dailyVerseEnabled', '==', true)
      .limit(500)
      .get();

    console.log(`Processing ${usersSnap.size} users...`);

    const promises = usersSnap.docs.map(async (doc) => {
      const user = doc.data();
      const userId = doc.id;

      try {
        const context = buildUserContext(user);
        const raw = await callClaudeSDK(apiKey, buildDailyVersePrompt(context),
          'Generate today\'s personalized verse drop.', 600);
        const verse = parseJSON(raw);

        await firestore.collection('users').doc(userId)
          .collection('dailyVerses')
          .add({
            ...verse,
            generatedAt: admin.firestore.Timestamp.now(),
            date: new Date().toISOString().split('T')[0],
          });

        await firestore.collection('users').doc(userId).update({
          todayVerse: verse,
          todayVerseDate: admin.firestore.Timestamp.now(),
        });

        if (user.fcmToken) {
          await sendPushNotificationToken(user.fcmToken, verse.reference, verse.hook, {
            type: 'daily_verse',
          });
        }
        console.log(`✅ Verse sent to ${userId}: ${verse.reference}`);
      } catch (err) {
        console.error(`❌ Failed for ${userId}:`, err.message);
      }
    });

    await Promise.allSettled(promises);
    console.log('🌅 Daily Verse Drop complete.');
  }
);

// ─── 2. Weekly Prayer Recap ───────────────────────────────────────────────────

exports.weeklyPrayerRecap = onSchedule(
  {
    schedule: '0 20 * * 0',
    timeZone: 'America/Chicago',
    secrets: [CLAUDE_API_KEY],
    timeoutSeconds: 540,
    memory: '512MiB',
    region: 'us-central1',
  },
  async () => {
    const apiKey = CLAUDE_API_KEY.value();
    const firestore = admin.firestore();
    console.log('📖 Weekly Prayer Recap starting...');

    const usersSnap = await firestore.collection('users')
      .where('notificationsEnabled', '==', true)
      .where('prayerRecapEnabled', '==', true)
      .limit(500)
      .get();

    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const promises = usersSnap.docs.map(async (doc) => {
      const user = doc.data();
      const userId = doc.id;

      try {
        const prayersSnap = await firestore.collection('users').doc(userId)
          .collection('prayers')
          .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
          .orderBy('createdAt', 'desc')
          .limit(30)
          .get();

        if (prayersSnap.empty) {
          console.log(`Skipping ${userId} — no prayers this week`);
          return;
        }

        const prayerText = prayersSnap.docs.map((p) => {
          const prayer = p.data();
          const date = prayer.createdAt.toDate().toLocaleDateString('en-US', { weekday: 'long' });
          return `[${date}] ${prayer.content || prayer.text || ''}${prayer.answered ? ' (marked as answered)' : ''}`;
        }).join('\n\n');

        const userName = user.displayName || user.name || 'friend';
        const raw = await callClaudeSDK(apiKey, buildPrayerRecapPrompt(prayerText, userName),
          'Generate my weekly prayer recap.', 1200);
        const recap = parseJSON(raw);

        const recapRef = await firestore.collection('users').doc(userId)
          .collection('weeklyRecaps')
          .add({
            ...recap,
            generatedAt: admin.firestore.Timestamp.now(),
            weekOf: sevenDaysAgo.toISOString().split('T')[0],
            prayerCount: prayersSnap.size,
          });

        await firestore.collection('users').doc(userId).update({
          latestRecap: recap,
          latestRecapDate: admin.firestore.Timestamp.now(),
          latestRecapId: recapRef.id,
        });

        if (user.fcmToken) {
          await sendPushNotificationToken(
            user.fcmToken,
            'Your Week in Faith is Ready ✦',
            `${prayersSnap.size} prayers. Here's what God's been doing.`,
            { type: 'prayer_recap', recapId: recapRef.id }
          );
        }
        console.log(`✅ Recap sent to ${userId} (${prayersSnap.size} prayers)`);
      } catch (err) {
        console.error(`❌ Failed for ${userId}:`, err.message);
      }
    });

    await Promise.allSettled(promises);
    console.log('📖 Weekly Prayer Recap complete.');
  }
);

// ─── 3. Generate Prayer Recap (callable) ─────────────────────────────────────

exports.generatePrayerRecap = onCall(
  {
    secrets: [CLAUDE_API_KEY],
    region: 'us-central1',
    enforceAppCheck: false,
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) throw new Error('Unauthenticated');

    const apiKey = CLAUDE_API_KEY.value();
    const firestore = admin.firestore();

    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const prayersSnap = await firestore.collection('users').doc(userId)
      .collection('prayers')
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
      .orderBy('createdAt', 'desc')
      .limit(30)
      .get();

    if (prayersSnap.empty) {
      return { error: 'no_prayers', message: 'No prayers found this week.' };
    }

    const userDoc = await firestore.collection('users').doc(userId).get();
    const user = userDoc.data() || {};
    const userName = user.displayName || user.name || 'friend';

    const prayerText = prayersSnap.docs.map((p) => {
      const prayer = p.data();
      const date = prayer.createdAt.toDate().toLocaleDateString('en-US', { weekday: 'long' });
      return `[${date}] ${prayer.content || prayer.text || ''}${prayer.answered ? ' (marked as answered)' : ''}`;
    }).join('\n\n');

    const raw = await callClaudeSDK(apiKey, buildPrayerRecapPrompt(prayerText, userName),
      'Generate my weekly prayer recap.', 1200);
    const recap = parseJSON(raw);

    const recapRef = await firestore.collection('users').doc(userId)
      .collection('weeklyRecaps')
      .add({ ...recap, generatedAt: admin.firestore.Timestamp.now() });

    return { recap, recapId: recapRef.id };
  }
);
