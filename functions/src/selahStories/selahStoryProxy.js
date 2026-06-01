/**
 * selahStoryProxy.js
 * AMEN App — Selah Stories proxy callable (Master Run A8)
 *
 * Deploy status:
 *   - createStory / deleteStory: fully implemented, safe to deploy.
 *   - generateReflectionPrompt: implemented — requires ANTHROPIC_API_KEY secret.
 *   - recognizeVerse: implemented — requires GOOGLE_APPLICATION_CREDENTIALS / ADC.
 *   - matchAudio: stub — [NEEDS HUMAN DEPLOY] after Pinecone index is provisioned.
 *
 * Security:
 *   - App Check enforced (enforceAppCheck: true).
 *   - Auth required — unauthenticated callers receive HttpsError('unauthenticated').
 *   - mediaURL ownership enforced: path must contain /${uid}/.
 *
 * Input (request.data):
 *   {
 *     action:  "recognizeVerse" | "generateReflectionPrompt" | "matchAudio"
 *            | "createStory"   | "deleteStory",
 *     payload: object   // action-specific (see per-case comments)
 *   }
 */

'use strict';

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions/v2');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Fallback reflection prompts keyed by "<book> <chapter>:<verse>" ──────────

const FALLBACK_PROMPTS = {
  'Psalm 23:1':
    'Where do you sense God leading you to still waters in this season?',
  'John 3:16':
    'How does knowing you are loved this deeply change what you are afraid of today?',
  'Romans 8:28':
    'Where have you seen God weaving something difficult into something purposeful in your own story?',
  'Philippians 4:13':
    'What task before you today feels impossible, and how might you invite God\'s strength into it?',
  'Isaiah 40:31':
    'Where in your life are you most in need of renewed strength, and what does waiting on God look like for you practically?',
};

const DEFAULT_FALLBACK_PROMPT =
  "What does this passage reveal about God's character to you today?";

// ─── Main export ──────────────────────────────────────────────────────────────

exports.selahStoryProxy = onCall(
  { enforceAppCheck: true },
  async (request) => {
    // 1. Auth guard
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Login required');
    }

    const uid = request.auth.uid;
    const { action, payload } = request.data ?? {};

    // 2. Input validation
    if (!action || typeof action !== 'string') {
      throw new HttpsError('invalid-argument', 'action required');
    }

    // 3. Route to action handler
    switch (action) {

      // ── recognizeVerse ──────────────────────────────────────────────────────
      case 'recognizeVerse': {
        /*
         * Uses @google-cloud/vision TEXT_DETECTION to extract text from the
         * base64-encoded image, then applies a regex to pull a scripture ref.
         */
        const imageData = payload?.imageData;
        if (!imageData || typeof imageData !== 'string') {
          throw new HttpsError('invalid-argument', 'payload.imageData (base64) required');
        }

        if (!process.env.GOOGLE_APPLICATION_CREDENTIALS &&
            !process.env.FUNCTION_TARGET /* not running on GCP */) {
          logger.warn('recognizeVerse: GOOGLE_APPLICATION_CREDENTIALS not set — returning low-confidence fallback');
          return { book: null, chapter: null, verse: null, confidence: 'low', rawText: '' };
        }

        try {
          const vision = require('@google-cloud/vision');
          const client = new vision.ImageAnnotatorClient();

          const [result] = await client.textDetection({
            image: { content: imageData },
          });

          const extractedText = result.fullTextAnnotation?.text ?? '';

          // Match patterns like "Psalm 23:1", "1 Corinthians 13:4", "2 Tim 3:16"
          const scripturePattern = /(\d?\s?[A-Za-z]+)\s+(\d+):(\d+)/g;
          const match = scripturePattern.exec(extractedText);

          if (match) {
            return {
              book: match[1].trim(),
              chapter: parseInt(match[2], 10),
              verse: parseInt(match[3], 10),
              confidence: 'high',
            };
          }

          return {
            book: null,
            chapter: null,
            verse: null,
            confidence: 'low',
            rawText: extractedText.slice(0, 200),
          };
        } catch (err) {
          logger.error('recognizeVerse: Vision API error', err);
          return {
            book: null,
            chapter: null,
            verse: null,
            confidence: 'low',
            rawText: '',
          };
        }
      }

      // ── generateReflectionPrompt ────────────────────────────────────────────
      case 'generateReflectionPrompt': {
        /*
         * Calls Claude (claude-3-haiku) to generate a single spiritually-
         * formative reflection question grounded in the given scripture ref.
         * Falls back to a hardcoded map if ANTHROPIC_API_KEY is absent.
         * [NEEDS HUMAN DEPLOY] — ANTHROPIC_API_KEY must be set as a secret.
         */
        const scriptureRef = payload?.scriptureRef;
        if (!scriptureRef?.book || !scriptureRef?.chapter || !scriptureRef?.verse) {
          throw new HttpsError(
            'invalid-argument',
            'payload.scriptureRef { book, chapter, verse } required'
          );
        }

        const { book, chapter, verse } = scriptureRef;
        const theme = payload?.theme ?? null;
        const refKey = `${book} ${chapter}:${verse}`;

        if (!process.env.ANTHROPIC_API_KEY) {
          logger.warn('generateReflectionPrompt: ANTHROPIC_API_KEY not set — returning fallback prompt');
          const prompt = FALLBACK_PROMPTS[refKey] ?? DEFAULT_FALLBACK_PROMPT;
          return { prompt };
        }

        try {
          const Anthropic = require('@anthropic-ai/sdk');
          const anthropic = new Anthropic.default({ apiKey: process.env.ANTHROPIC_API_KEY });

          const systemPrompt =
            'You are Berean, a scripture-grounded spiritual companion for the AMEN app. ' +
            'Generate a single, open-ended reflection question (1-2 sentences) grounded in ' +
            'the given scripture passage. The question should invite personal reflection ' +
            'without being prescriptive. Do not use phrases like "How does this make you ' +
            'feel". Keep it spiritually formative and rooted in the text.';

          const userMsg =
            `Generate a reflection prompt for ${book} ${chapter}:${verse}` +
            (theme ? ` (theme: ${theme})` : '') + '.';

          const message = await anthropic.messages.create({
            model: 'claude-3-haiku-20240307',
            max_tokens: 150,
            messages: [{ role: 'user', content: userMsg }],
            system: systemPrompt,
          });

          const prompt =
            message.content[0]?.text ??
            (FALLBACK_PROMPTS[refKey] ?? DEFAULT_FALLBACK_PROMPT);

          return { prompt };
        } catch (err) {
          logger.error('generateReflectionPrompt: Anthropic API error', err);
          const prompt = FALLBACK_PROMPTS[refKey] ?? DEFAULT_FALLBACK_PROMPT;
          return { prompt };
        }
      }

      // ── matchAudio ──────────────────────────────────────────────────────────
      case 'matchAudio': {
        /*
         * [NEEDS HUMAN DEPLOY] — Pinecone audio-tracks index not yet provisioned.
         * Real implementation:
         *   a. Embed payload.theme via OpenAI embeddings (OPENAI_API_KEY secret)
         *   b. Query Pinecone audio-tracks index for nearest neighbours
         *   c. Return top result as AudioTrackRef with a signed Storage URL
         */
        logger.info('matchAudio: Pinecone not yet configured — returning default track');
        return {
          id: 'psalm23-instrumental',
          title: 'Still Waters',
          artistName: 'Formation Audio',
          url: '',
          durationSeconds: 240,
        };
      }

      // ── createStory ─────────────────────────────────────────────────────────
      case 'createStory': {
        /*
         * Validates the media URL, writes a new SelahStory doc to Firestore,
         * and returns the server-generated storyId.
         */
        const {
          scriptureRef = null,
          reflectionText = null,
          reflectionPrompt = null,
          audioTrackId = null,
          mediaURL,
          visibility,
          audienceIds = [],
          shareToFeed = false,
          liturgicalSeason = null,
        } = payload ?? {};

        // Validate required fields
        if (!mediaURL || typeof mediaURL !== 'string') {
          throw new HttpsError('invalid-argument', 'payload.mediaURL required');
        }
        if (!visibility || !['closeFriends', 'churchGroup', 'accountabilityPartner'].includes(visibility)) {
          throw new HttpsError(
            'invalid-argument',
            'payload.visibility must be one of: closeFriends, churchGroup, accountabilityPartner'
          );
        }

        // Ownership check: mediaURL must be gs:// and path must contain /${uid}/
        if (!mediaURL.startsWith('gs://')) {
          throw new HttpsError('invalid-argument', 'payload.mediaURL must be a gs:// path');
        }
        if (!mediaURL.includes(`/${uid}/`)) {
          throw new HttpsError(
            'permission-denied',
            'mediaURL path does not belong to the authenticated user'
          );
        }

        // Server-side storyId
        const storyRef = db.collection('selahStories').doc();
        const storyId = storyRef.id;

        // expiresAt: 24 hours from now
        const expiresAt = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 24 * 60 * 60 * 1000)
        );

        await storyRef.set({
          id: storyId,
          authorId: uid,
          audienceIds,
          visibility,
          scriptureRef: scriptureRef ?? null,
          reflectionText: reflectionText ?? null,
          reflectionPrompt: reflectionPrompt ?? null,
          audioTrackId: audioTrackId ?? null,
          mediaURL,
          liturgicalSeason: liturgicalSeason ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt,
          isActive: true,
          shareToFeed: shareToFeed === true,
        });

        logger.info(`createStory: created ${storyId} for uid=${uid}`);
        return { storyId };
      }

      // ── deleteStory ─────────────────────────────────────────────────────────
      case 'deleteStory': {
        /*
         * Verifies ownership, deletes the Firestore document, and attempts to
         * delete the associated Storage object.
         */
        const { storyId } = payload ?? {};
        if (!storyId || typeof storyId !== 'string') {
          throw new HttpsError('invalid-argument', 'payload.storyId required');
        }

        const docRef = db.collection('selahStories').doc(storyId);
        const docSnap = await docRef.get();

        if (!docSnap.exists) {
          throw new HttpsError('not-found', `Story ${storyId} not found`);
        }

        const data = docSnap.data();
        if (data.authorId !== uid) {
          throw new HttpsError('permission-denied', 'You do not own this story');
        }

        // Delete Firestore document
        await docRef.delete();
        logger.info(`deleteStory: deleted Firestore doc ${storyId} for uid=${uid}`);

        // Attempt Storage deletion — non-fatal if it fails
        const mediaURL = data.mediaURL;
        if (mediaURL && mediaURL.startsWith('gs://')) {
          try {
            // gs://bucket-name/path/to/file  →  strip "gs://bucket-name/"
            const withoutScheme = mediaURL.slice('gs://'.length);
            const slashIndex = withoutScheme.indexOf('/');
            const bucketName = withoutScheme.slice(0, slashIndex);
            const storagePath = withoutScheme.slice(slashIndex + 1);

            await admin.storage().bucket(bucketName).file(storagePath).delete();
            logger.info(`deleteStory: deleted Storage object ${storagePath}`);
          } catch (storageErr) {
            // Log but do not fail — doc is already deleted
            logger.warn(`deleteStory: Storage deletion failed for ${mediaURL}`, storageErr);
          }
        }

        return { success: true };
      }

      // ── unknown action ──────────────────────────────────────────────────────
      default:
        throw new HttpsError('invalid-argument', `Unknown action: ${action}`);
    }
  }
);
