/**
 * pulse.ts — Amen Pulse server-side generation pipeline.
 *
 * Amen Pulse is a BOUNDED daily surface (NOT a feed). Once per day (and on
 * demand) the server fans out per user: disjoint, fail-soft candidate
 * collectors → Berean Daily Brief summarizer (cite-or-refuse, fail-closed) →
 * composite scoring + threshold + hard cap → safety + guilt-lint gate
 * (fail-closed) → authoritative minor/Sabbath/crisis resolution → write a
 * SINGLE document to /users/{uid}/pulse/{dateKey} with a `cards` ARRAY.
 *
 * The client reads exactly one doc and never ranks. Score is selection-only.
 *
 * Mirrors bereanPulse.ts architecture; this is a NEW standalone surface and
 * does not touch bereanPulse.ts / bereanPulseEngine.ts.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { requireAppCheck } from "./trustIntelligence";
import { callModel, moderateContent, ANTHROPIC_API_KEY } from "./intelligence/amenRouting";
import {
  PulseCard,
  PulseCandidate,
  PulseDocument,
  PulseBriefSection,
  buildSabbathStillCard,
  passesGuiltLint,
  pulseDeeplink,
  selectPulseCards,
  violatesGuiltLint,
} from "./pulseEngine";

const db = admin.firestore();
type Ts = admin.firestore.Timestamp;

// ─── Config (server-authoritative, Firestore-backed at config/pulse) ──────────

interface PulseConfig {
  "pulse.enabled": boolean;
  "pulse.maxCards": number;
  "pulse.scoreThreshold": number;
  "pulse.generationHourLocal": number;
  "whatsNew.enabled": boolean;
  // per-kind kill switches (default true = allowed)
  "pulse.kind.prayer_followup": boolean;
  "pulse.kind.occasion": boolean;
  "pulse.kind.church_event": boolean;
  "pulse.kind.space_activity": boolean;
  "pulse.kind.sermon": boolean;
  "pulse.kind.whats_new": boolean;
  "pulse.kind.daily_brief_hero": boolean;
}

const PULSE_CONFIG_DEFAULTS: PulseConfig = {
  "pulse.enabled": false,
  "pulse.maxCards": 7,
  "pulse.scoreThreshold": 0.35,
  "pulse.generationHourLocal": 5,
  "whatsNew.enabled": true,
  "pulse.kind.prayer_followup": true,
  "pulse.kind.occasion": true,
  "pulse.kind.church_event": true,
  "pulse.kind.space_activity": true,
  "pulse.kind.sermon": true,
  "pulse.kind.whats_new": true,
  "pulse.kind.daily_brief_hero": true,
};

async function loadPulseConfig(): Promise<PulseConfig> {
  try {
    const snap = await db.collection("config").doc("pulse").get();
    const data = (snap.data() ?? {}) as Partial<PulseConfig>;
    return { ...PULSE_CONFIG_DEFAULTS, ...data };
  } catch {
    return { ...PULSE_CONFIG_DEFAULTS };
  }
}

// ─── Date / refs ──────────────────────────────────────────────────────────────

function dateKeyFor(date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

function pulseDayDoc(uid: string, dateKey: string) {
  return db.collection("users").doc(uid).collection("pulse").doc(dateKey);
}

function pulseMetaDoc(uid: string) {
  return db.collection("users").doc(uid).collection("pulse").doc("_meta");
}

function tsNow(): Ts {
  return admin.firestore.Timestamp.now();
}

function tsFromMillis(ms: number): Ts {
  return admin.firestore.Timestamp.fromMillis(ms);
}

const DAY_MS = 86_400_000;

// ─── User profile: minor status (authoritative, fail-closed) ──────────────────

interface MinorResolution {
  isMinor: boolean;
  unknown: boolean;
}

/**
 * Authoritative server-side minor resolution. Mirrors the codebase's existing
 * conventions (isMinor / ageTier / dateOfBirth — see safetyOS.ts,
 * sabbath/familySabbathSync.ts). Fail-closed: if status is genuinely
 * undeterminable (user doc missing or read error), treat as minor and log.
 */
async function resolveMinor(uid: string): Promise<MinorResolution> {
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) {
      logger.warn("Pulse minor resolution: user doc missing, treating as minor", { uid });
      return { isMinor: true, unknown: true };
    }
    const data = snap.data() as {
      isMinor?: boolean;
      ageTier?: string;
      dateOfBirth?: admin.firestore.Timestamp | string | Date;
    };
    if (data.isMinor === true) return { isMinor: true, unknown: false };
    const tier = data.ageTier ?? "";
    if (tier === "minor" || tier === "teen" || tier === "under_minimum") {
      return { isMinor: true, unknown: false };
    }
    if (data.dateOfBirth) {
      let dob: Date | null = null;
      if (data.dateOfBirth instanceof admin.firestore.Timestamp) dob = data.dateOfBirth.toDate();
      else if (typeof data.dateOfBirth === "string") dob = new Date(data.dateOfBirth);
      else if (data.dateOfBirth instanceof Date) dob = data.dateOfBirth;
      if (dob && !Number.isNaN(dob.getTime())) {
        const ageYears = (Date.now() - dob.getTime()) / (DAY_MS * 365.25);
        if (ageYears < 18) return { isMinor: true, unknown: false };
      }
    }
    // We have a user doc and an explicit adult tier OR a valid adult DOB.
    if (data.isMinor === false || tier === "adult" || data.dateOfBirth) {
      return { isMinor: false, unknown: false };
    }
    // No age signal at all on an existing doc → fail-closed.
    logger.warn("Pulse minor resolution: no age signal, treating as minor", { uid });
    return { isMinor: true, unknown: true };
  } catch (error) {
    logger.error("Pulse minor resolution failed, treating as minor", { uid, error });
    return { isMinor: true, unknown: true };
  }
}

// ─── Sabbath check (reuse Sabbath Mode config) ────────────────────────────────

/**
 * Is today the user's Sabbath? Reuses the Sabbath Mode config doc
 * (users/{uid}/sabbath/config with chosenDay + timezone). Fail-soft: any error
 * or missing config → not Sabbath (Pulse generates normally).
 */
async function isUsersSabbath(uid: string): Promise<boolean> {
  try {
    const snap = await db.collection("users").doc(uid).collection("sabbath").doc("config").get();
    if (!snap.exists) return false;
    const config = snap.data() as { chosenDay?: "saturday" | "sunday"; timezone?: string };
    const tz = config.timezone || "UTC";
    const targetDay = config.chosenDay === "saturday" ? 6 : config.chosenDay === "sunday" ? 0 : -1;
    if (targetDay < 0) return false;
    const weekday = new Date(new Date().toLocaleString("en-US", { timeZone: tz })).getDay();
    return weekday === targetDay;
  } catch {
    return false;
  }
}

// ─── User prefs (style + maxCards) ────────────────────────────────────────────

interface PulsePrefs {
  enabled?: boolean;
  style?: string;
  maxCards?: number;
}

async function loadPrefs(uid: string): Promise<PulsePrefs> {
  try {
    const snap = await db.collection("users").doc(uid).collection("pulsePrefs").doc("main").get();
    return (snap.data() ?? {}) as PulsePrefs;
  } catch {
    return {};
  }
}

// ─── Crisis detection (mirror safetyOS crisis patterns) ───────────────────────

const CRISIS_PATTERNS: RegExp[] = [
  /\b(want\s+to\s+(die|kill\s+myself|end\s+it))\b/i,
  /\b(suicide|self.harm|cutting\s+myself)\b/i,
  /\b(kill\s+yourself|kys)\b/i,
];

function isCrisisText(text: string | undefined): boolean {
  if (!text) return false;
  return CRISIS_PATTERNS.some((p) => p.test(text));
}

// ─── Collectors (parallel, disjoint reads, each fail-soft → []) ───────────────

interface CollectorContext {
  uid: string;
  now: Ts;
  expiresAt: Ts;
  churchIds: string[];
  spaceIds: string[];
  interestTopics: string[];
}

function newCardId(prefix: string, suffix: string): string {
  return `${prefix}_${suffix}`.replace(/[^a-zA-Z0-9_]/g, "_").slice(0, 120);
}

/** Relationship occasions: birthdays / milestones / new baby. NEVER absence. */
async function collectOccasions(ctx: CollectorContext): Promise<PulseCandidate[]> {
  try {
    const snap = await db
      .collection("users")
      .doc(ctx.uid)
      .collection("relationshipOccasions")
      .where("occasionDate", ">=", admin.firestore.Timestamp.fromMillis(ctx.now.toMillis() - DAY_MS))
      .limit(10)
      .get();

    const candidates: PulseCandidate[] = [];
    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const personName = String(data.personName ?? "Someone you love");
      const type = String(data.type ?? "milestone"); // birthday | milestone | new_baby
      const friendId = typeof data.friendId === "string" ? data.friendId : "";

      const eyebrow =
        type === "birthday" ? "BIRTHDAY TODAY" :
        type === "new_baby" ? "NEW BABY" : "MILESTONE";
      const title =
        type === "birthday" ? `It's ${personName}'s birthday` :
        type === "new_baby" ? `${personName} welcomed a new baby` :
        `A milestone for ${personName}`;

      const sendLoveLink = pulseDeeplink("sendLove", { friendId });
      candidates.push({
        card: {
          id: newCardId("occasion", doc.id),
          kind: "occasion",
          hero: { scrim: "dark", style: "occasion" },
          eyebrow,
          title,
          subtitle: "Send a word of love today",
          action: {
            kind: "sendLove",
            label: "Send love",
            ...(friendId ? { payload: { friendId } } : {}),
            ...(sendLoveLink ? { deeplink: sendLoveLink } : {}),
          },
          minorSafe: true,
          expiresAt: ctx.expiresAt,
          provenanceLabel: "From your circle",
        },
        signal: { relationship: 0.9, spiritual: 0.2, community: 0.3, urgency: 0.6, interest: 0.5 },
      });
    }
    return candidates;
  } catch (error) {
    logger.warn("Pulse collectOccasions failed", { uid: ctx.uid, error });
    return [];
  }
}

/** Prayer follow-ups: updates on prayers the user joined. */
async function collectPrayerFollowUps(ctx: CollectorContext): Promise<PulseCandidate[]> {
  try {
    const snap = await db
      .collection("users")
      .doc(ctx.uid)
      .collection("joinedPrayers")
      .where("hasUpdate", "==", true)
      .limit(10)
      .get();

    const candidates: PulseCandidate[] = [];
    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const prayerId = typeof data.prayerId === "string" ? data.prayerId : doc.id;
      const subject = String(data.subject ?? "a prayer you joined");
      const updateText = String(data.updateText ?? "There's a new update.");

      // Crisis content bypasses Pulse entirely.
      if (isCrisisText(subject) || isCrisisText(updateText)) continue;

      candidates.push({
        card: {
          id: newCardId("prayer", doc.id),
          kind: "prayer_followup",
          hero: { scrim: "dark", style: "prayer" },
          eyebrow: "PRAYER UPDATE",
          title: subject,
          subtitle: updateText.slice(0, 140),
          action: {
            kind: "pray",
            label: "Pray now",
            payload: { prayerId },
            ...(pulseDeeplink("pray", { prayerId }) ? { deeplink: pulseDeeplink("pray", { prayerId })! } : {}),
          },
          minorSafe: true,
          expiresAt: ctx.expiresAt,
          provenanceLabel: "A prayer you joined",
        },
        signal: { relationship: 0.5, spiritual: 0.8, community: 0.5, urgency: 0.5, interest: 0.6 },
      });
    }
    return candidates;
  } catch (error) {
    logger.warn("Pulse collectPrayerFollowUps failed", { uid: ctx.uid, error });
    return [];
  }
}

/** Church events published by the user's church (and sermons). */
async function collectChurchEvents(ctx: CollectorContext): Promise<PulseCandidate[]> {
  if (ctx.churchIds.length === 0) return [];
  try {
    const candidates: PulseCandidate[] = [];
    // Firestore "in" supports up to 10 values.
    const churchIds = ctx.churchIds.slice(0, 10);
    const snap = await db
      .collection("churchEvents")
      .where("churchId", "in", churchIds)
      .where("startsAt", ">=", ctx.now)
      .where("startsAt", "<=", tsFromMillis(ctx.now.toMillis() + 7 * DAY_MS))
      .limit(12)
      .get();

    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const isSermon = data.type === "sermon";
      const title = String(data.title ?? (isSermon ? "New sermon" : "Church event"));
      const startsAt = data.startsAt as Ts | undefined;
      const locationName = typeof data.locationName === "string" ? data.locationName : "";
      const startMs = startsAt?.toMillis() ?? ctx.now.toMillis();
      const when = new Date(startMs);
      const timeLabel = when.toLocaleString("en-US", {
        weekday: "short",
        hour: "numeric",
        minute: "2-digit",
      });

      const meta = [
        { systemImage: "calendar", text: timeLabel },
        ...(locationName ? [{ systemImage: "mappin.circle", text: locationName }] : []),
      ];

      if (isSermon) {
        candidates.push({
          card: {
            id: newCardId("sermon", doc.id),
            kind: "sermon",
            hero: { scrim: "dark", style: "event", imageUrl: optStr(data.imageUrl) },
            eyebrow: "FROM YOUR CHURCH",
            title,
            subtitle: optStr(data.summary)?.slice(0, 140),
            action: {
              kind: "openSermon",
              label: "Watch",
              payload: { eventId: doc.id },
              ...(pulseDeeplink("openSermon", { eventId: doc.id }) ? { deeplink: pulseDeeplink("openSermon", { eventId: doc.id })! } : {}),
            },
            minorSafe: true,
            expiresAt: ctx.expiresAt,
            provenanceLabel: "Published by your church",
            meta,
          },
          signal: { relationship: 0.3, spiritual: 0.8, community: 0.7, urgency: 0.3, interest: 0.6 },
        });
      } else {
        candidates.push({
          card: {
            id: newCardId("event", doc.id),
            kind: "church_event",
            hero: { scrim: "dark", style: "event", imageUrl: optStr(data.imageUrl) },
            eyebrow: timeLabel.toUpperCase(),
            title,
            subtitle: optStr(data.summary)?.slice(0, 140),
            action: {
              kind: "rsvp",
              label: "RSVP",
              payload: { eventId: doc.id },
              ...(pulseDeeplink("rsvp", { eventId: doc.id }) ? { deeplink: pulseDeeplink("rsvp", { eventId: doc.id })! } : {}),
            },
            minorSafe: true,
            expiresAt: ctx.expiresAt,
            provenanceLabel: "Published by your church",
            meta,
          },
          signal: { relationship: 0.3, spiritual: 0.5, community: 0.8, urgency: 0.6, interest: 0.6 },
        });
      }
    }
    return candidates;
  } catch (error) {
    logger.warn("Pulse collectChurchEvents failed", { uid: ctx.uid, error });
    return [];
  }
}

/** Space relevance: a Space the user belongs to whose topic intersects their reading. */
async function collectSpaceRelevance(ctx: CollectorContext): Promise<PulseCandidate[]> {
  if (ctx.spaceIds.length === 0 || ctx.interestTopics.length === 0) return [];
  try {
    const candidates: PulseCandidate[] = [];
    const spaceIds = ctx.spaceIds.slice(0, 10);
    const interest = new Set(ctx.interestTopics.map((t) => t.toLowerCase()));

    const snap = await db
      .collection("spaces")
      .where(admin.firestore.FieldPath.documentId(), "in", spaceIds)
      .limit(10)
      .get();

    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const topics = Array.isArray(data.topics) ? (data.topics as unknown[]).map((t) => String(t)) : [];
      const overlap = topics.filter((t) => interest.has(t.toLowerCase()));
      if (overlap.length === 0) continue; // relevance, NOT velocity

      const spaceName = String(data.name ?? "a Space you're in");
      // Relevance strength scales with topic overlap (NOT activity/velocity).
      const relevance = Math.min(1, 0.4 + overlap.length * 0.2);

      candidates.push({
        card: {
          id: newCardId("space", doc.id),
          kind: "space_activity",
          hero: { scrim: "dark", style: "space", imageUrl: optStr(data.coverImageUrl) },
          eyebrow: "RELATED TO YOUR READING",
          title: `${spaceName} touches on ${overlap[0]}`,
          subtitle: "A conversation that lines up with what you've been studying",
          action: {
            kind: "openSpace",
            label: "Open Space",
            payload: { spaceId: doc.id },
            ...(pulseDeeplink("openSpace", { spaceId: doc.id }) ? { deeplink: pulseDeeplink("openSpace", { spaceId: doc.id })! } : {}),
          },
          minorSafe: true,
          expiresAt: ctx.expiresAt,
          provenanceLabel: "Matched to your reading",
        },
        signal: { relationship: 0.2, spiritual: 0.5, community: 0.7, urgency: 0.2, interest: relevance },
      });
    }
    return candidates;
  } catch (error) {
    logger.warn("Pulse collectSpaceRelevance failed", { uid: ctx.uid, error });
    return [];
  }
}

/** Fresh What's New stories (<=14 days), audience-filtered for minors downstream. */
async function collectWhatsNew(ctx: CollectorContext, minor: boolean): Promise<PulseCandidate[]> {
  try {
    const cutoff = tsFromMillis(ctx.now.toMillis() - 14 * DAY_MS);
    const snap = await db
      .collection("whatsNewStories")
      .where("publishedAt", ">=", cutoff)
      .orderBy("publishedAt", "desc")
      .limit(6)
      .get();

    const candidates: PulseCandidate[] = [];
    for (const doc of snap.docs) {
      const data = doc.data() as Record<string, unknown>;
      const audience = String(data.audience ?? "all");
      // adult_only stories are not minorSafe.
      const minorSafe = audience !== "adult_only";
      if (minor && !minorSafe) continue;

      const title = String(data.title ?? "New in Amen");
      const tagline = optStr(data.tagline);
      const tryAction = data.tryAction as { deeplink?: string; label?: string } | undefined;

      candidates.push({
        card: {
          id: newCardId("whatsnew", doc.id),
          kind: "whats_new",
          hero: { scrim: "dark", style: "whatsnew", videoUrl: optStr(data.videoUrl) },
          eyebrow: "NEW IN AMEN",
          title,
          subtitle: tagline,
          action: tryAction?.deeplink
            ? { kind: "tryFeature", label: tryAction.label ?? "Try it", deeplink: tryAction.deeplink }
            : { kind: "seeWhatsNew", label: "See what's new", payload: { storyId: doc.id } },
          minorSafe,
          expiresAt: ctx.expiresAt,
          provenanceLabel: "What's new in Amen",
          whatsNewStoryId: doc.id,
        },
        signal: { relationship: 0.1, spiritual: 0.2, community: 0.3, urgency: 0.2, interest: 0.55 },
      });
    }
    return candidates;
  } catch (error) {
    logger.warn("Pulse collectWhatsNew failed", { uid: ctx.uid, error });
    return [];
  }
}

function optStr(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

// ─── Berean Daily Brief summarizer (Claude, cite-or-refuse, fail-closed) ──────

/**
 * Builds the Daily Brief hero card via the existing callModel helper
 * (intelligence.summarize → Claude). Cite-or-refuse and fail-closed: on ANY
 * failure (no key, provider error, refusal sentinel, empty), returns null and
 * the section is OMITTED. We never ship unverified scripture.
 */
async function buildDailyBriefHero(
  ctx: CollectorContext,
  sourceText: string
): Promise<PulseCandidate | null> {
  // No API key → omit the AI section entirely (fail-closed, no fabrication).
  if (!ANTHROPIC_API_KEY.value()) {
    logger.info("Pulse brief: model unavailable, omitting hero", { uid: ctx.uid });
    return null;
  }
  if (!sourceText.trim()) return null;

  const durations: Array<PulseBriefSection["minimumDuration"]> = ["30s", "3m", "10m"];
  const sections: PulseBriefSection[] = [];

  for (const duration of durations) {
    const instruction =
      duration === "30s"
        ? "Summarize in ONE sentence the single most important thing for today. Include at most one VERIFIED scripture reference."
        : duration === "3m"
        ? "Summarize in up to 3 concise bullet points. Each bullet may include one VERIFIED scripture reference."
        : "Provide a fuller reflection in up to 5 short paragraphs with VERIFIED scripture references only.";

    const out = await callModel({
      task: "intelligence.summarize",
      input: `${instruction}\n\nMaterial:\n${sourceText}`,
      userId: ctx.uid,
      safetyLevel: "strict",
    });

    // Fail-closed: any error or refusal sentinel → omit the whole hero.
    if (out.error) {
      logger.info("Pulse brief: model error, omitting hero", { uid: ctx.uid, error: out.error });
      return null;
    }
    const result = out.result;
    if (result && typeof result === "object" && "error" in (result as Record<string, unknown>)) {
      logger.info("Pulse brief: model refused, omitting hero", { uid: ctx.uid });
      return null;
    }
    const body = typeof result === "string" ? result.trim() : "";
    if (!body) return null;

    // Guilt-lint each generated section body too (fail-closed).
    if (violatesGuiltLint(body)) {
      logger.info("Pulse brief: section failed guilt-lint, omitting hero", { uid: ctx.uid });
      return null;
    }

    sections.push({
      heading: duration === "30s" ? "Today" : duration === "3m" ? "Go deeper" : "Sit with it",
      body,
      minimumDuration: duration,
    });
  }

  if (sections.length === 0) return null;

  const facts = [
    { systemImage: "book.closed", text: "Summaries by Berean" },
    { systemImage: "checkmark.seal", text: "Cite-or-refuse" },
  ];

  return {
    card: {
      id: "daily_brief_hero",
      kind: "daily_brief_hero",
      hero: { scrim: "dark", style: "brief" },
      eyebrow: "YOUR DAILY BRIEF",
      title: "A few minutes with Berean",
      subtitle: sections[0]?.body.slice(0, 120),
      action: { kind: "openBrief", label: "Open brief" },
      minorSafe: true,
      expiresAt: ctx.expiresAt,
      provenanceLabel: "Generated this morning · Summaries by Berean · cite-or-refuse",
      facts,
      briefSections: sections,
    },
    signal: { relationship: 0.3, spiritual: 0.95, community: 0.3, urgency: 0.4, interest: 0.7 },
  };
}

// ─── Safety gate (fail-closed; any failure DROPS the card) ────────────────────

/**
 * Run a card's user-facing strings through the existing moderation helper AND
 * the guilt-lint pass. Returns true only if the card is safe. Fail-closed: a
 * moderation error or any guilt-lint match → false (DROP), never degrade to
 * unfiltered output.
 */
async function cardPassesSafety(card: PulseCard): Promise<boolean> {
  if (!passesGuiltLint(card)) return false;

  const strings = [card.eyebrow, card.title, card.subtitle ?? "", card.provenanceLabel ?? ""];
  for (const section of card.briefSections ?? []) {
    strings.push(section.heading, section.body);
    if (violatesGuiltLint(section.heading) || violatesGuiltLint(section.body)) return false;
  }

  try {
    for (const s of strings) {
      if (!s.trim()) continue;
      const result = await moderateContent(s);
      if (!result.safe) return false; // fail-closed drop
    }
    return true;
  } catch {
    return false; // fail-closed: never ship unfiltered
  }
}

// ─── Read user's church + space memberships + reading interests (fail-soft) ───

async function loadUserContext(uid: string): Promise<{
  churchIds: string[];
  spaceIds: string[];
  interestTopics: string[];
}> {
  const [churchIds, spaceIds, interestTopics] = await Promise.all([
    safeIds(db.collection("users").doc(uid).collection("churchMemberships").limit(10)),
    safeIds(db.collection("users").doc(uid).collection("spaceMemberships").limit(10)),
    safeTopics(uid),
  ]);
  return { churchIds, spaceIds, interestTopics };
}

async function safeIds(query: FirebaseFirestore.Query): Promise<string[]> {
  try {
    const snap = await query.get();
    return snap.docs.map((d) => d.id);
  } catch {
    return [];
  }
}

async function safeTopics(uid: string): Promise<string[]> {
  try {
    const snap = await db.collection("users").doc(uid).collection("followedTopics").limit(20).get();
    return snap.docs.map((d) => {
      const data = d.data() as Record<string, unknown>;
      return String(data.topic ?? data.name ?? d.id);
    });
  } catch {
    return [];
  }
}

// ─── Source material for the Daily Brief (fail-soft) ──────────────────────────

async function loadBriefSourceText(uid: string): Promise<string> {
  try {
    const snap = await db
      .collection("users")
      .doc(uid)
      .collection("reflectionEntries")
      .orderBy("updatedAt", "desc")
      .limit(3)
      .get();
    const parts = snap.docs.map((d) => {
      const data = d.data() as Record<string, unknown>;
      return String(data.text ?? data.content ?? data.passageReference ?? "").slice(0, 400);
    });
    return parts.filter(Boolean).join("\n\n");
  } catch {
    return "";
  }
}

// ─── Generator ────────────────────────────────────────────────────────────────

export async function generateAmenPulseForUser(
  uid: string,
  dateKey = dateKeyFor()
): Promise<PulseCard[]> {
  const config = await loadPulseConfig();
  if (!config["pulse.enabled"]) {
    logger.info("Amen Pulse disabled by config", { uid });
    return [];
  }

  const prefs = await loadPrefs(uid);
  if (prefs.enabled === false) {
    logger.info("Amen Pulse disabled by user pref", { uid });
    return [];
  }

  const now = tsNow();
  const expiresAt = tsFromMillis(now.toMillis() + DAY_MS);

  // Authoritative resolutions.
  const [minor, sabbath, userContext] = await Promise.all([
    resolveMinor(uid),
    isUsersSabbath(uid),
    loadUserContext(uid),
  ]);

  // ── Sabbath: a SINGLE still card, no events/countdowns. ──
  if (sabbath) {
    const stillCard = buildSabbathStillCard(
      "Come to me, all you who are weary and burdened, and I will give you rest.",
      "Matthew 11:28",
      expiresAt
    );
    const doc: PulseDocument = {
      date: dateKey,
      generatedAt: now,
      sabbath: true,
      briefDurations: ["30s", "3m", "10m"],
      cards: [stillCard],
    };
    await pulseDayDoc(uid, dateKey).set(doc, { merge: false });
    logger.info("Amen Pulse generated (Sabbath)", { uid, dateKey });
    return [stillCard];
  }

  const ctx: CollectorContext = {
    uid,
    now,
    expiresAt,
    churchIds: userContext.churchIds,
    spaceIds: userContext.spaceIds,
    interestTopics: userContext.interestTopics,
  };

  // ── Collectors run in parallel; each fail-soft. ──
  const [
    occasions,
    prayers,
    churchEvents,
    spaceRelevance,
    whatsNew,
    briefSource,
  ] = await Promise.all([
    config["pulse.kind.occasion"] ? collectOccasions(ctx) : Promise.resolve([]),
    config["pulse.kind.prayer_followup"] ? collectPrayerFollowUps(ctx) : Promise.resolve([]),
    config["pulse.kind.church_event"] || config["pulse.kind.sermon"]
      ? collectChurchEvents(ctx)
      : Promise.resolve([]),
    config["pulse.kind.space_activity"] ? collectSpaceRelevance(ctx) : Promise.resolve([]),
    config["whatsNew.enabled"] && config["pulse.kind.whats_new"]
      ? collectWhatsNew(ctx, minor.isMinor)
      : Promise.resolve([]),
    loadBriefSourceText(uid),
  ]);

  // ── Berean Daily Brief hero (fail-closed; omitted on any failure). ──
  let brief: PulseCandidate | null = null;
  if (config["pulse.kind.daily_brief_hero"]) {
    brief = await buildDailyBriefHero(ctx, briefSource);
  }

  let candidates: PulseCandidate[] = [
    ...(brief ? [brief] : []),
    ...occasions,
    ...prayers,
    ...churchEvents,
    ...spaceRelevance,
    ...whatsNew,
  ];

  // ── Crisis: any crisis-class candidate is dropped (bypasses Pulse). ──
  candidates = candidates.filter((c) => {
    if (c.isCrisis) return false;
    if (isCrisisText(c.card.title) || isCrisisText(c.card.subtitle)) return false;
    return true;
  });

  // ── Pure scoring + selection (guilt-lint + minor gate + threshold + cap). ──
  let selected = selectPulseCards({
    candidates,
    style: prefs.style,
    maxCards: config["pulse.maxCards"],
    userMaxCards: prefs.maxCards,
    scoreThreshold: config["pulse.scoreThreshold"],
    isMinor: minor.isMinor,
  });

  // ── Safety gate (async moderation + guilt-lint), fail-closed per card. ──
  const safeCards: PulseCard[] = [];
  for (const card of selected) {
    if (await cardPassesSafety(card)) safeCards.push(card);
  }
  selected = safeCards;

  const doc: PulseDocument = {
    date: dateKey,
    generatedAt: now,
    sabbath: false,
    briefDurations: ["30s", "3m", "10m"],
    cards: selected,
  };

  await pulseDayDoc(uid, dateKey).set(doc, { merge: false });
  logger.info("Amen Pulse generated", {
    uid,
    dateKey,
    cards: selected.length,
    minor: minor.isMinor,
    minorUnknown: minor.unknown,
  });
  return selected;
}

// ─── Callable: refreshAmenPulseForCurrentUser ────────────────────────────────

export async function refreshAmenPulseForCurrentUserHandler(request: {
  data?: { dateKey?: unknown };
  app?: unknown;
  auth?: { uid?: string };
}) {
  requireAppCheck(request);
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const metaRef = pulseMetaDoc(uid);
  const metaSnap = await metaRef.get();
  const lastManualRefreshAt = metaSnap.data()?.lastManualRefreshAt as Ts | undefined;
  const now = tsNow();
  const secondsSinceRefresh = lastManualRefreshAt
    ? now.seconds - lastManualRefreshAt.seconds
    : Number.POSITIVE_INFINITY;

  if (secondsSinceRefresh < 300) {
    throw new HttpsError("resource-exhausted", "Amen Pulse can be refreshed every five minutes.");
  }

  const dateKey = typeof request.data?.dateKey === "string" ? request.data.dateKey : dateKeyFor();
  const cards = await generateAmenPulseForUser(uid, dateKey);
  await metaRef.set({ lastManualRefreshAt: now }, { merge: true });
  return { ok: true, dateKey, cardCount: cards.length };
}

export const refreshAmenPulseForCurrentUser = onCall(
  { region: "us-central1", enforceAppCheck: true, secrets: [ANTHROPIC_API_KEY] },
  refreshAmenPulseForCurrentUserHandler
);

// ─── Schedule: generateAmenPulseDaily ─────────────────────────────────────────

export const generateAmenPulseDaily = onSchedule(
  {
    schedule: "every day 05:15",
    region: "us-central1",
    timeZone: "America/New_York",
    secrets: [ANTHROPIC_API_KEY],
  },
  async () => {
    const dateKey = dateKeyFor();
    const users = await db.collection("users").limit(100).get();
    for (const user of users.docs) {
      try {
        await generateAmenPulseForUser(user.id, dateKey);
      } catch (error) {
        logger.error("Amen Pulse daily generation failed", { uid: user.id, error });
      }
    }
  }
);

// ─── What's New seed (admin-only, idempotent) ─────────────────────────────────

interface WhatsNewStorySeed {
  id: string;
  version: string;
  title: string;
  tagline: string;
  pages: Array<{
    heroImageUrl?: string;
    style?: string;
    headline: string;
    body: string;
    layout: "full_bleed" | "split" | "caption_over";
  }>;
  tryAction?: { deeplink: string; label: string };
  videoUrl?: string;
  audience: "all" | "adult_only";
  bookmarkable: true;
}

const WHATS_NEW_SEEDS: WhatsNewStorySeed[] = [
  {
    id: "church_notes_2",
    version: "2.0",
    title: "Church Notes 2.0",
    tagline: "Capture the sermon, keep the meaning.",
    pages: [
      {
        headline: "Notes that understand the message",
        body: "Church Notes now follows along with the sermon and helps you keep what matters.",
        layout: "full_bleed",
        style: "whatsnew",
      },
      {
        headline: "Organized by passage",
        body: "Your notes link to the scripture they came from, so you can return any time.",
        layout: "split",
      },
    ],
    tryAction: { deeplink: "amen://church-notes", label: "Open Church Notes" },
    audience: "all",
    bookmarkable: true,
  },
  {
    id: "berean_sermon_context",
    version: "1.0",
    title: "Berean Understands Sermon Context",
    tagline: "Ask follow-up questions, grounded in what was preached.",
    pages: [
      {
        headline: "Context-aware study",
        body: "Berean can now reason about the sermon you just heard, cite-or-refuse, never fabricating references.",
        layout: "full_bleed",
        style: "whatsnew",
      },
    ],
    tryAction: { deeplink: "amen://berean", label: "Ask Berean" },
    audience: "all",
    bookmarkable: true,
  },
  {
    id: "guardian_family_safe_sharing",
    version: "1.0",
    title: "Guardian Family Safe Sharing",
    tagline: "Share with your family, safely and privately.",
    pages: [
      {
        headline: "Family-safe by design",
        body: "Guardian tools let families share moments with privacy controls built for every age.",
        layout: "caption_over",
        style: "whatsnew",
      },
    ],
    tryAction: { deeplink: "amen://guardian", label: "Set up Guardian" },
    audience: "adult_only",
    bookmarkable: true,
  },
  {
    id: "smart_volunteer_matching",
    version: "1.0",
    title: "Smart Volunteer Matching",
    tagline: "Find the right way to serve.",
    pages: [
      {
        headline: "Serve where you're needed",
        body: "We match your gifts and availability to opportunities at your church and community.",
        layout: "split",
        style: "whatsnew",
      },
    ],
    tryAction: { deeplink: "amen://opportunities", label: "Find a way to serve" },
    audience: "all",
    bookmarkable: true,
  },
];

export async function seedWhatsNewStoriesInternal(): Promise<number> {
  const now = tsNow();
  const batch = db.batch();
  for (const seed of WHATS_NEW_SEEDS) {
    const { id, ...rest } = seed;
    const ref = db.collection("whatsNewStories").doc(id);
    // Idempotent: set with merge preserves any later edits to publishedAt.
    batch.set(
      ref,
      { ...rest, publishedAt: now },
      { merge: true }
    );
  }
  await batch.commit();
  return WHATS_NEW_SEEDS.length;
}

export const seedWhatsNewStories = onCall(
  { region: "us-central1", enforceAppCheck: true },
  async (request) => {
    requireAppCheck(request);
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Must be signed in.");
    const isAdmin = request.auth?.token?.admin === true;
    if (!isAdmin) throw new HttpsError("permission-denied", "Admin only.");
    const count = await seedWhatsNewStoriesInternal();
    return { ok: true, count };
  }
);
