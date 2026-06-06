/**
 * rankingEngine.ts
 *
 * Ranking Brain for AMEN Living Intelligence.
 * Computes rankScore (0–100) and rankReasons[] for each IntelligenceCard
 * relative to the caller's UserContext.
 *
 * Score formula:
 *   rankScore = actionability(0–30) + proximity(0–25) + formationValue(0–25)
 *             + seasonMatch(0–10)   + liturgicalRelevance(0–10)
 *
 * Boosts applied after base:
 *   +10  church involvement match
 *   +8   liturgical relevance
 *   +7   season-of-life match
 *   +5   capacity signal = "free"
 *
 * Demotions applied after boosts:
 *   -20  DEVELOPING truth level
 *   -15  novelty-only card (matchScore<15 + no loop parent)
 *   -10  refresh-bait detection (very new card, low formation value)
 */

import { IntelligenceCard, TruthLevel } from "./contracts";

// ─── UserContext ───────────────────────────────────────────────────────────────

export interface UserContext {
  uid: string;
  coarseGeo?: { lat: number; lng: number };
  followedChurchIds: string[];
  seasonOfLife?: string; // "parent" | "student" | "single" | "married" | ...
  liturgicalCalendarData?: {
    currentSeason: string;     // "Advent" | "Lent" | "Ordinary Time" | ...
    upcomingFeast?: string;
  };
  capacitySignal?: "free" | "busy" | "unknown";
  actedOnCardIds: string[]; // cards the user has already acted on (loop-closing)
}

// ─── Scoring components ────────────────────────────────────────────────────────

/** 0–30: Does the card have wired, actionable next steps? */
function scoreActionability(card: IntelligenceCard): number {
  if (!card.actions || card.actions.length === 0) return 0;

  // High-actionability rungs
  const highRungs = new Set(["RSVP", "GIVE", "SHOW_UP", "START", "VOLUNTEER"]);
  const midRungs = new Set(["DISCUSS", "LEARN", "PRAY"]);

  let score = 0;
  for (const action of card.actions) {
    if (highRungs.has(action.rung)) {
      score += 10;
    } else if (midRungs.has(action.rung)) {
      score += 6;
    } else {
      score += 3; // NOTICE
    }
  }

  // Bonus for multiple diverse rungs
  const uniqueRungs = new Set(card.actions.map((a) => a.rung));
  if (uniqueRungs.size >= 3) score += 5;

  return Math.min(30, score);
}

/**
 * 0–25: How geographically close is this opportunity to the user?
 * Uses coarse Haversine distance (kilometers). No precise coordinates stored.
 */
function scoreProximity(card: IntelligenceCard, ctx: UserContext): number {
  if (!card.geo || !ctx.coarseGeo) return 5; // No geo data — neutral score

  const distKm = haversineKm(
    ctx.coarseGeo.lat,
    ctx.coarseGeo.lng,
    card.geo.lat,
    card.geo.lng
  );

  if (distKm <= 5) return 25;
  if (distKm <= 15) return 20;
  if (distKm <= 30) return 15;
  if (distKm <= 60) return 10;
  if (distKm <= 120) return 5;
  return 2; // Distant but still surfaces as low-priority local
}

/**
 * 0–25: Formation value — does this card support spiritual growth?
 * Based on tier, truth level, and whether the card has scripture/study backing.
 */
function scoreFormationValue(card: IntelligenceCard): number {
  let score = 0;

  // Tier scoring
  const tierScores: Record<string, number> = {
    SPIRITUAL: 20,
    FAMILY: 16,
    COMMUNITY: 14,
    LOCAL: 10,
    GLOBAL: 8,
  };
  score += tierScores[card.tier] ?? 8;

  // Truth level modifier
  const VERIFIED: TruthLevel = "VERIFIED";
  const CHURCH_CONFIRMED: TruthLevel = "CHURCH_CONFIRMED";
  if (card.truthLevel === VERIFIED) score += 5;
  else if (card.truthLevel === CHURCH_CONFIRMED) score += 3;

  // Summary bullets mean Berean found real formation content
  const bulletCount = card.summary?.length ?? 0;
  score += Math.min(bulletCount, 3);

  return Math.min(25, score);
}

/**
 * 0–10: Does this card match the user's season of life?
 */
function scoreSeasonMatch(card: IntelligenceCard, ctx: UserContext): number {
  if (!ctx.seasonOfLife) return 0;

  const season = ctx.seasonOfLife.toLowerCase();
  const text = `${card.title} ${card.summary?.join(" ") ?? ""}`.toLowerCase();

  const seasonKeywords: Record<string, string[]> = {
    parent: ["parent", "family", "children", "kids", "youth", "school"],
    student: ["student", "college", "campus", "youth", "young adult", "university"],
    single: ["single", "young adult", "community", "fellowship", "dating"],
    married: ["marriage", "married", "couple", "family", "spouse"],
    senior: ["senior", "elder", "wisdom", "legacy", "grandparent"],
    widowed: ["grief", "loss", "healing", "comfort", "widow", "bereaved"],
  };

  const keywords = seasonKeywords[season] ?? [];
  const matchCount = keywords.filter((kw) => text.includes(kw)).length;

  if (matchCount >= 3) return 10;
  if (matchCount >= 2) return 7;
  if (matchCount >= 1) return 4;
  return 0;
}

/**
 * 0–10: Does this card align with the current liturgical season?
 */
function scoreLiturgicalRelevance(
  card: IntelligenceCard,
  ctx: UserContext
): number {
  if (!ctx.liturgicalCalendarData) return 0;

  const { currentSeason, upcomingFeast } = ctx.liturgicalCalendarData;
  const text = `${card.title} ${card.summary?.join(" ") ?? ""}`.toLowerCase();
  const season = currentSeason.toLowerCase();

  let score = 0;

  // Direct season match
  if (text.includes(season)) score += 6;

  // Upcoming feast relevance
  if (upcomingFeast) {
    const feast = upcomingFeast.toLowerCase();
    if (text.includes(feast)) score += 8;
  }

  // Seasonal spiritual action words
  const seasonalTerms: Record<string, string[]> = {
    advent: ["prepare", "wait", "hope", "coming", "anticipate"],
    lent: ["fast", "repent", "sacrifice", "ash", "prayer", "discipline"],
    easter: ["resurrection", "risen", "alleluia", "new life", "victory"],
    pentecost: ["spirit", "fire", "mission", "witness", "apostle"],
    "ordinary time": ["discipleship", "growth", "formation", "everyday"],
    christmas: ["incarnation", "birth", "nativity", "emmanuel"],
  };

  const seasonTermList = seasonalTerms[season] ?? [];
  const termMatches = seasonTermList.filter((t) => text.includes(t)).length;
  score += Math.min(termMatches * 2, 4);

  return Math.min(10, score);
}

// ─── Boost & demote helpers ────────────────────────────────────────────────────

function applyBoosts(
  baseScore: number,
  card: IntelligenceCard,
  ctx: UserContext,
  reasons: string[]
): number {
  let score = baseScore;

  // +10: church involvement match
  const churchMatch = card.backingEntity?.kind === "CHURCH" &&
    ctx.followedChurchIds.includes(card.backingEntity.id);
  if (churchMatch) {
    score += 10;
    reasons.push("Your church is hosting this");
  }

  // +8: liturgical relevance (only if liturgicalRelevance score > 0)
  if (ctx.liturgicalCalendarData) {
    const litScore = scoreLiturgicalRelevance(card, ctx);
    if (litScore >= 6) {
      score += 8;
      reasons.push(`Relevant to ${ctx.liturgicalCalendarData.currentSeason} season`);
    }
  }

  // +7: season-of-life match
  const seasonScore = scoreSeasonMatch(card, ctx);
  if (seasonScore >= 7) {
    score += 7;
    reasons.push(`Relevant to your season of life`);
  }

  // +5: capacity free
  if (ctx.capacitySignal === "free") {
    score += 5;
    reasons.push("Good time to engage");
  }

  return score;
}

function applyDemotions(
  score: number,
  card: IntelligenceCard,
  reasons: string[]
): number {
  let s = score;

  // -20: DEVELOPING truth level
  if (card.truthLevel === "DEVELOPING") {
    s -= 20;
    reasons.push("Story still developing — low confidence");
  }

  // -15: novelty-only (very low matchScore + no loop parent)
  const hasLoopParent = Boolean(card.formation?.loopParentId);
  const isNoveltyOnly = (card.matchScore ?? 50) < 15 && !hasLoopParent;
  if (isNoveltyOnly) {
    s -= 15;
    // No user-facing reason — this is a ranking demotion only
  }

  // -10: refresh-bait (card is very new AND has low formation value)
  const ageMs = Date.now() - card.createdAt;
  const isVeryNew = ageMs < 5 * 60 * 1000; // < 5 minutes old
  const formationScore = scoreFormationValue(card);
  if (isVeryNew && formationScore < 10) {
    s -= 10;
    // No user-facing reason — prevents engagement-baiting on fresh cards
  }

  return s;
}

// ─── Main ranking function ─────────────────────────────────────────────────────

export interface RankedCard {
  card: IntelligenceCard;
  rankScore: number;
  rankReasons: string[];
}

/**
 * Rank a single IntelligenceCard against the user's context.
 * Returns a new card object with rankScore and rankReasons populated.
 */
export function rankCard(card: IntelligenceCard, ctx: UserContext): RankedCard {
  const reasons: string[] = [];

  // Base components
  const actionability = scoreActionability(card);
  const proximity = scoreProximity(card, ctx);
  const formationValue = scoreFormationValue(card);
  const seasonMatch = scoreSeasonMatch(card, ctx);
  const liturgicalRelevance = scoreLiturgicalRelevance(card, ctx);

  let base = actionability + proximity + formationValue + seasonMatch + liturgicalRelevance;

  // Build reasons from component scores
  if (proximity >= 20 && ctx.coarseGeo) reasons.push("Near you");
  if (actionability >= 20) reasons.push("Clear next step available");
  if (formationValue >= 18) reasons.push("High spiritual formation value");
  if (liturgicalRelevance >= 6 && ctx.liturgicalCalendarData) {
    reasons.push(`Matches ${ctx.liturgicalCalendarData.currentSeason} season`);
  }
  if (seasonMatch >= 4 && ctx.seasonOfLife) {
    reasons.push(`Relevant to your season of life`);
  }

  // Carry forward existing matchReasons if present
  if (card.matchReasons) {
    for (const r of card.matchReasons) {
      if (!reasons.includes(r)) reasons.push(r);
    }
  }

  // Loop-closing signal
  if (card.formation?.loopParentId && ctx.actedOnCardIds.includes(card.formation.loopParentId)) {
    base += 5;
    reasons.push("Follows up on something you started");
  }

  // Boosts & demotions
  base = applyBoosts(base, card, ctx, reasons);
  base = applyDemotions(base, card, reasons);

  // Clamp to 0–100
  const rankScore = Math.max(0, Math.min(100, Math.round(base)));

  // Always populate at least one reason
  if (reasons.length === 0) {
    reasons.push("Surfaced based on your community activity");
  }

  return {
    card: {
      ...card,
      rankScore,
      rankReasons: reasons,
    },
    rankScore,
    rankReasons: reasons,
  };
}

/**
 * Rank and sort a list of cards for a user.
 * Returns cards sorted descending by rankScore, with rankScore and rankReasons set.
 */
export function rankCards(
  cards: IntelligenceCard[],
  ctx: UserContext
): IntelligenceCard[] {
  return cards
    .map((card) => rankCard(card, ctx))
    .sort((a, b) => b.rankScore - a.rankScore)
    .map((r) => r.card);
}

// ─── Geo helper ───────────────────────────────────────────────────────────────

/** Approximate Haversine distance in kilometers. Coarse inputs only. */
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371; // Earth radius in km
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}
