import { SmartDetectedEntity, SmartMessageAction } from "./types";
import { stableId } from "./validators";

const BOOKS = [
  "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
  "Samuel", "Kings", "Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalm", "Psalms",
  "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations",
  "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum",
  "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi", "Matthew", "Mark", "Luke",
  "John", "Acts", "Romans", "Corinthians", "Galatians", "Ephesians", "Philippians",
  "Colossians", "Thessalonians", "Timothy", "Titus", "Philemon", "Hebrews", "James",
  "Peter", "Jude", "Revelation",
];

const bookPattern = BOOKS
  .sort((a, b) => b.length - a.length)
  .map((book) => book.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
  .join("|");

const scriptureRegex = new RegExp(`\\b(?:[1-3]\\s*)?(?:${bookPattern})\\s+\\d{1,3}(?::\\d{1,3}(?:[-–]\\d{1,3})?)?\\b`, "gi");

export function normalizeScriptureReference(value: string): string {
  return value.replace(/\s+/g, " ").replace("Psalms ", "Psalm ").trim();
}

export function detectScriptures(text: string): SmartDetectedEntity[] {
  const now = Date.now();
  const matches: SmartDetectedEntity[] = [];
  for (const match of text.matchAll(scriptureRegex)) {
    const sourceText = match[0];
    const normalizedValue = normalizeScriptureReference(sourceText);
    matches.push({
      id: stableId("scripture", [normalizedValue, match.index ?? 0]),
      type: "scriptureReference",
      sourceText,
      normalizedValue,
      confidence: /:\d/.test(sourceText) ? 0.94 : 0.82,
      range: { start: match.index ?? 0, length: sourceText.length },
      createdAt: now,
      metadata: parseScriptureParts(normalizedValue),
    });
  }
  return matches;
}

export function scriptureActions(entity: SmartDetectedEntity): SmartMessageAction[] {
  return [
    {
      id: stableId("action", [entity.id, "openScripture"]),
      title: "Open Scripture",
      subtitle: entity.normalizedValue,
      iconSystemName: "book",
      actionType: "openScripture",
      payload: { scriptureReference: entity.normalizedValue },
      requiresConfirmation: false,
      privacyLevel: "private",
    },
    {
      id: stableId("action", [entity.id, "askBerean"]),
      title: "Ask Berean",
      subtitle: "Explore context and application",
      iconSystemName: "sparkles",
      actionType: "askBerean",
      payload: { selectedText: entity.sourceText, scriptureReference: entity.normalizedValue },
      requiresConfirmation: false,
      privacyLevel: "private",
    },
  ];
}

function parseScriptureParts(reference: string): Record<string, unknown> {
  const match = reference.match(/^((?:[1-3]\s*)?[A-Za-z ]+)\s+(\d{1,3})(?::(\d{1,3})(?:[-–](\d{1,3}))?)?$/);
  if (!match) return {};
  return {
    book: match[1].trim(),
    chapter: Number(match[2]),
    verseStart: match[3] ? Number(match[3]) : null,
    verseEnd: match[4] ? Number(match[4]) : match[3] ? Number(match[3]) : null,
  };
}
