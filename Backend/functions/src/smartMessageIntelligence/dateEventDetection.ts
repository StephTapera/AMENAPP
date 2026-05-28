import { SmartDetectedEntity, SmartMessageAction } from "./types";
import { stableId } from "./validators";

const dateWords = "\\b(?:today|tomorrow|tonight|sunday|monday|tuesday|wednesday|thursday|friday|saturday|next\\s+week|this\\s+weekend)\\b";
const timeWords = "\\b(?:at\\s+)?\\d{1,2}(?::\\d{2})?\\s*(?:am|pm|a\\.m\\.|p\\.m\\.)\\b";
const dateEventRegex = new RegExp(`(?:${dateWords}(?:[^.!?]{0,50}${timeWords})?|${timeWords})`, "gi");
const locationRegex = /\b(?:in|at)\s+([A-Z][A-Za-z0-9 .'-]{2,40}(?:Building|Room|Hall|Church|Center|Chapel|C|A|B)?)/g;

export function detectDateEvents(text: string): SmartDetectedEntity[] {
  const now = Date.now();
  const entities: SmartDetectedEntity[] = [];
  for (const match of text.matchAll(dateEventRegex)) {
    const sourceText = match[0].trim();
    entities.push({
      id: stableId("datetime", [sourceText, match.index ?? 0]),
      type: "dateTime",
      sourceText,
      normalizedValue: sourceText.toLowerCase(),
      confidence: 0.74,
      range: { start: match.index ?? 0, length: match[0].length },
      createdAt: now,
    });
  }
  for (const match of text.matchAll(locationRegex)) {
    const sourceText = match[0].trim();
    entities.push({
      id: stableId("location", [sourceText, match.index ?? 0]),
      type: "location",
      sourceText,
      normalizedValue: match[1].trim(),
      confidence: 0.62,
      range: { start: match.index ?? 0, length: match[0].length },
      createdAt: now,
    });
  }
  return entities;
}

export function eventActions(entity: SmartDetectedEntity, text: string): SmartMessageAction[] {
  return [
    {
      id: stableId("action", [entity.id, "calendar"]),
      title: "Add to Calendar",
      subtitle: entity.sourceText,
      iconSystemName: "calendar.badge.plus",
      actionType: "addToCalendar",
      payload: { sourceText: entity.sourceText, messageText: text },
      requiresConfirmation: true,
      privacyLevel: "private",
    },
    {
      id: stableId("action", [entity.id, "reminder"]),
      title: "Add Reminder",
      subtitle: entity.sourceText,
      iconSystemName: "bell.badge",
      actionType: "addReminder",
      payload: { sourceText: entity.sourceText, messageText: text },
      requiresConfirmation: true,
      privacyLevel: "private",
    },
  ];
}
