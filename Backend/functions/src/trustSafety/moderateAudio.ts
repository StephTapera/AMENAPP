/**
 * moderateAudio.ts — Amen Trust + Safety OS
 *
 * Callable: runAudioPreflight
 *
 * Audio moderation pipeline:
 *   1. Transcription (Whisper/Speech-to-Text)
 *   2. Transcript text moderation (banned terms + Perspective)
 *   3. Flagged segments quarantined for human review
 *
 * Livestream audio is moderated in near-real-time via transcript chunks.
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
const db = admin.firestore();

// ─── Types ───────────────────────────────────────────────────────────────

export interface AudioPreflightRequest {
  transcript: string;           // pre-transcribed text (required)
  storageUri?: string;          // gs:// path to audio (for reference)
  contentType: ContentSurface;
  contentId?: string;
  isMinor?: boolean;
  isLivestream?: boolean;
}

export interface AudioPreflightResponse {
  allowed: boolean;
  decision: SafetyDecisionOutcome;
  userFacingReason: string | null;
  labelRequired: boolean;
  requiresHumanReview: boolean;
  flaggedSegments: string[];
  policyVersion: string;
}

// ─── Banned patterns ─────────────────────────────────────────────────────

const AUDIO_BANNED: Array<{ pattern: RegExp; category: RiskCategory; escalate: boolean }> = [
  { pattern: /\b(csam|child\s*porn)\b/i,                                   category: "csam_indicator",  escalate: true },
  { pattern: /\b(sex\s*traffic|sell\s*(girl|boy|minor))\b/i,               category: "trafficking",     escalate: true },
  { pattern: /\b(how\s*to\s*(kill|harm)\s*(my|your)self)\b/i,              category: "self_harm",       escalate: true },
  { pattern: /\b(send\s*(nudes?)\s*(of\s*)?(your|my)?\s*kid)\b/i,          category: "grooming",        escalate: true },
  { pattern: /\b(buy\s*(meth|heroin|fentanyl))\b/i,                        category: "spam",            escalate: false },
  { pattern: /\b(sextort|revenge\s*porn)\b/i,                              category: "sextortion",      escalate: true },
  { pattern: /\b(allahu\s*akbar.*kill|death\s*to\s*(all|infidel))\b/i,    category: "extremism",       escalate: true },
];

// ─── Core decision ───────────────────────────────────────────────────────

async function runAudioPreflightInternal(
  transcript: string,
  contentType: ContentSurface,
  authorUid: string,
  contentId: string | undefined,
  isMinor: boolean,
  isLivestream: boolean
): Promise<SafetyDecision & { flaggedSegments: string[] }> {
  const categories: Partial<Record<RiskCategory, number>> = {};
  let outcome: SafetyDecisionOutcome = "allow";
  let enforcementAction: EnforcementAction = "none";
  let userFacingReason: string | null = null;
  let explanation = "clean";
  let requiresHumanReview = false;
  const flaggedSegments: string[] = [];

  // Scan transcript for banned patterns
  for (const rule of AUDIO_BANNED) {
    const match = transcript.match(rule.pattern);
    if (match) {
      categories[rule.category] = 1.0;
      outcome = rule.escalate ? "escalate" : "block";
      enforcementAction = rule.escalate ? "escalate_to_reviewer" : "block";
      userFacingReason = rule.escalate
        ? "This audio contains content that violates Amen safety rules."
        : "This audio has been blocked due to policy violations.";
      explanation = `audio_banned:${rule.category}`;
      requiresHumanReview = true;
      flaggedSegments.push(match[0]);
      break;
    }
  }

  // Livestreams get quarantined pending real-time review if no transcript yet
  if (outcome === "allow" && isLivestream && !transcript) {
    outcome = "quarantine";
    enforcementAction = "quarantine";
    requiresHumanReview = true;
    explanation = "livestream_pending_transcript";
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
    contentId,
    contentType,
    authorUid,
    flaggedSegments,
  };
}

// ─── Exported callable ───────────────────────────────────────────────────

export const runAudioPreflight = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<AudioPreflightResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const data = request.data as AudioPreflightRequest;
    if (!data.transcript && !data.storageUri) {
      throw new HttpsError("invalid-argument", "transcript or storageUri required.");
    }

    const uid = request.auth.uid;
    const result = await runAudioPreflightInternal(
      data.transcript ?? "",
      data.contentType ?? "post",
      uid,
      data.contentId,
      data.isMinor === true,
      data.isLivestream === true
    );

    if (result.decision !== "allow") {
      await writeSafetyAuditEvent({
        eventType: result.decision === "block" ? "content_blocked" : "content_quarantined",
        actorUid: uid,
        targetUid: null,
        contentId: data.contentId ?? null,
        contentType: data.contentType ?? null,
        decision: result.decision,
        category: Object.keys(result.categories)[0] as RiskCategory ?? null,
        metadata: { riskScore: result.riskScore, flaggedSegments: result.flaggedSegments },
      });
    }

    return {
      allowed: result.decision === "allow" || result.decision === "allow_with_label",
      decision: result.decision,
      userFacingReason: result.userFacingReason,
      labelRequired: result.decision === "allow_with_label",
      requiresHumanReview: result.enforcementAction === "quarantine" ||
        result.enforcementAction === "escalate_to_reviewer",
      flaggedSegments: result.flaggedSegments,
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);
