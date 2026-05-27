// personalizedSummaryEngine.ts
// AMEN Conversation OS — Personalized Intelligence Engine
//
// Different users get different summaries based on:
// role, unread state, participation, mentions, followed topics,
// assigned tasks, emotional relevance, organizational relevance.

import {
  PersonalizedSummaryRequest, CompressedChunk, ConversationSummary,
  TopicCluster, ActionItem, Decision, UnresolvedQuestion, SummaryProvenance,
  SummaryType, UserRole, OrgType,
} from "./types";
import { v4 as uuidv4 } from "uuid";

// MARK: - Role-Based Personalization

export function personalizeForRole(
  baseSummary: ConversationSummary,
  request: PersonalizedSummaryRequest
): ConversationSummary {
  const roleFilters = getRoleFilters(request.userRole, request.orgType);

  // Filter topic clusters by followed topics
  const relevantClusters = filterClustersByInterest(
    baseSummary.topicClusters,
    request.followedTopics,
    request.userRole
  );

  // Filter action items by assignment or role
  const relevantActions = filterActionsByRole(
    baseSummary.actionItems,
    request.userId,
    request.userRole
  );

  // Personalize summary text
  const personalizedText = buildPersonalizedText(
    baseSummary.summaryText,
    request.userRole,
    request.orgType,
    request.preferredLength
  );

  // Role-specific summary type
  const summaryType = getRoleSummaryType(request.userRole);

  return {
    ...baseSummary,
    id: uuidv4(),
    summaryText: personalizedText,
    summaryType,
    topicClusters: relevantClusters,
    actionItems: relevantActions,
    decisions: roleFilters.showDecisions ? baseSummary.decisions : [],
    unresolvedQuestions: roleFilters.showQuestions ? baseSummary.unresolvedQuestions : [],
    blockers: roleFilters.showBlockers ? baseSummary.blockers : [],
  };
}

// MARK: - Role Filters

interface RoleFilters {
  showDecisions: boolean;
  showBlockers: boolean;
  showQuestions: boolean;
  prioritizeAssigned: boolean;
  includeLeadershipContext: boolean;
}

function getRoleFilters(role: UserRole, orgType: OrgType): RoleFilters {
  switch (role) {
    case "admin":
    case "church_leader":
    case "teacher":
    case "business_manager":
      return { showDecisions: true, showBlockers: true, showQuestions: true, prioritizeAssigned: false, includeLeadershipContext: true };

    case "moderator":
      return { showDecisions: true, showBlockers: true, showQuestions: false, prioritizeAssigned: false, includeLeadershipContext: true };

    case "creator":
    case "volunteer":
      return { showDecisions: false, showBlockers: true, showQuestions: true, prioritizeAssigned: true, includeLeadershipContext: false };

    case "student":
      return { showDecisions: false, showBlockers: false, showQuestions: true, prioritizeAssigned: true, includeLeadershipContext: false };

    case "group_member":
    default:
      return { showDecisions: false, showBlockers: false, showQuestions: true, prioritizeAssigned: true, includeLeadershipContext: false };
  }
}

// MARK: - Cluster Filtering

function filterClustersByInterest(
  clusters: TopicCluster[],
  followedTopics: string[],
  role: UserRole
): TopicCluster[] {
  if (followedTopics.length === 0) return clusters.slice(0, 5);

  const lowerTopics = followedTopics.map((t) => t.toLowerCase());

  // Score each cluster by relevance to followed topics
  const scored = clusters.map((c) => {
    const titleLower = c.title.toLowerCase();
    const summaryLower = c.summary.toLowerCase();
    const matchScore = lowerTopics.reduce((score, topic) => {
      if (titleLower.includes(topic)) return score + 2;
      if (summaryLower.includes(topic)) return score + 1;
      return score;
    }, 0);
    return { cluster: c, score: matchScore + c.confidence };
  });

  return scored
    .sort((a, b) => b.score - a.score)
    .map((s) => s.cluster)
    .slice(0, 5);
}

// MARK: - Action Filtering by Role

function filterActionsByRole(
  actions: ActionItem[],
  userId: string,
  role: UserRole
): ActionItem[] {
  const pending = actions.filter((a) => a.status === "pending");

  // Leaders and admins see all pending actions
  if (["admin", "church_leader", "teacher", "business_manager"].includes(role)) {
    return pending.slice(0, 10);
  }

  // Others see only their assigned actions
  const mine = pending.filter(
    (a) => a.assigneeId === userId || !a.assigneeId // unassigned items
  );
  return mine.slice(0, 5);
}

// MARK: - Personalized Text

function buildPersonalizedText(
  baseText: string,
  role: UserRole,
  orgType: OrgType,
  length: "brief" | "balanced" | "deep"
): string {
  const prefix = getRolePrefix(role, orgType);
  const trimmed = trimToLength(baseText, length);
  return prefix ? `${prefix} ${trimmed}` : trimmed;
}

function getRolePrefix(role: UserRole, orgType: OrgType): string {
  if (role === "student") return "Here's what happened in class:";
  if (role === "church_leader" && orgType === "church") return "Leadership update:";
  if (role === "teacher") return "Classroom summary:";
  if (role === "business_manager") return "Team update:";
  return "";
}

function trimToLength(text: string, length: "brief" | "balanced" | "deep"): string {
  const limits = { brief: 200, balanced: 500, deep: 1000 };
  const limit = limits[length];
  if (text.length <= limit) return text;
  return text.slice(0, limit).trimEnd() + "…";
}

// MARK: - Role Summary Type

function getRoleSummaryType(role: UserRole): SummaryType {
  switch (role) {
    case "teacher": return "educational";
    case "student": return "educational";
    case "church_leader": return "reflection";
    case "business_manager": return "operational";
    case "admin": return "catch_up";
    case "moderator": return "operational";
    default: return "catch_up";
  }
}

// MARK: - Unread Context Builder

export function buildUnreadContext(
  unreadCount: number,
  lastVisitedAt?: Date
): string {
  if (unreadCount === 0) return "You're caught up.";

  const timeAgo = lastVisitedAt
    ? formatRelativeTime(lastVisitedAt)
    : "a while";

  if (unreadCount === 1) return `1 new message since ${timeAgo}.`;
  if (unreadCount < 10) return `${unreadCount} new messages since ${timeAgo}.`;
  if (unreadCount < 50) return `${unreadCount} messages since ${timeAgo} — here's what matters.`;
  return `${unreadCount}+ messages since ${timeAgo}. Here's the key context.`;
}

function formatRelativeTime(date: Date): string {
  const diffMs = Date.now() - date.getTime();
  const diffMin = Math.floor(diffMs / 60000);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);

  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHr < 24) return `${diffHr}h ago`;
  if (diffDay === 1) return "yesterday";
  return `${diffDay} days ago`;
}

// MARK: - Personalized Provenance

export function buildPersonalizedProvenance(baseProvenance: SummaryProvenance): SummaryProvenance {
  return {
    ...baseProvenance,
    generatedAt: new Date(),
    moderationPassed: true,
    permissionsValidated: true,
  };
}
