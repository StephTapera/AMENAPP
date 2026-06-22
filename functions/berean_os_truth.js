// SECURITY: enforceAppCheck: true added — enable Console enforce-mode per DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md
"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const REGION = "us-central1";

/**
 * bereanClassifyStatement
 *
 * Classifies an array of text statements by epistemic status (confidence level).
 * Accepts 1-20 statements per call; defaults to "uncertain" when classification
 * cannot be determined.
 *
 * Request shape: { statements: string[] }
 * Response shape: { classifications: { [statement: string]: confidenceLevel } }
 *
 * Levels: verified | supported | likely | uncertain | speculative | opinion | aiGenerated
 */
exports.bereanClassifyStatement = onCall(
  {region: REGION, secrets: [OPENAI_API_KEY], enforceAppCheck: true},
  async (request) => {
    // Auth guard
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }

    const {statements} = request.data;

    // Input validation
    if (!Array.isArray(statements) || statements.length === 0) {
      throw new HttpsError("invalid-argument", "statements array required.");
    }
    if (statements.length > 20) {
      throw new HttpsError("invalid-argument", "Max 20 statements per call.");
    }

    const fetch = (await import("node-fetch")).default;

    const validLevels = new Set([
      "verified", "supported", "likely", "uncertain",
      "speculative", "opinion", "aiGenerated",
    ]);

    const prompt =
      "Classify each statement's epistemic status. Return JSON: { \"classifications\": { \"statement\": \"level\" } }\n" +
      "Levels: verified (multiple reliable sources confirm), supported (good evidence), likely (probable), " +
      "uncertain (needs verification), speculative (possible but weak evidence), opinion (interpretation not fact), " +
      "aiGenerated (AI output that needs verification).\n" +
      "Default to \"uncertain\" when unsure. Never over-claim confidence.\n\n" +
      "Statements:\n" +
      statements.map((s, i) => `${i + 1}. ${s.slice(0, 300)}`).join("\n");

    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY.value()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [{role: "user", content: prompt}],
        response_format: {type: "json_object"},
        max_tokens: 512,
      }),
    });

    if (!resp.ok) {
      console.error("OpenAI API error", resp.status, await resp.text());
      throw new HttpsError("internal", "Classification service unavailable.");
    }

    const data = await resp.json();
    let result = {classifications: {}};

    try {
      const parsed = JSON.parse(data.choices[0].message.content);
      if (parsed && typeof parsed.classifications === "object") {
        // Sanitise: keep only known level strings, default unknown to "uncertain"
        const sanitised = {};
        for (const [statement, level] of Object.entries(parsed.classifications)) {
          sanitised[statement] = validLevels.has(level) ? level : "uncertain";
        }
        result = {classifications: sanitised};
      }
    } catch (parseErr) {
      console.warn("Failed to parse classification response:", parseErr);
      result = {classifications: {}};
    }

    return result;
  }
);
