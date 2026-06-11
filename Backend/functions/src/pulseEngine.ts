/**
 * pulseEngine.ts — Amen Pulse pure builder/scorer (no Firestore I/O).
 *
 * Amen Pulse is a BOUNDED daily surface (NOT a feed). The server selects a
 * FINITE, ordered set of cards once per day and writes a SINGLE document the
 * client decodes verbatim. This module holds the pure, testable logic:
 *   - the written document/card shape (exact field names the iOS client decodes)
 *   - composite scoring + threshold + hard-cap selection
 *   - the guilt-lint regex pass (fail-closed: any match DROPS the card)
 *
 * Side-effecting work (collectors, model calls, safety calls, writes) lives in
 * pulse.ts. This file imports ONLY the firebase-admin Timestamp type.
 */

import * as admin from "firebase-admin";

type Ts = admin.firestore.Timestamp;

// ─── Written document shape (decoded by the iOS client — DO NOT rename) ───────

export type PulseCardKind =
  | "daily_brief_hero"
  | "scripture_hero"
  | "prayer_followup"
  | "occasion"
  | "church_event"
  | "space_activity"
  | "sermon"
  | "whats_new";

export type PulseActionKind =
  | "openBrief"
  | "pray"
  | "checkIn"
  | "rsvp"
  | "read"
  | "sendLove"
  | "openSpace"
  | "openSermon"
  | "tryFeature"
  | "seeWhatsNew"
  | "none";

/**
 * Synthesizes the in-app deeplink for a routable Pulse action. Pure routing —
 * no new data exposure, no tier/consent change. Returns undefined when the
 * kind + ids don't resolve to a destination the client DeepLinkRouter can
 * reach (the action pill then disables — fail-closed beats landing nowhere).
 *
 * Backend and the Swift PulseActionRouter / DeepLinkRouter MUST keep these
 * forms identical:
 *   pray      → amen://prayer/{prayerId}
 *   sendLove  → amen://user/{userId|friendId}
 *   rsvp      → amen://event/{eventId}
 *   openSermon→ amen://event/{eventId}
 *   openSpace → amen://space/{spaceId}
 */
export function pulseDeeplink(
  kind: PulseActionKind,
  ids: {
    prayerId?: string;
    friendId?: string;
    userId?: string;
    eventId?: string;
    spaceId?: string;
  }
): string | undefined {
  switch (kind) {
    case "pray":
      return ids.prayerId ? `amen://prayer/${ids.prayerId}` : undefined;
    case "sendLove": {
      const user = ids.userId ?? ids.friendId;
      return user ? `amen://user/${user}` : undefined;
    }
    case "rsvp":
    case "openSermon":
      return ids.eventId ? `amen://event/${ids.eventId}` : undefined;
    case "openSpace":
      return ids.spaceId ? `amen://space/${ids.spaceId}` : undefined;
    default:
      return undefined;
  }
}

export type PulseHeroStyle =
  | "brief"
  | "whatsnew"
  | "prayer"
  | "event"
  | "verse"
  | "occasion"
  | "space";

export type PulseBriefDuration = "30s" | "3m" | "10m";

export interface PulseScore {
  relationship: number;
  spiritual: number;
  community: number;
  urgency: number;
  interest: number;
  composite: number;
}

export interface PulseHero {
  imageUrl?: string;
  videoUrl?: string;
  scrim: "light" | "dark";
  style: PulseHeroStyle;
}

export interface PulseAction {
  kind: PulseActionKind;
  label: string;
  deeplink?: string;
  payload?: { [k: string]: string };
}

export interface PulseFactRow {
  systemImage: string;
  text: string;
}

export interface PulseBriefSection {
  heading: string;
  body: string;
  minimumDuration: PulseBriefDuration;
}

export interface PulseCard {
  id: string;
  kind: PulseCardKind;
  score: PulseScore;
  hero: PulseHero;
  eyebrow: string;
  title: string;
  subtitle?: string;
  action: PulseAction;
  minorSafe: boolean;
  expiresAt: Ts;
  provenanceLabel?: string;
  facts?: PulseFactRow[];
  meta?: PulseFactRow[];
  briefSections?: PulseBriefSection[];
  whatsNewStoryId?: string;
}

export interface PulseDocument {
  date: string;
  generatedAt: Ts;
  sabbath: boolean;
  briefDurations: PulseBriefDuration[];
  cards: PulseCard[];
}

// ─── Style weights (from user prefs) ──────────────────────────────────────────

export type PulseStyle =
  | "balanced"
  | "spiritual_first"
  | "relationship_first"
  | "community_first";

export interface PulseStyleWeights {
  relationship: number;
  spiritual: number;
  community: number;
  urgency: number;
  interest: number;
}

const STYLE_WEIGHTS: Record<PulseStyle, PulseStyleWeights> = {
  balanced: { relationship: 1, spiritual: 1, community: 1, urgency: 1, interest: 1 },
  spiritual_first: { relationship: 0.9, spiritual: 1.5, community: 0.9, urgency: 1, interest: 0.9 },
  relationship_first: { relationship: 1.5, spiritual: 0.9, community: 0.9, urgency: 1, interest: 0.9 },
  community_first: { relationship: 0.9, spiritual: 0.9, community: 1.5, urgency: 1, interest: 0.9 },
};

export function styleWeightsFor(style: string | undefined): PulseStyleWeights {
  if (style && style in STYLE_WEIGHTS) {
    return STYLE_WEIGHTS[style as PulseStyle];
  }
  return STYLE_WEIGHTS.balanced;
}

// ─── Candidate (pre-selection) ────────────────────────────────────────────────

/**
 * A candidate is a fully-formed card MINUS its final composite score. The
 * collectors in pulse.ts emit candidates with per-axis raw signal strengths;
 * the engine computes the composite and performs selection.
 */
export interface PulseCandidate {
  card: Omit<PulseCard, "score"> & { score?: never };
  signal: Omit<PulseScore, "composite">;
  /** True if this card originated from a crisis-class signal. Always dropped. */
  isCrisis?: boolean;
}

// ─── Guilt-lint (fail-closed) ─────────────────────────────────────────────────

/**
 * Guilt / absence / streak / velocity patterns. Any card whose title OR
 * subtitle OR eyebrow matches is DROPPED. This is a hard safety gate, not a
 * style preference: Pulse never nudges via guilt, absence, streaks, or hype.
 */
export const GUILT_LINT_PATTERNS: RegExp[] = [
  /you\s+haven'?t/i,
  /haven'?t\s+(talked|spoken|prayed|posted|opened|checked|been)/i,
  /\bmissed\b/i,
  /\bmissing\s+out\b/i,
  /\bstreak\b/i,
  /don'?t\s+lose/i,
  /keep\s+(it|your|the)\s+\w*\s*going/i,
  /\btrending\b/i,
  /\bpopular\b/i,
  /gaining\s+momentum/i,
  /\bblowing\s+up\b/i,
  /\bviral\b/i,
  /everyone'?s\s+(talking|watching)/i,
  /it'?s\s+been\s+\d+\s+(day|week)/i,
  /\bback\s+to\s+your/i,
  /\bwhere\s+have\s+you\s+been\b/i,
];

export function violatesGuiltLint(text: string | undefined): boolean {
  if (!text) return false;
  return GUILT_LINT_PATTERNS.some((p) => p.test(text));
}

/**
 * Returns true if a card is safe to ship past the guilt-lint gate.
 * Checks eyebrow, title and subtitle. Fail-closed: on any match → false.
 */
export function passesGuiltLint(card: Pick<PulseCard, "eyebrow" | "title" | "subtitle">): boolean {
  if (violatesGuiltLint(card.eyebrow)) return false;
  if (violatesGuiltLint(card.title)) return false;
  if (violatesGuiltLint(card.subtitle)) return false;
  return true;
}

// ─── Scoring + selection ──────────────────────────────────────────────────────

function clamp01(value: number): number {
  if (Number.isNaN(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

/**
 * Compute the composite for one candidate given the user's style weights.
 * Each axis is weighted, then averaged back into [0,1].
 */
export function compositeScore(
  signal: Omit<PulseScore, "composite">,
  weights: PulseStyleWeights
): PulseScore {
  const relationship = clamp01(signal.relationship);
  const spiritual = clamp01(signal.spiritual);
  const community = clamp01(signal.community);
  const urgency = clamp01(signal.urgency);
  const interest = clamp01(signal.interest);

  const weighted =
    relationship * weights.relationship +
    spiritual * weights.spiritual +
    community * weights.community +
    urgency * weights.urgency +
    interest * weights.interest;
  const weightSum =
    weights.relationship +
    weights.spiritual +
    weights.community +
    weights.urgency +
    weights.interest;

  const composite = clamp01(weightSum > 0 ? weighted / weightSum : 0);
  return { relationship, spiritual, community, urgency, interest, composite };
}

export interface SelectPulseCardsInput {
  candidates: PulseCandidate[];
  style: string | undefined;
  /** Hard cap from config (default 7). Never exceeded. */
  maxCards: number;
  /** Optional per-user lower cap (a user may lower, never raise). */
  userMaxCards?: number;
  /** Minimum composite required to ship. */
  scoreThreshold: number;
  /** True if the account is a minor — minorSafe==false cards are excluded. */
  isMinor: boolean;
}

/**
 * Pure selection: score → guilt-lint → crisis drop → minor gate → threshold →
 * sort best-first → hard cap. Returns the finite, ordered card array exactly as
 * it will be written into the document's `cards` field.
 */
export function selectPulseCards(input: SelectPulseCardsInput): PulseCard[] {
  const weights = styleWeightsFor(input.style);

  const effectiveCap = Math.max(
    0,
    Math.min(
      input.maxCards,
      typeof input.userMaxCards === "number" ? input.userMaxCards : input.maxCards
    )
  );

  const scored: PulseCard[] = [];
  for (const candidate of input.candidates) {
    // Crisis content NEVER becomes a Pulse card.
    if (candidate.isCrisis) continue;

    const base = candidate.card;

    // Guilt-lint fail-closed gate.
    if (!passesGuiltLint(base)) continue;

    // Minor gate: minors never see minorSafe==false cards.
    if (input.isMinor && base.minorSafe === false) continue;

    const score = compositeScore(candidate.signal, weights);
    if (score.composite < input.scoreThreshold) continue;

    scored.push({ ...base, score } as PulseCard);
  }

  scored.sort((a, b) => b.score.composite - a.score.composite);
  return scored.slice(0, effectiveCap);
}

// ─── Sabbath still card ───────────────────────────────────────────────────────

/**
 * The single still card written on a user's Sabbath. No events, no countdowns,
 * no actions beyond a gentle rest framing.
 */
export function buildSabbathStillCard(verseText: string, verseReference: string, expiresAt: Ts): PulseCard {
  return {
    id: "sabbath_still",
    kind: "scripture_hero",
    score: { relationship: 0, spiritual: 1, community: 0, urgency: 0, interest: 0, composite: 1 },
    hero: { scrim: "dark", style: "verse" },
    eyebrow: "SABBATH REST",
    title: verseText,
    subtitle: verseReference,
    action: { kind: "none", label: "Rest" },
    minorSafe: true,
    expiresAt,
    provenanceLabel: "A still moment for your Sabbath",
  };
}
