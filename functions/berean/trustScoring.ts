/**
 * berean/trustScoring.ts — Trust Scoring Layer (Layer 5b)
 * Berean Trust Architecture · Layer 5b · Version: v1
 *
 * Responsibilities:
 *   1. Compute a detailed TrustScoreBreakdown from retrieval + verification results
 *   2. Provide a human-readable label bucketed into four tiers
 *   3. Persist the breakdown to Firestore "bereanTrustScores/{traceId}"
 *
 * The constitutionalPipeline.ts computes a single scalar trustScore; this module
 * provides the per-component breakdown that powers the trust UI badge and audit trail.
 */

import * as FirebaseFirestore from "firebase-admin/firestore";
import { RetrievedChunk } from "./evidenceRetrieval";
import { ConstitutionalReviewResult } from "./bereanConstitution";

// ── TYPES ─────────────────────────────────────────────────────────────────────

/**
 * A detailed breakdown of every factor that contributes to the trust score.
 * All component values are in the range 0.0–1.0 before summation.
 * totalScore is capped to [0.0, 1.0].
 */
export interface TrustScoreBreakdown {
  /** 0.0–0.25: quality signal derived from number of retrieved chunks. */
  retrievalQuality: number;
  /** 0.0–0.20: highest source-type weight among retrieved chunks. */
  sourceQuality: number;
  /** 0.0–0.25: maps constitutional-review confidence to a numeric reward. */
  confidenceLevel: number;
  /** 0.0–0.20: reward for verification outcome (pass/degraded/fail). */
  verificationOutcome: number;
  /** 0.0 or negative: penalty applied for each retry attempt. */
  hallucinationRisk: number;
  /** 0.0–0.10: base completeness reward, boosted by chunk count up to cap. */
  contextCompleteness: number;
  /** Sum of all components, clamped to [0.0, 1.0]. */
  totalScore: number;
  /** Human-readable sentence summarising why this score was assigned. */
  explanation: string;
}

/** Tier labels presented in the trust UI badge. */
export type TrustLabel =
  | "Verified"
  | "Mostly Verified"
  | "Partially Verified"
  | "Unverified";

// ── CONSTANTS ─────────────────────────────────────────────────────────────────

const SOURCE_TYPE_WEIGHTS: Record<RetrievedChunk["source"], number> = {
  scripture: 0.20,
  theology: 0.15,
  church: 0.10,
  userData: 0.08,
  platform: 0.05,
};

const CONFIDENCE_WEIGHTS: Record<string, number> = {
  High: 0.25,
  Moderate: 0.15,
  Low: 0.08,
  Unknown: 0.0,
};

const VERIFICATION_WEIGHTS: Record<
  ConstitutionalReviewResult["overallVerdict"],
  number
> = {
  pass: 0.20,
  degraded: 0.10,
  fail: 0.0,
};

// ── HELPERS ───────────────────────────────────────────────────────────────────

/** Clamp a number into the inclusive range [min, max]. */
function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

/**
 * Describe the best source type found in the chunk set for use in the
 * explanation string.
 */
function bestSourceLabel(chunks: RetrievedChunk[]): string {
  const order: RetrievedChunk["source"][] = [
    "scripture",
    "theology",
    "church",
    "userData",
    "platform",
  ];
  for (const src of order) {
    if (chunks.some((c) => c.source === src)) return src;
  }
  return "no";
}

// ── CORE EXPORT: computeTrustScore ────────────────────────────────────────────

/**
 * Compute a TrustScoreBreakdown for a single pipeline trace.
 *
 * @param params.chunks             Retrieved evidence chunks for this trace.
 * @param params.verificationResult Constitutional review result for this trace.
 * @param params.retryCount         Number of generation retries that occurred.
 * @param params.intentClasses      Intent classes resolved for the query.
 */
export function computeTrustScore(params: {
  chunks: RetrievedChunk[];
  verificationResult: ConstitutionalReviewResult;
  retryCount: number;
  intentClasses: string[];
}): TrustScoreBreakdown {
  const { chunks, verificationResult, retryCount } = params;
  const chunkCount = chunks.length;

  // ── 1. Retrieval quality (0.0–0.25) ─────────────────────────────────────────
  let retrievalQuality: number;
  if (chunkCount === 0) {
    retrievalQuality = 0.0;
  } else if (chunkCount <= 3) {
    retrievalQuality = 0.10;
  } else if (chunkCount <= 7) {
    retrievalQuality = 0.18;
  } else {
    retrievalQuality = 0.25;
  }

  // ── 2. Source quality (0.0–0.20) ────────────────────────────────────────────
  // Use the highest-weight source type present in the chunk set.
  let sourceQuality = 0.0;
  for (const chunk of chunks) {
    const w = SOURCE_TYPE_WEIGHTS[chunk.source] ?? 0.0;
    if (w > sourceQuality) sourceQuality = w;
  }

  // ── 3. Confidence level (0.0–0.25) ──────────────────────────────────────────
  // verificationResult.confidence may be a ConfidenceLevel string or an
  // arbitrary string; fall back to 0.0 for unrecognised values.
  const confidenceKey = verificationResult.confidence ?? "Unknown";
  const confidenceLevel: number = CONFIDENCE_WEIGHTS[confidenceKey] ?? 0.0;

  // ── 4. Verification outcome (0.0–0.20) ──────────────────────────────────────
  const verificationOutcome: number =
    VERIFICATION_WEIGHTS[verificationResult.overallVerdict] ?? 0.0;

  // ── 5. Hallucination risk (penalty, ≤ 0) ────────────────────────────────────
  // -0.10 per retry, floor at 0 to avoid going below zero before summation.
  const hallucinationRisk: number = -Math.min(retryCount * 0.10, 1.0);

  // ── 6. Context completeness (0.0–0.10) ──────────────────────────────────────
  // 0.10 base + 0.01 per chunk, capped at 0.10 total.
  const contextCompleteness: number = clamp(0.10 + chunkCount * 0.01, 0.0, 0.10);

  // ── 7. Total (clamped to [0.0, 1.0]) ────────────────────────────────────────
  const rawTotal =
    retrievalQuality +
    sourceQuality +
    confidenceLevel +
    verificationOutcome +
    hallucinationRisk +
    contextCompleteness;

  const totalScore = clamp(rawTotal, 0.0, 1.0);

  // ── 8. Explanation ───────────────────────────────────────────────────────────
  const sourceName = bestSourceLabel(chunks);
  const verdictText =
    verificationResult.overallVerdict === "pass"
      ? "verified"
      : verificationResult.overallVerdict === "degraded"
      ? "partially verified"
      : "not verified";
  const retryNote =
    retryCount > 0
      ? ` ${retryCount} retry${retryCount > 1 ? "ies" : ""} reduced the score by ${Math.abs(hallucinationRisk).toFixed(2)}.`
      : "";

  const explanation =
    `Confidence is ${confidenceKey} because ${sourceName} source${
      chunkCount !== 1 ? "s were" : " was"
    } retrieved and ${verdictText} against ${chunkCount} chunk${
      chunkCount !== 1 ? "s" : ""
    }.${retryNote} Total score: ${totalScore.toFixed(2)} (${trustScoreToLabel(totalScore)}).`;

  return {
    retrievalQuality,
    sourceQuality,
    confidenceLevel,
    verificationOutcome,
    hallucinationRisk,
    contextCompleteness,
    totalScore,
    explanation,
  };
}

// ── CORE EXPORT: trustScoreToLabel ────────────────────────────────────────────

/**
 * Map a scalar trust score to a four-tier label for UI display.
 *
 * @param score A number in [0.0, 1.0].
 */
export function trustScoreToLabel(score: number): TrustLabel {
  if (score >= 0.8) return "Verified";
  if (score >= 0.6) return "Mostly Verified";
  if (score >= 0.4) return "Partially Verified";
  return "Unverified";
}

// ── CORE EXPORT: saveTrustScore ───────────────────────────────────────────────

/**
 * Persist a TrustScoreBreakdown to Firestore at "bereanTrustScores/{traceId}".
 *
 * Merges into any pre-existing document so a re-score does not erase prior
 * fields written by other pipeline stages.
 *
 * @param traceId  The pipeline trace identifier (matches the pipeline trace doc).
 * @param score    The breakdown produced by computeTrustScore.
 * @param db       Firestore instance (passed in to keep this module testable).
 */
export async function saveTrustScore(
  traceId: string,
  score: TrustScoreBreakdown,
  db: FirebaseFirestore.Firestore,
): Promise<void> {
  await db
    .collection("bereanTrustScores")
    .doc(traceId)
    .set(
      {
        ...score,
        label: trustScoreToLabel(score.totalScore),
        updatedAt: FirebaseFirestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}
