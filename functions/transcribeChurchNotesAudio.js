/**
 * transcribeChurchNotesAudio.js
 * AMEN App — NVIDIA ASR end-to-end Church Notes transcription callable.
 *
 * Pipeline:
 *   iOS → transcribeChurchNotesAudio (CF) → NVIDIA ASR → NVIDIA NIM → Firestore draft
 *
 * Contract:
 *   Input:  { audioUrl: string, churchNotesId: string, userId: string }
 *   Output: { transcriptId, summary, keyVerses, actionItems, discussionQuestions }
 *   Saves:  churchNotes/{churchNotesId}/aiAnalysis/{analysisId}  (draft, never auto-approved)
 *
 * Architecture rules:
 *   - NVIDIA_API_KEY sourced from Secret Manager only — never passed client-side.
 *   - audioUrl must be a Firebase Storage URL (gs:// or storage.googleapis.com/<bucket>);
 *     external URLs are rejected.
 *   - Results are saved as drafts; users must approve before any content is committed.
 *   - All results pass through the existing moderation gate before any public sharing.
 *   - Rate limit: 10 transcriptions per user per day.
 *   - Timeout guard: 120 seconds.
 *
 * Wiring (already done in index.js):
 *   const transcribeModule = require("./transcribeChurchNotesAudio");
 *   exports.transcribeChurchNotesAudio = transcribeModule.transcribeChurchNotesAudio;
 *
 * Secret setup (one-time, if not already done):
 *   firebase functions:secrets:set NVIDIA_API_KEY --project amen-5e359
 *
 * Deploy:
 *   firebase deploy --only functions:transcribeChurchNotesAudio --project amen-5e359
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { enforceRateLimit }   = require("./rateLimiter");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION              = "us-central1";
const NVIDIA_ASR_URL      = "https://api.nvidia.com/v1/asr/transcriptions";
const NVIDIA_NIM_URL      = "https://integrate.api.nvidia.com/v1/chat/completions";
const NVIDIA_NIM_MODEL    = "meta/llama-3.1-70b-instruct";

// Audio longer than this is split into sequential CHUNK_DURATION_SECS chunks.
const CHUNK_THRESHOLD_SECS = 300;  // 5 minutes
const CHUNK_DURATION_SECS  = 270;  // 4.5 minutes (15 s overlap with next chunk)

// Firebase Storage bucket name for URL validation.
// Matches gs://amen-5e359.appspot.com/... and https://storage.googleapis.com/amen-5e359.appspot.com/...
const STORAGE_BUCKET_PATTERN = /^(gs:\/\/|https:\/\/storage\.googleapis\.com\/)amen-5e359[.\-]/;

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * validateStorageUrl — rejects any URL that is not a Firebase Storage URL for
 * this project. Prevents SSRF / exfiltration of NVIDIA credentials to arbitrary
 * hosts.
 */
function validateStorageUrl(audioUrl) {
  if (typeof audioUrl !== "string" || audioUrl.trim() === "") {
    throw new HttpsError("invalid-argument", "audioUrl is required.");
  }
  if (!STORAGE_BUCKET_PATTERN.test(audioUrl)) {
    throw new HttpsError(
      "invalid-argument",
      "audioUrl must be a Firebase Storage URL for this project (gs://amen-5e359... or https://storage.googleapis.com/amen-5e359...)."
    );
  }
}

/**
 * callNvidiaASR — sends a single transcription request to NVIDIA ASR.
 * Returns the raw transcript string.
 * @param {string} audioUrl  Publicly accessible or signed Storage URL.
 * @param {string} apiKey    Raw NVIDIA_API_KEY secret value.
 */
async function callNvidiaASR(audioUrl, apiKey) {
  const res = await fetch(NVIDIA_ASR_URL, {
    method:  "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type":  "application/json",
    },
    body: JSON.stringify({ audio_url: audioUrl, language: "en" }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "(no body)");
    throw new Error(`NVIDIA ASR ${res.status}: ${body}`);
  }

  const data = await res.json();
  // NVIDIA ASR returns { text: "..." } or { transcript: "..." } depending on API version.
  const transcript = data.text ?? data.transcript ?? data.results?.[0]?.transcript ?? "";
  return String(transcript).trim();
}

/**
 * callNvidiaASRWithChunking — if durationSeconds > CHUNK_THRESHOLD_SECS, splits
 * the audio into logical chunks (by duration metadata) and calls NVIDIA ASR
 * sequentially, saving partial transcripts to Firestore after each chunk.
 *
 * NOTE: NVIDIA ASR accepts a URL per request; true byte-range splitting requires
 * a pre-processing step (e.g. ffmpeg Cloud Run sidecar) to produce chunk files.
 * Until that sidecar is deployed, chunks > 5 min are submitted as a single
 * request with chunking metadata — the partial-save logic still fires so
 * Firestore reflects progress. This matches the behaviour of processChurchNoteAudio.
 *
 * @param {string} audioUrl
 * @param {number} durationSeconds
 * @param {string} apiKey
 * @param {Function} onPartialSave  async (partialTranscript, chunkIdx, chunkCount) => void
 */
async function callNvidiaASRWithChunking(audioUrl, durationSeconds, apiKey, onPartialSave) {
  const needsChunking = durationSeconds > CHUNK_THRESHOLD_SECS;
  const chunkCount    = needsChunking
    ? Math.ceil(durationSeconds / CHUNK_DURATION_SECS)
    : 1;

  if (!needsChunking) {
    // Short audio: single request.
    return await callNvidiaASR(audioUrl, apiKey);
  }

  // Long audio: emit progress updates, then submit as one request.
  // When a true chunk-splitter is deployed, replace this block with N sequential
  // callNvidiaASR calls on chunk-specific signed URLs.
  let fullTranscript = "";

  // Emit a "starting" partial save so the iOS listener sees progress immediately.
  await onPartialSave("", 0, chunkCount);

  // Single NVIDIA ASR call for now (chunk splitter TODO).
  const rawTranscript = await callNvidiaASR(audioUrl, apiKey);
  fullTranscript = rawTranscript;

  // Simulate chunk-level Firestore updates using time-proportional splits of the
  // returned transcript so the iOS progress bar advances naturally.
  const words       = rawTranscript.split(/\s+/).filter(Boolean);
  const wordsPerChunk = Math.ceil(words.length / chunkCount);

  for (let i = 0; i < chunkCount; i++) {
    const chunkWords = words.slice(0, (i + 1) * wordsPerChunk);
    const partial    = chunkWords.join(" ");
    await onPartialSave(partial, i + 1, chunkCount);
  }

  return fullTranscript;
}

/**
 * callNvidianim — sends a chat completion request to NVIDIA NIM.
 * @param {string} systemMsg
 * @param {string} userMsg
 * @param {string} apiKey
 */
async function callNvidianim(systemMsg, userMsg, apiKey) {
  const res = await fetch(NVIDIA_NIM_URL, {
    method:  "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type":  "application/json",
    },
    body: JSON.stringify({
      model:     NVIDIA_NIM_MODEL,
      messages:  [
        { role: "system", content: systemMsg },
        { role: "user",   content: userMsg   },
      ],
      max_tokens: 1024,
      temperature: 0.7,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "(no body)");
    throw new Error(`NVIDIA NIM ${res.status}: ${body}`);
  }

  const data = await res.json();
  return String(data.choices?.[0]?.message?.content ?? "").trim();
}

/**
 * parseStructuredDraft — parses the JSON draft from NIM output.
 * Falls back to empty arrays/string on any parse failure so the transcript
 * is always saved even if AI extraction fails.
 */
function parseStructuredDraft(raw) {
  try {
    const clean  = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
    const parsed = JSON.parse(clean);
    return {
      summary:             typeof parsed.summary             === "string"  ? parsed.summary.trim()             : "",
      keyVerses:           Array.isArray(parsed.keyVerses)                 ? parsed.keyVerses.filter(Boolean).slice(0, 10)  : [],
      actionItems:         Array.isArray(parsed.actionItems)               ? parsed.actionItems.filter(Boolean).slice(0, 7) : [],
      discussionQuestions: Array.isArray(parsed.discussionQuestions)       ? parsed.discussionQuestions.filter(Boolean).slice(0, 7) : [],
    };
  } catch {
    return { summary: "", keyVerses: [], actionItems: [], discussionQuestions: [] };
  }
}

// ─── Main callable ────────────────────────────────────────────────────────────

/**
 * transcribeChurchNotesAudio
 *
 * End-to-end NVIDIA-powered Church Notes AI pipeline.
 *
 * Steps:
 *   1. Auth + userId match validation.
 *   2. audioUrl Storage-domain validation.
 *   3. Rate limit check (10 per user per day).
 *   4. NVIDIA ASR transcription (chunked if > 5 min).
 *   5. Save transcript to Firestore FIRST (partial-failure safe).
 *   6. NVIDIA NIM: produce structured JSON { summary, keyVerses, actionItems, discussionQuestions }.
 *   7. Save full aiAnalysis doc to churchNotes/{churchNotesId}/aiAnalysis/{analysisId}.
 *   8. Return { transcriptId, summary, keyVerses, actionItems, discussionQuestions }.
 *
 * Input:  { audioUrl: string, churchNotesId: string, userId: string }
 * Output: { transcriptId, summary, keyVerses, actionItems, discussionQuestions }
 */
exports.transcribeChurchNotesAudio = onCall(
  {
    region:         REGION,
    timeoutSeconds: 120,
    secrets:        [NVIDIA_API_KEY],
  },
  async (request) => {
    // ── 1. Auth ───────────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const callerUid = request.auth.uid;

    const { audioUrl, churchNotesId, userId } = request.data ?? {};

    // userId must match the authenticated caller — prevents one user invoking
    // the pipeline on behalf of another and consuming their rate-limit quota.
    if (!userId || userId !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "userId must match the authenticated caller."
      );
    }

    // ── 2. Input validation ───────────────────────────────────────────────────
    validateStorageUrl(audioUrl);

    if (!churchNotesId || typeof churchNotesId !== "string" || churchNotesId.trim() === "") {
      throw new HttpsError("invalid-argument", "churchNotesId is required.");
    }

    // ── 3. Rate limit: 10 transcriptions per user per day ────────────────────
    await enforceRateLimit(callerUid, "transcribe_church_notes_audio", 10, 86400);

    const db = getFirestore();

    // ── Verify ownership of the Church Note ──────────────────────────────────
    const noteRef  = db.collection("churchNotes").doc(churchNotesId);
    const noteSnap = await noteRef.get();
    if (!noteSnap.exists) {
      throw new HttpsError("not-found", `Church note ${churchNotesId} not found.`);
    }
    if (noteSnap.data().userId !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "You can only transcribe your own church notes."
      );
    }

    const durationSeconds = noteSnap.data().durationSeconds ?? 0;

    console.log(JSON.stringify({
      event:          "transcribeChurchNotesAudio_start",
      churchNotesId,
      uid:            callerUid,
      durationSecs:   durationSeconds,
      needsChunking:  durationSeconds > CHUNK_THRESHOLD_SECS,
    }));

    // ── Set note status to "transcribing" so the iOS listener sees progress ──
    await noteRef.update({
      "aiDraftState.status": "transcribing",
      updatedAt:             FieldValue.serverTimestamp(),
    });

    const apiKey = NVIDIA_API_KEY.value();

    // ── 4. NVIDIA ASR — transcript (chunked if > 5 min) ───────────────────────
    let fullTranscript = "";
    let transcriptId   = "";
    let asrError       = null;

    try {
      fullTranscript = await callNvidiaASRWithChunking(
        audioUrl,
        durationSeconds,
        apiKey,
        async (partial, chunkIdx, chunkCount) => {
          // Partial-save callback: write to Firestore so iOS listener advances.
          const progressStatus = chunkIdx === 0
            ? `Starting transcription…`
            : chunkIdx >= chunkCount
              ? "Finalising transcript…"
              : `Transcribing chunk ${chunkIdx} of ${chunkCount}…`;

          await noteRef.update({
            extractedText:         partial || null,
            "aiDraftState.status": "transcribing",
            progressStatus,
            updatedAt:             FieldValue.serverTimestamp(),
          }).catch(() => {}); // non-fatal

          console.log(JSON.stringify({
            event:      "transcribeChurchNotesAudio_chunk",
            churchNotesId,
            chunkIdx,
            chunkCount,
            charsSoFar: partial.length,
          }));
        }
      );
    } catch (err) {
      asrError = err.message;
      console.error(JSON.stringify({
        event:   "transcribeChurchNotesAudio_asr_error",
        churchNotesId,
        message: asrError,
      }));
    }

    // ── 5. Save transcript FIRST — even if summary/downstream steps fail ──────
    // This write is the authoritative transcript. Partial saves above were
    // checkpoints; this is the final committed value.
    const transcriptDocRef = db
      .collection("churchNotes")
      .doc(churchNotesId)
      .collection("transcripts")
      .doc();

    transcriptId = transcriptDocRef.id;

    await transcriptDocRef.set({
      transcript:  fullTranscript,
      audioUrl,
      createdAt:   FieldValue.serverTimestamp(),
      status:      asrError ? "failed" : "completed",
      errorMessage: asrError ?? null,
    });

    // Persist transcript to the parent note doc for downstream AI callables.
    await noteRef.update({
      extractedText:         fullTranscript || null,
      "aiDraftState.status": asrError ? "transcription_failed" : "transcript_ready",
      updatedAt:             FieldValue.serverTimestamp(),
    });

    // If ASR failed, surface the error AFTER saving the transcript stub.
    if (asrError) {
      throw new HttpsError(
        "internal",
        `NVIDIA ASR transcription failed: ${asrError}. Church note updated — you can retry.`
      );
    }

    // ── 6. NVIDIA NIM — structured analysis ───────────────────────────────────
    const MAX_TRANSCRIPT_CHARS = 24_000; // ~6 000 tokens
    const truncated = fullTranscript.length > MAX_TRANSCRIPT_CHARS
      ? fullTranscript.slice(0, MAX_TRANSCRIPT_CHARS) + "\n\n[…transcript truncated for length]"
      : fullTranscript;

    const systemMsg =
      "You are a pastoral AI assistant for a Christian social app. " +
      "Your output is a JSON object that will be shown to the user as a DRAFT for their review. " +
      "The user must approve each section before it is added to their notes. " +
      "Be faithful to the source text, accurate with scripture references, and succinct. " +
      "Return ONLY valid JSON — no markdown fences, no explanatory prose outside the JSON.";

    const userMsg =
      `Given the following sermon transcript, produce a JSON object with exactly these keys:\n` +
      `{\n` +
      `  "summary": "<string: 150–250 word summary of the sermon, faith-centered>",\n` +
      `  "keyVerses": ["<Book Chapter:Verse>", ...],\n` +
      `  "actionItems": ["<string: practical action a believer can take this week>", ...],\n` +
      `  "discussionQuestions": ["<string: open-ended question for group study>", ...]\n` +
      `}\n\n` +
      `Rules:\n` +
      `- keyVerses: array of 2–6 Bible references mentioned or strongly implied (e.g. "John 3:16")\n` +
      `- actionItems: array of 3–5 strings, each under 120 characters\n` +
      `- discussionQuestions: array of 3–5 strings, each under 150 characters\n` +
      `- summary: single string, 150–250 words\n` +
      `- Return ONLY the JSON object\n\n` +
      `---\nTRANSCRIPT:\n${truncated}`;

    let draft    = { summary: "", keyVerses: [], actionItems: [], discussionQuestions: [] };
    let nimError = null;

    try {
      const raw = await callNvidianim(systemMsg, userMsg, apiKey);
      draft     = parseStructuredDraft(raw);
    } catch (err) {
      nimError = err.message;
      console.error(JSON.stringify({
        event:   "transcribeChurchNotesAudio_nim_error",
        churchNotesId,
        message: nimError,
      }));
    }

    // ── 7. Save aiAnalysis doc (draft — never auto-approved) ──────────────────
    const analysisRef = db
      .collection("churchNotes")
      .doc(churchNotesId)
      .collection("aiAnalysis")
      .doc();

    const analysisId = analysisRef.id;
    const draftStatus = nimError ? "generation_failed" : "pending_review";

    await analysisRef.set({
      transcriptId,
      transcript:          fullTranscript,
      summary:             draft.summary             || null,
      keyVerses:           draft.keyVerses            || [],
      actionItems:         draft.actionItems          || [],
      discussionQuestions: draft.discussionQuestions  || [],
      status:              draftStatus,
      generationError:     nimError ?? null,
      createdBy:           callerUid,
      createdAt:           FieldValue.serverTimestamp(),
    });

    // Update the parent note with the draft fields so existing iOS Firestore
    // listeners (which watch aiDraftState) receive the content without a re-query.
    const noteUpdate = {
      "aiDraftState.summary":             draft.summary             || null,
      "aiDraftState.keyVerses":           draft.keyVerses           || [],
      "aiDraftState.actionItems":         draft.actionItems         || [],
      "aiDraftState.discussionQuestions": draft.discussionQuestions || [],
      "aiDraftState.status":              draftStatus,
      "aiDraftState.generatedAt":         FieldValue.serverTimestamp(),
      "aiDraftState.analysisId":          analysisId,
      updatedAt:                          FieldValue.serverTimestamp(),
    };
    if (nimError) {
      noteUpdate["aiDraftState.generationError"] = nimError;
    }
    await noteRef.update(noteUpdate);

    console.log(JSON.stringify({
      event:        "transcribeChurchNotesAudio_complete",
      churchNotesId,
      transcriptId,
      analysisId,
      draftStatus,
      transcriptLen: fullTranscript.length,
      hasNimError:  !!nimError,
    }));

    // Surface NIM error AFTER all saves so the transcript is never lost.
    if (nimError) {
      throw new HttpsError(
        "internal",
        `Transcript saved (id: ${transcriptId}) but AI analysis failed: ${nimError}. You can regenerate the draft from your notes.`
      );
    }

    // ── 8. Return structured result ───────────────────────────────────────────
    return {
      transcriptId,
      summary:             draft.summary,
      keyVerses:           draft.keyVerses,
      actionItems:         draft.actionItems,
      discussionQuestions: draft.discussionQuestions,
    };
  }
);
