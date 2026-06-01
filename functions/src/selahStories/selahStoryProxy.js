/**
 * selahStoryProxy.js
 * AMEN App — Selah Stories proxy callable (Master Run A8)
 *
 * Deploy status:
 *   - createStory / deleteStory: fully implemented, safe to deploy.
 *   - generateReflectionPrompt: implemented — requires ANTHROPIC_API_KEY secret.
 *   - recognizeVerse: implemented — requires GOOGLE_APPLICATION_CREDENTIALS / ADC.
 *   - matchAudio: fail-closed until Pinecone index is provisioned.
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
const { defineSecret } = require('firebase-functions/params');

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REGION = 'us-central1';
const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const PINECONE_API_KEY = defineSecret('PINECONE_API_KEY');
const PINECONE_HOST = defineSecret('PINECONE_HOST');

const callableOptions = {
  region: REGION,
  enforceAppCheck: true,
  secrets: [ANTHROPIC_API_KEY, OPENAI_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
  timeoutSeconds: 60,
};

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Login required');
  }
  return request.auth.uid;
}

function secretValue(secret, envName) {
  try {
    return secret.value() || process.env[envName] || '';
  } catch {
    return process.env[envName] || '';
  }
}

function normalizeActionRequest(request, fixedAction = null) {
  if (fixedAction) {
    return {
      uid: requireAuth(request),
      action: fixedAction,
      payload: request.data ?? {},
    };
  }

  const uid = requireAuth(request);
  const { action, payload } = request.data ?? {};
  if (!action || typeof action !== 'string') {
    throw new HttpsError('invalid-argument', 'action required');
  }
  return { uid, action, payload: payload ?? {} };
}

function hasUserOwnedStoragePath(url, uid) {
  return typeof url === 'string' && (
    url.includes(`/${uid}/`) ||
    url.includes(`%2F${uid}%2F`) ||
    url.includes(`/${encodeURIComponent(uid)}/`)
  );
}

async function createOpenAIEmbedding(input) {
  const apiKey = secretValue(OPENAI_API_KEY, 'OPENAI_API_KEY');
  if (!apiKey) {
    throw new HttpsError('failed-precondition', 'Audio matching is not configured.');
  }

  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'text-embedding-3-small',
      input: input.slice(0, 2000),
    }),
  });

  if (!response.ok) {
    logger.error('matchAudio: OpenAI embedding failed', {
      status: response.status,
      body: await response.text(),
    });
    throw new HttpsError('internal', 'Audio matching failed.');
  }

  const json = await response.json();
  const embedding = json.data?.[0]?.embedding;
  if (!Array.isArray(embedding)) {
    throw new HttpsError('internal', 'Audio matching failed.');
  }
  return embedding;
}

async function queryPineconeAudio(vector, season) {
  const apiKey = secretValue(PINECONE_API_KEY, 'PINECONE_API_KEY');
  const host = secretValue(PINECONE_HOST, 'PINECONE_HOST');
  if (!apiKey || !host) {
    throw new HttpsError('failed-precondition', 'Audio matching is not configured.');
  }

  const body = {
    vector,
    topK: 5,
    namespace: 'audio-tracks',
    includeMetadata: true,
  };
  if (season) {
    body.filter = {
      $or: [
        { season: { $eq: season } },
        { liturgicalSeason: { $eq: season } },
      ],
    };
  }

  const response = await fetch(`https://${host}/query`, {
    method: 'POST',
    headers: {
      'Api-Key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    logger.error('matchAudio: Pinecone query failed', {
      status: response.status,
      body: await response.text(),
    });
    throw new HttpsError('internal', 'Audio matching failed.');
  }

  const json = await response.json();
  return Array.isArray(json.matches) ? json.matches : [];
}

function audioFromMatch(match) {
  const metadata = match.metadata ?? {};
  const id = String(metadata.id || metadata.trackId || match.id || '');
  const title = String(metadata.title || '');
  const url = String(metadata.url || metadata.audioURL || metadata.storageURL || '');
  const durationSeconds = Number(metadata.durationSeconds || metadata.duration || 0);

  if (!id || !title || !url || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    return null;
  }

  return {
    id,
    title,
    artistName: metadata.artistName ? String(metadata.artistName) : null,
    url,
    durationSeconds,
  };
}

async function handleSelahStoryAction(request, fixedAction = null) {
  const { uid, action, payload } = normalizeActionRequest(request, fixedAction);

    switch (action) {

      // ── recognizeVerse ──────────────────────────────────────────────────────
      case 'recognizeVerse': {
        /*
         * Uses @google-cloud/vision TEXT_DETECTION to extract text from the
         * base64-encoded image, then applies a regex to pull a scripture ref.
         */
        const imageData = payload?.imageData || payload?.imageBase64;
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
         * Fails closed if ANTHROPIC_API_KEY is absent so production never
         * returns canned prompt content as if it were generated.
         */
        const scriptureRef = payload?.scriptureRef ?? payload;
        if (!scriptureRef?.book || !scriptureRef?.chapter || !scriptureRef?.verse) {
          throw new HttpsError(
            'invalid-argument',
            'payload.scriptureRef { book, chapter, verse } required'
          );
        }

        const { book, chapter, verse } = scriptureRef;
        const theme = payload?.theme ?? null;
        const anthropicKey = secretValue(ANTHROPIC_API_KEY, 'ANTHROPIC_API_KEY');
        if (!anthropicKey) {
          logger.warn('generateReflectionPrompt: ANTHROPIC_API_KEY not set');
          throw new HttpsError(
            'failed-precondition',
            'Reflection prompt generation is not configured.'
          );
        }

        try {
          const Anthropic = require('@anthropic-ai/sdk');
          const AnthropicClient = Anthropic.default || Anthropic;
          const anthropic = new AnthropicClient({ apiKey: anthropicKey });

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
            message.content[0]?.text;

          if (!prompt) {
            throw new Error('Anthropic response did not include prompt text.');
          }

          return { prompt };
        } catch (err) {
          logger.error('generateReflectionPrompt: Anthropic API error', err);
          throw new HttpsError('internal', 'Reflection prompt generation failed.');
        }
      }

      // ── matchAudio ──────────────────────────────────────────────────────────
      case 'matchAudio': {
        const scriptureRef = payload?.scriptureRef ?? payload ?? {};
        const book = scriptureRef.book;
        const chapter = scriptureRef.chapter;
        const verse = scriptureRef.verse ?? null;
        const season = payload?.season ?? scriptureRef.season ?? null;

        if (!book || typeof book !== 'string' || typeof chapter !== 'number') {
          throw new HttpsError('invalid-argument', 'payload { book, chapter } required');
        }

        const queryText = [
          `${book} ${chapter}${verse ? `:${verse}` : ''}`,
          season ? `liturgical season ${season}` : '',
          payload?.theme ? String(payload.theme) : '',
        ].filter(Boolean).join(' ');

        const embedding = await createOpenAIEmbedding(queryText);
        const matches = await queryPineconeAudio(embedding, season);
        const audio = matches.map(audioFromMatch).find(Boolean);

        if (!audio) {
          return null;
        }

        return audio;
      }

      // ── createStory ─────────────────────────────────────────────────────────
      case 'createStory': {
        /*
         * Validates the media URL, writes a new SelahStory doc to Firestore,
         * and returns the server-generated storyId.
         */
        const media = Array.isArray(payload?.media) ? payload.media : [];
        const primaryMedia = media[0] ?? null;
        const mediaURL = payload?.mediaURL ?? primaryMedia?.url;
        const visibility = payload?.visibility ?? payload?.audience;
        const audienceIds = Array.isArray(payload?.audienceIds) ? payload.audienceIds : [];
        const shareToFeed = payload?.shareToFeed === true;
        const liturgicalSeason = payload?.liturgicalSeason ?? null;
        const audioTrackId = payload?.audioTrackId ?? payload?.audio?.id ?? null;

        // Validate required fields
        if (!mediaURL || typeof mediaURL !== 'string') {
          throw new HttpsError('invalid-argument', 'payload.mediaURL or payload.media[0].url required');
        }
        if (!visibility || !['closeFriends', 'churchGroup', 'accountabilityPartner'].includes(visibility)) {
          throw new HttpsError(
            'invalid-argument',
            'payload.visibility/audience must be one of: closeFriends, churchGroup, accountabilityPartner'
          );
        }
        if (payload.ownerUid && payload.ownerUid !== uid) {
          throw new HttpsError('permission-denied', 'ownerUid does not match the authenticated user');
        }

        if ((mediaURL.startsWith('gs://') || mediaURL.startsWith('https://')) &&
            !hasUserOwnedStoragePath(mediaURL, uid)) {
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
          ownerUid: uid,
          authorId: uid,
          audienceIds,
          audience: visibility,
          visibility,
          kind: payload?.kind ?? 'reflection',
          media,
          overlays: Array.isArray(payload?.overlays) ? payload.overlays : [],
          audio: payload?.audio ?? null,
          scriptureRef: payload?.scriptureRef ?? null,
          caption: payload?.caption ?? null,
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

// ─── Main exports ─────────────────────────────────────────────────────────────

exports.selahStoryProxy = onCall(callableOptions, async (request) =>
  handleSelahStoryAction(request)
);

exports.selahRecognizeVerse = onCall(callableOptions, async (request) =>
  handleSelahStoryAction(request, 'recognizeVerse')
);

exports.selahGenerateReflectionPrompt = onCall(callableOptions, async (request) =>
  handleSelahStoryAction(request, 'generateReflectionPrompt')
);

exports.selahMatchAudio = onCall(callableOptions, async (request) =>
  handleSelahStoryAction(request, 'matchAudio')
);

exports.createSelahStory = onCall(callableOptions, async (request) =>
  handleSelahStoryAction(request, 'createStory')
);

exports.deleteSelahStory = onCall(callableOptions, async (request) =>
  handleSelahStoryAction(request, 'deleteStory')
);
