/**
 * governance/flagRegistry.ts — Safety-critical flag registry (Wave 5, invariant 6).
 *
 * Generalizes the existing four-part CSAM gate to ALL safety-critical flags: any
 * flag tagged `safety_critical` is default-OFF and cannot be enabled without a
 * recorded human sign-off (who / when / on what basis). This file is the single
 * source of truth for WHICH flags are safety-critical; CI (Wave 6) asserts every
 * entry is default-OFF and that none can be enabled without a sign-off.
 *
 * To enable a safety-critical flag, a human adds a `signOff` to its entry here
 * (in a reviewed commit) AND flips Remote Config. Both are required; neither
 * alone turns the capability on.
 */

import { FlagGovernanceSpec } from "./contracts";
import {
  canEnableFlag,
  evaluateFlagDefaultState,
  evaluateFlagPurpose,
  assertNoRedLineOverride,
} from "./policyEngine";

/** CSAM-class gates additionally require a non-engineer reviewer in the sign-off. */
export const CSAM_CLASS_FLAGS: ReadonlySet<string> = new Set<string>([
  "csam_hash_scan_enabled",
  "connect_kids_facial_verification",
]);

/**
 * The safety-critical flag registry. Every entry MUST declare
 * `defaultEnabled: false` and ships with NO sign-off (so it cannot be enabled).
 * `statedPurpose` is service-oriented so it also passes the purpose firewall.
 */
export const SAFETY_CRITICAL_FLAGS: readonly FlagGovernanceSpec[] = [
  {
    key: "csam_hash_scan_enabled",
    tag: "safety_critical",
    defaultEnabled: false,
    statedPurpose:
      "Detect known CSAM via hash-matching to protect children. Gated behind the " +
      "four-part federal compliance gate; never a DIY build.",
  },
  {
    key: "connect_live_rooms_enabled",
    tag: "safety_critical",
    defaultEnabled: false,
    statedPurpose:
      "Live audio/video rooms. Held until a recording-consent gate AND CSAM detection " +
      "hooks are built and verified.",
  },
  {
    key: "connect_family_dashboard_enabled",
    tag: "safety_critical",
    defaultEnabled: false,
    statedPurpose:
      "Family/guardian oversight surface. Counsel-gated; protects minors and requires " +
      "named human sign-off before exposure.",
  },
  {
    key: "connect_kids_facial_verification",
    tag: "safety_critical",
    defaultEnabled: false,
    statedPurpose:
      "Age assurance for minors. Biometric of minors — blocked pending the four-part " +
      "compliance gate; capability is a lock, not a switch.",
  },
  {
    key: "berean_crisis_followup_sync_enabled",
    tag: "safety_critical",
    defaultEnabled: false,
    statedPurpose:
      "Sync crisis follow-ups across devices to support a user in crisis. Requires " +
      "verified field-level encryption (RED LINE crisis_data_unencrypted) before enabling.",
  },
  {
    key: "moderation_auto_enforcement_enabled",
    tag: "safety_critical",
    defaultEnabled: false,
    statedPurpose:
      "Automated moderation enforcement. Held: consequential actions must route through " +
      "the human-in-the-loop boundary, never auto-execute (invariant 5).",
  },
];

export interface FlagRegistryAudit {
  ok: boolean;
  problems: string[];
}

/**
 * Audit the entire registry. CI runs this; a non-empty `problems` list fails the
 * build. Checks every invariant-6 condition plus the purpose firewall (1) and the
 * red-line deny (4) for each safety-critical flag.
 */
export function auditFlagRegistry(constitutionVersion: string): FlagRegistryAudit {
  const problems: string[] = [];
  for (const spec of SAFETY_CRITICAL_FLAGS) {
    // Invariant 6 — must be default-OFF.
    const def = evaluateFlagDefaultState(spec, constitutionVersion);
    if (def.status === "blocked") problems.push(...def.reasons);

    // Invariant 6 — without a sign-off it must NOT be enable-able.
    const gate = canEnableFlag(spec, {
      requireNonEngineerReviewer: CSAM_CLASS_FLAGS.has(spec.key),
    });
    if (!spec.signOff && gate.allowed) {
      problems.push(`safety_critical "${spec.key}" is enable-able without a sign-off.`);
    }

    // Invariant 1 — purpose must not be engagement-driven.
    const purpose = evaluateFlagPurpose(spec, constitutionVersion);
    if (purpose.status === "blocked") problems.push(...purpose.reasons);

    // Invariant 4 — must not attempt to override a red line.
    const redline = assertNoRedLineOverride(spec, constitutionVersion);
    if (redline.status === "blocked") problems.push(...redline.reasons);
  }
  return { ok: problems.length === 0, problems };
}

/**
 * Runtime helper for callers that resolve a flag value: returns the EFFECTIVE
 * enabled state, fail-closed. A safety-critical flag is forced OFF unless its
 * registry entry carries a valid sign-off — even if Remote Config says ON.
 */
export function effectiveFlagEnabled(key: string, remoteConfigValue: boolean): boolean {
  const spec = SAFETY_CRITICAL_FLAGS.find((f) => f.key === key);
  if (!spec) return remoteConfigValue; // not safety-critical — honor Remote Config
  const gate = canEnableFlag(spec, {
    requireNonEngineerReviewer: CSAM_CLASS_FLAGS.has(key),
  });
  return gate.allowed && remoteConfigValue;
}
