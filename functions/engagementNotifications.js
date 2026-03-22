/**
 * engagementNotifications.js
 *
 * Engagement lifecycle notifications:
 *   #3  Testimony Anniversary   — daily scheduler, 1-year anniversary detection
 *   #4  Friend Returned         — daily scheduler, 14+ day gap detection, 30-day cap
 *   #6  Gentle Re-engagement    — Sunday-only scheduler, 7-day dormancy, 14-day cap
 *   #7  New Church Member       — Firestore trigger on users.churchId transition
 *   #10 Prayer Check-in         — Wednesday scheduler, 7-day-old prayers, 14-day cap
 */

'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const db = admin.firestore();
const REGION = 'us-central1';

// ─── Helper: safe FCM send with stale-token cleanup ──────────────────────────
async function safeSend(userId, token, message) {
  try {
    await admin.messaging().send({ ...message, token });
    return true;
  } catch (err) {
    if (
      err.code === 'messaging/registration-token-not-registered' ||
      err.code === 'messaging/invalid-registration-token'
    ) {
      await db
        .collection('users')
        .doc(userId)
        .update({ fcmToken: admin.firestore.FieldValue.delete() });
    }
    return false;
  }
}

// ─── Helper: cap check + record ──────────────────────────────────────────────
/**
 * Returns true if the cap doc exists AND was written within windowMs.
 * If not capped, records the cap timestamp and returns false.
 */
async function isCapped(collection, docId, windowMs) {
  const capRef = db.collection(collection).doc(docId);
  const capSnap = await capRef.get();
  if (capSnap.exists) {
    const lastSent = capSnap.data()?.lastSentAt?.toDate();
    if (lastSent && Date.now() - lastSent.getTime() < windowMs) return true;
  }
  await capRef.set(
    { lastSentAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// #6  Gentle Re-engagement
//     Runs every Sunday at 10:00 AM UTC.
//     Targets users dormant 7+ days; capped at once per 14 days per user.
// ─────────────────────────────────────────────────────────────────────────────
exports.gentleReengagement = onSchedule(
  { schedule: '0 10 * * 0', timeZone: 'UTC', region: REGION }, // Sun 10AM UTC
  async () => {
    const now = Date.now();
    const sevenDaysAgo = new Date(now - 7 * 24 * 60 * 60 * 1000);
    const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000;

    console.log('🌅 Running Gentle Re-engagement (Sunday only)...');

    try {
      const usersSnap = await db
        .collection('users')
        .where('lastActiveAt', '<=', admin.firestore.Timestamp.fromDate(sevenDaysAgo))
        .limit(500)
        .get();

      let sentCount = 0;

      for (const userDoc of usersSnap.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        if (!userData.fcmToken) continue;

        if (await isCapped('reengagementCaps', userId, FOURTEEN_DAYS_MS)) continue;

        const displayName = userData.displayName || 'Friend';

        await db.collection('users').doc(userId).collection('notifications').add({
          type: 'gentle_reengagement',
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const sent = await safeSend(userId, userData.fcmToken, {
          notification: {
            title: 'We miss you',
            body: `${displayName}, your community is praying for you. Come back and share what God is doing.`,
          },
          data: { type: 'gentle_reengagement', deepLink: 'amen://feed' },
        });
        if (sent) sentCount++;
      }

      console.log(`✅ Gentle Re-engagement sent to ${sentCount} users`);
    } catch (error) {
      console.error('❌ Error in gentleReengagement:', error);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// #7  New Church Member
//     Firestore trigger: fires when users/{userId}.churchId transitions
//     from empty/null to a non-empty value (new join or church change).
//     Batch-notifies existing members with in-app + push notification.
// ─────────────────────────────────────────────────────────────────────────────
exports.onNewChurchMember = onDocumentUpdated(
  { document: 'users/{userId}', region: REGION },
  async (event) => {
    const userId = event.params.userId;
    const before = event.data.before.data();
    const after  = event.data.after.data();

    const oldChurchId = before?.churchId || null;
    const newChurchId = after?.churchId  || null;

    // Only fire when churchId transitions to a new non-empty value
    if (!newChurchId || oldChurchId === newChurchId) return null;

    console.log(`⛪ New church member: ${userId} joined ${newChurchId}`);

    try {
      const newMemberName = after.displayName || after.username || 'A new member';

      const [communitySnap, churchDoc] = await Promise.all([
        db.collection('users').where('churchId', '==', newChurchId).limit(200).get(),
        db.collection('churches').doc(newChurchId).get(),
      ]);

      const churchName = churchDoc.data()?.name || 'your church';
      const batchWriter = db.batch();

      let pushCount = 0;

      for (const memberDoc of communitySnap.docs) {
        if (memberDoc.id === userId) continue;

        const memberData = memberDoc.data();
        // Respect notification opt-out
        if (memberData.notificationSettings?.newChurchMembers === false) continue;

        const notifRef = db
          .collection('users')
          .doc(memberDoc.id)
          .collection('notifications')
          .doc();

        batchWriter.set(notifRef, {
          type: 'new_church_member',
          actorId: userId,
          actorName: after.displayName || after.username || '',
          actorProfileImageURL: after.profileImageURL || '',
          churchId: newChurchId,
          churchName,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (memberData.fcmToken) {
          // Fire-and-forget push (don't await to avoid blocking batch)
          safeSend(memberDoc.id, memberData.fcmToken, {
            notification: {
              title: `New member at ${churchName}`,
              body: `${newMemberName} just joined your church community! Welcome them 👋`,
            },
            data: {
              type: 'new_church_member',
              actorId: userId,
              churchId: newChurchId,
              deepLink: `amen://profile/${userId}`,
            },
          });
          pushCount++;
        }
      }

      await batchWriter.commit();
      console.log(`✅ New church member: in-app notifications batched, ${pushCount} push sent`);
      return null;
    } catch (error) {
      console.error('❌ Error in onNewChurchMember:', error);
      return null;
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// #10 Prayer Check-in
//     Runs every Wednesday at 12:00 PM UTC.
//     Finds unanswered prayers created 7–8 days ago.
//     Author gets a gentle nudge capped at once per 14 days.
// ─────────────────────────────────────────────────────────────────────────────
exports.prayerCheckin = onSchedule(
  { schedule: '0 12 * * 3', timeZone: 'UTC', region: REGION }, // Wed 12PM UTC
  async () => {
    const now = Date.now();
    const windowStart = new Date(now - 8 * 24 * 60 * 60 * 1000);
    const windowEnd   = new Date(now - 7 * 24 * 60 * 60 * 1000);
    const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000;

    console.log('🙏 Running Prayer Check-in (Wednesday)...');

    try {
      const prayersSnap = await db
        .collection('prayers')
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(windowStart))
        .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(windowEnd))
        .where('isAnswered', '==', false)
        .limit(500)
        .get();

      let sentCount = 0;

      for (const prayerDoc of prayersSnap.docs) {
        const prayer   = prayerDoc.data();
        const authorId = prayer.authorId || prayer.userId;
        if (!authorId) continue;

        if (await isCapped('prayerCheckinCaps', authorId, FOURTEEN_DAYS_MS)) continue;

        const userDoc = await db.collection('users').doc(authorId).get();
        if (!userDoc.exists) continue;

        const userData    = userDoc.data();
        const prayerTitle = prayer.title
          || (prayer.content || prayer.text || '').substring(0, 60)
          || 'your prayer';

        await db.collection('users').doc(authorId).collection('notifications').add({
          type: 'prayer_checkin',
          prayerId: prayerDoc.id,
          prayerTitle,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (userData.fcmToken) {
          const sent = await safeSend(authorId, userData.fcmToken, {
            notification: {
              title: '🙏 Prayer Update',
              body: `Has God answered "${prayerTitle}" yet? Share what happened.`,
            },
            data: {
              type: 'prayer_checkin',
              prayerId: prayerDoc.id,
              deepLink: `amen://prayer/${prayerDoc.id}`,
            },
          });
          if (sent) sentCount++;
        }
      }

      console.log(`✅ Prayer Check-in sent to ${sentCount} users`);
    } catch (error) {
      console.error('❌ Error in prayerCheckin:', error);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// #3  Testimony Anniversary
//     Runs daily at 6:00 AM UTC.
//     Finds testimonies posted exactly 1 year ago (±12 hour window).
//     Sends a celebratory notification to the post author.
// ─────────────────────────────────────────────────────────────────────────────
exports.testimonyAnniversary = onSchedule(
  { schedule: '0 6 * * *', timeZone: 'UTC', region: REGION },
  async () => {
    const now     = new Date();
    const yearAgo = new Date(now);
    yearAgo.setFullYear(yearAgo.getFullYear() - 1);

    const windowStart = new Date(yearAgo.getTime() - 12 * 60 * 60 * 1000);
    const windowEnd   = new Date(yearAgo.getTime() + 12 * 60 * 60 * 1000);

    console.log(`🎉 Running Testimony Anniversary for ${yearAgo.toDateString()}...`);

    try {
      const snap = await db
        .collection('posts')
        .where('type', '==', 'testimony')
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(windowStart))
        .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(windowEnd))
        .get();

      let sentCount = 0;

      for (const postDoc of snap.docs) {
        const post     = postDoc.data();
        const authorId = post.authorId || post.userId;
        if (!authorId) continue;

        const userDoc = await db.collection('users').doc(authorId).get();
        if (!userDoc.exists) continue;

        const userData    = userDoc.data();
        const displayName = userData.displayName || 'Friend';

        await db.collection('users').doc(authorId).collection('notifications').add({
          type: 'testimony_anniversary',
          postId: postDoc.id,
          yearsAgo: 1,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (userData.fcmToken) {
          const sent = await safeSend(authorId, userData.fcmToken, {
            notification: {
              title: '🎉 One Year Ago Today',
              body: `${displayName}, one year ago you shared a testimony. See how far God has brought you!`,
            },
            data: {
              type: 'testimony_anniversary',
              postId: postDoc.id,
              deepLink: `amen://post/${postDoc.id}`,
            },
          });
          if (sent) sentCount++;
        }
      }

      console.log(`✅ Testimony Anniversary notifications sent to ${sentCount} users`);
    } catch (error) {
      console.error('❌ Error in testimonyAnniversary:', error);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// #4  Friend Returned
//     Runs daily at 9:00 AM UTC.
//     Finds users active in last 24h who were previously dormant 14+ days.
//     Notifies their followers; capped at once per 30 days per follower pair.
//
//     Requires: users/{uid}.previousLastActiveAt field (stamp the previous
//     lastActiveAt value whenever onUserActivity updates lastActiveAt).
// ─────────────────────────────────────────────────────────────────────────────
exports.friendReturned = onSchedule(
  { schedule: '0 9 * * *', timeZone: 'UTC', region: REGION },
  async () => {
    const now = Date.now();
    const oneDayAgo       = new Date(now - 24 * 60 * 60 * 1000);
    const fourteenDaysAgo = new Date(now - 14 * 24 * 60 * 60 * 1000);
    const THIRTY_DAYS_MS  = 30 * 24 * 60 * 60 * 1000;

    console.log('👋 Running Friend Returned detection...');

    try {
      const recentlyActiveSnap = await db
        .collection('users')
        .where('lastActiveAt', '>=', admin.firestore.Timestamp.fromDate(oneDayAgo))
        .limit(500)
        .get();

      let sentCount = 0;

      for (const returnedUserDoc of recentlyActiveSnap.docs) {
        const returnedUserId = returnedUserDoc.id;
        const returnedUser   = returnedUserDoc.data();

        // Only qualify if they were dormant for 14+ days before this activity
        const previousLastActive = returnedUser.previousLastActiveAt?.toDate();
        if (!previousLastActive || previousLastActive >= fourteenDaysAgo) continue;

        const returnedName = returnedUser.displayName || returnedUser.username || 'Someone';

        const followersSnap = await db
          .collection('users')
          .doc(returnedUserId)
          .collection('followers')
          .limit(200)
          .get();

        for (const followerDoc of followersSnap.docs) {
          const followerId = followerDoc.id;

          const capped = await isCapped(
            'friendReturnedCaps',
            `${followerId}_${returnedUserId}`,
            THIRTY_DAYS_MS
          );
          if (capped) continue;

          const followerUserDoc = await db.collection('users').doc(followerId).get();
          if (!followerUserDoc.exists) continue;

          const followerData = followerUserDoc.data();

          await db.collection('users').doc(followerId).collection('notifications').add({
            type: 'friend_returned',
            actorId: returnedUserId,
            actorName: returnedName,
            actorProfileImageURL: returnedUser.profileImageURL || '',
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          if (followerData.fcmToken) {
            const sent = await safeSend(followerId, followerData.fcmToken, {
              notification: {
                title: '👋 A friend is back!',
                body: `${returnedName} is back after a while away. Say hello!`,
              },
              data: {
                type: 'friend_returned',
                actorId: returnedUserId,
                deepLink: `amen://profile/${returnedUserId}`,
              },
            });
            if (sent) sentCount++;
          }
        }
      }

      console.log(`✅ Friend Returned notifications sent: ${sentCount}`);
    } catch (error) {
      console.error('❌ Error in friendReturned:', error);
    }
  }
);
