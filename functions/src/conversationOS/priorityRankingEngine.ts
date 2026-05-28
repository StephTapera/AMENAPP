// priorityRankingEngine.ts
// AMEN Conversation OS — Priority Ranking Engine
//
// Scores and ranks signals to answer: "What should this user care about?"
// Inputs: mentions, replies, reactions, thread velocity, leadership participation,
// emotional urgency, repeated topic emergence, event proximity, role relevance.

import { PrioritySignal, RawMessage, UserRole, ConversationOSSurface, Urgency } from "./types";
import { v4 as uuidv4 } from "uuid";

// MARK: - Entry Point

export function rankPrioritySignals(
  messages: RawMessage[],
  userId: string,
  userRole: UserRole,
  surface: ConversationOSSurface,
  spaceId: string,
  threadId: string
): PrioritySignal[] {
  const signals: PrioritySignal[] = [];

  // 1. Direct mentions
  const mentionSignals = detectMentions(messages, userId, threadId, spaceId);
  signals.push(...mentionSignals);

  // 2. Unresolved questions from the user
  const questionSignals = detectUnansweredUserQuestions(messages, userId, threadId, spaceId);
  signals.push(...questionSignals);

  // 3. High-velocity threads (rapid messages = urgency)
  const velocitySignal = detectHighVelocity(messages, threadId, spaceId);
  if (velocitySignal) signals.push(velocitySignal);

  // 4. Leadership participation (signals importance to the group)
  const leaderSignal = detectLeadershipParticipation(messages, userRole, threadId, spaceId);
  if (leaderSignal) signals.push(leaderSignal);

  // 5. Repeated topic emergence
  const topicSignals = detectRepeatedTopics(messages, threadId, spaceId);
  signals.push(...topicSignals);

  // 6. Consensus forming
  const consensusSignal = detectConsensusForming(messages, threadId, spaceId);
  if (consensusSignal) signals.push(consensusSignal);

  // Score, filter by role relevance, sort
  return signals
    .map((s) => ({ ...s, score: computeScore(s, userRole) }))
    .filter((s) => s.score > 0.3)
    .sort((a, b) => b.score - a.score)
    .slice(0, 10);
}

// MARK: - Mention Detection

function detectMentions(
  messages: RawMessage[],
  userId: string,
  threadId: string,
  spaceId: string
): PrioritySignal[] {
  return messages
    .filter((m) => m.senderId !== userId && m.text.includes(`@${userId}`))
    .slice(0, 3)
    .map((m) => ({
      id: uuidv4(),
      type: "mention" as const,
      title: "You were mentioned",
      description: `${m.senderDisplayName}: "${m.text.slice(0, 80)}"`,
      urgency: "high" as Urgency,
      threadId,
      spaceId,
      relevantToRoles: ["group_member", "admin", "moderator"] as UserRole[],
      score: 0.9,
      createdAt: m.timestamp.toDate(),
    }));
}

// MARK: - Unanswered User Questions

function detectUnansweredUserQuestions(
  messages: RawMessage[],
  userId: string,
  threadId: string,
  spaceId: string
): PrioritySignal[] {
  const userQuestions = messages.filter(
    (m) => m.senderId === userId && (m.text.endsWith("?") || /^(what|when|how|who|why|can|should)/i.test(m.text))
  );

  return userQuestions
    .filter((q) => {
      const qTime = q.timestamp.toMillis();
      return !messages.some(
        (m) => m.senderId !== userId && m.timestamp.toMillis() > qTime
      );
    })
    .slice(0, 2)
    .map((q) => ({
      id: uuidv4(),
      type: "unresolved_question" as const,
      title: "Your question hasn't been answered",
      description: q.text.slice(0, 100),
      urgency: "medium" as Urgency,
      threadId,
      spaceId,
      relevantToRoles: ["group_member"] as UserRole[],
      score: 0.7,
      createdAt: q.timestamp.toDate(),
    }));
}

// MARK: - High Velocity Detection

function detectHighVelocity(
  messages: RawMessage[],
  threadId: string,
  spaceId: string
): PrioritySignal | null {
  if (messages.length < 5) return null;

  const recent = messages.slice(-10);
  if (recent.length < 5) return null;

  const firstTime = recent[0].timestamp.toMillis();
  const lastTime = recent[recent.length - 1].timestamp.toMillis();
  const minuteSpan = (lastTime - firstTime) / 60000;

  // High velocity: 10+ messages in < 5 minutes
  if (recent.length >= 10 && minuteSpan < 5) {
    return {
      id: uuidv4(),
      type: "urgent_thread",
      title: "Thread moving quickly",
      description: `${recent.length} messages in ${Math.round(minuteSpan)} minutes`,
      urgency: "high",
      threadId,
      spaceId,
      relevantToRoles: ["admin", "moderator", "church_leader", "teacher"],
      score: 0.75,
      createdAt: new Date(),
    };
  }

  return null;
}

// MARK: - Leadership Participation

function detectLeadershipParticipation(
  messages: RawMessage[],
  userRole: UserRole,
  threadId: string,
  spaceId: string
): PrioritySignal | null {
  // Only surface this for non-leadership roles — it's a signal to pay attention
  if (["admin", "moderator", "church_leader", "teacher"].includes(userRole)) return null;

  // Heuristic: look for messages with leadership-indicative content
  const leadershipKeywords = /\b(important announcement|all members|as your pastor|as your leader|decision has been made|official|please note)\b/i;
  const leaderMessages = messages.filter((m) => leadershipKeywords.test(m.text));

  if (leaderMessages.length === 0) return null;

  const mostRecent = leaderMessages[leaderMessages.length - 1];
  return {
    id: uuidv4(),
    type: "action_required",
    title: "Leadership communication",
    description: `${mostRecent.senderDisplayName}: "${mostRecent.text.slice(0, 80)}"`,
    urgency: "high",
    threadId,
    spaceId,
    relevantToRoles: ["group_member", "student", "volunteer"],
    score: 0.8,
    createdAt: mostRecent.timestamp.toDate(),
  };
}

// MARK: - Repeated Topic Emergence

function detectRepeatedTopics(
  messages: RawMessage[],
  threadId: string,
  spaceId: string
): PrioritySignal[] {
  const topicCounts: Map<string, number> = new Map();

  const keywords = [
    "deadline", "meeting", "budget", "event", "prayer", "conflict",
    "schedule", "feedback", "approval", "announcement", "reminder",
  ];

  for (const msg of messages) {
    const lower = msg.text.toLowerCase();
    for (const kw of keywords) {
      if (lower.includes(kw)) {
        topicCounts.set(kw, (topicCounts.get(kw) ?? 0) + 1);
      }
    }
  }

  return Array.from(topicCounts.entries())
    .filter(([, count]) => count >= 3)
    .slice(0, 2)
    .map(([topic, count]) => ({
      id: uuidv4(),
      type: "action_required" as const,
      title: `"${topic}" mentioned ${count} times`,
      description: `This topic keeps coming up — it may need direct attention.`,
      urgency: "medium" as Urgency,
      threadId,
      spaceId,
      relevantToRoles: ["admin", "church_leader", "teacher", "business_manager"] as UserRole[],
      score: 0.5 + Math.min(count * 0.05, 0.3),
      createdAt: new Date(),
    }));
}

// MARK: - Consensus Forming

function detectConsensusForming(
  messages: RawMessage[],
  threadId: string,
  spaceId: string
): PrioritySignal | null {
  const consensusKeywords = /\b(agree|agreed|sounds good|makes sense|yes|let's do it|approved|confirmed)\b/i;
  const consensusMessages = messages.filter((m) => consensusKeywords.test(m.text));

  const senders = new Set(consensusMessages.map((m) => m.senderId));

  // Consensus forming: 3+ different people expressing agreement
  if (senders.size >= 3) {
    return {
      id: uuidv4(),
      type: "consensus_forming",
      title: "Consensus forming",
      description: `${senders.size} members appear to be in agreement. A decision may be forming.`,
      urgency: "medium",
      threadId,
      spaceId,
      relevantToRoles: ["admin", "church_leader", "moderator", "teacher", "business_manager"],
      score: 0.65,
      createdAt: new Date(),
    };
  }

  return null;
}

// MARK: - Score by Role Relevance

function computeScore(signal: PrioritySignal, userRole: UserRole): number {
  const baseScore = signal.score;
  const roleMatch = signal.relevantToRoles.includes(userRole);
  const urgencyBoost: Record<Urgency, number> = {
    low: 0, medium: 0.05, high: 0.15, critical: 0.3,
  };
  return baseScore * (roleMatch ? 1.0 : 0.6) + urgencyBoost[signal.urgency];
}
