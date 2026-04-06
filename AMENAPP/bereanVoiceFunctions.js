/**
 * bereanVoiceFunctions.js
 * AMENAPP — Berean Live Voice Cloud Functions
 *
 * Exports:
 *   bereanVoiceProxy   — LLM proxy (Claude / OpenAI) with faith-shaped prompts
 *   voiceSessionStart  — Create session document and return sessionId
 *   voiceModeration    — Crisis-signal scanner integrated with safety pipeline
 *   ttsProxy           — Text-to-speech proxy (Google TTS or OpenAI TTS)
 *
 * All callables require Firebase Auth.
 * Keys live exclusively in Firebase Secret Manager — never on-device.
 */

'use strict';

const functions  = require('firebase-functions');
const admin      = require('firebase-admin');
const { defineSecret } = require('firebase-functions/params');

// Secrets (populated via Secret Manager)
const OPENAI_API_KEY    = defineSecret('OPENAI_API_KEY');
const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const GOOGLE_TTS_KEY    = defineSecret('GOOGLE_TTS_KEY');

// Firestore shorthand (admin is already initialised in functionsindex.js)
const db = () => admin.firestore();

// ---------------------------------------------------------------------------
// MARK: Rate-limiting helper
// ---------------------------------------------------------------------------

/**
 * Returns true if the caller is within the allowed quota.
 * Quota: 60 calls per user per hour, tracked in Firestore.
 */
async function checkRateLimit(uid, functionName) {
  const windowMs  = 60 * 60 * 1000;     // 1 hour
  const maxCalls  = 60;
  const now       = Date.now();
  const windowStart = now - windowMs;

  const ref = db()
    .collection('berean_voice_rate_limits')
    .doc(`${uid}_${functionName}`);

  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : { calls: [], uid, functionName };

    // Prune calls outside the current window
    const recentCalls = (data.calls || []).filter((ts) => ts > windowStart);

    if (recentCalls.length >= maxCalls) {
      return false; // rate limited
    }

    recentCalls.push(now);
    tx.set(ref, { ...data, calls: recentCalls, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return true;
  });
}

// ---------------------------------------------------------------------------
// MARK: System prompt factory
// ---------------------------------------------------------------------------

/**
 * Returns a mode-specific system prompt for Berean's voice persona.
 */
function buildSystemPrompt(mode, emotionalState) {
  const basePersona = `You are Berean, a warm, biblically grounded AI companion integrated into the AMEN community app.
You speak conversationally, with clarity and compassion. You are not a replacement for pastoral care or professional counseling.
Keep responses concise (2–4 sentences for voice). Speak naturally — no markdown, no lists, no headers.`;

  const empathyLayer = emotionalState === 'distressed'
    ? `\nThe user appears to be in distress. Lead with empathy before offering scriptural perspective. Remind them they are not alone.`
    : emotionalState === 'joyful'
    ? `\nThe user is joyful. Celebrate with them and affirm God's goodness in their experience.`
    : emotionalState === 'seeking'
    ? `\nThe user is searching for understanding. Be patient, thoughtful, and invite them deeper.`
    : '';

  const modeLayer = {
    conversation: `\nMode: open conversation. Engage naturally about faith, life, and Scripture.`,
    prayer:       `\nMode: prayer. Gently guide the user in prayer or pray alongside them. Use reverent, intimate language.`,
    churchNotes:  `\nMode: church notes. Help the user capture and reflect on the sermon or teaching they are hearing.`,
    discovery:    `\nMode: discovery. Help the user explore a Scripture passage, biblical topic, or theological question.`,
    wellness:     `\nMode: spiritual wellness. Offer encouragement, breathing space, and gentle biblical wisdom for the user's emotional or spiritual state.`,
  }[mode] || '';

  return basePersona + empathyLayer + modeLayer;
}

// ---------------------------------------------------------------------------
// MARK: 1. bereanVoiceProxy
// ---------------------------------------------------------------------------

/**
 * Callable: bereanVoiceProxy
 *
 * Input:  { userText, mode, emotionalState, sessionId, transcriptHistory: string[] }
 * Output: { text: string, sessionId: string }
 *
 * Routes to Claude (Haiku) for conversation/prayer/wellness,
 * and OpenAI GPT-4o for churchNotes/discovery (richer knowledge).
 * Rate-limited: 60 calls / user / hour.
 */
exports.bereanVoiceProxy = functions
  .runWith({ secrets: [OPENAI_API_KEY, ANTHROPIC_API_KEY] })
  .https
  .onCall(async (data, context) => {
    // Auth guard
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }
    const uid = context.auth.uid;

    // Rate limit
    const allowed = await checkRateLimit(uid, 'bereanVoiceProxy');
    if (!allowed) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Voice rate limit reached (60 calls/hour). Please wait before continuing.'
      );
    }

    const {
      userText,
      mode            = 'conversation',
      emotionalState  = 'neutral',
      sessionId       = '',
      transcriptHistory = [],
    } = data;

    if (!userText || typeof userText !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'userText is required.');
    }

    const systemPrompt = buildSystemPrompt(mode, emotionalState);

    // Build conversation history (last 5 turns)
    const historyMessages = (transcriptHistory || [])
      .slice(-5)
      .map((turn) => ({ role: 'user', content: turn }));

    let responseText = '';

    // Route: Claude for conversational/empathic modes; OpenAI for knowledge-heavy modes
    const useOpenAI = (mode === 'churchNotes' || mode === 'discovery');

    if (useOpenAI) {
      // ---- OpenAI GPT-4o-mini ----
      const fetch = (await import('node-fetch')).default;
      const messages = [
        { role: 'system', content: systemPrompt },
        ...historyMessages,
        { role: 'user', content: userText },
      ];

      const resp = await fetch('https://api.openai.com/v1/chat/completions', {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${OPENAI_API_KEY.value()}`,
        },
        body: JSON.stringify({
          model:       'gpt-4o-mini',
          messages,
          max_tokens:  300,
          temperature: 0.7,
        }),
      });

      if (!resp.ok) {
        const err = await resp.text();
        console.error('bereanVoiceProxy OpenAI error:', err);
        throw new functions.https.HttpsError('internal', 'AI service error.');
      }

      const json = await resp.json();
      responseText = json.choices?.[0]?.message?.content?.trim() || '';

    } else {
      // ---- Anthropic Claude Haiku ----
      const fetch = (await import('node-fetch')).default;
      const resp = await fetch('https://api.anthropic.com/v1/messages', {
        method:  'POST',
        headers: {
          'Content-Type':      'application/json',
          'x-api-key':         ANTHROPIC_API_KEY.value(),
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model:      'claude-haiku-20240307',
          max_tokens: 300,
          system:     systemPrompt,
          messages: [
            ...historyMessages,
            { role: 'user', content: userText },
          ],
        }),
      });

      if (!resp.ok) {
        const err = await resp.text();
        console.error('bereanVoiceProxy Claude error:', err);
        throw new functions.https.HttpsError('internal', 'AI service error.');
      }

      const json = await resp.json();
      responseText = json.content?.[0]?.text?.trim() || '';
    }

    // Append response to Firestore session transcript (fire-and-forget)
    if (sessionId) {
      db()
        .collection('berean_voice_sessions')
        .doc(sessionId)
        .update({
          transcriptChunks: admin.firestore.FieldValue.arrayUnion(`Berean: ${responseText}`),
        })
        .catch((e) => console.warn('bereanVoiceProxy: transcript update failed', e));
    }

    console.log(`bereanVoiceProxy: uid=${uid} mode=${mode} len=${responseText.length}`);
    return { text: responseText, sessionId };
  });

// ---------------------------------------------------------------------------
// MARK: 2. voiceSessionStart
// ---------------------------------------------------------------------------

/**
 * Callable: voiceSessionStart
 *
 * Input:  { mode, userId? }
 * Output: { sessionId: string }
 *
 * Creates a session document in berean_voice_sessions and returns its ID.
 */
exports.voiceSessionStart = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const uid  = context.auth.uid;
  const mode = data.mode || 'conversation';

  const sessionRef = db().collection('berean_voice_sessions').doc();
  const sessionData = {
    id:                sessionRef.id,
    userId:            uid,
    mode,
    startTime:         admin.firestore.FieldValue.serverTimestamp(),
    endTime:           null,
    emotionalState:    'neutral',
    interruptionCount: 0,
    avgLatencyMs:      0,
    transcriptChunks:  [],
    isActive:          true,
    createdAt:         admin.firestore.FieldValue.serverTimestamp(),
  };

  await sessionRef.set(sessionData);
  console.log(`voiceSessionStart: created session ${sessionRef.id} for uid=${uid}`);
  return { sessionId: sessionRef.id };
});

// ---------------------------------------------------------------------------
// MARK: 3. voiceModeration
// ---------------------------------------------------------------------------

/**
 * Callable: voiceModeration
 *
 * Input:  { transcript: string, sessionId: string }
 * Output: { escalate: boolean, message?: string }
 *
 * Scans a transcript for crisis signals. If triggered:
 *   - Flags the Firestore session with safetyFlag: true
 *   - Returns escalate:true with a pastoral message to surface in the UI
 *   - Integrates with the existing safety pipeline (BereanConversationSafetyService)
 */
exports.voiceModeration = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
  }

  const uid        = context.auth.uid;
  const transcript = (data.transcript || '').toLowerCase();
  const sessionId  = data.sessionId || '';

  // Crisis keyword detection — aligned with the existing safety pipeline
  const crisisSignals = [
    'want to die', 'kill myself', 'end my life', 'suicide', 'hurt myself',
    'self harm', 'no reason to live', 'can\'t go on', 'give up on life',
    'take my own life', 'don\'t want to be here anymore',
  ];

  const distressSignals = [
    'hopeless', 'worthless', 'nobody cares', 'completely alone', 'no way out',
  ];

  const hasCrisis   = crisisSignals.some((s)   => transcript.includes(s));
  const hasDistress = distressSignals.some((s) => transcript.includes(s));

  if (hasCrisis) {
    // Flag the session
    if (sessionId) {
      await db()
        .collection('berean_voice_sessions')
        .doc(sessionId)
        .update({
          safetyFlag:      true,
          safetyFlaggedAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((e) => console.error('voiceModeration: could not flag session', e));
    }

    // Write a moderation event
    await db()
      .collection('berean_voice_events')
      .add({
        sessionId,
        userId:    uid,
        type:      'safetyFlag',
        severity:  'crisis',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        payload:   { transcriptPreview: transcript.slice(0, 200) },
      })
      .catch((e) => console.error('voiceModeration: could not log event', e));

    console.warn(`voiceModeration: CRISIS signal detected uid=${uid} session=${sessionId}`);

    return {
      escalate: true,
      message:
        "I want you to know that you matter deeply, and help is available right now. " +
        "Please reach out to the 988 Suicide & Crisis Lifeline by calling or texting 988. " +
        "You are not alone — God is with you and so is our community.",
    };
  }

  if (hasDistress) {
    console.log(`voiceModeration: distress signal uid=${uid}`);
    return {
      escalate: false,
      adjustTone: true,
      message: null,
    };
  }

  return { escalate: false };
});

// ---------------------------------------------------------------------------
// MARK: 4. ttsProxy
// ---------------------------------------------------------------------------

/**
 * Callable: ttsProxy
 *
 * Input:  { text: string, emotionalState: 'neutral'|'distressed'|'seeking'|'joyful' }
 * Output: { audio: string (base64 PCM/MP3) }
 *
 * Tries Google Cloud TTS first (higher quality, configurable SSML).
 * Falls back to OpenAI TTS if GOOGLE_TTS_KEY is absent.
 * emotionalState adjusts speaking rate and pitch for natural empathic delivery.
 */
exports.ttsProxy = functions
  .runWith({ secrets: [GOOGLE_TTS_KEY, OPENAI_API_KEY] })
  .https
  .onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const text           = (data.text || '').trim();
    const emotionalState = data.emotionalState || 'neutral';

    if (!text) {
      throw new functions.https.HttpsError('invalid-argument', 'text is required.');
    }

    // Clamp text length for TTS
    const safeText = text.slice(0, 800);

    // Emotional-state voice adjustments
    const voiceParams = {
      neutral:    { speakingRate: 1.0,  pitch: 0.0  },
      distressed: { speakingRate: 0.9,  pitch: -1.5 }, // slower, lower — gentle
      seeking:    { speakingRate: 0.95, pitch: -0.5 },
      joyful:     { speakingRate: 1.05, pitch: 1.0  }, // slightly brighter
    }[emotionalState] || { speakingRate: 1.0, pitch: 0.0 };

    const googleKey = GOOGLE_TTS_KEY.value();

    if (googleKey) {
      // ---- Google Cloud TTS ----
      const fetch = (await import('node-fetch')).default;
      const body = {
        input: { text: safeText },
        voice: {
          languageCode: 'en-US',
          name:         'en-US-Journey-F',  // Neural2/Journey — warm, natural
          ssmlGender:   'FEMALE',
        },
        audioConfig: {
          audioEncoding: 'LINEAR16',
          sampleRateHertz: 24000,
          speakingRate:    voiceParams.speakingRate,
          pitch:           voiceParams.pitch,
        },
      };

      const resp = await fetch(
        `https://texttospeech.googleapis.com/v1/text:synthesize?key=${googleKey}`,
        {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify(body),
        }
      );

      if (!resp.ok) {
        const err = await resp.text();
        console.error('ttsProxy Google TTS error:', err);
        // Fall through to OpenAI fallback
      } else {
        const json = await resp.json();
        const audioBase64 = json.audioContent || '';
        if (audioBase64) {
          return { audio: audioBase64, encoding: 'LINEAR16', sampleRate: 24000 };
        }
      }
    }

    // ---- OpenAI TTS fallback ----
    const fetch = (await import('node-fetch')).default;
    const resp = await fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: {
        'Content-Type':  'application/json',
        'Authorization': `Bearer ${OPENAI_API_KEY.value()}`,
      },
      body: JSON.stringify({
        model:           'tts-1',
        input:           safeText,
        voice:           emotionalState === 'distressed' ? 'shimmer' : 'nova',
        response_format: 'pcm',          // raw 24 kHz 16-bit PCM
        speed:           voiceParams.speakingRate,
      }),
    });

    if (!resp.ok) {
      const err = await resp.text();
      console.error('ttsProxy OpenAI TTS error:', err);
      throw new functions.https.HttpsError('internal', 'TTS service error.');
    }

    const audioBuffer = await resp.buffer();
    const audioBase64 = audioBuffer.toString('base64');

    return { audio: audioBase64, encoding: 'LINEAR16', sampleRate: 24000 };
  });
