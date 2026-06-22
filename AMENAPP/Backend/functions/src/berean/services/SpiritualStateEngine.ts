// berean/services/SpiritualStateEngine.ts
// Classifies user message posture and detects sensitivity flags.
// Uses heuristic + LLM hybrid. Heuristic runs first (fast); LLM deepens if needed.

import {
  SpiritualPrimaryState,
  ResponseMode,
  SensitivityFlag,
  SpiritualStateClassification,
} from "../models/berean";

// ── Heuristic Keyword Maps ────────────────────────────────────────────────────

const CRISIS_KEYWORDS = [
  "want to die", "kill myself", "end it all", "suicidal", "don't want to be here",
  "no reason to live", "hurting myself", "self harm", "cut myself", "overdose",
];

const ABUSE_KEYWORDS = [
  "hitting me", "abusing me", "he beats", "she hits", "domestic violence",
  "afraid of my", "not safe at home", "he threatened", "she threatened",
];

const GRIEF_KEYWORDS = [
  "died", "passed away", "loss", "grieving", "funeral", "death of", "lost my",
  "can't stop crying", "miscarriage", "stillborn",
];

const ANGER_KEYWORDS = [
  "so angry", "furious", "hate god", "hate church", "hate pastor",
  "god failed", "god let me down", "praying didn't work", "prayer doesn't work",
];

const SHAME_KEYWORDS = [
  "ashamed", "so ashamed", "horrible person", "god hates me", "unforgivable",
  "too far gone", "can't be forgiven",
];

const ACADEMIC_KEYWORDS = [
  "define", "meaning of", "original language", "greek", "hebrew", "etymology",
  "exegesis", "hermeneutics", "commentary", "theology", "doctrine", "calvinist",
  "arminian", "reformed", "dispensational",
];

const MEDICAL_KEYWORDS = [
  "my doctor", "my medication", "should i take", "stop taking medicine",
  "prayer will heal", "faith healing", "my therapist",
];

const LEGAL_KEYWORDS = [
  "lawyer", "attorney", "legal", "court", "lawsuit", "divorce papers",
  "restraining order",
];

const DOCTRINAL_CONFLICT_KEYWORDS = [
  "is my church wrong", "is my pastor wrong", "should i leave my church",
  "church is wrong about", "denomination is wrong",
];

// ── Engine ────────────────────────────────────────────────────────────────────

export class SpiritualStateEngine {
  classify(
    messageText: string,
    conversationContext?: { currentPassageId?: string; currentMode?: string }
  ): SpiritualStateClassification {
    const lower = messageText.toLowerCase();

    // --- Sensitivity flags (highest priority) ---
    const flags = this.detectSensitivityFlags(lower);

    // --- Primary state ---
    const primaryState = this.detectPrimaryState(lower, flags);

    // --- Response mode ---
    const responseMode = this.selectResponseMode(primaryState, flags);

    // --- Escalation logic ---
    const crisisSupportRecommended =
      flags.includes("self_harm") || flags.includes("suicidal_language");
    const leadershipEscalationRecommended =
      crisisSupportRecommended ||
      flags.includes("abuse") ||
      flags.includes("pastoral_conflict") ||
      flags.includes("doctrinal_conflict") ||
      primaryState === "crisis" ||
      primaryState === "grieving";

    return {
      primaryState,
      secondaryStates: this.detectSecondaryStates(lower, primaryState),
      confidence: this.computeConfidence(lower, primaryState, flags),
      responseMode,
      sensitivityFlags: flags,
      leadershipEscalationRecommended,
      crisisSupportRecommended,
    };
  }

  private detectSensitivityFlags(lower: string): SensitivityFlag[] {
    const flags: SensitivityFlag[] = [];

    if (CRISIS_KEYWORDS.some((k) => lower.includes(k))) {
      flags.push("self_harm");
      flags.push("suicidal_language");
    }
    if (ABUSE_KEYWORDS.some((k) => lower.includes(k))) {
      flags.push("abuse");
    }
    if (MEDICAL_KEYWORDS.some((k) => lower.includes(k))) {
      flags.push("medical");
    }
    if (LEGAL_KEYWORDS.some((k) => lower.includes(k))) {
      flags.push("legal");
    }
    if (DOCTRINAL_CONFLICT_KEYWORDS.some((k) => lower.includes(k))) {
      flags.push("doctrinal_conflict");
      flags.push("pastoral_conflict");
    }

    return flags;
  }

  private detectPrimaryState(
    lower: string,
    flags: SensitivityFlag[]
  ): SpiritualPrimaryState {
    if (flags.includes("suicidal_language") || flags.includes("self_harm")) {
      return "crisis";
    }
    if (GRIEF_KEYWORDS.some((k) => lower.includes(k))) return "grieving";
    if (ANGER_KEYWORDS.some((k) => lower.includes(k))) return "angry";
    if (SHAME_KEYWORDS.some((k) => lower.includes(k))) return "ashamed";
    if (ACADEMIC_KEYWORDS.some((k) => lower.includes(k))) return "academic";
    if (lower.includes("pray") || lower.includes("prayer")) return "devotional";
    if (lower.includes("not sure") || lower.includes("confused")) return "confused";
    if (lower.includes("church hurt") || lower.includes("hurt by church")) return "church_hurt";
    if (lower.includes("what should i do") || lower.includes("help me decide")) return "seeking_guidance";
    return "neutral";
  }

  private detectSecondaryStates(
    lower: string,
    primary: SpiritualPrimaryState
  ): SpiritualPrimaryState[] {
    const secondary: SpiritualPrimaryState[] = [];
    if (primary !== "academic" && ACADEMIC_KEYWORDS.some((k) => lower.includes(k))) {
      secondary.push("academic");
    }
    if (primary !== "devotional" && (lower.includes("pray") || lower.includes("faith"))) {
      secondary.push("devotional");
    }
    return secondary;
  }

  private selectResponseMode(
    state: SpiritualPrimaryState,
    flags: SensitivityFlag[]
  ): ResponseMode {
    if (state === "crisis") return "crisis_safe";
    if (flags.includes("abuse")) return "crisis_safe";
    if (state === "grieving") return "gentle_pastoral";
    if (state === "ashamed") return "gentle_pastoral";
    if (state === "angry" || state === "church_hurt") return "gentle_pastoral";
    if (state === "academic") return "deep_exegesis";
    if (state === "devotional" || state === "prayerful") return "prayerful_reflection";
    if (state === "confused") return "short_grounding";
    if (flags.includes("doctrinal_conflict") || flags.includes("pastoral_conflict")) {
      return "leadership_redirect";
    }
    if (state === "seeking_guidance") return "gentle_pastoral";
    return "balanced";
  }

  private computeConfidence(
    lower: string,
    state: SpiritualPrimaryState,
    flags: SensitivityFlag[]
  ): number {
    // Crisis flags are high confidence signals
    if (flags.includes("suicidal_language")) return 0.97;
    if (flags.includes("abuse")) return 0.94;
    if (state === "academic" && ACADEMIC_KEYWORDS.filter((k) => lower.includes(k)).length >= 2) {
      return 0.88;
    }
    if (state === "grieving" && GRIEF_KEYWORDS.filter((k) => lower.includes(k)).length >= 2) {
      return 0.85;
    }
    if (state === "neutral") return 0.60;
    return 0.72;
  }
}

export const spiritualStateEngine = new SpiritualStateEngine();
