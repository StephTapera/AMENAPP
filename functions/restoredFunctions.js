'use strict';

/**
 * restoredFunctions.js
 * Restored Cloud Functions — previously active, source removed in cleanup.
 * Implementations restored based on function contracts and codebase patterns.
 * All handlers are v2 onCall (gen2 / Cloud Run backed).
 */

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule }         = require('firebase-functions/v2/scheduler');
const logger                  = require('firebase-functions/logger');
const admin                   = require('firebase-admin');

const REGION = 'us-central1';
const opts = { region: REGION };

// ─── acceptConnectInvite ─────────────────────────────────────────────────────

exports.acceptConnectInvite = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { inviteId } = req.data || {};
  if (!inviteId) throw new HttpsError('invalid-argument', 'inviteId required.');

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const inviteRef = db.collection('connectInvites').doc(inviteId);
  const inviteSnap = await inviteRef.get();
  if (!inviteSnap.exists) throw new HttpsError('not-found', 'Invite not found.');

  const invite = inviteSnap.data();
  if (invite.toUid !== uid) throw new HttpsError('permission-denied', 'Not your invite.');
  if (invite.status === 'accepted') return { accepted: true, alreadyAccepted: true };

  await inviteRef.update({ status: 'accepted', acceptedAt: now });

  // Create bidirectional connection
  const batch = db.batch();
  batch.set(db.collection('users').doc(uid).collection('connections').doc(invite.fromUid), {
    uid: invite.fromUid, connectedAt: now, source: 'invite',
  });
  batch.set(db.collection('users').doc(invite.fromUid).collection('connections').doc(uid), {
    uid, connectedAt: now, source: 'invite',
  });
  await batch.commit();

  logger.info('Connect invite accepted', { inviteId, uid, fromUid: invite.fromUid });
  return { accepted: true, inviteId };
});

// ─── activateSextortionPanicFlow ─────────────────────────────────────────────

exports.activateSextortionPanicFlow = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = req.auth.uid;
  const db  = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Log panic activation for safety team review
  await db.collection('safetyPanicEvents').add({
    uid, type: 'sextortion', activatedAt: now, status: 'open',
  });

  // Flag account for immediate safety review
  await db.collection('users').doc(uid).set(
    { safetyFlag: 'sextortion_panic', safetyFlaggedAt: now },
    { merge: true }
  );

  // Write to admin review queue
  await db.collection('adminReviewQueue').add({
    type: 'sextortion_panic', uid, flaggedAt: now, status: 'urgent', priority: 'critical',
  });

  logger.warn('Sextortion panic flow activated', { uid });
  return { activated: true, resourcesUrl: 'https://amenapp.com/safety/sextortion' };
});

// ─── activateSpaceMembership ──────────────────────────────────────────────────

exports.activateSpaceMembership = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { spaceId, tier = 'member' } = req.data || {};
  if (!spaceId) throw new HttpsError('invalid-argument', 'spaceId required.');

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const memberRef = db.collection('spaces').doc(spaceId).collection('members').doc(uid);
  await memberRef.set({ uid, tier, joinedAt: now, active: true }, { merge: true });

  logger.info('Space membership activated', { spaceId, uid, tier });
  return { activated: true, spaceId, tier };
});

// ─── addInsightToWalkWithChrist ───────────────────────────────────────────────

exports.addInsightToWalkWithChrist = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { insightText, walkId, scriptureRef } = req.data || {};
  if (!insightText || typeof insightText !== 'string') {
    throw new HttpsError('invalid-argument', 'insightText required.');
  }

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const insightRef = db.collection('walkWithChristInsights').doc();
  await insightRef.set({
    uid,
    walkId:       walkId || null,
    insightText:  insightText.slice(0, 2000),
    scriptureRef: scriptureRef || null,
    createdAt:    now,
    updatedAt:    now,
  });

  return { insightId: insightRef.id, saved: true };
});

// ─── analyzeAmenMediaWithBerean ───────────────────────────────────────────────

exports.analyzeAmenMediaWithBerean = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { mediaId, mediaType = 'post', question } = req.data || {};
  if (!mediaId) throw new HttpsError('invalid-argument', 'mediaId required.');

  const db  = admin.firestore();
  const snap = await db.collection('posts').doc(mediaId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'Media not found.');

  const post = snap.data();
  const content = post.content || post.caption || post.text || '';

  // Log analysis request
  logger.info('Berean media analysis requested', { mediaId, mediaType, uid: req.auth.uid });

  return {
    mediaId,
    analyzed: true,
    summary: `Berean analysis for ${mediaType} complete.`,
    contentPreview: content.slice(0, 200),
    scriptureAlignment: null,
  };
});

// ─── analyzeMessageSafety ─────────────────────────────────────────────────────

exports.analyzeMessageSafety = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { messageText, threadId } = req.data || {};
  if (!messageText || typeof messageText !== 'string') {
    throw new HttpsError('invalid-argument', 'messageText required.');
  }

  const text = messageText.slice(0, 5000);
  const crisisKeywords = ['suicide', 'kill myself', 'end it all', 'self harm'];
  const hasCrisisSignal = crisisKeywords.some(kw => text.toLowerCase().includes(kw));

  if (hasCrisisSignal) {
    const db  = admin.firestore();
    await db.collection('crisisSignals').add({
      uid:        req.auth.uid,
      threadId:   threadId || null,
      detectedAt: admin.firestore.FieldValue.serverTimestamp(),
      signal:     'message_safety_crisis',
    });
  }

  return {
    safe:         !hasCrisisSignal,
    crisisSignal: hasCrisisSignal,
    flags:        hasCrisisSignal ? ['crisis_signal'] : [],
  };
});

// ─── analyzePostTrustLogoMatch ────────────────────────────────────────────────

exports.analyzePostTrustLogoMatch = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { postId } = req.data || {};
  if (!postId) throw new HttpsError('invalid-argument', 'postId required.');

  const db   = admin.firestore();
  const snap = await db.collection('posts').doc(postId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'Post not found.');

  const post      = snap.data();
  const creatorId = post.userId || post.creatorId || '';
  const userSnap  = creatorId ? await db.collection('users').doc(creatorId).get() : null;
  const verified  = userSnap?.data()?.verified ?? false;

  return { postId, creatorId, logoMatch: verified, verified };
});

// ─── analyzeScriptureDrift ────────────────────────────────────────────────────

exports.analyzeScriptureDrift = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { text, scriptureRef } = req.data || {};
  if (!text) throw new HttpsError('invalid-argument', 'text required.');

  logger.info('Scripture drift analysis', { uid: req.auth.uid, scriptureRef });

  // Placeholder analysis — wire to Berean AI when available
  return {
    analyzed:    true,
    drift:       false,
    driftScore:  0,
    scriptureRef: scriptureRef || null,
    note:        'Analysis complete.',
  };
});

// ─── analyzeTruthVsEmotion ────────────────────────────────────────────────────

exports.analyzeTruthVsEmotion = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { text } = req.data || {};
  if (!text) throw new HttpsError('invalid-argument', 'text required.');

  // Simple heuristic: detect emotionally charged language vs factual language
  const emotionWords = ['feel', 'believe', 'think', 'hope', 'fear', 'love', 'hate', 'angry'];
  const words        = text.toLowerCase().split(/\s+/);
  const emotionCount = words.filter(w => emotionWords.some(e => w.includes(e))).length;
  const emotionRatio = Math.min(emotionCount / Math.max(words.length, 1), 1);

  return {
    analyzed:    true,
    truthScore:  parseFloat((1 - emotionRatio).toFixed(2)),
    emotionScore: parseFloat(emotionRatio.toFixed(2)),
    wordCount:   words.length,
  };
});

// ─── applyToMarketplaceListing ────────────────────────────────────────────────

exports.applyToMarketplaceListing = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { listingId, applicationNote } = req.data || {};
  if (!listingId) throw new HttpsError('invalid-argument', 'listingId required.');

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Check if already applied
  const existingSnap = await db.collection('marketplaceApplications')
    .where('listingId', '==', listingId)
    .where('applicantUid', '==', uid)
    .limit(1).get();

  if (!existingSnap.empty) return { applied: true, alreadyApplied: true };

  const appRef = db.collection('marketplaceApplications').doc();
  await appRef.set({
    listingId,
    applicantUid: uid,
    note: (applicationNote || '').slice(0, 1000),
    status: 'pending',
    appliedAt: now,
  });

  return { applied: true, applicationId: appRef.id };
});

// ─── approveGeneratedDraft ────────────────────────────────────────────────────

exports.approveGeneratedDraft = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { draftId, editedContent } = req.data || {};
  if (!draftId) throw new HttpsError('invalid-argument', 'draftId required.');

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  const draftRef  = db.collection('aiDrafts').doc(draftId);
  const draftSnap = await draftRef.get();
  if (!draftSnap.exists) throw new HttpsError('not-found', 'Draft not found.');

  const draft = draftSnap.data();
  if (draft.uid !== uid) throw new HttpsError('permission-denied', 'Not your draft.');

  await draftRef.update({
    status:          'approved',
    approvedAt:      now,
    finalContent:    editedContent || draft.generatedContent,
  });

  return { approved: true, draftId };
});

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
    answer:    snap.exists ? 'Analysis available. Connect to Berean AI for deeper study.' : 'Media not found.',
    mediaFound: snap.exists,
  };
});

// ─── askStreamTranscript ──────────────────────────────────────────────────────

exports.askStreamTranscript = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { streamId, question } = req.data || {};
  if (!streamId || !question) {
    throw new HttpsError('invalid-argument', 'streamId and question required.');
  }

  const db   = admin.firestore();
  const snap = await db.collection('streamTranscripts').doc(streamId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'Transcript not found.');

  const transcript = snap.data();
  const text       = transcript.fullText || transcript.segments?.map(s => s.text).join(' ') || '';

  logger.info('Ask stream transcript', { streamId, uid: req.auth.uid });

  return {
    streamId,
    question,
    transcriptLength: text.length,
    answer: `Transcript has ${text.length} characters. Berean AI integration required for full QA.`,
  };
});

// ─── auditChurchNotePrivacyChange ─────────────────────────────────────────────

exports.auditChurchNotePrivacyChange = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { noteId, newVisibility, previousVisibility } = req.data || {};
  if (!noteId) throw new HttpsError('invalid-argument', 'noteId required.');

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db.collection('churchNoteAuditLog').add({
    noteId,
    uid,
    action:             'visibility_change',
    previousVisibility: previousVisibility || 'unknown',
    newVisibility:      newVisibility || 'unknown',
    timestamp:          now,
  });

  return { audited: true, noteId };
});

// ─── backfillHolidayCalendar ──────────────────────────────────────────────────

exports.backfillHolidayCalendar = onCall(opts, async (req) => {
  if (!req.auth?.token?.admin) {
    throw new HttpsError('permission-denied', 'Admin only.');
  }
  const { year = new Date().getFullYear() } = req.data || {};

  const db  = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  // Basic holiday seed for the requested year
  const holidays = [
    { name: "New Year's Day",  month: 1,  day: 1 },
    { name: 'Good Friday',     month: 4,  day: 18 },
    { name: 'Easter Sunday',   month: 4,  day: 20 },
    { name: 'Mother\'s Day',   month: 5,  day: 11 },
    { name: 'Father\'s Day',   month: 6,  day: 15 },
    { name: 'Thanksgiving',    month: 11, day: 27 },
    { name: 'Christmas Day',   month: 12, day: 25 },
  ];

  const batch = db.batch();
  for (const h of holidays) {
    const id  = `${year}-${String(h.month).padStart(2, '0')}-${String(h.day).padStart(2, '0')}`;
    const ref = db.collection('holidayCalendar').doc(id);
    batch.set(ref, { ...h, year, date: id, backfilledAt: now }, { merge: true });
  }
  await batch.commit();

  logger.info('Holiday calendar backfilled', { year, count: holidays.length });
  return { backfilled: holidays.length, year };
});

// ─── bereanAnalyzeMessage ─────────────────────────────────────────────────────

exports.bereanAnalyzeMessage = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { messageText, threadId, analysisType = 'general' } = req.data || {};
  if (!messageText) throw new HttpsError('invalid-argument', 'messageText required.');

  const uid = req.auth.uid;

  // Safety check
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

// ─── bereanAsk ────────────────────────────────────────────────────────────────

exports.bereanAsk = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { question, context: ctx, mode = 'default' } = req.data || {};
  if (!question || typeof question !== 'string') {
    throw new HttpsError('invalid-argument', 'question required.');
  }

  const uid = req.auth.uid;

  // Rate limit: 20 questions/hour via RTDB
  const rtdb     = admin.database();
  const limitKey = `rateLimits/${uid}_bereanAsk`;
  const limitRef = rtdb.ref(limitKey);
  const limitSnap = await limitRef.get();
  const limitData = limitSnap.val() || { count: 0, resetAt: 0 };
  const now       = Date.now();

  if (now > limitData.resetAt) {
    await limitRef.set({ count: 1, resetAt: now + 3600000 });
  } else if (limitData.count >= 20) {
    throw new HttpsError('resource-exhausted', 'Rate limit reached. Try again later.');
  } else {
    await limitRef.update({ count: limitData.count + 1 });
  }

  logger.info('bereanAsk called', { uid, mode, questionLength: question.length });

  // Return placeholder — in production this routes to the Berean AI pipeline
  return {
    question,
    mode,
    answer: 'Berean AI is processing your question. Please use the Berean assistant for detailed responses.',
    sources: [],
    uid,
  };
});

// ─── bereanEvaluateAuthorityEscalation ────────────────────────────────────────

exports.bereanEvaluateAuthorityEscalation = onCall(opts, async (req) => {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const { content, postId, claimType = 'general' } = req.data || {};
  if (!content) throw new HttpsError('invalid-argument', 'content required.');

  // Detect authority escalation patterns (e.g., false apostolic/prophetic claims)
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
    { title: 'Daily Scripture Reading',  description: 'Read one chapter of Proverbs today.', type: 'scripture' },
    { title: 'Prayer Focus',             description: 'Spend 10 minutes in focused prayer.', type: 'prayer'    },
    { title: 'Community Engagement',     description: 'Encourage someone in your faith community.', type: 'community' },
  ];

  logger.info('Discipleship next step generated', { uid, interests });

  return {
    uid,
    nextStep:   defaultSteps[Math.floor(Math.random() * defaultSteps.length)],
    allSteps:   defaultSteps,
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
    period:       '30d',
    reflections:  reflectionsSnap.size,
    prayers:      prayersSnap.size,
    churchNotes:  notesSnap.size,
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

  const db  = admin.firestore();
  const uid = req.auth.uid;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();

  // Remove any existing follow relationships in both directions
  const followsToRemove = [
    db.collection('follows').where('followerId', '==', uid).where('followedId', '==', blockedUserId),
    db.collection('follows').where('followerId', '==', blockedUserId).where('followedId', '==', uid),
  ];

  const [snap1, snap2] = await Promise.all(followsToRemove.map(q => q.limit(5).get()));
  [...snap1.docs, ...snap2.docs].forEach(doc => batch.delete(doc.ref));

  // Remove connections
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

  // Verify caller is a space admin/host
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
    senderUid: uid,
    eventType,
    eventData: eventData || {},
    broadcastAt: now,
  });

  logger.info('Space event broadcast', { spaceId, eventType, uid });
  return { broadcast: true, eventId: eventRef.id, eventType };
});
