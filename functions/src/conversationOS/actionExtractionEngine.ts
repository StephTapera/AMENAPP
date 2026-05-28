// actionExtractionEngine.ts
// AMEN Conversation OS — Action, Decision & Unresolved Question Extraction
//
// Extracts typed structured outputs from compressed chunks.
// All extraction is rule-based + optional LLM refinement.
// Never fabricates assignments — only extracts what was explicitly stated.

import {
  CompressedChunk, RawMessage, ActionItem, Decision, UnresolvedQuestion, Blocker,
} from "./types";
import { v4 as uuidv4 } from "uuid";

// MARK: - Action Extraction

export function extractActions(
  messages: RawMessage[],
  chunks: CompressedChunk[],
  threadId: string
): ActionItem[] {
  const actions: ActionItem[] = [];

  for (const msg of messages) {
    const text = msg.text;
    const lower = text.toLowerCase();

    // Task assignment patterns
    const taskPatterns = [
      /(?:can you|please|could you|i need you to|will you)\s+(.+?)(?:\.|$)/i,
      /(?:action item|todo|to-do|task):\s*(.+?)(?:\.|$)/i,
      /(?:@\w+)\s+(?:please|can you|could you)\s+(.+?)(?:\.|$)/i,
    ];

    for (const pattern of taskPatterns) {
      const match = text.match(pattern);
      if (match) {
        const description = match[1]?.trim();
        if (!description || description.length < 5) continue;

        const assigneeInfo = extractMentionedAssignee(text, messages);
        const dueDate = extractDueDate(text);
        const confidence = computeActionConfidence(msg, lower);

        actions.push({
          id: uuidv4(),
          title: truncate(description, 80),
          description,
          assigneeId: assigneeInfo?.id,
          assigneeDisplayName: assigneeInfo?.name,
          dueDate,
          sourceMessageId: msg.id,
          threadId,
          status: "pending",
          confidence,
          createdAt: msg.timestamp.toDate(),
        });
        break; // One action per message
      }
    }
  }

  // Deduplicate by similar title
  return deduplicateActions(actions).slice(0, 10);
}

// MARK: - Decision Extraction

export function extractDecisions(
  messages: RawMessage[],
  threadId: string
): Decision[] {
  const decisions: Decision[] = [];

  for (const msg of messages) {
    const text = msg.text;
    const lower = text.toLowerCase();

    const decisionPatterns = [
      /(?:we've? decided|we're going with|final decision|agreed:?|approved:?)\s*:?\s*(.+?)(?:\.|$)/i,
      /(?:decision|decided|agreed|confirmed|approved):\s*(.+?)(?:\.|$)/i,
      /(?:let's go with|we'll do|we'll use)\s+(.+?)(?:\.|$)/i,
    ];

    for (const pattern of decisionPatterns) {
      const match = text.match(pattern);
      if (match) {
        const summary = match[1]?.trim();
        if (!summary || summary.length < 5) continue;

        const confidence = computeDecisionConfidence(msg, lower);

        decisions.push({
          id: uuidv4(),
          summary: truncate(summary, 120),
          sourceSnippet: truncate(text, 200),
          participants: [msg.senderId],
          confirmedBy: [],
          status: "proposed",
          threadId,
          confidence,
          createdAt: msg.timestamp.toDate(),
        });
        break;
      }
    }
  }

  return deduplicateDecisions(decisions).slice(0, 8);
}

// MARK: - Unresolved Question Extraction

export function extractUnresolvedQuestions(
  messages: RawMessage[],
  threadId: string
): UnresolvedQuestion[] {
  const questions: UnresolvedQuestion[] = [];
  const answeredQuestionIds = new Set<string>();

  // First pass: find all questions
  const questionMessages = messages.filter((m) => {
    const text = m.text.trim();
    return (
      text.endsWith("?") ||
      /^(what|when|where|who|why|how|can|could|should|is|are|does|do)\b/i.test(text)
    );
  });

  // Second pass: check if they were answered (a reply in the thread followed shortly after)
  for (const qMsg of questionMessages) {
    const qTime = qMsg.timestamp.toMillis();
    const hasAnswer = messages.some(
      (m) =>
        m.senderId !== qMsg.senderId &&
        m.timestamp.toMillis() > qTime &&
        m.timestamp.toMillis() < qTime + 30 * 60 * 1000 && // within 30 min
        m.replyCount === 0 // not itself a question
    );

    if (!hasAnswer && !answeredQuestionIds.has(qMsg.id)) {
      questions.push({
        id: uuidv4(),
        question: truncate(qMsg.text, 200),
        sourceSnippet: truncate(qMsg.text, 200),
        askedByDisplayName: qMsg.senderDisplayName,
        threadId,
        askedAt: qMsg.timestamp.toDate(),
      });
    }
  }

  return questions.slice(0, 8);
}

// MARK: - Blocker Extraction

export function extractBlockers(
  messages: RawMessage[],
  threadId: string
): Blocker[] {
  const blockers: Blocker[] = [];

  for (const msg of messages) {
    const lower = msg.text.toLowerCase();
    const blockerPatterns = [
      /blocked?\s+(?:by|on)\s+(.+?)(?:\.|$)/i,
      /(?:can't|cannot|unable to)\s+(?:proceed|continue|move forward)\s*(?:because|until)?\s*(.+?)(?:\.|$)/i,
      /(?:waiting (?:for|on))\s+(.+?)(?:before|to|\.)/i,
      /(?:blocker|blocking issue):\s*(.+?)(?:\.|$)/i,
    ];

    for (const pattern of blockerPatterns) {
      const match = msg.text.match(pattern);
      if (match) {
        const description = match[1]?.trim();
        if (!description || description.length < 5) continue;

        blockers.push({
          id: uuidv4(),
          description: truncate(description, 200),
          sourceSnippet: truncate(msg.text, 200),
          threadId,
          confidence: 0.7,
          detectedAt: msg.timestamp.toDate(),
        });
        break;
      }
    }
  }

  return blockers.slice(0, 5);
}

// MARK: - Assignee Extraction

function extractMentionedAssignee(
  text: string,
  messages: RawMessage[]
): { id: string; name: string } | null {
  const mentionMatch = text.match(/@(\w+)/);
  if (!mentionMatch) return null;

  const mentionedName = mentionMatch[1].toLowerCase();
  const matchedMsg = messages.find(
    (m) => m.senderDisplayName.toLowerCase().startsWith(mentionedName)
  );
  if (!matchedMsg) return null;

  return { id: matchedMsg.senderId, name: matchedMsg.senderDisplayName };
}

// MARK: - Due Date Extraction

function extractDueDate(text: string): Date | undefined {
  const lower = text.toLowerCase();
  const now = new Date();

  if (/by tomorrow/.test(lower)) {
    const d = new Date(now);
    d.setDate(d.getDate() + 1);
    return d;
  }
  if (/by end of week|by friday|this friday/.test(lower)) {
    const d = new Date(now);
    const day = d.getDay();
    d.setDate(d.getDate() + (5 - day));
    return d;
  }
  if (/by monday|next monday/.test(lower)) {
    const d = new Date(now);
    d.setDate(d.getDate() + ((1 + 7 - d.getDay()) % 7 || 7));
    return d;
  }
  if (/asap|urgent|immediately/.test(lower)) {
    return new Date(now.getTime() + 24 * 60 * 60 * 1000);
  }

  return undefined;
}

// MARK: - Confidence Scoring

function computeActionConfidence(msg: RawMessage, lower: string): number {
  let score = 0.5;
  if (/\b(must|need to|have to|required)\b/.test(lower)) score += 0.2;
  if (/\b(please|could you|can you)\b/.test(lower)) score += 0.15;
  if (msg.replyCount > 0) score += 0.1;
  if (/@\w+/.test(msg.text)) score += 0.1;
  return Math.min(score, 0.9);
}

function computeDecisionConfidence(msg: RawMessage, lower: string): number {
  let score = 0.5;
  if (/\b(agreed|approved|confirmed|final)\b/.test(lower)) score += 0.25;
  if (msg.reactionCount >= 3) score += 0.1;
  if (msg.replyCount >= 2) score += 0.1;
  return Math.min(score, 0.9);
}

// MARK: - Deduplication

function deduplicateActions(actions: ActionItem[]): ActionItem[] {
  const seen = new Set<string>();
  return actions.filter((a) => {
    const key = a.title.slice(0, 40).toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function deduplicateDecisions(decisions: Decision[]): Decision[] {
  const seen = new Set<string>();
  return decisions.filter((d) => {
    const key = d.summary.slice(0, 40).toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// MARK: - Utility

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max).trimEnd() + "…";
}
