// anonymousBerean.js
// Firebase Cloud Function: anonymousBereanQuery
// Accepts a plain question with NO userId — anonymous by design.
// Calls Anthropic and returns { answer: string }.

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const https = require("https");
const admin = require("firebase-admin");
const { logger } = require("firebase-functions");
const { checkGlobalCircuitBreaker } = require("./globalCircuitBreaker");

const SYSTEM_PROMPT =
  "You are Berean, a knowledgeable biblical assistant. " +
  "Answer questions thoughtfully and concisely (2–4 paragraphs), " +
  "citing relevant scripture where appropriate. " +
  "Do not request personal information. Do not ask follow-up questions.";

// Graceful degradation message shown to anonymous users when global cap is hit.
const BUSY_ANSWER =
  "Berean is receiving many questions right now. Please try again in a little while, " +
  "or sign in to the AMEN app for a dedicated Berean session.";

const anonymousBereanQuery = onCall(
  { maxInstances: 10, enforceAppCheck: true },
  async (request) => {
    const { question } = request.data;

    if (!question || typeof question !== "string") {
      throw new HttpsError("invalid-argument", "question is required");
    }

    const trimmed = question.trim().slice(0, 500);
    if (trimmed.length < 3) {
      throw new HttpsError("invalid-argument", "question is too short");
    }

    // ── Global daily cap — graceful degradation for anonymous callers ─────
    // Anonymous users get a friendly "service busy" response instead of an error
    // when the global daily request pool is exhausted.
    try {
      const db = admin.firestore();
      const dayKey = new Date().toISOString().slice(0, 10);
      const anonRef = db.doc("meta/anonymousBereanUsage");
      const anonSnap = await anonRef.get();
      const anonData = anonSnap.exists ? anonSnap.data() : {};
      const storedDay = anonData.dailyKey ?? "";
      const todayCalls = storedDay === dayKey ? (anonData.todayCalls ?? 0) : 0;

      if (todayCalls >= 500) {
        logger.warn("[anonymousBerean] global daily cap reached", { todayCalls, dayKey });
        return { answer: BUSY_ANSWER };
      }

      // Increment anonymous counter
      if (storedDay !== dayKey) {
        await anonRef.set({ dailyKey: dayKey, todayCalls: 1 }, { merge: true });
      } else {
        await anonRef.update({ todayCalls: admin.firestore.FieldValue.increment(1) });
      }

      // ── Hourly global anonymous rate limit (sliding window) ──────────────
      const hourKey = new Date().toISOString().slice(0, 13);
      const hourRef = db.doc("meta/anonymousBerean");
      const hourSnap = await hourRef.get();
      const hourData = hourSnap.exists ? hourSnap.data() : {};
      const storedHour = hourData.hourKey ?? "";
      const hourCalls = storedHour === hourKey ? (hourData.count ?? 0) : 0;

      if (hourCalls >= 200) {
        logger.warn("[anonymousBerean] global hourly cap reached", { hourCalls, hourKey });
        return { answer: BUSY_ANSWER };
      }

      if (storedHour !== hourKey) {
        await hourRef.set({ hourKey, count: 1 }, { merge: true });
      } else {
        await hourRef.update({ count: admin.firestore.FieldValue.increment(1) });
      }
    } catch (capErr) {
      // Fail OPEN on Firestore errors — don't block anonymous users on a config error.
      logger.error("[anonymousBerean] cap check failed, proceeding", capErr);
    }

    // ── Global cost circuit-breaker ───────────────────────────────────────
    // For anonymous callers we convert resource-exhausted to a graceful message.
    try {
      await checkGlobalCircuitBreaker("anthropic");
    } catch (cbErr) {
      if (cbErr.code === "resource-exhausted") {
        return { answer: BUSY_ANSWER };
      }
      throw cbErr;
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
