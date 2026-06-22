/**
 * liturgicalSeason.ts
 * Phase 2D — Berean Sabbath Guide
 * Date: 2026-06-07
 *
 * Pure TypeScript liturgical season detection.
 * No external dependencies. Approximate season boundaries — not exact
 * church-calendar-spec, but sufficient for liturgical context prompts.
 *
 * DO NOT import from contracts (read-only). This file is standalone.
 */

// ── Types ─────────────────────────────────────────────────────────────────────

export type LiturgicalSeason =
  | 'Advent'
  | 'Christmas'
  | 'Epiphany'
  | 'Lent'
  | 'HolyWeek'
  | 'Easter'
  | 'Pentecost'
  | 'OrdinaryTime';

export interface LiturgicalContext {
  season: LiturgicalSeason;
  weekNumber?: number;       // e.g. "3rd week of Advent"
  dominantTheme: string;     // e.g. "hope", "preparation", "resurrection"
  suggestedScriptures: string[];  // e.g. ["Isaiah 40:3-5", "Luke 3:1-6"]
  colorSignifier: string;    // liturgical color word only — never a hex
}

// ── Easter Calculation (Anonymous Gregorian Algorithm) ────────────────────────

/**
 * Returns Easter Sunday (month 0-indexed) for the given year.
 * Uses the Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
 */
function computeEaster(year: number): Date {
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31); // 1-indexed
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(year, month - 1, day); // month 0-indexed for Date
}

// ── Season Data ───────────────────────────────────────────────────────────────

interface SeasonData {
  dominantTheme: string;
  suggestedScriptures: string[];
  colorSignifier: string;
}

const SEASON_DATA: Record<LiturgicalSeason, SeasonData> = {
  Advent: {
    dominantTheme: 'hope and preparation',
    suggestedScriptures: [
      'Isaiah 40:3-5',
      'Luke 3:1-6',
      'Romans 13:11-14',
      'Matthew 24:36-44',
    ],
    colorSignifier: 'purple',
  },
  Christmas: {
    dominantTheme: 'incarnation and joy',
    suggestedScriptures: [
      'Luke 2:1-20',
      'John 1:1-14',
      'Isaiah 9:6-7',
      'Titus 2:11-14',
    ],
    colorSignifier: 'white',
  },
  Epiphany: {
    dominantTheme: 'revelation and light',
    suggestedScriptures: [
      'Matthew 2:1-12',
      'Isaiah 60:1-6',
      'Ephesians 3:1-12',
      'Luke 2:41-52',
    ],
    colorSignifier: 'white',
  },
  Lent: {
    dominantTheme: 'repentance and renewal',
    suggestedScriptures: [
      'Psalm 51:1-17',
      'Matthew 4:1-11',
      'Joel 2:12-13',
      '2 Corinthians 5:20-21',
    ],
    colorSignifier: 'purple',
  },
  HolyWeek: {
    dominantTheme: 'suffering, sacrifice, and surrender',
    suggestedScriptures: [
      'Isaiah 53:1-12',
      'Philippians 2:5-11',
      'John 12:12-16',
      'Luke 22:39-46',
    ],
    colorSignifier: 'red',
  },
  Easter: {
    dominantTheme: 'resurrection and new life',
    suggestedScriptures: [
      'John 20:1-18',
      '1 Corinthians 15:1-11',
      'Romans 6:3-11',
      'Colossians 3:1-4',
    ],
    colorSignifier: 'white',
  },
  Pentecost: {
    dominantTheme: 'the Holy Spirit and the life of the Church',
    suggestedScriptures: [
      'Acts 2:1-21',
      'Romans 8:14-17',
      'John 14:8-17',
      'Ezekiel 37:1-14',
    ],
    colorSignifier: 'red',
  },
  OrdinaryTime: {
    dominantTheme: 'growth, discipleship, and faithful living',
    suggestedScriptures: [
      'Matthew 5:1-12',
      'Romans 12:1-2',
      'Micah 6:8',
      'James 1:22-25',
    ],
    colorSignifier: 'green',
  },
};

// ── Helper: days between two dates (ignores time) ─────────────────────────────

function daysBetween(a: Date, b: Date): number {
  const MS_PER_DAY = 1000 * 60 * 60 * 24;
  const aUtc = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const bUtc = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((bUtc - aUtc) / MS_PER_DAY);
}

/** Returns the most recent Sunday on or before `date`. */
function startOfWeek(date: Date): Date {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const dow = d.getDay(); // 0 = Sunday
  d.setDate(d.getDate() - dow);
  return d;
}

// ── Advent Calculation ────────────────────────────────────────────────────────

/**
 * Returns the first Sunday of Advent for the given year.
 * Advent begins on the Sunday nearest November 30 (St. Andrew's Day).
 * Equivalently: the 4th Sunday before Christmas (Dec 25).
 */
function firstSundayOfAdvent(year: number): Date {
  const christmas = new Date(year, 11, 25); // Dec 25
  const dow = christmas.getDay(); // 0 = Sunday
  // Days to subtract to get to the Sunday before Christmas
  const daysToLastSundayBeforeChristmas = dow === 0 ? 7 : dow;
  const lastSundayBeforeChristmas = new Date(year, 11, 25 - daysToLastSundayBeforeChristmas);
  // First Sunday of Advent = 3 Sundays before that (i.e. 4th Sunday counting back from Christmas)
  const firstAdvent = new Date(lastSundayBeforeChristmas);
  firstAdvent.setDate(firstAdvent.getDate() - 21);
  return firstAdvent;
}

// ── Main Export ───────────────────────────────────────────────────────────────

/**
 * Determines the approximate liturgical season for a given date.
 *
 * Season boundaries are approximate (±1 day at edges) — sufficient for
 * contextual prompt shaping but not suitable for canonical church-calendar use.
 */
export function getLiturgicalContext(date: Date): LiturgicalContext {
  const year = date.getFullYear();
  const month = date.getMonth();  // 0-indexed
  const day = date.getDate();

  // Normalize to midnight for comparison
  const d = new Date(year, month, day);

  // ── Easter-relative seasons ──────────────────────────────────────────────
  const easter = computeEaster(year);
  const daysToEaster = daysBetween(d, easter); // negative = after Easter
  const daysAfterEaster = -daysToEaster;       // positive = after Easter

  // Ash Wednesday = 46 days before Easter
  const ashWednesdayOffset = -46;
  // Holy Week = Palm Sunday (7 days before Easter) through Holy Saturday (1 day before)
  const palmSundayOffset = -7;

  // Pentecost = 49 days after Easter (the 50th day)
  // We treat Pentecost Sunday as its own season (one day)
  const pentecostDay = daysAfterEaster === 49;

  // Easter season: Easter Sunday through the day before Pentecost
  if (daysAfterEaster >= 0 && daysAfterEaster < 49) {
    if (pentecostDay) {
      // This branch is never hit (49 < 49 is false), handled below
    }
    const data = SEASON_DATA['Easter'];
    const weekNumber = Math.floor(daysAfterEaster / 7) + 1;
    return { season: 'Easter', weekNumber, ...data };
  }

  if (pentecostDay) {
    const data = SEASON_DATA['Pentecost'];
    return { season: 'Pentecost', ...data };
  }

  // Holy Week: Palm Sunday through Holy Saturday
  if (daysToEaster >= 1 && daysToEaster <= 7) {
    const data = SEASON_DATA['HolyWeek'];
    return { season: 'HolyWeek', ...data };
  }

  // Lent: Ash Wednesday through Holy Saturday (i.e. daysToEaster 2..46)
  if (daysToEaster >= 2 && daysToEaster <= 46) {
    const data = SEASON_DATA['Lent'];
    // Week number within Lent (approximate, starting from Ash Wednesday)
    const daysIntoLent = 46 - daysToEaster;
    const weekNumber = Math.floor(daysIntoLent / 7) + 1;
    return { season: 'Lent', weekNumber, ...data };
  }

  // ── Calendar-relative seasons ────────────────────────────────────────────

  // Christmas: Dec 25 – Jan 5 (12 days of Christmas)
  const isChristmasSeason =
    (month === 11 && day >= 25) ||
    (month === 0 && day <= 5);

  if (isChristmasSeason) {
    const data = SEASON_DATA['Christmas'];
    return { season: 'Christmas', ...data };
  }

  // Advent: first Sunday of Advent through Dec 24
  const currentAdventStart = firstSundayOfAdvent(year);
  // Also check previous year's Advent for early Jan dates
  const prevAdventStart = firstSundayOfAdvent(year - 1);
  const adventEnd = new Date(year, 11, 24);

  const isInAdvent =
    (d >= currentAdventStart && d <= adventEnd);

  if (isInAdvent) {
    const data = SEASON_DATA['Advent'];
    const weekNumber = Math.floor(daysBetween(currentAdventStart, d) / 7) + 1;
    return { season: 'Advent', weekNumber: Math.min(weekNumber, 4), ...data };
  }

  // Epiphany: Jan 6 through Ash Wednesday eve (handled above by Lent check)
  // At this point we're after Jan 5 and before Lent
  if (month === 0 && day >= 6) {
    const data = SEASON_DATA['Epiphany'];
    return { season: 'Epiphany', ...data };
  }

  // Epiphany continues into February until Ash Wednesday
  // (if we are in Jan-Feb and haven't hit Lent yet, it's Epiphany)
  if (month === 1 && daysToEaster > 46) {
    const data = SEASON_DATA['Epiphany'];
    return { season: 'Epiphany', ...data };
  }

  // Ordinary Time: everything else
  // (after Pentecost until Advent; also the brief window in early Jan if any)
  const data = SEASON_DATA['OrdinaryTime'];
  return { season: 'OrdinaryTime', ...data };
}
