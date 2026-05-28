// conversationCompressionEngine.ts
// AMEN Conversation OS — Message Compression Pipeline
//
// Core safety rule: NEVER send full raw message history to LLMs.
// Pipeline: retrieve → rank → compress into chunks → summarize chunks.
// Token budget enforced strictly before any LLM call.

import { RawMessage, CompressedChunk, SemanticTag, LLMBudget, DEFAULT_SUMMARY_BUDGET } from "./types";
import { v4 as uuidv4 } from "uuid";

const MAX_CHUNK_MESSAGES = 25;
const MAX_MESSAGE_PREVIEW_CHARS = 200;
const TARGET_TOKENS_PER_CHUNK = 800;

// MARK: - Entry Point

export function compressMessages(
  messages: RawMessage[],
  budget: LLMBudget = DEFAULT_SUMMARY_BUDGET
): CompressedChunk[] {
  if (messages.length === 0) return [];

  // Sort chronologically
  const sorted = [...messages].sort(
    (a, b) => a.timestamp.toMillis() - b.timestamp.toMillis()
  );

  // Split into time-window batches
  const batches = splitIntoTimeBatches(sorted);

  // Compress each batch into a chunk
  return batches.map((batch) => compressBatch(batch, budget));
}

// MARK: - Time Window Batching (semantic-first, not purely chronological)

function splitIntoTimeBatches(messages: RawMessage[]): RawMessage[][] {
  const batches: RawMessage[][] = [];
  let current: RawMessage[] = [];

  for (const msg of messages) {
    current.push(msg);
    if (current.length >= MAX_CHUNK_MESSAGES) {
      batches.push(current);
      current = [];
    }
  }
  if (current.length > 0) batches.push(current);

  return batches;
}

// MARK: - Batch → CompressedChunk

function compressBatch(batch: RawMessage[], budget: LLMBudget): CompressedChunk {
  const tags = extractTagsFromBatch(batch);
  const participantNames = extractParticipants(batch);
  const sentiment = detectSentiment(batch);
  const summary = buildChunkSummary(batch, tags);

  const start = batch[0].timestamp.toDate();
  const end = batch[batch.length - 1].timestamp.toDate();

  return {
    id: uuidv4(),
    summary,
    messageIds: batch.map((m) => m.id),
    tags,
    timeRange: { start, end },
    tokenCount: estimateTokens(summary),
    participantDisplayNames: participantNames,
    sentiment,
  };
}

// MARK: - Tag Extraction

function extractTagsFromBatch(messages: RawMessage[]): SemanticTag[] {
  const tagCounts: Partial<Record<SemanticTag, number>> = {};

  for (const msg of messages) {
    // Explicit tags already classified (e.g. from prior triage)
    for (const tag of msg.tags ?? []) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }

    // Heuristic keyword detection
    const text = msg.text.toLowerCase();
    if (/\bdecide[d]?\b|\bapprove[d]?\b|\bagreed?\b/.test(text)) tagCounts.decision = (tagCounts.decision ?? 0) + 1;
    if (/\?/.test(text)) tagCounts.question = (tagCounts.question ?? 0) + 1;
    if (/\btask\b|\btodo\b|\bassign\b|\bdo this\b/.test(text)) tagCounts.task = (tagCounts.task ?? 0) + 1;
    if (/\bpray\b|\bprayer\b|\bpraise\b/.test(text)) tagCounts.prayer_request = (tagCounts.prayer_request ?? 0) + 1;
    if (/\bblocked?\b|\bcan't proceed\b|\bwaiting on\b/.test(text)) tagCounts.blocker = (tagCounts.blocker ?? 0) + 1;
    if (/\bremind\b|\bdon't forget\b|\bfollow[- ]?up\b/.test(text)) tagCounts.reminder = (tagCounts.reminder ?? 0) + 1;
    if (/\bannounce\b|\bfyi\b|\bheads[- ]?up\b/.test(text)) tagCounts.announcement = (tagCounts.announcement ?? 0) + 1;
    if (/\bcongrat\b|\bthank[s]?\b|\bgreat work\b|\bwell done\b/.test(text)) tagCounts.encouragement = (tagCounts.encouragement ?? 0) + 1;
    if (/\beveryone agrees?\b|\bconsensus\b/.test(text)) tagCounts.consensus = (tagCounts.consensus ?? 0) + 1;
  }

  // Return tags that appear in at least 1 message, sorted by frequency
  return (Object.entries(tagCounts) as [SemanticTag, number][])
    .filter(([, count]) => count >= 1)
    .sort(([, a], [, b]) => b - a)
    .map(([tag]) => tag)
    .slice(0, 5); // Cap at 5 tags per chunk
}

// MARK: - Participant Extraction

function extractParticipants(messages: RawMessage[]): string[] {
  const seen = new Set<string>();
  const names: string[] = [];
  for (const msg of messages) {
    if (!seen.has(msg.senderId)) {
      seen.add(msg.senderId);
      names.push(msg.senderDisplayName);
    }
  }
  return names.slice(0, 10); // Cap display names per chunk
}

// MARK: - Sentiment Detection

function detectSentiment(messages: RawMessage[]): CompressedChunk["sentiment"] {
  let urgentScore = 0;
  let negativeScore = 0;
  let positiveScore = 0;

  for (const msg of messages) {
    const text = msg.text.toLowerCase();
    if (/urgent|asap|emergency|critical|blocked/.test(text)) urgentScore++;
    if (/problem|issue|fail|error|wrong|bad|sorry/.test(text)) negativeScore++;
    if (/great|awesome|love|thank|congrat|yes|perfect/.test(text)) positiveScore++;
  }

  if (urgentScore > 0) return "urgent";
  if (negativeScore > positiveScore) return "negative";
  if (positiveScore > negativeScore) return "positive";
  return "neutral";
}

// MARK: - Chunk Summary Builder (rule-based, no LLM — used to build compressed context)

function buildChunkSummary(messages: RawMessage[], tags: SemanticTag[]): string {
  const participantNames = extractParticipants(messages);
  const nameStr = participantNames.slice(0, 3).join(", ");
  const more = participantNames.length > 3 ? ` +${participantNames.length - 3}` : "";
  const tagStr = tags.slice(0, 3).join(", ") || "general";

  // Take the most-engaged messages (by reaction + reply count)
  const top = [...messages]
    .sort((a, b) => (b.reactionCount + b.replyCount) - (a.reactionCount + a.replyCount))
    .slice(0, 5);

  const previews = top
    .map((m) => `${m.senderDisplayName}: ${truncate(m.text, MAX_MESSAGE_PREVIEW_CHARS)}`)
    .join(" | ");

  return `[${tagStr}] ${nameStr}${more}: ${previews}`;
}

// MARK: - Token Estimation (rough 4 chars/token heuristic)

function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

export function estimateTotalTokens(chunks: CompressedChunk[]): number {
  return chunks.reduce((sum, c) => sum + c.tokenCount, 0);
}

export function fitChunksTobudget(chunks: CompressedChunk[], maxTokens: number): CompressedChunk[] {
  let total = 0;
  const result: CompressedChunk[] = [];
  // Prioritize most recent chunks
  for (const chunk of [...chunks].reverse()) {
    if (total + chunk.tokenCount > maxTokens) break;
    result.unshift(chunk);
    total += chunk.tokenCount;
  }
  return result;
}

// MARK: - Utility

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max).trimEnd() + "…";
}
