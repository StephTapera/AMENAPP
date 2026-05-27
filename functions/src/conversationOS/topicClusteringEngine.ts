// topicClusteringEngine.ts
// AMEN Conversation OS — Semantic Topic Clustering Engine
//
// Converts unread/discussion volume into semantic clusters.
// Does NOT summarize chronologically — groups by semantic intent.
// Clusters: "Event planning", "Leadership decisions", "Prayer momentum", etc.

import { RawMessage, TopicCluster, SemanticTag, CompressedChunk } from "./types";
import { v4 as uuidv4 } from "uuid";

// MARK: - Cluster Entry Point

export function clusterMessages(
  messages: RawMessage[],
  chunks: CompressedChunk[]
): TopicCluster[] {
  if (messages.length === 0) return [];

  // Group chunks by dominant tag
  const tagGroups = groupChunksByDominantTag(chunks);

  // Merge related tag groups into semantic clusters
  const merged = mergeRelatedGroups(tagGroups);

  // Build cluster objects
  return merged.map((group) => buildCluster(group.chunks, group.label, messages));
}

// MARK: - Group Chunks by Dominant Tag

interface TagGroup {
  tag: SemanticTag;
  chunks: CompressedChunk[];
}

function groupChunksByDominantTag(chunks: CompressedChunk[]): TagGroup[] {
  const groups: Map<SemanticTag, CompressedChunk[]> = new Map();

  for (const chunk of chunks) {
    const dominantTag = chunk.tags[0] ?? ("question" as SemanticTag);
    const existing = groups.get(dominantTag) ?? [];
    existing.push(chunk);
    groups.set(dominantTag, existing);
  }

  return Array.from(groups.entries()).map(([tag, chunks]) => ({ tag, chunks }));
}

// MARK: - Merge Related Groups (semantic grouping)

interface MergedGroup {
  label: string;
  tags: SemanticTag[];
  chunks: CompressedChunk[];
}

const SEMANTIC_MERGE_MAP: Array<{ tags: SemanticTag[]; label: string }> = [
  { tags: ["decision", "consensus"], label: "Decisions & Agreements" },
  { tags: ["task", "reminder", "blocker"], label: "Tasks & Follow-Ups" },
  { tags: ["question"], label: "Open Questions" },
  { tags: ["prayer_request", "encouragement"], label: "Prayer & Encouragement" },
  { tags: ["announcement"], label: "Announcements" },
  { tags: ["teaching_moment"], label: "Study & Teaching" },
  { tags: ["conflict", "escalation"], label: "Items Needing Attention" },
];

function mergeRelatedGroups(groups: TagGroup[]): MergedGroup[] {
  const used = new Set<SemanticTag>();
  const merged: MergedGroup[] = [];

  for (const mapping of SEMANTIC_MERGE_MAP) {
    const matchingGroups = groups.filter(
      (g) => mapping.tags.includes(g.tag) && !used.has(g.tag)
    );
    if (matchingGroups.length === 0) continue;

    for (const g of matchingGroups) used.add(g.tag);
    merged.push({
      label: mapping.label,
      tags: mapping.tags,
      chunks: matchingGroups.flatMap((g) => g.chunks),
    });
  }

  // Catch-all for any remaining tags
  const remaining = groups.filter((g) => !used.has(g.tag));
  if (remaining.length > 0) {
    merged.push({
      label: "General Discussion",
      tags: remaining.map((g) => g.tag),
      chunks: remaining.flatMap((g) => g.chunks),
    });
  }

  return merged.filter((g) => g.chunks.length > 0);
}

// MARK: - Build Cluster Object

function buildCluster(
  chunks: CompressedChunk[],
  label: string,
  allMessages: RawMessage[]
): TopicCluster {
  const messageIds = new Set(chunks.flatMap((c) => c.messageIds));
  const clusterMessages = allMessages.filter((m) => messageIds.has(m.id));

  const participantIds = new Set(clusterMessages.map((m) => m.senderId));
  const tags = [...new Set(chunks.flatMap((c) => c.tags))].slice(0, 5) as SemanticTag[];

  const clusterSummary = buildClusterSummary(chunks, label);

  const messageRefs = clusterMessages
    .sort((a, b) => (b.reactionCount + b.replyCount) - (a.reactionCount + a.replyCount))
    .slice(0, 5)
    .map((m) => ({
      id: m.id,
      preview: m.text.slice(0, 100),
      timestamp: m.timestamp.toDate(),
      senderDisplayName: m.senderDisplayName,
    }));

  const confidence = computeClusterConfidence(chunks, clusterMessages);

  const timestamps = chunks.map((c) => c.timeRange.start.getTime());
  const createdAt = new Date(Math.min(...timestamps));
  const updatedAt = new Date(Math.max(...chunks.map((c) => c.timeRange.end.getTime())));

  return {
    id: uuidv4(),
    title: label,
    summary: clusterSummary,
    tags,
    messageCount: clusterMessages.length,
    participantCount: participantIds.size,
    confidence,
    messageRefs,
    createdAt,
    updatedAt,
  };
}

// MARK: - Cluster Summary (rule-based, no LLM)

function buildClusterSummary(chunks: CompressedChunk[], label: string): string {
  const participantNames = [
    ...new Set(chunks.flatMap((c) => c.participantDisplayNames)),
  ].slice(0, 4);

  const nameStr = participantNames.join(", ");
  const more = participantNames.length >= 4 ? " and others" : "";
  const messageCount = chunks.reduce((s, c) => s + c.messageIds.length, 0);

  const topChunk = [...chunks].sort(
    (a, b) => b.messageIds.length - a.messageIds.length
  )[0];

  return `${messageCount} messages from ${nameStr}${more}. ${topChunk?.summary?.slice(0, 150) ?? ""}`;
}

// MARK: - Confidence

function computeClusterConfidence(
  chunks: CompressedChunk[],
  messages: RawMessage[]
): number {
  let score = 0.5;
  if (chunks.length >= 2) score += 0.1;
  if (messages.length >= 5) score += 0.1;

  // Higher engagement = higher confidence
  const avgEngagement =
    messages.reduce((s, m) => s + m.reactionCount + m.replyCount, 0) /
    Math.max(messages.length, 1);
  if (avgEngagement >= 1) score += 0.1;
  if (avgEngagement >= 3) score += 0.1;

  return Math.min(score, 0.9);
}

// MARK: - Org-Type Cluster Labels

export function getOrgSpecificClusterLabels(orgType: string): Array<{ tags: SemanticTag[]; label: string }> {
  const churchLabels: Array<{ tags: SemanticTag[]; label: string }> = [
    { tags: ["prayer_request", "encouragement"], label: "Prayer Momentum" },
    { tags: ["announcement"], label: "Ministry Announcements" },
    { tags: ["teaching_moment"], label: "Scripture & Study" },
    { tags: ["decision", "consensus"], label: "Leadership Decisions" },
    { tags: ["task", "reminder"], label: "Service Follow-Ups" },
  ];

  const schoolLabels: Array<{ tags: SemanticTag[]; label: string }> = [
    { tags: ["question"], label: "Assignment Questions" },
    { tags: ["teaching_moment"], label: "Lesson Highlights" },
    { tags: ["task", "reminder"], label: "Homework & Deadlines" },
    { tags: ["announcement"], label: "Class Announcements" },
    { tags: ["decision"], label: "Group Project Decisions" },
  ];

  const businessLabels: Array<{ tags: SemanticTag[]; label: string }> = [
    { tags: ["decision", "consensus"], label: "Strategic Decisions" },
    { tags: ["blocker"], label: "Blockers & Issues" },
    { tags: ["task", "reminder"], label: "Action Items" },
    { tags: ["announcement"], label: "Team Updates" },
    { tags: ["question"], label: "Open Questions" },
  ];

  switch (orgType) {
    case "church": case "ministry": case "prayer_group": return churchLabels;
    case "school": case "study_group": return schoolLabels;
    case "business": case "enterprise": case "operational_team": return businessLabels;
    default: return SEMANTIC_MERGE_MAP;
  }
}
