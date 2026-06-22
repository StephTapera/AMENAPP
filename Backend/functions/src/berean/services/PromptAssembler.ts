// berean/services/PromptAssembler.ts
// Assembles the full LLM prompt from system prompt + mode instructions
// + sensitive topic policy + retrieved context + user message.

import { buildBereanSystemPrompt } from "../prompts/systemPrompt";
import { buildResponseModeInstructions } from "../prompts/responseModePrompt";
import { buildSensitiveTopicPolicyBlock } from "../prompts/sensitiveTopicPolicy";
import { buildStructuredOutputContract } from "../prompts/structuredOutputContract";
import {
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

export type MemoryScope = "off" | "this_chat" | "this_project" | "all_berean";

export interface PostContext {
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
}

export interface UserContext {
  faithJourneyStage?: string;
  persona?: string;
}

export interface ScriptureContext {
  preferredTranslation?: string;
  quotedReference?: string;
}

export interface AppContext {
  surface: string;
  mayBeSharedPublicly: boolean;
  currentMode: string;
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
    postContext?: PostContext;
    userContext?: UserContext;
    scriptureContext?: ScriptureContext;
    appContext?: AppContext;
  }): PromptPackage {
    const {
      userMessage,
      classification,
      topicClass,
      additionalFlags,
      passageContext,
      retrievedScriptureContext = [],
      postContext,
      userContext,
      scriptureContext,
      appContext,
    } = params;

    // ── System Prompt ──────────────────────────────────────────────────────────
    const systemParts: string[] = [
      buildBereanSystemPrompt(),
      buildResponseModeInstructions(classification.selectedResponseMode),
    ];

    // ── Sensitive topic policy block ───────────────────────────────────────────
    const allFlags = [
      ...new Set([...(classification.sensitivityFlags ?? []), ...additionalFlags]),
    ] as SensitivityFlag[];

    const policyBlock = buildSensitiveTopicPolicyBlock(allFlags, topicClass);
    if (policyBlock) {
      systemParts.push(policyBlock);
    }

    if (appContext) {
      systemParts.push(
        [
          `APP CONTEXT`,
          `Surface: ${appContext.surface}`,
          `Conversation mode: ${appContext.currentMode}`,
          appContext.mayBeSharedPublicly
            ? `The user may share or discuss this response on a public Christian community surface. Write with that visibility in mind.`
            : `This is a private in-app Berean conversation.`
        ].join("\n")
      );
    }

    if (userContext?.faithJourneyStage || userContext?.persona) {
      const identityLines = [`USER CONTEXT`];
      if (userContext.faithJourneyStage) {
        identityLines.push(`Faith journey stage: ${userContext.faithJourneyStage}`);
      }
      if (userContext.persona) {
        identityLines.push(`Persona or role: ${userContext.persona}`);
      }
      identityLines.push(
        `Use this context to calibrate depth, vocabulary, and examples. Do not reduce safety, humility, or doctrinal charity because of persona.`
      );
      systemParts.push(identityLines.join("\n"));
    }

    if (scriptureContext?.preferredTranslation || scriptureContext?.quotedReference) {
      const scriptureLines = [`SCRIPTURE PREFERENCE CONTEXT`];
      if (scriptureContext.preferredTranslation) {
        scriptureLines.push(`Preferred translation: ${scriptureContext.preferredTranslation}`);
      }
      if (scriptureContext.quotedReference) {
        scriptureLines.push(`Quoted or active reference: ${scriptureContext.quotedReference}`);
      }
      scriptureLines.push(
        `When referring back to the same passage, preserve the user's translation context when known and do not imply a different translation was quoted.`
      );
      systemParts.push(scriptureLines.join("\n"));
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

    if (postContext) {
      const postLines = [
        `POST CONTEXT`,
        `Post ID: ${postContext.postId}`,
        `Author ID: ${postContext.authorId}`,
        `Author: ${postContext.authorName}`,
        `Category: ${postContext.category}`,
        `Safe summary: ${postContext.previewText}`,
        `Treat this post context as canonical for the current turn.`,
      ];
      if (postContext.bodyText) {
        postLines.push(`Post body: ${postContext.bodyText}`);
      }
      if (postContext.verseReference) {
        postLines.push(`Scripture reference: ${postContext.verseReference}`);
      }
      if (postContext.verseText) {
        postLines.push(`Scripture text: ${postContext.verseText}`);
      }
      if (postContext.mediaSummary) {
        postLines.push(`Media metadata: ${postContext.mediaSummary}`);
      }
      if (postContext.isSensitive) {
        postLines.push(
          `This post is sensitive. Do not reveal hidden details beyond the safe summary.`
        );
      }
      postLines.push(
        `Use the author context, scripture references, and media metadata to interpret the user's question about this post.`
      );
      systemParts.push(postLines.join("\n"));
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
        `[DETECTED USER STATE: ${classification.primaryState} | Response mode: ${classification.selectedResponseMode}]`
      );
    }

    userParts.push(userMessage);

    return {
      systemPrompt: systemParts.join("\n\n"),
      userPrompt: userParts.join("\n"),
    };
  }

  buildContextMessages(
    history: ContextMessage[],
    memoryScope: MemoryScope = "this_chat"
  ): Array<{ role: string; content: string }> {
    const scopedHistory = (() => {
      switch (memoryScope) {
        case "off":
          return [];
        case "this_chat":
          return history.slice(-10);
        case "this_project":
          return history.slice(-6);
        case "all_berean":
          return history;
        default:
          return history.slice(-10);
      }
    })();

    const tokenBudget = this.historyTokenBudget(memoryScope);
    if (this.estimateHistoryTokens(scopedHistory) <= tokenBudget) {
      return scopedHistory.map((m) => ({
        role: m.role,
        content: m.content,
      }));
    }

    const recentMessages: ContextMessage[] = [];
    let recentTokens = 0;
    const recentBudget = Math.floor(tokenBudget * 0.55);
    for (let index = scopedHistory.length - 1; index >= 0; index -= 1) {
      const message = scopedHistory[index];
      const messageTokens = this.estimateMessageTokens(message);
      if (recentMessages.length >= 4 && recentTokens + messageTokens > recentBudget) {
        break;
      }
      recentMessages.unshift(message);
      recentTokens += messageTokens;
    }

    const olderMessages = scopedHistory.slice(0, scopedHistory.length - recentMessages.length);
    const summarizedHistory = this.summarizeHistory(olderMessages);
    const condensedHistory = summarizedHistory
      ? [{ role: "assistant", content: summarizedHistory }, ...recentMessages]
      : recentMessages;

    return condensedHistory.map((m) => ({
      role: m.role,
      content: m.content,
    }));
  }

  private historyTokenBudget(memoryScope: MemoryScope): number {
    switch (memoryScope) {
      case "off":
        return 0;
      case "this_project":
        return 1100;
      case "all_berean":
        return 1500;
      case "this_chat":
      default:
        return 1300;
    }
  }

  private estimateHistoryTokens(history: ContextMessage[]): number {
    return history.reduce((sum, message) => sum + this.estimateMessageTokens(message), 0);
  }

  private estimateMessageTokens(message: ContextMessage): number {
    return Math.ceil(message.content.length / 4) + 8;
  }

  private summarizeHistory(history: ContextMessage[]): string {
    if (history.length === 0) {
      return "";
    }

    const summaryLines = history.slice(-6).map((message, index) => {
      const speaker = message.role === "user" ? "User" : "Berean";
      return `${index + 1}. ${speaker}: ${this.clipForSummary(message.content)}`;
    });

    return [
      "Conversation summary of earlier turns. Treat this as compressed context from older messages:",
      ...summaryLines,
    ].join("\n");
  }

  private clipForSummary(text: string): string {
    const flattened = text.replace(/\s+/g, " ").trim();
    if (flattened.length <= 180) {
      return flattened;
    }
    return `${flattened.slice(0, 177)}...`;
  }
}

export const promptAssembler = new PromptAssembler();
