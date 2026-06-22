// churchNotesAICallables.js
// AI-powered Church Notes Cloud Functions for the Amen app.
// All generation uses NVIDIA NIM (meta/llama-3.1-70b-instruct) via the
// OpenAI-compatible endpoint at integrate.api.nvidia.com.
//
// Architecture:
//   iOS → Firebase Callable → Secret Manager (NVIDIA_API_KEY) → NVIDIA/LLM API
//       → Firestore (result saved as draft) → UI (user reviews/approves/rejects)
//   AI output is NEVER auto-posted. All drafts require explicit user approval.
//
// Wiring:
//   1) Require and spread-export from index.js:
//        const churchNotesAI = require("./churchNotesAICallables");
//        Object.assign(exports, churchNotesAI);
//   2) Secret (one-time):
//        firebase functions:secrets:set NVIDIA_API_KEY --project amen-5e359
//   3) Deploy:
//        firebase deploy --only functions:generateChurchNoteSummary,... --project amen-5e359

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { enforceRateLimit } = require("./rateLimiter");

// ─── Constants ────────────────────────────────────────────────────────────────

const NVIDIA_API_KEY = defineSecret("NVIDIA_API_KEY");
const NIM_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const NIM_MODEL = "meta/llama-3.1-70b-instruct";
const REGION = "us-central1";

const VALID_DRAFT_FIELDS = [
  "summary",
  "studyGuide",
  "prayerPrompts",
  "actionItems",
  "scriptures",
  "clipSuggestions",
];

// ─── Shared NIM helper ────────────────────────────────────────────────────────

/**
 * callNIM — sends a chat completion request to NVIDIA NIM.
 * @param {string} prompt      The user-facing prompt.
 * @param {string} systemMsg   The system instruction.
 * @param {string} apiKey      Raw NVIDIA_API_KEY secret value.
 * @returns {Promise<string>}  The model's text response.
 */
async function callNIM(prompt, systemMsg, apiKey) {
  const res = await fetch(NIM_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: NIM_MODEL,
      messages: [
        { role: "system", content: systemMsg },
        { role: "user", content: prompt },
      ],
      max_tokens: 1024,
      temperature: 0.7,
    }),
  });

  if (!res.ok) {
    throw new Error(`NIM ${res.status}: ${await res.text()}`);
  }

  const data = await res.json();
  return data.choices?.[0]?.message?.content ?? "";
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

/**
 * getNoteText — returns the best available text from a note document.
 * Priority: extractedText (from media pipeline) → content (manual notes).
 */
function getNoteText(note) {
  return (note.extractedText || note.content || "").trim();
}

/**
 * requireAuth — throws unauthenticated error if no auth context.
 */
function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/**
 * fetchNote — reads a churchNotes document and throws if missing.
 */
async function fetchNote(db, noteId) {
  const snap = await db.collection("churchNotes").doc(noteId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", `Church note ${noteId} not found.`);
  }
  return snap;
}

/**
 * updateJobStatus — updates a processing job's status field.
 * Safe to call even when jobId is empty/undefined.
 */
async function updateJobStatus(db, jobId, status, extra = {}) {
  if (!jobId) return;
  await db.collection("churchNoteProcessingJobs").doc(jobId).update({
    status,
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  });
}

/**
 * parseJSONArray — tries to extract a JSON array from LLM output.
 * Falls back to wrapping the raw string in an array when parsing fails.
 */
function parseJSONArray(raw) {
  try {
    // Strip markdown code-fence if present
    const cleaned = raw.replace(/```json?\s*/gi, "").replace(/```\s*/g, "").trim();
    const parsed = JSON.parse(cleaned);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    // Return raw text as single-element array so writes never fail silently.
    return [raw.trim()];
  }
}

// ─── Base config shared by all callables ─────────────────────────────────────

const BASE_CONFIG = {
  region: REGION,
  secrets: [NVIDIA_API_KEY],
};

// ─── 0. generateChurchNoteDraft (full-pipeline draft callable) ────────────────

/**
 * generateChurchNoteDraft
 *
 * Single-callable that accepts a transcript (or reads it from the note doc) and
 * returns a fully structured draft object for user review. This is the canonical
 * entry point from iOS after transcription completes.
 *
 * Responsibilities:
 *   - Read transcript from Firestore (note.extractedText) if not supplied inline.
 *   - Call NVIDIA NIM once to produce { summary, keyVerses, actionItems,
 *     discussionQuestions } in a single structured JSON response.
 *   - Save ALL fields to churchNotes/{noteId}.aiDraftState as a draft
 *     (status: "pending_review") — NEVER as approved/committed content.
 *   - Persist draft even if individual field parsing fails (partial-failure safe).
 *   - Update the processing job status to "draft_ready".
 *   - Return the full draft object to iOS for display in ChurchNotesAIDraftReviewView.
 *
 * The user MUST approve each field through approveChurchNoteAIDraft before any
 * text is inserted into the note. This callable does not write to note content.
 *
 * Rate limit: 10 draft-generation calls per user per hour.
 *
 * Input:  { noteId, jobId?, transcript? }
 *   - transcript: optional inline override; if omitted the note's extractedText is used.
 * Output: { success: true, draft: { summary, keyVerses, actionItems, discussionQuestions } }
 */
exports.generateChurchNoteDraft = onCall(
  { ...BASE_CONFIG, timeoutSeconds: 120 },
  async (request) => {
    // ── Auth ──────────────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── Input validation ──────────────────────────────────────────────────────
    const { noteId, jobId, transcript: inlineTranscript } = request.data || {};
    if (!noteId || typeof noteId !== "string" || noteId.trim() === "") {
      throw new HttpsError("invalid-argument", "noteId is required.");
    }

    // ── Rate limit: 10 draft-generation calls per user per hour ──────────────
    await enforceRateLimit(uid, "church_notes_draft_generate", 10, 3600);

    const db = getFirestore();

    // ── Fetch note + ownership check ──────────────────────────────────────────
    const noteSnap = await db.collection("churchNotes").doc(noteId).get();
    if (!noteSnap.exists) {
      throw new HttpsError("not-found", `Church note ${noteId} not found.`);
    }
    const note = noteSnap.data();
    if (note.userId !== uid) {
      throw new HttpsError("permission-denied", "You can only generate drafts for your own notes.");
    }

    // ── Resolve transcript ────────────────────────────────────────────────────
    const transcript = (
      inlineTranscript ||
      note.extractedText ||
      note.content ||
      ""
    ).trim();

    if (!transcript) {
      throw new HttpsError(
        "failed-precondition",
        "No transcript available. Complete audio/OCR processing before generating a draft."
      );
    }

    const MAX_TRANSCRIPT_CHARS = 24_000; // ~6 000 tokens — safe NIM context window
    const truncatedTranscript  = transcript.length > MAX_TRANSCRIPT_CHARS
      ? transcript.slice(0, MAX_TRANSCRIPT_CHARS) + "\n\n[…transcript truncated for length]"
      : transcript;

    console.log(JSON.stringify({
      event:            "generateChurchNoteDraft_start",
      noteId,
      jobId:            jobId || null,
      uid,
      transcriptLength: transcript.length,
      truncated:        transcript.length > MAX_TRANSCRIPT_CHARS,
    }));

    // ── Set draft status to "generating" so iOS can show a spinner ────────────
    await db.collection("churchNotes").doc(noteId).update({
      "aiDraftState.status": "generating",
      updatedAt: FieldValue.serverTimestamp(),
    });

    // ── Single NIM call for all draft fields ──────────────────────────────────
    const systemMsg =
      "You are a pastoral AI assistant for a Christian social app. " +
      "Your output is a JSON object that will be shown to the user as a DRAFT for their review. " +
      "The user must approve each section before it is added to their notes. " +
      "Be faithful to the source text, accurate with scripture references, and succinct. " +
      "Return ONLY valid JSON — no markdown fences, no explanatory prose outside the JSON.";

    const prompt =
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
      `---\nTRANSCRIPT:\n${truncatedTranscript}`;

    let draft = {};
    let nimError = null;

    try {
      const raw   = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
      const clean = raw.replace(/```json\s*/gi, "").replace(/```\s*/g, "").trim();
      const parsed = JSON.parse(clean);

      draft = {
        summary:             typeof parsed.summary === "string"           ? parsed.summary.trim() : "",
        keyVerses:           Array.isArray(parsed.keyVerses)              ? parsed.keyVerses.filter(Boolean).slice(0, 10) : [],
        actionItems:         Array.isArray(parsed.actionItems)            ? parsed.actionItems.filter(Boolean).slice(0, 7) : [],
        discussionQuestions: Array.isArray(parsed.discussionQuestions)    ? parsed.discussionQuestions.filter(Boolean).slice(0, 7) : [],
      };
    } catch (err) {
      // ── Partial-failure: save what we have (empty draft) and surface the error.
      // The transcript is already in Firestore from the pipeline step. The user
      // can retry draft generation without re-uploading audio.
      nimError = err.message;
      console.error(JSON.stringify({
        event:   "generateChurchNoteDraft_nim_error",
        noteId,
        message: nimError,
      }));
    }

    // ── Persist draft to Firestore (always, even on partial failure) ──────────
    const draftStatus = nimError ? "generation_failed" : "pending_review";

    const noteUpdate = {
      "aiDraftState.summary":             draft.summary             || null,
      "aiDraftState.keyVerses":           draft.keyVerses           || [],
      "aiDraftState.actionItems":         draft.actionItems         || [],
      "aiDraftState.discussionQuestions": draft.discussionQuestions || [],
      "aiDraftState.status":              draftStatus,
      "aiDraftState.generatedAt":         FieldValue.serverTimestamp(),
      updatedAt:                          FieldValue.serverTimestamp(),
    };

    if (nimError) {
      noteUpdate["aiDraftState.generationError"] = nimError;
    }

    const batch = db.batch();
    batch.update(db.collection("churchNotes").doc(noteId), noteUpdate);

    if (jobId) {
      batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
        status:    nimError ? "draft_failed" : "draft_ready",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    console.log(JSON.stringify({
      event:       "generateChurchNoteDraft_complete",
      noteId,
      jobId:       jobId || null,
      draftStatus,
      hasError:    !!nimError,
    }));

    // ── If NIM failed, surface a retryable error AFTER saving the draft stub ──
    if (nimError) {
      throw new HttpsError(
        "internal",
        `Draft generation failed: ${nimError}. Your transcript is saved — you can retry.`
      );
    }

    return { success: true, draft };
  }
);

// ─── 1. generateChurchNoteSummary ─────────────────────────────────────────────

exports.generateChurchNoteSummary = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const note = noteSnap.data();
  const text = getNoteText(note);

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    "You are a helpful assistant for a Christian social app. " +
    "Write concise, faith-centered sermon summaries that honor the speaker's message.";
  const prompt =
    `Summarize the following sermon notes in 200 words or fewer. ` +
    `Keep the tone reverent and faithful to the Gospel.\n\n---\n${text}`;

  const summary = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.summary": summary,
    "aiDraftState.status": "completed",
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 2. generateChurchNoteStudyGuide ─────────────────────────────────────────

exports.generateChurchNoteStudyGuide = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const text = getNoteText(noteSnap.data());

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    "You are a Bible study curriculum writer for a Christian community app. " +
    "Your guides are accessible, doctrinally sound, and scripture-anchored.";
  const prompt =
    `Create a 5-question Bible study guide from this sermon content, ` +
    `with scripture references for each question.\n\n---\n${text}`;

  const studyGuide = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.studyGuide": studyGuide,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 3. generateChurchNotePrayerPrompts ──────────────────────────────────────

exports.generateChurchNotePrayerPrompts = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const text = getNoteText(noteSnap.data());

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    "You are a prayer guide writer for a Christian app. " +
    "Return a JSON array of exactly 3 prayer prompt strings, no extra commentary.";
  const prompt =
    `Generate 3 personal prayer prompts based on this sermon. ` +
    `Return a JSON array of strings.\n\n---\n${text}`;

  const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
  const prayerPrompts = parseJSONArray(raw);

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.prayerPrompts": prayerPrompts,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 4. generateChurchNoteActionItems ────────────────────────────────────────

exports.generateChurchNoteActionItems = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const text = getNoteText(noteSnap.data());

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    "You are a discipleship coach writing practical takeaways from sermons. " +
    "Return a JSON array of 3–5 action item strings, no extra commentary.";
  const prompt =
    `Extract 3–5 practical action items a believer can apply this week ` +
    `from this sermon. Return a JSON array of strings.\n\n---\n${text}`;

  const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
  const actionItems = parseJSONArray(raw);

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.actionItems": actionItems,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 5. detectChurchNoteScriptures ───────────────────────────────────────────

exports.detectChurchNoteScriptures = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const text = getNoteText(noteSnap.data());

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    "You are a Biblical reference extractor. " +
    "Identify every Bible verse or passage mentioned in the provided text. " +
    'Return ONLY a JSON array of objects with keys "reference" (e.g. "John 3:16") ' +
    'and "text" (the full verse text or a short description if not quoted). ' +
    "No explanatory prose.";
  const prompt =
    `Identify all Bible references in the following sermon notes and return them ` +
    `as a JSON array of { reference, text } objects.\n\n---\n${text}`;

  const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
  const scriptures = parseJSONArray(raw);

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.scriptures": scriptures,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 6. translateChurchNoteContent ───────────────────────────────────────────

exports.translateChurchNoteContent = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId, targetLanguage } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");
  if (!targetLanguage) {
    throw new HttpsError("invalid-argument", "targetLanguage is required.");
  }

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const text = getNoteText(noteSnap.data());

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    `You are a professional translator specializing in religious and spiritual content. ` +
    `Translate accurately and naturally into ${targetLanguage}, preserving theological meaning.`;
  const prompt =
    `Translate the following sermon notes into ${targetLanguage}. ` +
    `Return only the translated text.\n\n---\n${text}`;

  const translation = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.translation": translation,
    translatedContent: translation,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 7. regenerateChurchNoteSection ──────────────────────────────────────────

exports.regenerateChurchNoteSection = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId, draftField } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");
  if (!draftField || !VALID_DRAFT_FIELDS.includes(draftField)) {
    throw new HttpsError(
      "invalid-argument",
      `draftField must be one of: ${VALID_DRAFT_FIELDS.join(", ")}.`
    );
  }

  const db = getFirestore();

  // Reset the approval for this field before regenerating.
  await db.collection("churchNotes").doc(noteId).update({
    [`draftApprovals.${draftField}`]: null,
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Dispatch to the appropriate generation function by constructing a synthetic
  // request and calling the underlying logic directly. We build a minimal
  // request-like object so each generator can run standalone.
  const syntheticRequest = {
    auth: request.auth,
    data: { noteId, jobId, targetLanguage: request.data.targetLanguage },
  };

  switch (draftField) {
    case "summary":
      await exports.generateChurchNoteSummary.run(syntheticRequest);
      break;
    case "studyGuide":
      await exports.generateChurchNoteStudyGuide.run(syntheticRequest);
      break;
    case "prayerPrompts":
      await exports.generateChurchNotePrayerPrompts.run(syntheticRequest);
      break;
    case "actionItems":
      await exports.generateChurchNoteActionItems.run(syntheticRequest);
      break;
    case "scriptures":
      await exports.detectChurchNoteScriptures.run(syntheticRequest);
      break;
    case "clipSuggestions":
      await exports.createChurchNoteClipSuggestions.run(syntheticRequest);
      break;
    default:
      throw new HttpsError("invalid-argument", `Unknown draftField: ${draftField}.`);
  }

  return { success: true };
});

// ─── 8. createChurchNoteClipSuggestions ──────────────────────────────────────

exports.createChurchNoteClipSuggestions = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId } = request.data || {};
  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const text = getNoteText(noteSnap.data());

  if (!text) {
    throw new HttpsError("failed-precondition", "No content to process.");
  }

  const systemMsg =
    "You are a social media content strategist for a Christian app. " +
    "Identify the most shareable, impactful moments from sermon transcripts. " +
    'Return ONLY a JSON array of objects with keys: "title", "startCue", "endCue", "theme". ' +
    "No extra prose or markdown.";
  const prompt =
    `From this sermon transcript, identify 3 powerful 60-second clip segments. ` +
    `For each provide: title (short), startCue (first few words of the segment), ` +
    `endCue (last few words of the segment), theme (1–3 word label). ` +
    `Return a JSON array of { title, startCue, endCue, theme } objects.\n\n---\n${text}`;

  const raw = await callNIM(prompt, systemMsg, NVIDIA_API_KEY.value());
  const clipSuggestions = parseJSONArray(raw);

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    "aiDraftState.clipSuggestions": clipSuggestions,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "completed",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 9. approveChurchNoteAIDraft ─────────────────────────────────────────────

exports.approveChurchNoteAIDraft = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  const { noteId, jobId, draftField } = request.data || {};

  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");
  if (!draftField || !VALID_DRAFT_FIELDS.includes(draftField)) {
    throw new HttpsError(
      "invalid-argument",
      `draftField must be one of: ${VALID_DRAFT_FIELDS.join(", ")}.`
    );
  }

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const note = noteSnap.data();

  // Ownership check — only the note author may approve drafts.
  if (note.userId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "You can only approve drafts on your own notes."
    );
  }

  const approvedText = note.aiDraftState?.[draftField] ?? null;

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    [`draftApprovals.${draftField}`]: "approved",
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "approved",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return {
    jobId: jobId || null,
    noteId,
    draftField,
    approvedText,
    sourceType: "ai_generated",
  };
});

// ─── 10. rejectChurchNoteAIDraft ──────────────────────────────────────────────

exports.rejectChurchNoteAIDraft = onCall(BASE_CONFIG, async (request) => {
  requireAuth(request);
  const { noteId, jobId, draftField, reason } = request.data || {};

  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");
  if (!draftField || !VALID_DRAFT_FIELDS.includes(draftField)) {
    throw new HttpsError(
      "invalid-argument",
      `draftField must be one of: ${VALID_DRAFT_FIELDS.join(", ")}.`
    );
  }

  const db = getFirestore();
  // Verify note exists before writing.
  await fetchNote(db, noteId);

  const batch = db.batch();
  batch.update(db.collection("churchNotes").doc(noteId), {
    [`draftApprovals.${draftField}`]: "rejected",
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (jobId) {
    batch.update(db.collection("churchNoteProcessingJobs").doc(jobId), {
      status: "rejected",
      rejectionReason: reason || null,
      rejectedField: draftField,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  return { success: true };
});

// ─── 11. shareChurchNoteWithCollaborators ─────────────────────────────────────

const VALID_ROLES = ["owner", "editor", "commenter", "viewer"];

exports.shareChurchNoteWithCollaborators = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  const { noteId, collaboratorUid, role } = request.data || {};

  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");
  if (!collaboratorUid) {
    throw new HttpsError("invalid-argument", "collaboratorUid is required.");
  }
  if (!role || !VALID_ROLES.includes(role)) {
    throw new HttpsError(
      "invalid-argument",
      `role must be one of: ${VALID_ROLES.join(", ")}.`
    );
  }
  if (collaboratorUid === uid) {
    throw new HttpsError(
      "invalid-argument",
      "You cannot add yourself as a collaborator."
    );
  }

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const note = noteSnap.data();

  // Only the note owner may add collaborators.
  if (note.userId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "You can only share your own notes."
    );
  }

  await db.collection("churchNotes").doc(noteId).update({
    [`collaborators.${collaboratorUid}`]: {
      role,
      addedAt: FieldValue.serverTimestamp(),
      addedBy: uid,
    },
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { success: true };
});

// ─── 12. updateChurchNotePermissions ─────────────────────────────────────────

exports.updateChurchNotePermissions = onCall(BASE_CONFIG, async (request) => {
  const uid = requireAuth(request);
  const { noteId, collaboratorUid, role, remove } = request.data || {};

  if (!noteId) throw new HttpsError("invalid-argument", "noteId is required.");
  if (!collaboratorUid) {
    throw new HttpsError("invalid-argument", "collaboratorUid is required.");
  }
  if (!remove && (!role || !VALID_ROLES.includes(role))) {
    throw new HttpsError(
      "invalid-argument",
      `role must be one of: ${VALID_ROLES.join(", ")} when not removing.`
    );
  }

  const db = getFirestore();
  const noteSnap = await fetchNote(db, noteId);
  const note = noteSnap.data();

  // Only the owner may change permissions.
  if (note.userId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the note owner can update permissions."
    );
  }

  if (remove) {
    // Use FieldValue.delete() to remove the collaborator entry entirely.
    await db.collection("churchNotes").doc(noteId).update({
      [`collaborators.${collaboratorUid}`]: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    // Merge-update only the role field; preserve addedAt / addedBy.
    await db.collection("churchNotes").doc(noteId).update({
      [`collaborators.${collaboratorUid}.role`]: role,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  return { success: true };
});
