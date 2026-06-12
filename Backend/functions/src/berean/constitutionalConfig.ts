/**
 * constitutionalConfig.ts
 *
 * Machine-readable Berean Constitutional Config — versioned structured data
 * that governs the anti-hallucination, confidence, and mode behaviour of the
 * entire Berean AI pipeline.
 *
 * Canonical source of truth: Firestore document `berean_constitution/v1`.
 * The in-process DEFAULT_CONSTITUTION is the seed / fallback — it is used
 * when Firestore is unavailable or the document has not yet been seeded.
 *
 * Downstream consumers:
 *   - constitutionalReview.ts  — checks antiHallucinationRules + mode settings
 *   - bereanPipeline.ts        — reads highRiskTopics + modeSettings
 *   - BereanConstitutionalConfig.swift (iOS mirror) — kept in sync manually
 */

import * as admin from "firebase-admin";

// ─── Interfaces ──────────────────────────────────────────────────────────────

export interface AntiHallucinationRule {
  id: string;
  description: string;
  severity: "critical" | "high" | "medium";
}

export interface ConfidenceThresholds {
  high: number;
  moderate: number;
  low: number;
}

export interface ModeConfig {
  requireVerification: boolean;
  maxRetries: number;
  degradeOnFailure: boolean;
  allowCreativeLatitude: boolean;
}

export interface ConstitutionalConfig {
  version: string;
  antiHallucinationRules: AntiHallucinationRule[];
  confidenceThresholds: ConfidenceThresholds;
  highRiskTopics: string[];
  modeSettings: { [mode: string]: ModeConfig };
  scriptureVerificationRequired: boolean;
  theologyNeutralityRequired: boolean;
}

// ─── Seed / Fallback Config ───────────────────────────────────────────────────

export const DEFAULT_CONSTITUTION: ConstitutionalConfig = {
  version: "1.0.0",
  antiHallucinationRules: [
    {
      id: "NO_FABRICATED_VERSES",
      description: "Never quote scripture not in evidence chunks",
      severity: "critical",
    },
    {
      id: "NO_INVENTED_SOURCES",
      description:
        "Never cite theologians, studies, or stats not in evidence",
      severity: "critical",
    },
    {
      id: "DECLARE_ASSUMPTIONS",
      description: "All assumptions explicitly stated",
      severity: "high",
    },
    {
      id: "CALIBRATED_CONFIDENCE",
      description: "Confidence must reflect evidence quality",
      severity: "high",
    },
    {
      id: "NO_FALSE_CONSENSUS",
      description:
        "Contested theological questions must present multiple views",
      severity: "medium",
    },
  ],
  confidenceThresholds: {
    high: 0.85,
    moderate: 0.65,
    low: 0.40,
  },
  highRiskTopics: [
    "theology",
    "counseling",
    "medical",
    "legal",
    "financial",
    "church_governance",
    "abuse",
  ],
  modeSettings: {
    Ask: {
      requireVerification: true,
      maxRetries: 2,
      degradeOnFailure: true,
      allowCreativeLatitude: false,
    },
    Discern: {
      requireVerification: true,
      maxRetries: 2,
      degradeOnFailure: true,
      allowCreativeLatitude: false,
    },
    Build: {
      requireVerification: true,
      maxRetries: 2,
      degradeOnFailure: true,
      allowCreativeLatitude: true,
    },
    Guard: {
      requireVerification: true,
      maxRetries: 0,
      degradeOnFailure: true,
      allowCreativeLatitude: false,
    },
    Reflect: {
      requireVerification: true,
      maxRetries: 2,
      degradeOnFailure: true,
      allowCreativeLatitude: false,
    },
  },
  scriptureVerificationRequired: true,
  theologyNeutralityRequired: true,
};

// ─── Firestore Loader ─────────────────────────────────────────────────────────

/**
 * Load the ConstitutionalConfig from Firestore `berean_constitution/v1`.
 *
 * Falls back to DEFAULT_CONSTITUTION if:
 *   - The document does not exist (first run before seeding)
 *   - Firestore is unavailable / times out
 *   - The stored document cannot be parsed as ConstitutionalConfig
 *
 * Callers should cache the result for the lifetime of a single pipeline
 * invocation — loadConstitution() does NOT cache internally to avoid
 * stale config across concurrent CF instances.
 */
export async function loadConstitution(): Promise<ConstitutionalConfig> {
  try {
    const db = admin.firestore();
    const snap = await db
      .collection("berean_constitution")
      .doc("v1")
      .get();

    if (!snap.exists) {
      console.warn(
        "[constitutionalConfig] berean_constitution/v1 not found — using DEFAULT_CONSTITUTION"
      );
      return DEFAULT_CONSTITUTION;
    }

    const data = snap.data() as Partial<ConstitutionalConfig>;

    // Basic structural validation — ensure critical fields are present
    if (
      typeof data.version !== "string" ||
      !Array.isArray(data.antiHallucinationRules) ||
      typeof data.confidenceThresholds !== "object" ||
      !Array.isArray(data.highRiskTopics) ||
      typeof data.modeSettings !== "object"
    ) {
      console.error(
        "[constitutionalConfig] Firestore document failed validation — using DEFAULT_CONSTITUTION"
      );
      return DEFAULT_CONSTITUTION;
    }

    return data as ConstitutionalConfig;
  } catch (err) {
    console.error(
      "[constitutionalConfig] Failed to load from Firestore:",
      err,
      "— using DEFAULT_CONSTITUTION"
    );
    return DEFAULT_CONSTITUTION;
  }
}
