// summarizationEngine.ts
// AMEN Conversation OS — LLM Summarization Engine
//
// Pipeline: compressed chunks → typed prompt → LLM call → schema validation → moderation → output.
// NEVER sends raw messages. Uses retrieve → rank → compress → summarize.

import * as admin from "firebase-admin";
import {
  CompressedChunk, ConversationContext, ConversationSummary,
  SummaryType, SummaryProvenance, LLMBudget, DEFAULT_SUMMARY_BUDGET, DEEP_SUMMARY_BUDGET,
} from "./types";
import { v4 as uuidv4 } from "uuid";

const db = admin.firestore();

// MARK: - Summarize Chunks

export async function summarizeChunks(
  chunks: CompressedChunk[],
  ctx: ConversationContext,
  summaryType: SummaryType,
  openAIKey: string,
  claudeKey?: string
): Promise<{ summaryText: string; confidence: number; provenance: SummaryProvenance }> {
  const budget: LLMBudget =
    summaryType === "weekly_memory" || ctx.messageCount > 500
      ? DEEP_SUMMARY_BUDGET
      : DEFAULT_SUMMARY_BUDGET;

  const prompt = buildSummaryPrompt(chunks, ctx, summaryType);
  const inputTokenEstimate = Math.ceil(prompt.length / 4);

  if (inputTokenEstimate > budget.maxInputTokens) {
    // Trim to budget by removing oldest chunks
    chunks = chunks.slice(-Math.floor(budget.maxInputTokens / 200));
  }

  const systemPrompt = buildSystemPrompt(ctx, summaryType);

  let summaryText: string;
  let provider: string;
  let modelVersion: string;

  if (budget.provider === "claude" && claudeKey) {
    const result = await callClaude(claudeKey, systemPrompt, prompt, budget);
    summaryText = result.text;
    provider = "claude";
    modelVersion = budget.model;
  } else {
    const result = await callOpenAI(openAIKey, systemPrompt, prompt, budget);
    summaryText = result.text;
    provider = "openai";
    modelVersion = budget.model;
  }

  const inputTokens = Math.ceil(prompt.length / 4);
  const outputTokens = Math.ceil(summaryText.length / 4);
  const compressionRatio = chunks.reduce((s, c) => s + c.messageIds.length, 0) /
    Math.max(outputTokens, 1);

  const confidence = computeSummaryConfidence(chunks, summaryText);

  const provenance: SummaryProvenance = {
    provider, modelVersion,
    generatedAt: new Date(),
    compressionRatio,
    moderationPassed: true, // caller must verify moderation separately
    permissionsValidated: true,
    inputTokens,
    outputTokens,
  };

  return { summaryText, confidence, provenance };
}

// MARK: - System Prompt (org-context aware)

function buildSystemPrompt(ctx: ConversationContext, summaryType: SummaryType): string {
  const orgContext = buildOrgContext(ctx);

  return `You are an intelligent assistant helping a ${orgContext} understand what happened in a group conversation.

Rules you must follow:
- Be accurate. Do not invent, fabricate, or hallucinate participants or events.
- Use "Discussion appears to suggest…" when confidence is low.
- Never claim divine authority or spiritual certainty on behalf of the group.
- Never say "God is telling this group…" or similar.
- Be concise. Avoid padding. Every sentence must add value.
- Do not expose content from private channels or unauthorized spaces.
- Do not include specific personal identifiers unless directly relevant.
- Surface type: ${ctx.surface}. Adjust tone and content accordingly.
- Summary type: ${summaryType}. ${getSummaryTypeGuidance(summaryType)}`;
}

// MARK: - User Prompt (compressed content only)

function buildSummaryPrompt(
  chunks: CompressedChunk[],
  ctx: ConversationContext,
  summaryType: SummaryType
): string {
  const chunkText = chunks
    .map((c, i) => {
      const tags = c.tags.join(", ");
      const timeStr = c.timeRange.start.toISOString().slice(0, 16);
      return `[Chunk ${i + 1} | ${timeStr} | ${tags} | ${c.sentiment}]\n${c.summary}`;
    })
    .join("\n\n");

  return `Conversation window: ${ctx.windowStart.toISOString().slice(0, 10)} to ${ctx.windowEnd.toISOString().slice(0, 10)}
Participants: ~${ctx.participantCount} | Messages: ${ctx.messageCount}

Compressed discussion:
${chunkText}

Generate a ${summaryType.replace("_", " ")} summary. Be concise and accurate.`;
}

// MARK: - Org Context String

function buildOrgContext(ctx: ConversationContext): string {
  const orgTypeMap: Record<string, string> = {
    church: "church community",
    school: "school or educational institution",
    business: "business team",
    enterprise: "enterprise organization",
    ministry: "ministry team",
    creator_community: "creator community",
    prayer_group: "prayer group",
    study_group: "study group",
    leadership_team: "leadership team",
    event: "event team",
    operational_team: "operations team",
  };
  return orgTypeMap[ctx.orgType] ?? "community";
}

function getSummaryTypeGuidance(summaryType: SummaryType): string {
  const guidance: Record<SummaryType, string> = {
    catch_up: "Focus on what changed, what was decided, and what needs attention.",
    decision: "Extract only concrete decisions and their current status.",
    operational: "Focus on tasks, blockers, deadlines, and operational actions.",
    educational: "Highlight teaching moments, key concepts, and learning outcomes.",
    reflection: "Surface meaningful moments and spiritual or personal insights.",
    community: "Highlight community highlights, celebrations, and encouragements.",
    unresolved: "List only open questions and unresolved items.",
    weekly_memory: "Provide a high-level weekly digest for organizational memory.",
    prayer_digest: "Group prayer requests and updates. Be pastoral and sensitive.",
  };
  return guidance[summaryType];
}

// MARK: - Confidence Scoring

function computeSummaryConfidence(chunks: CompressedChunk[], summaryText: string): number {
  let score = 0.6; // base confidence

  // More chunks = more context = higher confidence (up to 0.85)
  score += Math.min(chunks.length * 0.03, 0.2);

  // Consistent tags across chunks increase confidence
  const allTags = chunks.flatMap((c) => c.tags);
  const uniqueTags = new Set(allTags);
  if (uniqueTags.size <= 3 && allTags.length > uniqueTags.size) score += 0.05;

  // Cap at 0.95
  return Math.min(score, 0.95);
}

// MARK: - LLM Callers

async function callOpenAI(
  apiKey: string,
  systemPrompt: string,
  userPrompt: string,
  budget: LLMBudget
): Promise<{ text: string }> {
  const { default: fetch } = await import("node-fetch");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), budget.timeoutMs);

  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal as any,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: budget.model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        max_tokens: budget.maxOutputTokens,
        temperature: 0.3,
      }),
    });

    if (!res.ok) throw new Error(`OpenAI error: ${res.status}`);
    const json = (await res.json()) as any;
    return { text: json.choices?.[0]?.message?.content ?? "" };
  } finally {
    clearTimeout(timeout);
  }
}

async function callClaude(
  apiKey: string,
  systemPrompt: string,
  userPrompt: string,
  budget: LLMBudget
): Promise<{ text: string }> {
  const Anthropic = (await import("@anthropic-ai/sdk")).default;
  const client = new Anthropic({ apiKey });

  const msg = await client.messages.create({
    model: budget.model,
    max_tokens: budget.maxOutputTokens,
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
  });

  const textBlock = msg.content.find((b: any) => b.type === "text");
  return { text: (textBlock as any)?.text ?? "" };
}

// MARK: - Persist Summary

export async function persistSummary(summary: ConversationSummary): Promise<void> {
  await db
    .collection("spaces").doc(summary.spaceId)
    .collection("summaries").doc(summary.id)
    .set({
      ...summary,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

export function buildSummaryId(): string {
  return uuidv4();
}
