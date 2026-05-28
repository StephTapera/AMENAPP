import { HttpsError } from "firebase-functions/v2/https";
import { SmartDetectedEntity } from "./types";
import { stableId } from "./validators";

export function transcriptEntity(transcript: string, messageId: string): SmartDetectedEntity {
  if (!transcript.trim()) {
    throw new HttpsError(
      "failed-precondition",
      "No transcript provider output was available. Request transcription through the approved audio pipeline first."
    );
  }
  return {
    id: stableId("voiceTranscript", [messageId, transcript.slice(0, 80)]),
    type: "voiceTranscript",
    sourceText: transcript.slice(0, 240),
    normalizedValue: transcript,
    confidence: 0.9,
    range: { start: 0, length: transcript.length },
    createdAt: Date.now(),
  };
}
