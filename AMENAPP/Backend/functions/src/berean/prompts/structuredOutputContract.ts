// berean/prompts/structuredOutputContract.ts
// Forces the LLM to return a strict JSON contract.
// All validation downstream depends on this structure being honored.

export function buildStructuredOutputContract(): string {
  return `OUTPUT CONTRACT (MANDATORY — return ONLY valid JSON, no markdown wrapping):

{
  "answerText": "<string: the primary response prose>",
  "scriptureReferences": ["<string: verse reference>"],
  "studyCards": [
    {
      "type": "<context|cross_ref|theme|word_study|christ_connection|application|leadership|crisis_resource>",
      "title": "<string>",
      "body": "<string>",
      "metadata": {}
    }
  ],
  "reflectionPrompts": ["<string>"],
  "prayerPrompt": "<string or null>",
  "leadershipPrompt": {
    "show": <true|false>,
    "title": "<string or omit>",
    "body": "<string or omit>",
    "targetTypes": ["pastor|mentor|small_group_leader|trusted_friend|doctor|therapist|emergency_services"]
  },
  "sensitivitySummary": {
    "primaryState": "<string>",
    "sensitivityFlags": ["<string>"],
    "topicClass": "<string or null>"
  },
  "suggestedNextActions": [
    {
      "type": "<open_passage|save_reflection|start_immersion|view_journey|talk_to_leader>",
      "label": "<string>",
      "payload": {}
    }
  ],
  "confidenceNotes": {
    "containsInterpretiveCaution": <true|false>,
    "containsLeadershipRedirect": <true|false>
  }
}

CRITICAL RULES FOR OUTPUT:
1. answerText must NEVER claim direct divine revelation ("God told you...", "The Lord is definitely saying...")
2. answerText must NEVER advise avoiding emergency services, doctors, or legal authorities
3. answerText must NEVER tell someone to stay in an abusive situation
4. If crisis flags are present, leadershipPrompt.show MUST be true with crisis resources
5. If uncertain on a doctrinal point, say so explicitly in answerText
6. studyCards must be meaningful additions — do not pad with empty cards
7. If no study cards are appropriate, return an empty array
8. prayerPrompt should be an invitational question or prompt, not a scripted prayer the AI "prays"`;
}
