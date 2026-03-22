/**
 * messages_features.js
 *
 * Cloud Functions for AMEN Messages features 01–10.
 *
 * Feature 01: onPrayerChainUpdated       — notify requester when prayedBy grows
 * Feature 04: processTimeCapsules        — hourly scheduler, unseals delivered capsules
 * Feature 05: sendWeeklyAccountabilityCheckIn — Monday 8AM, streak updates + Claude prompt
 * Feature 07: revealGraceDropIdentity    — HTTP callable, reveal anonymous sender
 * Feature 08: analyzeThreadsForRevival   — daily 7AM, write revivalNudges docs
 * Feature 10: notifyPrayerRoomAnswered   — callable, FCM fan-out to prayedLog members
 */

'use strict';

const { onCall, HttpsError }    = require('firebase-functions/v2/https');
const { onDocumentUpdated }     = require('firebase-functions/v2/firestore');
const { onSchedule }            = require('firebase-functions/v2/scheduler');
const admin                     = require('firebase-admin');

const db      = admin.firestore();
const REGION  = 'us-central1';

// ─── Anthropic helper ────────────────────────────────────────────────────────
const https = require('https');

function claudeRequest(messages, maxTokens = 512) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model:      'claude-sonnet-4-6',
      max_tokens: maxTokens,
      messages,
    });

    const req = https.request(
      {
        hostname: 'api.anthropic.com',
        path:     '/v1/messages',
        method:   'POST',
        headers: {
          'Content-Type':      'application/json',
          'x-api-key':         process.env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
          'Content-Length':    Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            const text   = parsed?.content?.[0]?.text || '';
            resolve(text);
          } catch (e) { reject(e); }
        });
      }
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ─── Safe FCM send with stale-token cleanup ───────────────────────────────────
async function safeSend(userId, token, message) {
  try {
    await admin.messaging().send({ ...message, token });
    return true;
  } catch (err) {
    if (
      err.code === 'messaging/registration-token-not-registered' ||
      err.code === 'messaging/invalid-registration-token'
    ) {
      await db.collection('users').doc(userId)
        .update({ fcmToken: admin.firestore.FieldValue.delete() });
    }
    return false;
  }
}

// =============================================================================
// FEATURE 01 — Prayer Chain Relay
// Firestore trigger: messages/{threadId}/prayerChains/{chainId}
// Fires when prayedBy array grows. Notifies the requester with who just prayed.
// =============================================================================
exports.onPrayerChainUpdated = onDocumentUpdated(
  {
    document: 'messages/{threadId}/prayerChains/{chainId}',
    region: REGION,
  },
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    const beforePrayedBy = before?.prayedBy || [];
    const afterPrayedBy  = after?.prayedBy  || [];

    // Only proceed if prayedBy grew
    if (afterPrayedBy.length <= beforePrayedBy.length) return null;

    // Find the newly added prayer(s)
    const newPrayers = afterPrayedBy.filter((uid) => !beforePrayedBy.includes(uid));
    if (newPrayers.length === 0) return null;

    const requesterId = after.requesterId;
    const newPrayerId = newPrayers[0];

    if (newPrayerId === requesterId) return null; // Don't notify self

    try {
      // Fetch the new prayer-er's name
      const prayerDoc = await db.collection('users').doc(newPrayerId).get();
      const prayerName = prayerDoc.data()?.displayName || 'Someone';
      const totalCount = afterPrayedBy.length;

      // In-app notification
      await db.collection('users').doc(requesterId).collection('notifications').add({
        type:        'prayer_chain_update',
        actorId:     newPrayerId,
        actorName:   prayerName,
        chainId:     event.params.chainId,
        threadId:    event.params.threadId,
        prayedCount: totalCount,
        read:        false,
        createdAt:   admin.firestore.FieldValue.serverTimestamp(),
      });

      // Push notification
      const requesterDoc = await db.collection('users').doc(requesterId).get();
      const fcmToken     = requesterDoc.data()?.fcmToken;
      if (fcmToken) {
        await safeSend(requesterId, fcmToken, {
          notification: {
            title: `${totalCount} ${totalCount === 1 ? 'person has' : 'people have'} prayed for you 🙏`,
            body:  `${prayerName} just prayed for your request.`,
          },
          data: {
            type:     'prayer_chain_update',
            threadId: event.params.threadId,
            chainId:  event.params.chainId,
            deepLink: `amen://messages/${event.params.threadId}`,
          },
        });
      }

      return null;
    } catch (err) {
      console.error('❌ onPrayerChainUpdated:', err);
      return null;
    }
  }
);

// =============================================================================
// FEATURE 04 — Time Capsule: Process Sealed Capsules
// Runs every hour. Finds sealed capsules whose deliverAt <= now.
// Updates status to "delivered" and sends FCM to recipient.
// =============================================================================
exports.processTimeCapsules = onSchedule(
  { schedule: '0 * * * *', timeZone: 'UTC', region: REGION }, // Every hour
  async () => {
    const now = admin.firestore.Timestamp.now();

    console.log('⏳ Processing time capsules...');

    try {
      const snap = await db.collectionGroup('messages')
        .where('isTimeCapsule', '==', true)
        .where('status', '==', 'sealed')
        .where('deliverAt', '<=', now)
        .limit(100)
        .get();

      let deliveredCount = 0;

      for (const msgDoc of snap.docs) {
        const msg          = msgDoc.data();
        const senderId     = msg.senderId;
        const recipientId  = msg.recipientId;

        if (!recipientId) continue;

        // Mark as delivered
        await msgDoc.ref.update({
          status:      'delivered',
          deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
          // Clear obfuscation flag so client shows real content
          sealedContent: admin.firestore.FieldValue.delete(),
        });

        // Fetch sender name
        const senderDoc  = await db.collection('users').doc(senderId).get();
        const senderName = senderDoc.data()?.displayName || 'Someone';

        // In-app notification for recipient
        await db.collection('users').doc(recipientId).collection('notifications').add({
          type:        'time_capsule_delivered',
          actorId:     senderId,
          actorName:   senderName,
          messageId:   msgDoc.id,
          read:        false,
          createdAt:   admin.firestore.FieldValue.serverTimestamp(),
        });

        // Push to recipient
        const recipientDoc = await db.collection('users').doc(recipientId).get();
        const fcmToken     = recipientDoc.data()?.fcmToken;
        if (fcmToken) {
          await safeSend(recipientId, fcmToken, {
            notification: {
              title: '💌 A message just opened for you',
              body:  `${senderName} left this for you`,
            },
            data: {
              type:     'time_capsule_delivered',
              deepLink: `amen://messages/${msgDoc.ref.parent.parent?.id || ''}`,
            },
          });
        }

        deliveredCount++;
      }

      console.log(`✅ Time capsules delivered: ${deliveredCount}`);
    } catch (err) {
      console.error('❌ processTimeCapsules:', err);
    }
  }
);

// =============================================================================
// FEATURE 05 — Accountability Thread: Weekly Check-in
// Runs every Monday at 8:00 AM UTC.
// Updates streaks, generates Claude check-in question, sends FCM to members.
// =============================================================================
exports.sendWeeklyAccountabilityCheckIn = onSchedule(
  { schedule: '0 8 * * 1', timeZone: 'UTC', region: REGION }, // Mon 8AM
  async () => {
    console.log('🤝 Running Weekly Accountability Check-in...');

    const now    = new Date();
    const weekId = `${now.getUTCFullYear()}_W${Math.ceil(now.getUTCDate() / 7)}`;
    const lastWeekId = `${now.getUTCFullYear()}_W${Math.max(1, Math.ceil(now.getUTCDate() / 7) - 1)}`;

    try {
      const threadsSnap = await db.collection('accountabilityThreads').get();
      let processedCount = 0;

      for (const threadDoc of threadsSnap.docs) {
        const thread  = threadDoc.data();
        const members = thread.members || [];
        if (members.length === 0) continue;

        // ── Update streaks based on last week's check-ins ──────────────
        const streakUpdates = {};
        for (const uid of members) {
          const lastWeekCheckIn = await db
            .collection('accountabilityThreads').doc(threadDoc.id)
            .collection('checkIns').doc(lastWeekId)
            .collection('responses').doc(uid)
            .get();

          const currentStreak = thread.streaks?.[uid] ?? 0;
          streakUpdates[`streaks.${uid}`] = lastWeekCheckIn.exists
            ? currentStreak + 1
            : 0;
        }

        await threadDoc.ref.update(streakUpdates);

        // ── Generate Claude check-in question ──────────────────────────
        // Fetch last 3 weeks of responses as context
        const recentResponses = [];
        for (let w = 1; w <= 3; w++) {
          const wId    = `${now.getUTCFullYear()}_W${Math.max(1, Math.ceil(now.getUTCDate() / 7) - w)}`;
          const wSnap  = await db
            .collection('accountabilityThreads').doc(threadDoc.id)
            .collection('checkIns').doc(wId)
            .get();
          if (wSnap.exists) recentResponses.push(JSON.stringify(wSnap.data()));
        }

        const context = recentResponses.join('\n');
        let question  = `How are you progressing toward: "${thread.goalTitle}"?`;

        try {
          const claudeText = await claudeRequest([{
            role:    'user',
            content: `Based on this accountability goal and recent check-in history, generate one personalized, encouraging check-in question (max 25 words).\n\nGoal: ${thread.goalTitle}\n\nRecent responses:\n${context || 'No responses yet.'}`,
          }], 100);
          if (claudeText) question = claudeText.trim();
        } catch (claudeErr) {
          console.warn('[AccountabilityCheckIn] Claude error, using default question:', claudeErr.message);
        }

        // Write the prompt doc
        await db
          .collection('accountabilityThreads').doc(threadDoc.id)
          .collection('weeklyPrompts').doc(weekId)
          .set({
            question,
            weekId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

        // ── Push to all members ────────────────────────────────────────
        for (const uid of members) {
          const userDoc  = await db.collection('users').doc(uid).get();
          const fcmToken = userDoc.data()?.fcmToken;
          if (!fcmToken) continue;

          await safeSend(uid, fcmToken, {
            notification: {
              title: '📋 Weekly Check-in',
              body:  question.substring(0, 100),
            },
            data: {
              type:     'accountability_checkin',
              threadId: threadDoc.id,
              weekId,
              deepLink: `amen://messages/accountability/${threadDoc.id}`,
            },
          });
        }

        processedCount++;
      }

      console.log(`✅ Accountability check-ins sent for ${processedCount} threads`);
    } catch (err) {
      console.error('❌ sendWeeklyAccountabilityCheckIn:', err);
    }
  }
);

// =============================================================================
// FEATURE 07 — Anonymous Grace Drop: Reveal Identity
// HTTP callable. Takes threadId, reveals the anonymous sender,
// sends FCM to both parties, writes a system message.
// =============================================================================
exports.revealGraceDropIdentity = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Must be signed in');

  const { threadId } = request.data;
  if (!threadId) throw new HttpsError('invalid-argument', 'threadId required');

  try {
    // Find the anonymous drop message in this thread
    const messagesSnap = await db
      .collection('conversations').doc(threadId)
      .collection('messages')
      .where('isAnonymousDrop', '==', true)
      .where('revealed', '==', false)
      .limit(1)
      .get();

    if (messagesSnap.empty) {
      return { success: true, alreadyRevealed: true };
    }

    const msgDoc       = messagesSnap.docs[0];
    const msgData      = msgDoc.data();
    const realSenderId = msgData.realSenderId;

    if (!realSenderId) throw new HttpsError('not-found', 'Sender ID missing');

    // Reveal the message
    await msgDoc.ref.update({
      revealed:   true,
      revealedAt: admin.firestore.FieldValue.serverTimestamp(),
      senderId:   realSenderId,  // Expose real sender
    });

    // Write system message to thread
    await db.collection('conversations').doc(threadId)
      .collection('messages').add({
        type:      'system',
        text:      'Identity revealed ✓',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    // Fetch sender's display info
    const senderDoc  = await db.collection('users').doc(realSenderId).get();
    const senderData = senderDoc.data() || {};
    const senderName = senderData.displayName || 'Someone';

    // Notify the sender ("your identity was revealed")
    const senderToken = senderData.fcmToken;
    if (senderToken) {
      await safeSend(realSenderId, senderToken, {
        notification: {
          title: 'Your identity was revealed',
          body:  'Your identity was revealed — they said thank you 🙏',
        },
        data: { type: 'grace_drop_revealed', threadId, deepLink: `amen://messages/${threadId}` },
      });
    }

    // Notify the recipient ("you now know who encouraged you")
    const recipientId    = auth.uid;
    const recipientDoc   = await db.collection('users').doc(recipientId).get();
    const recipientToken = recipientDoc.data()?.fcmToken;
    if (recipientToken) {
      await safeSend(recipientId, recipientToken, {
        notification: {
          title: 'A mystery revealed 🙏',
          body:  `The person who encouraged you was ${senderName}`,
        },
        data: { type: 'grace_drop_revealed', threadId, deepLink: `amen://messages/${threadId}` },
      });
    }

    return { success: true, senderName };
  } catch (err) {
    console.error('❌ revealGraceDropIdentity:', err);
    throw new HttpsError('internal', err.message);
  }
});

// =============================================================================
// FEATURE 08 — Cold Thread Revival: Analyze Threads
// Runs daily at 7:00 AM UTC.
// For each user, finds threads silent 14–20 days with hardship keywords.
// Writes revivalNudges docs for client to display privately.
// =============================================================================
exports.analyzeThreadsForRevival = onSchedule(
  { schedule: '0 7 * * *', timeZone: 'UTC', region: REGION },
  async () => {
    const now             = Date.now();
    const fourteenDaysAgo = new Date(now - 14 * 24 * 60 * 60 * 1000);
    const twentyDaysAgo   = new Date(now - 20 * 24 * 60 * 60 * 1000);

    const HARDSHIP_KEYWORDS = [
      'lost', 'passed away', 'diagnosis', 'struggling',
      'fired', 'divorce', 'hospital', 'depressed',
      'grief', 'broken', 'scared', 'alone',
    ];

    console.log('🔍 Analyzing cold threads for revival nudges...');

    try {
      // Sample active users (those with a lastActiveAt in the last 7 days)
      const usersSnap = await db.collection('users')
        .where('lastActiveAt', '>=', admin.firestore.Timestamp.fromDate(
          new Date(now - 7 * 24 * 60 * 60 * 1000)
        ))
        .limit(300)
        .get();

      let nudgesWritten = 0;

      for (const userDoc of usersSnap.docs) {
        const userId = userDoc.id;

        // Query this user's conversations that have gone silent 14–20 days
        const threadsSnap = await db.collection('conversations')
          .where('participantIds', 'array-contains', userId)
          .where('lastMessageAt', '>=', admin.firestore.Timestamp.fromDate(twentyDaysAgo))
          .where('lastMessageAt', '<=', admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
          .limit(10)
          .get();

        for (const threadDoc of threadsSnap.docs) {
          const threadData = threadDoc.data();
          const lastContent = (threadData.lastMessageContent || '').toLowerCase();

          // Check for hardship signal
          const topic = HARDSHIP_KEYWORDS.find((kw) => lastContent.includes(kw));
          if (!topic) continue;

          // Find the other participant
          const participantIds = threadData.participantIds || [];
          const partnerId      = participantIds.find((id) => id !== userId);
          if (!partnerId) continue;

          const partnerDoc  = await db.collection('users').doc(partnerId).get();
          const partnerName = partnerDoc.data()?.displayName || 'a friend';

          const lastMsg  = threadData.lastMessageAt?.toDate?.() || new Date(0);
          const daysSilent = Math.round((now - lastMsg.getTime()) / (24 * 60 * 60 * 1000));

          // Write nudge doc (client reads this on app open)
          await db.collection('users').doc(userId)
            .collection('revivalNudges').doc(threadDoc.id)
            .set({
              partnerName,
              topic,
              daysSilent,
              shown:     false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });

          nudgesWritten++;
        }
      }

      console.log(`✅ Revival nudges written: ${nudgesWritten}`);
    } catch (err) {
      console.error('❌ analyzeThreadsForRevival:', err);
    }
  }
);

// =============================================================================
// FEATURE 10 — Prayer Room: Notify Answered
// HTTP callable — fires when thread creator marks prayer as answered.
// Sends FCM to all members in prayedLog.
// =============================================================================
exports.notifyPrayerRoomAnswered = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Must be signed in');

  const { threadId, authorName } = request.data;
  if (!threadId) throw new HttpsError('invalid-argument', 'threadId required');

  try {
    const prayedLogSnap = await db
      .collection('threads').doc(threadId)
      .collection('prayedLog')
      .get();

    let notifiedCount = 0;

    for (const prayerDoc of prayedLogSnap.docs) {
      const prayerId = prayerDoc.id;
      if (prayerId === auth.uid) continue; // Don't notify the author themselves

      // In-app notification
      await db.collection('users').doc(prayerId).collection('notifications').add({
        type:       'prayer_room_answered',
        actorId:    auth.uid,
        actorName:  authorName || 'Someone',
        threadId,
        read:       false,
        createdAt:  admin.firestore.FieldValue.serverTimestamp(),
      });

      const userDoc  = await db.collection('users').doc(prayerId).get();
      const fcmToken = userDoc.data()?.fcmToken;
      if (fcmToken) {
        const sent = await safeSend(prayerId, fcmToken, {
          notification: {
            title: '🙌 Prayer Answered!',
            body:  `${authorName || 'Someone'}'s prayer request has been answered 🙌`,
          },
          data: {
            type:     'prayer_room_answered',
            threadId,
            deepLink: `amen://messages/${threadId}`,
          },
        });
        if (sent) notifiedCount++;
      }
    }

    console.log(`✅ Prayer room answered: notified ${notifiedCount} members`);
    return { success: true, notifiedCount };
  } catch (err) {
    console.error('❌ notifyPrayerRoomAnswered:', err);
    throw new HttpsError('internal', err.message);
  }
});
