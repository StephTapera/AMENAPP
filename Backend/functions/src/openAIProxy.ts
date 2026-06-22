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

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {enforceRateLimit, RATE_LIMITS} from "./rateLimit";

interface OpenAIProxyRequest {
    messages: Array<{
        role: "system" | "user" | "assistant";
        content: string;
    }>;
    maxTokens?: number;
    temperature?: number;
    model?: string;
}

interface OpenAIResponse {
    choices?: Array<{
        message?: {
            content?: string;
        };
    }>;
    usage?: {
        prompt_tokens?: number;
        completion_tokens?: number;
        total_tokens?: number;
    };
}

const openaiApiKey = defineSecret("OPENAI_API_KEY");

/**
 * OpenAI Chat Completion Proxy
 * Proxies OpenAI API calls with secure API key management
 */
export const openAIProxy = onCall(
    {
        secrets: [openaiApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
        // 5.1 FIX: Reject calls from clients without a valid App Check token.
        enforceAppCheck: true,
    },
    async (request) => {
        // Verify authentication
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated to use AI features");
        }

        // CRITICAL-CF FIX: Per-user rate limiting.
        // Enforce both a per-minute burst limit and a daily token budget cap.
        // Throws HttpsError("resource-exhausted") if either window is exceeded.
        await enforceRateLimit(request.auth.uid, [
            RATE_LIMITS.AI_PER_MINUTE,
            RATE_LIMITS.AI_PER_DAY,
        ]);

        const data = request.data as OpenAIProxyRequest;

        const {
            messages,
            maxTokens = 1000,
            temperature = 0.7,
            model: requestedModel = "gpt-4o-mini",
        } = data;

        // Allowlist prevents clients from specifying expensive models (e.g. gpt-4)
        const ALLOWED_MODELS = new Set(["gpt-4o-mini", "gpt-4o"]);
        const model = ALLOWED_MODELS.has(requestedModel) ? requestedModel : "gpt-4o-mini";

        // Validate input
        if (!messages || !Array.isArray(messages) || messages.length === 0) {
            throw new HttpsError("invalid-argument", "Messages array is required and must not be empty");
        }

        // HIGH FIX #8: Enforce maximum per-message content length.
        // Without this, a client can send arbitrarily large strings directly to the
        // OpenAI API, incurring large token costs and risking function timeouts / OOM.
        // 4000 characters covers any realistic single message while keeping tokens
        // well within the per-call budget. Also cap total messages array size.
        const MAX_MESSAGE_CONTENT_LENGTH = 4000;
        const MAX_MESSAGES_COUNT = 50;
        if (messages.length > MAX_MESSAGES_COUNT) {
            throw new HttpsError("invalid-argument", `Messages array exceeds maximum count of ${MAX_MESSAGES_COUNT}.`);
        }
        for (const msg of messages) {
            if (typeof msg.content === "string" && msg.content.length > MAX_MESSAGE_CONTENT_LENGTH) {
                throw new HttpsError("invalid-argument", `Message content exceeds maximum length of ${MAX_MESSAGE_CONTENT_LENGTH} characters.`);
            }
        }

        // Get API key from secret
        const apiKey = openaiApiKey.value();
        if (!apiKey) {
            console.error("❌ OPENAI_API_KEY not configured");
            throw new HttpsError("unavailable", "OpenAI is not configured. Please contact support.");
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
                throw new HttpsError("unavailable", `OpenAI API error: ${response.status}`);
            }

            const result = await response.json() as OpenAIResponse;

            // Extract response
            const responseText = result.choices?.[0]?.message?.content || "";

            // Log usage for monitoring (no UID — use opaque metrics only)
            console.log(`✅ OpenAI (${model}) — tokens: ${result.usage?.total_tokens || 0}`);

            return {
                response: responseText,
                model,
                usage: result.usage,
            };

        } catch (error: any) {
            if (error instanceof HttpsError) throw error;
            console.error("❌ OpenAI Proxy error:", error);
            throw new HttpsError("internal", "Failed to process OpenAI request");
        }
    }
);
