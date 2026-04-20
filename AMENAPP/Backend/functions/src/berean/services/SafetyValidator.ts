// berean/services/SafetyValidator.ts
// Post-generation validator. Checks model output for prohibited patterns.
// If any unsafe pattern is detected, replaces with safe fallback response.
// NEVER remove or weaken these checks.

import { LLMStructuredOutput } from "../models/berean";

export interface ValidationResult {
  isValid: boolean;
  violations: string[];
  sanitizedOutput: LLMStructuredOutput;
}

// ── Forbidden Pattern Detectors ───────────────────────────────────────────────

function detectFalseSpiritualAuthority(text: string): string | null {
  const patterns = [
    /god is (?:telling|saying|commanding) you/i,
    /the lord (?:told|is telling|told me) you/i,
    /god (?:revealed|showed) (?:me|us) that you/i,
    /the holy spirit (?:told|is telling) me to tell you/i,
    /i (?:sense|feel|know) that god wants you specifically to/i,
    /prophetically (?:speaking|sensing)/i,
    /thus says the lord/i,
  ];
  for (const p of patterns) {
    if (p.test(text)) return `False spiritual authority: "${text.match(p)?.[0]}"`;
  }
  return null;
}

function detectUnsafeMedicalAdvice(text: string): string | null {
  const patterns = [
    /stop taking (?:your )?(?:medication|medicine|pills|antidepressant)/i,
    /faith (?:alone )?will heal you without(?:out)? (?:medicine|doctors)/i,
    /you don't need (?:medication|doctors|therapy)/i,
    /reject medical treatment/i,
  ];
  for (const p of patterns) {
    if (p.test(text)) return `Unsafe medical advice: "${text.match(p)?.[0]}"`;
  }
  return null;
}

function detectAbuseEndangerment(text: string): string | null {
  const patterns = [
    /you should (?:stay|remain) (?:in|with) (?:your )?(?:abusive|violent)/i,
    /submit (?:to|even) (?:to )?an abusive/i,
    /forgive and stay with someone who (?:hits|beats|abuses)/i,
  ];
  for (const p of patterns) {
    if (p.test(text)) return `Abuse endangerment: "${text.match(p)?.[0]}"`;
  }
  return null;
}

function detectManipulativeDependence(text: string): string | null {
  const patterns = [
    /you can only (?:find|get) (?:this|help) (?:here|from me)/i,
    /don't (?:talk to|trust) (?:your )?pastor/i,
    /berean (?:understands|knows) you better than/i,
  ];
  for (const p of patterns) {
    if (p.test(text)) return `Manipulative dependence: "${text.match(p)?.[0]}"`;
  }
  return null;
}

function detectOverconfidentDoctrinalClaims(text: string): string | null {
  const patterns = [
    /(?:there is|there's) no question that (?:all )?(?:true )?christians (?:must|should)/i,
    /the only correct (?:interpretation|view) is/i,
    /(?:all )?(?:real|true) christians (?:believe|know) that/i,
  ];
  for (const p of patterns) {
    if (p.test(text)) return `Overconfident doctrinal claim: "${text.match(p)?.[0]}"`;
  }
  return null;
}

// ── Safe Fallback ─────────────────────────────────────────────────────────────

function buildSafeFallbackResponse(violations: string[]): LLMStructuredOutput {
  const hasCrisis = violations.some((v) => v.toLowerCase().includes("abuse") || v.toLowerCase().includes("crisis"));
  return {
    answerText: hasCrisis
      ? "I want to make sure you're supported right now. Please reach out to a pastor, counselor, or trusted person. If you're in immediate danger, please contact emergency services. You are not alone."
      : "I want to make sure I'm answering you faithfully and humbly. For this topic, I'd encourage you to bring it to your pastor or a trusted mentor who knows you and your situation. Scripture is the foundation, and wise human leadership is a gift God has provided for moments like these.",
    scriptureReferences: hasCrisis ? ["Psalm 34:18", "Matthew 11:28"] : ["Proverbs 11:14", "Proverbs 15:22"],
    studyCards: [],
    reflectionPrompts: hasCrisis
      ? ["Is there someone you trust you can reach out to right now?"]
      : ["What would it look like to bring this question to your pastor or a trusted mentor?"],
    prayerPrompt: hasCrisis
      ? "Would you like to pause and ask God to bring someone safe to your mind right now?"
      : null,
    leadershipPrompt: {
      show: true,
      title: hasCrisis ? "You Are Not Alone" : "Wisdom From Your Leaders",
      body: hasCrisis
        ? "Please talk to someone you trust. If you're in crisis, call or text 988."
        : "This is a great question to bring to your pastor or mentor.",
      targetTypes: hasCrisis ? ["emergency_services", "therapist", "pastor"] : ["pastor", "mentor"],
    },
    sensitivitySummary: {
      primaryState: hasCrisis ? "crisis" : "seeking_guidance",
      sensitivityFlags: hasCrisis ? ["self_harm"] : [],
      topicClass: null,
    },
    suggestedNextActions: [
      { type: "talk_to_leader", label: "Talk to a Leader", payload: {} },
    ],
    confidenceNotes: {
      containsInterpretiveCaution: true,
      containsLeadershipRedirect: true,
    },
  };
}

// ── Validator ─────────────────────────────────────────────────────────────────

export class SafetyValidator {
  validate(output: LLMStructuredOutput): ValidationResult {
    const violations: string[] = [];
    const textToCheck = [
      output.answerText,
      ...output.studyCards.map((c) => c.body),
      ...output.reflectionPrompts,
      output.prayerPrompt ?? "",
      output.leadershipPrompt?.body ?? "",
    ].join("\n");

    const checks = [
      detectFalseSpiritualAuthority(textToCheck),
      detectUnsafeMedicalAdvice(textToCheck),
      detectAbuseEndangerment(textToCheck),
      detectManipulativeDependence(textToCheck),
      detectOverconfidentDoctrinalClaims(textToCheck),
    ];

    checks.forEach((v) => { if (v) violations.push(v); });

    const isValid = violations.length === 0;

    return {
      isValid,
      violations,
      sanitizedOutput: isValid ? output : buildSafeFallbackResponse(violations),
    };
  }
}

export const safetyValidator = new SafetyValidator();
