export type LivingEntryIntent =
  | "spiritualGrowth"
  | "churchVisit"
  | "sermonReflection"
  | "prayerCare"
  | "relationship"
  | "work"
  | "rest"
  | "personal"
  | "unknown";

export interface GravityInput {
  neglectAgeScore?: number;
  spiritualWeight?: number;
  dueSoonScore?: number;
  churchContextScore?: number;
  reflectionNeedScore?: number;
  regretRisk?: number;
  intent?: LivingEntryIntent;
  isSunday?: boolean;
  isDue?: boolean;
}

export function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

export function calculateIntentGravityScore(input: GravityInput): number {
  let score =
    clamp01(input.neglectAgeScore ?? 0) * 0.25 +
    clamp01(input.spiritualWeight ?? 0) * 0.25 +
    clamp01(input.dueSoonScore ?? 0) * 0.20 +
    clamp01(input.churchContextScore ?? 0) * 0.15 +
    clamp01(input.reflectionNeedScore ?? 0) * 0.10 +
    clamp01(input.regretRisk ?? 0) * 0.05;

  if (input.isSunday && input.intent === "work" && !input.isDue) {
    score -= 0.18;
  }
  if (input.isSunday && (input.intent === "churchVisit" || input.intent === "sermonReflection")) {
    score += 0.1;
  }

  return clamp01(score);
}

export function buildGentleRegretCopy(regretRisk: number): string {
  if (regretRisk >= 0.7) {
    return "This has mattered to you before. Want to keep it visible or move it to later?";
  }
  if (regretRisk >= 0.4) {
    return "This may be worth another look when you have room for it.";
  }
  return "You can keep this active, defer it, or archive it when it no longer fits.";
}
