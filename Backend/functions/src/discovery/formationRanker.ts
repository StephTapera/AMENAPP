// formationRanker.ts
// Formation-weighted ranking — no engagement optimization.
// FORMATION_WEIGHTS is the authoritative source; engagement is explicitly excluded.

import {
  Candidate,
  CandidateFeatures,
  DiscoveryCardType,
  FORMATION_WEIGHTS,
} from "./contracts";

// ── Formation score ─────────────────────────────────────────────────

export function computeFormationScore(features: CandidateFeatures): number {
  const {
    relevanceScore,
    freshnessScore,
    friendAffinityScore,
    localProximityScore,
    scriptureContinuityScore,
  } = features;

  const w = FORMATION_WEIGHTS;
  return (
    relevanceScore           * w.relevance +
    freshnessScore           * w.freshness +
    friendAffinityScore      * w.friendAffinity +
    localProximityScore      * w.localProximity +
    scriptureContinuityScore * w.scriptureContinuity
  );
}

// ── Freshness decay (exponential half-life 72h) ─────────────────────

export function freshnessScore(createdAtMs: number): number {
  const ageHours = (Date.now() - createdAtMs) / 3_600_000;
  return Math.exp(-0.01 * ageHours);   // half-life ~70h
}

// ── MMR-style diversification ───────────────────────────────────────

const MAX_PER_TYPE: Partial<Record<DiscoveryCardType, number>> = {
  bibleStudy: 3,
  prayerRoom: 3,
  church:     4,
  event:      3,
  discussion: 5,
  space:      4,
  audioRoom:  3,
};

export function diversifyAndRank(candidates: Candidate[]): Candidate[] {
  const scored = candidates
    .map((c) => ({
      ...c,
      features: {
        ...c.features,
        formationScore: computeFormationScore(c.features),
      },
    }))
    .sort((a, b) => (b.features.formationScore ?? 0) - (a.features.formationScore ?? 0));

  const typeCounts: Partial<Record<DiscoveryCardType, number>> = {};
  const result: Candidate[] = [];

  for (const candidate of scored) {
    const cap = MAX_PER_TYPE[candidate.type] ?? 6;
    const count = typeCounts[candidate.type] ?? 0;
    if (count < cap) {
      result.push(candidate);
      typeCounts[candidate.type] = count + 1;
    }
  }

  return result;
}

// ── Dedup by id ─────────────────────────────────────────────────────

export function dedup(candidates: Candidate[]): Candidate[] {
  const seen = new Set<string>();
  return candidates.filter((c) => {
    if (seen.has(c.id)) return false;
    seen.add(c.id);
    return true;
  });
}
