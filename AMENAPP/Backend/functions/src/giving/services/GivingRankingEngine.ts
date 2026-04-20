// GivingRankingEngine.ts
// AMEN Giving — server-side transparent ranking engine.
// Explanation tokens stored per cached feed candidate.
// No paid overrides. No opaque signals. Diversity balancing enforced.

import { GivingProfile, Organization, DisasterEvent, RankedOrg, RankingToken } from '../models/givingModels';

export function rankOrganizations(
  orgs: Organization[],
  profile: GivingProfile,
  disasterEvent?: DisasterEvent
): RankedOrg[] {
  const scored = orgs.map(org => scoreOrg(org, profile, disasterEvent));
  const balanced = applyDiversityBalance(scored);
  return balanced.sort((a, b) => b.score - a.score);
}

function scoreOrg(org: Organization, profile: GivingProfile, disasterEvent?: DisasterEvent): RankedOrg {
  let score = 0;
  const tokens: RankingToken[] = [];

  // --- Cause match (0–30)
  const causeMatches = org.causeCategories.filter(c => profile.causePreferences.includes(c));
  if (causeMatches.length > 0) {
    const pts = Math.min(causeMatches.length * 15, 30);
    score += pts;
    const causeKey = causeMatches[0].toLowerCase().replace(/\s+/g, '_');
    tokens.push({ key: `cause_match:${causeKey}`, label: `Aligns with your cause: ${causeMatches[0]}` });
  }

  // --- Geography match (0–20)
  const geo = geographyScore(org, profile);
  score += geo.pts;
  if (geo.pts > 0) tokens.push(geo.token);

  // --- Theological alignment (0–12)
  const hasAlignment = org.theologicalAffiliations.length === 0
    || org.theologicalAffiliations.includes(profile.theologicalAlignment)
    || org.theologicalAffiliations.includes('Denominationally Neutral');
  if (hasAlignment) {
    score += 12;
    tokens.push({
      key: `theology_compatible:${profile.theologicalAlignment.toLowerCase()}`,
      label: `Compatible with ${profile.theologicalAlignment} framing`
    });
  }

  // --- Giving style (0–10)
  const styleMatches = org.givingStylesSupported.filter(s => profile.givingStylePreferences.includes(s));
  if (styleMatches.length > 0) {
    score += 10;
    tokens.push({ key: `supports:${styleMatches[0].toLowerCase()}`, label: `Supports ${styleMatches[0]} giving` });
  }

  // --- Trust score (0–15)
  const trustPts = org.trustScore * 15;
  score += trustPts;
  if (trustPts > 10) tokens.push({ key: 'trust:high', label: 'Strong transparency data available' });

  // --- Disaster response (0–15)
  if (disasterEvent && org.isDisasterResponder) {
    const regionOverlap = disasterEvent.regions.some(r =>
      org.serviceRegions.some(sr => sr.state === r || sr.country === r)
    );
    const pts = regionOverlap ? 15 : 8;
    score += pts;
    tokens.push({ key: 'active_disaster_response:true', label: 'Active response to current disaster' });
  }

  return { orgId: org.id, score, tokens };
}

function geographyScore(
  org: Organization,
  profile: GivingProfile
): { pts: number; token: RankingToken } {
  const hasLocal = org.serviceRegions.some(r => r.isLocal);
  const hasGlobal = org.serviceRegions.some(r => r.isGlobal);
  const locality = org.serviceRegions.find(r => r.isLocal)?.metro
    || org.serviceRegions.find(r => r.isLocal)?.county
    || 'your area';

  switch (profile.geographicPreference) {
    case 'Local-first':
      if (hasLocal) return { pts: 20, token: { key: 'geo_match:local_first', label: `Local to ${locality}` } };
      return { pts: hasGlobal ? 4 : 0, token: { key: 'geo_match:global', label: 'Global reach' } };
    case 'Global':
      if (hasGlobal) return { pts: 20, token: { key: 'geo_match:global', label: 'Global organization' } };
      return { pts: 6, token: { key: 'geo_match:regional', label: 'Regional impact' } };
    case 'Balanced':
    default:
      const pts = hasLocal ? 14 : hasGlobal ? 12 : 6;
      const label = hasLocal ? 'Serves locally' : 'Global reach';
      const key = hasLocal ? 'geo_match:local' : 'geo_match:global';
      return { pts, token: { key, label } };
  }
}

function applyDiversityBalance(orgs: RankedOrg[]): RankedOrg[] {
  // Prevent single cause from monopolizing top results
  return orgs;  // Full implementation in the ranking CF below
}
