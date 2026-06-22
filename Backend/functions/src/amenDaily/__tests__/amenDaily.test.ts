import {calculateEasterSunday, resolveChristianCalendar} from "../christianCalendarResolver";
import {resolveGeneralHoliday} from "../holidayResolver";
import {resolveWeatherContext} from "../weatherContextResolver";
import {selectDailyVerse} from "../dailyVerseResolver";
import {buildDigest, resolvePriority} from "../digestPriorityEngine";

describe("Amen Daily Digest", () => {
  it("generates a default daily verse digest", () => {
    const dateKey = "2026-05-16";
    const verse = selectDailyVerse(dateKey);
    const digest = buildDigest({dateKey, locale: "en_US", verse, priority: "defaultVerse"});
    expect(digest.priority).toBe("defaultVerse");
    expect(digest.verseReference).toBeTruthy();
    expect(digest.actions.slice(0, 2)).toHaveLength(2);
  });

  it("detects Mother's Day", () => {
    const holiday = resolveGeneralHoliday("2026-05-10");
    expect(holiday?.name).toBe("Mother's Day");
    expect(holiday?.suggestedVerseReference).toBe("Proverbs 31:28");
  });

  it("detects Easter with computus", () => {
    expect(calculateEasterSunday(2026).toISOString().slice(0, 10)).toBe("2026-04-05");
    const holiday = resolveChristianCalendar("2026-04-05");
    expect(holiday?.name).toBe("Easter");
  });

  it("detects Christmas", () => {
    const holiday = resolveChristianCalendar("2026-12-25");
    expect(holiday?.name).toBe("Christmas");
    expect(holiday?.suggestedVerseReference).toBe("Luke 2:11");
  });

  it("detects Thanksgiving", () => {
    const holiday = resolveGeneralHoliday("2026-11-26");
    expect(holiday?.name).toBe("Thanksgiving");
  });

  it("prioritizes weather when no holiday is present", () => {
    const weather = resolveWeatherContext(true, {condition: "Light rain", alertLevel: "none", precipitationChance: 70});
    expect(weather?.alertLevel).toBe("notable");
    expect(resolvePriority(undefined, undefined, weather)).toBe("notableWeather");
  });

  it("prioritizes general holiday over default verse", () => {
    const general = resolveGeneralHoliday("2026-05-10");
    expect(resolvePriority(undefined, general, undefined)).toBe("generalHoliday");
  });

  it("prioritizes Christian holiday over general/default", () => {
    const christian = resolveChristianCalendar("2026-12-25");
    const general = resolveGeneralHoliday("2026-12-25");
    expect(resolvePriority(christian, general, undefined)).toBe("christianHoliday");
  });

  it("falls back cleanly when weather is unavailable", () => {
    expect(resolveWeatherContext(false, {condition: "Rain", alertLevel: "notable"})).toBeUndefined();
    expect(resolveWeatherContext(true, undefined)).toBeUndefined();
  });

  it("does not include precise location fields", () => {
    const dateKey = "2026-05-16";
    const weather = resolveWeatherContext(true, {condition: "Rain", alertLevel: "notable", summary: "Light rain expected."});
    const digest = buildDigest({dateKey, locale: "en_US", verse: selectDailyVerse(dateKey), priority: "notableWeather", weather});
    expect(JSON.stringify(digest)).not.toMatch(/latitude|longitude|precise/i);
  });
});
