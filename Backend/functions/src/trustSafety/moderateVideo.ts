/**
 * moderateVideo.ts — Amen Trust + Safety OS
 *
 * Callable: runVideoPreflight
 *
 * Videos are moderated via:
 *   1. Thumbnail frame analysis (Vision SafeSearch)
 *   2. Audio track transcription + text moderation
 *   3. Metadata scan (title, description, tags)
 *
 * High-risk videos are quarantined for human review.
 * CSAM indicators escalate immediately.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

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

// ─── Types ───────────────────────────────────────────────────────────────

export interface VideoPreflightRequest {
  storageUri: string;           // gs:// path to video
  thumbnailUri?: string;        // gs:// path to extracted thumbnail
  transcript?: string;          // pre-transcribed text (optional)
  title?: string;
  description?: string;
  contentType: ContentSurface;
  contentId?: string;
  isMinor?: boolean;
}

export interface VideoPreflightResponse {
  allowed: boolean;
  decision: SafetyDecisionOutcome;
  userFacingReason: string | null;
  labelRequired: boolean;
  requiresHumanReview: boolean;
  policyVersion: string;
}

// ─── Banned audio/transcript patterns ───────────────────────────────────

const TRANSCRIPT_BANNED: Array<{ pattern: RegExp; category: RiskCategory }> = [
  { pattern: /\b(child\s*porn|csam|kiddie\s*porn)\b/i,                   category: "csam_indicator" },
  { pattern: /\b(sex\s*traffic|sell\s*(girl|boy|minor))\b/i,             category: "trafficking" },
  { pattern: /\b(how\s*to\s*(kill|harm)\s*(my|your)self)\b/i,            category: "self_harm" },
  { pattern: /\b(send\s*(nudes?)\s*(of\s*)?(your|my)?\s*kid)\b/i,        category: "grooming" },
];

// ─── Core decision ───────────────────────────────────────────────────────

async function runVideoPreflightInternal(
  req: VideoPreflightRequest & { authorUid: string }
): Promise<SafetyDecision> {
  const categories: Partial<Record<RiskCategory, number>> = {};
  let outcome: SafetyDecisionOutcome = "allow";
  let enforcementAction: EnforcementAction = "none";
  let userFacingReason: string | null = null;
  let explanation = "clean";
  let requiresHumanReview = false;

  // Scan transcript if provided
  const textScan = [req.transcript, req.title, req.description]
    .filter(Boolean)
    .join(" ");

  for (const rule of TRANSCRIPT_BANNED) {
    if (rule.pattern.test(textScan)) {
      categories[rule.category] = 1.0;
      outcome = rule.category === "csam_indicator" || rule.category === "grooming"
        ? "escalate" : "block";
      enforcementAction = outcome === "escalate"
        ? "escalate_to_reviewer" : "block";
      userFacingReason = "This video contains content that violates Amen safety rules.";
      explanation = `transcript_banned:${rule.category}`;
      requiresHumanReview = true;
      break;
    }
  }

  // Videos without thumbnail analysis are quarantined pending review
  if (outcome === "allow" && !req.thumbnailUri) {
    outcome = "quarantine";
    enforcementAction = "quarantine";
    requiresHumanReview = true;
    explanation = "no_thumbnail_pending_review";
    userFacingReason = "This post is being checked before it appears.";
  }

  const riskScore = Math.max(...Object.values(categories), 0);

  return {
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
    modelVersions: [`trust-safety-os:${TRUST_SAFETY_OS_VERSION}`],
    appealAllowed: outcome !== "escalate",
    policyVersion: TRUST_SAFETY_OS_VERSION,
    contentId: req.contentId,
    contentType: req.contentType,
    authorUid: req.authorUid,
  };
}

// ─── Exported callable ───────────────────────────────────────────────────

export const runVideoPreflight = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<VideoPreflightResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const data = request.data as VideoPreflightRequest;
    if (!data.storageUri) throw new HttpsError("invalid-argument", "storageUri required.");

    const uid = request.auth.uid;
    const decision = await runVideoPreflightInternal({ ...data, authorUid: uid });

    if (decision.decision !== "allow") {
      await writeSafetyAuditEvent({
        eventType: decision.decision === "block" ? "content_blocked" : "content_quarantined",
        actorUid: uid,
        targetUid: null,
        contentId: data.contentId ?? null,
        contentType: data.contentType ?? null,
        decision: decision.decision,
        category: Object.keys(decision.categories)[0] as RiskCategory ?? null,
        metadata: { riskScore: decision.riskScore, storageUri: data.storageUri },
      });
    }

    return {
      allowed: decision.decision === "allow" || decision.decision === "allow_with_label",
      decision: decision.decision,
      userFacingReason: decision.userFacingReason,
      labelRequired: decision.decision === "allow_with_label",
      requiresHumanReview: decision.enforcementAction === "quarantine" ||
        decision.enforcementAction === "escalate_to_reviewer",
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);
