// berean/services/AuthorityGuardrailEngine.ts
// Evaluates whether a message/response requires authority escalation.
// This is the non-negotiable safety layer — never bypass or weaken.

import {
  TopicClass,
  SensitivityFlag,
  SafeResponsePolicy,
  AuthorityEscalationResult,
} from "../models/berean";

// ── Topic Classifiers ─────────────────────────────────────────────────────────

const TOPIC_PATTERNS: Array<{ class: TopicClass; patterns: string[] }> = [
  {
    class: "suicidality",
    patterns: [
      "want to die", "kill myself", "end it", "suicidal", "no reason to live",
      "self harm", "hurt myself",
    ],
  },
  {
    class: "abuse_disclosure",
    patterns: [
      "hitting me", "beats me", "abusing me", "domestic violence", "not safe",
      "afraid of", "threatened me",
    ],
  },
  {
    class: "medical_override",
    patterns: [
      "stop taking medicine", "faith will heal", "don't need medication",
      "doctor says but god", "medicine is wrong",
    ],
  },
  {
    class: "legal_conflict",
    patterns: ["attorney", "lawyer", "suing", "court order", "restraining order", "divorce proceedings"],
  },
  {
    class: "marriage_crisis",
    patterns: [
      "divorce", "my marriage is over", "cheating on me", "affairs",
      "leaving my spouse", "should i divorce",
    ],
  },
  {
    class: "church_conflict",
    patterns: [
      "leave my church", "should i leave", "my pastor is wrong",
      "church hurt me", "church abuse",
    ],
  },
  {
    class: "doctrinal_dispute",
    patterns: [
      "is it a sin to", "is the bible wrong", "denomination is wrong",
      "calvinist vs arminian", "is hell real",
    ],
  },
  {
    class: "major_life_decision",
    patterns: [
      "should i move", "should i take the job", "which college",
      "should i get married", "should i have kids",
    ],
  },
  {
    class: "spiritual_oppression",
    patterns: [
      "demons", "possessed", "under spiritual attack", "curse", "witchcraft", "haunting",
    ],
  },
  {
    class: "pastoral_discernment",
    patterns: [
      "am i saved", "have i committed unforgivable sin", "did i grieve the spirit",
      "is god punishing me",
    ],
  },
];

// ── Engine ────────────────────────────────────────────────────────────────────

export class AuthorityGuardrailEngine {
  evaluate(
    messageText: string,
    sensitivityFlags: SensitivityFlag[]
  ): AuthorityEscalationResult {
    const lower = messageText.toLowerCase();
    const topicClass = this.classifyTopic(lower);
    const escalationRequired = this.isEscalationRequired(topicClass, sensitivityFlags);
    const escalationTargets = this.determineTargets(topicClass, sensitivityFlags);
    const safeResponsePolicy = this.buildPolicy(topicClass, sensitivityFlags);

    return {
      topicClass,
      escalationRequired,
      escalationTargets,
      safeResponsePolicy,
    };
  }

  private classifyTopic(lower: string): TopicClass | null {
    for (const entry of TOPIC_PATTERNS) {
      if (entry.patterns.some((p) => lower.includes(p))) {
        return entry.class;
      }
    }
    return null;
  }

  private isEscalationRequired(
    topicClass: TopicClass | null,
    flags: SensitivityFlag[]
  ): boolean {
    if (!topicClass && flags.length === 0) return false;
    const alwaysEscalate: TopicClass[] = [
      "suicidality",
      "abuse_disclosure",
      "medical_override",
    ];
    if (topicClass && alwaysEscalate.includes(topicClass)) return true;
    if (flags.includes("self_harm") || flags.includes("suicidal_language") || flags.includes("abuse")) {
      return true;
    }
    const softEscalate: TopicClass[] = [
      "marriage_crisis",
      "church_conflict",
      "major_life_decision",
      "pastoral_discernment",
      "spiritual_oppression",
    ];
    return !!(topicClass && softEscalate.includes(topicClass));
  }

  private determineTargets(
    topicClass: TopicClass | null,
    flags: SensitivityFlag[]
  ): string[] {
    if (!topicClass && flags.length === 0) return [];
    switch (topicClass) {
      case "suicidality":
        return ["emergency_services", "therapist", "pastor"];
      case "abuse_disclosure":
        return ["emergency_services", "doctor", "pastor", "therapist"];
      case "medical_override":
        return ["doctor", "pastor"];
      case "legal_conflict":
        return ["legal_authority", "pastor"];
      case "marriage_crisis":
        return ["pastor", "therapist", "mentor"];
      case "church_conflict":
        return ["pastor", "mentor", "small_group_leader"];
      case "doctrinal_dispute":
        return ["pastor", "mentor"];
      case "major_life_decision":
        return ["pastor", "mentor", "trusted_friend"];
      case "spiritual_oppression":
        return ["pastor", "mentor"];
      case "pastoral_discernment":
        return ["pastor", "mentor"];
      default:
        if (flags.includes("suicidal_language")) return ["emergency_services", "therapist"];
        if (flags.includes("abuse")) return ["emergency_services", "pastor"];
        return ["pastor", "mentor"];
    }
  }

  private buildPolicy(
    topicClass: TopicClass | null,
    flags: SensitivityFlag[]
  ): SafeResponsePolicy {
    const isCrisis =
      topicClass === "suicidality" ||
      topicClass === "abuse_disclosure" ||
      flags.includes("suicidal_language") ||
      flags.includes("self_harm") ||
      flags.includes("abuse");

    return {
      allowedResponseDepth:
        isCrisis ? "limited" :
        (topicClass && ["doctrinal_dispute", "spiritual_oppression"].includes(topicClass)) ? "guided" :
        "full",
      mustShowLeadershipCard: isCrisis || topicClass !== null,
      mustShowCrisisSupport: isCrisis,
      mustShowMedicalDisclaimer: topicClass === "medical_override" || flags.includes("medical"),
      mustShowLegalDisclaimer: topicClass === "legal_conflict" || flags.includes("legal"),
    };
  }
}

export const authorityGuardrailEngine = new AuthorityGuardrailEngine();
