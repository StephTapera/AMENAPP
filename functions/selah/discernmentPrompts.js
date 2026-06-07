/**
 * discernmentPrompts.js — Prompt construction for the Berean Discernment Engine.
 *
 * Prompt invariants (all enforced here, never in the engine layer):
 *   1. Task framing is humble and Berean (Acts 17:11; 1 Thess 5:21) — never prosecutorial.
 *   2. Output verdict vocabulary: 'aligns' | 'diverges' | 'contested' | 'insufficient'.
 *      Terms 'FALSE', 'UNBIBLICAL', 'heresy', 'heretical' are NEVER used.
 *   3. Open-license verses (BSB/WEB/KJV) are the ONLY verse text provided to Claude.
 *      Licensed translations (ESV, NIV, NLT, NASB, etc.) are NEVER injected here.
 *   4. If no relevant verses exist for a claim → refuse that claim specifically, not the whole check.
 *   5. Output MUST match the DiscernmentCheck JSON shape from selah.contracts.ts.
 *
 * AGENT C scope: this file is owned exclusively by Agent C (Berean Discernment Engine).
 * DO NOT import from discernmentEngine.js — this is a pure prompt-construction module.
 */

"use strict";

// ---------------------------------------------------------------------------
// CONSTANTS
// ---------------------------------------------------------------------------

/** Framing preamble — never changes. Enforces humble, Berean spirit. */
const BEREAN_PREAMBLE = `You are a careful, humble Bible study assistant helping a believer test ideas against Scripture (Acts 17:11; 1 Thess 5:21). Your role is to help the reader understand what Scripture says, not to render verdicts. You approach each claim with intellectual humility, acknowledging where faithful Christians disagree, and you never characterize a teaching as 'FALSE' or 'UNBIBLICAL' — those are your user's conclusions to draw, not yours to impose.`;

/** Valid claim classification values, mirroring ClaimClass from selah.contracts.ts */
const VALID_CLAIM_CLASSES = ["doctrinal", "ethical", "historical", "devotional", "unverifiable"];

/** Valid verdict values, mirroring DiscernmentVerdict from selah.contracts.ts */
const VALID_VERDICTS = ["aligns", "diverges", "contested", "insufficient"];

/** Open-licensed translations that may appear in Claude's output citations */
const OPEN_TRANSLATIONS = ["BSB", "WEB", "KJV"];

// ---------------------------------------------------------------------------
// buildDiscernmentPrompt
// ---------------------------------------------------------------------------

/**
 * Builds the full structured prompt for a Berean discernment check.
 *
 * @param {object} params
 * @param {string} params.inputText         - The post-moderation text to examine
 * @param {string[]} [params.claims]        - Optional pre-extracted claims (from extractClaimsPrompt pass)
 * @param {Array<{reference: string, translation: string, text: string}>} params.openLicenseVerses
 *                                          - BSB/WEB/KJV passages fetched by Agent E.
 *                                            HARD CONSTRAINT: no licensed verse text here.
 * @param {string} params.sourceType        - DiscernmentSourceType value for context framing
 * @returns {string} The full prompt string ready for callModel({ task: 'discernment', input: prompt })
 */
function buildDiscernmentPrompt({ inputText, claims = [], openLicenseVerses = [], sourceType }) {
  // Validate openLicenseVerses — strip any that sneak in a licensed translation.
  // The engine also enforces assertOpenTranslation, but we double-enforce here at the prompt boundary.
  const safeVerses = openLicenseVerses.filter((v) => {
    if (!OPEN_TRANSLATIONS.includes(v.translation)) {
      console.error(
        `[discernmentPrompts] HARD CONSTRAINT VIOLATION: licensed translation "${v.translation}" ` +
        `attempted to enter the discernment prompt. Stripped. Reference: ${v.reference}`
      );
      return false;
    }
    return true;
  });

  const verseContext = safeVerses.length > 0
    ? safeVerses
        .map((v) => `• ${v.reference} (${v.translation}): "${v.text}"`)
        .join("\n")
    : "(No relevant open-licensed passages were retrieved for this text. " +
      "If you cannot ground a claim in the passages below, say so honestly — do not fabricate references.)";

  const claimSeedSection = claims.length > 0
    ? `\n\nPRE-IDENTIFIED CLAIMS (from extraction pass):\n${claims.map((c, i) => `${i + 1}. ${c}`).join("\n")}\n\nVerify, adjust, or add to these claims as needed based on your own reading of the text.`
    : "";

  const sourceTypeNote = sourceType
    ? `\n\nSOURCE TYPE: This text comes from a "${sourceType}" surface in the app.`
    : "";

  return `${BEREAN_PREAMBLE}
${sourceTypeNote}
${claimSeedSection}

════════════════════════════════════════════════════════════
OPEN-LICENSED SCRIPTURE CONTEXT (BSB / WEB / KJV ONLY)
You MUST cite ONLY from the passages listed below.
Do NOT quote ESV, NIV, NLT, NASB, CSB, or any other licensed translation.
If the passages below do not address a claim, state that honestly.
════════════════════════════════════════════════════════════

${verseContext}

════════════════════════════════════════════════════════════
TEXT TO EXAMINE
════════════════════════════════════════════════════════════

${inputText}

════════════════════════════════════════════════════════════
YOUR TASK
════════════════════════════════════════════════════════════

Follow these steps precisely:

1. IDENTIFY CLAIMS
   Read the text and identify each distinct claim. For each claim, classify it as one of:
   ${VALID_CLAIM_CLASSES.join(" | ")}

2. EXAMINE EACH CLAIM AGAINST SCRIPTURE
   For each claim:
   a. Find relevant passages from the SCRIPTURE CONTEXT above.
   b. Assess alignment using ONLY these verdicts:
      - "aligns"       — the claim is well-supported by the provided passages
      - "diverges"     — the provided passages point in a meaningfully different direction
      - "contested"    — faithful traditions within orthodox Christianity disagree on this
      - "insufficient" — the provided passages do not address the claim clearly enough to assess
   c. Use "Here is what Scripture says about this claim..." framing — never "This is FALSE/UNBIBLICAL."
   d. If the claim is classified as "unverifiable" OR no relevant verses were found:
      - Refuse that SPECIFIC claim only (not the whole check).
      - Set that claim's verdict to null and provide a refusalReason for that claim.
   e. NEVER fabricate a Scripture reference. If no passage addresses the claim, say so.

3. CONTESTED CLAIMS
   If a claim is "contested", present multiple faithful theological traditions with:
   - The tradition name (e.g. "Reformed / Calvinist", "Arminian / Wesleyan", "Eastern Orthodox")
   - A brief, charitable summary of that tradition's position
   - The Scripture citations that tradition emphasizes (from the provided context only)

4. OVERALL VERDICT
   After examining all claims, assign ONE overall verdict from:
   ${VALID_VERDICTS.join(" | ")}
   This reflects the aggregate theological picture, not a moral judgment of the author.

5. OUTPUT FORMAT
   Return a single valid JSON object matching this shape EXACTLY:
   {
     "status": "grounded",
     "verdict": "<one of: aligns | diverges | contested | insufficient>",
     "claims": [
       {
         "text": "<the claim text>",
         "classification": "<doctrinal | ethical | historical | devotional | unverifiable>",
         "claimVerdict": "<aligns | diverges | contested | insufficient | null>",
         "claimRefusalReason": "<string or null>"
       }
     ],
     "citations": [
       {
         "reference": "<Book Chapter:Verse>",
         "translation": "<BSB | WEB | KJV>",
         "text": "<exact open-licensed verse text>"
       }
     ],
     "perspectives": [
       {
         "tradition": "<tradition name>",
         "summary": "<charitable summary>",
         "citations": [{ "reference": "...", "translation": "...", "text": "..." }]
       }
     ],
     "refusalReason": null,
     "truthLevel": "scripture_examined"
   }

   HARD RULES FOR YOUR OUTPUT:
   - "perspectives" is populated ONLY when overall verdict is "contested". Empty array otherwise.
   - "citations" contains ONLY BSB/WEB/KJV text. Any other translation is a hard contract violation.
   - If status is "grounded", verdict MUST be non-null.
   - Do not include commentary outside the JSON object.
   - Do not wrap the JSON in markdown code fences.
`;
}

// ---------------------------------------------------------------------------
// buildRefusalResponse
// ---------------------------------------------------------------------------

/**
 * Builds a partial DiscernmentCheck with status:'refused'.
 * Used when NeMo blocks input/output, or when a hard constraint prevents processing.
 *
 * Invariants from selah.contracts.ts:
 *   - status === 'refused' => verdict null, citations empty, refusalReason set
 *
 * @param {string} reason - Human-readable reason for the refusal
 * @returns {object} Partial DiscernmentCheck with status:'refused'
 */
function buildRefusalResponse(reason) {
  if (!reason || typeof reason !== "string" || reason.trim() === "") {
    // A refusal must always have a reason — even if we have to provide a fallback.
    reason = "This check could not be completed. Please try again.";
  }

  return {
    status: "refused",
    verdict: null,
    claims: [],
    citations: [],          // INVARIANT: refused checks have empty citations
    perspectives: [],
    refusalReason: reason.trim(),
    truthLevel: "refused",
  };
}

// ---------------------------------------------------------------------------
// extractClaimsPrompt
// ---------------------------------------------------------------------------

/**
 * Builds a shorter extraction-only prompt for a first-pass claim identification.
 * This is used as an optional pre-step before the full discernment prompt.
 * The engine may call this separately and inject the results into buildDiscernmentPrompt.
 *
 * Output: a JSON array of claim strings, e.g.:
 *   ["Salvation is by faith alone.", "The Holy Spirit does not give gifts today."]
 *
 * @param {string} inputText - The raw text to extract claims from
 * @returns {string} Prompt string for the claims-extraction pass
 */
function extractClaimsPrompt(inputText) {
  return `${BEREAN_PREAMBLE}

════════════════════════════════════════════════════════════
EXTRACTION TASK — CLAIM IDENTIFICATION ONLY
════════════════════════════════════════════════════════════

Read the following text and identify each distinct theological, ethical, historical, or devotional claim it makes. A "claim" is any statement that can be assessed against Scripture or Christian teaching.

Guidelines:
- Extract only explicit or strongly implied claims — do not add your own.
- Ignore rhetorical questions, greetings, and personal anecdotes unless they embed claims.
- If the text makes no assessable claims, return an empty array.
- Classify each claim as: doctrinal | ethical | historical | devotional | unverifiable
- Keep each claim concise (one sentence or phrase).

TEXT:
${inputText}

OUTPUT FORMAT:
Return ONLY a valid JSON array of strings. No commentary, no markdown fences.
Example: ["Claim one.", "Claim two."]

If no claims are found, return: []`;
}

// ---------------------------------------------------------------------------
// EXPORTS
// ---------------------------------------------------------------------------

module.exports = {
  buildDiscernmentPrompt,
  buildRefusalResponse,
  extractClaimsPrompt,
  // Export constants so the engine can reference them without re-declaring
  BEREAN_PREAMBLE,
  VALID_CLAIM_CLASSES,
  VALID_VERDICTS,
  OPEN_TRANSLATIONS,
};
