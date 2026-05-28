import { SmartMessageAction } from "./types";
import { stableId } from "./validators";

export function contextualBereanActions(selectedText: string, sourceType: string, sourceId?: string): SmartMessageAction[] {
  const basePayload = { selectedText, sourceType, sourceId: sourceId ?? "" };
  return [
    ["Explain", "Find meaning and context", "text.bubble", "askBerean"],
    ["Find Scripture", "Search related passages", "books.vertical", "askBerean"],
    ["Compare Context", "Explore biblical context", "rectangle.split.2x1", "askBerean"],
    ["Create Reflection", "Turn this into a reflection", "square.and.pencil", "saveToJournal"],
    ["Start Study", "Create a study session", "book.closed", "startStudyMode"],
    ["Save to Church Notes", "Prefill a note", "note.text", "saveToJournal"],
    ["Pray Through This", "Open prayer reflection", "hands.sparkles", "prayNow"],
  ].map(([title, subtitle, iconSystemName, actionType]) => ({
    id: stableId("bereanAction", [title, selectedText, sourceId]),
    title,
    subtitle,
    iconSystemName,
    actionType: actionType as SmartMessageAction["actionType"],
    payload: basePayload,
    requiresConfirmation: actionType === "saveToJournal" || actionType === "startStudyMode",
    privacyLevel: "private",
  }));
}
