/**
 * worldResponseEngine.ts
 *
 * Living Intelligence — GLOBAL Tier
 * Generates WorldResponseOutput from a WorldEventInput via Anthropic Claude.
 *
 * Contract rules (enforced here, not in callers):
 *  - Summary is ALWAYS three parts: What's Known / What's Contested / How to Respond
 *  - Never asserts unverified claims
 *  - Never produces partisan framing or editorial commentary
 *  - Lament frame required for disaster / conflict / persecution events
 *  - isDeveloping = true  if source count < 2 OR event is < 4 hours old
 *  - Suggested actions STRICTLY: PRAY | GIVE | SHOW_UP | DISCUSS — no others
 *  - If Anthropic is unavailable: returns null (fail-closed, no fabricated response)
 *
 * Called by: worldEventsFunctions.ts (submitWorldEvent, digest builder)
 */

import { ACTION_HANDLERS } from "./contracts";
import { callModel } from "./amenRouting";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type WorldEventType =
  | "disaster"
  | "conflict"
  | "persecution"
  | "humanitarian"
  | "global_church"
  | "general";

export type GlobalActionRung = "PRAY" | "GIVE" | "SHOW_UP" | "DISCUSS";

export interface WorldEventInput {
  title: string;
  description: string;
  source: string;         // provenance required — caller must validate non-empty
  sourceUrl?: string;
  eventType: WorldEventType;
  verifiedBy?: string;    // e.g. "AP", "Reuters", "BBC"
  publishedAt: number;    // Unix ms
}

export interface WorldResponseOutput {
  whatIsKnown: string;       // verified facts only
  whatIsContested: string;   // what is disputed or unclear
  howToRespond: string;      // Christian response framing — no editorial opinion
  isLamentContext: boolean;  // true for disaster / conflict / persecution
  isDeveloping: boolean;     // true → card must be DEMOTED in ranking
  suggestedActions: Array<{
    rung: GlobalActionRung;
    label: string;
    handler: string;
    target: string;
  }>;
}

// ---------------------------------------------------------------------------
// Known authoritative sources — used to determine VERIFIED vs DEVELOPING
// ---------------------------------------------------------------------------

const AUTHORITATIVE_SOURCES = new Set([
  "ap", "reuters", "bbc", "associated press", "afp", "npr",
  "un", "united nations", "unhcr", "red cross", "icrc",
  "world council of churches", "lausanne movement",
  "open doors", "voice of the martyrs", "compass direct",
]);

function isAuthoritativeSource(verifiedBy?: string): boolean {
  if (!verifiedBy) return false;
  return AUTHORITATIVE_SOURCES.has(verifiedBy.toLowerCase().trim());
}

// ---------------------------------------------------------------------------
// Core generation function
// ---------------------------------------------------------------------------

/**
 * Calls Anthropic Claude to produce a WorldResponseOutput.
 * Returns null on ANY failure — no partial / fabricated responses.
 */
export async function generateWorldResponse(
  event: WorldEventInput
): Promise<WorldResponseOutput | null> {
  // Guard: source is required
  if (!event.source || event.source.trim() === "") {
    return null;
  }

  const isLamentContext =
    event.eventType === "disaster" ||
    event.eventType === "conflict" ||
    event.eventType === "persecution";

  // isDeveloping: single unverified source OR < 4 hours old
  const fourHoursMs = 4 * 60 * 60 * 1000;
  const isDeveloping =
    !isAuthoritativeSource(event.verifiedBy) ||
    Date.now() - event.publishedAt < fourHoursMs;

  const systemPrompt = buildSystemPrompt(isLamentContext);
  const userPrompt = buildUserPrompt(event);

  try {
    const output = await callModel({
      task: "intelligence.world_response",
      input: `${systemPrompt}\n\n${userPrompt}`,
      userId: "system",
    });

    if (output.error || !output.result) return null;

    const parsed = parseAnthropicResponse(
      typeof output.result === "string" ? output.result : JSON.stringify(output.result)
    );
    if (!parsed) return null;

    // Build suggested actions — strictly limited to GLOBAL-allowed rungs
    const suggestedActions = buildSuggestedActions(event, isLamentContext);

    return {
      whatIsKnown: parsed.whatIsKnown,
      whatIsContested: parsed.whatIsContested,
      howToRespond: parsed.howToRespond,
      isLamentContext,
      isDeveloping,
      suggestedActions,
    };
  } catch (err) {
    // Fail-closed: log and return null — never fabricate
    console.error("[worldResponseEngine] generateWorldResponse failed:", err);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Prompt builders
// ---------------------------------------------------------------------------

function buildSystemPrompt(isLamentContext: boolean): string {
  const lamentInstruction = isLamentContext
    ? [
        "This event is a disaster, conflict, or persecution — use a lament-and-act frame.",
        "Acknowledge suffering with compassion before moving to response.",
        "Never minimize or rationalize the harm.",
      ].join(" ")
    : "Frame the response with Christian hope and practical action.";

  return [
    "You are a trusted Christian world-events reporter for the AMEN platform.",
    "Your job is to help the Christian community understand world events and respond faithfully.",
    "",
    "ABSOLUTE RULES:",
    "1. Never assert unverified facts. If something is disputed, say so in whatIsContested.",
    "2. Never produce partisan political framing, editorial commentary, or 'hot takes'.",
    "3. Never tell users WHAT to think politically — only what is factually known and how Christians can respond.",
    "4. Cite the original source; never fabricate quotes or statistics.",
    "5. If you do not have reliable information, say 'Details are still emerging' rather than guessing.",
    "",
    lamentInstruction,
    "",
    "Respond ONLY with valid JSON matching this exact schema:",
    JSON.stringify({
      whatIsKnown: "<verified facts only, ≤60 words>",
      whatIsContested: "<what is disputed or unclear, ≤50 words>",
      howToRespond: "<how Christians can respond faithfully, ≤60 words — no political opinion>",
    }),
  ].join("\n");
}

function buildUserPrompt(event: WorldEventInput): string {
  return [
    `Event title: ${event.title}`,
    `Event type: ${event.eventType}`,
    `Source: ${event.source}${event.verifiedBy ? ` (verified by ${event.verifiedBy})` : ""}`,
    event.sourceUrl ? `Source URL: ${event.sourceUrl}` : "",
    "",
    "Description:",
    event.description,
  ]
    .filter(Boolean)
    .join("\n");
}


// ---------------------------------------------------------------------------
// Response parser
// ---------------------------------------------------------------------------

interface ParsedResponse {
  whatIsKnown: string;
  whatIsContested: string;
  howToRespond: string;
}

function parseAnthropicResponse(raw: string): ParsedResponse | null {
  try {
    // Strip markdown code fences if present
    const cleaned = raw
      .replace(/^```json\s*/i, "")
      .replace(/^```\s*/i, "")
      .replace(/\s*```$/i, "")
      .trim();

    const obj = JSON.parse(cleaned) as Record<string, unknown>;
    const whatIsKnown = typeof obj.whatIsKnown === "string" ? obj.whatIsKnown.trim() : "";
    const whatIsContested = typeof obj.whatIsContested === "string" ? obj.whatIsContested.trim() : "";
    const howToRespond = typeof obj.howToRespond === "string" ? obj.howToRespond.trim() : "";

    if (!whatIsKnown || !whatIsContested || !howToRespond) {
      console.error("[worldResponseEngine] parseAnthropicResponse: missing required fields");
      return null;
    }

    return { whatIsKnown, whatIsContested, howToRespond };
  } catch (err) {
    console.error("[worldResponseEngine] parseAnthropicResponse JSON error:", err);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Suggested action builder
// ---------------------------------------------------------------------------

function buildSuggestedActions(
  event: WorldEventInput,
  isLamentContext: boolean
): WorldResponseOutput["suggestedActions"] {
  const actions: WorldResponseOutput["suggestedActions"] = [];

  // PRAY is always first for GLOBAL cards
  actions.push({
    rung: "PRAY",
    label: isLamentContext ? "Pray for those affected" : "Pray about this",
    handler: ACTION_HANDLERS.ADD_TO_PRAYER,
    target: `world_event:${slugify(event.title)}`,
  });

  // GIVE is appropriate for humanitarian / disaster
  if (
    event.eventType === "disaster" ||
    event.eventType === "humanitarian" ||
    event.eventType === "persecution"
  ) {
    actions.push({
      rung: "GIVE",
      label: "Give to relief efforts",
      handler: ACTION_HANDLERS.GIVE_TO_NEED,
      target: `world_event:${slugify(event.title)}`,
    });
  }

  // SHOW_UP for local or humanitarian action
  if (
    event.eventType === "humanitarian" ||
    event.eventType === "global_church"
  ) {
    actions.push({
      rung: "SHOW_UP",
      label: "Find a way to serve",
      handler: ACTION_HANDLERS.VOLUNTEER,
      target: `world_event:${slugify(event.title)}`,
    });
  }

  // DISCUSS — always available
  actions.push({
    rung: "DISCUSS",
    label: "Discuss with your community",
    handler: ACTION_HANDLERS.DISCUSS,
    target: `world_event:${slugify(event.title)}`,
  });

  return actions;
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function slugify(title: string): string {
  return title
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "_")
    .slice(0, 64);
}
