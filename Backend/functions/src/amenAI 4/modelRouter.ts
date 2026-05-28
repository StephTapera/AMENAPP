export type AmenAIProvider = "claude" | "openai" | "gemini" | "local" | "backend";
export type AmenAIExecutionPath = "backend_only" | "direct_client" | "local_only";
export type AmenAIRiskTier = "low" | "medium" | "high" | "restricted";

export type AmenAITaskType =
  | "daily_verse_quick_reflection"
  | "church_note_title_summary"
  | "smart_message_summary"
  | "post_caption_suggestion"
  | "church_grounded_search"
  | "church_notes_file_search"
  | "tts_narration"
  | "image_generation"
  | "video_generation"
  | "berean_quick_answer"
  | "berean_deep_study"
  | "pastoral_care"
  | "moderation"
  | "crisis"
  | "paid_entitlement"
  | "feed_ranking"
  | "creator_monetization"
  | "final_publish_decision";

export interface AmenAIRouteRequest {
  taskType: AmenAITaskType;
  surface: string;
  preferredProvider?: AmenAIProvider;
  preferredExecutionPath?: AmenAIExecutionPath;
  userConsentedToSensitiveClientAI?: boolean;
  timeoutBudgetMs?: number;
  costBudgetMicroUSD?: number;
  modelOverride?: string;
  sensitiveCategories?: string[];
}

export interface AmenAIRouteDecision {
  taskType: AmenAITaskType;
  provider: AmenAIProvider;
  model: string;
  executionPath: AmenAIExecutionPath;
  riskTier: AmenAIRiskTier;
  timeoutBudgetMs: number;
  costBudgetMicroUSD: number;
  blockedReason?: string;
  requiresConsent: boolean;
}

const backendOnlyTasks = new Set<AmenAITaskType>([
  "moderation",
  "crisis",
  "paid_entitlement",
  "feed_ranking",
  "creator_monetization",
  "final_publish_decision",
  "berean_deep_study",
  "pastoral_care",
  "church_notes_file_search",
  "image_generation",
  "video_generation",
]);

const backendOnlySensitiveCategories = new Set([
  "prayer",
  "confession",
  "private_message",
  "trauma",
  "minors",
  "crisis",
  "sensitive_note",
  "paid_content",
  "monetization",
  "moderation",
]);

export function routeAmenAIRequest(request: AmenAIRouteRequest): AmenAIRouteDecision {
  const sensitive = request.sensitiveCategories ?? [];
  const requiresConsent = sensitive.length > 0;
  const requiresBackendForSensitivity = sensitive.some((category) => backendOnlySensitiveCategories.has(category));
  const riskTier = riskFor(request.taskType, sensitive);
  const directClientRequested = request.preferredExecutionPath === "direct_client";
  const mustStayBackend = backendOnlyTasks.has(request.taskType) || requiresBackendForSensitivity || riskTier === "high" || riskTier === "restricted";

  if (directClientRequested && requiresConsent && !request.userConsentedToSensitiveClientAI) {
    return blocked(request, riskTier, "sensitive_content_requires_explicit_consent");
  }

  if (directClientRequested && mustStayBackend) {
    return blocked(request, riskTier, "task_requires_backend_only");
  }

  const provider = request.preferredProvider ?? defaultProviderFor(request.taskType, directClientRequested);
  return {
    taskType: request.taskType,
    provider,
    model: request.modelOverride || defaultModelFor(provider),
    executionPath: provider === "local" ? "local_only" : mustStayBackend ? "backend_only" : directClientRequested ? "direct_client" : "backend_only",
    riskTier,
    timeoutBudgetMs: request.timeoutBudgetMs ?? 5000,
    costBudgetMicroUSD: request.costBudgetMicroUSD ?? 1000,
    requiresConsent,
  };
}

function blocked(request: AmenAIRouteRequest, riskTier: AmenAIRiskTier, blockedReason: string): AmenAIRouteDecision {
  const provider = request.preferredProvider ?? "backend";
  return {
    taskType: request.taskType,
    provider,
    model: request.modelOverride || defaultModelFor(provider),
    executionPath: "backend_only",
    riskTier,
    timeoutBudgetMs: request.timeoutBudgetMs ?? 5000,
    costBudgetMicroUSD: request.costBudgetMicroUSD ?? 1000,
    blockedReason,
    requiresConsent: (request.sensitiveCategories ?? []).length > 0,
  };
}

function riskFor(taskType: AmenAITaskType, sensitiveCategories: string[]): AmenAIRiskTier {
  if (sensitiveCategories.includes("crisis") || sensitiveCategories.includes("minors")) return "restricted";
  if (backendOnlyTasks.has(taskType)) return "restricted";
  if (sensitiveCategories.length > 0) return "high";
  if (["smart_message_summary", "church_grounded_search", "tts_narration", "berean_quick_answer"].includes(taskType)) return "medium";
  return "low";
}

function defaultProviderFor(taskType: AmenAITaskType, directClientRequested: boolean): AmenAIProvider {
  if (directClientRequested && ["daily_verse_quick_reflection", "church_note_title_summary", "post_caption_suggestion", "church_grounded_search", "tts_narration"].includes(taskType)) {
    return "gemini";
  }
  if (["berean_deep_study", "pastoral_care", "berean_quick_answer"].includes(taskType)) return "claude";
  return "backend";
}

function defaultModelFor(provider: AmenAIProvider): string {
  switch (provider) {
    case "gemini": return "gemini-3.5-flash";
    case "claude": return "server_selected_claude";
    case "openai": return "server_selected_openai";
    case "local": return "on_device_policy_v1";
    case "backend": return "server_selected";
  }
}
