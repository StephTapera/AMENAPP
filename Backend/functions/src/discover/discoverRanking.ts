import { DiscoverMetadata } from "./discoverTypes";

export function rankScore(meta: DiscoverMetadata): number {
  const relevanceScore = meta.qualityScore;
  const spiritualUsefulnessScore = meta.spiritualUsefulnessScore;
  const safetyScore = meta.safetyScore;
  const originalityScore = meta.originalityScore;
  const localFitScore = meta.localFitScore ?? 0;
  const freshnessScore = meta.freshnessScore ?? 0;
  const creatorTrustScore = meta.creatorTrustScore;
  const intentMatchScore = meta.intentMatchScore ?? 0;

  const repetitionPenalty = meta.repetitionPenalty ?? 0;
  const sensationalismPenalty = meta.sensationalismPenalty ?? 0;
  const unresolvedModerationPenalty = meta.unresolvedModerationPenalty ?? 0;
  const lowTrustAIPenalty = meta.lowTrustAIPenalty ?? 0;

  return (
    relevanceScore * 0.24 +
    spiritualUsefulnessScore * 0.22 +
    safetyScore * 0.18 +
    originalityScore * 0.12 +
    localFitScore * 0.08 +
    freshnessScore * 0.06 +
    creatorTrustScore * 0.05 +
    intentMatchScore * 0.05 -
    repetitionPenalty -
    sensationalismPenalty -
    unresolvedModerationPenalty -
    lowTrustAIPenalty
  );
}
