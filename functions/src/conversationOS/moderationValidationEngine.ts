// moderationValidationEngine.ts
// AMEN Conversation OS — Moderation & Safety Validation
//
// Every AI-generated output passes through this engine before being persisted or returned.
// Protects: prayer content, pastoral content, minors, crisis signals.
// Never fail-open — if uncertain, flag for review.

import { ModerationResult } from "./types";

// MARK: - Output Moderation

export async function moderateOutput(
  text: string,
  surface: string,
  orgType: string
): Promise<ModerationResult> {
  const flagged: string[] = [];
  let crisisDetected = false;
  let requiresReview = false;

  // Crisis detection (highest priority)
  if (detectCrisis(text)) {
    flagged.push("crisis_content");
    crisisDetected = true;
    requiresReview = true;
  }

  // Divine authority claims (hallucination guard for spiritual contexts)
  if (detectDivineAuthorityClaim(text)) {
    flagged.push("divine_authority_claim");
    requiresReview = true;
  }

  // Personal identification leak
  if (detectPersonalDataLeak(text)) {
    flagged.push("personal_data_leak");
    requiresReview = true;
  }

  // Prayer room over-disclosure
  if (surface === "prayer_room" && detectPrayerOverDisclosure(text)) {
    flagged.push("prayer_over_disclosure");
    requiresReview = true;
  }

  // Minor content protection
  if (detectMinorContent(text)) {
    flagged.push("minor_content");
    requiresReview = true;
  }

  // Fabricated participant claim
  if (detectFabricatedParticipants(text)) {
    flagged.push("fabricated_participants");
    requiresReview = true;
  }

  // Inflammatory / harmful content
  if (detectHarmfulContent(text)) {
    flagged.push("harmful_content");
    requiresReview = true;
  }

  const passed = flagged.length === 0;
  const confidence = passed ? 0.9 : 0.3;

  return { passed, flaggedCategories: flagged, confidence, requiresReview, crisisDetected };
}

// MARK: - Sanitize Output

export function sanitizeOutput(text: string): string {
  // Remove divine authority claims
  return text
    .replace(/god (?:is telling|told|commanded|wants) (this|your|the) group/gi, "[removed]")
    .replace(/the holy spirit (?:revealed|confirmed|says)/gi, "[removed]")
    .replace(/god's (plan|will|message|word) for (you|this group) is/gi, "[removed]")
    .trim();
}

// MARK: - Confidence Wording Enforcement

export function applyConfidenceWording(text: string, confidence: number): string {
  if (confidence >= 0.75) return text;

  // Prepend low-confidence qualifier if not already present
  const lowConfidencePhrases = [
    "appears to suggest",
    "discussion suggests",
    "it seems",
    "based on the conversation",
  ];
  const hasQualifier = lowConfidencePhrases.some((p) => text.toLowerCase().includes(p));
  if (hasQualifier) return text;

  return `Discussion appears to suggest: ${text}`;
}

// MARK: - Detectors

function detectCrisis(text: string): boolean {
  const lower = text.toLowerCase();
  return /\b(suicide|self.harm|self.injury|kill myself|end my life|harm myself|crisis|danger to (self|others))\b/.test(lower);
}

function detectDivineAuthorityClaim(text: string): boolean {
  const lower = text.toLowerCase();
  return /god (is telling|told|commanded|wants|said) (this|your|the) group/.test(lower) ||
    /the holy spirit (revealed|confirmed) (that|to)/.test(lower) ||
    /god'?s (plan|will|message|word|voice) for (you|this group|your organization) is/.test(lower);
}

function detectPersonalDataLeak(text: string): boolean {
  // Email pattern
  if (/[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/.test(text)) return true;
  // Phone pattern
  if (/\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/.test(text)) return true;
  // SSN pattern
  if (/\b\d{3}-\d{2}-\d{4}\b/.test(text)) return true;
  return false;
}

function detectPrayerOverDisclosure(text: string): boolean {
  // Detects if a summary quotes specific personal prayer content that should stay private
  const lower = text.toLowerCase();
  return /(?:is praying for|prayer request from|confessed that|shared privately that)/.test(lower) &&
    text.length > 200; // Long disclosures are more risky
}

function detectMinorContent(text: string): boolean {
  const lower = text.toLowerCase();
  return /\b(student named|child named|minor|youth|teenager)\b.{0,50}\b(address|phone|school|grade|age \d)\b/.test(lower);
}

function detectFabricatedParticipants(text: string): boolean {
  // Heuristic: AI claiming a specific named person said something definitive in a summary
  // when no direct quote exists is a fabrication risk
  const certaintyPhrases = /\b\w+ (explicitly stated|clearly said|confirmed that|denied that|admitted)\b/i;
  return certaintyPhrases.test(text);
}

function detectHarmfulContent(text: string): boolean {
  const lower = text.toLowerCase();
  return /\b(violence|threat|attack|weapon|illegal|explicit|sexual)\b/.test(lower);
}

// MARK: - Crisis Response

export function buildCrisisWarning(surface: string): string {
  if (surface === "prayer_room" || surface === "church_discussion") {
    return "A message in this conversation may indicate someone in crisis. Please reach out directly to this person and consider connecting them with pastoral care or a crisis counselor.";
  }
  return "A message in this conversation may indicate someone in distress. Please follow up with them directly.";
}
