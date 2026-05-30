/**
 * structuredOutputContract.ts
 *
 * JSON schema / prompt fragment that instructs Claude to return a structured
 * BereanStructuredResponse. Used by generateStructuredResponse controller.
 *
 * The model must return valid JSON matching this contract exactly.
 * The backend validates the response before forwarding to the client.
 */

export const STRUCTURED_OUTPUT_INSTRUCTION = `
STRUCTURED OUTPUT REQUIREMENT:
You MUST respond with a single JSON object matching the following schema exactly.
Do NOT include any text outside the JSON object.
Do NOT include markdown code fences.

{
  "answer": "<string — the main prose response>",
  "responseMode": "<one of: scholarly | pastoral | comfort | crisis | exploratory | prayer_support | balanced>",
  "studyCards": [
    {
      "id": "<uuid string>",
      "type": "<one of: scripture | word_study | historical_context | commentary | application | reflection | cross_reference | christ_connection | leader_referral | crisis_resource>",
      "title": "<short title for this card>",
      "content": "<body content of the card>",
      "scriptureRef": "<optional: e.g. John 3:16 (ESV)>",
      "resourceURL": "<optional: URL string>",
      "sortOrder": <integer starting at 0>
    }
  ],
  "sensitivityFlags": ["<zero or more SensitivityFlag values>"],
  "leadershipPromptShown": <boolean>,
  "followUpSuggestion": "<optional: a question or prompt to continue the study>",
  "anchorPassage": "<optional: primary scripture reference that grounds this response, e.g. Romans 8:28 (ESV)>",
  "doctrinalConfidence": <float 0.0–1.0>
}

CONSTRAINTS FOR YOUR JSON:
- "studyCards" should contain 0–4 cards maximum; do not generate more
- Include a "scripture" card if any scripture is quoted; put the full text in "content"
- Include "word_study" cards only if the original language is directly relevant
- If crisis signals exist: set sensitivityFlags to include "crisis_escalation", leadershipPromptShown to true, include a "crisis_resource" studyCard
- If you are uncertain about a doctrinal claim, set doctrinalConfidence below 0.7
- Do NOT set doctrinalConfidence to 1.0 unless the claim is unambiguously clear in Scripture
- "sensitivityFlags" must only contain values from this set: divine_authority_assertion, scripture_contradiction, pastoral_escalation, crisis_escalation, controversial_doctrine, minor_user, scrupulosity_risk
`;

/**
 * Validates that a parsed JSON object loosely conforms to the BereanStructuredResponse shape.
 * Returns the validated object or throws if critically malformed.
 */
export function validateStructuredResponse(parsed: unknown): Record<string, unknown> {
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("Structured response is not a JSON object");
  }

  const obj = parsed as Record<string, unknown>;

  if (typeof obj.answer !== "string" || !obj.answer.trim()) {
    throw new Error("Structured response missing required 'answer' field");
  }

  if (!Array.isArray(obj.studyCards)) {
    obj.studyCards = [];
  }

  if (!Array.isArray(obj.sensitivityFlags)) {
    obj.sensitivityFlags = [];
  }

  if (typeof obj.leadershipPromptShown !== "boolean") {
    obj.leadershipPromptShown = false;
  }

  if (typeof obj.doctrinalConfidence !== "number") {
    obj.doctrinalConfidence = 0.7;
  }

  // Clamp confidence to valid range
  obj.doctrinalConfidence = Math.max(0, Math.min(1, obj.doctrinalConfidence as number));

  return obj;
}

export function buildStructuredOutputContract(): string {
  return STRUCTURED_OUTPUT_INSTRUCTION;
}
