/**
 * functions/connectedIntelligence/transformFunctions.js
 *
 * AMEN Connected Intelligence v1 — Response Action Sheet AI transforms.
 *
 * ONE callable: bereanTransform. Maps the 6 sheet transforms to the REAL
 * routing task keys in functions/router/amenRouting.config.js, runs them
 * through callModel, and returns a TYPED result the action sheet can render —
 * including the distinct moderation-blocked / refusal states.
 *
 * Transform → task mapping (verified against amenRouting.config.js):
 *   simplify        → scripture ? berean_explain : quick_summary
 *   deep_dive       → scripture ? berean_explain : deep_analysis
 *   challenge_this  → berean_perspective   (Acts 17:11 — labeled+cited traditions)
 *   generate_questions → family_questions
 *   verify_scripture → berean_answer       (claude-exclusive, requireCitations → cite-or-refuse)
 *   show_sources     → berean_answer       (claude-exclusive, requireCitations → cite-or-refuse)
 *
 * Hard rules:
 *   1. requireBereanAuth first (local helper, mirrors v2functions.js).
 *   2. enforceRateLimit(uid, "bereanTransform", 40, 3600).
 *   3. sourceDomain validated against the FROZEN 14-value Domain union.
 *      'crisis' is REJECTED — transforms never run on crisis content.
 *   4. Scripture transforms (verify_scripture / show_sources, and the scripture
 *      branch of simplify/deep_dive) are claude-exclusive + fail-closed via the
 *      routing config — citations_required block ⇒ typed refusal, never fabrication.
 *   5. NEVER throws HttpsError for a moderation/refusal outcome — returns
 *      { blocked, refusal, ... } so the sheet renders the distinct blocked state.
 *      HttpsError is reserved for auth / bad-input / rate-limit only.
 *
 * Domain is INHERITED from sourceDomain (the originating response's domain) so a
 * transform of a scripture answer stays claude-exclusive end-to-end.
 *
 * OWNER: Agent F (Response Action Sheet). Connected Intelligence v1.
 */

"use strict";

const { onCall: onCallV2, HttpsError: HttpsErrorV2 } = require("firebase-functions/v2/https");
const { defineSecret: defineSecretV2 } = require("firebase-functions/params");
const loggerV2 = require("firebase-functions/logger");

const { enforceRateLimit } = require("../rateLimiter");
const { callModel } = require("../router/callModel");

// Secrets used by the routes this callable can hit (Claude + NVIDIA guard +
// Pinecone retrieval for the grounded scripture branches).
const TRANSFORM_ANTHROPIC_KEY = defineSecretV2("ANTHROPIC_API_KEY");
const TRANSFORM_NVIDIA_KEY    = defineSecretV2("NVIDIA_API_KEY");
const TRANSFORM_PINECONE_KEY  = defineSecretV2("PINECONE_API_KEY");
const TRANSFORM_PINECONE_HOST = defineSecretV2("PINECONE_HOST");

// ─────────────────────────────────────────────────────────────────────────────
// FROZEN Domain union (mirror of src/berean/contracts.ts — 14 values).
// sourceDomain MUST be one of these. 'crisis' is valid in the union but is
// explicitly rejected for transforms.
// ─────────────────────────────────────────────────────────────────────────────

const DOMAIN_UNION = new Set([
  "scripture", "prayer", "devotional", "theology", "pastoral", "study",
  "church_notes", "reflection", "discovery", "admin", "giving",
  "safety", "general", "crisis",
]);

// Domains that are treated as scripture-grounded ⇒ claude-exclusive routing.
const SCRIPTURE_DOMAINS = new Set(["scripture", "theology", "pastoral", "study", "devotional"]);

// The 6 transforms the action sheet can request.
const VALID_TRANSFORMS = new Set([
  "simplify", "deep_dive", "challenge_this",
  "generate_questions", "verify_scripture", "show_sources",
]);

// ─────────────────────────────────────────────────────────────────────────────
// Shared auth helper (local — mirrors v2functions.js requireBereanAuth).
// ─────────────────────────────────────────────────────────────────────────────

function requireBereanAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsErrorV2("unauthenticated", "Authentication required.");
  }
  return request.auth.uid;
}

/**
 * Resolve a transform + source domain to a real routing task key.
 * Returns { task, claudeExclusive }.
 *
 * Scripture-grounded source ⇒ Claude-exclusive routes everywhere.
 */
function resolveTask(transform, sourceDomain) {
  const isScripture = SCRIPTURE_DOMAINS.has(sourceDomain);

  switch (transform) {
    case "simplify":
      return isScripture
        ? { task: "berean_explain", claudeExclusive: true }
        : { task: "quick_summary", claudeExclusive: false };
    case "deep_dive":
      return isScripture
        ? { task: "berean_explain", claudeExclusive: true }
        : { task: "deep_analysis", claudeExclusive: false };
    case "challenge_this":
      // Acts 17:11 — labeled + cited traditions, no manufactured controversy.
      return { task: "berean_perspective", claudeExclusive: true };
    case "generate_questions":
      return { task: "family_questions", claudeExclusive: true };
    case "verify_scripture":
    case "show_sources":
      // ALWAYS Claude-exclusive; requireCitations ⇒ cite-or-refuse.
      return { task: "berean_answer", claudeExclusive: true };
    default:
      return null;
  }
}

/**
 * Task-specific system prompt. Keeps each transform on-rails and reverent.
 * No manufactured controversy; cite-or-refuse for scripture verification.
 */
function systemPromptFor(transform) {
  switch (transform) {
    case "simplify":
      return "Restate the following faith content in plainer, simpler language. Preserve every scripture citation exactly. Do not add new claims. If a claim cannot be grounded, omit it rather than soften the truth.";
    case "deep_dive":
      return "Expand the following faith content with deeper context, grounded in scripture and historic Christian teaching. Cite every scripture reference. Do not speculate beyond what can be grounded.";
    case "challenge_this":
      return "Following Acts 17:11, present the legitimate, historically-held Christian perspectives on this question. Label each tradition or view by name and cite its scriptural basis. Do NOT manufacture controversy, and do NOT issue a single verdict — surface the honest range of faithful views.";
    case "generate_questions":
      return "Generate a short set of reflective discussion questions a family or small group could use to engage this content together. Keep them open, warm, and scripture-anchored.";
    case "verify_scripture":
      return "Verify the scripture references in the following content. For each, confirm the reference and quote it from an open-licensed translation. If a reference cannot be verified from a grounded source, say so plainly. Cite every verse. Never fabricate a reference.";
    case "show_sources":
      return "List the grounded sources behind the following content — scripture references and historic Christian documents — with exact citations. If a claim has no grounded source, state that it is unsourced rather than inventing one.";
    default:
      return "You are Berean, a reverent formation assistant. Stay grounded; cite scripture; never fabricate.";
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// bereanTransform — the single Response Action Sheet AI-transform callable.
//
// Request:
//   transform     {string}  one of VALID_TRANSFORMS
//   sourceText    {string}  the originating Berean response text (1–6000 chars)
//   sourceDomain  {Domain}  domain of the originating response (14-value union)
//
// Response (typed — NEVER an HttpsError for a moderation/refusal outcome):
//   { text, provenance, blocked, refusal, task, claudeExclusive }
//     blocked === true  ⇒ sheet renders the DISTINCT moderation-blocked state.
//     refusal !== null  ⇒ reason string (citations_required, moderation_blocked, …)
// ─────────────────────────────────────────────────────────────────────────────

exports.bereanTransform = onCallV2(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    secrets: [
      TRANSFORM_ANTHROPIC_KEY,
      TRANSFORM_NVIDIA_KEY,
      TRANSFORM_PINECONE_KEY,
      TRANSFORM_PINECONE_HOST,
    ],
  },
  async (request) => {
    // ── 1. Auth ──────────────────────────────────────────────────────────────
    const uid = requireBereanAuth(request);

    // ── 2. Input validation ──────────────────────────────────────────────────
    const { transform, sourceText, sourceDomain } = request.data ?? {};

    if (!transform || typeof transform !== "string" || !VALID_TRANSFORMS.has(transform)) {
      throw new HttpsErrorV2(
        "invalid-argument",
        `transform must be one of: ${[...VALID_TRANSFORMS].join(", ")}.`,
      );
    }
    if (!sourceText || typeof sourceText !== "string" || sourceText.trim().length < 1) {
      throw new HttpsErrorV2("invalid-argument", "sourceText is required.");
    }
    if (sourceText.length > 6000) {
      throw new HttpsErrorV2("invalid-argument", "sourceText exceeds 6000 character limit.");
    }
    if (!sourceDomain || typeof sourceDomain !== "string" || !DOMAIN_UNION.has(sourceDomain)) {
      throw new HttpsErrorV2(
        "invalid-argument",
        "sourceDomain must be one of the 14 valid Berean domains.",
      );
    }

    // ── 3. Crisis domain is never transformed ────────────────────────────────
    if (sourceDomain === "crisis") {
      loggerV2.warn("bereanTransform: crisis domain rejected", { uid, transform });
      return {
        text: null,
        provenance: { sources: [], truthLevel: "refused" },
        blocked: true,
        refusal: "crisis_handoff",
        task: null,
        claudeExclusive: true,
      };
    }

    // ── 4. Rate limit ────────────────────────────────────────────────────────
    await enforceRateLimit(uid, "bereanTransform", 40, 3600);

    // ── 5. Resolve real routing task (domain inherited from sourceDomain) ────
    const resolved = resolveTask(transform, sourceDomain);
    if (!resolved) {
      // Unreachable (transform already validated) — fail closed, never run unrouted.
      throw new HttpsErrorV2("invalid-argument", "Unroutable transform.");
    }
    const { task, claudeExclusive } = resolved;

    loggerV2.info("bereanTransform", { uid, transform, sourceDomain, task, claudeExclusive });

    // ── 6. Run the transform through the central router ──────────────────────
    let result;
    try {
      result = await callModel({
        task,
        input: sourceText,
        systemPrompt: systemPromptFor(transform),
        userId: uid,
        safetyLevel: claudeExclusive ? "strict" : "standard",
      });
    } catch (err) {
      // Router threw (provider config / unknown task). Fail closed, typed refusal.
      loggerV2.error("bereanTransform: callModel threw", { uid, transform, task, error: err.message });
      return {
        text: null,
        provenance: { sources: [], truthLevel: "refused" },
        blocked: true,
        refusal: "provider_unavailable",
        task,
        claudeExclusive,
      };
    }

    // ── 7. Typed outcome mapping (NEVER HttpsError for moderation/refusal) ────
    if (result.blocked) {
      // citations_required (cite-or-refuse), input/output guard, retrieval_failed,
      // provider_unavailable, feature_disabled → all surface as a distinct,
      // renderable blocked state.
      const reason = result.reason ?? "moderation_blocked";
      loggerV2.warn("bereanTransform: blocked", { uid, transform, task, reason });
      return {
        text: null,
        provenance: { sources: [], truthLevel: "refused" },
        blocked: true,
        refusal: reason,
        task,
        claudeExclusive,
      };
    }

    if (result.degraded) {
      return {
        text: null,
        provenance: { sources: [], truthLevel: "refused" },
        blocked: false,
        refusal: "provider_unavailable",
        task,
        claudeExclusive,
      };
    }

    return {
      text: result.output ?? "",
      provenance: { sources: [], truthLevel: claudeExclusive ? "grounded" : "inferred" },
      blocked: false,
      refusal: null,
      task,
      claudeExclusive,
    };
  },
);
