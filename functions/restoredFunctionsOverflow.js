'use strict';

/**
 * restoredFunctionsOverflow.js
 * 11 restored functions that could not be deployed to us-central1 (quota full).
 * Deployed to us-east1 instead. iOS clients calling these should specify region.
 * All handlers are v2 onCall (gen2 / Cloud Run backed), region: us-east1.
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger                  = require('firebase-functions/logger');
const admin                   = require('firebase-admin');

const REGION = 'us-east1';
const opts = { region: REGION };

// ─── askBereanAboutSelahMedia ─────────────────────────────────────────────────

exports.askBereanAboutSelahMedia = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { mediaId, question } = req.data || {};
  if (!mediaId || !question) {
    throw new HttpsError('invalid-argument', 'mediaId and question required.');
  }

  const db   = admin.firestore();
  const snap = await db.collection('selahStories').doc(mediaId).get();

  logger.info('Ask Berean about Selah media', { mediaId, uid: req.auth.uid });

  return {
    mediaId,
    question,
    answer:     snap.exists ? 'Analysis available. Connect to Berean AI for deeper study.' : 'Media not found.',
    mediaFound: snap.exists,
  };
});

// ─── bereanAnalyzeMessage ─────────────────────────────────────────────────────

exports.bereanAnalyzeMessage = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { messageText, threadId, analysisType = 'general' } = req.data || {};
  if (!messageText) throw new HttpsError('invalid-argument', 'messageText required.');

  const uid = req.auth.uid;
  const crisisWords = ['hurt myself', 'suicide', 'end my life'];
  const hasCrisis   = crisisWords.some(w => messageText.toLowerCase().includes(w));

  logger.info('Berean message analysis', { uid, analysisType, hasCrisis });

  return {
    analyzed:      true,
    messageLength: messageText.length,
    analysisType,
    crisisSignal:  hasCrisis,
    scriptureHint: null,
    threadId:      threadId || null,
  };
});

// ─── bereanEvaluateAuthorityEscalation ────────────────────────────────────────

exports.bereanEvaluateAuthorityEscalation = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { content, postId, claimType = 'general' } = req.data || {};
  if (!content) throw new HttpsError('invalid-argument', 'content required.');

  const escalationPatterns = [
    'god told me to tell you',
    'i speak for god',
    'thus saith the lord',
    'divine revelation',
    'prophetic word for you',
  ];
  const text    = content.toLowerCase();
  const found   = escalationPatterns.filter(p => text.includes(p));
  const escalate = found.length > 0;

  logger.info('Authority escalation evaluated', { uid: req.auth.uid, escalate, postId });

  return {
    escalate,
    patterns:  found,
    claimType,
    postId:    postId || null,
    note:      escalate ? 'Potential authority claim detected for review.' : 'No escalation detected.',
  };
});

// ─── bereanGenerateChurchNotesSummary ─────────────────────────────────────────

exports.bereanGenerateChurchNotesSummary = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { noteId } = req.data || {};
  if (!noteId) throw new HttpsError('invalid-argument', 'noteId required.');

  const db   = admin.firestore();
  const uid  = req.auth.uid;
  const snap = await db.collection('churchNotes').doc(noteId).get();

  if (!snap.exists) throw new HttpsError('not-found', 'Church note not found.');

  const note = snap.data();
  if (note.uid !== uid && note.userId !== uid) {
    throw new HttpsError('permission-denied', 'Not your note.');
  }

  const rawText = note.content || note.rawText || '';
  const summary = rawText.length > 200
    ? rawText.slice(0, 200).trimEnd() + '…'
    : rawText || 'No content to summarize.';

  logger.info('Church notes summary generated', { noteId, uid });
  return { noteId, summary, wordCount: rawText.split(/\s+/).length };
});

// ─── bereanGenerateDiscipleshipNextStep ───────────────────────────────────────

exports.bereanGenerateDiscipleshipNextStep = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = req.auth.uid;

  const db   = admin.firestore();
  const snap = await db.collection('users').doc(uid).get();
  const user = snap.exists ? snap.data() : {};

  const interests    = user.interests || user.spiritualInterests || [];
  const defaultSteps = [
    { title: 'Daily Scripture Reading', description: 'Read one chapter of Proverbs today.',   type: 'scripture'  },
    { title: 'Prayer Focus',            description: 'Spend 10 minutes in focused prayer.',  type: 'prayer'     },
    { title: 'Community Engagement',    description: 'Encourage someone in your community.', type: 'community'  },
  ];

  logger.info('Discipleship next step generated', { uid, interests });
  return {
    uid,
    nextStep: defaultSteps[Math.floor(Math.random() * defaultSteps.length)],
    allSteps: defaultSteps,
    interests,
  };
});

// ─── bereanGetImmersionPayload ────────────────────────────────────────────────

exports.bereanGetImmersionPayload = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { sessionType = 'scripture', topicId } = req.data || {};
  const uid = req.auth.uid;

  const payload = {
    sessionType,
    topicId:   topicId || null,
    uid,
    scripture: {
      reference: 'Psalm 46:10',
      text:      'Be still, and know that I am God.',
      version:   'KJV',
    },
    backgroundAudio: null,
    guidedPrompt:    `Take a moment to reflect on what it means to be still in ${sessionType} today.`,
    durationMinutes: 15,
  };

  return { payload };
});

// ─── bereanGetJourneySnapshot ─────────────────────────────────────────────────

exports.bereanGetJourneySnapshot = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = req.auth.uid;

  const db  = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(now.toMillis() - 30 * 24 * 60 * 60 * 1000);

  const [reflectionsSnap, prayersSnap, notesSnap] = await Promise.all([
    db.collection('reflections').where('uid', '==', uid).where('createdAt', '>=', thirtyDaysAgo).limit(30).get(),
    db.collection('prayerRequests').where('userId', '==', uid).where('createdAt', '>=', thirtyDaysAgo).limit(30).get(),
    db.collection('churchNotes').where('uid', '==', uid).where('createdAt', '>=', thirtyDaysAgo).limit(30).get(),
  ]);

  return {
    uid,
    period:           '30d',
    reflections:      reflectionsSnap.size,
    prayers:          prayersSnap.size,
    churchNotes:      notesSnap.size,
    totalEngagements: reflectionsSnap.size + prayersSnap.size + notesSnap.size,
  };
});

// ─── bereanSaveReflectionEntry ────────────────────────────────────────────────

exports.bereanSaveReflectionEntry = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { reflectionText, scriptureRef, mood, sessionId } = req.data || {};
  if (!reflectionText || typeof reflectionText !== 'string') {
    throw new HttpsError('invalid-argument', 'reflectionText required.');
  }

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const refDoc = db.collection('bereanReflections').doc();
  await refDoc.set({
    uid,
    reflectionText: reflectionText.slice(0, 3000),
    scriptureRef:   scriptureRef || null,
    mood:           mood || null,
    sessionId:      sessionId || null,
    createdAt:      now,
  });

  return { saved: true, reflectionId: refDoc.id };
});

// ─── blockRelationshipCleanup ─────────────────────────────────────────────────

exports.blockRelationshipCleanup = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { blockedUserId } = req.data || {};
  if (!blockedUserId) throw new HttpsError('invalid-argument', 'blockedUserId required.');

  const db    = admin.firestore();
  const uid   = req.auth.uid;
  const batch = db.batch();

  const [snap1, snap2] = await Promise.all([
    db.collection('follows').where('followerId', '==', uid).where('followedId', '==', blockedUserId).limit(5).get(),
    db.collection('follows').where('followerId', '==', blockedUserId).where('followedId', '==', uid).limit(5).get(),
  ]);
  [...snap1.docs, ...snap2.docs].forEach(doc => batch.delete(doc.ref));

  batch.delete(db.collection('users').doc(uid).collection('connections').doc(blockedUserId));
  batch.delete(db.collection('users').doc(blockedUserId).collection('connections').doc(uid));

  await batch.commit();

  logger.info('Block relationship cleanup complete', { uid, blockedUserId });
  return { cleaned: true, uid, blockedUserId };
});

// ─── broadcastSpaceAnnouncement ───────────────────────────────────────────────

exports.broadcastSpaceAnnouncement = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { spaceId, message, title } = req.data || {};
  if (!spaceId || !message) {
    throw new HttpsError('invalid-argument', 'spaceId and message required.');
  }

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const memberRef  = db.collection('spaces').doc(spaceId).collection('members').doc(uid);
  const memberSnap = await memberRef.get();
  if (!memberSnap.exists || !['host', 'admin', 'moderator'].includes(memberSnap.data()?.tier)) {
    throw new HttpsError('permission-denied', 'Only space hosts/admins can broadcast.');
  }

  const announcementRef = db.collection('spaces').doc(spaceId).collection('announcements').doc();
  await announcementRef.set({
    spaceId,
    senderUid: uid,
    title:     (title || '').slice(0, 100),
    message:   message.slice(0, 2000),
    sentAt:    now,
    type:      'announcement',
  });

  logger.info('Space announcement broadcast', { spaceId, uid });
  return { sent: true, announcementId: announcementRef.id };
});

// ─── broadcastSpaceEvent ──────────────────────────────────────────────────────

exports.broadcastSpaceEvent = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { spaceId, eventType, eventData } = req.data || {};
  if (!spaceId || !eventType) {
    throw new HttpsError('invalid-argument', 'spaceId and eventType required.');
  }

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const eventRef = db.collection('spaces').doc(spaceId).collection('events').doc();
  await eventRef.set({
    spaceId,
    senderUid:   uid,
    eventType,
    eventData:   eventData || {},
    broadcastAt: now,
  });

  logger.info('Space event broadcast', { spaceId, eventType, uid });
  return { broadcast: true, eventId: eventRef.id, eventType };
});
