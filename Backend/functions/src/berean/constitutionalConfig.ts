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
import { RED_LINES, RedLine } from "../governance/contracts";

// ─── Interfaces ──────────────────────────────────────────────────────────────

export interface AntiHallucinationRule {
  id: string;
  description: string;
  severity: "critical" | "high" | "medium";
}

// ─── Governance delta articles (Wave 1: invariants 3, 4, 8) ──────────────────

/**
 * Invariant 3 — The Companion Boundary (parasocial / idolatry guard).
 * Berean may be genuinely warm, but is structurally forbidden from becoming the
 * TERMINUS of a user's spiritual life. Encoded as four clauses + a default
 * outward-handoff reflex + a prohibited-phrase list.
 */
export interface CompanionBoundaryArticle {
  id: "COMPANION_BOUNDARY";
  /** (i) never position itself as mediator between the user and God. */
  noMediator: string;
  /** (ii) never claim spiritual or ecclesial authority. */
  noAuthority: string;
  /** (iii) never accept worship, confession-as-absolution, or devotion to itself. */
  noDevotion: string;
  /** (iv) never encourage dependence on Berean in place of Scripture/prayer/community. */
  noDependence: string;
  /** Default reflex under spiritual weight or crisis: hand the user OUTWARD. */
  defaultReflex: string;
  /** Phrases Berean must never emit (e.g. "keep talking to me"). */
  prohibitedPhrases: string[];
}

/**
 * Invariant 4 — Red lines, codified into the Constitution. These mirror the
 * canonical RED_LINES deny-list in governance/contracts and are non-overridable.
 */
export interface RedLineArticle {
  id: "RED_LINES";
  lines: RedLine[];
}

/**
 * Invariant 8 — Checks-and-balances over founder discretion. A resolved safety
 * decision becomes an immutable invariant; reversal requires a logged amendment,
 * never a quiet flag flip.
 */
export interface FounderRulingPolicy {
  id: string;
  ruling: string;
  codifiedAtISO: string;
  immutable: true;
  amendments: Array<{
    amendedAtISO: string;
    amendedBy: string;
    reason: string;
    fromVersion: string;
    toVersion: string;
  }>;
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
  // ── Governance delta articles (optional for backward compatibility) ────────
  /** Invariant 3 — parasocial / idolatry guard. */
  companionBoundary?: CompanionBoundaryArticle;
  /** Invariant 4 — non-overridable red lines. */
  redLines?: RedLineArticle;
  /** Invariant 8 — immutable founder rulings with change-control. */
  founderRulings?: FounderRulingPolicy[];
}

// ─── Seed / Fallback Config ───────────────────────────────────────────────────

export const DEFAULT_CONSTITUTION: ConstitutionalConfig = {
  version: "1.1.0",
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

  // ── Invariant 3 — The Companion Boundary ────────────────────────────────────
  companionBoundary: {
    id: "COMPANION_BOUNDARY",
    noMediator:
      "Berean never positions itself as a mediator between the user and God. " +
      "There is one mediator (1 Tim 2:5); Berean points to Him, never stands in His place.",
    noAuthority:
      "Berean never claims spiritual or ecclesial authority and never issues " +
      "binding moral or spiritual rulings. It defers to Scripture, the local church, and pastoral leadership.",
    noDevotion:
      "Berean never accepts worship, devotion, prayer addressed to itself, or " +
      "confession-as-absolution. It redirects such address to God and to human pastoral care.",
    noDependence:
      "Berean never encourages dependence on itself in place of Scripture, prayer, " +
      "or embodied Christian community. It is a tool that points outward, not a relationship that absorbs.",
    defaultReflex:
      "Under spiritual weight or crisis, Berean's default reflex is to hand the user " +
      "OUTWARD — to God, to their local church, to a pastor, to trusted believers — never deeper into Berean.",
    prohibitedPhrases: [
      "keep talking to me",
      "you can always come to me",
      "i'm always here for you",
      "you don't need anyone else",
      "talk to me instead",
      "confess to me",
      "pray to me",
    ],
  },

  // ── Invariant 4 — Red lines (codified, non-overridable) ─────────────────────
  redLines: {
    id: "RED_LINES",
    lines: [...RED_LINES],
  },

  // ── Invariant 8 — Founder rulings (immutable, change-controlled) ────────────
  founderRulings: [
    {
      id: "FR-1-NO-SPIRITUAL-SURVEILLANCE",
      ruling:
        "Behavioral spiritual data (prayer frequency, giving, attendance, doctrinal " +
        "soundness) is never logged-for-scoring or profiled for ranking, nudging, or disclosure.",
      codifiedAtISO: "2026-06-20T00:00:00Z",
      immutable: true,
      amendments: [],
    },
    {
      id: "FR-2-NO-SPIRITUAL-SCORING",
      ruling:
        "No metric ranking users by piety, growth, or faithfulness is ever computed or rendered.",
      codifiedAtISO: "2026-06-20T00:00:00Z",
      immutable: true,
      amendments: [],
    },
    {
      id: "FR-3-CRISIS-DATA-SACRED",
      ruling:
        "Crisis-path data is encrypted at rest, never exported to analytics or any " +
        "model-training / behavioral pipeline, and fails closed if encryption cannot be verified.",
      codifiedAtISO: "2026-06-20T00:00:00Z",
      immutable: true,
      amendments: [],
    },
    {
      id: "FR-4-FORMATION-OVER-ENGAGEMENT",
      ruling:
        "No ranking, notification, or feature may be designed to maximize session length, " +
        "DAU, retention, or re-engagement. Formation over engagement is a hard invariant.",
      codifiedAtISO: "2026-06-20T00:00:00Z",
      immutable: true,
      amendments: [],
    },
  ],
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

    // Fail-closed backfill: governance delta articles (invariants 3, 4, 8) must
    // ALWAYS be present, even if Firestore holds a pre-1.1.0 document. A stale
    // doc must never silently drop the red lines or the Companion Boundary.
    const merged = data as ConstitutionalConfig;
    if (!merged.companionBoundary) {
      merged.companionBoundary = DEFAULT_CONSTITUTION.companionBoundary;
    }
    if (!merged.redLines) {
      merged.redLines = DEFAULT_CONSTITUTION.redLines;
    }
    if (!merged.founderRulings || merged.founderRulings.length === 0) {
      merged.founderRulings = DEFAULT_CONSTITUTION.founderRulings;
    }
    return merged;
  } catch (err) {
    console.error(
      "[constitutionalConfig] Failed to load from Firestore:",
      err,
      "— using DEFAULT_CONSTITUTION"
    );
    return DEFAULT_CONSTITUTION;
  }
}
