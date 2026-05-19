/**
 * creationAI.ts
 *
 * AI-powered creation assistance callables:
 *   suggestCreationVerses, improveCreationCaption,
 *   suggestCreationHashtags, generateCreationOutline
 *
 * Uses raw fetch to Anthropic REST API (matches codebase pattern — no @anthropic-ai/sdk).
 * Claude Haiku for low-latency creation assistance.
 */

import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const HAIKU_MODEL = "claude-haiku-4-5-20251001";

// ---------------------------------------------------------------------------
// Auth helper
// ---------------------------------------------------------------------------

function requireAuth(request: CallableRequest): string {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  return request.auth.uid;
}

// ---------------------------------------------------------------------------
// Anthropic fetch helper
// ---------------------------------------------------------------------------

async function callAnthropic(
  apiKey: string,
  prompt: string,
  maxTokens = 300
): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: HAIKU_MODEL,
      max_tokens: maxTokens,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new HttpsError("internal", `Anthropic error: ${err.slice(0, 200)}`);
  }
  const data = (await response.json()) as {
    content?: Array<{ type: string; text: string }>;
  };
  return data.content?.find((b) => b.type === "text")?.text ?? "";
}

// ---------------------------------------------------------------------------
// suggestCreationVerses
// Returns up to 3 relevant scripture references for the draft content.
// ---------------------------------------------------------------------------

export const suggestCreationVerses = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true },
  async (request: CallableRequest) => {
    requireAuth(request);
    const { text = "", intent = "textPost" } = (request.data ?? {}) as {
      text?: string;
      intent?: string;
    };
    if (!text || text.trim().length < 30) {
      return { verses: [] };
    }
    const prompt = `You are a biblical scholar assistant for a Christian social app.
The user is writing a ${intent.replace("_", " ")} post with this draft:
"${text.slice(0, 400)}"

Return ONLY a JSON array of up to 3 objects with keys:
  "reference" (e.g. "Romans 8:28"), "snippet" (15 words max from the verse), "reason" (why it fits, 10 words max).

Return valid JSON only. No markdown, no explanation.`;

    const raw = await callAnthropic(anthropicApiKey.value(), prompt, 300);
    let verses: Array<{ reference: string; snippet: string; reason: string }> = [];
    try {
      const match = raw.match(/\[[\s\S]*\]/);
      if (match) verses = JSON.parse(match[0]);
    } catch {
      logger.warn("suggestCreationVerses: JSON parse failed", { raw: raw.slice(0, 100) });
    }
    return { verses };
  }
);

// ---------------------------------------------------------------------------
// improveCreationCaption
// Returns an improved caption written in a spiritually warm voice.
// ---------------------------------------------------------------------------

export const improveCreationCaption = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true },
  async (request: CallableRequest) => {
    requireAuth(request);
    const { caption = "", mediaType = "photo" } = (request.data ?? {}) as {
      caption?: string;
      mediaType?: string;
    };
    if (!caption || caption.trim().length < 5) {
      return { improved: null };
    }
    const prompt = `You are a Christian content creation assistant.
Improve this ${mediaType} caption to be warmer, more compelling, and faith-forward.
Keep it under 140 characters. Return only the improved caption text — no quotes, no explanation.

Original caption: "${caption.slice(0, 200)}"`;

    const improved = (await callAnthropic(anthropicApiKey.value(), prompt, 160)).trim();
    return { improved: improved || null };
  }
);

// ---------------------------------------------------------------------------
// suggestCreationHashtags
// Returns 5–8 on-brand Christian hashtags.
// ---------------------------------------------------------------------------

export const suggestCreationHashtags = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true },
  async (request: CallableRequest) => {
    requireAuth(request);
    const { text = "", intent = "textPost" } = (request.data ?? {}) as {
      text?: string;
      intent?: string;
    };
    if (!text || text.trim().length < 20) {
      return { hashtags: [] };
    }
    const prompt = `You are a Christian social media assistant.
Given this ${intent} post draft, return 5–8 relevant Christian hashtags as a JSON array of strings (e.g. ["#faith", "#prayer"]).
No # is required — add it yourself. No markdown, no explanation — return JSON array only.

Post: "${text.slice(0, 300)}"`;

    const raw = await callAnthropic(anthropicApiKey.value(), prompt, 120);
    let hashtags: string[] = [];
    try {
      const match = raw.match(/\[[\s\S]*?\]/);
      if (match) hashtags = JSON.parse(match[0]);
    } catch {
      logger.warn("suggestCreationHashtags: JSON parse failed");
    }
    return { hashtags: hashtags.slice(0, 8) };
  }
);

// ---------------------------------------------------------------------------
// generateCreationOutline
// Returns a structured outline for long-form posts and notes.
// ---------------------------------------------------------------------------

export const generateCreationOutline = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true },
  async (request: CallableRequest) => {
    requireAuth(request);
    const { topic = "", intent = "note" } = (request.data ?? {}) as {
      topic?: string;
      intent?: string;
    };
    if (!topic || topic.trim().length < 5) {
      return { outline: [] };
    }
    const prompt = `You are a Christian content creation assistant.
Create a 4–6 point outline for a ${intent} about: "${topic.slice(0, 200)}".
Return ONLY a JSON array of short strings — each is one outline point (max 8 words each).
No markdown, no explanation.`;

    const raw = await callAnthropic(anthropicApiKey.value(), prompt, 200);
    let outline: string[] = [];
    try {
      const match = raw.match(/\[[\s\S]*?\]/);
      if (match) outline = JSON.parse(match[0]);
    } catch {
      logger.warn("generateCreationOutline: JSON parse failed");
    }
    return { outline: outline.slice(0, 6) };
  }
);
