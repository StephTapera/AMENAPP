// berean/services/ModelRouter.ts
// Routes LLM calls to the appropriate model based on task type and cost budget.
// All credentials stay server-side — never pass API keys to the client.

import * as admin from "firebase-admin";
import { LLMStructuredOutput } from "../models/berean";

type ModelTier = "fast" | "standard" | "deep";

export interface ModelCallParams {
  systemPrompt: string;
  userPrompt: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  tier?: ModelTier;
  modelId?: string;
  maxTokens?: number;
}

export class ModelRouter {
  /** Route to a Cloud Function proxy that holds the actual LLM credentials. */
  async callStructured(params: ModelCallParams): Promise<LLMStructuredOutput> {
    const tier = params.tier ?? "standard";
    const fnName = this.resolveFunctionName(tier);
    const modelId = params.modelId ?? this.resolveModelId(tier);

    const payload = {
      systemPrompt: params.systemPrompt,
      userPrompt: params.userPrompt,
      conversationHistory: params.conversationHistory ?? [],
      maxTokens: params.maxTokens ?? 1024,
      outputFormat: "json",
      modelId,
    };

    try {
      // Call the Genkit/Cloud Run LLM proxy that holds model credentials
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const result = await (admin.app() as any).functions().httpsCallable(fnName)(payload);
      const data = result.data as Record<string, unknown>;

      if (data.error) {
        throw new Error(String(data.error));
      }

      // Parse the structured JSON output from the model
      const raw = data.content as string;
      return this.parseStructuredOutput(raw);
    } catch (err) {
      console.error(`[ModelRouter] ${fnName} failed:`, err);
      throw err;
    }
  }

  private resolveFunctionName(tier: ModelTier): string {
    switch (tier) {
      case "fast":
        return "bereanChatProxy"; // Fast path: existing Genkit proxy
      case "deep":
        return "bereanChatProxy"; // Same proxy, different system prompt depth
      case "standard":
      default:
        return "bereanChatProxy";
    }
  }

  private resolveModelId(tier: ModelTier): string {
    switch (tier) {
      case "fast":
        return "claude-haiku-4-5";
      case "deep":
        return "claude-opus-4-1";
      case "standard":
      default:
        return "claude-sonnet-4-5";
    }
  }

  private parseStructuredOutput(raw: string): LLMStructuredOutput {
    // Strip any markdown code fencing if the model wrapped it
    const cleaned = raw
      .replace(/^```(?:json)?\n?/m, "")
      .replace(/\n?```$/m, "")
      .trim();

    try {
      return JSON.parse(cleaned) as LLMStructuredOutput;
    } catch {
      // Fallback: return a visible retry state instead of a blank response.
      return {
        answerText: "Berean encountered an issue parsing the response. Tap to retry.",
        scriptureReferences: [],
        studyCards: [
          {
            type: "context",
            title: "Retry Needed",
            body: "Berean encountered an issue parsing the response. Please try again.",
            metadata: { retryable: true, rawPreview: raw.slice(0, 240) },
          },
        ],
        reflectionPrompts: [],
        prayerPrompt: null,
        leadershipPrompt: { show: false, title: "Retry", body: "Retry this Berean response." },
        sensitivitySummary: {
          primaryState: "neutral",
          sensitivityFlags: [],
          topicClass: null,
        },
        suggestedNextActions: [
          {
            type: "view_journey",
            label: "Retry response",
            payload: { retryable: true },
          },
        ],
        confidenceNotes: {
          containsInterpretiveCaution: true,
          containsLeadershipRedirect: false,
        },
      };
    }
  }
}

export const modelRouter = new ModelRouter();
