// flags.ts — Berean Island feature flags (Wave 0)
//
// All flags default FALSE. Human flips via Firebase Remote Config after verification.
// Remote Config key names must match AMENFeatureFlags.swift applyRemoteConfig entries.

export const BEREAN_ISLAND_FLAGS = {
  /** Master gate: floating Island pill + all four states. Off = zero Island UI. */
  bereanIsland: "berean_island",
  /** Allows context-triggered proactive compact suggestions (≤3/day hard cap). */
  bereanIslandProactive: "berean_island_proactive",
  /** Write-with-Berean composer glyph and tools in all composers. */
  writeWithBerean: "write_with_berean",
  /** Phone-context engine: calendar, location, reminders signals (Tier-C, opt-in). */
  bereanContextEngine: "berean_context_engine",
  /** Berean Lens camera surface: bible/flyer/safety/study/fellowship/sermon modes. */
  bereanLens: "berean_lens",
  /** Sermon Companion live session with on-device speech and Smart Church Note streaming. */
  bereanSermonCompanion: "berean_sermon_companion",
  /** Voice personalization: TTS voices + Mind & Manner dials. */
  bereanVoicePersonalization: "berean_voice_personalization",
  /** Berean+ gating: enforce free-tier limits per entitlement matrix. */
  bereanPlusGating: "berean_plus_gating",
} as const;

export type BereanIslandFlagKey = keyof typeof BEREAN_ISLAND_FLAGS;

/** Returns true only if the named flag is enabled in the provided Remote Config snapshot. */
export function isBereanFlagEnabled(
  remoteConfigSnapshot: Record<string, boolean>,
  flag: BereanIslandFlagKey
): boolean {
  return remoteConfigSnapshot[BEREAN_ISLAND_FLAGS[flag]] === true;
}

/** Safety Lens and all GUARDIAN checks are never gated — enforce this invariant. */
export const NEVER_GATED = ["berean_safety_lens", "berean_guardian", "berean_crisis"] as const;
