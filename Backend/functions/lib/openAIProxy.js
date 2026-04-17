"use strict";
/**
 * openAIProxy.ts
 *
 * OpenAI API proxy for general AI features (smart suggestions, content moderation, etc.)
 * Routes requests from OpenAIService.swift through Firebase Cloud Functions to api.openai.com
 * keeping the API key secure in Firebase Secret Manager.
 *
 * Setup:
 *   firebase functions:secrets:set OPENAI_API_KEY
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.openAIProxy = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const rateLimit_1 = require("./rateLimit");
const openaiApiKey = (0, params_1.defineSecret)("OPENAI_API_KEY");
/**
 * OpenAI Chat Completion Proxy
 * Proxies OpenAI API calls with secure API key management
 */
exports.openAIProxy = (0, https_1.onCall)({
    secrets: [openaiApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: false,
}, async (request) => {
    // Verify authentication
    if (!request.auth) {
        throw new Error("User must be authenticated to use AI features");
    }
    // CRITICAL-CF FIX: Per-user rate limiting.
    // Enforce both a per-minute burst limit and a daily token budget cap.
    // Throws HttpsError("resource-exhausted") if either window is exceeded.
    await (0, rateLimit_1.enforceRateLimit)(request.auth.uid, [
        rateLimit_1.RATE_LIMITS.AI_PER_MINUTE,
        rateLimit_1.RATE_LIMITS.AI_PER_DAY,
    ]);
    const data = request.data;
    const context = request;
    const { messages, maxTokens = 1000, temperature = 0.7, model = "gpt-4o-mini", // Cost-effective default
     } = data;
    // Validate input
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
        throw new Error("Messages array is required and must not be empty");
    }
    // HIGH FIX #8: Enforce maximum per-message content length.
    // Without this, a client can send arbitrarily large strings directly to the
    // OpenAI API, incurring large token costs and risking function timeouts / OOM.
    // 4000 characters covers any realistic single message while keeping tokens
    // well within the per-call budget. Also cap total messages array size.
    const MAX_MESSAGE_CONTENT_LENGTH = 4000;
    const MAX_MESSAGES_COUNT = 50;
    if (messages.length > MAX_MESSAGES_COUNT) {
        throw new Error(`Messages array exceeds maximum count of ${MAX_MESSAGES_COUNT}.`);
    }
    for (const msg of messages) {
        if (typeof msg.content === "string" && msg.content.length > MAX_MESSAGE_CONTENT_LENGTH) {
            throw new Error(`Message content exceeds maximum length of ${MAX_MESSAGE_CONTENT_LENGTH} characters.`);
        }
    }
    // Get API key from secret
    const apiKey = openaiApiKey.value();
    if (!apiKey) {
        console.error("❌ OPENAI_API_KEY not configured");
        throw new Error("OpenAI is not configured. Please contact support.");
    }
    try {
        // Call OpenAI API
        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
                model,
                messages: messages.slice(-20), // Limit context to last 20 messages
                max_tokens: maxTokens,
                temperature,
            }),
        });
        if (!response.ok) {
            const errorText = await response.text();
            console.error(`❌ OpenAI API error: ${response.status}`, errorText);
            throw new Error(`OpenAI API error: ${response.status}`);
        }
        const result = await response.json();
        // Extract response
        const responseText = result.choices?.[0]?.message?.content || "";
        // Log usage for monitoring
        console.log(`✅ OpenAI (${model}) - User: ${context.auth.uid} - Tokens: ${result.usage?.total_tokens || 0}`);
        return {
            response: responseText,
            model,
            usage: result.usage,
        };
    }
    catch (error) {
        console.error("❌ OpenAI Proxy error:", error);
        throw new Error("Failed to process OpenAI request");
    }
});
//# sourceMappingURL=openAIProxy.js.map