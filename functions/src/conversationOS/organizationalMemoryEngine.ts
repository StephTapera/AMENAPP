// organizationalMemoryEngine.ts
// AMEN Conversation OS — Organizational Memory Engine
//
// Persists and queries: recurring topics, prior decisions, historical context,
// unresolved discussions, org momentum, and evolving collaboration patterns.
// Supports queries: "What changed?", "What's unresolved?", "What did we decide?"

import * as admin from "firebase-admin";
import { OrganizationalMemory, Decision, UnresolvedQuestion, SummaryProvenance } from "./types";
import { v4 as uuidv4 } from "uuid";

const db = admin.firestore();

// MARK: - Save Weekly Memory

export async function saveWeeklyMemory(
  orgId: string,
  weekLabel: string,
  decisions: Decision[],
  unresolvedItems: UnresolvedQuestion[],
  recurringTopics: string[],
  collaborationPatterns: string[],
  summaryText: string,
  provenance: SummaryProvenance
): Promise<void> {
  const memory: OrganizationalMemory = {
    id: uuidv4(),
    orgId,
    weekLabel,
    recurringTopics,
    keyDecisions: decisions,
    unresolvedItems,
    collaborationPatterns,
    summaryText,
    generatedAt: new Date(),
    provenance,
  };

  await db
    .collection("organizations").doc(orgId)
    .collection("memory").doc(memory.id)
    .set({
      ...memory,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

// MARK: - Query Memory

export async function queryOrgMemory(
  orgId: string,
  query: string
): Promise<OrganizationalMemory | null> {
  const intent = classifyMemoryQuery(query);

  try {
    let snapshot: admin.firestore.QuerySnapshot;

    switch (intent) {
      case "recent_changes":
        snapshot = await db
          .collection("organizations").doc(orgId)
          .collection("memory")
          .orderBy("generatedAt", "desc")
          .limit(1)
          .get();
        break;

      case "unresolved":
        snapshot = await db
          .collection("organizations").doc(orgId)
          .collection("memory")
          .orderBy("generatedAt", "desc")
          .limit(3)
          .get();
        // Find the one with most unresolved items
        const docs = snapshot.docs.map((d) => d.data() as OrganizationalMemory);
        const mostUnresolved = docs.sort(
          (a, b) => (b.unresolvedItems?.length ?? 0) - (a.unresolvedItems?.length ?? 0)
        )[0];
        return mostUnresolved ?? null;

      case "decisions":
        snapshot = await db
          .collection("organizations").doc(orgId)
          .collection("memory")
          .orderBy("generatedAt", "desc")
          .limit(2)
          .get();
        break;

      default:
        snapshot = await db
          .collection("organizations").doc(orgId)
          .collection("memory")
          .orderBy("generatedAt", "desc")
          .limit(1)
          .get();
    }

    if (snapshot.empty) return null;
    return snapshot.docs[0].data() as OrganizationalMemory;
  } catch (err) {
    console.error("queryOrgMemory error:", err);
    return null;
  }
}

// MARK: - Get Recurring Topics

export async function getRecurringTopics(orgId: string, lookbackWeeks = 4): Promise<string[]> {
  try {
    const snapshot = await db
      .collection("organizations").doc(orgId)
      .collection("memory")
      .orderBy("generatedAt", "desc")
      .limit(lookbackWeeks)
      .get();

    const allTopics = snapshot.docs.flatMap(
      (d) => (d.data() as OrganizationalMemory).recurringTopics ?? []
    );

    // Count and return topics that appear in 2+ weeks
    const counts: Map<string, number> = new Map();
    for (const topic of allTopics) {
      counts.set(topic, (counts.get(topic) ?? 0) + 1);
    }

    return Array.from(counts.entries())
      .filter(([, count]) => count >= 2)
      .sort(([, a], [, b]) => b - a)
      .map(([topic]) => topic)
      .slice(0, 10);
  } catch {
    return [];
  }
}

// MARK: - Get Prior Decisions

export async function getPriorDecisions(orgId: string, limit = 10): Promise<Decision[]> {
  try {
    const snapshot = await db
      .collection("organizations").doc(orgId)
      .collection("memory")
      .orderBy("generatedAt", "desc")
      .limit(4)
      .get();

    return snapshot.docs
      .flatMap((d) => (d.data() as OrganizationalMemory).keyDecisions ?? [])
      .filter((d) => d.status === "confirmed" || d.status === "proposed")
      .slice(0, limit);
  } catch {
    return [];
  }
}

// MARK: - Get Unresolved History

export async function getUnresolvedHistory(orgId: string): Promise<UnresolvedQuestion[]> {
  try {
    const snapshot = await db
      .collection("organizations").doc(orgId)
      .collection("memory")
      .orderBy("generatedAt", "desc")
      .limit(3)
      .get();

    return snapshot.docs
      .flatMap((d) => (d.data() as OrganizationalMemory).unresolvedItems ?? [])
      .slice(0, 15);
  } catch {
    return [];
  }
}

// MARK: - Detect Recurring Topics from Weekly Summaries

export function detectRecurringTopics(currentTopics: string[], historicalTopics: string[]): string[] {
  const historical = new Set(historicalTopics.map((t) => t.toLowerCase()));
  return currentTopics.filter((t) => historical.has(t.toLowerCase()));
}

// MARK: - Detect Collaboration Patterns

export function detectCollaborationPatterns(messages: { senderId: string; replyCount: number }[]): string[] {
  const patterns: string[] = [];

  const participantEngagement = messages.reduce((acc, m) => {
    acc.set(m.senderId, (acc.get(m.senderId) ?? 0) + m.replyCount + 1);
    return acc;
  }, new Map<string, number>());

  const active = [...participantEngagement.values()].filter((v) => v > 3).length;
  const total = participantEngagement.size;

  if (total > 0 && active / total > 0.7) {
    patterns.push("High collaboration — most members are actively engaging.");
  } else if (active === 1) {
    patterns.push("One-way communication — few members are responding.");
  }

  if (messages.filter((m) => m.replyCount > 5).length > 0) {
    patterns.push("Deep discussion threads forming around key topics.");
  }

  return patterns;
}

// MARK: - Memory Query Intent Classification

type MemoryQueryIntent = "recent_changes" | "unresolved" | "decisions" | "blockers" | "general";

function classifyMemoryQuery(query: string): MemoryQueryIntent {
  const lower = query.toLowerCase();
  if (/changed|update|new|recent|since/i.test(lower)) return "recent_changes";
  if (/unresolved|open|pending|unanswered|outstanding/i.test(lower)) return "unresolved";
  if (/decid|approved|confirmed|agreed/i.test(lower)) return "decisions";
  if (/blocked?|blocker|issue|problem/i.test(lower)) return "blockers";
  return "general";
}

// MARK: - Week Label Builder

export function buildWeekLabel(date: Date = new Date()): string {
  const start = new Date(date);
  start.setDate(date.getDate() - date.getDay()); // Sunday
  const end = new Date(start);
  end.setDate(start.getDate() + 6);

  const fmt = (d: Date) =>
    d.toLocaleDateString("en-US", { month: "short", day: "numeric" });

  return `Week of ${fmt(start)}–${fmt(end)}, ${end.getFullYear()}`;
}
