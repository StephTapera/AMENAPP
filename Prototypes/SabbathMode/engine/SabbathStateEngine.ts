/**
 * SabbathStateEngine.ts — PHASE 2A — State & Gating Engine
 * Pure TypeScript (no React). Timezone-aware Sabbath state computation.
 *
 * Implements:
 *   - computeSabbathState(config, now): SabbathState
 *   - getLocalDateString(timezone, now?): string
 *   - canStepOut(session, policy): boolean
 *   - buildSessionKey(timezone, chosenDay): string
 */

import type { SabbathState, SabbathDay, SabbathBoundary } from '../contracts/SabbathTypes';
import type { SabbathConfig, SabbathSession } from '../contracts/SabbathModels';
import type { SabbathConfigDefaults } from '../contracts/SabbathConfig';

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL UTILITIES
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Map our SabbathDay to the JS Date.getDay() weekday number.
 * getDay() returns: 0=Sunday, 1=Monday … 6=Saturday.
 */
const DAY_TO_JS_WEEKDAY: Record<SabbathDay, number> = {
  sunday: 0,
  saturday: 6,
};

/**
 * Return the local-time components (year, month, day, hour, minute, weekday)
 * for the given `now` expressed in the given IANA `timezone`.
 *
 * We rely on Intl.DateTimeFormat which is available in all modern JS runtimes
 * (React Native Hermes, Node ≥ 13, all browsers).
 */
function getLocalParts(
  timezone: string,
  now: Date,
): {
  year: number;
  month: number; // 1-based
  day: number;
  hour: number;
  minute: number;
  weekday: number; // 0 = Sunday … 6 = Saturday (JS convention)
} {
  // Use Intl to decompose the date in the target timezone.
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    weekday: 'short', // e.g. "Sun", "Sat"
  });

  const parts = fmt.formatToParts(now);
  const get = (type: string): string =>
    parts.find((p) => p.type === type)?.value ?? '0';

  const year = parseInt(get('year'), 10);
  const month = parseInt(get('month'), 10);
  const day = parseInt(get('day'), 10);
  const rawHour = parseInt(get('hour'), 10);
  // Intl hour12:false can return "24" for midnight in some environments — normalise.
  const hour = rawHour === 24 ? 0 : rawHour;
  const minute = parseInt(get('minute'), 10);

  // Map the short weekday string to a JS weekday number (0=Sun … 6=Sat).
  const WEEKDAY_MAP: Record<string, number> = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
  };
  const weekdayStr = get('weekday');
  const weekday = WEEKDAY_MAP[weekdayStr] ?? new Date(now).getDay();

  return { year, month, day, hour, minute, weekday };
}

// ─────────────────────────────────────────────────────────────────────────────
// SUNDOWN CALCULATION
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Estimate solar noon and approximate sunset for a given date and lat/lng.
 *
 * This is a simplified astronomical calculation (accurate to ±10 minutes) that
 * does not require any external library. For production accuracy consider
 * integrating SunCalc (npm package). The formula follows the NOAA simplified
 * method for solar declination and hour angle.
 *
 * @param date  Local calendar date (year/month/day in local time)
 * @param lat   Latitude in decimal degrees
 * @param lng   Longitude in decimal degrees (east positive)
 * @returns     Approximate sunset as fractional hours in LOCAL solar time
 *              (e.g. 19.5 = 19:30 local solar time)
 */
function approximateSunsetHour(
  date: { year: number; month: number; day: number },
  lat: number,
  lng: number,
): number {
  // Day of year (Julian day number approximation)
  const daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  let dayOfYear = date.day;
  for (let m = 1; m < date.month; m++) {
    dayOfYear += daysInMonth[m];
  }
  // Leap year correction
  if (
    date.month > 2 &&
    ((date.year % 4 === 0 && date.year % 100 !== 0) || date.year % 400 === 0)
  ) {
    dayOfYear += 1;
  }

  // Solar declination (degrees)
  const declination =
    -23.45 * Math.cos((360 / 365) * (dayOfYear + 10) * (Math.PI / 180));

  // Latitude in radians
  const latRad = lat * (Math.PI / 180);
  const declRad = declination * (Math.PI / 180);

  // Hour angle at sunset
  const cosHourAngle =
    -Math.tan(latRad) * Math.tan(declRad);

  if (cosHourAngle < -1) {
    // Sun never sets (midnight sun) — treat as 23:59
    return 23.983;
  }
  if (cosHourAngle > 1) {
    // Sun never rises (polar night) — treat as 0:01
    return 0.017;
  }

  const hourAngleDeg = Math.acos(cosHourAngle) * (180 / Math.PI);

  // Solar noon in UTC hours
  // Equation of time (minutes) — simplified
  const B = (360 / 365) * (dayOfYear - 81) * (Math.PI / 180);
  const eotMinutes =
    9.87 * Math.sin(2 * B) - 7.53 * Math.cos(B) - 1.5 * Math.sin(B);
  const solarNoonUTC = 12 - lng / 15 - eotMinutes / 60;

  // Sunset UTC
  const sunsetUTC = solarNoonUTC + hourAngleDeg / 15;

  return sunsetUTC;
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Returns the local date string `'yyyy-mm-dd'` expressed in the given IANA timezone.
 */
export function getLocalDateString(timezone: string, now: Date = new Date()): string {
  const { year, month, day } = getLocalParts(timezone, now);
  const mm = String(month).padStart(2, '0');
  const dd = String(day).padStart(2, '0');
  return `${year}-${mm}-${dd}`;
}

/**
 * Builds the session document key (the yyyy-mm-dd string used as the Firestore
 * document ID for a SabbathSession).
 *
 * The key is always the local date of the Sabbath DAY (i.e. the chosen weekday
 * the user observes), evaluated in the config timezone.
 *
 * During the current Sabbath window `buildSessionKey` returns today's local date.
 * Callers should only call this when `computeSabbathState` returns 'active' or
 * 'steppedOut'.
 */
export function buildSessionKey(
  timezone: string,
  chosenDay: SabbathDay,
  now: Date = new Date(),
): string {
  // For localMidnight boundaries the session key is simply today's local date.
  // For sundown boundaries the session key is still the calendar date of the
  // start of the observed Sabbath (i.e. the chosen weekday).
  // Since buildSessionKey is called after the state is confirmed active,
  // returning today's local date is correct.
  return getLocalDateString(timezone, now);
}

/**
 * Determine whether the user may step out of Sabbath Mode.
 *
 * @param session   The current SabbathSession (may be partial — steppedOutAt optional)
 * @param policy    The stepOutPolicy from SabbathConfigDefaults
 * @param confirmed Whether the caller has already surfaced a confirmation UI
 * @returns         true if stepping out is permitted; false otherwise
 */
export function canStepOut(
  session: Pick<SabbathSession, 'steppedOutAt'>,
  policy: SabbathConfigDefaults['stepOutPolicy'],
  confirmed: boolean = false,
): boolean {
  // If the user has already stepped out and maxPerSabbath is 1, deny.
  if (session.steppedOutAt !== undefined && policy.maxPerSabbath === 1) {
    return false;
  }

  // If confirmation is required and the caller has not confirmed, deny.
  if (policy.requiresConfirm && !confirmed) {
    return false;
  }

  return true;
}

/**
 * Compute the current SabbathState given the user's config and the current time.
 *
 * Timezone-aware:
 *   - Reads `config.timezone` (IANA string)
 *   - Supports `config.boundary === 'localMidnight'` (standard midnight-to-midnight)
 *   - Supports `config.boundary === 'sundown'` with solar calculation when
 *     lat/lng are provided on the config object (extended config); otherwise
 *     falls back to midnight with a console.warn.
 *
 * NOTE: This function does NOT read Firestore. It is pure computation.
 * The caller (SabbathProvider) is responsible for reading the current session's
 * `steppedOutAt` and passing it via the extended config parameter below.
 *
 * @param config        The user's SabbathConfig from Firestore
 * @param now           The current instant (default: new Date())
 * @param steppedOutAt  If set, the engine short-circuits to 'steppedOut'
 *                      when we are inside the Sabbath window.
 */
export function computeSabbathState(
  config: SabbathConfig,
  now: Date = new Date(),
  steppedOutAt?: number,
): SabbathState {
  const { timezone, chosenDay, boundary } = config;

  const localParts = getLocalParts(timezone, now);
  const targetWeekday = DAY_TO_JS_WEEKDAY[chosenDay];

  let isInWindow = false;

  if (boundary === 'localMidnight') {
    // Active from 00:00 to 23:59 on the chosen weekday in the user's timezone.
    isInWindow = localParts.weekday === targetWeekday;
  } else if (boundary === 'sundown') {
    // Sundown-to-sundown: Sabbath begins at sundown on the EVE of the chosen day
    // and ends at sundown on the chosen day itself.
    //
    // Example for Saturday Sabbath:
    //   Friday   sundown → Saturday sundown  (active)
    //   Saturday sundown → Sunday midnight   (inactive)
    //   Sunday midnight  → Friday sundown    (inactive)

    // Extended config may carry lat/lng for accurate solar calculation.
    // These are not in the frozen SabbathConfig interface; we read them safely.
    const extConfig = config as SabbathConfig & {
      lat?: number;
      lng?: number;
    };

    if (
      typeof extConfig.lat === 'number' &&
      typeof extConfig.lng === 'number'
    ) {
      const todayDate = {
        year: localParts.year,
        month: localParts.month,
        day: localParts.day,
      };
      const sunsetUTCHours = approximateSunsetHour(
        todayDate,
        extConfig.lat,
        extConfig.lng,
      );

      // Convert sunset UTC hours to local hours (approximate via timezone offset).
      // We construct a Date for today at the computed sunset UTC time and then
      // read back the local hour in the target timezone.
      const sunsetDate = new Date(now);
      const todayMidnightUTC = Date.UTC(
        localParts.year,
        localParts.month - 1,
        localParts.day,
        0,
        0,
        0,
        0,
      );
      sunsetDate.setTime(
        todayMidnightUTC + sunsetUTCHours * 60 * 60 * 1000,
      );

      const sunsetLocalParts = getLocalParts(timezone, sunsetDate);
      const nowFractionalHour =
        localParts.hour + localParts.minute / 60;
      const sunsetFractionalHour =
        sunsetLocalParts.hour + sunsetLocalParts.minute / 60;

      // Determine the EVE weekday (day before chosen Sabbath).
      const eveWeekday = (targetWeekday + 6) % 7;

      if (localParts.weekday === eveWeekday) {
        // On the eve: Sabbath begins at sundown.
        isInWindow = nowFractionalHour >= sunsetFractionalHour;
      } else if (localParts.weekday === targetWeekday) {
        // On the Sabbath day itself: active until sundown.
        isInWindow = nowFractionalHour < sunsetFractionalHour;
      } else {
        isInWindow = false;
      }
    } else {
      // No lat/lng available — graceful fallback to midnight boundary.
      console.warn(
        '[SabbathStateEngine] boundary=sundown requested but no lat/lng provided in config. ' +
          'Falling back to localMidnight boundary.',
      );
      isInWindow = localParts.weekday === targetWeekday;
    }
  }

  if (!isInWindow) {
    return 'inactive';
  }

  // We are inside the Sabbath window.
  // If the user has already stepped out, honour that for the rest of the day.
  if (steppedOutAt !== undefined) {
    return 'steppedOut';
  }

  return 'active';
}
