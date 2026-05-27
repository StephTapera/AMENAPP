/**
 * rankingSafety.ts — Amen Trust + Safety OS
 *
 * Callable: computeRankingScore
 * Callable: markContentTrendIneligible
 *
 * Replaces engagement-first ranking with safety-first, usefulness-first ranking.
 *
 * Scores:
 *   + safetyScore, provenanceScore, usefulnessScore, originalityScore
 *   + relationshipRelevance, communityHealthScore, spiritualHelpfulness
 *   + localRelevance, userIntentMatch, freshness, diversity, wellnessImpact
 *
 * Penalties:
 *   - outrage, fearBait, engagementFarming, trauma monetization
 *   - botEngagementFraction, syntheticVirality, sourceUncertainty
 *   - massReposting, manipulativeCTAs
 *
 * Public vanity metrics hidden by default. Trends require trust + provenance.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import {
  RankingSignals,
  RankingDecision,
  TRUST_SAFETY_OS_VERSION,
} from "./safetyTypes";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// ─── Types ───────────────────────────────────────────────────────────────

export interface RankingRequest {
  contentId: string;
  authorUid: string;
  contentType: string;
  rawEngagement?: {
    likes?: number;
    comments?: number;
    reposts?: number;
    views?: number;
  };
  authorTrustScore?: number;    // 0–100 from identity trust
  botEngagementFraction?: number;  // 0–1, fraction of engagement from bots
  provenanceStatus?: string;
  aiGeneratedStatus?: string;
  communityHealthSignals?: {
    hasHighConflict?: boolean;
    hasSpiritualValue?: boolean;
    isLocalRelevant?: boolean;
  };
  ageSeconds?: number;
}

export interface RankingResponse {
  contentId: string;
  finalScore: number;
  trendEligible: boolean;
  boostEligible: boolean;
  suppressedReason: string | null;
  policyVersion: string;
}

// ─── Penalty patterns ─────────────────────────────────────────────────────

const OUTRAGE_PATTERNS = [
  /\b(you\s*need\s*to\s*be\s*angry|this\s*is\s*outrageous|why\s*aren.t\s*you\s*mad)\b/i,
  /\b(share\s*before\s*it.s\s*deleted|they\s*don.t\s*want\s*you\s*to\s*know)\b/i,
  /\b(\\d+\s*people\s*(died|killed)\s*and\s*nobody\s*cares)\b/i,
];

const FEAR_BAIT_PATTERNS = [
  /\b(end\s*times?|mark\s*of\s*the\s*beast|rapture\s*is\s*here)\b/i,
  /\b(government\s*is\s*coming\s*for\s*(your|our)\s*(guns?|kids?|church))\b/i,
];

const ENGAGEMENT_FARM_PATTERNS = [
  /\b(like\s*if\s*you\s*(agree|believe|love\s*god|love\s*jesus))\b/i,
  /\b(comment\s*amen\s*if|type\s*amen\s*to)\b/i,
  /\b(share\s*this\s*(100|1000)\s*times)\b/i,
];

function detectPenaltySignals(text?: string): {
  outrageSignal: number;
  fearBaitSignal: number;
  engagementFarmingSignal: number;
} {
  if (!text) return { outrageSignal: 0, fearBaitSignal: 0, engagementFarmingSignal: 0 };
  return {
    outrageSignal: OUTRAGE_PATTERNS.some((p) => p.test(text)) ? 0.6 : 0,
    fearBaitSignal: FEAR_BAIT_PATTERNS.some((p) => p.test(text)) ? 0.5 : 0,
    engagementFarmingSignal: ENGAGEMENT_FARM_PATTERNS.some((p) => p.test(text)) ? 0.7 : 0,
  };
}

// ─── Score computation ────────────────────────────────────────────────────

function computeScore(signals: RankingSignals): number {
  const positive = (
    signals.safetyScore * 0.20 +
    signals.provenanceScore * 0.15 +
    signals.usefulnessScore * 0.15 +
    signals.originalityScore * 0.10 +
    signals.communityHealthScore * 0.10 +
    signals.spiritualHelpfulnessScore * 0.10 +
    signals.relationshipRelevance * 0.08 +
    signals.userIntentMatch * 0.05 +
    signals.freshness * 0.04 +
    signals.wellnessImpact * 0.03
  );

  const penalties = (
    signals.outrageSignal * 0.20 +
    signals.fearBaitSignal * 0.15 +
    signals.engagementFarmingSignal * 0.20 +
    signals.botEngagementFraction * 0.30 +
    signals.syntheticViralitySignal * 0.25
  );

  return Math.max(0, Math.min(1, positive - penalties));
}

function isTrendEligible(signals: RankingSignals, provenanceStatus: string): boolean {
  if (provenanceStatus === "source_uncertain" || provenanceStatus === "unknown") return false;
  if (signals.botEngagementFraction > 0.2) return false;
  if (signals.syntheticViralitySignal > 0.5) return false;
  if (signals.safetyScore < 0.6) return false;
  return true;
}

// ─── Exported callable ───────────────────────────────────────────────────

export const computeRankingScore = onCall(
  { enforceAppCheck: true, cors: false },
  async (request): Promise<RankingResponse> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");

    const data = request.data as RankingRequest;
    if (!data.contentId) throw new HttpsError("invalid-argument", "contentId required.");

    const communityHealth = data.communityHealthSignals ?? {};
    const botFraction = Math.min(data.botEngagementFraction ?? 0, 1.0);
    const authorTrust = (data.authorTrustScore ?? 50) / 100;
    const provenanceStatus = data.provenanceStatus ?? "unknown";

    const provenanceScore = provenanceStatus === "original" ? 1.0
      : provenanceStatus === "verified_source" ? 1.0
      : provenanceStatus === "edited" ? 0.7
      : provenanceStatus === "ai_assisted" ? 0.5
      : provenanceStatus === "ai_generated" ? 0.4
      : provenanceStatus === "reposted" ? 0.3
      : 0.1; // source_uncertain / unknown

    const freshnessDays = Math.max(0, (data.ageSeconds ?? 0) / 86400);
    const freshness = Math.max(0, 1 - freshnessDays / 7);

    const { outrageSignal, fearBaitSignal, engagementFarmingSignal } = detectPenaltySignals();

    const signals: RankingSignals = {
      safetyScore: authorTrust,
      provenanceScore,
      usefulnessScore: communityHealth.hasSpiritualValue ? 0.8 : 0.5,
      originalityScore: provenanceStatus === "original" ? 0.9 : 0.4,
      relationshipRelevance: 0.5,
      communityHealthScore: communityHealth.hasHighConflict ? 0.2 : 0.7,
      spiritualHelpfulnessScore: communityHealth.hasSpiritualValue ? 0.8 : 0.4,
      localRelevance: communityHealth.isLocalRelevant ? 0.7 : 0.3,
      userIntentMatch: 0.5,
      freshness,
      diversity: 0.5,
      wellnessImpact: communityHealth.hasHighConflict ? -0.2 : 0.3,
      outrageSignal,
      fearBaitSignal,
      engagementFarmingSignal,
      botEngagementFraction: botFraction,
      syntheticViralitySignal: botFraction > 0.3 ? 0.8 : 0,
    };

    const finalScore = computeScore(signals);
    const trendEligible = isTrendEligible(signals, provenanceStatus);
    const boostEligible = finalScore > 0.6 && botFraction < 0.1;
    const suppressedReason = botFraction > 0.4
      ? "High bot engagement detected"
      : signals.syntheticViralitySignal > 0.5
      ? "Suspected synthetic virality"
      : null;

    const decision: RankingDecision = {
      contentId: data.contentId,
      finalScore,
      signals,
      trendEligible,
      boostEligible,
      suppressedReason,
      createdAt: admin.firestore.Timestamp.now(),
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };

    await db.doc(`posts/${data.contentId}/ranking/main`).set(decision);

    return {
      contentId: data.contentId,
      finalScore,
      trendEligible,
      boostEligible,
      suppressedReason,
      policyVersion: TRUST_SAFETY_OS_VERSION,
    };
  }
);

// ─── Mark trend ineligible (admin) ───────────────────────────────────────

export const markContentTrendIneligible = onCall(
  { enforceAppCheck: true, cors: false },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required.");
    if (!request.auth.token.admin && !request.auth.token.moderator) {
      throw new HttpsError("permission-denied", "Moderator role required.");
    }
    const { contentId, reason } = request.data as { contentId: string; reason: string };
    await db.doc(`posts/${contentId}/ranking/main`).set(
      { trendEligible: false, boostEligible: false, suppressedReason: reason ?? "manually_suppressed",
        updatedAt: admin.firestore.Timestamp.now() },
      { merge: true }
    );
    return { success: true };
  }
);
