"use strict";

/**
 * policyMap.js
 *
 * Central policy constants for the AMEN moderation pipeline.
 *
 * - POLICY_VERSION: immutable string stamped on every audit log entry.
 * - MODERATION_STATUS: canonical decision values produced by the orchestrator.
 * - SAFETY_CATEGORIES: full taxonomy used across text, image, and link checks.
 * - CATEGORY_ACTIONS: per-category disposition rules (auto-block / review / escalate).
 * - RISK_THRESHOLDS: numeric risk-score bands that map to MODERATION_STATUS values.
 *
 * Policy changes MUST increment POLICY_VERSION and be reviewed by trust & safety.
 */

// ─── Policy version ───────────────────────────────────────────────────────────

const POLICY_VERSION = "amen-safety-v1";

// ─── Moderation status values ─────────────────────────────────────────────────

/**
 * MODERATION_STATUS
 *
 * Canonical string values written to content documents and audit logs.
 *
 *   APPROVED  — content passed all checks; visible: true
 *   BLOCKED   — content failed at least one hard check; visible: false, removed: true
 *   PENDING   — content requires human review; visible: false, queued
 *   ESCALATED — child-safety or critical category detected; visible: false, legal hold
 */
const MODERATION_STATUS = Object.freeze({
  APPROVED:  "approved",
  BLOCKED:   "blocked",
  PENDING:   "pending",
  ESCALATED: "escalated",
});

// ─── Safety category taxonomy ─────────────────────────────────────────────────

/**
 * SAFETY_CATEGORIES
 *
 * All recognised category strings used by text, image, and link moderation.
 * String values are lower_snake_case for consistency with NeMo Guard output.
 *
 * Categories beginning with "cs_" are child-safety categories that trigger
 * the ESCALATED path and mandatory legal reporting.
 */
const SAFETY_CATEGORIES = Object.freeze([
  // Child-safety (CS) — always escalate; no auto-block path
  "cs_csam_suspected",
  "cs_child_exploitation",
  "cs_child_grooming",
  "cs_child_trafficking",
  "cs_child_safety_other",

  // Adult / sexual content
  "sexual_content",
  "nudity",
  "suggestive_content",

  // Violence & harm
  "graphic_violence",
  "self_harm",
  "self_harm_instructions",
  "suicide_encouragement",
  "dangerous_activity",

  // Hate & harassment
  "hate_speech",
  "discrimination",
  "harassment",
  "bullying",
  "threat",
  "doxxing",

  // Misinformation / integrity
  "misinformation",
  "religious_misinformation",
  "health_misinformation",
  "electoral_misinformation",

  // Spam & manipulation
  "spam",
  "phishing",
  "scam",
  "malware_link",

  // Unsafe link schemes
  "unsafe_link_scheme",

  // Platform integrity
  "impersonation",
  "coordinated_inauthentic_behavior",

  // Image-specific pipeline categories
  "image_review_required",
  "pending_image_review",

  // Fallback
  "unknown_model_error",
  "other_policy_violation",
]);

// ─── Category-to-action mapping ───────────────────────────────────────────────

/**
 * CATEGORY_ACTIONS
 *
 * Maps each safety category to its disposition action.
 *
 *   "escalate"   — immediately call escalateChildSafety; do not route to general queue
 *   "auto_block" — set visible: false, removed: true, status: "blocked"
 *   "review"     — set visible: false, status: "pending"; add to moderationQueue
 *
 * A single piece of content may trigger multiple categories; the most severe
 * action wins: escalate > auto_block > review.
 */
const CATEGORY_ACTIONS = Object.freeze({
  // Child-safety — escalate always
  cs_csam_suspected:       "escalate",
  cs_child_exploitation:   "escalate",
  cs_child_grooming:       "escalate",
  cs_child_trafficking:    "escalate",
  cs_child_safety_other:   "escalate",

  // Hard auto-blocks
  sexual_content:           "auto_block",
  nudity:                   "auto_block",
  graphic_violence:         "auto_block",
  self_harm_instructions:   "auto_block",
  suicide_encouragement:    "auto_block",
  dangerous_activity:       "auto_block",
  hate_speech:              "auto_block",
  threat:                   "auto_block",
  phishing:                 "auto_block",
  malware_link:             "auto_block",
  unsafe_link_scheme:       "auto_block",

  // Human review required
  suggestive_content:       "review",
  self_harm:                "review",
  harassment:               "review",
  bullying:                 "review",
  discrimination:           "review",
  doxxing:                  "review",
  misinformation:           "review",
  religious_misinformation: "review",
  health_misinformation:    "review",
  electoral_misinformation: "review",
  spam:                     "review",
  scam:                     "review",
  impersonation:            "review",
  coordinated_inauthentic_behavior: "review",

  // Image pipeline
  image_review_required:   "review",
  pending_image_review:    "review",

  // Fallbacks
  unknown_model_error:     "review",
  other_policy_violation:  "review",
});

// ─── Risk score thresholds ────────────────────────────────────────────────────

/**
 * RISK_THRESHOLDS
 *
 * The orchestrator computes a numeric riskScore in [0, 1].
 * These bands map scores to MODERATION_STATUS values.
 *
 *   >= ESCALATE_THRESHOLD  → ESCALATED  (child-safety only; score alone does not escalate)
 *   >= BLOCK_THRESHOLD     → BLOCKED
 *   >= REVIEW_THRESHOLD    → PENDING
 *   <  REVIEW_THRESHOLD    → APPROVED
 *
 * Note: child-safety categories always trigger ESCALATED regardless of score.
 * Note: auto_block categories always trigger BLOCKED regardless of score.
 */
const RISK_THRESHOLDS = Object.freeze({
  BLOCK_THRESHOLD:    0.7,
  REVIEW_THRESHOLD:   0.3,
});

/**
 * resolveDisposition(categories, riskScore)
 *
 * Given a list of detected categories and a computed risk score, returns the
 * canonical MODERATION_STATUS value that the orchestrator should apply.
 *
 * Severity order: escalate > auto_block > review > approve
 *
 * @param {string[]} categories   Normalised category strings
 * @param {number}   riskScore    Numeric score in [0, 1]
 * @returns {string}  One of MODERATION_STATUS values
 */
function resolveDisposition(categories, riskScore) {
  const cats = (categories ?? []).map((c) => String(c).toLowerCase().trim());

  // 1. Escalate takes absolute priority.
  if (cats.some((c) => CATEGORY_ACTIONS[c] === "escalate")) {
    return MODERATION_STATUS.ESCALATED;
  }

  // 2. Auto-block — hard categories or high risk score.
  if (
    cats.some((c) => CATEGORY_ACTIONS[c] === "auto_block") ||
    riskScore >= RISK_THRESHOLDS.BLOCK_THRESHOLD
  ) {
    return MODERATION_STATUS.BLOCKED;
  }

  // 3. Review — review categories or moderate risk score.
  if (
    cats.some((c) => CATEGORY_ACTIONS[c] === "review") ||
    riskScore >= RISK_THRESHOLDS.REVIEW_THRESHOLD
  ) {
    return MODERATION_STATUS.PENDING;
  }

  // 4. All clear.
  return MODERATION_STATUS.APPROVED;
}

// ─── Exports ──────────────────────────────────────────────────────────────────

module.exports = {
  POLICY_VERSION,
  MODERATION_STATUS,
  SAFETY_CATEGORIES,
  CATEGORY_ACTIONS,
  RISK_THRESHOLDS,
  resolveDisposition,
};
