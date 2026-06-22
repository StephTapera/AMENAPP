"use strict";
/**
 * transformContent.ts
 *
 * Cloud Function for the Understand Sheet readability engine.
 * Takes post content + readability mode, returns LLM-transformed text.
 *
 * Modes:
 *   - simplify: Rewrite at 8th-grade reading level
 *   - summarize: 3-5 bullet point summary
 *   - keyTerms: Extract + define key terms with related verses
 *   - explain: Newcomer-friendly explanation
 *   - expandContext: Historical/theological background
 *
 * Uses Claude Haiku for fast, low-cost transformations.
 * Preserves verse references and faith-specific terminology.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.transformContent = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
exports.transformContent = (0, https_1.onCall)({
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: true,
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated to use Understand features");
    }
    const data = request.data;
    const { text, mode, language, contentId } = data;
    if (!text || typeof text !== "string" || text.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", "Text is required and must be a non-empty string");
    }
    const validModes = ["simplify", "summarize", "keyTerms", "explain", "expandContext"];
    if (!mode || !validModes.includes(mode)) {
        throw new https_1.HttpsError("invalid-argument", `Mode must be one of: ${validModes.join(", ")}`);
    }
    const apiKey = anthropicApiKey.value();
    if (!apiKey) {
        console.error("ANTHROPIC_API_KEY not configured");
        throw new https_1.HttpsError("unavailable", "Service not configured. Please contact support.");
    }
    try {
        const systemPrompt = buildSystemPrompt(mode, language);
        const userPrompt = buildUserPrompt(text, mode);
        const response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            },
            body: JSON.stringify({
                model: "claude-3-haiku-20240307",
                max_tokens: 1500,
                temperature: 0.3,
                system: systemPrompt,
                messages: [{ role: "user", content: userPrompt }],
            }),
        });
        if (!response.ok) {
            const errorText = await response.text();
            console.error(`Claude API error: ${response.status}`, errorText);
            throw new https_1.HttpsError("unavailable", `Claude API error: ${response.status}`);
        }
        const result = await response.json();
        const responseText = result.content?.[0]?.text || "";
        // Parse structured response for keyTerms mode
        if (mode === "keyTerms") {
            const parsed = parseKeyTermsResponse(responseText);
            console.log(`transformContent (${mode}) — content: ${contentId} — tokens: ${result.usage?.output_tokens || 0}`);
            return {
                transformedText: parsed.summary,
                keyTerms: parsed.terms,
                mode,
                contentId,
                usage: result.usage,
            };
        }
        console.log(`transformContent (${mode}) — content: ${contentId} — tokens: ${result.usage?.output_tokens || 0}`);
        return {
            transformedText: responseText,
            mode,
            contentId,
            usage: result.usage,
        };
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        const errorMessage = error instanceof Error ? error.message : "Unknown error";
        console.error("transformContent error:", errorMessage);
        throw new https_1.HttpsError("internal", "Failed to transform content");
    }
});
function buildSystemPrompt(mode, language) {
    const base = `You are a content accessibility assistant for a Christian social app called AMEN.
Your job is to make faith-based content more accessible and understandable.

Rules:
- ALWAYS preserve Bible verse references exactly (e.g., John 3:16, Psalm 23:1-6)
- ALWAYS preserve @mentions and #hashtags exactly as they appear
- Respond in ${language || "en"} (the user's language)
- Be respectful of all Christian traditions and denominations
- Do not add your own theological opinions — explain what the content says`;
    const modeInstructions = {
        simplify: `${base}

MODE: Simplify
Rewrite the content at an 8th-grade reading level.
- Use shorter sentences (under 15 words each)
- Replace uncommon words with simpler alternatives
- Keep the same meaning and tone
- Preserve all verse references, mentions, and hashtags
- Do NOT add information that wasn't in the original`,
        summarize: `${base}

MODE: Summarize
Create a clear, concise summary of the content.
- Use 3-5 bullet points (use • character)
- Each bullet should capture one key idea
- Include relevant verse references mentioned
- Keep bullets under 20 words each`,
        keyTerms: `${base}

MODE: Key Terms
Extract and define important terms from the content.

Respond in this exact format:
SUMMARY: [1-2 sentence overview of the content]

TERM: [term name]
DEFINITION: [clear, accessible definition]
VERSE: [related Bible verse reference, or "None"]

TERM: [next term]
DEFINITION: [definition]
VERSE: [verse or "None"]

Extract 3-7 terms. Focus on:
- Theological concepts (grace, redemption, sanctification, etc.)
- Faith-specific vocabulary
- Names of biblical figures or places
- Any term a newcomer to Christianity might not understand`,
        explain: `${base}

MODE: Explain for Newcomers
Rewrite this content as if explaining it to someone who is new to Christianity.
- Define any faith-specific terms inline
- Add brief context for verse references
- Use warm, welcoming language
- Don't assume prior Bible knowledge
- Keep the same message and intent`,
        expandContext: `${base}

MODE: Expand Historical/Theological Context
Add helpful context to understand this content more deeply.
- Historical background for referenced events or figures
- Cultural context from the time period
- How different Christian traditions may interpret this
- Related passages that add depth
- Format as flowing paragraphs, not bullets`,
    };
    return modeInstructions[mode] || modeInstructions.explain;
}
function buildUserPrompt(text, mode) {
    const modeVerbs = {
        simplify: "Simplify",
        summarize: "Summarize",
        keyTerms: "Extract key terms from",
        explain: "Explain for a newcomer",
        expandContext: "Add historical and theological context to",
    };
    const verb = modeVerbs[mode] || "Process";
    return `${verb} the following content:\n\n${text}`;
}
/**
 * Parse the structured keyTerms response into summary + terms array
 */
function parseKeyTermsResponse(text) {
    const lines = text.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
    let summary = "";
    const terms = [];
    let currentTerm = null;
    for (const line of lines) {
        if (line.startsWith("SUMMARY:")) {
            summary = line.replace("SUMMARY:", "").trim();
        }
        else if (line.startsWith("TERM:")) {
            if (currentTerm && currentTerm.term) {
                terms.push(currentTerm);
            }
            currentTerm = {
                term: line.replace("TERM:", "").trim(),
                definition: "",
                relatedVerse: null,
            };
        }
        else if (line.startsWith("DEFINITION:") && currentTerm) {
            currentTerm.definition = line.replace("DEFINITION:", "").trim();
        }
        else if (line.startsWith("VERSE:") && currentTerm) {
            const verse = line.replace("VERSE:", "").trim();
            currentTerm.relatedVerse = verse.toLowerCase() === "none" ? null : verse;
        }
    }
    if (currentTerm && currentTerm.term) {
        terms.push(currentTerm);
    }
    return { summary: summary || "Key terms from this content:", terms };
}
//# sourceMappingURL=transformContent.js.map