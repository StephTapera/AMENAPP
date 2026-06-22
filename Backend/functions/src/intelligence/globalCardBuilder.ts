/**
 * globalCardBuilder.ts
 *
 * Living Intelligence — GLOBAL Tier
 * Builds a well-formed IntelligenceCard from a WorldEventInput + WorldResponseOutput.
 *
 * This is a pure utility — no Cloud Function, no Firestore reads.
 * All callers (worldEventsFunctions.ts, digest builder) must pass a resolved orgId
 * or accept a DEVELOPING card with the "global_response" fallback.
 *
 * Contract invariants enforced here (thrown as Error so callers get a hard failure):
 *  - source REQUIRED — never a sourceless GLOBAL card
 *  - backingEntity REQUIRED — resolves to orgId or "global_response"
 *  - formation.lamentFrame = worldResponse.isLamentContext
 *  - formation.spectacleCounters = false
 *  - formation.finite = true
 *  - truthLevel = "VERIFIED" only if verifiedBy is a known authoritative source;
 *    otherwise "DEVELOPING"
 *  - actions ONLY from: PRAY, GIVE, SHOW_UP, DISCUSS — any others stripped
 *  - summary = exactly 3 bullets from [whatIsKnown, whatIsContested, howToRespond]
 */

import * as crypto from "crypto";
import type {
  IntelligenceCard,
  TruthLevel,
  BackingEntity,
  CardAction,
  ActionRung,
} from "./contracts";
import type { WorldEventInput, WorldResponseOutput } from "./worldResponseEngine";

// ---------------------------------------------------------------------------
// Allowed action rungs for GLOBAL tier — no others permitted
// ---------------------------------------------------------------------------

const GLOBAL_ALLOWED_RUNGS = new Set<ActionRung>(["PRAY", "GIVE", "SHOW_UP", "DISCUSS"]);

// ---------------------------------------------------------------------------
// Authoritative source registry (mirrors worldResponseEngine — kept in sync)
// ---------------------------------------------------------------------------

const AUTHORITATIVE_SOURCES = new Set([
  "ap", "reuters", "bbc", "associated press", "afp", "npr",
  "un", "united nations", "unhcr", "red cross", "icrc",
  "world council of churches", "lausanne movement",
  "open doors", "voice of the martyrs", "compass direct",
]);

function resolveTruthLevel(event: WorldEventInput): TruthLevel {
  if (
    event.verifiedBy &&
    AUTHORITATIVE_SOURCES.has(event.verifiedBy.toLowerCase().trim())
  ) {
    return "VERIFIED";
  }
  return "DEVELOPING";
}

// ---------------------------------------------------------------------------
// Card TTL — GLOBAL cards expire after 48 h (developing after 6 h)
// ---------------------------------------------------------------------------

const GLOBAL_TTL_MS = 48 * 60 * 60 * 1000;
const DEVELOPING_TTL_MS = 6 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// buildGlobalCard
// ---------------------------------------------------------------------------

/**
 * @param event        - The raw world event input (source REQUIRED)
 * @param worldResponse - The AI-generated response from worldResponseEngine
 * @param orgId        - Optional: verified org entity to use as backingEntity.id
 *                       If absent, falls back to "global_response" with verified: false
 */
export function buildGlobalCard(
  event: WorldEventInput,
  worldResponse: WorldResponseOutput,
  orgId?: string
): IntelligenceCard {
  // --- Guard: source required ---
  if (!event.source || event.source.trim() === "") {
    throw new Error("buildGlobalCard: source is required for every GLOBAL card");
  }

  const truthLevel = resolveTruthLevel(event);
  const now = Date.now();
  const ttl = worldResponse.isDeveloping ? DEVELOPING_TTL_MS : GLOBAL_TTL_MS;

  // --- backingEntity resolution ---
  let backingEntity: BackingEntity;
  if (orgId && orgId.trim() !== "") {
    backingEntity = {
      kind: "ORG",
      id: orgId.trim(),
      verified: true,
    };
  } else {
    // Fallback — must always resolve to something; DEVELOPING forces demotion
    if (!orgId) {
      backingEntity = {
        kind: "ORG",
        id: "global_response",
        verified: false,
      };
    } else {
      throw new Error("buildGlobalCard: backingEntity could not be resolved");
    }
  }

  // --- Filter actions to GLOBAL-allowed rungs ONLY ---
  const filteredActions: CardAction[] = worldResponse.suggestedActions
    .filter((a) => GLOBAL_ALLOWED_RUNGS.has(a.rung as ActionRung))
    .map((a) => ({
      rung: a.rung as ActionRung,
      label: a.label,
      handler: a.handler,
      target: a.target,
    }));

  if (filteredActions.length === 0) {
    throw new Error(
      "buildGlobalCard: no valid actions after filtering — at least PRAY must be present"
    );
  }

  // --- Rank score: DEVELOPING is demoted to bottom quartile ---
  const baseRank = worldResponse.isDeveloping ? 10 : 60;
  const rankScore =
    baseRank +
    (worldResponse.isLamentContext ? 15 : 0) + // lament events surface higher
    (truthLevel === "VERIFIED" ? 10 : 0);

  const rankReasons: string[] = [];
  if (worldResponse.isLamentContext) rankReasons.push("Lament context: disaster/conflict/persecution");
  if (truthLevel === "VERIFIED") rankReasons.push(`Verified by ${event.verifiedBy}`);
  if (worldResponse.isDeveloping) rankReasons.push("Developing story — demoted");
  rankReasons.push(`Source: ${event.source}`);

  // --- Summary: exactly 3 bullets ---
  const summary: string[] = [
    worldResponse.whatIsKnown,
    worldResponse.whatIsContested,
    worldResponse.howToRespond,
  ];

  const card: IntelligenceCard = {
    id: crypto.randomUUID(),
    tier: "GLOBAL",
    title: event.title,
    summary,
    backingEntity,
    truthLevel,
    actions: filteredActions,
    rankScore,
    rankReasons,
    source: event.source,
    formation: {
      finite: true,
      spectacleCounters: false,
      lamentFrame: worldResponse.isLamentContext || undefined,
    },
    createdAt: now,
    expiresAt: now + ttl,
  };

  return card;
}
