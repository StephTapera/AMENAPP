"use strict";

const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const Anthropic = require("@anthropic-ai/sdk");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const REGION = "us-central1";

exports.bereanChatProxyStream = onRequest(
    {
      cors: false,
      region: REGION,
      secrets: [ANTHROPIC_API_KEY],
      timeoutSeconds: 120,
    },
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const authHeader = req.headers["authorization"] || "";
      const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
      if (!token) {
        res.status(401).json({error: "Missing authorization token."});
        return;
      }

      let uid;
      try {
        const decoded = await admin.auth().verifyIdToken(token);
        uid = decoded.uid;
      } catch {
        res.status(401).json({error: "Invalid or expired token."});
        return;
      }

      const {systemPrompt, userMessage, maxTokens = 1024} = req.body || {};

      if (!userMessage || typeof userMessage !== "string") {
        res.status(400).json({error: "userMessage is required."});
        return;
      }

      const db = admin.firestore();
      const hourKey = new Date().toISOString().slice(0, 13);
      const usageRef = db.doc(`users/${uid}/bereanUsage/${hourKey}`);
      const usageSnap = await usageRef.get();
      const count = usageSnap.exists ? (usageSnap.data().count ?? 0) : 0;
      if (count >= 30) {
        res.status(429).json({error: "Berean usage limit reached. Please try again later."});
        return;
      }
      await usageRef.set({count: count + 1}, {merge: true});

      const anthropic = new Anthropic({apiKey: process.env.ANTHROPIC_API_KEY});

      res.setHeader("Content-Type", "text/event-stream");
      res.setHeader("Cache-Control", "no-cache");
      res.setHeader("Connection", "keep-alive");

      try {
        const stream = anthropic.messages.stream({
          model: "claude-opus-4-7",
          max_tokens: maxTokens,
          system: systemPrompt || "",
          messages: [{role: "user", content: userMessage}],
        });

        for await (const event of stream) {
          if (event.type === "content_block_delta" && event.delta?.type === "text_delta") {
            const text = event.delta.text;
            res.write(`data: ${JSON.stringify({delta: {text}})}\n\n`);
          }
        }

        res.write("data: [DONE]\n\n");
        res.end();
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        res.write(`data: ${JSON.stringify({error: msg})}\n\n`);
        res.end();
      }
    }
);
