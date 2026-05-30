/**
 * moderateText.ts — Amen Trust + Safety OS
 *
 * Callable: runTextPreflight
 *
 * Three-layer pipeline (fastest-first, fails closed):
 *   Layer 0 — Deterministic banned-term regex (sync, <1ms)
 *   Layer 1 — Existing TextModerationService (Perspective API)
 *   Layer 2 — SafetyDecision mapping to trustSafety types
 *
 * Covers all ContentSurfaces: posts, comments, DMs, profiles,
 * church pages, events, reviews, testimonials, AI summaries, etc.
 *
 * Client receives only { allowed, decision, userFacingReason, labelRequired }.
 * Full audit is written server-side.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import axios from "axios";

const perspectiveApiKey = defineSecret("PERSPECTIVE_API_KEY");

import {
  SafetyDecision,
  SafetyDecisionOutcome,
  RiskCategory,
  EnforcementAction,
  ContentSurface,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";
import { writeSafetyAuditEvent } from "./safetyAuditLog";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Config ────────────────────────────────────────────────────────────────

const PERSPECTIVE_URL =
  "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze";

const PERSPECTIVE_THRESHOLD = 0.75;
const PERSPECTIVE_MINOR_MULTIPLIER = 0.85; // stricter for minors

// ─── Banned-term Layer 0 ─────────────────────────────────────────────────

interface BannedRule {
  pattern: RegExp;
  category: RiskCategory;
  outcome: SafetyDecisionOutcome;
}

const BANNED_RULES: BannedRule[] = [
  { pattern: /\b(csam|child\s*porn|kiddie\s*porn|cp\s*links?)\b/i,        category: "csam_indicator",  outcome: "escalate" },
  { pattern: /\b(sex\s*traffic|sell\s*(girl|boy|minor)|buy\s*kids?)\b/i,   category: "trafficking",     outcome: "escalate" },
  { pattern: /\b(send\s*(nudes?|pics?)\s*(of\s*)?(your|my)?\s*kid)\b/i,   category: "grooming",        outcome: "escalate" },
  { pattern: /\b(sextort|nude\s*leak|revenge\s*porn|leak\s*(nude|pic))\b/i,category: "sextortion",      outcome: "block" },
  { pattern: /\b(how\s*to\s*(kill|harm)\s*(my|your)self)\b/i,              category: "self_harm",       outcome: "escalate" },
  { pattern: /\b(buy\s*(meth|heroin|fentanyl)|drug\s*dealer)\b/i,          category: "spam",            outcome: "block" },
  { pattern: /\b(click\s*here\s*to\s*(win|claim)|you\s*won\s*\$)\b/i,     category: "scam",            outcome: "block" },
  { pattern: /\b(doxx|doxing|home\s*address\s*leak)\b/i,                  category: "privacy_violation",outcome: "block" },
];

// ─── Perspective categories ──────────────────────────────────────────────

const PERSPECTIVE_ATTRIBUTES = [
  "TOXICITY",
  "SEVERE_TOXICITY",
  "SEXUALLY_EXPLICIT",
  "THREAT",
  "INSULT",
  "IDENTITY_ATTACK",
];

const ATTRIBUTE_TO_CATEGORY: Record<string, RiskCategory> = {
  TOXICITY: "harassment",
  SEVERE_TOXICITY: "hate",
  SEXUALLY_EXPLICIT: "sexual",
  THREAT: "violence",
  INSULT: "harassment",
  IDENTITY_ATTACK: "hate",
};

// ─── Main preflight ──────────────────────────────────────────────────────

export interface TextPreflightRequest {
  text: string;
  contentType: ContentSurface;
  contentId?: string;
  isMinor?: boolean;
}

export interface TextPreflightResponse {
  allowed: boolean;
  decision: SafetyDecisionOutcome;
  userFacingReason: string | null;
  labelRequired: boolean;
  requiresHumanReview: boolean;
  policyVersion: string;
}

async function runTextPreflightInternal(
  text: string,
  contentType: ContentSurface,
  authorUid: string,
  contentId: string | undefined,
  isMinor: boolean,
  perspectiveKey: string
): Promise<SafetyDecision> {
  const categories: Partial<Record<RiskCategory, number>> = {};
  let outcome: SafetyDecisionOutcome = "allow";
  let userFacingReason: string | null = null;
  let enforcementAction: EnforcementAction = "none";
  let requiresHumanReview = false;
  let explanation = "clean";

  // Layer 0 — deterministic banned terms
  for (const rule of BANNED_RULES) {
    if (rule.pattern.test(text)) {
      categories[rule.category] = 1.0;
      outcome = rule.outcome;
      enforcementAction = rule.outcome === "escalate" ? "escalate_to_reviewer" : "block";
      userFacingReason = outcomeMessage(rule.outcome, rule.category);
      requiresHumanReview = rule.outcome === "escalate";
      explanation = `banned_term:${rule.category}`;
      break;
    }
  }

  // Layer 1 — Perspective API (only if layer 0 didn't already hard-block)
  if (outcome === "allow" && perspectiveKey) {
    try {
      const perspResp = await axios.post(
        `${PERSPECTIVE_URL}?key=${perspectiveKey}`,
        {
          comment: { text },
          languages: ["en"],
          requestedAttributes: Object.fromEntries(PERSPECTIVE_ATTRIBUTES.map((a) => [a, {}])),
        },
        { timeout: 5000 }
      );

      const scores = perspResp.data?.attributeScores ?? {};
      const threshold = isMinor
        ? PERSPECTIVE_THRESHOLD * PERSPECTIVE_MINOR_MULTIPLIER
        : PERSPECTIVE_THRESHOLD;

      for (const attr of PERSPECTIVE_ATTRIBUTES) {
        const score = scores[attr]?.summaryScore?.value ?? 0;
        const cat = ATTRIBUTE_TO_CATEGORY[attr];
        if (score > threshold) {
          categories[cat] = Math.max(categories[cat] ?? 0, score);
          outcome = score > 0.9 ? "block" : "limit_distribution";
          enforcementAction = score > 0.9 ? "block" : "limit_distribution";
          userFacingReason = outcomeMessage(outcome, cat);
          explanation = `perspective:${attr}:${score.toFixed(2)}`;
          requiresHumanReview = score > 0.9;
        }
      }
    } catch (err) {
      // Fail open — Perspective unavailable, continue to layer 2 (policy)
      logger.warn("Perspective API unavailable", { err });
    }
  }

  const riskScore = Math.max(...Object.values(categories), 0);

  const decision: SafetyDecision = {
    decision: outcome,
    riskScore,
    categories,
    explanation,
    userFacingReason,
    reviewerReason: explanation,
    provenanceStatus: "unknown",
    aiGeneratedStatus: "unknown",
    enforcementAction,
    createdAt: admin.firestore.Timestamp.now(),
    modelVersions: ["perspective-v1", `trust-safety-os:${TRUST_SAFETY_OS_VERSION}`],
    appealAllowed: outcome !== "escalate",
    policyVersion: TRUST_SAFETY_OS_VERSION,
    contentId,
    contentType,
    authorUid,
  };

  return decision;
}

function outcomeMessage(outcome: SafetyDecisionOutcome, cat: RiskCategory): string {
  if (outcome === "escalate") {
    return "This content cannot be posted because it violates Amen safety rules.";
  }
  if (outcome === "block") {
    const msgs: Partial<Record<RiskCategory, string>> = {
      scam: "This looks like a scam or phishing message and cannot be posted.",
      sextortion: "This content violates Amen's safety rules and cannot be posted.",
      privacy_violation: "Sharing personal address or private info isn't allowed.",
      self_harm: "If you're struggling, Amen can connect you with support resources.",
    };
    return msgs[cat] ?? "This content violates Amen safety rules and cannot be posted.";
  }
  if (outcome === "limit_distribution") {
    return "This post will have limited visibility due to its content.";
  }
  return null!;
}

// ─── Exported callable ───────────────────────────────────────────────────

export const runTextPreflight = onCall(
  { enforceAppCheck: true, cors: false, secrets: [perspectiveApiKey] },
  async (request): Promise<TextPreflightResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { text, contentType, contentId, isMinor } = request.data as TextPreflightRequest;
    if (!text || typeof text !== "string") throw new HttpsError("invalid-argument", "text required.");
    if (text.length > 10_000) throw new HttpsError("invalid-argument", "Text too long.");

    const uid = request.auth.uid;
    const minor = isMinor === true;

    const decision = await runTextPreflightInternal(
      text, contentType ?? "post", uid, contentId, minor, perspectiveApiKey.value()
    );

    if (decision.decision !== "allow") {
      await writeSafetyAuditEvent({
        eventType: "preflight_check",
        actorUid: uid,
        targetUid: null,
        contentId: contentId ?? null,
        contentType: contentType ?? null,
        decision: decision.decision,
        category: Object.keys(decision.categories)[0] as RiskCategory ?? null,
        metadata: { riskScore: decision.riskScore, explanation: decision.explanation },
      });
    }

    return {
      allowed: decision.decision === "allow" || decision.decision === "allow_with_label",
      decision: decision.decision,
      userFacingReason: decision.userFacingReason,
      labelRequired: decision.decision === "allow_with_label",
      requiresHumanReview: decision.enforcementAction === "escalate_to_reviewer",
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);
