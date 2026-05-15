import type { FeedDirectionIntentType, FeedHealthState, ClassificationResult } from "./types";

const INTENSITY_WEIGHTS: Record<string, number> = { light: 0.25, medium: 0.5, strong: 0.85 };
const MAX_BOOST = 3.0;
const MAX_SUPPRESS = -3.0;

export function classifyFeedDirection(
  text: string,
  echoChamberRisk: boolean
): ClassificationResult {
  const lower = text.toLowerCase();

  let intentType: FeedDirectionIntentType = "unknown";
  let topicsIncreased: string[] = [];
  let topicsDecreased: string[] = [];
  const modesActivated: string[] = [];
  const feedHealthUpdates: Partial<FeedHealthState> = {};
  let interpretedSummary = "";
  let confidence = 0.6;

  // Worship intent
  if (/worship|praise|hymn/i.test(lower)) {
    intentType = "worship";
    topicsIncreased = ["worship", "music", "devotional"];
    interpretedSummary = "More worship content";
    confidence = 0.85;
  }

  // Bible study / Berean
  else if (/bible study|berean|scripture breakdown|deep dive|theological|theology|exegesis/i.test(lower)) {
    intentType = "bibleStudy";
    topicsIncreased = ["scripture", "theology", "bible_study", "teaching"];
    modesActivated.push("berean");
    interpretedSummary = "More scripture teaching and Bible study content";
    confidence = 0.88;
  }

  // Scripture/verse
  else if (/scripture|verse|passage|bible verse|word of god/i.test(lower)) {
    intentType = "spiritualGrowth";
    topicsIncreased = ["scripture", "devotional", "teaching"];
    interpretedSummary = "More scripture-focused content";
    confidence = 0.82;
  }

  // Reduce conflict / drama
  else if (/less (church )?drama|less conflict|less argument|less debate|reduce conflict|drama|church fight/i.test(lower)) {
    intentType = "reduceConflict";
    topicsDecreased = ["drama", "conflict", "church_controversy", "debate"];
    feedHealthUpdates.reduceOutrage = true;
    interpretedSummary = "Less conflict-heavy church content";
    confidence = 0.90;
  }

  // Reduce politics
  else if (/less politic|no politic|political|less partisan|less divisive/i.test(lower)) {
    intentType = "reducePolitics";
    topicsDecreased = ["politics", "partisan", "debate"];
    feedHealthUpdates.reduceOutrage = true;
    interpretedSummary = "Reduce political and divisive content";
    confidence = 0.88;
  }

  // Emotional regulation
  else if (/overwhelmed|anxious|anxiety|stressed|calm(er)?( feed)?|less noise|feel better|peaceful|peace/i.test(lower)) {
    intentType = "emotionalRegulation";
    topicsIncreased = ["prayer", "worship", "devotional", "calm_teaching"];
    topicsDecreased = ["conflict", "outrage", "debate"];
    feedHealthUpdates.preferCalmContent = true;
    feedHealthUpdates.reduceRapidCuts = true;
    feedHealthUpdates.reduceOutrage = true;
    interpretedSummary = "A calmer, lower-stimulation feed";
    confidence = 0.87;
  }

  // Local church
  else if (/local church|nearby church|my church|community church/i.test(lower)) {
    intentType = "localChurch";
    topicsIncreased = ["local_church", "church_community", "church_events"];
    interpretedSummary = "More local church content";
    confidence = 0.82;
  }

  // Testimonies
  else if (/testimon/i.test(lower)) {
    intentType = "increaseTopic";
    topicsIncreased = ["testimony", "stories", "faith_journey"];
    interpretedSummary = "More testimonies and faith stories";
    confidence = 0.82;
  }

  // Prayer
  else if (/more prayer|prayer content|intercessory/i.test(lower)) {
    intentType = "increaseTopic";
    topicsIncreased = ["prayer", "intercession", "devotional"];
    interpretedSummary = "More prayer content";
    confidence = 0.80;
  }

  // Sabbath / Sunday rest
  else if (/sabbath|sunday (rest|quiet|mode|calm)|lord.s day|day of rest/i.test(lower)) {
    intentType = "sabbathRest";
    topicsIncreased = ["worship", "rest", "sabbath"];
    topicsDecreased = ["debate", "conflict"];
    modesActivated.push("sundayRest");
    feedHealthUpdates.reduceOutrage = true;
    interpretedSummary = "Quieter, worship-focused Sundays";
    confidence = 0.88;
  }

  // Creator affinity
  else if (/creator|teacher|pastor|preacher|who teach/i.test(lower)) {
    intentType = "creatorAffinity";
    topicsIncreased = ["teaching_creators", "pastoral_content"];
    interpretedSummary = "More content from quality scripture teachers";
    confidence = 0.75;
  }

  // Time-based
  else if (/morning|evening|night|afternoon|at work|before bed/i.test(lower)) {
    intentType = "timeBasedPreference";
    interpretedSummary = "Time-of-day feed preference";
    confidence = 0.70;
  }

  // Generic more/less
  else if (/show me more|more of|i want more/i.test(lower)) {
    intentType = "increaseTopic";
    interpretedSummary = "Show more of a topic";
    confidence = 0.65;
  } else if (/show me less|less of|stop showing|i want less/i.test(lower)) {
    intentType = "decreaseTopic";
    interpretedSummary = "Show less of a topic";
    feedHealthUpdates.reduceOutrage = topicsDecreased.some((t) => ["conflict","debate","outrage"].includes(t));
    confidence = 0.65;
  }

  // Echo chamber protection
  if (echoChamberRisk) {
    feedHealthUpdates.preserveDiversity = true;
    topicsDecreased = topicsDecreased.filter((t) => !["all_opposing", "all_different"].includes(t));
  }

  return {
    intentType,
    confidence,
    topicsIncreased,
    topicsDecreased,
    modesActivated,
    feedHealthUpdates,
    interpretedSummary,
    echoChamberRisk,
  };
}

export function computeIntensityWeight(intensity: string): number {
  return INTENSITY_WEIGHTS[intensity] ?? 0.5;
}

export function computeExpiresAt(
  duration: string,
  localHour: number,
  timezone: string
): Date | null {
  const now = new Date();
  switch (duration) {
    case "session":
    case "now":
      return new Date(now.getTime() + 2 * 60 * 60 * 1000);
    case "today": {
      const end = new Date(now);
      end.setHours(23, 59, 59, 999);
      return end;
    }
    case "week":
      return new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    case "always":
      return null;
    default:
      return new Date(now.getTime() + 24 * 60 * 60 * 1000);
  }
}

export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export { MAX_BOOST, MAX_SUPPRESS };
