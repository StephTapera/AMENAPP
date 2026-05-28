/**
 * spiritualRhythm.ts
 *
 * Spiritual Rhythm OS — streak tracking, verse candidates, and spiritual digests.
 *
 * Functions exported:
 *   recordSpiritualActivity   — record a daily spiritual activity and update streak
 *   recoverStreak             — apply a grace-period recovery to an at-risk streak
 *   generateDailyVerseCandidate — deterministic verse selection (no AI; Phase 3 adds AI)
 *   generateSpiritualDigest   — compose a morning or evening text digest
 *
 * Internal helpers (not exported as callables):
 *   calculateStreakState       — pure streak-state resolver
 *
 * Language rules:
 *   - Never use phrases like "streak broken", "missed", "failed", or "lost"
 *   - Recovery language: "grace period", "continuing your rhythm"
 *   - Digest language: gentle, non-pressuring, encouraging
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const REGION = "us-central1";

// ─── Types ────────────────────────────────────────────────────────────────────

type StreakType = "scripture" | "prayer" | "community" | "reading";
type StreakState = "active" | "recovering" | "paused";
type DigestType = "morning" | "evening";

interface SpiritualStreak {
  streakType: StreakType;
  currentCount: number;
  longestCount: number;
  state: StreakState;
  lastActivityDate: string; // ISO date string YYYY-MM-DD
  gracePeriodsUsed: number;
  gracePeriodsAllowed: number;
  recoveredAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  startedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  updatedAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

interface VerseCandidate {
  reference: string;
  text: string;
  theme: VerseTheme;
  translation: string;
}

type VerseTheme =
  | "peace"
  | "strength"
  | "gratitude"
  | "hope"
  | "community"
  | "wisdom"
  | "rest"
  | "faith";

// ─── Input Interfaces ─────────────────────────────────────────────────────────

interface RecordActivityInput {
  streakType: StreakType;
  activityDate?: string; // YYYY-MM-DD; defaults to today (UTC)
}

interface RecoverStreakInput {
  streakType: StreakType;
}

interface GenerateVerseInput {
  themes?: VerseTheme[];
  preferredTranslation?: string;
}

interface GenerateDigestInput {
  digestType: DigestType;
}

// ─── Verse Corpus (30 verses, 8 themes, deterministic — no AI) ───────────────

const VERSE_CORPUS: VerseCandidate[] = [
  // Peace (4)
  {
    reference: "Philippians 4:7",
    text: "And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.",
    theme: "peace",
    translation: "NIV",
  },
  {
    reference: "John 14:27",
    text: "Peace I leave with you; my peace I give you. I do not give to you as the world gives. Do not let your hearts be troubled and do not be afraid.",
    theme: "peace",
    translation: "NIV",
  },
  {
    reference: "Isaiah 26:3",
    text: "You will keep in perfect peace those whose minds are steadfast, because they trust in you.",
    theme: "peace",
    translation: "NIV",
  },
  {
    reference: "Romans 15:13",
    text: "May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.",
    theme: "peace",
    translation: "NIV",
  },
  // Strength (4)
  {
    reference: "Philippians 4:13",
    text: "I can do all this through him who gives me strength.",
    theme: "strength",
    translation: "NIV",
  },
  {
    reference: "Isaiah 40:31",
    text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.",
    theme: "strength",
    translation: "NIV",
  },
  {
    reference: "Psalm 28:7",
    text: "The Lord is my strength and my shield; my heart trusts in him, and he helps me.",
    theme: "strength",
    translation: "NIV",
  },
  {
    reference: "2 Corinthians 12:9",
    text: "But he said to me, 'My grace is sufficient for you, for my power is made perfect in weakness.'",
    theme: "strength",
    translation: "NIV",
  },
  // Gratitude (3)
  {
    reference: "1 Thessalonians 5:18",
    text: "Give thanks in all circumstances; for this is God's will for you in Christ Jesus.",
    theme: "gratitude",
    translation: "NIV",
  },
  {
    reference: "Psalm 107:1",
    text: "Give thanks to the Lord, for he is good; his love endures forever.",
    theme: "gratitude",
    translation: "NIV",
  },
  {
    reference: "Colossians 3:17",
    text: "And whatever you do, whether in word or deed, do it all in the name of the Lord Jesus, giving thanks to God the Father through him.",
    theme: "gratitude",
    translation: "NIV",
  },
  // Hope (4)
  {
    reference: "Jeremiah 29:11",
    text: "For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.",
    theme: "hope",
    translation: "NIV",
  },
  {
    reference: "Romans 8:28",
    text: "And we know that in all things God works for the good of those who love him, who have been called according to his purpose.",
    theme: "hope",
    translation: "NIV",
  },
  {
    reference: "Lamentations 3:22-23",
    text: "Because of the Lord's great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness.",
    theme: "hope",
    translation: "NIV",
  },
  {
    reference: "Psalm 39:7",
    text: "But now, Lord, what do I look for? My hope is in you.",
    theme: "hope",
    translation: "NIV",
  },
  // Community (3)
  {
    reference: "Hebrews 10:24-25",
    text: "And let us consider how we may spur one another on toward love and good deeds, not giving up meeting together, as some are in the habit of doing, but encouraging one another.",
    theme: "community",
    translation: "NIV",
  },
  {
    reference: "Galatians 6:2",
    text: "Carry each other's burdens, and in this way you will fulfill the law of Christ.",
    theme: "community",
    translation: "NIV",
  },
  {
    reference: "1 John 1:7",
    text: "But if we walk in the light, as he is in the light, we have fellowship with one another, and the blood of Jesus, his Son, purifies us from all sin.",
    theme: "community",
    translation: "NIV",
  },
  // Wisdom (4)
  {
    reference: "Proverbs 3:5-6",
    text: "Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.",
    theme: "wisdom",
    translation: "NIV",
  },
  {
    reference: "James 1:5",
    text: "If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.",
    theme: "wisdom",
    translation: "NIV",
  },
  {
    reference: "Psalm 119:105",
    text: "Your word is a lamp for my feet, a light on my path.",
    theme: "wisdom",
    translation: "NIV",
  },
  {
    reference: "Proverbs 9:10",
    text: "The fear of the Lord is the beginning of wisdom, and knowledge of the Holy One is understanding.",
    theme: "wisdom",
    translation: "NIV",
  },
  // Rest (4)
  {
    reference: "Matthew 11:28-29",
    text: "Come to me, all you who are weary and burdened, and I will give you rest. Take my yoke upon you and learn from me, for I am gentle and humble in heart, and you will find rest for your souls.",
    theme: "rest",
    translation: "NIV",
  },
  {
    reference: "Psalm 46:10",
    text: "He says, 'Be still, and know that I am God; I will be exalted among the nations, I will be exalted in the earth.'",
    theme: "rest",
    translation: "NIV",
  },
  {
    reference: "Exodus 33:14",
    text: "The Lord replied, 'My Presence will go with you, and I will give you rest.'",
    theme: "rest",
    translation: "NIV",
  },
  {
    reference: "Psalm 23:2-3",
    text: "He makes me lie down in green pastures, he leads me beside quiet waters, he refreshes my soul.",
    theme: "rest",
    translation: "NIV",
  },
  // Faith (4)
  {
    reference: "Hebrews 11:1",
    text: "Now faith is confidence in what we hope for and assurance about what we do not see.",
    theme: "faith",
    translation: "NIV",
  },
  {
    reference: "2 Corinthians 5:7",
    text: "For we live by faith, not by sight.",
    theme: "faith",
    translation: "NIV",
  },
  {
    reference: "Mark 9:23",
    text: "Everything is possible for one who believes.",
    theme: "faith",
    translation: "NIV",
  },
  {
    reference: "Romans 10:17",
    text: "Consequently, faith comes from hearing the message, and the message is heard through the word about Christ.",
    theme: "faith",
    translation: "NIV",
  },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

function requireAuth(request: { auth?: { uid: string } | null; app?: unknown }): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!request.app) {
    throw new HttpsError(
      "failed-precondition",
      "The function must be called from an App Check verified app."
    );
  }
  return request.auth.uid;
}

function utcDateString(d: Date = new Date()): string {
  return d.toISOString().split("T")[0]!;
}

function parseISODate(dateStr: string): Date {
  const [year, month, day] = dateStr.split("-").map(Number);
  return new Date(Date.UTC(year!, (month! - 1), day!));
}

function daysBetween(a: string, b: string): number {
  const msA = parseISODate(a).getTime();
  const msB = parseISODate(b).getTime();
  return Math.round(Math.abs(msB - msA) / (1000 * 60 * 60 * 24));
}

const VALID_STREAK_TYPES = new Set<StreakType>(["scripture", "prayer", "community", "reading"]);
const GRACE_PERIODS_ALLOWED = 2;

// ─── Internal: calculateStreakState ──────────────────────────────────────────
// Pure helper — not exported as a callable.

interface StreakStateResult {
  newCurrentCount: number;
  newState: StreakState;
  newGracePeriodsUsed: number;
  wasRecoveredByGrace: boolean;
  shouldReset: boolean;
}

function calculateStreakState(opts: {
  today: string;
  lastActivityDate: string;
  currentCount: number;
  gracePeriodsUsed: number;
  gracePeriodsAllowed: number;
}): StreakStateResult {
  const { today, lastActivityDate, currentCount, gracePeriodsUsed, gracePeriodsAllowed } = opts;
  const gap = daysBetween(lastActivityDate, today);

  if (gap === 0) {
    // Already recorded today — caller should no-op
    return {
      newCurrentCount: currentCount,
      newState: "active",
      newGracePeriodsUsed: gracePeriodsUsed,
      wasRecoveredByGrace: false,
      shouldReset: false,
    };
  }

  if (gap === 1) {
    // Consecutive day
    return {
      newCurrentCount: currentCount + 1,
      newState: "active",
      newGracePeriodsUsed: gracePeriodsUsed,
      wasRecoveredByGrace: false,
      shouldReset: false,
    };
  }

  if (gap === 2 && gracePeriodsUsed < gracePeriodsAllowed) {
    // One-day gap with grace available — keep the rhythm alive
    return {
      newCurrentCount: currentCount + 1,
      newState: "recovering",
      newGracePeriodsUsed: gracePeriodsUsed + 1,
      wasRecoveredByGrace: true,
      shouldReset: false,
    };
  }

  // Gap too large or grace exhausted — begin a new rhythm cycle
  return {
    newCurrentCount: 1,
    newState: "active",
    newGracePeriodsUsed: gracePeriodsUsed,
    wasRecoveredByGrace: false,
    shouldReset: true,
  };
}

// ─── Callable: recordSpiritualActivity ───────────────────────────────────────

export const recordSpiritualActivity = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ streak: SpiritualStreak; wasRecoveredByGrace: boolean }> => {
    const uid = requireAuth(request);

    const data = request.data as RecordActivityInput;
    const streakType = data?.streakType as StreakType | undefined;

    if (!streakType || !VALID_STREAK_TYPES.has(streakType)) {
      throw new HttpsError(
        "invalid-argument",
        "streakType must be one of: scripture, prayer, community, reading."
      );
    }

    const today =
      typeof data.activityDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(data.activityDate)
        ? data.activityDate
        : utcDateString();

    const streakRef = db
      .collection("users")
      .doc(uid)
      .collection("streaks")
      .doc(streakType);

    const activityRef = db
      .collection("users")
      .doc(uid)
      .collection("activity")
      .doc("main");

    const snap = await streakRef.get();

    let resultStreak: SpiritualStreak;
    let wasRecoveredByGrace = false;

    if (!snap.exists) {
      // First-ever record for this streak type
      resultStreak = {
        streakType,
        currentCount: 1,
        longestCount: 1,
        state: "active",
        lastActivityDate: today,
        gracePeriodsUsed: 0,
        gracePeriodsAllowed: GRACE_PERIODS_ALLOWED,
        startedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      await streakRef.set(resultStreak);
    } else {
      const existing = snap.data() as SpiritualStreak;
      const lastDate = existing.lastActivityDate ?? today;

      if (lastDate === today) {
        // Already recorded today — return as-is
        logger.info(
          `[spiritualRhythm] recordSpiritualActivity uid=${uid} type=${streakType} — already recorded today`
        );
        return { streak: existing, wasRecoveredByGrace: false };
      }

      const calc = calculateStreakState({
        today,
        lastActivityDate: lastDate,
        currentCount: existing.currentCount ?? 1,
        gracePeriodsUsed: existing.gracePeriodsUsed ?? 0,
        gracePeriodsAllowed: existing.gracePeriodsAllowed ?? GRACE_PERIODS_ALLOWED,
      });

      wasRecoveredByGrace = calc.wasRecoveredByGrace;
      const newLongest = Math.max(existing.longestCount ?? 1, calc.newCurrentCount);

      const updatePayload: Partial<SpiritualStreak> & Record<string, unknown> = {
        currentCount: calc.newCurrentCount,
        longestCount: newLongest,
        state: calc.newState,
        lastActivityDate: today,
        gracePeriodsUsed: calc.newGracePeriodsUsed,
        gracePeriodsAllowed: existing.gracePeriodsAllowed ?? GRACE_PERIODS_ALLOWED,
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (calc.shouldReset) {
        updatePayload["recoveredAt"] = FieldValue.serverTimestamp();
        updatePayload["startedAt"] = FieldValue.serverTimestamp();
      }

      await streakRef.set(updatePayload, { merge: true });

      resultStreak = {
        ...existing,
        ...(updatePayload as Partial<SpiritualStreak>),
        streakType,
      };
    }

    // Always touch lastActiveAt on activity
    await activityRef.set(
      { lastActiveAt: FieldValue.serverTimestamp() },
      { merge: true }
    );

    logger.info(
      `[spiritualRhythm] recordSpiritualActivity uid=${uid} type=${streakType} ` +
        `count=${resultStreak.currentCount} grace=${wasRecoveredByGrace}`
    );

    return { streak: resultStreak, wasRecoveredByGrace };
  }
);

// ─── Callable: recoverStreak ──────────────────────────────────────────────────

export const recoverStreak = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ success: true; gracePeriodsRemaining: number }> => {
    const uid = requireAuth(request);

    const data = request.data as RecoverStreakInput;
    const streakType = data?.streakType as StreakType | undefined;

    if (!streakType || !VALID_STREAK_TYPES.has(streakType)) {
      throw new HttpsError(
        "invalid-argument",
        "streakType must be one of: scripture, prayer, community, reading."
      );
    }

    const streakRef = db
      .collection("users")
      .doc(uid)
      .collection("streaks")
      .doc(streakType);

    const snap = await streakRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "No streak found for this type.");
    }

    const existing = snap.data() as SpiritualStreak;
    const used = existing.gracePeriodsUsed ?? 0;
    const allowed = existing.gracePeriodsAllowed ?? GRACE_PERIODS_ALLOWED;

    if (used >= allowed) {
      throw new HttpsError(
        "failed-precondition",
        "No grace periods remaining for this rhythm."
      );
    }

    const newUsed = used + 1;
    const remaining = allowed - newUsed;

    await streakRef.set(
      {
        gracePeriodsUsed: newUsed,
        state: "recovering" as StreakState,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info(
      `[spiritualRhythm] recoverStreak uid=${uid} type=${streakType} remaining=${remaining}`
    );

    return { success: true, gracePeriodsRemaining: remaining };
  }
);

// ─── Callable: generateDailyVerseCandidate ───────────────────────────────────
// Deterministic selection only. AI personalization is Phase 3.

export const generateDailyVerseCandidate = onCall(
  { region: REGION, enforceAppCheck: true },
  async (request): Promise<{ reference: string; text: string; theme: string; translation: string }> => {
    const uid = requireAuth(request);

    const data = request.data as GenerateVerseInput;

    // Load emotional energy filter to bias theme selection
    let emotionalEnergyFilter: string | null = null;
    try {
      const feedSnap = await db
        .collection("users")
        .doc(uid)
        .collection("feedControls")
        .doc("main")
        .get();
      if (feedSnap.exists) {
        const feedData = feedSnap.data() as Record<string, unknown>;
        emotionalEnergyFilter =
          typeof feedData["emotionalEnergyFilter"] === "string"
            ? (feedData["emotionalEnergyFilter"] as string)
            : null;
      }
    } catch {
      // Non-fatal — proceed with theme list as supplied
    }

    // Build candidate theme list — prefer calm/rest themes when filter is "calm"
    let themePool: VerseTheme[] = data.themes && data.themes.length > 0 ? data.themes : [];

    if (themePool.length === 0) {
      if (emotionalEnergyFilter === "calm") {
        themePool = ["peace", "rest", "gratitude", "hope"];
      } else if (emotionalEnergyFilter === "uplifting") {
        themePool = ["strength", "hope", "faith", "gratitude"];
      } else {
        // balanced / varied / unset — full pool
        themePool = ["peace", "strength", "gratitude", "hope", "community", "wisdom", "rest", "faith"];
      }
    }

    // Filter corpus to matching themes
    const candidates = VERSE_CORPUS.filter((v) => themePool.includes(v.theme));
    const pool = candidates.length > 0 ? candidates : VERSE_CORPUS;

    // Deterministic but varied: use day-of-year + uid hash as seed
    const dayOfYear = Math.floor(
      (Date.now() - new Date(new Date().getFullYear(), 0, 0).getTime()) / 86400000
    );
    const uidSum = uid.split("").reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
    const index = (dayOfYear + uidSum) % pool.length;
    const verse = pool[index]!;

    const translation = data.preferredTranslation ?? verse.translation;

    logger.info(`[spiritualRhythm] generateDailyVerseCandidate uid=${uid} theme=${verse.theme}`);

    return {
      reference: verse.reference,
      text: verse.text,
      theme: verse.theme,
      translation,
    };
  }
);

// ─── Callable: generateSpiritualDigest ───────────────────────────────────────

export const generateSpiritualDigest = onCall(
  { region: REGION, enforceAppCheck: true },
  async (
    request
  ): Promise<{
    digestText: string;
    verse?: { reference: string; text: string };
    streakHighlight?: string;
  }> => {
    const uid = requireAuth(request);

    const data = request.data as GenerateDigestInput;
    const digestType: DigestType = data?.digestType === "evening" ? "evening" : "morning";

    // Load all streak types in parallel
    const [scriptureSnap, prayerSnap, communitySnap, readingSnap] = await Promise.all([
      db.collection("users").doc(uid).collection("streaks").doc("scripture").get(),
      db.collection("users").doc(uid).collection("streaks").doc("prayer").get(),
      db.collection("users").doc(uid).collection("streaks").doc("community").get(),
      db.collection("users").doc(uid).collection("streaks").doc("reading").get(),
    ]);

    const toCount = (snap: admin.firestore.DocumentSnapshot): number => {
      if (!snap.exists) return 0;
      return Number((snap.data() as Record<string, unknown>)["currentCount"] ?? 0);
    };

    const streakCounts: Record<StreakType, number> = {
      scripture: toCount(scriptureSnap),
      prayer: toCount(prayerSnap),
      community: toCount(communitySnap),
      reading: toCount(readingSnap),
    };

    // Find the strongest streak for the highlight
    const topStreak = (Object.entries(streakCounts) as [StreakType, number][])
      .filter(([, c]) => c > 0)
      .sort(([, a], [, b]) => b - a)[0];

    const streakHighlight = topStreak
      ? buildStreakHighlight(topStreak[0], topStreak[1], digestType)
      : undefined;

    // Pick a verse (same deterministic logic as generateDailyVerseCandidate)
    const dayOfYear = Math.floor(
      (Date.now() - new Date(new Date().getFullYear(), 0, 0).getTime()) / 86400000
    );
    const uidSum = uid.split("").reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
    const themePool: VerseTheme[] =
      digestType === "morning"
        ? ["strength", "hope", "faith", "gratitude"]
        : ["peace", "rest", "gratitude", "wisdom"];
    const candidates = VERSE_CORPUS.filter((v) => themePool.includes(v.theme));
    const index = (dayOfYear + uidSum) % candidates.length;
    const verse = candidates[index]!;

    const digestText = buildDigestText(digestType, streakHighlight, verse);

    logger.info(`[spiritualRhythm] generateSpiritualDigest uid=${uid} type=${digestType}`);

    return {
      digestText,
      verse: { reference: verse.reference, text: verse.text },
      streakHighlight,
    };
  }
);

// ─── Digest helpers ───────────────────────────────────────────────────────────

function buildStreakHighlight(
  streakType: StreakType,
  count: number,
  digestType: DigestType
): string {
  const label: Record<StreakType, string> = {
    scripture: "scripture",
    prayer: "prayer",
    community: "community",
    reading: "reading",
  };

  if (count <= 1) {
    return digestType === "morning"
      ? `Today is a great day to begin a ${label[streakType]} rhythm.`
      : `You took a step in your ${label[streakType]} journey today.`;
  }

  return digestType === "morning"
    ? `You're on a ${count}-day ${label[streakType]} rhythm.`
    : `${count} days of ${label[streakType]} — that's something worth holding onto.`;
}

function buildDigestText(
  digestType: DigestType,
  streakHighlight: string | undefined,
  verse: VerseCandidate
): string {
  const greeting =
    digestType === "morning"
      ? "Good morning."
      : "As your day draws to a close.";

  const verseLine = `Today's verse: "${verse.text}" — ${verse.reference}`;

  if (digestType === "morning") {
    const parts = [greeting];
    if (streakHighlight) parts.push(streakHighlight);
    parts.push(verseLine);
    return parts.join(" ");
  }

  // Evening: calming and reflective
  const parts = [greeting];
  parts.push("Take a moment to breathe and reflect.");
  parts.push(verseLine);
  if (streakHighlight) parts.push(streakHighlight);
  return parts.join(" ");
}
