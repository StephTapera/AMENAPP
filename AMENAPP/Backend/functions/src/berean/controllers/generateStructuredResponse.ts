// berean/controllers/generateStructuredResponse.ts
// The primary Berean orchestration pipeline.
// Called by BereanAPIClient.swift for all conversation messages.
//
// Pipeline:
//   1. Authenticate + App Check
//   2. Validate payload
//   3. Rate limit check (TODO: add quota)
//   4. Persist user message
//   5. Classify spiritual state
//   6. Evaluate authority escalation
//   7. Retrieve conversation context
//   8. Assemble structured prompt
//   9. Call LLM
//  10. Run post-generation safety validation
//  11. Persist assistant message
//  12. Fire analytics + safety events
//  13. Return structured response

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

import { spiritualStateEngine } from "../services/SpiritualStateEngine";
import { authorityGuardrailEngine } from "../services/AuthorityGuardrailEngine";
import { promptAssembler } from "../services/PromptAssembler";
import { modelRouter } from "../services/ModelRouter";
import { safetyValidator } from "../services/SafetyValidator";
import { discipleshipTrackerService } from "../services/DiscipleshipTrackerService";
import { analyticsService } from "../services/AnalyticsService";
import { conversationRepository } from "../repositories/ConversationRepository";
import { safetyEventRepository } from "../repositories/SafetyEventRepository";
import { BereanStructuredResponse, LLMStructuredOutput } from "../models/berean";

export const bereanGenerateStructuredResponse = onCall(
  { region: "us-central1", timeoutSeconds: 60 },
  async (request): Promise<BereanStructuredResponse> => {
    // ── 1. Auth ──────────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    if (!request.app) {
      throw new HttpsError("unauthenticated", "App Check required.");
    }

    const userId = request.auth.uid;
    const {
      conversationId,
      userMessage,
      passageContext,
      previousMessages = [],
      currentMode = "chat",
    } = request.data as {
      conversationId: string;
      userMessage: string;
      passageContext?: string;
      previousMessages?: Array<{ role: string; content: string }>;
      currentMode?: string;
    };

    // ── 2. Validate ──────────────────────────────────────────────────────────
    if (!conversationId || typeof conversationId !== "string") {
      throw new HttpsError("invalid-argument", "conversationId is required.");
    }
    if (!userMessage || typeof userMessage !== "string" || userMessage.trim().length === 0) {
      throw new HttpsError("invalid-argument", "userMessage is required.");
    }
    if (userMessage.length > 4000) {
      throw new HttpsError("invalid-argument", "Message too long (max 4000 chars).");
    }

    const startTime = await analyticsService.logRequestStart(userId, conversationId);

    // ── 3. Ensure conversation exists ────────────────────────────────────────
    const existingConversation = await conversationRepository.getConversation(conversationId);
    if (!existingConversation) {
      await conversationRepository.createConversation(
        userId,
        conversationId,
        currentMode as "chat" | "study" | "journey" | "reflect" | "discuss"
      );
    }

    // ── 4. Persist user message ──────────────────────────────────────────────
    const userMessageId = admin.firestore().collection("berean_messages").doc().id;
    await conversationRepository.saveMessage(userMessageId, {
      conversationId,
      userId,
      role: "user",
      text: userMessage.trim(),
      responseMode: null,
      primaryThemes: [],
      passageIds: [],
      sensitivityFlags: [],
      structuredCards: [],
      leadershipPromptShown: false,
      createdAt: admin.firestore.Timestamp.now(),
    });

    // ── 5. Classify spiritual state ──────────────────────────────────────────
    const classification = spiritualStateEngine.classify(userMessage, {
      currentPassageId: passageContext,
    });

    // ── 6. Authority escalation evaluation ──────────────────────────────────
    const escalation = authorityGuardrailEngine.evaluate(
      userMessage,
      classification.sensitivityFlags
    );

    // Log safety session
    await safetyEventRepository.logStateSession(
      userId,
      conversationId,
      userMessageId,
      classification.primaryState,
      classification.responseMode,
      classification.sensitivityFlags,
      classification.leadershipEscalationRecommended
    );

    // ── 7. Build context messages ────────────────────────────────────────────
    const history = (previousMessages as Array<{ role: string; content: string }>)
      .slice(-8)
      .map((m) => ({ role: m.role as "user" | "assistant", content: m.content }));

    // ── 8. Assemble prompt ───────────────────────────────────────────────────
    const promptPackage = promptAssembler.assemble({
      userMessage: userMessage.trim(),
      conversationHistory: history,
      classification,
      topicClass: escalation.topicClass,
      additionalFlags: classification.sensitivityFlags,
      passageContext,
    });

    // ── 9. Call LLM ──────────────────────────────────────────────────────────
    let rawOutput: LLMStructuredOutput;
    try {
      rawOutput = await modelRouter.callStructured({
        systemPrompt: promptPackage.systemPrompt,
        userPrompt: promptPackage.userPrompt,
        conversationHistory: promptAssembler.buildContextMessages(history),
        tier: classification.primaryState === "academic" ? "deep" : "standard",
        maxTokens: classification.responseMode === "crisis_safe" ? 512 : 1024,
      });
    } catch (err) {
      console.error("[bereanGenerateStructuredResponse] LLM call failed:", err);
      await analyticsService.log({
        event: "llm_request_failed",
        userId,
        conversationId,
        latencyMs: Date.now() - startTime,
      });
      throw new HttpsError("internal", "Berean is temporarily unavailable. Please try again.");
    }

    // ── 10. Safety validation ────────────────────────────────────────────────
    const validation = safetyValidator.validate(rawOutput);
    if (!validation.isValid) {
      await analyticsService.logSafetyViolation(userId, conversationId, validation.violations);
      await safetyEventRepository.logSafetyEvent({
        userId,
        conversationId,
        messageId: userMessageId,
        eventType: "safety_violation",
        severity: "high",
        topicClass: escalation.topicClass,
        actionTaken: "response_replaced",
        leadershipRedirectShown: true,
        crisisSupportShown: classification.crisisSupportRecommended,
        createdAt: admin.firestore.Timestamp.now(),
      });
    }

    const finalOutput = validation.sanitizedOutput;

    // Enforce escalation cards if authority policy requires it
    if (escalation.safeResponsePolicy.mustShowLeadershipCard && !finalOutput.leadershipPrompt?.show) {
      finalOutput.leadershipPrompt = {
        show: true,
        title: "Connect With a Leader",
        body: "This topic is important to bring to a pastor or trusted mentor who knows you.",
        targetTypes: escalation.escalationTargets,
      };
    }

    if (escalation.safeResponsePolicy.mustShowCrisisSupport) {
      finalOutput.studyCards.push({
        type: "crisis_resource",
        title: "You're Not Alone",
        body: "If you're in crisis, please call or text 988 (US Suicide & Crisis Lifeline). You can also reach out to a pastor, counselor, or trusted friend.",
        metadata: { hotline: "988" },
      });
    }

    if (escalation.safeResponsePolicy.mustShowMedicalDisclaimer) {
      finalOutput.studyCards.push({
        type: "leadership",
        title: "Medical Note",
        body: "Berean is not a medical professional. Please consult your doctor about medical decisions.",
        metadata: {},
      });
    }

    if (escalation.safeResponsePolicy.mustShowLegalDisclaimer) {
      finalOutput.studyCards.push({
        type: "leadership",
        title: "Legal Note",
        body: "This is not legal advice. Please consult a qualified attorney for legal matters.",
        metadata: {},
      });
    }

    // ── 11. Persist assistant message ────────────────────────────────────────
    const assistantMessageId = admin.firestore().collection("berean_messages").doc().id;
    await conversationRepository.saveMessage(assistantMessageId, {
      conversationId,
      userId,
      role: "assistant",
      text: finalOutput.answerText,
      responseMode: classification.responseMode,
      primaryThemes: [],
      passageIds: passageContext ? [passageContext] : [],
      sensitivityFlags: classification.sensitivityFlags,
      structuredCards: finalOutput.studyCards,
      leadershipPromptShown: finalOutput.leadershipPrompt?.show ?? false,
      createdAt: admin.firestore.Timestamp.now(),
    });

    await conversationRepository.touchConversation(conversationId);

    // ── 12. Analytics + background tasks ────────────────────────────────────
    await analyticsService.logRequestComplete(
      userId,
      conversationId,
      startTime,
      false,
      classification.responseMode
    );

    // Fire-and-forget: record discipleship study session
    discipleshipTrackerService
      .recordStudySession(userId, conversationId, passageContext ?? null, [])
      .catch(() => {});

    // ── 13. Return ───────────────────────────────────────────────────────────
    return {
      success: true,
      message: {
        answerText: finalOutput.answerText,
        responseMode: classification.responseMode,
        scriptureReferences: finalOutput.scriptureReferences,
        studyCards: finalOutput.studyCards,
        reflectionPrompts: finalOutput.reflectionPrompts,
        prayerPrompt: finalOutput.prayerPrompt,
        leadershipPrompt: finalOutput.leadershipPrompt ?? null,
        sensitivitySummary: finalOutput.sensitivitySummary,
        suggestedNextActions: finalOutput.suggestedNextActions,
        confidenceNotes: finalOutput.confidenceNotes,
      },
    };
  }
);
