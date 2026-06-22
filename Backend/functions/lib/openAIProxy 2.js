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
const openaiApiKey = (0, params_1.defineSecret)("OPENAI_API_KEY");
/**
 * OpenAI Chat Completion Proxy
 * Proxies OpenAI API calls with secure API key management
 */
exports.openAIProxy = (0, https_1.onCall)({
    secrets: [openaiApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
}, async (request) => {
    // Verify authentication
    if (!request.auth) {
        throw new Error("User must be authenticated to use AI features");
    }
    const data = request.data;
    const context = request;
    const { messages, maxTokens = 1000, temperature = 0.7, model = "gpt-4o-mini", // Cost-effective default
     } = data;
    // Validate input
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
        throw new Error("Messages array is required and must not be empty");
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
//# sourceMappingURL=openAIProxy%202.js.map