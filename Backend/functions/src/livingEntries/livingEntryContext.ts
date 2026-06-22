import { clamp01, LivingEntryIntent } from "./livingEntryScoring";

export interface ContextInput {
  priorityScore?: number;
  gravityScore?: number;
  spiritualWeight?: number;
  intent?: LivingEntryIntent;
  dueAtMillis?: number | null;
  churchId?: string | null;
  nearbyChurchId?: string | null;
  recentChurchVisitId?: string | null;
  serviceStartAtMillis?: number | null;
  isSunday?: boolean;
  appOpenedAfterInactivity?: boolean;
  eveningHours?: boolean;
  lowMotion?: boolean;
  activeTyping?: boolean;
}

export interface ContextResult {
  contextMatchScore: number;
  interruptionPenalty: number;
  surfaceScore: number;
  reasons: string[];
}

export function evaluateContext(input: ContextInput, nowMillis: number = Date.now()): ContextResult {
  let contextMatchScore = 0;
  let interruptionPenalty = 0;
  const reasons: string[] = [];

  if (input.dueAtMillis && input.dueAtMillis <= nowMillis) {
    contextMatchScore += 0.7;
    reasons.push("Due tonight");
  }

  if (input.churchId && input.nearbyChurchId && input.churchId === input.nearbyChurchId) {
    contextMatchScore += 0.65;
    reasons.push("Near church");
  }

  if (input.serviceStartAtMillis && input.serviceStartAtMillis > nowMillis) {
    const minutesUntilService = (input.serviceStartAtMillis - nowMillis) / 60_000;
    if (minutesUntilService >= 30 && minutesUntilService <= 90) {
      contextMatchScore += 0.6;
      reasons.push("Before service");
    }
  }

  if (input.churchId && input.recentChurchVisitId && input.churchId === input.recentChurchVisitId) {
    contextMatchScore += 0.55;
    reasons.push("After church");
  }

  if (input.lowMotion && input.appOpenedAfterInactivity && input.eveningHours && !input.activeTyping) {
    contextMatchScore += 0.65;
    reasons.push("Quiet moment");
  }

  if (input.isSunday && (input.intent === "churchVisit" || input.intent === "sermonReflection")) {
    contextMatchScore += 0.2;
    reasons.push("Sunday mode");
  }

  if (input.isSunday && input.intent === "work" && !(input.dueAtMillis && input.dueAtMillis <= nowMillis)) {
    interruptionPenalty += 0.25;
  }

  const surfaceScore = clamp01(
    clamp01(input.priorityScore ?? 0) * 0.35 +
      clamp01(input.gravityScore ?? 0) * 0.25 +
      clamp01(input.spiritualWeight ?? 0) * 0.20 +
      clamp01(contextMatchScore) * 0.15 -
      clamp01(interruptionPenalty) * 0.05
  );

  return {
    contextMatchScore: clamp01(contextMatchScore),
    interruptionPenalty: clamp01(interruptionPenalty),
    surfaceScore,
    reasons,
  };
}
