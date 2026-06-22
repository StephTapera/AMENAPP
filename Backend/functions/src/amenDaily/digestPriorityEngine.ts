import {
  AmenDailyDigest,
  AmenDailyDigestAction,
  AmenDailyDigestPriority,
  AmenDailyHolidayContext,
  AmenDailyWeatherContext,
} from "./amenDailyTypes";
import {VerseSelection} from "./dailyVerseResolver";

export function resolvePriority(
  christianHoliday?: AmenDailyHolidayContext,
  generalHoliday?: AmenDailyHolidayContext,
  weather?: AmenDailyWeatherContext,
): AmenDailyDigestPriority {
  if (christianHoliday) return "christianHoliday";
  if (generalHoliday) return "generalHoliday";
  if (weather?.alertLevel === "severe") return "severeWeather";
  if (weather?.alertLevel === "notable") return "notableWeather";
  return "defaultVerse";
}

export function buildDigest(params: {
  dateKey: string;
  locale: string;
  verse: VerseSelection;
  priority: AmenDailyDigestPriority;
  holiday?: AmenDailyHolidayContext;
  weather?: AmenDailyWeatherContext;
}): AmenDailyDigest {
  const {dateKey, verse, priority, holiday, weather} = params;
  const title = holiday?.title ?? weatherTitle(weather) ?? verse.title;
  const contextText = holiday?.message ?? weather?.summary ?? verse.contextText;
  return {
    id: `amen-daily-${dateKey}`,
    dateKey,
    greeting: greetingFor(dateKey),
    title,
    verseText: verse.verseText,
    verseReference: verse.verseReference,
    contextText,
    reflectionText: verse.reflectionText,
    prayerPrompt: verse.prayerPrompt,
    passage: {
      reference: verse.passageReference,
      title: verse.passageTitle,
      book: verse.passageReference.split(" ")[0],
    },
    weather,
    holiday,
    actions: buildActions(dateKey, verse, title, holiday, priority),
    priority,
    generatedAt: new Date().toISOString(),
    source: "backend",
  };
}

function buildActions(
  dateKey: string,
  verse: VerseSelection,
  title: string,
  holiday: AmenDailyHolidayContext | undefined,
  priority: AmenDailyDigestPriority,
): AmenDailyDigestAction[] {
  const askPrompt = `Help me understand ${verse.verseReference} in context. Explain the passage carefully, include historical context, key themes, and a practical reflection for today.`;
  const notePrefill = `${dateKey}\n${verse.verseReference}\n${verse.verseText}\n\nReflection: ${verse.reflectionText}\n\nPrayer: ${verse.prayerPrompt}`;
  const shareText = `${verse.verseText}\n- ${verse.verseReference}\n\n${verse.contextText}\n\nFrom Amen`;
  const primary: AmenDailyDigestAction[] = [];

  if (holiday?.name === "Mother's Day") {
    primary.push({id: "pray", title: "Pray", systemImage: "hands.sparkles", destination: {type: "prayer", prompt: verse.prayerPrompt}, analyticsName: "pray"});
    primary.push({id: "share_encouragement", title: "Send Encouragement", systemImage: "square.and.arrow.up", destination: {type: "share", text: shareText}, analyticsName: "share_encouragement"});
  } else if (priority === "christianHoliday") {
    primary.push({id: "read_passage", title: `Read ${verse.passageReference}`, systemImage: "book", destination: {type: "passage", reference: verse.passageReference}, analyticsName: "read_passage"});
    primary.push({id: "reflect", title: "Reflect", systemImage: "sparkles", destination: {type: "selah"}, analyticsName: "reflect"});
  } else {
    primary.push({id: "start_selah", title: "Start Selah", systemImage: "sparkles", destination: {type: "selah"}, analyticsName: "start_selah"});
    primary.push({id: "read_passage", title: "Read Passage", systemImage: "book", destination: {type: "passage", reference: verse.passageReference}, analyticsName: "read_passage"});
  }

  return [
    ...primary,
    {id: "ask_berean_ai", title: "Ask Berean AI", systemImage: "sparkles", destination: {type: "bereanAI", prompt: askPrompt}, analyticsName: "ask_berean_ai"},
    {id: "save_church_notes", title: "Save to Church Notes", systemImage: "note.text", destination: {type: "churchNotes", prefill: notePrefill}, analyticsName: "save_church_notes"},
    {id: "journal", title: "Journal", systemImage: "square.and.pencil", destination: {type: "journal", prefill: notePrefill}, analyticsName: "journal"},
    ...(shouldOfferFindChurch(holiday, dateKey) ? [{id: "find_church", title: "Find a Church", systemImage: "mappin.and.ellipse", destination: {type: "findAChurch"} as const, analyticsName: "find_church"}] : []),
    {id: "share", title: "Share Encouragement", systemImage: "square.and.arrow.up", destination: {type: "share", text: shareText}, analyticsName: "share"},
  ];
}

function shouldOfferFindChurch(holiday: AmenDailyHolidayContext | undefined, dateKey: string): boolean {
  const day = new Date(`${dateKey}T00:00:00Z`).getUTCDay();
  return day === 0 || holiday?.name === "Easter" || holiday?.name === "Christmas" || holiday?.name === "Christmas Day";
}

function weatherTitle(weather?: AmenDailyWeatherContext): string | undefined {
  if (!weather) return undefined;
  const condition = (weather.condition ?? "").toLowerCase();
  if (weather.alertLevel === "severe") return "Weather alert";
  if (condition.includes("rain")) return "Rain today";
  if (condition.includes("snow")) return "Snow today";
  if (condition.includes("storm")) return "Storms possible";
  return undefined;
}

function greetingFor(dateKey: string): string {
  return dateKey ? "Good morning" : "Daily Verse";
}
