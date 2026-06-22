/**
 * holidayCalendarGenerator.ts
 *
 * Generates and stores the annual holiday calendar in Firestore.
 * Firestore schema:
 *   holiday_calendar/{year}/days/{yyyy-MM-dd}/observances/{holidayId}
 *
 * Exported functions:
 *   generateNextYearHolidayCalendar  — scheduled: runs Nov 1 every year, pre-generates next year
 *   backfillHolidayCalendar          — callable: backfills a specific year (admin-only)
 *   validateHolidayCalendarYear      — callable: checks completeness for a given year
 */

import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const db = admin.firestore();

// ─── Types ────────────────────────────────────────────────────────────────────

type HolidayCategory = "christian_event" | "biblical_feast" | "biblically_consistent" | "discernment" | "personal";
type HolidayConsistencyLevel = "strong" | "consistent" | "discernment" | "avoid";
type DateType = "fixed" | "floating" | "easter_relative" | "hebrew_calendar" | "liturgical";

interface HolidayObservanceDoc {
  id: string;
  canonicalName: string;
  category: HolidayCategory;
  consistencyLevel: HolidayConsistencyLevel;
  dateType: DateType;
  startDate: string;       // yyyy-MM-dd
  endDate: string;         // yyyy-MM-dd (same as startDate for single-day holidays)
  priority: number;
  primaryVerseReference: string;
  scriptures: string[];
  theme: string;
  shortBannerTitle: string;
  shortBannerMessage: string;
  expandedReflection: string;
  callToActionLabel: string;
  callToActionRoute: string;
  visualTreatment: string;
  allowedTone: string;
  prohibitedTone: string;
  safetyNotes: string;
  createdAt: admin.firestore.Timestamp;
  updatedAt: admin.firestore.Timestamp;
  sourceVersion: string;
}

const SOURCE_VERSION = "1.0.0";

// ─── Easter Computation (Anonymous Gregorian / Computus) ─────────────────────

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
  const month = Math.floor((h + l - 7 * m + 114) / 31); // 1-based
  const day = ((h + l - 7 * m + 114) % 31) + 1;
  return utcDate(year, month, day);
}

// ─── Hebrew Calendar Lookup (2024–2033) ──────────────────────────────────────

// Authoritative dates from hebcal.com. Gauss algorithm used outside this range.
const passoverLookup: Record<number, [number, number]> = {
  2024: [4, 22], 2025: [4, 12], 2026: [4, 1],  2027: [4, 20],
  2028: [4, 9],  2029: [3, 29], 2030: [4, 17], 2031: [4, 6],
  2032: [4, 23], 2033: [4, 12],
};

const roshHashanahLookup: Record<number, [number, number]> = {
  2024: [10, 2], 2025: [9, 22], 2026: [9, 11], 2027: [9, 30],
  2028: [9, 19], 2029: [9, 9],  2030: [9, 27], 2031: [9, 17],
  2032: [9, 5],  2033: [9, 24],
};

function passoverDate(year: number): Date {
  if (passoverLookup[year]) {
    const [m, d] = passoverLookup[year];
    return utcDate(year, m, d);
  }
  // Gauss algorithm fallback
  const hebrewYear = year + 3760;
  const a = hebrewYear % 19;
  const b = hebrewYear % 4;
  const q = -0.5 - 0.025 * a + 0.3765 * Math.floor(7 * a / 19) + b * 0.75;
  const passoverJulian = Math.floor(q) + 1;
  const marchBase = utcDate(year, 3, 1);
  marchBase.setUTCDate(marchBase.getUTCDate() + passoverJulian + 21);
  return marchBase;
}

function roshHashanahDate(year: number): Date {
  if (roshHashanahLookup[year]) {
    const [m, d] = roshHashanahLookup[year];
    return utcDate(year, m, d);
  }
  // Approximate fallback: Rosh Hashanah is ~163 days after Passover
  const p = passoverDate(year);
  const rosh = new Date(p);
  rosh.setUTCDate(rosh.getUTCDate() + 163);
  return rosh;
}

// ─── Floating Holiday Helpers ─────────────────────────────────────────────────

/** Returns the nth occurrence of `weekday` (0=Sun) in `month` (1-based) of `year`. */
function nthWeekday(weekday: number, ordinal: number, month: number, year: number): Date {
  const first = utcDate(year, month, 1);
  const firstDay = first.getUTCDay();
  let dayOffset = (weekday - firstDay + 7) % 7;
  dayOffset += (ordinal - 1) * 7;
  first.setUTCDate(1 + dayOffset);
  return first;
}

/** Returns the last occurrence of `weekday` in `month`. */
function lastWeekday(weekday: number, month: number, year: number): Date {
  const lastDay = new Date(Date.UTC(year, month, 0)); // last day of month
  const offset = (lastDay.getUTCDay() - weekday + 7) % 7;
  lastDay.setUTCDate(lastDay.getUTCDate() - offset);
  return lastDay;
}

function utcDate(year: number, month: number, day: number): Date {
  return new Date(Date.UTC(year, month - 1, day));
}

function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

// ─── Holiday Catalog ──────────────────────────────────────────────────────────

interface HolidaySpec {
  id: string;
  canonicalName: string;
  category: HolidayCategory;
  consistencyLevel: HolidayConsistencyLevel;
  dateType: DateType;
  priority: number;
  primaryVerseReference: string;
  scriptures: string[];
  theme: string;
  shortBannerTitle: string;
  shortBannerMessage: string;
  expandedReflection: string;
  callToActionLabel: string;
  callToActionRoute: string;
  visualTreatment: string;
  allowedTone: string;
  prohibitedTone: string;
  safetyNotes: string;
  durationDays: number;
  getDate: (year: number) => Date;
}

function buildCatalog(): HolidaySpec[] {
  return [
    // ── Major Christian Events ────────────────────────────────────────────────
    {
      id: "easter",
      canonicalName: "Easter Sunday",
      category: "christian_event",
      consistencyLevel: "strong",
      dateType: "easter_relative",
      priority: 10,
      primaryVerseReference: "Matthew 28:6",
      scriptures: ["1 Corinthians 15:20", "Romans 6:4", "John 11:25"],
      theme: "resurrection, new life, hope",
      shortBannerTitle: "He Is Risen",
      shortBannerMessage: "Death could not hold Him. He is risen, just as He said.",
      expandedReflection: "Easter is the cornerstone of the Christian faith — the moment history turned. The empty tomb is not a symbol; it is a historical event that changes everything. Because Jesus rose, we have hope that transcends every grief, every loss, every fear. Today, let the resurrection be not just a doctrine but a daily reality.",
      callToActionLabel: "Explore the Resurrection",
      callToActionRoute: "amen://study/easter",
      visualTreatment: "sunrise_gold",
      allowedTone: "triumphant, joyful, reverent",
      prohibitedTone: "casual, irreverent",
      safetyNotes: "Emphasize historical resurrection, not mythological rebirth imagery.",
      durationDays: 1,
      getDate: (y) => computeEaster(y),
    },
    {
      id: "good_friday",
      canonicalName: "Good Friday",
      category: "christian_event",
      consistencyLevel: "strong",
      dateType: "easter_relative",
      priority: 9,
      primaryVerseReference: "Isaiah 53:5",
      scriptures: ["John 19:30", "Romans 5:8", "1 Peter 2:24"],
      theme: "atonement, sacrifice, love",
      shortBannerTitle: "The Cross",
      shortBannerMessage: "It was for our transgressions. Every wound, every word — all for us.",
      expandedReflection: "Good Friday names something that seems a contradiction: the day that held the greatest evil was the source of our greatest good. The cross is where justice and mercy met, where God absorbed the cost of our rebellion. Sit with the weight of it today.",
      callToActionLabel: "Reflect on the Cross",
      callToActionRoute: "amen://study/good_friday",
      visualTreatment: "solemn_dark",
      allowedTone: "solemn, reverent, grateful",
      prohibitedTone: "triumphant, cheerful, casual",
      safetyNotes: "Quiet, reflective framing only. Avoid anything celebratory.",
      durationDays: 1,
      getDate: (y) => addDays(computeEaster(y), -2),
    },
    {
      id: "christmas",
      canonicalName: "Christmas Day",
      category: "christian_event",
      consistencyLevel: "strong",
      dateType: "fixed",
      priority: 9,
      primaryVerseReference: "John 1:14",
      scriptures: ["Luke 2:11", "Isaiah 9:6", "Matthew 1:23"],
      theme: "incarnation, Emmanuel, gift",
      shortBannerTitle: "The Word Became Flesh",
      shortBannerMessage: "God entered our story. Not from a distance — but in flesh, in a manger, among us.",
      expandedReflection: "Christmas is not primarily about gifts or warmth, though those are good. It is about the astonishing fact that the Creator chose to become a creature. The Infinite entered the finite. Emmanuel — God with us — is the most important announcement in human history.",
      callToActionLabel: "Celebrate the Incarnation",
      callToActionRoute: "amen://study/christmas",
      visualTreatment: "warm_gold",
      allowedTone: "joyful, reverent, wonder-filled",
      prohibitedTone: "materialistic, Santa-focused, secular",
      safetyNotes: "Center on the incarnation. Avoid reducing Christmas to gift-giving culture.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 12, 25),
    },
    {
      id: "christmas_eve",
      canonicalName: "Christmas Eve",
      category: "christian_event",
      consistencyLevel: "strong",
      dateType: "fixed",
      priority: 8,
      primaryVerseReference: "Luke 2:10–11",
      scriptures: ["Micah 5:2", "Matthew 2:1", "Isaiah 7:14"],
      theme: "anticipation, waiting, wonder",
      shortBannerTitle: "The Night Before",
      shortBannerMessage: "Tonight, the long waiting ends. The promised One is almost here.",
      expandedReflection: "Christmas Eve holds a kind of holy anticipation — the world on the edge of something it has been waiting thousands of years for. Let this evening be a chance to lean into wonder, to sit in the darkness that is about to be filled with light.",
      callToActionLabel: "Prepare Your Heart",
      callToActionRoute: "amen://study/christmas_eve",
      visualTreatment: "candlelight",
      allowedTone: "anticipatory, tender, quiet wonder",
      prohibitedTone: "anxious, hurried, commercial",
      safetyNotes: "Focus on spiritual preparation, not busyness.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 12, 24),
    },
    {
      id: "palm_sunday",
      canonicalName: "Palm Sunday",
      category: "christian_event",
      consistencyLevel: "strong",
      dateType: "easter_relative",
      priority: 7,
      primaryVerseReference: "Matthew 21:9",
      scriptures: ["Zechariah 9:9", "John 12:13", "Psalm 118:26"],
      theme: "kingship, humility, triumphal entry",
      shortBannerTitle: "Hosanna",
      shortBannerMessage: "He came not on a war horse but a donkey — a king who came to serve.",
      expandedReflection: "Palm Sunday marks the beginning of Holy Week. The crowd expected a conquering king; they got a servant king riding on a donkey, fulfilling an ancient prophecy. The same crowd who shouted hosanna would shout crucify him within five days. Jesus knew. He came anyway.",
      callToActionLabel: "Begin Holy Week",
      callToActionRoute: "amen://study/palm_sunday",
      visualTreatment: "palm_green",
      allowedTone: "anticipatory, reflective",
      prohibitedTone: "triumphal without gravity",
      safetyNotes: "Hold joy and shadow together — the crowd's misunderstanding is part of the story.",
      durationDays: 1,
      getDate: (y) => addDays(computeEaster(y), -7),
    },
    {
      id: "ash_wednesday",
      canonicalName: "Ash Wednesday",
      category: "christian_event",
      consistencyLevel: "consistent",
      dateType: "easter_relative",
      priority: 7,
      primaryVerseReference: "Joel 2:12–13",
      scriptures: ["Genesis 3:19", "2 Corinthians 7:10", "Psalm 51:1"],
      theme: "repentance, mortality, Lenten journey",
      shortBannerTitle: "Remember You Are Dust",
      shortBannerMessage: "Ashes mark the beginning of the Lenten journey — turning back to the One who redeems.",
      expandedReflection: "Ash Wednesday confronts us with our mortality. 'From dust you came, to dust you shall return.' It is not morbid — it is clarifying. When we know our days are numbered, we stop wasting them on the wrong things. Lent is not about guilt. It is about returning.",
      callToActionLabel: "Start Your Lenten Journey",
      callToActionRoute: "amen://study/ash_wednesday",
      visualTreatment: "solemn_ash",
      allowedTone: "sober, reflective, hopeful-repentance",
      prohibitedTone: "cheerful, celebratory",
      safetyNotes: "Lent is observed across many traditions. Avoid implying any one tradition is the only correct approach.",
      durationDays: 1,
      getDate: (y) => addDays(computeEaster(y), -46),
    },
    {
      id: "pentecost",
      canonicalName: "Pentecost",
      category: "christian_event",
      consistencyLevel: "strong",
      dateType: "easter_relative",
      priority: 8,
      primaryVerseReference: "Acts 2:1–4",
      scriptures: ["John 14:26", "Galatians 5:22–23", "Joel 2:28"],
      theme: "Holy Spirit, empowerment, the Church's birthday",
      shortBannerTitle: "The Spirit Is Here",
      shortBannerMessage: "Fifty days after the resurrection, the Spirit came. He has not left.",
      expandedReflection: "Pentecost is when the scattered disciples became the Church. The Spirit did not descend to make religion more intense — He came to make God's presence personally available to every believer. The wind and fire of Acts 2 are a permanent reality, not a one-time event.",
      callToActionLabel: "Learn About the Spirit",
      callToActionRoute: "amen://study/pentecost",
      visualTreatment: "flame_red",
      allowedTone: "empowering, joyful, reverent",
      prohibitedTone: "sensational, divisive",
      safetyNotes: "Pentecost is celebrated across many traditions. Present the Spirit as a gift to the whole Church.",
      durationDays: 1,
      getDate: (y) => addDays(computeEaster(y), 49),
    },
    {
      id: "ascension",
      canonicalName: "Ascension Day",
      category: "christian_event",
      consistencyLevel: "consistent",
      dateType: "easter_relative",
      priority: 6,
      primaryVerseReference: "Acts 1:9–11",
      scriptures: ["Ephesians 4:10", "Hebrews 4:14", "John 14:2"],
      theme: "ascension, intercession, reign of Christ",
      shortBannerTitle: "He Ascended in Glory",
      shortBannerMessage: "Forty days after Easter, Jesus ascended to the right hand of the Father — still interceding for us.",
      expandedReflection: "Ascension Day is often overlooked, but it is doctrinally vital. Jesus did not disappear — He ascended to a position of authority and intercession. Right now He sits at the right hand of the Father, advocating for you by name. The ascension is the guarantee of Pentecost.",
      callToActionLabel: "Explore Christ's Ascension",
      callToActionRoute: "amen://study/ascension",
      visualTreatment: "sky_blue",
      allowedTone: "reverent, majestic",
      prohibitedTone: "casual",
      safetyNotes: "Emphasize ongoing intercession, not absence.",
      durationDays: 1,
      getDate: (y) => addDays(computeEaster(y), 39),
    },

    // ── Biblical Feasts ───────────────────────────────────────────────────────
    {
      id: "passover",
      canonicalName: "Passover (Pesach)",
      category: "biblical_feast",
      consistencyLevel: "strong",
      dateType: "hebrew_calendar",
      priority: 8,
      primaryVerseReference: "Exodus 12:13",
      scriptures: ["1 Corinthians 5:7", "John 1:29", "Hebrews 9:22"],
      theme: "redemption, deliverance, the Lamb",
      shortBannerTitle: "Passover",
      shortBannerMessage: "The blood on the doorposts pointed to the Lamb who would come. He has come.",
      expandedReflection: "Passover is the central act of Old Testament redemption — God delivering His people from slavery through the blood of a lamb. For Christians, Passover is fulfilled in Jesus. Paul writes: 'Christ, our Passover Lamb, has been sacrificed.' The seder table is not behind us; it leads us forward to the Supper of the Lamb.",
      callToActionLabel: "Understand the Passover",
      callToActionRoute: "amen://study/passover",
      visualTreatment: "exodus_sand",
      allowedTone: "reverent, historically rich, Christocentric",
      prohibitedTone: "supersessionist, dismissive of Jewish tradition",
      safetyNotes: "Honor Jewish tradition. Present Christian fulfillment as completion, not replacement.",
      durationDays: 7,
      getDate: (y) => passoverDate(y),
    },
    {
      id: "feast_of_trumpets",
      canonicalName: "Feast of Trumpets (Rosh Hashanah)",
      category: "biblical_feast",
      consistencyLevel: "consistent",
      dateType: "hebrew_calendar",
      priority: 7,
      primaryVerseReference: "Leviticus 23:24",
      scriptures: ["1 Thessalonians 4:16", "Numbers 29:1", "Revelation 8:2"],
      theme: "awakening, call to repentance, anticipation",
      shortBannerTitle: "The Trumpet Sounds",
      shortBannerMessage: "Rosh Hashanah calls us to awaken — to examine ourselves and turn back to God.",
      expandedReflection: "The shofar blast of Rosh Hashanah is a call to attention. In Scripture, the trumpet signals a divine summons — to repentance, to battle, to celebration, to assembly. Christians connect its eschatological echo to the last trumpet of 1 Thessalonians. Today, let the blast awaken your spirit.",
      callToActionLabel: "Hear the Trumpet's Call",
      callToActionRoute: "amen://study/feast_of_trumpets",
      visualTreatment: "shofar_gold",
      allowedTone: "awakening, reflective, expectant",
      prohibitedTone: "dismissive of Jewish roots",
      safetyNotes: "Honor the feast's Jewish context. Christian typology is a connection, not a correction.",
      durationDays: 2,
      getDate: (y) => roshHashanahDate(y),
    },
    {
      id: "day_of_atonement",
      canonicalName: "Day of Atonement (Yom Kippur)",
      category: "biblical_feast",
      consistencyLevel: "strong",
      dateType: "hebrew_calendar",
      priority: 7,
      primaryVerseReference: "Leviticus 16:30",
      scriptures: ["Hebrews 9:11–12", "Romans 3:25", "Isaiah 53:6"],
      theme: "atonement, cleansing, high priest",
      shortBannerTitle: "Covered and Cleansed",
      shortBannerMessage: "Yom Kippur is the day the high priest entered the Holy of Holies. Jesus entered once for all.",
      expandedReflection: "The Day of Atonement was the most solemn day on Israel's calendar. The high priest — and only the high priest — could enter the Most Holy Place, once per year, with blood. The book of Hebrews announces that Jesus has done what all those sacrifices could only symbolize. He entered by His own blood and obtained eternal redemption.",
      callToActionLabel: "Explore Our High Priest",
      callToActionRoute: "amen://study/yom_kippur",
      visualTreatment: "solemn_white",
      allowedTone: "solemn, theologically rich, hopeful",
      prohibitedTone: "casual, triumphalist",
      safetyNotes: "Treat Yom Kippur with deep reverence. Avoid reducing it to a theme for Christian content.",
      durationDays: 1,
      getDate: (y) => addDays(roshHashanahDate(y), 9),
    },
    {
      id: "feast_of_tabernacles",
      canonicalName: "Feast of Tabernacles (Sukkot)",
      category: "biblical_feast",
      consistencyLevel: "consistent",
      dateType: "hebrew_calendar",
      priority: 6,
      primaryVerseReference: "Leviticus 23:42–43",
      scriptures: ["John 1:14", "Zechariah 14:16", "Revelation 21:3"],
      theme: "dwelling, presence, pilgrimage",
      shortBannerTitle: "He Tabernacled Among Us",
      shortBannerMessage: "Sukkot celebrates God dwelling with His people. John 1:14 says Jesus 'tabernacled' among us.",
      expandedReflection: "Sukkot remembers the wilderness wandering and God's provision. Families build temporary shelters to remember they were once pilgrims. John 1:14 uses this word: the Word 'tabernacled' among us. God's ultimate dwelling with His people awaits (Revelation 21:3), but He is not distant now.",
      callToActionLabel: "Discover Sukkot",
      callToActionRoute: "amen://study/sukkot",
      visualTreatment: "harvest_amber",
      allowedTone: "joyful, pilgrimage-oriented, eschatological",
      prohibitedTone: "",
      safetyNotes: "One of the most joyful feasts. Connect to both wilderness provision and incarnation.",
      durationDays: 7,
      getDate: (y) => addDays(roshHashanahDate(y), 14),
    },
    {
      id: "feast_of_weeks",
      canonicalName: "Feast of Weeks (Shavuot)",
      category: "biblical_feast",
      consistencyLevel: "consistent",
      dateType: "easter_relative",
      priority: 7,
      primaryVerseReference: "Leviticus 23:16",
      scriptures: ["Acts 2:1", "Exodus 19:1", "Ruth 2:23"],
      theme: "harvest, Torah, Pentecost",
      shortBannerTitle: "First Fruits of the Harvest",
      shortBannerMessage: "Fifty days of counting — and then the harvest, the Law, and the Spirit.",
      expandedReflection: "Shavuot celebrates the grain harvest and the giving of the Torah at Sinai. Fifty days after Passover, Israel received the Law that would shape a nation. Fifty days after Christ's resurrection, the Spirit came at Pentecost — writing that law on hearts instead of stone. The harvest is spiritual now.",
      callToActionLabel: "Explore Shavuot/Pentecost",
      callToActionRoute: "amen://study/feast_of_weeks",
      visualTreatment: "wheat_gold",
      allowedTone: "joyful, harvest-rich",
      prohibitedTone: "",
      safetyNotes: "Same day as Christian Pentecost in most years. Present the connection.",
      durationDays: 2,
      getDate: (y) => addDays(passoverDate(y), 49),
    },
    {
      id: "firstfruits",
      canonicalName: "Feast of Firstfruits",
      category: "biblical_feast",
      consistencyLevel: "consistent",
      dateType: "easter_relative",
      priority: 6,
      primaryVerseReference: "1 Corinthians 15:20",
      scriptures: ["Leviticus 23:10", "Romans 8:23", "James 1:18"],
      theme: "firstfruits, resurrection, pledge",
      shortBannerTitle: "Firstfruits of the Resurrection",
      shortBannerMessage: "Jesus rose on the feast of Firstfruits — the first of a great harvest yet to come.",
      expandedReflection: "Firstfruits was the first sheaf of the barley harvest, offered to God as a pledge that the rest of the harvest was coming. Paul deliberately names Jesus 'the firstfruits of those who have fallen asleep.' The resurrection is not an isolated miracle — it is a down payment on a harvest of resurrection that you are part of.",
      callToActionLabel: "Study the Firstfruits",
      callToActionRoute: "amen://study/firstfruits",
      visualTreatment: "spring_green",
      allowedTone: "joyful, hopeful, typological",
      prohibitedTone: "",
      safetyNotes: "Connect to resurrection hope.",
      durationDays: 1,
      getDate: (y) => {
        // First Sunday after Passover
        const p = passoverDate(y);
        const dow = p.getUTCDay(); // 0=Sun
        const daysToSunday = dow === 0 ? 7 : (7 - dow);
        return addDays(p, daysToSunday);
      },
    },

    // ── Biblically Consistent Civic ───────────────────────────────────────────
    {
      id: "thanksgiving",
      canonicalName: "Thanksgiving",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "floating",
      priority: 5,
      primaryVerseReference: "Psalm 100:4",
      scriptures: ["1 Thessalonians 5:18", "Colossians 3:17", "Philippians 4:6"],
      theme: "gratitude, provision, contentment",
      shortBannerTitle: "Enter His Courts with Thanks",
      shortBannerMessage: "Gratitude is not a feeling — it is a practice that reshapes how we see everything.",
      expandedReflection: "Biblical thanksgiving is not sentiment about abundance. Paul wrote 'give thanks in all circumstances' from prison. Gratitude is an act of trust — a declaration that God's goodness is not contingent on our circumstances. Let the table today point you past the meal to the Giver.",
      callToActionLabel: "Practice Gratitude",
      callToActionRoute: "amen://study/thanksgiving",
      visualTreatment: "harvest_warm",
      allowedTone: "warm, grateful, reflective",
      prohibitedTone: "prosperity-gospel, nationalistic, purely cultural",
      safetyNotes: "Focus on biblical thankfulness. Avoid nationalist or consumerist framing.",
      durationDays: 1,
      getDate: (y) => nthWeekday(4, 4, 11, y), // 4th Thursday, November
    },
    {
      id: "mothers_day",
      canonicalName: "Mother's Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "floating",
      priority: 4,
      primaryVerseReference: "Proverbs 31:25",
      scriptures: ["Luke 1:46–47", "2 Timothy 1:5", "Proverbs 31:28"],
      theme: "motherhood, honor, nurturing faith",
      shortBannerTitle: "Honor Her",
      shortBannerMessage: "The Bible has much to say about the strength and faith of mothers.",
      expandedReflection: "Scripture honors mothers from Eve to Mary, from Jochebed to Lois. Motherhood in the Bible is not sentimentalized — it is portrayed as a real, costly, courageous act of love. Whether you have a mother nearby or at a distance, living or gone — today is a chance to honor the gift of that love.",
      callToActionLabel: "Celebrate God's Gift",
      callToActionRoute: "amen://study/mothers_day",
      visualTreatment: "soft_floral",
      allowedTone: "warm, honoring, sensitive",
      prohibitedTone: "excluding (acknowledge loss/estrangement), sentimental only",
      safetyNotes: "Be sensitive to those who have lost mothers, are estranged, or are struggling with infertility.",
      durationDays: 1,
      getDate: (y) => nthWeekday(0, 2, 5, y), // 2nd Sunday, May
    },
    {
      id: "fathers_day",
      canonicalName: "Father's Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "floating",
      priority: 4,
      primaryVerseReference: "Ephesians 6:4",
      scriptures: ["Psalm 103:13", "Proverbs 3:11–12", "Luke 15:20"],
      theme: "fatherhood, discipleship, God's fatherhood",
      shortBannerTitle: "The Father's Heart",
      shortBannerMessage: "Human fatherhood at its best reflects the heart of our heavenly Father.",
      expandedReflection: "The parable of the prodigal son is ultimately about a father — one who sees his child 'while he was still a long way off' and runs. Human fathers are given the high calling of imaging God's fatherhood: present, patient, disciplining in love. Today, honor the fathers in your life, and turn to the Father who never leaves.",
      callToActionLabel: "Reflect on Fatherhood",
      callToActionRoute: "amen://study/fathers_day",
      visualTreatment: "warm_earth",
      allowedTone: "warm, encouraging, honest about imperfect fathers",
      prohibitedTone: "excluding those with difficult father relationships",
      safetyNotes: "Be sensitive to those with absent, abusive, or deceased fathers.",
      durationDays: 1,
      getDate: (y) => nthWeekday(0, 3, 6, y), // 3rd Sunday, June
    },
    {
      id: "memorial_day",
      canonicalName: "Memorial Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "floating",
      priority: 3,
      primaryVerseReference: "John 15:13",
      scriptures: ["2 Samuel 1:23", "Isaiah 40:31", "Lamentations 3:22"],
      theme: "sacrifice, remembrance, courage",
      shortBannerTitle: "Greater Love",
      shortBannerMessage: "No greater love than to lay down one's life. We remember those who did.",
      expandedReflection: "Memorial Day honors those who gave their lives in military service. While ultimate sacrifice belongs to Christ, there is something right about honoring human courage and love for others. Scripture honors valor and mourns loss. Today we can both grieve and give thanks.",
      callToActionLabel: "Remember and Reflect",
      callToActionRoute: "amen://study/memorial_day",
      visualTreatment: "flag_solemn",
      allowedTone: "solemn, honoring, patriotic without idolatry",
      prohibitedTone: "war-glorifying, nationalistic idolatry",
      safetyNotes: "Avoid equating military sacrifice with Christ's sacrifice. Present as 'echoes of,' not equal to.",
      durationDays: 1,
      getDate: (y) => lastWeekday(1, 5, y), // Last Monday, May
    },
    {
      id: "labor_day",
      canonicalName: "Labor Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "floating",
      priority: 3,
      primaryVerseReference: "Colossians 3:23",
      scriptures: ["Genesis 2:15", "Proverbs 14:23", "2 Thessalonians 3:10"],
      theme: "work, dignity, calling, rest",
      shortBannerTitle: "Work as Worship",
      shortBannerMessage: "Work is not a curse — it is part of the image of God in us. Rest is too.",
      expandedReflection: "Work preceded the Fall. Adam and Eve were given a garden to cultivate before sin entered the story. Labor Day is a moment to reclaim the dignity of work — not as the source of our worth, but as a meaningful way we image a creating God. And to honor the day itself: rest well.",
      callToActionLabel: "Find Your Calling",
      callToActionRoute: "amen://study/labor_day",
      visualTreatment: "earthy_craft",
      allowedTone: "dignifying, theological, practical",
      prohibitedTone: "prosperity-framing, hustle-culture endorsement",
      safetyNotes: "Avoid prosperity gospel framing. Biblical work theology includes rest and limitation.",
      durationDays: 1,
      getDate: (y) => nthWeekday(1, 1, 9, y), // 1st Monday, September
    },
    {
      id: "independence_day",
      canonicalName: "Independence Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "fixed",
      priority: 3,
      primaryVerseReference: "Galatians 5:1",
      scriptures: ["John 8:36", "Romans 13:1", "1 Peter 2:16"],
      theme: "freedom, responsibility, Christian citizenship",
      shortBannerTitle: "Free Indeed",
      shortBannerMessage: "Earthly freedom is a gift. But the freedom Christ gives is greater — and never taken away.",
      expandedReflection: "Christians can celebrate national freedom while holding it in proper perspective. The freedom the gospel proclaims goes deeper than political liberty: freedom from sin, shame, and death. Earthly freedom is worth protecting, but do not confuse it with the freedom that is eternal.",
      callToActionLabel: "Explore True Freedom",
      callToActionRoute: "amen://study/independence_day",
      visualTreatment: "liberty_blue",
      allowedTone: "grateful, theologically grounded",
      prohibitedTone: "nationalistic idolatry, Christian nationalism framing",
      safetyNotes: "US-specific. Avoid equating American exceptionalism with God's favor.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 7, 4),
    },
    {
      id: "veterans_day",
      canonicalName: "Veterans Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "fixed",
      priority: 3,
      primaryVerseReference: "Isaiah 6:8",
      scriptures: ["Romans 13:4", "John 15:13", "Micah 4:3"],
      theme: "service, courage, peace",
      shortBannerTitle: "Those Who Served",
      shortBannerMessage: "Today we honor those who answered the call to serve. May we seek the peace they helped protect.",
      expandedReflection: "Veterans Day honors those who served, not those who died in battle (that is Memorial Day). Their service deserves gratitude. It also invites us to pray for the peace that surpasses all understanding — both for individuals who carry the weight of service, and for the world they protected.",
      callToActionLabel: "Honor and Pray",
      callToActionRoute: "amen://study/veterans_day",
      visualTreatment: "service_honor",
      allowedTone: "honoring, prayerful",
      prohibitedTone: "war-glorifying",
      safetyNotes: "Be sensitive to veterans with PTSD and trauma. Frame with care.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 11, 11),
    },
    {
      id: "new_years",
      canonicalName: "New Year's Day",
      category: "biblically_consistent",
      consistencyLevel: "consistent",
      dateType: "fixed",
      priority: 3,
      primaryVerseReference: "Lamentations 3:22–23",
      scriptures: ["Isaiah 43:19", "Philippians 3:13–14", "Psalm 90:12"],
      theme: "new beginnings, God's faithfulness, hope",
      shortBannerTitle: "New Mercies Every Morning",
      shortBannerMessage: "His mercies are new every morning — and that includes the first morning of a new year.",
      expandedReflection: "The calendar turning is a human invention, but renewal is a divine reality. Lamentations was written in the ashes of Jerusalem's fall, yet it holds: 'His compassions never fail. They are new every morning.' New Year's is not about resolutions. It is about remembering whose faithfulness carries us forward.",
      callToActionLabel: "Start the Year with Scripture",
      callToActionRoute: "amen://study/new_years",
      visualTreatment: "dawn_horizon",
      allowedTone: "hopeful, reflective, forward-looking",
      prohibitedTone: "pressure-filled, resolution-focused without grace",
      safetyNotes: "Acknowledge that new years can be hard for those who are grieving or struggling.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 1, 1),
    },

    // ── Discernment Holidays ──────────────────────────────────────────────────
    {
      id: "halloween",
      canonicalName: "Halloween",
      category: "discernment",
      consistencyLevel: "discernment",
      dateType: "fixed",
      priority: 2,
      primaryVerseReference: "Ephesians 5:11",
      scriptures: ["1 Thessalonians 5:22", "Philippians 4:8", "Romans 12:2"],
      theme: "spiritual discernment, light vs. darkness",
      shortBannerTitle: "Walk in the Light",
      shortBannerMessage: "Christians approach this season differently. Here's how to think through it.",
      expandedReflection: "Halloween is one of the most contested dates on the Christian calendar. Churches respond in many ways: some celebrate the Reformation (October 31, 1517), some hold harvest festivals, some abstain. Scripture calls us to discern all things. The key question: does your engagement today glorify God and protect your spirit?",
      callToActionLabel: "Navigate with Wisdom",
      callToActionRoute: "amen://study/halloween",
      visualTreatment: "discernment_neutral",
      allowedTone: "discerning, pastoral, non-condemning, thoughtful",
      prohibitedTone: "occult, dark, fear-based, condemning of all participation",
      safetyNotes: "NO occult, witchcraft, divination, or horror references. Reformation Day connection is appropriate. Do not shame Christians who navigate this differently.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 10, 31),
    },
    {
      id: "valentines_day",
      canonicalName: "Valentine's Day",
      category: "discernment",
      consistencyLevel: "discernment",
      dateType: "fixed",
      priority: 2,
      primaryVerseReference: "1 Corinthians 13:4–7",
      scriptures: ["Song of Solomon 2:4", "1 John 4:19", "Ephesians 5:25"],
      theme: "love, commitment, agape",
      shortBannerTitle: "Love That Goes Deeper",
      shortBannerMessage: "The world offers romance. Scripture offers something far greater.",
      expandedReflection: "Valentine's Day can be an opportunity to reflect on love — real love. Not Hallmark love, not eros alone, but the kind Paul describes in 1 Corinthians 13: patient, kind, not self-seeking. Christian love is grounded in the agape of God who loved us 'while we were still sinners.' That is the love worth celebrating.",
      callToActionLabel: "Reflect on Biblical Love",
      callToActionRoute: "amen://study/valentines_day",
      visualTreatment: "discernment_rose",
      allowedTone: "warm, theologically grounded, not romantic-only",
      prohibitedTone: "lustful, hypersexualized, hookup-culture framing",
      safetyNotes: "Avoid romantic pressure. Be sensitive to those who are single, widowed, or in difficult relationships.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 2, 14),
    },
    {
      id: "st_patricks_day",
      canonicalName: "St. Patrick's Day",
      category: "discernment",
      consistencyLevel: "discernment",
      dateType: "fixed",
      priority: 2,
      primaryVerseReference: "Acts 16:9",
      scriptures: ["Matthew 28:19–20", "Romans 1:16", "Galatians 2:20"],
      theme: "mission, courage, the real Patrick",
      shortBannerTitle: "The Real St. Patrick",
      shortBannerMessage: "The man behind the myth was a missionary, a captive, and a courageous follower of Jesus.",
      expandedReflection: "Patrick was not a lucky charm. He was a British teenager kidnapped into Irish slavery who, after his escape, felt called to return to Ireland with the Gospel. He wrote movingly of his faith in his Confessio. The shamrock legend aside, Patrick was a real missionary. His day is worth reclaiming.",
      callToActionLabel: "Discover the Real Patrick",
      callToActionRoute: "amen://study/st_patricks_day",
      visualTreatment: "discernment_green",
      allowedTone: "historically grounded, missional",
      prohibitedTone: "alcohol-focused, luck-based, Celtic pagan imagery",
      safetyNotes: "Avoid any alcohol references or leprechaun/luck imagery. Focus on the historical missionary.",
      durationDays: 1,
      getDate: (y) => utcDate(y, 3, 17),
    },
    {
      id: "mardi_gras",
      canonicalName: "Mardi Gras",
      category: "discernment",
      consistencyLevel: "discernment",
      dateType: "easter_relative",
      priority: 2,
      primaryVerseReference: "Galatians 5:16",
      scriptures: ["1 Corinthians 6:12", "Romans 6:1–2", "Titus 2:12"],
      theme: "grace, self-control, preparation",
      shortBannerTitle: "Before the Fast",
      shortBannerMessage: "Tomorrow is Ash Wednesday. Today is a chance to begin preparing, not a last chance to indulge.",
      expandedReflection: "Mardi Gras ('Fat Tuesday') originated as the final feast before the Lenten fast. Today its cultural expressions range from harmless to harmful. The Christian question is not whether you join the parade — it is whether you are actually preparing your heart for the Lenten season ahead.",
      callToActionLabel: "Prepare for Lent",
      callToActionRoute: "amen://study/mardi_gras",
      visualTreatment: "discernment_neutral",
      allowedTone: "sobering, preparatory, pastoral",
      prohibitedTone: "party-culture endorsement, excess-normalizing",
      safetyNotes: "Do not normalize alcohol, excess, or Mardi Gras debauchery. Focus on Lenten preparation.",
      durationDays: 1,
      getDate: (y) => addDays(computeEaster(y), -47),
    },
  ];
}

// ─── Calendar Generation ──────────────────────────────────────────────────────

async function generateHolidayCalendarForYear(year: number): Promise<number> {
  const catalog = buildCatalog();
  const now = admin.firestore.Timestamp.now();
  let written = 0;

  for (const spec of catalog) {
    const startDate = spec.getDate(year);
    const endDate = addDays(startDate, spec.durationDays - 1);
    const dateStr = isoDate(startDate);

    const doc: HolidayObservanceDoc = {
      id: spec.id,
      canonicalName: spec.canonicalName,
      category: spec.category,
      consistencyLevel: spec.consistencyLevel,
      dateType: spec.dateType,
      startDate: dateStr,
      endDate: isoDate(endDate),
      priority: spec.priority,
      primaryVerseReference: spec.primaryVerseReference,
      scriptures: spec.scriptures,
      theme: spec.theme,
      shortBannerTitle: spec.shortBannerTitle,
      shortBannerMessage: spec.shortBannerMessage,
      expandedReflection: spec.expandedReflection,
      callToActionLabel: spec.callToActionLabel,
      callToActionRoute: spec.callToActionRoute,
      visualTreatment: spec.visualTreatment,
      allowedTone: spec.allowedTone,
      prohibitedTone: spec.prohibitedTone,
      safetyNotes: spec.safetyNotes,
      createdAt: now,
      updatedAt: now,
      sourceVersion: SOURCE_VERSION,
    };

    await db
      .collection("holiday_calendar").doc(`${year}`)
      .collection("days").doc(dateStr)
      .collection("observances").doc(spec.id)
      .set(doc, { merge: true });

    written++;
  }

  return written;
}

// ─── Completeness Validation ──────────────────────────────────────────────────

const REQUIRED_HOLIDAY_IDS = [
  "easter", "good_friday", "christmas", "christmas_eve", "palm_sunday",
  "ash_wednesday", "pentecost", "ascension",
  "passover", "feast_of_trumpets", "day_of_atonement", "feast_of_tabernacles",
  "feast_of_weeks", "firstfruits",
  "thanksgiving", "mothers_day", "fathers_day", "memorial_day", "labor_day",
  "independence_day", "veterans_day", "new_years",
  "halloween", "valentines_day", "st_patricks_day", "mardi_gras",
];

async function validateCalendarYear(year: number): Promise<{ found: string[]; missing: string[] }> {
  const found: string[] = [];
  const missing: string[] = [];

  for (const id of REQUIRED_HOLIDAY_IDS) {
    const yearRef = db.collection("holiday_calendar").doc(`${year}`);
    const daysSnap = await yearRef.collection("days").get();
    let foundThisId = false;
    for (const dayDoc of daysSnap.docs) {
      const obsSnap = await dayDoc.ref.collection("observances").doc(id).get();
      if (obsSnap.exists) {
        foundThisId = true;
        break;
      }
    }
    if (foundThisId) found.push(id);
    else missing.push(id);
  }

  return { found, missing };
}

// ─── Exported Cloud Functions ─────────────────────────────────────────────────

/** Scheduled: runs November 1st each year to pre-generate the next year's calendar. */
export const generateNextYearHolidayCalendar = onSchedule(
  {
    schedule: "0 6 1 11 *", // 06:00 UTC on November 1
    timeZone: "UTC",
  },
  async () => {
    const nextYear = new Date().getUTCFullYear() + 1;
    logger.info(`[holidayCalendar] Generating calendar for ${nextYear}`);
    const count = await generateHolidayCalendarForYear(nextYear);
    logger.info(`[holidayCalendar] Wrote ${count} observances for ${nextYear}`);
  }
);

/** Callable: backfill a specific year. Requires admin custom claim. */
export const backfillHolidayCalendar = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (request.app === undefined) {
      throw new HttpsError("failed-precondition", "App Check required.");
    }

    // Require admin claim
    const token = request.auth?.token;
    if (!token?.admin) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const { year } = request.data as { year?: number };
    if (!year || year < 2020 || year > 2100) {
      throw new HttpsError("invalid-argument", "Provide a valid year between 2020 and 2100.");
    }

    logger.info(`[holidayCalendar] Backfilling ${year} by admin ${request.auth?.uid}`);
    const count = await generateHolidayCalendarForYear(year);
    return { success: true, year, observancesWritten: count };
  }
);

/** Callable: validates calendar completeness for a year. Requires admin custom claim. */
export const validateHolidayCalendarYear = onCall(
  { enforceAppCheck: true },
  async (request) => {
    if (request.app === undefined) {
      throw new HttpsError("failed-precondition", "App Check required.");
    }

    const token = request.auth?.token;
    if (!token?.admin) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }

    const { year } = request.data as { year?: number };
    if (!year || year < 2020 || year > 2100) {
      throw new HttpsError("invalid-argument", "Provide a valid year between 2020 and 2100.");
    }

    const result = await validateCalendarYear(year);
    logger.info(
      `[holidayCalendar] Validation for ${year}: ${result.found.length} found, ${result.missing.length} missing`,
      result.missing.length > 0 ? { missing: result.missing } : {}
    );
    return { year, ...result, complete: result.missing.length === 0 };
  }
);
