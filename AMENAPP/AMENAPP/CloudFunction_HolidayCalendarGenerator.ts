/**
 * CloudFunction_HolidayCalendarGenerator.ts
 *
 * Reference copy — actual deployable source is at:
 *   Backend/functions/src/holidayCalendarGenerator.ts
 *
 * Generates and stores the AMEN annual holiday calendar in Firestore.
 *
 * Firestore schema:
 *   holiday_calendar/{year}/days/{yyyy-MM-dd}/observances/{holidayId}
 *
 * Document fields (HolidayObservanceDoc):
 *   id                    — matches HolidayType.rawValue on iOS
 *   canonicalName         — display name
 *   category              — christian_event | biblical_feast | biblically_consistent | discernment | personal
 *   consistencyLevel      — strong | consistent | discernment | avoid
 *   dateType              — fixed | floating | easter_relative | hebrew_calendar | liturgical
 *   startDate             — yyyy-MM-dd (first day)
 *   endDate               — yyyy-MM-dd (last day, same as startDate for 1-day events)
 *   priority              — 1–10 (higher = shown first when multiple holidays coincide)
 *   primaryVerseReference — e.g. "Matthew 28:6"
 *   scriptures            — additional references array
 *   theme                 — comma-separated themes
 *   shortBannerTitle      — shown in the daily verse banner header (≤30 chars)
 *   shortBannerMessage    — shown in the banner body (≤120 chars)
 *   expandedReflection    — full reflection text for HolidayReflectionSheet
 *   callToActionLabel     — CTA button label
 *   callToActionRoute     — deep link: amen://study/{id}
 *   visualTreatment       — hint for future banner theming
 *   allowedTone           — pastoral tone guidance
 *   prohibitedTone        — content guardrail (never write this)
 *   safetyNotes           — additional editorial safety guidance
 *   createdAt             — Firestore serverTimestamp
 *   updatedAt             — Firestore serverTimestamp
 *   sourceVersion         — generator version string
 *
 * Exported functions:
 *   generateNextYearHolidayCalendar  — onSchedule: "0 6 1 11 *" (Nov 1, UTC)
 *   backfillHolidayCalendar          — onCall (admin-only): { year: number }
 *   validateHolidayCalendarYear      — onCall (admin-only): { year: number }
 *
 * Holiday coverage (26 total):
 *
 *   Christian Events (priority 7–10):
 *     easter, good_friday, christmas, christmas_eve, palm_sunday,
 *     ash_wednesday, pentecost, ascension
 *
 *   Biblical Feasts (priority 6–8):
 *     passover, feast_of_trumpets, day_of_atonement, feast_of_tabernacles,
 *     feast_of_weeks, firstfruits
 *
 *   Biblically Consistent Civic (priority 3–5):
 *     thanksgiving, mothers_day, fathers_day, memorial_day, labor_day,
 *     independence_day, veterans_day, new_years
 *
 *   Discernment (priority 2):
 *     halloween, valentines_day, st_patricks_day, mardi_gras
 *
 * Date algorithms:
 *   - Easter: Anonymous Gregorian algorithm (Computus)
 *   - Easter-relative: offset ± N days from Easter
 *   - Passover: lookup table 2024–2033 (hebcal.com), Gauss fallback
 *   - Rosh Hashanah: lookup table 2024–2033, ~163-day offset from Passover fallback
 *   - Floating civic: nthWeekday() / lastWeekday() using UTC DateComponents
 *   - Fixed: utcDate(year, month, day)
 *
 * iOS integration:
 *   HolidayAwarenessService.fetchFirestoreContext() reads this schema.
 *   Client falls back to LiturgicalCalendarEngine offline.
 *
 * Deployment:
 *   firebase deploy --only functions:generateNextYearHolidayCalendar
 *   firebase deploy --only functions:backfillHolidayCalendar
 *   firebase deploy --only functions:validateHolidayCalendarYear
 *
 * First-time setup (backfill current + next year):
 *   Call backfillHolidayCalendar({ year: 2025 }) and { year: 2026 }) from admin.
 */

// See Backend/functions/src/holidayCalendarGenerator.ts for full implementation.
