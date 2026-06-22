"use strict";
/**
 * studyPassage.ts
 *
 * Cloud Function: `bereanStudyPassage`
 *
 * Fetches or builds the full Living Scripture Graph payload for a passage.
 * Orchestrates:
 *   1. Reference parsing
 *   2. Cache lookup (30-day TTL)
 *   3. LLM hydration (word study, cross-refs, Christ connection, immersion context)
 *   4. Discipleship event recording
 *
 * Model: claude-3-5-sonnet-20241022 (graph hydration requires depth)
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.bereanStudyPassage = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const rateLimit_1 = require("../../rateLimit");
const ScriptureGraphService_1 = require("../services/ScriptureGraphService");
const DiscipleshipTrackerService_1 = require("../services/DiscipleshipTrackerService");
const anthropicApiKey = (0, params_1.defineSecret)("ANTHROPIC_API_KEY");
/**
 * Berean Living Scripture Graph — Passage Study Endpoint
 */
exports.bereanStudyPassage = (0, https_1.onCall)({
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
    memory: "512MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: true,
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const userId = request.auth.uid;
    await (0, rateLimit_1.enforceRateLimit)(userId, [
        rateLimit_1.RATE_LIMITS.bereanPerMinute,
        rateLimit_1.RATE_LIMITS.bereanDailyBudget,
    ]);
    const body = request.data;
    if (!body?.reference?.trim()) {
        throw new https_1.HttpsError("invalid-argument", "reference is required (e.g. 'John 3:16')");
    }
    let payload;
    try {
        payload = await (0, ScriptureGraphService_1.getPassagePayload)({
            reference: body.reference,
            translation: body.translation ?? "ESV",
            includeWordStudy: body.includeWordStudy ?? true,
            includeChristConnection: body.includeChristConnection ?? true,
            includeImmersionMode: body.includeImmersionMode ?? false,
        }, anthropicApiKey.value());
    }
    catch (err) {
        console.error("[bereanStudyPassage] Graph hydration failed:", err);
        throw new https_1.HttpsError("internal", "Failed to build scripture payload");
    }
    // Record study event (fire-and-forget)
    (0, DiscipleshipTrackerService_1.recordDiscipleshipEvent)(userId, "study_session_completed", {
        passageId: payload.id,
        passageReference: body.reference,
    }).catch(() => { });
    return payload;
});
//# sourceMappingURL=studyPassage.js.map