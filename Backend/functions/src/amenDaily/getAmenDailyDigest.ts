import {onCall, HttpsError} from "firebase-functions/v2/https";
import {AmenDailyDigestRequest} from "./amenDailyTypes";
import {resolveChristianCalendar} from "./christianCalendarResolver";
import {resolveGeneralHoliday} from "./holidayResolver";
import {resolveWeatherContext} from "./weatherContextResolver";
import {selectDailyVerse} from "./dailyVerseResolver";
import {buildDigest, resolvePriority} from "./digestPriorityEngine";

export const getAmenDailyDigest = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 10,
    memory: "256MiB",
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const data = request.data as AmenDailyDigestRequest;
    const dateKey = normalizeDateKey(data.dateKey, data.timezone);
    const locale = safeString(data.locale, "en_US");
    const christianHoliday = data.christianCalendarEnabled !== false ? resolveChristianCalendar(dateKey) : undefined;
    const generalHoliday = data.holidayEnabled !== false ? resolveGeneralHoliday(dateKey) : undefined;
    const holiday = christianHoliday ?? generalHoliday;
    const weather = resolveWeatherContext(data.weatherEnabled === true, data.weather);
    const priority = resolvePriority(christianHoliday, generalHoliday, weather);
    const verse = selectDailyVerse(dateKey, holiday);

    return buildDigest({dateKey, locale, verse, priority, holiday, weather});
  },
);

function normalizeDateKey(dateKey?: string, timezone?: string): string {
  if (dateKey && /^\\d{4}-\\d{2}-\\d{2}$/.test(dateKey)) return dateKey;
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(new Date());
}

function safeString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.length <= 80 ? value : fallback;
}
