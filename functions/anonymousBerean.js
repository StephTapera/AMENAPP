// anonymousBerean.js
// Firebase Cloud Function: anonymousBereanQuery
// Accepts a plain question with NO userId — anonymous by design.
// Calls Anthropic and returns { answer: string }.

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const https = require("https");

const SYSTEM_PROMPT =
  "You are Berean, a knowledgeable biblical assistant. " +
  "Answer questions thoughtfully and concisely (2–4 paragraphs), " +
  "citing relevant scripture where appropriate. " +
  "Do not request personal information. Do not ask follow-up questions.";

const anonymousBereanQuery = onCall(
  { maxInstances: 10, enforceAppCheck: false },
  async (request) => {
    const { question } = request.data;

    if (!question || typeof question !== "string") {
      throw new HttpsError("invalid-argument", "question is required");
    }

    const trimmed = question.trim().slice(0, 500);
    if (trimmed.length < 3) {
      throw new HttpsError("invalid-argument", "question is too short");
    }

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new HttpsError("unavailable", "AI service is not configured");
    }

    const body = JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: trimmed }],
    });

    const answer = await new Promise((resolve, reject) => {
      const req = https.request(
        {
          hostname: "api.anthropic.com",
          path: "/v1/messages",
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "Content-Length": Buffer.byteLength(body),
          },
        },
        (res) => {
          let data = "";
          res.on("data", (chunk) => { data += chunk; });
          res.on("end", () => {
            try {
              const parsed = JSON.parse(data);
              if (parsed.error) {
                reject(new HttpsError("internal", parsed.error.message));
                return;
              }
              const text =
                parsed.content?.[0]?.text ??
                "I'm unable to answer that right now.";
              resolve(text);
            } catch {
              reject(new HttpsError("internal", "Invalid response from AI service"));
            }
          });
        }
      );
      req.on("error", (err) => reject(new HttpsError("internal", err.message)));
      req.write(body);
      req.end();
    });

    return { answer };
  }
);

module.exports = { anonymousBereanQuery };
