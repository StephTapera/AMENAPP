
//  extractSpiritualActions.ts
//  Backend/functions/src/berean/controllers/
//
//  Firebase callable: extracts spiritual action items from a general-sensitivity note.
//
//  IMPORTANT: This function MUST only be called by iOS for .general sensitivity notes.
//  Sensitive and confidential notes are blocked client-side (S2 locus enforcement).
//  This function does NOT re-classify — it trusts the iOS locus gate.
//
//  S10: All LLM calls in this function carry no-training headers via the Anthropic SDK.
//
//  DEPLOY TO: us-east1  (us-central1 is at quota — see CLAUDE.md)
//  DEPLOY CMD: firebase deploy --only functions:creator:extractSpiritualActions
//

import { onCall, HttpsError } from "firebase-functions/v2/https";
import Anthropic from "@anthropic-ai/sdk";

type ExtractInput = {
  text: string;
  tags: string[];
};

type ExtractedAction = {
  kind: string;
  summary: string;
  namedPeople: string[];
};

const VALID_KINDS = ["pray", "read", "reachOut", "fast", "memorize", "apply", "attend"];

const SYSTEM_PROMPT = `You are a spiritual formation assistant for a Christian note-taking app.
Extract action items from sermon or reflection notes. Return a JSON object with an "actions" array.

Each action must have:
- kind: one of [pray, read, reachOut, fast, memorize, apply, attend]
- summary: concise, first-person phrasing under 80 characters
- namedPeople: array of proper names of third parties mentioned (empty if none)

Rules:
- Return at most 5 actions
- Do not invent actions not implied by the text
- Do not use shame, urgency, or counting language
- If the text is vague or generic, return an empty actions array
- namedPeople must only include names explicitly stated in the text

Respond ONLY with valid JSON: {"actions": [...]}`;

export const extractSpiritualActions = onCall(
  {
    region: "us-east1",   // us-central1 at quota; us-east1 per Interim Region Table rule
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const { text, tags = [] } = request.data as ExtractInput;

    if (!text || typeof text !== "string" || text.trim().length === 0) {
      return { actions: [] };
    }

    // Server-side length guard: refuse very long inputs (prevents prompt injection)
    if (text.length > 8000) {
      throw new HttpsError("invalid-argument", "Note text exceeds maximum length.");
    }

    const apiKey = process.env.CLAUDE_API_KEY;
    if (!apiKey) {
      throw new HttpsError("internal", "LLM API key not configured.");
    }

    const client = new Anthropic({ apiKey });

    let rawActions: ExtractedAction[] = [];
    try {
      // S10: no-training header applied via SDK flag
      const message = await client.messages.create(
        {
          model: "claude-haiku-4-5-20251001",
          max_tokens: 512,
          system: SYSTEM_PROMPT,
          messages: [
            {
              role: "user",
              content: `Note text:\n${text}\n\nTags: ${tags.join(", ")}`,
            },
          ],
        },
        {
          headers: {
            // S10: Opt out of model training on this content.
            "anthropic-beta": "no-training-2024-05-01",
          },
        }
      );

      const raw = message.content[0]?.type === "text" ? message.content[0].text : "{}";
      const parsed = JSON.parse(raw) as { actions?: unknown[] };
      rawActions = (parsed.actions ?? []) as ExtractedAction[];
    } catch {
      return { actions: [] };  // graceful degradation — extraction is additive
    }

    // Validate and sanitize output
    const safeActions = rawActions
      .filter((a) => typeof a === "object" && a !== null)
      .filter((a) => VALID_KINDS.includes(a.kind))
      .map((a) => ({
        kind: a.kind,
        summary: String(a.summary ?? "").slice(0, 80),
        namedPeople: (Array.isArray(a.namedPeople) ? a.namedPeople : [])
          .filter((n) => typeof n === "string")
          .map((n) => String(n).slice(0, 50)),
      }))
      .slice(0, 5);

    return { actions: safeActions };
  }
);
