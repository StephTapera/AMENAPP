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

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { enforceRateLimit, RATE_LIMITS } from "../../rateLimit";
import { getPassagePayload } from "../services/ScriptureGraphService";
import { recordDiscipleshipEvent } from "../services/DiscipleshipTrackerService";
import { StudyPassageRequest, ScripturePassagePayload } from "../models/berean";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

/**
 * Berean Living Scripture Graph — Passage Study Endpoint
 */
export const bereanStudyPassage = onCall(
  {
    secrets: [anthropicApiKey],
    timeoutSeconds: 60,
    memory: "512MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const userId = request.auth.uid;

    await enforceRateLimit(userId, [
      RATE_LIMITS.bereanPerMinute,
      RATE_LIMITS.bereanDailyBudget,
    ]);

    const body = request.data as StudyPassageRequest;
    if (!body?.reference?.trim()) {
      throw new HttpsError("invalid-argument", "reference is required (e.g. 'John 3:16')");
    }

    let payload: ScripturePassagePayload;
    try {
      payload = await getPassagePayload(
        {
          reference: body.reference,
          translation: body.translation ?? "ESV",
          includeWordStudy: body.includeWordStudy ?? true,
          includeChristConnection: body.includeChristConnection ?? true,
          includeImmersionMode: body.includeImmersionMode ?? false,
        },
        anthropicApiKey.value()
      );
    } catch (err) {
      console.error("[bereanStudyPassage] Graph hydration failed:", err);
      throw new HttpsError("internal", "Failed to build scripture payload");
    }

    // Record study event (fire-and-forget)
    recordDiscipleshipEvent(userId, "study_session_completed", {
      passageId: payload.id,
      passageReference: body.reference,
    }).catch(() => {/* non-fatal */});

    return payload;
  }
);
