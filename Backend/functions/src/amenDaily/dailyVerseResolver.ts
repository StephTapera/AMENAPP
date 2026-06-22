import {AmenDailyHolidayContext} from "./amenDailyTypes";

export interface VerseSelection {
  title: string;
  verseText: string;
  verseReference: string;
  reflectionText: string;
  prayerPrompt: string;
  passageReference: string;
  passageTitle?: string;
  contextText: string;
}

const verses: VerseSelection[] = [
  {
    title: "Good morning",
    verseText: "The Lord is my shepherd; I shall not want.",
    verseReference: "Psalm 23:1",
    contextText: "Start today grounded.",
    reflectionText: "God's care is steady before the day begins. Take a quiet moment to receive his presence and move with peace.",
    prayerPrompt: "Lord, guide my attention today and help me walk with trust.",
    passageReference: "Psalm 23",
    passageTitle: "The Lord Is My Shepherd",
  },
  {
    title: "Start the week grounded",
    verseText: "Commit your work to the Lord, and your plans will be established.",
    verseReference: "Proverbs 16:3",
    contextText: "Before the day gets full, take a short moment to reset.",
    reflectionText: "Work can begin from surrender rather than pressure. Offer the day to God before it starts moving quickly.",
    prayerPrompt: "Lord, establish what is good and teach me to work with peace.",
    passageReference: "Proverbs 16",
  },
  {
    title: "Peace for today",
    verseText: "You keep him in perfect peace whose mind is stayed on you.",
    verseReference: "Isaiah 26:3",
    contextText: "A quiet breath before the day begins can re-center your attention.",
    reflectionText: "Peace is not passivity. It is attention anchored in the Lord while you do the next faithful thing.",
    prayerPrompt: "Lord, steady my mind and keep me near to you today.",
    passageReference: "Isaiah 26",
  },
];

const holidayVerses: Record<string, VerseSelection> = {
  "Mother's Day": {
    title: "Happy Mother's Day",
    verseText: "Her children rise up and call her blessed.",
    verseReference: "Proverbs 31:28",
    contextText: "Take a moment to honor, remember, or pray for mothers and mother figures.",
    reflectionText: "Today can hold gratitude, tenderness, joy, or grief. Bring the whole day honestly before God.",
    prayerPrompt: "Lord, bless mothers and mother figures, and comfort those for whom this day is tender.",
    passageReference: "Proverbs 31",
  },
  Easter: {
    title: "He is risen",
    verseText: "He is not here; he has risen!",
    verseReference: "Luke 24:6",
    contextText: "Today is a day of resurrection, renewal, and hope.",
    reflectionText: "The resurrection is not an idea to admire from a distance. It is hope breaking into the ordinary day.",
    prayerPrompt: "Risen Lord, renew my hope and teach me to live in your life today.",
    passageReference: "Luke 24",
  },
  Christmas: {
    title: "Merry Christmas",
    verseText: "For unto you is born this day in the city of David a Savior, who is Christ the Lord.",
    verseReference: "Luke 2:11",
    contextText: "Today's focus: presence, peace, and the gift of Christ.",
    reflectionText: "Christ comes near in humility and grace. Receive the gift before rushing to explain it.",
    prayerPrompt: "Jesus, help me receive your nearness with gratitude and peace.",
    passageReference: "Luke 2",
  },
  "Christmas Day": {
    title: "Merry Christmas",
    verseText: "For unto you is born this day in the city of David a Savior, who is Christ the Lord.",
    verseReference: "Luke 2:11",
    contextText: "Today's focus: presence, peace, and the gift of Christ.",
    reflectionText: "Christ comes near in humility and grace. Receive the gift before rushing to explain it.",
    prayerPrompt: "Jesus, help me receive your nearness with gratitude and peace.",
    passageReference: "Luke 2",
  },
  Thanksgiving: {
    title: "Give thanks",
    verseText: "Oh give thanks to the Lord, for he is good, for his steadfast love endures forever!",
    verseReference: "Psalm 107:1",
    contextText: "Name one mercy before the day gets full.",
    reflectionText: "Gratitude trains attention toward grace. Start with one honest thanks and let it become prayer.",
    prayerPrompt: "Lord, open my eyes to your mercy and make me generous with thanks.",
    passageReference: "Psalm 107",
  },
};

export function selectDailyVerse(dateKey: string, holiday?: AmenDailyHolidayContext): VerseSelection {
  if (holiday && holidayVerses[holiday.name]) return holidayVerses[holiday.name];
  if (holiday?.suggestedVerseReference) {
    return {
      ...verses[0],
      title: holiday.title ?? holiday.name,
      verseReference: holiday.suggestedVerseReference,
      contextText: holiday.message,
      passageReference: holiday.passageReference ?? holiday.suggestedVerseReference.replace(/:\\d+.*/, ""),
    };
  }
  const index = deterministicIndex(dateKey, verses.length);
  return verses[index];
}

function deterministicIndex(value: string, length: number): number {
  let hash = 0;
  for (const char of value) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return hash % length;
}
