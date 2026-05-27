/**
 * TextModerationService.ts
 *
 * Backend text moderation pipeline for Amen Safety OS.
 * Callable by iOS via moderateText(), and internally by onPostCreated,
 * comment creation, DM sending, and profile update triggers.
 *
 * Pipeline layers (fastest-first):
 *   Layer 0 — Deterministic banned-term regex (synchronous, no network)
 *   Layer 1 — Perspective API toxicity scoring (async, external)
 *   Layer 2 — Policy catalog enforcement (from AmenSafetyPolicy)
 *
 * Fails CLOSED: if the Perspective API is unavailable, uncertain content
 * is held for human review rather than being allowed.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import axios from "axios";
import {
  AMEN_POLICY_CATALOG,
  userFacingMessageFor,
  ModerationStatus,
  EnforcementAction,
} from "./AmenSafetyPolicy";
import { AMEN_SAFETY_POLICY_VERSION } from "./AmenSafetyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

export interface TextModerationRequest {
  text: string;
  contentType: "post" | "comment" | "dm" | "profile_bio" | "username" | "search" | "event_title" | "group_name" | "church_name" | "church_description" | "livestream_title";
  contentId?: string;
  isMinor?: boolean;
}

export interface TextModerationResult {
  allowed: boolean;
  enforcement: EnforcementAction;
  moderationStatus: ModerationStatus;
  harmCategoryId: string | null;
  userFacingMessage: string | null;
  requiresHumanReview: boolean;
  contentWarning: string | null;
  perspectiveScores?: Record<string, number>;
  triggeredRule?: string;
  policyVersion: string;
}

// ─── Banned-Term Rules (Layer 0) ──────────────────────────────────────────────

interface BannedTermRule {
  pattern: RegExp;
  harmCategoryId: string;
}

/**
 * Deterministic rules checked before any network call.
 * Patterns are intentionally broad and include common leet-speak variants.
 * Do NOT add overly specific patterns here — context-sensitive judgment
 * belongs to Layer 1 (Perspective).
 */
const BANNED_TERM_RULES: BannedTermRule[] = [
  // CSAM signal words
  { pattern: /\b(c[- ]?h[- ]?i[- ]?l[- ]?d[- ]?p[- ]?o[- ]?r[- ]?n|cp[- ]?trade|jailbait)\b/i, harmCategoryId: "csam" },
  // Trafficking
  { pattern: /\b(sex[- ]?traffick|human[- ]?traffick|escort[- ]?agency[- ]?for[- ]?sale|buy[- ]?girl[- ]?cheap)\b/i, harmCategoryId: "sex_trafficking" },
  // Sexual solicitation
  { pattern: /\b(send[- ]?nudes?|onlyfans[- ]?trade|sugar[- ]?daddy[- ]?pay|meet[- ]?irl[- ]?sex|nudes[- ]?for[- ]?(cash|money))\b/i, harmCategoryId: "sexual_solicitation" },
  // Sextortion signals
  { pattern: /\b(i[- ]?have[- ]?your[- ]?photos?[- ]?i[- ]?will[- ]?share|pay[- ]?or[- ]?i[- ]?post[- ]?your[- ]?nudes?)\b/i, harmCategoryId: "sextortion" },
  // Self-harm encouragement
  { pattern: /\b(how[- ]?to[- ]?(kill|hurt)[- ]?your(self)?|cut[- ]?yourself[- ]?to|pro[- ]?ana[- ]?tips)\b/i, harmCategoryId: "self_harm_encouragement" },
  // Drug sales
  { pattern: /\b(buy[- ]?(meth|heroin|fentanyl|crack|xanax)[- ]?(online|now|cheap)|sell[- ]?drugs?[- ]?dm[- ]?me)\b/i, harmCategoryId: "drug_sales" },
  // Illegal weapons
  { pattern: /\b(buy[- ]?guns?[- ]?no[- ]?background|ghost[- ]?guns?[- ]?for[- ]?sale|untraceable[- ]?firearms?)\b/i, harmCategoryId: "illegal_weapon_sales" },
  // Doxxing patterns
  { pattern: /\b(here[- ]?is[- ]?your[- ]?(address|phone|ssn)|doxx(ing)?[- ]?you|exposing[- ]?your[- ]?(home|location))\b/i, harmCategoryId: "doxxing" },
  // Phishing / scam
  { pattern: /\b(click[- ]?here[- ]?to[- ]?(claim|win)[- ]?(your[- ]?)?(free[- ]?)?(iphone|gift|cash|prize)|you[- ]?won[- ]?a[- ]?(lottery|prize)[- ]?send[- ]?(fee|deposit))\b/i, harmCategoryId: "scam_phishing" },
];

// Profanity list (top English profanities — extend as needed)
const PROFANITY_PATTERNS = /\b(f+u+c+k+|s+h+i+t+|a+s+s+h+o+l+e+|b+i+t+c+h+|c+u+n+t+|d+i+c+k+|n+i+g+g+|f+a+g+g+)\b/i;

function checkBannedTerms(text: string): { matched: boolean; harmCategoryId: string; triggeredRule: string } | null {
  for (const rule of BANNED_TERM_RULES) {
    if (rule.pattern.test(text)) {
      return { matched: true, harmCategoryId: rule.harmCategoryId, triggeredRule: rule.pattern.source };
    }
  }
  if (PROFANITY_PATTERNS.test(text)) {
    return { matched: true, harmCategoryId: "profanity", triggeredRule: "profanity_pattern" };
  }
  return null;
}

// ─── Perspective API (Layer 1) ────────────────────────────────────────────────

const PERSPECTIVE_ENDPOINT = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze";

interface PerspectiveScore {
  summaryScore: { value: number };
}

interface PerspectiveResponse {
  attributeScores: Record<string, PerspectiveScore>;
}

async function scorePerspective(text: string): Promise<Record<string, number>> {
  const apiKey = process.env.PERSPECTIVE_API_KEY;
  if (!apiKey) {
    logger.warn("[TextModerationService] PERSPECTIVE_API_KEY not set — skipping Layer 1.");
    return {};
  }

  try {
    const response = await axios.post<PerspectiveResponse>(
      `${PERSPECTIVE_ENDPOINT}?key=${apiKey}`,
      {
        comment: { text },
        languages: ["en"],
        requestedAttributes: {
          TOXICITY: {},
          SEVERE_TOXICITY: {},
          SEXUALLY_EXPLICIT: {},
          THREAT: {},
          INSULT: {},
          PROFANITY: {},
          IDENTITY_ATTACK: {},
        },
      },
      { timeout: 5000 }
    );

    const scores: Record<string, number> = {};
    for (const [attr, val] of Object.entries(response.data.attributeScores)) {
      scores[attr] = val.summaryScore.value;
    }
    return scores;
  } catch (err) {
    logger.warn("[TextModerationService] Perspective API error — failing closed.", err);
    return {};
  }
}

function harmFromPerspective(scores: Record<string, number>, isMinor: boolean): string | null {
  const minorMultiplier = isMinor ? 0.85 : 1.0; // 15% stricter threshold for minors

  if ((scores["SEXUALLY_EXPLICIT"] ?? 0) > 0.7 * minorMultiplier) return "sexual_content";
  if ((scores["SEVERE_TOXICITY"] ?? 0) > 0.85 * minorMultiplier) return "hate_speech";
  if ((scores["THREAT"] ?? 0) > 0.8 * minorMultiplier) return "violence_threat";
  if ((scores["IDENTITY_ATTACK"] ?? 0) > 0.75 * minorMultiplier) return "hate_speech";
  if ((scores["PROFANITY"] ?? 0) > 0.9 * minorMultiplier) return "profanity";
  if ((scores["TOXICITY"] ?? 0) > 0.95 * minorMultiplier) return "harassment";
  return null;
}

function borderlineFromPerspective(scores: Record<string, number>, isMinor: boolean): string | null {
  const minorMultiplier = isMinor ? 0.85 : 1.0;
  // Borderline thresholds: lower than block thresholds, indicating content worth labeling
  if ((scores["TOXICITY"] ?? 0) > 0.55 * minorMultiplier && (scores["TOXICITY"] ?? 0) <= 0.95 * minorMultiplier) {
    return "We added a content notice because some readers may find this post challenging.";
  }
  if ((scores["SEXUALLY_EXPLICIT"] ?? 0) > 0.4 * minorMultiplier && (scores["SEXUALLY_EXPLICIT"] ?? 0) <= 0.7 * minorMultiplier) {
    return "This post contains content some members may prefer to filter.";
  }
  if ((scores["IDENTITY_ATTACK"] ?? 0) > 0.45 * minorMultiplier && (scores["IDENTITY_ATTACK"] ?? 0) <= 0.75 * minorMultiplier) {
    return "This post addresses a sensitive topic — approach with grace.";
  }
  return null;
}

// ─── Core Moderation Logic ────────────────────────────────────────────────────

export async function moderateText(
  text: string,
  contentType: TextModerationRequest["contentType"],
  isMinor = false,
  _contentId?: string
): Promise<TextModerationResult> {
  if (!text || text.trim().length === 0) {
    return {
      allowed: true,
      enforcement: "allow",
      moderationStatus: "pending",
      harmCategoryId: null,
      userFacingMessage: null,
      contentWarning: null,
      requiresHumanReview: false,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // Layer 0 — deterministic banned terms
  const bannedMatch = checkBannedTerms(text);
  if (bannedMatch) {
    const policy = AMEN_POLICY_CATALOG.find((p) => p.id === bannedMatch.harmCategoryId);
    const enforcement: EnforcementAction = policy?.enforcement ?? "block";
    return {
      allowed: false,
      enforcement,
      moderationStatus: policy?.moderationStatus ?? "blocked",
      harmCategoryId: bannedMatch.harmCategoryId,
      userFacingMessage: userFacingMessageFor(bannedMatch.harmCategoryId),
      contentWarning: null,
      requiresHumanReview: policy?.moderationStatus === "needs_human_review",
      triggeredRule: bannedMatch.triggeredRule,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // Layer 1 — Perspective API
  const perspectiveScores = await scorePerspective(text);
  const perspectiveHarm = harmFromPerspective(perspectiveScores, isMinor);

  if (perspectiveHarm) {
    const policy = AMEN_POLICY_CATALOG.find((p) => p.id === perspectiveHarm);
    const enforcement: EnforcementAction = policy?.enforcement ?? "block";
    return {
      allowed: enforcement === "allow" || enforcement === "warn_user",
      enforcement,
      moderationStatus: policy?.moderationStatus ?? "blocked",
      harmCategoryId: perspectiveHarm,
      userFacingMessage: userFacingMessageFor(perspectiveHarm),
      contentWarning: null,
      requiresHumanReview: policy?.moderationStatus === "needs_human_review",
      perspectiveScores,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  // All layers passed — content is safe
  // Check for borderline content that passes moderation but warrants a label
  const contentWarning = borderlineFromPerspective(perspectiveScores, isMinor);
  if (contentWarning) {
    return {
      allowed: true,
      enforcement: "content_warning",
      moderationStatus: "borderline",
      harmCategoryId: null,
      userFacingMessage: null,
      contentWarning,
      requiresHumanReview: false,
      perspectiveScores,
      policyVersion: AMEN_SAFETY_POLICY_VERSION,
    };
  }

  return {
    allowed: true,
    enforcement: "allow",
    moderationStatus: "approved",
    harmCategoryId: null,
    userFacingMessage: null,
    contentWarning: null,
    requiresHumanReview: false,
    perspectiveScores,
    policyVersion: AMEN_SAFETY_POLICY_VERSION,
  };
}

// ─── Callable Function ────────────────────────────────────────────────────────

/**
 * moderateText callable
 *
 * Called by iOS before post/comment/DM submission when the client needs a
 * server-authoritative moderation decision for a text payload.
 *
 * The client must treat "allowed: false" as a hard gate and must NOT post
 * content without receiving "allowed: true" from this function.
 *
 * Input:  TextModerationRequest
 * Output: TextModerationResult (without internalReason)
 */
export const moderateTextCallable = onCall(
  { enforceAppCheck: true },
  async (request: CallableRequest<TextModerationRequest>): Promise<TextModerationResult> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const { text, contentType, contentId, isMinor } = request.data;

    if (!text || typeof text !== "string") {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > 10_000) {
      throw new HttpsError("invalid-argument", "text exceeds maximum length.");
    }

    const uid = request.auth.uid;
    const result = await moderateText(text, contentType, isMinor ?? false, contentId);

    // Write audit entry for non-allowed decisions
    if (!result.allowed && result.harmCategoryId) {
      try {
        await db.collection("textModerationLogs").add({
          uid,
          contentType,
          contentId: contentId ?? null,
          harmCategoryId: result.harmCategoryId,
          enforcement: result.enforcement,
          policyVersion: result.policyVersion,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (logErr) {
        logger.warn("[TextModerationService] Failed to write audit log.", logErr);
      }
    }

    // Strip internal scores before returning to client
    const { perspectiveScores: _, triggeredRule: __, ...clientResult } = result;
    return { ...clientResult, policyVersion: AMEN_SAFETY_POLICY_VERSION };
  }
);
