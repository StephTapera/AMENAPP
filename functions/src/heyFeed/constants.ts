// constants.ts — Hey Feed constants and taxonomy

export const PARSER_VERSION = 1;

export const MAX_ACTIVE_PREFERENCES_PER_USER = 30;

export const DURATION_TO_HOURS: Record<string, number | null> = {
  session:    3,
  today:      24,
  three_days: 72,
  seven_days: 168,
  persistent: null,
};

export function expiryFromDuration(duration: string): Date | null {
  const hours = DURATION_TO_HOURS[duration];
  if (hours === null || hours === undefined) return null;
  const d = new Date();
  d.setHours(d.getHours() + hours);
  return d;
}

// Taxonomy: topic IDs and their keyword synonyms
export const TOPIC_SYNONYMS: Record<string, string[]> = {
  testimonies:          ["testimon", "miracle", "story", "stories", "what god did", "answered prayer"],
  prayer_requests:      ["prayer request", "pray for", "need prayer", "intercession"],
  bible_teaching:       ["bible teaching", "biblical", "teaching", "sermon", "devotional", "scripture"],
  practical_faith:      ["practical", "how to", "apply", "daily life", "faith in action"],
  encouragement:        ["encouragement", "uplifting", "hope", "positive", "inspiring", "uplift"],
  church_discovery:     ["church", "churches", "congregation", "ministry", "local church"],
  debate:               ["debate", "argument", "controversy", "controversial", "politics", "heated"],
  promotional_content:  ["promo", "promotional", "marketing", "advertisement", "spam", "ads"],
  grief_support:        ["grief", "loss", "grieving", "sad", "mental health", "struggle", "support"],
  worship_music:        ["worship", "music", "song", "songs", "praise", "hymn"],
  theology:             ["theology", "doctrine", "deep dive", "theological", "apologetics"],
  community:            ["community", "fellowship", "connection", "people", "relationships"],
};

export const TOPIC_LABELS: Record<string, string> = {
  testimonies:          "Testimonies",
  prayer_requests:      "Prayer requests",
  bible_teaching:       "Bible teaching",
  practical_faith:      "Practical faith",
  encouragement:        "Encouragement",
  church_discovery:     "Church discovery",
  debate:               "Debates/arguments",
  promotional_content:  "Promotional content",
  grief_support:        "Grief & support",
  worship_music:        "Worship & music",
  theology:             "Theology",
  community:            "Community life",
};
