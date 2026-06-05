"use strict";
/**
 * refineTranslation.ts
 *
 * LLM-powered translation refinement for meaning-aware translation.
 * Takes a literal machine translation and refines it via Claude API
 * in two modes:
 *   - natural: rewritten to sound native in target language
 *   - contextual: preserves spiritual/emotional tone and faith context
 *
 * Setup:
 *   firebase functions:secrets:set ANTHROPIC_API_KEY
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.refineTranslation = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
/**
 * Refine a literal translation using Claude LLM
 */
exports.refineTranslation = (0, https_1.onCall)({
    secrets: [anthropicApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: true,
}, async (request) => {
    // Verify authentication
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated");
    }
    const data = request.data;
    const { originalText, literalTranslation, sourceLanguage, targetLanguage, mode, contentType, preservedEntities = [], } = data;
    // Validate
    if (!originalText || !literalTranslation || !mode) {
        throw new https_1.HttpsError("invalid-argument", "originalText, literalTranslation, and mode are required");
    }
    if (mode !== "natural" && mode !== "contextual") {
        throw new https_1.HttpsError("invalid-argument", "mode must be 'natural' or 'contextual'");
    }
    // Get API key
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
        throw new https_1.HttpsError("unavailable", "Translation refinement is not configured");
    }
    // Build entity preservation instructions
    const entityList = preservedEntities
        .map((e) => `- ${e.type}: "${e.text}"`)
        .join("\n");
    const entityInstructions = entityList
        ? `\n\nIMPORTANT — These entities MUST appear exactly as-is in your output (do NOT translate them):\n${entityList}`
        : "";
    // Build system prompt based on mode
    const systemPrompt = mode === "natural"
        ? buildNaturalPrompt(sourceLanguage, targetLanguage, entityInstructions)
        : buildContextualPrompt(sourceLanguage, targetLanguage, contentType, entityInstructions);
    // Select model — Haiku for natural (fast, cheap), Sonnet for contextual (deeper)
    const model = mode === "natural"
        ? "claude-3-haiku-20240307"
        : "claude-3-5-sonnet-20241022";
    try {
        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
                model,
                max_tokens: 1500,
                temperature: mode === "natural" ? 0.3 : 0.5,
                system: systemPrompt,
                messages: [
                    {
                        role: "user",
                        content: `Original (${sourceLanguage}): ${originalText}\n\nLiteral translation (${targetLanguage}): ${literalTranslation}\n\nProvide ONLY the refined translation. No explanations, no notes, no quotes around it.`,
                    },
                ],
            }),
        });
        if (!response.ok) {
            const errorText = await response.text();
            console.error(`Claude API error: ${response.status}`, errorText);
            throw new Error(`LLM refinement failed: ${response.status}`);
        }
        const result = await response.json();
        const refinedText = result.content?.[0]?.text?.trim() || literalTranslation;
        console.log(`refineTranslation (${mode}/${model}) — ` +
            `${sourceLanguage}→${targetLanguage} — ` +
            `tokens: ${result.usage?.output_tokens || 0}`);
        return {
            refinedText,
            mode,
            model,
            usage: result.usage,
        };
    }
    catch (error) {
        const message = error instanceof Error ? error.message : "Unknown error";
        console.error("refineTranslation error:", message);
        // Graceful degradation: return literal as fallback
        return {
            refinedText: literalTranslation,
            mode,
            model: "fallback",
            error: message,
        };
    }
});
function buildNaturalPrompt(sourceLang, targetLang, entityInstructions) {
    return `You are a professional translator refining a machine translation. Your goal is to make the translation sound completely natural and native in ${targetLang}, as if originally written in that language.

Rules:
- Rewrite the literal translation to sound natural and fluent
- Preserve the original meaning exactly
- Use natural idioms and phrasing for ${targetLang}
- Keep the same tone (formal, casual, emotional) as the original
- Keep the same length approximately
- Do NOT add information not in the original
- Do NOT change the meaning or add your own interpretation${entityInstructions}`;
}
function buildContextualPrompt(sourceLang, targetLang, contentType, entityInstructions) {
    return `You are a faith-aware translator refining a machine translation for the AMEN Christian social app. Your goal is to preserve spiritual meaning, emotional tone, and cultural context while making the translation sound natural in ${targetLang}.

Content type: ${contentType}

Rules:
- Preserve the spiritual and emotional meaning of the original
- Keep faith-specific terms culturally appropriate for ${targetLang} speakers
- Maintain the same level of intimacy/vulnerability as the original
- If the original is a prayer, testimony, or confession, handle with extra care
- If the original references church practices, keep them understandable across traditions
- Keep Bible verse references in their standard ${targetLang} citation format
- Do NOT water down, sanitize, or theologize the content
- Do NOT add theological interpretation or commentary
- Do NOT change the doctrinal stance or denominational framing
- Keep the same approximate length${entityInstructions}`;
}
//# sourceMappingURL=refineTranslation.js.map