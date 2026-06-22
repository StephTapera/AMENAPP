export type WeatherAlertLevel = "none" | "notable" | "severe";
export type HolidayType = "general" | "christian" | "season";
export type AmenDailyDigestPriority =
  | "christianHoliday"
  | "generalHoliday"
  | "severeWeather"
  | "notableWeather"
  | "personalContinuation"
  | "defaultVerse";
export type AmenDailyDigestSource = "bundled" | "remoteConfig" | "backend" | "cached";

export interface AmenDailyDigestRequest {
  dateKey?: string;
  timezone?: string;
  locale?: string;
  approximateRegion?: string;
  countryCode?: string;
  weatherEnabled?: boolean;
  holidayEnabled?: boolean;
  christianCalendarEnabled?: boolean;
  personalizationEnabled?: boolean;
  weather?: AmenDailyWeatherContext;
}

export interface AmenDailyDigest {
  id: string;
  dateKey: string;
  greeting: string;
  title: string;
  verseText: string;
  verseReference: string;
  contextText?: string;
  reflectionText?: string;
  prayerPrompt?: string;
  passage?: AmenDailyPassage;
  weather?: AmenDailyWeatherContext;
  holiday?: AmenDailyHolidayContext;
  actions: AmenDailyDigestAction[];
  priority: AmenDailyDigestPriority;
  generatedAt?: string;
  source: AmenDailyDigestSource;
}

export interface AmenDailyWeatherContext {
  temperature?: number;
  condition?: string;
  high?: number;
  low?: number;
  precipitationChance?: number;
  alertLevel: WeatherAlertLevel;
  summary?: string;
  spiritualTieIn?: string;
}

export interface AmenDailyHolidayContext {
  name: string;
  type: HolidayType;
  message: string;
  suggestedVerseReference?: string;
  dateKey: string;
  title?: string;
  suggestedAction?: string;
  verseText?: string;
  passageReference?: string;
}

export interface AmenDailyPassage {
  reference: string;
  title?: string;
  book?: string;
  chapter?: number;
  startVerse?: number;
  endVerse?: number;
}

export interface AmenDailyDigestAction {
  id: string;
  title: string;
  systemImage?: string;
  destination: AmenDailyDigestDestination;
  analyticsName: string;
}

export type AmenDailyDigestDestination =
  | { type: "selah" }
  | { type: "passage"; reference: string }
  | { type: "bereanAI"; prompt: string }
  | { type: "churchNotes"; prefill?: string }
  | { type: "findAChurch" }
  | { type: "prayer"; prompt?: string }
  | { type: "share"; text: string }
  | { type: "journal"; prefill?: string }
  | { type: "none" };
