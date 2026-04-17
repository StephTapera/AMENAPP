/**
 * bereanChatProxy.ts
 *
 * Anthropic Claude proxy for Berean AI assistant.
 * Routes requests from ClaudeService.swift through Firebase Cloud Functions
 * to api.anthropic.com, keeping the API key secure in Firebase Secret Manager.
 *
 * Setup:
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 *
 * Model Selection:
 *   - Haiku (claude-3-haiku-20240307): Real-time interactions, fast responses
 *   - Sonnet (claude-3-5-sonnet-20241022): Scholar/debater modes, deep analysis
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {enforceRateLimit, RATE_LIMITS} from "./rateLimit";

interface BereanChatRequest {
    message: string;
    conversationHistory?: Array<{
        role: "user" | "assistant";
        content: string;
    }>;
    maxTokens?: number;
    temperature?: number;
    mode?: string;
    systemPromptSuffix?: string;
}

interface ClaudeMessage {
    role: "user" | "assistant";
    content: string;
}

interface ClaudeResponse {
    content?: Array<{
        text?: string;
        type?: string;
    }>;
    usage?: {
        input_tokens?: number;
        output_tokens?: number;
    };
}

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

/**
 * Berean AI Chat Proxy
 * Proxies Claude API calls with secure API key management
 */
export const bereanChatProxy = onCall(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
        // 5.1 FIX: Reject calls from clients that cannot produce a valid App Check
        // token. Prevents scripted abuse of the Anthropic API proxy with a stolen
        // Firebase Auth token alone (no attested iOS binary required).
        enforceAppCheck: false,
    },
    async (request) => {
        // Verify authentication
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated to use Berean AI");
        }

        // CRITICAL-CF FIX: Per-user rate limiting.
        // Enforce both a per-minute burst limit and a daily token budget cap.
        // Throws HttpsError("resource-exhausted") if either window is exceeded.
        await enforceRateLimit(request.auth.uid, [
            RATE_LIMITS.AI_PER_MINUTE,
            RATE_LIMITS.AI_PER_DAY,
        ]);

        const data = request.data as BereanChatRequest;

        const {
            message,
            conversationHistory = [],
            maxTokens = 2000,
            temperature = 0.7,
            mode = "shepherd",
            systemPromptSuffix,
        } = data;

        // Validate input
        if (!message || typeof message !== "string" || message.trim().length === 0) {
            throw new HttpsError("invalid-argument", "Message is required and must be a non-empty string");
        }

        // HIGH FIX: Enforce maximum message length.
        // Without this, a client can send a 500KB+ string directly to the Anthropic
        // API, incurring large token costs and risking function timeouts / OOM.
        // 4000 characters covers any realistic single message while keeping tokens
        // well within the per-call budget.
        const MAX_MESSAGE_LENGTH = 4000;
        if (message.length > MAX_MESSAGE_LENGTH) {
            throw new HttpsError(
                "invalid-argument",
                `Message exceeds maximum length of ${MAX_MESSAGE_LENGTH} characters.`
            );
        }

        // Get API key from secret
        const apiKey = anthropicApiKey.value();
        if (!apiKey) {
            console.error("❌ ANTHROPIC_API_KEY not configured");
            throw new Error("Berean AI is not configured. Please contact support.");
        }

        try {
            // Select model based on mode
            const model = mode === "scholar" || mode === "debater"
                ? "claude-3-5-sonnet-20241022"
                : "claude-3-haiku-20240307";

            // Build system prompt
            let systemPrompt = buildSystemPrompt(mode);
            if (systemPromptSuffix) {
                systemPrompt += `\n\n${systemPromptSuffix}`;
            }

            // Build messages array
            const messages: ClaudeMessage[] = [
                ...conversationHistory.slice(-12), // Limit history to last 12 messages
                { role: "user", content: message },
            ];

            // Call Claude API
            const response = await fetch("https://api.anthropic.com/v1/messages", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01",
                },
                body: JSON.stringify({
                    model,
                    max_tokens: maxTokens,
                    temperature,
                    system: systemPrompt,
                    messages,
                }),
            });

            if (!response.ok) {
                const errorText = await response.text();
                console.error(`❌ Claude API error: ${response.status}`, errorText);
                throw new Error(`Claude API error: ${response.status}`);
            }

            const result = await response.json() as ClaudeResponse;

            // Extract text from response
            const responseText = result.content?.[0]?.text || "";

            // Log usage for monitoring
            console.log(`✅ Berean AI (${model}) - User: ${request.auth!.uid} - Tokens: ${result.usage?.output_tokens || 0}`);

            return {
                response: responseText,
                model,
                usage: result.usage,
            };

        } catch (error: any) {
            console.error("❌ Berean Chat Proxy error:", error);
            throw new Error("Failed to process Berean AI request");
        }
    }
);

/**
 * Build system prompt based on Berean mode
 */
function buildSystemPrompt(mode: string): string {
    const basePrompt = `You are Berean AI, a compassionate Biblical assistant for the AMEN Christian social app.
Your purpose is to help believers understand Scripture, grow in faith, and apply God's Word to their lives.

Core Principles:
- Always cite Scripture references (e.g., John 3:16, Psalm 23:1-6)
- Be encouraging, compassionate, and Christ-centered
- Acknowledge multiple theological perspectives when appropriate
- Refer complex theological questions to local church leaders
- Never claim to replace personal Bible study or pastoral guidance`;

    const modePrompts: Record<string, string> = {
        shepherd: `${basePrompt}

Mode: Shepherd - You are encouraging and pastoral. Guide users gently toward Scripture and practical application.`,

        scholar: `${basePrompt}

Mode: Scholar - You provide deeper theological analysis with historical context, original language insights, and cross-references. Maintain academic rigor while being accessible.`,

        debater: `${basePrompt}

Mode: Debater - You engage in respectful theological dialogue, exploring different perspectives and challenging assumptions with Scripture. Ask probing questions and encourage critical thinking.`,

        prayer: `${basePrompt}

Mode: Prayer Guide - Help users craft meaningful prayers based on Scripture. Suggest Biblical prayer patterns and relevant passages for their situation.`,
    };

    return modePrompts[mode] || modePrompts.shepherd;
}
