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

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { enforceRateLimit, RATE_LIMITS } from "../../rateLimit";
import { classifySpiritualState, detectSensitivityFlags } from "../services/SpiritualStateEngine";
import { buildSystemPrompt } from "../prompts/systemPrompt";
import {
  STRUCTURED_OUTPUT_INSTRUCTION,
  validateStructuredResponse,
} from "../prompts/structuredOutputContract";
import { auditResponse, createLeadershipReferral, buildEscalationContextSummary } from "../services/AuthorityGuardrailEngine";
import { recordDiscipleshipEvent, createFollowUpPrompt } from "../services/DiscipleshipTrackerService";
import {
  GenerateStructuredResponseRequest,
  BereanStructuredResponse,
  SensitivityFlag,
} from "../models/berean";
import {getBereanEntitlement} from "../services/BereanEntitlementService";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

/**
 * Berean Spiritual Intelligence — Structured Response Generator
 */
export const bereanGenerateStructuredResponse = onCall(
  {
    secrets: [anthropicApiKey],
    timeoutSeconds: 90,
    memory: "512MiB",
    // 5.1 FIX: Reject calls from clients without a valid App Check token.
    enforceAppCheck: true,
  },
  async (request) => {
    // Auth check
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required for Berean AI");
    }
    const userId = request.auth.uid;

    // Rate limiting — reuses the existing infrastructure
    await enforceRateLimit(userId, [
      RATE_LIMITS.bereanPerMinute,
      RATE_LIMITS.bereanDailyBudget,
    ]);

    // Free-tier daily cap: 3 Berean queries per day, enforced via Firestore transaction.
    const entitlement = await getBereanEntitlement(userId);
    if (entitlement.tier === "free") {
      const today = new Date().toISOString().slice(0, 10);
      const quotaRef = admin.firestore()
        .collection("users").doc(userId)
        .collection("aiQuota").doc(`berean_${today}`);
      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(quotaRef);
        const count = (snap.data()?.count as number) ?? 0;
        if (count >= 3) {
          throw new HttpsError(
            "resource-exhausted",
            "Daily Berean limit reached. Upgrade to AMEN+ for unlimited access."
          );
        }
        tx.set(quotaRef, {
          count: count + 1,
          uid: userId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      });
    }

    const body = request.data as GenerateStructuredResponseRequest;
    if (!body?.userMessage?.trim()) {
      throw new HttpsError("invalid-argument", "userMessage is required");
    }

    const conversationHistory = body.previousMessages ?? [];
    const passageContext = body.passageContext;

    // 1. Classify spiritual state
    const spiritualState = await classifySpiritualState(
      userId,
      body.userMessage,
      conversationHistory
    );

    // 2. Build system prompt
    const systemPrompt = buildSystemPrompt(
      spiritualState.selectedResponseMode,
      spiritualState.primaryState,
      passageContext
    ) + "\n\n" + STRUCTURED_OUTPUT_INSTRUCTION;

    // 3. Build message history for Anthropic
    const messages: Array<{ role: "user" | "assistant"; content: string }> = [
      ...conversationHistory.map((m) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
      { role: "user", content: body.userMessage },
    ];

    // 4. Call Anthropic API
    const rawResponse = await callAnthropicAPI(
      systemPrompt,
      messages,
      anthropicApiKey.value(),
      spiritualState.selectedResponseMode
    );

    // 5. Parse and validate structured response
    let parsed: Record<string, unknown>;
    try {
      const clean = rawResponse.replace(/^```json?\s*/i, "").replace(/```\s*$/, "").trim();
      parsed = validateStructuredResponse(JSON.parse(clean));
    } catch {
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
    const additionalFlags = detectSensitivityFlags(
      String(parsed.answer ?? ""),
      spiritualState.primaryState
    );
    const allFlags: SensitivityFlag[] = [
      ...((parsed.sensitivityFlags as SensitivityFlag[]) ?? []),
      ...additionalFlags,
    ];
    parsed.sensitivityFlags = [...new Set(allFlags)];

    // 7. Authority guardrail audit
    const partialResponse = {
      ...parsed,
      spiritualState,
      responseId: uuidv4(),
      generatedAt: admin.firestore.Timestamp.now(),
    } as unknown as BereanStructuredResponse;

    const auditResult = auditResponse(partialResponse, spiritualState);

    // Apply any patches from the guardrail
    if (auditResult.patchedAnswer) {
      parsed.answer = auditResult.patchedAnswer;
    }
    parsed.sensitivityFlags = [...new Set([
      ...(parsed.sensitivityFlags as SensitivityFlag[]),
      ...auditResult.detectedFlags,
    ])];
    parsed.leadershipPromptShown = auditResult.leadershipPromptRequired;

    // 8. Create leadership referral if needed (fire-and-forget)
    if (auditResult.leadershipPromptRequired && auditResult.detectedFlags.length > 0) {
      const primaryFlag = auditResult.detectedFlags[0];
      if (primaryFlag === "crisis_escalation" || primaryFlag === "pastoral_escalation") {
        createLeadershipReferral(
          userId,
          primaryFlag,
          buildEscalationContextSummary(
            passageContext ?? body.userMessage.slice(0, 50),
            primaryFlag
          ),
          primaryFlag === "crisis_escalation"
            ? "Please reach out to this member directly or connect them with crisis resources."
            : "Consider following up with this member about their study question."
        ).catch(() => {/* non-fatal */});
      }
    }

    // 9. Record discipleship event (fire-and-forget)
    recordDiscipleshipEvent(userId, "study_session_completed", {
      passageReference: passageContext,
      bereanSessionId: body.conversationId,
    }).catch(() => {/* non-fatal */});

    // 10. Schedule follow-up if response includes a suggestion
    const followUpSuggestion = parsed.followUpSuggestion as string | undefined;
    if (followUpSuggestion && passageContext) {
      createFollowUpPrompt(
        userId,
        body.conversationId,
        passageContext,
        followUpSuggestion,
        24  // Deliver follow-up 24 hours later
      ).catch(() => {/* non-fatal */});
    }

    // 11. Build final response
    const finalResponse: BereanStructuredResponse = {
      responseId: uuidv4(),
      answer: String(parsed.answer),
      responseMode: spiritualState.selectedResponseMode,
      spiritualState: spiritualState,
      studyCards: (parsed.studyCards ?? []) as BereanStructuredResponse["studyCards"],
      sensitivityFlags: parsed.sensitivityFlags as SensitivityFlag[],
      leadershipPromptShown: Boolean(parsed.leadershipPromptShown),
      followUpSuggestion: followUpSuggestion,
      anchorPassage: parsed.anchorPassage as string | undefined,
      doctrinalConfidence: Number(parsed.doctrinalConfidence ?? 0.7),
      generatedAt: admin.firestore.Timestamp.now(),
    };

    return finalResponse;
  }
);

// ---------------------------------------------------------------------------
// Anthropic API wrapper
// ---------------------------------------------------------------------------

async function callAnthropicAPI(
  system: string,
  messages: Array<{ role: "user" | "assistant"; content: string }>,
  apiKey: string,
  mode: string
): Promise<string> {
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
    throw new HttpsError("internal", `Anthropic API error: ${response.status} — ${error}`);
  }

  const data = await response.json() as {
    content?: Array<{ type?: string; text?: string }>;
  };

  return data.content?.find((b) => b.type === "text")?.text ?? "{}";
}
