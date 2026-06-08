/**
 * opportunityGraph.ts
 *
 * Opportunity Graph store and writer for AMEN Living Intelligence.
 * All Firestore writes use Admin SDK only — never client SDK.
 *
 * Collections:
 *   opportunity_graph/{opportunityId}   — OpportunityNode documents
 *
 * Supply↔Demand routing:
 *   matchOpportunitiesToUser computes matchScore + matchReasons per node
 *   using the same callModel abstraction (intelligence.match task).
 */

import * as admin from "firebase-admin";
import { BackingKind, Tier } from "./contracts";
import { callModel } from "./amenRouting";
import { UserContext } from "./rankingEngine";

// ─── Types ─────────────────────────────────────────────────────────────────────

export interface OpportunityNode {
  id: string;
  kind: BackingKind;
  backingRef: string;         // Firestore doc path, must resolve
  title: string;
  tier: Tier;
  churchIds: string[];        // affiliated churches
  geo?: { lat: number; lng: number; coarse: true };
  needs: string[];            // what this opportunity needs (volunteers, donors, prayers)
  provides: string[];         // what this provides (community, growth, service)
  expiresAt: number;
  createdAt: number;
  isActive: boolean;
}

export interface MatchedOpportunity {
  node: OpportunityNode;
  matchScore: number;
  matchReasons: string[];
}

// ─── Constants ─────────────────────────────────────────────────────────────────

const OPPORTUNITY_GRAPH_COLLECTION = "opportunity_graph";

// Maximum age (milliseconds) for default reads — 30 days
const DEFAULT_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;

// ─── Firestore helpers ─────────────────────────────────────────────────────────

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

// ─── addOpportunityNode ────────────────────────────────────────────────────────

/**
 * Write a new opportunity node to Firestore.
 * Returns the generated document ID.
 * Validates that backingRef is a non-empty path before writing.
 */
export async function addOpportunityNode(
  node: Omit<OpportunityNode, "id" | "createdAt">
): Promise<string> {
  if (!node.backingRef || node.backingRef.trim().length === 0) {
    throw new Error("backingRef is required and must be a non-empty Firestore path");
  }
  if (!node.title || node.title.trim().length === 0) {
    throw new Error("title is required");
  }
  if (!node.kind) {
    throw new Error("kind is required");
  }
  if (!node.tier) {
    throw new Error("tier is required");
  }

  // Enforce coarse geo — if geo is provided without coarse: true, strip it
  let safeGeo: OpportunityNode["geo"] | undefined = undefined;
  if (node.geo) {
    safeGeo = {
      lat: node.geo.lat,
      lng: node.geo.lng,
      coarse: true, // always set, enforces COARSE_GEO_ONLY
    };
  }

  const createdAt = Date.now();
  const docRef = db().collection(OPPORTUNITY_GRAPH_COLLECTION).doc();

  const fullNode: OpportunityNode = {
    ...node,
    id: docRef.id,
    geo: safeGeo,
    createdAt,
    needs: node.needs ?? [],
    provides: node.provides ?? [],
    churchIds: node.churchIds ?? [],
    isActive: node.isActive ?? true,
  };

  await docRef.set(fullNode);
  return docRef.id;
}

// ─── getOpportunityNodes ───────────────────────────────────────────────────────

/**
 * Fetch active opportunity nodes for a set of churches.
 * maxAge is in milliseconds; defaults to DEFAULT_MAX_AGE_MS (30 days).
 * Returns at most 50 nodes to avoid runaway read costs.
 */
export async function getOpportunityNodes(
  churchIds: string[],
  maxAge: number = DEFAULT_MAX_AGE_MS
): Promise<OpportunityNode[]> {
  if (churchIds.length === 0) {
    return [];
  }

  const now = Date.now();
  const oldestAllowed = now - maxAge;

  // Firestore `in` operator supports up to 30 values; chunk if needed
  const chunks: string[][] = [];
  for (let i = 0; i < churchIds.length; i += 30) {
    chunks.push(churchIds.slice(i, i + 30));
  }

  const results: OpportunityNode[] = [];

  for (const chunk of chunks) {
    const snap = await db()
      .collection(OPPORTUNITY_GRAPH_COLLECTION)
      .where("churchIds", "array-contains-any", chunk)
      .where("isActive", "==", true)
      .where("expiresAt", ">", now)
      .orderBy("expiresAt", "asc")
      .limit(50)
      .get();

    for (const doc of snap.docs) {
      const node = doc.data() as OpportunityNode;
      if (node.createdAt >= oldestAllowed) {
        results.push(node);
      }
    }
  }

  // Deduplicate by id in case of overlap across chunks
  const seen = new Set<string>();
  return results.filter((n) => {
    if (seen.has(n.id)) return false;
    seen.add(n.id);
    return true;
  });
}

// ─── matchOpportunitiesToUser ──────────────────────────────────────────────────

/**
 * Supply↔demand routing: match opportunity nodes to a user's context.
 * Uses callModel(intelligence.match) for AI-powered scoring.
 * Falls back to heuristic scoring if AI is unavailable (fail-open for matching
 * since this is ranking, not safety — but logs the fallback).
 */
export async function matchOpportunitiesToUser(
  uid: string,
  context: UserContext
): Promise<MatchedOpportunity[]> {
  // Fetch candidate nodes from followed churches
  const nodes = await getOpportunityNodes(context.followedChurchIds);

  if (nodes.length === 0) {
    return [];
  }

  const matched: MatchedOpportunity[] = [];

  for (const node of nodes) {
    const { matchScore, matchReasons } = await scoreNode(node, context, uid);
    if (matchScore > 0) {
      matched.push({ node, matchScore, matchReasons });
    }
  }

  // Sort descending by matchScore
  return matched.sort((a, b) => b.matchScore - a.matchScore);
}

// ─── Internal scoring ─────────────────────────────────────────────────────────

async function scoreNode(
  node: OpportunityNode,
  ctx: UserContext,
  uid: string
): Promise<{ matchScore: number; matchReasons: string[] }> {
  // Build a context payload for the AI model
  const contextPayload: Record<string, unknown> = {
    opportunityTitle: node.title,
    opportunityKind: node.kind,
    opportunityTier: node.tier,
    opportunityNeeds: node.needs,
    opportunityProvides: node.provides,
    userSeasonOfLife: ctx.seasonOfLife ?? "unknown",
    userLiturgicalSeason: ctx.liturgicalCalendarData?.currentSeason ?? "Ordinary Time",
    userChurchIds: ctx.followedChurchIds,
    opportunityChurchIds: node.churchIds,
    isChurchMatch: node.churchIds.some((id) => ctx.followedChurchIds.includes(id)),
    hasGeo: Boolean(node.geo && ctx.coarseGeo),
  };

  const aiResult = await callModel({
    task: "intelligence.match",
    input: `Match this opportunity to a user and compute matchScore (0-100) and matchReasons.`,
    context: contextPayload,
    userId: uid,
    safetyLevel: "standard",
  });

  if (aiResult.error || !aiResult.result) {
    // AI unavailable — use heuristic fallback
    return heuristicScore(node, ctx);
  }

  const parsed = aiResult.result as { matchScore?: number; matchReasons?: string[] };

  if (
    typeof parsed.matchScore !== "number" ||
    !Array.isArray(parsed.matchReasons)
  ) {
    return heuristicScore(node, ctx);
  }

  return {
    matchScore: Math.max(0, Math.min(100, Math.round(parsed.matchScore))),
    matchReasons: parsed.matchReasons.slice(0, 4),
  };
}

/**
 * Heuristic fallback when AI is unavailable.
 * Simpler scoring: church match + geo + tier.
 */
function heuristicScore(
  node: OpportunityNode,
  ctx: UserContext
): { matchScore: number; matchReasons: string[] } {
  let score = 30; // base
  const reasons: string[] = [];

  const churchMatch = node.churchIds.some((id) => ctx.followedChurchIds.includes(id));
  if (churchMatch) {
    score += 30;
    reasons.push("Your church is involved");
  }

  if (node.geo && ctx.coarseGeo) {
    const dLat = Math.abs(node.geo.lat - ctx.coarseGeo.lat);
    const dLng = Math.abs(node.geo.lng - ctx.coarseGeo.lng);
    const roughDist = Math.sqrt(dLat * dLat + dLng * dLng);
    if (roughDist < 0.3) {
      score += 20;
      reasons.push("Near you");
    } else if (roughDist < 1.0) {
      score += 10;
      reasons.push("In your area");
    }
  }

  const tierBonus: Record<string, number> = {
    SPIRITUAL: 15,
    FAMILY: 12,
    COMMUNITY: 10,
    LOCAL: 7,
    GLOBAL: 5,
  };
  score += tierBonus[node.tier] ?? 5;
  if (node.tier === "SPIRITUAL") reasons.push("Spiritual growth opportunity");

  return {
    matchScore: Math.min(100, score),
    matchReasons: reasons.length > 0 ? reasons : ["Recommended for your community"],
  };
}
