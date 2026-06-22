// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * discernmentEngine.js — Berean Discernment Engine (Firebase gen2 callable functions).
 *
 * Exports two Firebase gen2 onCall callables:
 *   runDiscernmentCheck   — full pipeline: NeMo → verse fetch → Claude → validate → save
 *   shareDiscernmentCheck — promote a private check to 'shared' (NeMo re-moderation required)
 *
 * Hard constraints (all enforced in code, not just comments):
 *   C1. NeMo runs FIRST — no Claude call if NeMo is unavailable. Fail closed.
 *   C2. Claude-only for 'discernment' task — no fallover to any other provider.
 *   C3. assertOpenTranslation on every citation — strip licensed text, log violation.
 *   C4. Visibility defaults to 'private' — never auto-share.
 *   C5. No hard delete — documents use deletedAt (soft-delete only).
 *   C6. Fail gracefully — retry exhaustion returns a 'refused' check, never a thrown error.
 *   C7. Framing — prompt never asks for FALSE/UNBIBLICAL verdicts.
 *   C8. sourceRef scoping — when sourceType is 'selah_note', validate note belongs to caller uid.
 *
 * Import conventions (match existing project style — see routerCallable.js):
 *   callModel  → ../router/callModel
 *   rateLimiter → ../rateLimiter
 *
 * AGENT C scope: this file is owned exclusively by Agent C.
 * Wiring into v2functions.js happens in the final wiring phase — do not edit that file here.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret }       = require("firebase-functions/params");
const logger                 = require("firebase-functions/logger");
const admin                  = require("firebase-admin");
const { v4: uuidv4 }         = require("uuid");

const { callModel }          = require("../router/callModel");
const { enforceRateLimit }   = require("../rateLimiter");
const {
  buildDiscernmentPrompt,
  buildRefusalResponse,
} = require("./discernmentPrompts");

// ---------------------------------------------------------------------------
// SECRETS — declared so Firebase runtime injects them at deploy time
// ---------------------------------------------------------------------------

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const NVIDIA_API_KEY    = defineSecret("NVIDIA_API_KEY");
const PINECONE_API_KEY  = defineSecret("PINECONE_API_KEY");
const PINECONE_HOST     = defineSecret("PINECONE_HOST");

// ---------------------------------------------------------------------------
// CONSTANTS
// ---------------------------------------------------------------------------

/** Rate limit: 10 discernment checks per minute per user (expensive Claude calls) */
const DISCERNMENT_RATE_LIMIT_MAX    = 10;
const DISCERNMENT_RATE_LIMIT_WINDOW = 60; // seconds

/** Max allowed input text length (characters) */
const MAX_INPUT_TEXT_LENGTH = 2000;

/** Retry backoff schedule for Claude calls (ms), matching DISCERNMENT_ROUTING in contracts */
const RETRY_BACKOFF_MS = [500, 1500, 4000];
const MAX_RETRY_ATTEMPTS = 3;

/** Valid DiscernmentSourceType values, frozen from selah.contracts.ts §SECTION 2 */
const VALID_SOURCE_TYPES = Object.freeze([
  "comment",
  "post",
  "space_message",
  "pasted_text",
  "selah_note",
  "verse",
]);

/** Firestore collection for discernment checks */
const DISCERNMENT_COLLECTION = "discernmentChecks";

/** Open-licensed translations that may appear in citations */
const OPEN_TRANSLATIONS = Object.freeze(["BSB", "WEB", "KJV"]);

// ---------------------------------------------------------------------------
// HELPER: sleep
// ---------------------------------------------------------------------------

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// HELPER: assertOpenTranslation (JS implementation mirroring selah.contracts.ts)
//
// C3: throws if translation is not BSB/WEB/KJV.
// Call at every boundary where citations enter or leave the system.
// ---------------------------------------------------------------------------

function assertOpenTranslation(translation) {
  if (!OPEN_TRANSLATIONS.includes(translation)) {
    throw new Error(
      `HARD CONTRACT VIOLATION: Translation "${translation}" is not open-licensed. ` +
      `Only BSB/WEB/KJV may appear in AI citation paths. ` +
      `Licensed versions (ESV, NIV, NLT, NASB, etc.) are restricted to the human reader path.`
    );
  }
}

// ---------------------------------------------------------------------------
// HELPER: validateDiscernmentCheck (JS implementation mirroring selah.contracts.ts)
//
// Enforces fail-closed invariants before Firestore write.
// ---------------------------------------------------------------------------

function validateDiscernmentCheck(check) {
  if (check.status === "refused") {
    if (check.verdict != null) {
      throw new Error("Contract violation: refused check must have null verdict");
    }
    if (Array.isArray(check.citations) && check.citations.length > 0) {
      throw new Error("Contract violation: refused check must have empty citations");
    }
    if (!check.refusalReason) {
      throw new Error("Contract violation: refused check must have a refusalReason");
    }
  }
  if (check.status === "grounded" && !check.verdict) {
    throw new Error("Contract violation: grounded check must have a verdict");
  }
}

// ---------------------------------------------------------------------------
// HELPER: getOpenLicenseVersesForContext
//
// Dependency injection point for Agent E's openLicenseVerseService.
// Calls Agent E's module when available; gracefully returns [] if not yet wired.
// The engine continues with an empty verse list rather than blocking — Claude will
// be instructed to acknowledge that no relevant passages were retrieved.
// ---------------------------------------------------------------------------

async function getOpenLicenseVersesForContext(inputText) {
  try {
    // Agent E's module is imported lazily to avoid hard circular dependency during build.
    // When Agent E's file exists, this require() will resolve it; otherwise we catch gracefully.
    const openLicenseVerseService = require("./openLicenseVerseService");
    if (typeof openLicenseVerseService.getOpenLicenseVersesForContext === "function") {
      const verses = await openLicenseVerseService.getOpenLicenseVersesForContext(inputText);
      // C3: Filter out any verse with a non-open translation before injecting into prompt
      return (verses || []).filter((v) => {
        if (!OPEN_TRANSLATIONS.includes(v.translation)) {
          logger.error("[discernmentEngine] Agent E returned a licensed translation — stripped", {
            reference: v.reference,
            translation: v.translation,
          });
          return false;
        }
        return true;
      });
    }
  } catch (err) {
    // Agent E not yet deployed or module missing — log and continue with empty verses.
    logger.warn("[discernmentEngine] openLicenseVerseService unavailable — proceeding with no verse context", {
      error: err.message,
    });
  }
  return [];
}

// ---------------------------------------------------------------------------
// HELPER: validateSelahNoteOwnership
//
// C8: When sourceType === 'selah_note', validate that the note belongs to the caller uid.
// Throws HttpsError 'permission-denied' if the note doesn't belong to the caller.
// ---------------------------------------------------------------------------

async function validateSelahNoteOwnership(noteId, uid) {
  if (!noteId) {
    throw new HttpsError(
      "invalid-argument",
      "sourceRef is required when sourceType is 'selah_note'."
    );
  }

  const db = admin.firestore();
  const noteRef = db.doc(`users/${uid}/selahNotes/${noteId}`);
  const snap = await noteRef.get();

  if (!snap.exists) {
    // Note does not exist in this user's namespace — could be wrong uid or wrong noteId.
    // Either way: permission denied (do not reveal whether note exists for another user).
    throw new HttpsError(
      "permission-denied",
      "The referenced Selah note was not found or does not belong to you."
    );
  }

  const data = snap.data();
  if (data.deletedAt != null) {
    throw new HttpsError(
      "not-found",
      "The referenced Selah note has been deleted."
    );
  }
  if (data.userId !== uid) {
    // Defensive: Firestore path already scopes by uid, but double-check the userId field.
    logger.error("[discernmentEngine] selah note userId mismatch — possible path traversal attempt", {
      noteId,
      callerUid: uid,
      noteUserId: data.userId,
    });
    throw new HttpsError(
      "permission-denied",
      "You do not have permission to run a discernment check on this note."
    );
  }
}

// ---------------------------------------------------------------------------
// HELPER: callClaudeWithRetry
//
// Calls callModel({ task: 'discernment', ... }) with the retry schedule from
// DISCERNMENT_ROUTING: 3 attempts, backoff [500ms, 1500ms, 4000ms].
// C2: task: 'discernment' enforces Claude-only routing via amenRouting.config.js.
// C6: on all-retry failure, returns null (caller builds a graceful refused response).
// ---------------------------------------------------------------------------

async function callClaudeWithRetry({ prompt, uid }) {
  let lastError = null;

  for (let attempt = 0; attempt < MAX_RETRY_ATTEMPTS; attempt++) {
    if (attempt > 0) {
      const backoff = RETRY_BACKOFF_MS[attempt - 1] ?? 4000;
      logger.warn("[discernmentEngine] Claude retry", { attempt, backoffMs: backoff, uid });
      await sleep(backoff);
    }

    try {
      // C2: task 'discernment' is Claude-only in amenRouting.config.js (no chain fallover).
      const result = await callModel({
        task: "discernment",          // routes exclusively to Claude per ROUTING config
        input: prompt,
        userId: uid,
        safetyLevel: "high",
        // inputGuard and outputGuard are handled separately in the engine pipeline
        // because we need explicit fail-closed control at each boundary.
        // callModel's internal guards are a second layer, not the primary control.
      });

      if (result && !result.blocked) {
        return result;
      }

      // callModel returned a blocked result — treat as a soft failure for this attempt
      logger.warn("[discernmentEngine] callModel returned blocked result on attempt", { attempt, uid });
      lastError = new Error("callModel returned blocked result");
    } catch (err) {
      lastError = err;
      logger.warn("[discernmentEngine] callModel threw on attempt", {
        attempt,
        uid,
        error: err.message,
      });
    }
  }

  // C6: All retries exhausted — log and return null; caller will build refused response.
  logger.error("[discernmentEngine] All Claude retries exhausted — failing gracefully", {
    uid,
    attempts: MAX_RETRY_ATTEMPTS,
    lastError: lastError?.message,
  });
  return null;
}

// ---------------------------------------------------------------------------
// HELPER: parseClaudeResponse
//
// Safely parses the JSON output from Claude into a DiscernmentCheck shape.
// Returns null on parse failure (caller converts to refused response).
// ---------------------------------------------------------------------------

function parseClaudeResponse(rawOutput) {
  if (!rawOutput) return null;

  // callModel returns { output: string, provider: string, ... }
  const text = typeof rawOutput.output === "string"
    ? rawOutput.output
    : typeof rawOutput === "string"
      ? rawOutput
      : null;

  if (!text) return null;

  // Strip markdown code fences if Claude added them despite instructions
  const cleaned = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  try {
    const parsed = JSON.parse(cleaned);
    return parsed;
  } catch (err) {
    logger.error("[discernmentEngine] Failed to parse Claude JSON response", {
      error: err.message,
      rawLength: text.length,
    });
    return null;
  }
}

// ---------------------------------------------------------------------------
// HELPER: stripLicensedCitations (C3 enforcement)
//
// For every citation in the parsed response:
//   - Call assertOpenTranslation.
//   - If it fails → remove citation from the array (do NOT throw to client), log violation.
// Returns the sanitised citations array.
// ---------------------------------------------------------------------------

function stripLicensedCitations(citations, uid) {
  if (!Array.isArray(citations)) return [];

  const safe = [];
  for (const citation of citations) {
    try {
      assertOpenTranslation(citation.translation);
      safe.push(citation);
    } catch (err) {
      // C3: Log the violation; strip the citation; never surface licensed text to client.
      logger.error("[discernmentEngine] C3 CITATION VIOLATION — licensed translation stripped", {
        reference: citation.reference,
        translation: citation.translation,
        uid,
        violation: err.message,
      });
      // Do NOT re-throw — continue processing remaining citations.
    }
  }
  return safe;
}

// ---------------------------------------------------------------------------
// HELPER: saveDiscernmentCheck (C4 + C5 enforcement)
//
// Writes the DiscernmentCheck to Firestore.
//   C4: visibility always set to 'private' (never 'shared') in this function.
//   C5: deletedAt always set to null (no hard-delete path).
// ---------------------------------------------------------------------------

async function saveDiscernmentCheck(check) {
  const db = admin.firestore();
  const ref = db.collection(DISCERNMENT_COLLECTION).doc(check.id);
  await ref.set(check);
  return check;
}

// ---------------------------------------------------------------------------
// MAIN CALLABLE: runDiscernmentCheck
// ---------------------------------------------------------------------------

/**
 * runDiscernmentCheck — Firebase gen2 onCall callable.
 *
 * Full pipeline:
 *   1. Auth guard
 *   2. Rate limit: 10/minute
 *   3. Input validation
 *   4. NeMo input guard (FIRST — C1: fail closed if unavailable)
 *   5. Fetch open-license verses (Agent E injection point)
 *   6. Build discernment prompt
 *   7. Call Claude with retry (C2: Claude-only)
 *   8. Parse Claude response
 *   9. Strip licensed citations (C3)
 *  10. NeMo output guard
 *  11. validateDiscernmentCheck
 *  12. Save to Firestore (C4: private; C5: soft-delete only)
 *  13. Return DiscernmentCheck to client
 */
exports.runDiscernmentCheck = onCall(
  {
    secrets: [ANTHROPIC_API_KEY, NVIDIA_API_KEY, PINECONE_API_KEY, PINECONE_HOST],
    enforceAppCheck: true,
  },
  async (request) => {
    const startMs = Date.now();

    // ── STEP 1: Auth guard ─────────────────────────────────────────────────
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to run a discernment check."
      );
    }
    const uid = request.auth.uid;

    // ── STEP 2: Rate limit (10/minute) ────────────────────────────────────
    // enforceRateLimit throws HttpsError('resource-exhausted') on breach.
    await enforceRateLimit(uid, "discernment_check", DISCERNMENT_RATE_LIMIT_MAX, DISCERNMENT_RATE_LIMIT_WINDOW);

    // ── STEP 3: Input validation ──────────────────────────────────────────
    const { inputText, sourceType, sourceRef, visibility: _ignoredVisibility } = request.data || {};

    if (!inputText || typeof inputText !== "string" || inputText.trim() === "") {
      throw new HttpsError(
        "invalid-argument",
        "inputText is required and must be a non-empty string."
      );
    }
    if (inputText.length > MAX_INPUT_TEXT_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `inputText exceeds the maximum allowed length of ${MAX_INPUT_TEXT_LENGTH} characters.`
      );
    }
    if (!sourceType || !VALID_SOURCE_TYPES.includes(sourceType)) {
      throw new HttpsError(
        "invalid-argument",
        `sourceType must be one of: ${VALID_SOURCE_TYPES.join(", ")}.`
      );
    }

    // C4: Visibility is ALWAYS 'private' — the client cannot set it to 'shared' here.
    // 'shared' is promoted only via shareDiscernmentCheck (with NeMo re-moderation).
    const visibility = "private";

    // C8: If sourceType is 'selah_note', validate ownership before any AI calls.
    if (sourceType === "selah_note") {
      await validateSelahNoteOwnership(sourceRef || null, uid);
    }

    const sanitisedText = inputText.trim();

    logger.info("[discernmentEngine] runDiscernmentCheck.start", {
      uid,
      sourceType,
      hasSourceRef: !!sourceRef,
      textLength: sanitisedText.length,
    });

    // ── STEP 4: NeMo input guard (C1: FAIL CLOSED) ───────────────────────
    // NeMo MUST run before any Claude call. If NeMo is unavailable, refuse.
    let nemoInputResult;
    try {
      nemoInputResult = await callModel({
        task: "guard_input",
        input: { text: sanitisedText },
        userId: uid,
      });
    } catch (nemoErr) {
      // C1: NeMo unavailable → fail closed. Never pass unmoderated text to Claude.
      logger.error("[discernmentEngine] NeMo input guard unavailable — failing closed", {
        uid,
        error: nemoErr.message,
      });
      return buildRefusalResponse(
        "Content moderation is temporarily unavailable. Please try again in a moment."
      );
    }

    if (!nemoInputResult || nemoInputResult.blocked) {
      logger.warn("[discernmentEngine] NeMo blocked input", {
        uid,
        reason: nemoInputResult?.reason,
        categories: nemoInputResult?.categories,
      });
      return buildRefusalResponse("Content blocked by safety filter.");
    }

    // ── STEP 5: Fetch open-license verse context (Agent E injection) ──────
    const openLicenseVerses = await getOpenLicenseVersesForContext(sanitisedText);

    logger.info("[discernmentEngine] verse context fetched", {
      uid,
      verseCount: openLicenseVerses.length,
    });

    // ── STEP 6: Build discernment prompt ──────────────────────────────────
    const prompt = buildDiscernmentPrompt({
      inputText: sanitisedText,
      openLicenseVerses,
      sourceType,
    });

    // ── STEP 7: Call Claude with retry (C2: Claude-only) ──────────────────
    const claudeResult = await callClaudeWithRetry({ prompt, uid });

    if (!claudeResult) {
      // C6: All retries exhausted — graceful refusal, not a thrown error.
      return buildRefusalResponse(
        "Service temporarily unavailable. Please try again."
      );
    }

    // ── STEP 8: Parse Claude response ─────────────────────────────────────
    const parsed = parseClaudeResponse(claudeResult);

    if (!parsed) {
      logger.error("[discernmentEngine] Failed to parse Claude response — refusing", { uid });
      return buildRefusalResponse(
        "The discernment check could not be completed due to an unexpected response. Please try again."
      );
    }

    // ── STEP 9: Hard citation validation (C3) ─────────────────────────────
    // Strip any licensed citations Claude may have hallucinated despite instructions.
    // Do NOT throw to client — remove and log.
    const safeCitations = stripLicensedCitations(parsed.citations || [], uid);

    // Also strip licensed citations from inside perspectives[] if present
    const safePersp = (parsed.perspectives || []).map((p) => ({
      ...p,
      citations: stripLicensedCitations(p.citations || [], uid),
    }));

    // Rebuild the parsed check with sanitised citations
    const sanitisedCheck = {
      ...parsed,
      citations: safeCitations,
      perspectives: safePersp,
    };

    // ── STEP 10: NeMo output guard ────────────────────────────────────────
    // Build a text representation of the response for moderation.
    const outputText = JSON.stringify(sanitisedCheck);

    let nemoOutputResult;
    try {
      nemoOutputResult = await callModel({
        task: "guard_output",
        input: { text: outputText },
        userId: uid,
      });
    } catch (nemoOutErr) {
      // C1: NeMo unavailable on output → fail closed.
      logger.error("[discernmentEngine] NeMo output guard unavailable — failing closed", {
        uid,
        error: nemoOutErr.message,
      });
      return buildRefusalResponse(
        "Content moderation is temporarily unavailable. Please try again in a moment."
      );
    }

    if (!nemoOutputResult || nemoOutputResult.blocked) {
      logger.warn("[discernmentEngine] NeMo blocked output", {
        uid,
        reason: nemoOutputResult?.reason,
      });
      return buildRefusalResponse("The discernment result was flagged by the safety filter and cannot be returned.");
    }

    // ── STEP 11: validateDiscernmentCheck ────────────────────────────────
    const checkId = uuidv4();
    const now = Date.now();

    const discernmentCheck = {
      id: checkId,
      sourceType,
      sourceRef: sourceRef || null,
      inputText: sanitisedText,              // post-moderation text only
      status: sanitisedCheck.status || "grounded",
      verdict: sanitisedCheck.verdict || null,
      claims: sanitisedCheck.claims || [],
      citations: sanitisedCheck.citations || [],
      perspectives: sanitisedCheck.perspectives || [],
      refusalReason: sanitisedCheck.refusalReason || null,
      truthLevel: sanitisedCheck.truthLevel || "scripture_examined",
      createdBy: uid,
      visibility,                            // C4: always 'private'
      createdAt: now,
      updatedAt: now,
      deletedAt: null,                       // C5: soft-delete only; no hard-delete path
    };

    try {
      validateDiscernmentCheck(discernmentCheck);
    } catch (validationErr) {
      // Contract invariant violated — log and refuse rather than saving a bad record.
      logger.error("[discernmentEngine] Contract validation failed — refusing", {
        uid,
        error: validationErr.message,
      });
      return buildRefusalResponse(
        "The discernment result could not be validated. Please try again."
      );
    }

    // ── STEP 12: Save to Firestore (C4 + C5) ─────────────────────────────
    try {
      await saveDiscernmentCheck(discernmentCheck);
    } catch (saveErr) {
      // Firestore write failure — log but still return the result to the client.
      // The check was valid; the save failure is infra, not a safety issue.
      logger.error("[discernmentEngine] Firestore save failed — returning result anyway", {
        uid,
        checkId,
        error: saveErr.message,
      });
    }

    logger.info("[discernmentEngine] runDiscernmentCheck.complete", {
      uid,
      checkId,
      verdict: discernmentCheck.verdict,
      status: discernmentCheck.status,
      citationCount: discernmentCheck.citations.length,
      durationMs: Date.now() - startMs,
    });

    // ── STEP 13: Return to client ─────────────────────────────────────────
    return discernmentCheck;
  }
);

// ---------------------------------------------------------------------------
// SECONDARY CALLABLE: shareDiscernmentCheck
//
// Promotes a private check to 'shared'. Requires:
//   - Auth guard: uid must match check.createdBy
//   - NeMo re-moderation on the check text before sharing
//   - Sets visibility: 'shared' on the Firestore document
//   - Returns updated check
//
// C4: 'shared' is ONLY settable via this function, never auto-set.
// C5: No hard-delete; deletedAt semantics unchanged.
// HUMAN GATE: selah.discernmentSharing Remote Config flag must be enabled in prod.
// ---------------------------------------------------------------------------

exports.shareDiscernmentCheck = onCall(
  {
    secrets: [NVIDIA_API_KEY],
    enforceAppCheck: true,
  },
  async (request) => {
    // ── Auth guard ─────────────────────────────────────────────────────────
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to share a discernment check."
      );
    }
    const uid = request.auth.uid;

    const { checkId } = request.data || {};
    if (!checkId || typeof checkId !== "string" || checkId.trim() === "") {
      throw new HttpsError(
        "invalid-argument",
        "checkId is required."
      );
    }

    const db = admin.firestore();
    const ref = db.collection(DISCERNMENT_COLLECTION).doc(checkId.trim());
    const snap = await ref.get();

    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        "Discernment check not found."
      );
    }

    const check = snap.data();

    // C5: Soft-deleted checks cannot be shared
    if (check.deletedAt != null) {
      throw new HttpsError(
        "not-found",
        "This discernment check has been deleted and cannot be shared."
      );
    }

    // Auth ownership check: uid must match createdBy
    if (check.createdBy !== uid) {
      logger.warn("[discernmentEngine] shareDiscernmentCheck — uid mismatch", {
        callerUid: uid,
        checkOwner: check.createdBy,
        checkId,
      });
      throw new HttpsError(
        "permission-denied",
        "You can only share your own discernment checks."
      );
    }

    // Already shared — idempotent return
    if (check.visibility === "shared") {
      return check;
    }

    // HUMAN GATE: selah.discernmentSharing feature flag must be enabled.
    // We check this via a Firestore config document rather than Remote Config SDK
    // to avoid adding a dependency; the wiring agent can upgrade to Remote Config.
    // For now, the flag defaults to OFF (blocked) and must be explicitly enabled.
    try {
      const flagRef = db.doc("remoteConfig/selah.discernmentSharing");
      const flagSnap = await flagRef.get();
      const flagEnabled = flagSnap.exists && flagSnap.data()?.enabled === true;
      if (!flagEnabled) {
        throw new HttpsError(
          "failed-precondition",
          "Discernment sharing is not yet enabled. This feature requires explicit approval before use."
        );
      }
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      // Flag check failed — fail closed, do not allow sharing on infrastructure error.
      logger.error("[discernmentEngine] discernmentSharing flag check failed — blocking share", {
        uid,
        checkId,
        error: err.message,
      });
      throw new HttpsError(
        "unavailable",
        "Unable to verify sharing permissions. Please try again."
      );
    }

    // NeMo re-moderation before making content visible to others
    const contentForModeration = JSON.stringify({
      inputText: check.inputText,
      claims: check.claims,
      citations: check.citations,
      perspectives: check.perspectives,
    });

    let nemoResult;
    try {
      nemoResult = await callModel({
        task: "guard_output",
        input: { text: contentForModeration },
        userId: uid,
      });
    } catch (nemoErr) {
      // C1: NeMo unavailable → fail closed on sharing too.
      logger.error("[discernmentEngine] NeMo re-moderation unavailable — blocking share", {
        uid,
        checkId,
        error: nemoErr.message,
      });
      throw new HttpsError(
        "unavailable",
        "Content moderation is temporarily unavailable. Please try again before sharing."
      );
    }

    if (!nemoResult || nemoResult.blocked) {
      logger.warn("[discernmentEngine] NeMo blocked discernment check from sharing", {
        uid,
        checkId,
        reason: nemoResult?.reason,
      });
      throw new HttpsError(
        "failed-precondition",
        "This discernment check was flagged by the safety filter and cannot be shared."
      );
    }

    // Promote to 'shared'
    const now = Date.now();
    await ref.update({
      visibility: "shared",   // C4: 'shared' set only here, only after NeMo passes
      updatedAt: now,
    });

    logger.info("[discernmentEngine] shareDiscernmentCheck.complete", {
      uid,
      checkId,
    });

    return { ...check, visibility: "shared", updatedAt: now };
  }
);
