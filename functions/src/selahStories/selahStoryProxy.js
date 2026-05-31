/**
 * selahStoryProxy.js
 * AMEN App — Selah Stories AI proxy callable (Phase 5 / Master Run A8)
 *
 * [NEEDS HUMAN DEPLOY] to production Firebase.
 * Safe to run in the Firebase Emulator Suite only.
 *
 * Purpose:
 *   Acts as the sole backend proxy for all Selah Stories AI operations.
 *   No AI credentials (Vertex AI Vision, Berean KG, Pinecone) ever touch
 *   the device — all AI keys must remain server-side.
 *
 * Security:
 *   - App Check enforced (enforceAppCheck: true) — invalid/spoofed apps are
 *     rejected before the function body runs.
 *   - Auth required — unauthenticated callers receive HttpsError('unauthenticated').
 *
 * Input (request.data):
 *   {
 *     action:  "recognizeVerse" | "generateReflectionPrompt" | "matchAudio"
 *            | "createStory"   | "deleteStory",
 *     payload: object   // action-specific payload (see per-case comments below)
 *   }
 *
 * Output:
 *   Action-specific response object (see per-case comments below).
 *
 * Implementation path:
 *   Each case has a TODO block describing the real integration:
 *   - recognizeVerse:          Vertex AI Vision OCR → Berean KG scripture match
 *   - generateReflectionPrompt: Berean-assisted prompt generation (Living Memory)
 *   - matchAudio:              Pinecone semantic search (theme + liturgical season)
 *   - createStory:             Write SelahStory to Firestore + Storage URL handling
 *   - deleteStory:             Verify ownership, delete Firestore doc + Storage media
 *   All AI/search keys must live in Firebase Secret Manager (defineSecret), never
 *   passed from the client.
 *
 * Emulator usage:
 *   firebase emulators:start --only functions
 *   (iOS points to http://localhost:5001 via useEmulator in AppDelegate)
 */

'use strict';

const functions = require('firebase-functions/v2');

// ─── Main export ──────────────────────────────────────────────────────────────

exports.selahStoryProxy = functions.https.onCall(
  { enforceAppCheck: true },
  async (request) => {
    // 1. Auth guard
    if (!request.auth?.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'Login required');
    }

    const uid = request.auth.uid;
    const { action, payload } = request.data;

    // 2. Input validation
    if (!action || typeof action !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'action required');
    }

    // 3. Route to action handler
    switch (action) {
      case 'recognizeVerse':
        // TODO: real OCR + scripture matching
        //   a. Receive imageURL or base64 from payload.imageData
        //   b. Call Vertex AI Vision (GOOGLE_VISION_API_KEY via defineSecret)
        //      to extract text regions from the image
        //   c. Run extracted text through Berean Knowledge Graph to resolve
        //      to a canonical ScriptureRef { book, chapter, verse }
        //   d. Return the best-confidence match (or array for ambiguous images)
        // Mock: return a plausible ScriptureRef for emulator
        return { book: 'Psalms', chapter: 23, verse: 1 };

      case 'generateReflectionPrompt':
        // TODO: Berean-assisted prompt generation
        //   a. Read payload.scriptureRef { book, chapter, verse }
        //   b. Fetch the user's Living Memory context from Firestore
        //      (users/{uid}/livingMemory) to personalize the prompt
        //   c. Call Berean / Claude with scripture text + user context
        //   d. Return a single spiritually-grounded reflection prompt string
        // Mock: return a generic prompt for emulator
        return {
          prompt: "What does this passage reveal about God's character to you today?",
        };

      case 'matchAudio':
        // TODO: Pinecone semantic search for worship / instrumental audio
        //   a. Read payload.theme (string) + payload.liturgicalSeason (optional)
        //   b. Generate a query embedding via OpenAI embeddings
        //      (OPENAI_API_KEY via defineSecret)
        //   c. Query the Pinecone audio-tracks index for nearest neighbours
        //   d. Return the top result as an AudioTrackRef { id, title, artistName,
        //      url (signed Storage URL), durationSeconds }
        //   The track URL must be a short-lived signed URL — never a raw gs:// path.
        // Mock: return a representative Formation Audio track for emulator
        return {
          id: 'psalm23-instrumental',
          title: 'Still Waters',
          artistName: 'Formation Audio',
          url: '',
          durationSeconds: 240,
        };

      case 'createStory':
        // TODO: write SelahStory to Firestore + handle Storage media URL
        //   a. Validate payload.mediaURL is a valid gs:// path owned by uid
        //   b. Write a new doc to selahStories/{storyId} with:
        //      { uid, scriptureRef, reflectionPrompt, audioTrackId, mediaURL,
        //        createdAt: serverTimestamp(), visibility: payload.visibility }
        //   c. Fanout: if payload.shareToFeed === true, call finalizePostPublish
        //   d. Return { storyId } (server-generated, not client-supplied)
        // Mock: return a deterministic storyId for emulator
        return { storyId: `story_${uid}_${Date.now()}` };

      case 'deleteStory':
        // TODO: verify ownership, delete Firestore doc + Storage media
        //   a. Read payload.storyId
        //   b. Fetch selahStories/{storyId} — throw permission-denied if uid !== doc.uid
        //   c. Delete the Storage object at doc.mediaURL (admin.storage())
        //   d. Delete the Firestore document
        //   e. If the story was shared to feed, soft-delete the linked post
        // Mock: return success for emulator
        return { success: true };

      default:
        throw new functions.https.HttpsError(
          'invalid-argument',
          `Unknown action: ${action}`
        );
    }
  }
);
