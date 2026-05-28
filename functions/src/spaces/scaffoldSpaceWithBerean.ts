// scaffoldSpaceWithBerean.ts
// AMEN Spaces — Cloud Function: AI Space Scaffolding via Berean
//
// Callable: { type: "chat"|"bibleStudy"|"group", title: string, communityContext?: string }
//
// Flow:
//   1. Auth + App Check enforcement.
//   2. Rate limit: 10 calls / user / hour (Firestore-backed transaction counter).
//   3. Call AI provider (Claude / OpenAI) with a structured faith-community prompt.
//   4. Return structured scaffold.
//
// Returns:
//   {
//     description: string,
//     passageRefs?: string[],        // bibleStudy only
//     cadenceSuggestion?: string,
//     discussionPrompts: string[],   // always 3
//     suggestedTitle?: string
//   }
//
// Hard constraints:
//   - AI calls MUST go through this proxy — never direct from iOS client.
//   - No "church" in any string or response field.
//   - No hard-deletes of any Firestore document.
//   - Rate limit: 10 calls / user / hour (fail with "resource-exhausted" when exceeded).

import * as logger from "firebase-functions/logger";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// AI secrets — same pattern as ConversationOS callable.
const CLAUDE_KEY = defineSecret("CLAUDE_API_KEY");
const OPENAI_KEY = defineSecret("OPENAI_API_KEY");

// MARK: - Rate limit config (10 calls / user / hour)

const RATE_LIMIT_MAX_CALLS = 10;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;  // 1 hour
const RATE_LIMIT_DOC_PATH = (uid: string) =>
  `users/${uid}/rateLimits/scaffoldSpaceWithBerean`;

// MARK: - Request / Response types

interface ScaffoldRequest {
  type: "chat" | "bibleStudy" | "group";
  title: string;
  communityContext?: string;
}

interface ScaffoldResponse {
  description: string;
  passageRefs?: string[];
  cadenceSuggestion?: string;
  discussionPrompts: string[];
  suggestedTitle?: string;
}

// MARK: - Callable export

export const scaffoldSpaceWithBerean = onCall(
  {
    enforceAppCheck: true,
    secrets: [CLAUDE_KEY, OPENAI_KEY],
  },
  async (request): Promise<ScaffoldResponse> => {
    // 1. Auth check
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    // 2. Input validation
    const { type, title, communityContext } = request.data as Partial<ScaffoldRequest>;

    if (!type || !["chat", "bibleStudy", "group"].includes(type)) {
      throw new HttpsError(
        "invalid-argument",
        "type must be 'chat', 'bibleStudy', or 'group'."
      );
    }
    if (!title || typeof title !== "string" || title.trim().length < 1) {
      throw new HttpsError("invalid-argument", "title is required.");
    }
    if (title.trim().length > 200) {
      throw new HttpsError("invalid-argument", "title must be 200 characters or fewer.");
    }

    // 3. Rate limiting
    await enforceRateLimit(callerUid);

    // 4. Call AI provider
    const scaffold = await generateScaffold(type, title.trim(), communityContext, callerUid);

    logger.info(
      `[scaffoldSpaceWithBerean] Generated scaffold for user=${callerUid} type=${type} title="${title.trim()}"`
    );

    return scaffold;
  }
);

// MARK: - Rate limiting (Firestore transaction counter)

async function enforceRateLimit(uid: string): Promise<void> {
  const rateLimitRef = db.doc(RATE_LIMIT_DOC_PATH(uid));
  const now = Date.now();

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(rateLimitRef);

      if (!snap.exists) {
        // First call — initialize the window.
        tx.set(rateLimitRef, {
          callCount: 1,
          windowStartMs: now,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      const existing = snap.data()!;
      const windowStartMs: number = existing.windowStartMs ?? now;
      const callCount: number = existing.callCount ?? 0;
      const windowAgeMs = now - windowStartMs;

      if (windowAgeMs > RATE_LIMIT_WINDOW_MS) {
        // Window has expired — reset the counter.
        tx.set(rateLimitRef, {
          callCount: 1,
          windowStartMs: now,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else if (callCount >= RATE_LIMIT_MAX_CALLS) {
        throw new HttpsError(
          "resource-exhausted",
          "Berean scaffold rate limit reached. Please wait before retrying."
        );
      } else {
        tx.update(rateLimitRef, {
          callCount: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    // If rate-limit Firestore write fails, fail open — log and continue.
    logger.error("[scaffoldSpaceWithBerean] Rate limit Firestore write failed:", err);
  }
}

// MARK: - AI generation

async function generateScaffold(
  type: "chat" | "bibleStudy" | "group",
  title: string,
  communityContext: string | undefined,
  uid: string
): Promise<ScaffoldResponse> {
  // Try Claude first; fall back to OpenAI if Claude key is unavailable.
  const claudeKey = process.env.CLAUDE_API_KEY;
  const openaiKey = process.env.OPENAI_API_KEY;

  if (claudeKey) {
    try {
      return await callClaude(claudeKey, type, title, communityContext);
    } catch (e) {
      logger.warn("[scaffoldSpaceWithBerean] Claude call failed, falling back to OpenAI:", e);
    }
  }

  if (openaiKey) {
    return await callOpenAI(openaiKey, type, title, communityContext);
  }

  // No AI keys configured — return a sensible default scaffold.
  logger.warn("[scaffoldSpaceWithBerean] No AI keys configured. Returning default scaffold.");
  return buildDefaultScaffold(type, title);
}

// MARK: - Claude

async function callClaude(
  apiKey: string,
  type: "chat" | "bibleStudy" | "group",
  title: string,
  communityContext: string | undefined
): Promise<ScaffoldResponse> {
  const prompt = buildPrompt(type, title, communityContext);

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 800,
      messages: [
        {
          role: "user",
          content: prompt,
        },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`Claude API error: ${response.status} ${response.statusText}`);
  }

  const json = await response.json();
  const text: string = json.content?.[0]?.text ?? "";
  return parseAIResponse(text, type);
}

// MARK: - OpenAI

async function callOpenAI(
  apiKey: string,
  type: "chat" | "bibleStudy" | "group",
  title: string,
  communityContext: string | undefined
): Promise<ScaffoldResponse> {
  const prompt = buildPrompt(type, title, communityContext);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      max_tokens: 800,
      messages: [
        { role: "system", content: "You are Berean, an AI assistant that helps faith communities create meaningful Spaces for discussion, study, and connection." },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI API error: ${response.status} ${response.statusText}`);
  }

  const json = await response.json();
  const text: string = json.choices?.[0]?.message?.content ?? "";
  return parseAIResponse(text, type);
}

// MARK: - Prompt builder

function buildPrompt(
  type: "chat" | "bibleStudy" | "group",
  title: string,
  communityContext: string | undefined
): string {
  const contextNote = communityContext
    ? `\nCommunity context: ${communityContext}`
    : "";

  const typeDescription: Record<string, string> = {
    chat: "an open discussion space for community conversation",
    bibleStudy: "a structured Scripture study space",
    group: "a community group space for shared activities and connection",
  };

  const studyExtra =
    type === "bibleStudy"
      ? "\nFor passageRefs: suggest 1–3 specific Bible passage ranges (e.g. ['Romans 1-8', 'Romans 12:1-2']).\nFor cadenceSuggestion: suggest a study cadence (e.g. '5-week study' or 'weekly meeting')."
      : '\nOmit passageRefs and cadenceSuggestion from your response (set to null).';

  return `You are helping someone create "${title}" — ${typeDescription[type]} for a faith community.${contextNote}

Generate a structured scaffold for this Space. Respond ONLY with valid JSON matching this schema exactly:
{
  "description": "A 1–2 sentence description of the Space purpose and community value.",
  "passageRefs": null,
  "cadenceSuggestion": null,
  "discussionPrompts": ["prompt 1", "prompt 2", "prompt 3"],
  "suggestedTitle": null
}
${studyExtra}

For suggestedTitle: only provide if you have a significantly better title than "${title}"; otherwise set to null.
For discussionPrompts: always return exactly 3 thoughtful, open-ended questions relevant to "${title}".
Keep all text faith-affirming, community-building, and accessible.
Do NOT use the word "church" anywhere. Use "community" instead.
Respond with ONLY the JSON object — no markdown, no explanation.`;
}

// MARK: - Response parser

function parseAIResponse(
  text: string,
  type: "chat" | "bibleStudy" | "group"
): ScaffoldResponse {
  // Strip markdown code fences if present
  const cleaned = text
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();

  let parsed: Partial<ScaffoldResponse>;

  try {
    parsed = JSON.parse(cleaned);
  } catch {
    logger.error("[scaffoldSpaceWithBerean] Failed to parse AI JSON:", cleaned);
    throw new HttpsError(
      "internal",
      "Berean returned an unexpected response. Please try again."
    );
  }

  // Validate and sanitize
  const description = typeof parsed.description === "string" && parsed.description.length > 0
    ? parsed.description.slice(0, 500)
    : "A Space for meaningful community connection and conversation.";

  const discussionPrompts = Array.isArray(parsed.discussionPrompts)
    ? parsed.discussionPrompts
        .filter((p): p is string => typeof p === "string" && p.length > 0)
        .slice(0, 3)
    : [];

  // Pad to 3 prompts if AI returned fewer
  while (discussionPrompts.length < 3) {
    discussionPrompts.push("What has resonated with you most from our recent conversations?");
  }

  const result: ScaffoldResponse = {
    description,
    discussionPrompts,
  };

  // Study-only fields
  if (type === "bibleStudy") {
    if (Array.isArray(parsed.passageRefs) && parsed.passageRefs.length > 0) {
      result.passageRefs = parsed.passageRefs
        .filter((r): r is string => typeof r === "string" && r.length > 0)
        .slice(0, 5);
    }
    if (typeof parsed.cadenceSuggestion === "string" && parsed.cadenceSuggestion.length > 0) {
      result.cadenceSuggestion = parsed.cadenceSuggestion.slice(0, 100);
    }
  }

  // Optional suggested title
  if (typeof parsed.suggestedTitle === "string" && parsed.suggestedTitle.length > 2) {
    result.suggestedTitle = parsed.suggestedTitle.slice(0, 100);
  }

  return result;
}

// MARK: - Default scaffold (no AI keys configured)

function buildDefaultScaffold(
  type: "chat" | "bibleStudy" | "group",
  title: string
): ScaffoldResponse {
  const defaults: Record<string, ScaffoldResponse> = {
    chat: {
      description: `A discussion Space for ${title} — a place for open conversation, encouragement, and community building.`,
      discussionPrompts: [
        "What brought you here, and what are you hoping to explore together?",
        "How can we support one another in this Space?",
        "What's one thing you'd like this community to focus on?",
      ],
    },
    bibleStudy: {
      description: `A guided Scripture study Space for ${title} — exploring God's Word together with structure and depth.`,
      passageRefs: undefined,
      cadenceSuggestion: "Weekly study sessions",
      discussionPrompts: [
        "What stands out to you in this passage, and why?",
        "How does this Scripture speak to your current season of life?",
        "What practical steps might this text be inviting you toward?",
      ],
    },
    group: {
      description: `A community group Space for ${title} — a place to connect, share, and grow together.`,
      discussionPrompts: [
        "What's something you're grateful for this week?",
        "How can our group be praying for you right now?",
        "What does belonging to this community mean to you?",
      ],
    },
  };

  return defaults[type] ?? defaults.chat;
}
