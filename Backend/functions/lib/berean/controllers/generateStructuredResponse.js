"use strict";
/**
 * generateStructuredResponse.ts
 *
 * Cloud Function: `bereanGenerateStructuredResponse`
 *
 * The primary entry point for Berean Spiritual Intelligence queries.
 * Orchestrates:
 *   1. Spiritual State Discernment (classifySpiritualState)
 *   2. System prompt selection (buildSystemPrompt)
 *   3. Structured response generation (Anthropic API)
 *   4. Authority guardrail audit (auditResponse)
 *   5. Discipleship event recording (recordDiscipleshipEvent)
 *   6. Follow-up prompt creation
 *
 * Pattern: mirrors bereanChatProxy.ts — onCall, secrets, rate limiting.
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.bereanGenerateStructuredResponse = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const uuid_1 = require("uuid");
const rateLimit_1 = require("../../rateLimit");
const SpiritualStateEngine_1 = require("../services/SpiritualStateEngine");
const systemPrompt_1 = require("../prompts/systemPrompt");
const structuredOutputContract_1 = require("../prompts/structuredOutputContract");
const AuthorityGuardrailEngine_1 = require("../services/AuthorityGuardrailEngine");
const DiscipleshipTrackerService_1 = require("../services/DiscipleshipTrackerService");
const anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
/**
 * Berean Spiritual Intelligence — Structured Response Generator
 */
exports.bereanGenerateStructuredResponse = (0, https_1.onCall)({
    secrets: [anthropicApiKey],
    timeoutSeconds: 90,
    memory: "512MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: false,
}, async (request) => {
    // Auth check
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required for Berean AI");
    }
    const userId = request.auth.uid;
    // Rate limiting — reuses the existing infrastructure
    await (0, rateLimit_1.enforceRateLimit)(userId, [
        rateLimit_1.RATE_LIMITS.bereanPerMinute,
        rateLimit_1.RATE_LIMITS.bereanDailyBudget,
    ]);
    const body = request.data;
    if (!body?.userMessage?.trim()) {
        throw new https_1.HttpsError("invalid-argument", "userMessage is required");
    }
    const conversationHistory = body.previousMessages ?? [];
    const passageContext = body.passageContext;
    // 1. Classify spiritual state
    const spiritualState = await (0, SpiritualStateEngine_1.classifySpiritualState)(userId, body.userMessage, conversationHistory);
    // 2. Build system prompt
    const systemPrompt = (0, systemPrompt_1.buildSystemPrompt)(spiritualState.selectedResponseMode, spiritualState.primaryState, passageContext) + "\n\n" + structuredOutputContract_1.STRUCTURED_OUTPUT_INSTRUCTION;
    // 3. Build message history for Anthropic
    const messages = [
        ...conversationHistory.map((m) => ({
            role: m.role,
            content: m.content,
        })),
        { role: "user", content: body.userMessage },
    ];
    // 4. Call Anthropic API
    const rawResponse = await callAnthropicAPI(systemPrompt, messages, anthropicApiKey.value(), spiritualState.selectedResponseMode);
    // 5. Parse and validate structured response
    let parsed;
    try {
        const clean = rawResponse.replace(/^```json?\s*/i, "").replace(/```\s*$/, "").trim();
        parsed = (0, structuredOutputContract_1.validateStructuredResponse)(JSON.parse(clean));
    }
    catch {
        // Fallback: treat as plain text answer
        parsed = {
            answer: rawResponse,
            responseMode: spiritualState.selectedResponseMode,
            studyCards: [],
            sensitivityFlags: [],
            leadershipPromptShown: false,
            doctrinalConfidence: 0.7,
        };
    }
    // 6. Post-generation sensitivity flag detection
    const additionalFlags = (0, SpiritualStateEngine_1.detectSensitivityFlags)(String(parsed.answer ?? ""), spiritualState.primaryState);
    const allFlags = [
        ...(parsed.sensitivityFlags ?? []),
        ...additionalFlags,
    ];
    parsed.sensitivityFlags = [...new Set(allFlags)];
    // 7. Authority guardrail audit
    const partialResponse = {
        ...parsed,
        spiritualState,
        responseId: (0, uuid_1.v4)(),
        generatedAt: admin.firestore.Timestamp.now(),
    };
    const auditResult = (0, AuthorityGuardrailEngine_1.auditResponse)(partialResponse, spiritualState);
    // Apply any patches from the guardrail
    if (auditResult.patchedAnswer) {
        parsed.answer = auditResult.patchedAnswer;
    }
    parsed.sensitivityFlags = [...new Set([
            ...parsed.sensitivityFlags,
            ...auditResult.detectedFlags,
        ])];
    parsed.leadershipPromptShown = auditResult.leadershipPromptRequired;
    // 8. Create leadership referral if needed (fire-and-forget)
    if (auditResult.leadershipPromptRequired && auditResult.detectedFlags.length > 0) {
        const primaryFlag = auditResult.detectedFlags[0];
        if (primaryFlag === "crisis_escalation" || primaryFlag === "pastoral_escalation") {
            (0, AuthorityGuardrailEngine_1.createLeadershipReferral)(userId, primaryFlag, (0, AuthorityGuardrailEngine_1.buildEscalationContextSummary)(passageContext ?? body.userMessage.slice(0, 50), primaryFlag), primaryFlag === "crisis_escalation"
                ? "Please reach out to this member directly or connect them with crisis resources."
                : "Consider following up with this member about their study question.").catch(() => { });
        }
    }
    // 9. Record discipleship event (fire-and-forget)
    (0, DiscipleshipTrackerService_1.recordDiscipleshipEvent)(userId, "study_session_completed", {
        passageReference: passageContext,
        bereanSessionId: body.conversationId,
    }).catch(() => { });
    // 10. Schedule follow-up if response includes a suggestion
    const followUpSuggestion = parsed.followUpSuggestion;
    if (followUpSuggestion && passageContext) {
        (0, DiscipleshipTrackerService_1.createFollowUpPrompt)(userId, body.conversationId, passageContext, followUpSuggestion, 24 // Deliver follow-up 24 hours later
        ).catch(() => { });
    }
    // 11. Build final response
    const finalResponse = {
        responseId: (0, uuid_1.v4)(),
        answer: String(parsed.answer),
        responseMode: spiritualState.selectedResponseMode,
        spiritualState: spiritualState,
        studyCards: (parsed.studyCards ?? []),
        sensitivityFlags: parsed.sensitivityFlags,
        leadershipPromptShown: Boolean(parsed.leadershipPromptShown),
        followUpSuggestion: followUpSuggestion,
        anchorPassage: parsed.anchorPassage,
        doctrinalConfidence: Number(parsed.doctrinalConfidence ?? 0.7),
        generatedAt: admin.firestore.Timestamp.now(),
    };
    return finalResponse;
});
// ---------------------------------------------------------------------------
// Anthropic API wrapper
// ---------------------------------------------------------------------------
async function callAnthropicAPI(system, messages, apiKey, mode) {
    // Use Sonnet for scholarly/exploratory; Haiku for pastoral/balanced real-time modes
    const usesSonnet = mode === "scholarly" || mode === "exploratory";
    const model = usesSonnet
        ? "claude-3-5-sonnet-20241022"
        : "claude-3-haiku-20240307";
    const maxTokens = usesSonnet ? 1500 : 800;
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
            system,
            messages,
        }),
    });
    if (!response.ok) {
        const error = await response.text().catch(() => "Unknown error");
        throw new https_1.HttpsError("internal", `Anthropic API error: ${response.status} — ${error}`);
    }
    const data = await response.json();
    return data.content?.find((b) => b.type === "text")?.text ?? "{}";
}
//# sourceMappingURL=generateStructuredResponse.js.map