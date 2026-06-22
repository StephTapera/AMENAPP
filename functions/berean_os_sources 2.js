// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
/**
 * Berean OS — Source Explorer Cloud Functions
 * bereanFetchSources
 *
 * Deploy: firebase deploy --only functions:bereanFetchSources --project amen-5e359
 * Requires: CLAUDE_API_KEY secret
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const fetch = require("node-fetch");

const REGION = "us-central1";
const CLAUDE_API_KEY = defineSecret("CLAUDE_API_KEY");

exports.bereanFetchSources = onCall(
  {
    region: REGION,
    secrets: [CLAUDE_API_KEY],
    enforceAppCheck: true,
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const { claim, context } = request.data;

    if (!claim || typeof claim !== "string" || claim.trim().length < 3) {
      throw new HttpsError("invalid-argument", "claim must be at least 3 characters.");
    }
    if (claim.length > 1000) {
      throw new HttpsError("invalid-argument", "claim must be ≤ 1000 characters.");
    }

    const systemPrompt = `You are a source quality analyst for the AMEN faith community.
Evaluate the given claim and provide traceable source information.
Return a JSON object with:
- sources: array of objects {
    title: string,
    author: string,
    publicationYear: number|null,
    sourceType: "scripture"|"scholarly"|"news"|"blog"|"social"|"unknown",
    qualityScore: number 0-1,
    qualityReason: string,
    url: string|null,
    conflictsWith: array of strings (other source titles it contradicts)
  }
- overallReliability: number 0-1
- conflictsDetected: boolean
- conflictSummary: string|null
- verificationNotes: string

Provide 3-6 relevant sources. Be honest about limitations.
Return ONLY valid JSON, no markdown.`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": CLAUDE_API_KEY.value(),
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 1500,
        messages: [
          {
            role: "user",
            content: `${systemPrompt}\n\nClaim: "${claim}"${context ? `\nContext: ${context}` : ""}`,
          },
        ],
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("[bereanFetchSources] Claude error:", err);
      throw new HttpsError("internal", "Source fetch failed.");
    }

    const result = await response.json();
    let parsed = {};
    try {
      const raw = result.content[0].text;
      const jsonMatch = raw.match(/\{[\s\S]*\}/);
      parsed = JSON.parse(jsonMatch ? jsonMatch[0] : raw);
    } catch (_) {
      throw new HttpsError("internal", "Failed to parse sources response.");
    }

    return parsed;
  }
);
