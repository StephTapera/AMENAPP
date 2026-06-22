// berean/services/PromptAssembler.ts
// Assembles the full LLM prompt from system prompt + mode instructions
// + sensitive topic policy + retrieved context + user message.

import { buildBereanSystemPrompt } from "../prompts/systemPrompt";
import { buildResponseModeInstructions } from "../prompts/responseModePrompt";
import { buildSensitiveTopicPolicyBlock } from "../prompts/sensitiveTopicPolicy";
import { buildStructuredOutputContract } from "../prompts/structuredOutputContract";
import {
  ResponseMode,
  SensitivityFlag,
  TopicClass,
  SpiritualStateClassification,
} from "../models/berean";

export interface PromptPackage {
  systemPrompt: string;
  userPrompt: string;
}

export interface ContextMessage {
  role: "user" | "assistant";
  content: string;
}

export class PromptAssembler {
  assemble(params: {
    userMessage: string;
    conversationHistory: ContextMessage[];
    classification: SpiritualStateClassification;
    topicClass: TopicClass | null;
    additionalFlags: SensitivityFlag[];
    passageContext?: string;
    retrievedScriptureContext?: string[];
  }): PromptPackage {
    const {
      userMessage,
      classification,
      topicClass,
      additionalFlags,
      passageContext,
      retrievedScriptureContext = [],
    } = params;

    // ── System Prompt ──────────────────────────────────────────────────────────
    const systemParts: string[] = [
      buildBereanSystemPrompt(),
      buildResponseModeInstructions(classification.responseMode),
    ];

    // ── Sensitive topic policy block ───────────────────────────────────────────
    const allFlags = [
      ...new Set([...classification.sensitivityFlags, ...additionalFlags]),
    ] as SensitivityFlag[];

    const policyBlock = buildSensitiveTopicPolicyBlock(allFlags, topicClass);
    if (policyBlock) {
      systemParts.push(policyBlock);
    }

    // ── Retrieved scripture context ────────────────────────────────────────────
    if (retrievedScriptureContext.length > 0) {
      const ctx = retrievedScriptureContext
        .map((s, i) => `[${i + 1}] ${s}`)
        .join("\n");
      systemParts.push(
        `RETRIEVED SCRIPTURE CONTEXT (use as citations — do not fabricate references):\n${ctx}`
      );
    }

    // ── Output contract ────────────────────────────────────────────────────────
    systemParts.push(buildStructuredOutputContract());

    // ── User prompt ────────────────────────────────────────────────────────────
    const userParts: string[] = [];

    if (passageContext) {
      userParts.push(`[PASSAGE CONTEXT: ${passageContext}]`);
    }

    // Summarize spiritual state for the model
    if (classification.primaryState !== "neutral") {
      userParts.push(
        `[DETECTED USER STATE: ${classification.primaryState} | Response mode: ${classification.responseMode}]`
      );
    }

    userParts.push(userMessage);

    return {
      systemPrompt: systemParts.join("\n\n"),
      userPrompt: userParts.join("\n"),
    };
  }

  buildContextMessages(history: ContextMessage[]): Array<{ role: string; content: string }> {
    return history.slice(-10).map((m) => ({
      role: m.role,
      content: m.content,
    }));
  }
}

export const promptAssembler = new PromptAssembler();
