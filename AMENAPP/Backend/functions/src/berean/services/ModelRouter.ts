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
  maxTokens?: number;
}

export class ModelRouter {
  /** Route to a Cloud Function proxy that holds the actual LLM credentials. */
  async callStructured(params: ModelCallParams): Promise<LLMStructuredOutput> {
    const tier = params.tier ?? "standard";
    const fnName = this.resolveFunctionName(tier);

    const payload = {
      systemPrompt: params.systemPrompt,
      userPrompt: params.userPrompt,
      conversationHistory: params.conversationHistory ?? [],
      maxTokens: params.maxTokens ?? 1024,
      outputFormat: "json",
    };

    try {
      // Call the Genkit/Cloud Run LLM proxy that holds model credentials
      const result = await admin.app().functions().httpsCallable(fnName)(payload);
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

  private parseStructuredOutput(raw: string): LLMStructuredOutput {
    // Strip any markdown code fencing if the model wrapped it
    const cleaned = raw
      .replace(/^```(?:json)?\n?/m, "")
      .replace(/\n?```$/m, "")
      .trim();

    try {
      return JSON.parse(cleaned) as LLMStructuredOutput;
    } catch {
      // Fallback: build a minimal valid response
      return {
        answerText: raw,
        scriptureReferences: [],
        studyCards: [],
        reflectionPrompts: [],
        prayerPrompt: null,
        leadershipPrompt: { show: false },
        sensitivitySummary: {
          primaryState: "neutral",
          sensitivityFlags: [],
          topicClass: null,
        },
        suggestedNextActions: [],
        confidenceNotes: {
          containsInterpretiveCaution: false,
          containsLeadershipRedirect: false,
        },
      };
    }
  }
}

export const modelRouter = new ModelRouter();
