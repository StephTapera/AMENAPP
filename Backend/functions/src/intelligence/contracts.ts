// FROZEN CONTRACTS — do not edit without lead sign-off
// Living Intelligence System — Amen Platform

export type Tier = "SPIRITUAL" | "COMMUNITY" | "FAMILY" | "LOCAL" | "GLOBAL";
export type TruthLevel = "VERIFIED" | "CHURCH_CONFIRMED" | "COMMUNITY_CONFIRMED" | "DEVELOPING";
export type ActionRung = "NOTICE" | "PRAY" | "LEARN" | "DISCUSS" | "GIVE" | "SHOW_UP" | "START";
export type BackingKind = "CHURCH" | "ORG" | "EVENT" | "PRAYER_REQUEST" | "STUDY" | "NEED";

export interface BackingEntity {
  kind: BackingKind;
  id: string;       // MUST resolve to a real Firestore doc
  verified: boolean;
}

export interface CardAction {
  rung: ActionRung;
  label: string;
  handler: string;  // handler id — no dead buttons allowed
  target: string;
}

export interface IntelligenceCard {
  id: string;
  tier: Tier;
  title: string;
  summary: string[];            // <=3 bullets, Berean-generated, REAL citations only
  backingEntity: BackingEntity; // REQUIRED. No card renders without verified backing entity.
  truthLevel: TruthLevel;
  matchScore?: number;          // 0-100
  matchReasons?: string[];      // "Friends attending", "Near you", "Relevant age group"
  actions: CardAction[];        // ordered ActionRung ladder, each wired
  rankScore: number;
  rankReasons: string[];        // REQUIRED — every card explains why it surfaced
  geo?: { lat: number; lng: number; coarse: true };
  formation: {
    finite: true;
    spectacleCounters: false;
    lamentFrame?: boolean;
    loopParentId?: string;      // ties to prior user action for loop-closing
  };
  source?: string;              // provenance required for GLOBAL/news cards
  createdAt: number;
  expiresAt: number;
}

export type UIState = "LOADING" | "POPULATED" | "EMPTY" | "ERROR" | "OFFLINE_STALE" | "SENSITIVE";

// Formation Governor — invariants enforced in code AND asserted by Vitest
export const FORMATION_INVARIANTS = {
  FINITE_BRIEF: true,
  DIGEST_CADENCE_MAX_PER_DAY: 2,
  NO_SPECTACLE_COUNTERS: true,
  DEVELOPING_NEVER_TOP: true,
  POLITICS_ROUTE_ONLY: ["PRAY", "SHOW_UP", "GIVE"] as ActionRung[],
  LOOP_CLOSING_REQUIRED: true,
  COARSE_GEO_ONLY: true,
} as const;

export const MAX_CARDS_PER_BRIEF = 7;
export const MAX_SUMMARY_BULLETS = 3;

// callModel task names — registered in amen.routing.config.ts
export const INTELLIGENCE_TASKS = {
  SUMMARIZE: "intelligence.summarize",           // Berean/Claude, fail-closed, REAL citations only
  CLASSIFY_NEED: "intelligence.classify_need",   // need detection over posts/prayers/announcements
  MATCH: "intelligence.match",                   // event & prayer matching → matchScore + matchReasons
  WORLD_RESPONSE: "intelligence.world_response", // GLOBAL cards: known/contested/how-to-respond
} as const;

// Action handler ids — every CardAction.handler must be one of these
export const ACTION_HANDLERS = {
  OPEN_EVENT: "action.openEvent",
  OPEN_PRAYER: "action.openPrayer",
  OPEN_CHURCH: "action.openChurch",
  OPEN_STUDY: "action.openStudy",
  OPEN_NEED: "action.openNeed",
  OPEN_ORG: "action.openOrg",
  ADD_TO_PRAYER: "action.addToPrayer",
  RSVP_EVENT: "action.rsvpEvent",
  GIVE_TO_NEED: "action.giveToNeed",
  VOLUNTEER: "action.volunteer",
  SHARE_STUDY: "action.shareStudy",
  DISCUSS: "action.discuss",
  START_INITIATIVE: "action.startInitiative",
} as const;

export type ActionHandlerId = typeof ACTION_HANDLERS[keyof typeof ACTION_HANDLERS];
