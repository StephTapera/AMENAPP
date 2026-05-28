import { SmartDetectedEntity, SmartMessageAction } from "./types";
import { stableId } from "./validators";

const prayerRegex = /\b(?:please\s+pray|pray\s+for|praying\s+for|need\s+prayer|keep .* in prayer|praise report|thank God|urgent prayer)\b[^.!?]*/gi;

export function classifyPrayer(text: string): string {
  const lower = text.toLowerCase();
  if (lower.includes("urgent")) return "urgent prayer";
  if (/(surgery|hospital|cancer|health|sick|illness)/.test(lower)) return "health";
  if (/(grief|loss|funeral|died|passed away)/.test(lower)) return "grief";
  if (/(family|marriage|child|children|mom|dad|wife|husband)/.test(lower)) return "family";
  if (/(job|rent|money|provision|financial)/.test(lower)) return "provision";
  if (/(guidance|wisdom|decision|discern)/.test(lower)) return "guidance";
  if (/(praise|thank god|answered)/.test(lower)) return "praise report";
  return "general prayer";
}

export function detectPrayerRequests(text: string): SmartDetectedEntity[] {
  const now = Date.now();
  const entities: SmartDetectedEntity[] = [];
  for (const match of text.matchAll(prayerRegex)) {
    const sourceText = match[0].trim();
    const category = classifyPrayer(sourceText);
    entities.push({
      id: stableId("prayer", [sourceText, match.index ?? 0]),
      type: "prayerRequest",
      sourceText,
      normalizedValue: category,
      confidence: category === "general prayer" ? 0.76 : 0.86,
      range: { start: match.index ?? 0, length: match[0].length },
      createdAt: now,
      metadata: { category },
    });
  }
  return entities;
}

export function prayerActions(entity: SmartDetectedEntity): SmartMessageAction[] {
  return [
    {
      id: stableId("action", [entity.id, "createPrayerRequest"]),
      title: "Add to Prayer List",
      subtitle: "Review before saving",
      iconSystemName: "hands.sparkles",
      actionType: "createPrayerRequest",
      payload: { extractedText: entity.sourceText, category: entity.normalizedValue },
      requiresConfirmation: true,
      privacyLevel: "private",
    },
    {
      id: stableId("action", [entity.id, "prayNow"]),
      title: "Pray Now",
      subtitle: entity.normalizedValue,
      iconSystemName: "heart.text.square",
      actionType: "prayNow",
      payload: { extractedText: entity.sourceText },
      requiresConfirmation: false,
      privacyLevel: "private",
    },
    {
      id: stableId("action", [entity.id, "prayerReminder"]),
      title: "Set Reminder",
      subtitle: "Pray again later",
      iconSystemName: "bell",
      actionType: "addReminder",
      payload: { sourceText: entity.sourceText },
      requiresConfirmation: true,
      privacyLevel: "private",
    },
  ];
}
