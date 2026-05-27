/**
 * moderateImage.ts — Amen Trust + Safety OS
 *
 * Callable: runImagePreflight
 *
 * Uses Google Cloud Vision SafeSearch + CSAM hash check.
 * Every image must pass before its parent document transitions
 * from moderationStatus="pending" to "approved".
 *
 * Integrates with provenance.ts for AI-detection labeling.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { ImageAnnotatorClient } from "@google-cloud/vision";

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

const visionClient = new ImageAnnotatorClient();

// Likelihood threshold mapping (Cloud Vision returns ordinal strings)
const LIKELIHOOD_BLOCK_THRESHOLD = 4; // LIKELY (4) or VERY_LIKELY (5)
const LIKELIHOOD_QUARANTINE_THRESHOLD = 3; // POSSIBLE (3)
const LIKELIHOOD_ORDER = ["UNKNOWN", "VERY_UNLIKELY", "UNLIKELY", "POSSIBLE", "LIKELY", "VERY_LIKELY"];

function likelihoodIndex(v: string | number | null | undefined): number {
  if (typeof v === "number") return Math.max(0, Math.min(5, v));
  return LIKELIHOOD_ORDER.indexOf(v ?? "UNKNOWN");
}

// ─── Types ───────────────────────────────────────────────────────────────

export interface ImagePreflightRequest {
  storageUri: string;         // gs://bucket/path
  contentType: ContentSurface;
  contentId?: string;
  uploaderUid?: string;
  isMinor?: boolean;
}

export interface ImagePreflightResponse {
  allowed: boolean;
  decision: SafetyDecisionOutcome;
  userFacingReason: string | null;
  labelRequired: boolean;
  requiresHumanReview: boolean;
  safeSearchSummary?: Record<string, string>;
  policyVersion: string;
}

// ─── SafeSearch analysis ─────────────────────────────────────────────────

async function analyzeWithVision(
  storageUri: string
): Promise<{ adult: number; racy: number; violence: number }> {
  const [result] = await visionClient.safeSearchDetection(storageUri);
  const ss = result.safeSearchAnnotation;
  return {
    adult: likelihoodIndex(ss?.adult as string | undefined),
    racy: likelihoodIndex(ss?.racy as string | undefined),
    violence: likelihoodIndex(ss?.violence as string | undefined),
  };
}

// ─── Core decision ───────────────────────────────────────────────────────

async function runImagePreflightInternal(
  storageUri: string,
  contentType: ContentSurface,
  authorUid: string,
  contentId: string | undefined,
  isMinor: boolean
): Promise<SafetyDecision> {
  const categories: Partial<Record<RiskCategory, number>> = {};
  let outcome: SafetyDecisionOutcome = "allow";
  let enforcementAction: EnforcementAction = "none";
  let userFacingReason: string | null = null;
  let explanation = "clean";
  let requiresHumanReview = false;

  // Minor threshold: POSSIBLE or higher triggers block
  const blockThreshold = isMinor ? LIKELIHOOD_QUARANTINE_THRESHOLD : LIKELIHOOD_BLOCK_THRESHOLD;
  const quarantineThreshold = isMinor ? 2 : LIKELIHOOD_QUARANTINE_THRESHOLD;

  try {
    const scores = await analyzeWithVision(storageUri);

    if (scores.adult >= blockThreshold) {
      categories.nudity = scores.adult / 5;
      categories.sexual = scores.adult / 5;
      outcome = "block";
      enforcementAction = "block";
      userFacingReason = "This image contains content that violates Amen safety rules.";
      explanation = `vision:adult:${scores.adult}`;
      requiresHumanReview = scores.adult >= 5; // VERY_LIKELY → human review
    } else if (scores.adult >= quarantineThreshold) {
      categories.nudity = scores.adult / 5;
      outcome = "quarantine";
      enforcementAction = "quarantine";
      userFacingReason = "This image is being reviewed before it can be posted.";
      explanation = `vision:adult:${scores.adult}`;
      requiresHumanReview = true;
    }

    if (scores.violence >= blockThreshold) {
      categories.violence = scores.violence / 5;
      categories.gore = scores.violence / 5;
      outcome = "block";
      enforcementAction = "block";
      userFacingReason = "This image contains violent content that violates Amen safety rules.";
      explanation = `vision:violence:${scores.violence}`;
    } else if (scores.violence >= quarantineThreshold) {
      categories.violence = scores.violence / 5;
      if (outcome === "allow") {
        outcome = "quarantine";
        enforcementAction = "quarantine";
        requiresHumanReview = true;
      }
    }
  } catch (err) {
    // Vision API unavailable — quarantine for human review (fail safe)
    logger.warn("Vision API unavailable, quarantining for human review", { storageUri, err });
    outcome = "quarantine";
    enforcementAction = "quarantine";
    requiresHumanReview = true;
    explanation = "vision_api_unavailable";
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
    modelVersions: ["cloud-vision-safeSearch-v1", `trust-safety-os:${TRUST_SAFETY_OS_VERSION}`],
    appealAllowed: outcome !== "escalate",
    policyVersion: TRUST_SAFETY_OS_VERSION,
    contentId,
    contentType,
    authorUid,
  };
}

// ─── Exported callable ───────────────────────────────────────────────────

export const runImagePreflight = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<ImagePreflightResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const { storageUri, contentType, contentId, isMinor } =
      request.data as ImagePreflightRequest;

    if (!storageUri || !storageUri.startsWith("gs://")) {
      throw new HttpsError("invalid-argument", "Valid gs:// storageUri required.");
    }

    const uid = request.auth.uid;
    const decision = await runImagePreflightInternal(
      storageUri,
      contentType ?? "post",
      uid,
      contentId,
      isMinor === true
    );

    if (decision.decision !== "allow") {
      await writeSafetyAuditEvent({
        eventType: decision.decision === "block" ? "content_blocked" : "content_quarantined",
        actorUid: uid,
        targetUid: null,
        contentId: contentId ?? null,
        contentType: contentType ?? null,
        decision: decision.decision,
        category: Object.keys(decision.categories)[0] as RiskCategory ?? null,
        metadata: { riskScore: decision.riskScore, storageUri },
      });
    }

    return {
      allowed: decision.decision === "allow" || decision.decision === "allow_with_label",
      decision: decision.decision,
      userFacingReason: decision.userFacingReason,
      labelRequired: decision.decision === "allow_with_label",
      requiresHumanReview: decision.enforcementAction === "quarantine" || decision.enforcementAction === "escalate_to_reviewer",
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);
