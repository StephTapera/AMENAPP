/**
 * bereanChatProxy.ts
 *
 * Anthropic Claude proxy for Berean AI assistant.
 * Routes requests from ClaudeService.swift through Firebase Cloud Functions
 * to api.anthropic.com, keeping the API key secure in Firebase Secret Manager.
 */

import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {enforceRateLimit, RATE_LIMITS} from "./rateLimit";
import {buildSensitiveTopicPolicyBlock} from "./berean/prompts/sensitiveTopicPolicy";
import {SensitivityFlag, TopicClass} from "./berean/models/berean";
import {validateRawTextOutput} from "./berean/services/SafetyValidator";
import {checkBereanKillSwitch} from "./berean/services/ageGate";

// Shared Firestore instance — initialised once per cold start
const db = admin.firestore();

interface BereanChatRequest {
    message: string;
    conversationHistory?: Array<{
        role: "user" | "assistant";
        content: string;
    }>;
    maxTokens?: number;
    temperature?: number;
    mode?: string;
    memoryScope?: string;
    callData?: {
        conversationId?: string;
        memoryScope?: string;
        faithJourneyStage?: string;
        userPersona?: string;
        scriptureTranslation?: string;
        responseMode?: string;
        sensitivityFlags?: string[];
        postContext?: {
            postId: string;
            authorId: string;
            authorName: string;
            previewText: string;
            bodyText?: string;
            category: string;
            verseReference?: string;
            verseText?: string;
            mediaSummary?: string;
            isSensitive: boolean;
        };
    };
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

interface ProxySensitivityContext {
    flags: SensitivityFlag[];
    topicClass: TopicClass | null;
}

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const bereanChatProxy = onCall(
    {
        secrets: [anthropicApiKey],
        timeoutSeconds: 60,
        memory: "256MiB",
        enforceAppCheck: true,
        region: "us-east1",  // us-central1 at quota limit
    },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated to use Berean AI");
        }

        // [C-INF-1-003] Kill switch check — evaluated before rate-limit to fail cheapest
        const killActive = await checkBereanKillSwitch(db);
        if (killActive) {
            throw new HttpsError("unavailable", "Berean AI is temporarily unavailable.");
        }

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
            memoryScope,
            callData,
        } = data;

        if (!message || typeof message !== "string" || message.trim().length === 0) {
            throw new HttpsError("invalid-argument", "Message is required and must be a non-empty string");
        }

        const maxMessageLength = 4000;
        if (message.length > maxMessageLength) {
            throw new HttpsError(
                "invalid-argument",
                `Message exceeds maximum length of ${maxMessageLength} characters.`
            );
        }

        const apiKey = anthropicApiKey.value();
        if (!apiKey) {
            throw new Error("Berean AI is not configured. Please contact support.");
        }

        try {
            const sensitivityContext = analyzeSensitivity(message, callData);
            const model = mode === "scholar" || mode === "debater"
                ? "claude-3-5-sonnet-20241022"
                : "claude-3-haiku-20240307";

            let systemPrompt = buildSystemPrompt(mode);
            const sensitivePolicyBlock = buildSensitiveTopicPolicyBlock(
                sensitivityContext.flags,
                sensitivityContext.topicClass
            );
            if (sensitivePolicyBlock) {
                systemPrompt += `\n\n${sensitivePolicyBlock}`;
            }

            const contextualPrompt = buildCallDataPrompt(callData ?? {memoryScope});
            if (contextualPrompt) {
                systemPrompt += `\n\n${contextualPrompt}`;
            }

            const messages: ClaudeMessage[] = [
                ...conversationHistory.slice(-12),
                {role: "user", content: message},
            ];

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
            const responseText = result.content?.[0]?.text || "";
            const validatedText = validateRawTextOutput(
                responseText || "Berean encountered an issue — tap to retry."
            );
            const safeResponseText = ensureAIDisclosure(validatedText.sanitizedText);

            if (!validatedText.isValid) {
                console.warn("⚠️ Berean proxy output sanitized", {
                    uid: request.auth.uid,
                    violations: validatedText.violations,
                });
            }

            return {
                response: safeResponseText,
                model,
                usage: result.usage,
            };
        } catch (error) {
            console.error("❌ Berean Chat Proxy error:", error);
            throw new Error("Failed to process Berean AI request");
        }
    }
);

function buildSystemPrompt(mode: string): string {
    const basePrompt = `You are Berean AI, a compassionate Biblical assistant for the AMEN Christian social app.
Your purpose is to help believers understand Scripture, grow in faith, and apply God's Word to their lives.

Core Principles:
- Always cite Scripture references (e.g., John 3:16, Psalm 23:1-6)
- Be encouraging, compassionate, and Christ-centered
- Acknowledge multiple theological perspectives when appropriate
- Refer complex theological questions to local church leaders
- Never claim to replace personal Bible study, pastoral guidance, therapy, or clinical care
- Never speak as if you have direct divine authority over a user's life
- Never tell a user that God is commanding them to leave a church, end a relationship, stop medication, or ignore wise human counsel
- For abuse, suicidality, or immediate safety concerns, prioritize human safety and local support over theological analysis
- For disputed doctrine, present faithful Christian differences with humility and do not treat one tradition as the only valid view`;

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

function analyzeSensitivity(
    message: string,
    callData?: BereanChatRequest["callData"]
): ProxySensitivityContext {
    const rawFlags = callData?.sensitivityFlags ?? [];
    const flags = rawFlags.filter((flag): flag is SensitivityFlag => {
        return [
            "self_harm",
            "suicidal_language",
            "abuse",
            "spiritual_abuse",
            "trauma",
            "marriage_crisis",
            "doctrinal_conflict",
            "pastoral_conflict",
            "medical",
            "legal",
            "psychosis_sensitive_religious_language",
        ].includes(flag);
    }) as unknown as SensitivityFlag[];

    const MEDICAL_KEYWORDS = [
        "my diagnosis",
        "should i take my medication",
        "stop my meds",
        "stop taking my medication",
        "cancer",
        "mental illness treatment",
        "my prescription",
        "my doctor told me",
        "my therapist",
        "my psychiatrist",
    ];

    const lower = message.toLowerCase();

    if (!flags.includes("medical" as SensitivityFlag) &&
        MEDICAL_KEYWORDS.some((kw) => lower.includes(kw))) {
        flags.push("medical" as SensitivityFlag);
    }

    let topicClass: TopicClass | null = null;
    if (flags.includes("abuse" as SensitivityFlag)) topicClass = "abuse_disclosure";
    else if (flags.includes("medical" as SensitivityFlag)) topicClass = "medical_override";
    else if (flags.includes("legal" as SensitivityFlag)) topicClass = "legal_conflict";
    else if (flags.includes("self_harm" as SensitivityFlag) || flags.includes("suicidal_language" as SensitivityFlag)) topicClass = "suicidality";
    else if (lower.includes("leave my church") || lower.includes("is my pastor wrong")) topicClass = "church_conflict";

    return {flags, topicClass};
}

/** [CIN3-002] Strip prompt-injection attempts from any user-provided string
 *  before it is interpolated into the system prompt. */
function stripInjection(value: string): string {
    return value
        .replace(/ignore\s+(previous|all|system|above)/gi, "[filtered]")
        .replace(/<\|im_start\|>/gi, "[filtered]");
}

function buildCallDataPrompt(callData?: BereanChatRequest["callData"]): string | null {
    if (!callData) return null;

    const lines: string[] = [];

    // [CIN3-002] Apply injection strip to all user-controlled scalar fields
    if (callData.faithJourneyStage) {
        lines.push(`Faith journey stage: ${stripInjection(callData.faithJourneyStage)}`);
    }
    if (callData.userPersona) {
        lines.push(`User persona: ${stripInjection(callData.userPersona)}`);
    }
    if (callData.scriptureTranslation) {
        lines.push(`Preferred translation: ${stripInjection(callData.scriptureTranslation)}`);
    }
    if (callData.responseMode) {
        lines.push(`Safety-tuned response mode: ${stripInjection(callData.responseMode)}`);
    }

    if (callData.postContext) {
        lines.push(`Post preview: ${stripInjection(callData.postContext.previewText)}`);
        lines.push(`Post category: ${stripInjection(callData.postContext.category)}`);
        if (callData.postContext.verseReference) {
            lines.push(`Post scripture reference: ${stripInjection(callData.postContext.verseReference)}`);
        }

        // [CIN3-001] bodyText was declared in the interface but never appended.
        // Cap at 500 chars, strip injection, then wrap in XML delimiters so the
        // LLM treats it as structured context, not as an instruction.
        const safeBody = stripInjection(
            (callData.postContext.bodyText ?? "").slice(0, 500)
        );
        if (safeBody.length > 0) {
            lines.push(`<user_post_context>\n${safeBody}\n</user_post_context>`);
        }
    }

    return lines.length === 0 ? null : lines.join("\n");
}

function ensureAIDisclosure(text: string): string {
    const disclosure = "AI-generated response — not pastoral, medical, or clinical advice.";
    return text.startsWith(disclosure) ? text : `${disclosure}\n\n${text}`;
}
