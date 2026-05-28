import { SmartDetectedEntity } from "./types";
import { stableId } from "./validators";

const TOPICS: Record<string, string[]> = {
  grace: ["grace", "mercy", "forgiveness"],
  anxiety: ["anxiety", "worry", "fear", "anxious"],
  prayer: ["prayer", "pray", "intercession"],
  fasting: ["fast", "fasting"],
  marriage: ["marriage", "wife", "husband"],
  discipleship: ["discipleship", "disciple", "mentor"],
  leadership: ["leadership", "leader", "pastor", "elder"],
  suffering: ["suffering", "trial", "hard season"],
  logistics: ["meeting", "schedule", "bring", "building", "zoom"],
  worship: ["worship", "song", "praise"],
};

export function extractTopics(text: string): SmartDetectedEntity[] {
  const lower = text.toLowerCase();
  const now = Date.now();
  const entities: SmartDetectedEntity[] = [];
  for (const [topic, terms] of Object.entries(TOPICS)) {
    const term = terms.find((candidate) => lower.includes(candidate));
    if (!term) continue;
    const start = lower.indexOf(term);
    entities.push({
      id: stableId("topic", [topic, start]),
      type: "topic",
      sourceText: text.slice(start, start + term.length),
      normalizedValue: topic,
      confidence: 0.68,
      range: { start, length: term.length },
      createdAt: now,
    });
  }
  return entities;
}
