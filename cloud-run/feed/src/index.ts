/**
 * AMEN Feed Ranking Service — Cloud Run (Node.js / TypeScript)
 *
 * POST /rank
 *   Body: { userId, posts[], interests, followingIds[] }
 *   Returns: { rankedIds: string[] }   — ordered post IDs
 *
 * Mirrors the 12-factor HomeFeedAlgorithm.swift scoring logic.
 * Runs server-side so the device never needs to download all posts.
 *
 * Deploy:
 *   gcloud run deploy amen-feed \
 *     --source . --region us-central1 \
 *     --no-allow-unauthenticated
 */

import express, { Request, Response } from "express";

const app = express();
app.use(express.json({ limit: "1mb" }));

// ─── Types ────────────────────────────────────────────────────────────────────

interface PostPayload {
  id: string;
  authorId: string;
  content: string;
  category: string;   // "openTable" | "testimonies" | "prayer" | "tip" | "funFact" | …
  topicTag?: string;
  amenCount: number;
  commentCount: number;
  createdAt: number;  // Unix timestamp (seconds)
}

interface UserInterests {
  engagedTopics: Record<string, number>;       // topic → score 0-100
  engagedAuthors: Record<string, number>;      // authorId → engagement count
  preferredCategories: Record<string, number>; // category → score
  onboardingGoals: string[];
}

interface RankRequest {
  userId: string;
  posts: PostPayload[];
  interests: UserInterests;
  followingIds: string[];
  /** Cards already shown this session (client-reported, used for session cap) */
  sessionCardsServed?: number;
  /** Max cards allowed per session. Defaults to 25 if omitted. */
  sessionCap?: number;
}

interface RankResponse {
  rankedIds: string[];
  /** Cards remaining in this session (undefined = no cap applied) */
  sessionCapRemaining?: number;
  /** True when the caller has exhausted the session cap */
  sessionExhausted?: boolean;
}

// ─── Scoring helpers ──────────────────────────────────────────────────────────

function recencyScore(createdAt: number): number {
  const hoursSince = (Date.now() / 1000 - createdAt) / 3600;
  if (hoursSince < 1)  return 100;
  if (hoursSince < 6)  return 90;
  if (hoursSince < 24) return 70;
  if (hoursSince < 72) return 40;
  return Math.max(10, 40 - ((hoursSince - 72) / 24) * 5);
}

function followingScore(post: PostPayload, followingSet: Set<string>): number {
  return followingSet.has(post.authorId) ? 90 : 30;
}

function topicScore(post: PostPayload, interests: UserInterests): number {
  let score = 50;
  if (post.topicTag && interests.engagedTopics[post.topicTag] != null) {
    score = interests.engagedTopics[post.topicTag];
  }
  const words = new Set(post.content.toLowerCase().split(/\s+/));
  let best = score;
  for (const [topic, s] of Object.entries(interests.engagedTopics)) {
    if (words.has(topic.toLowerCase())) best = Math.max(best, s);
  }
  return best;
}

const GOAL_KEYWORDS: Record<string, string[]> = {
  "Grow in Faith":       ["faith", "spiritual", "growth", "journey", "testimony", "berean"],
  "Daily Bible Reading": ["scripture", "bible", "verse", "psalm", "gospel", "word"],
  "Consistent Prayer":   ["prayer", "pray", "praying", "intercession", "worship"],
  "Build Community":     ["community", "fellowship", "church", "gathering", "together"],
  "Share the Gospel":    ["gospel", "evangelism", "witness", "testimony", "share"],
  "Serve Others":        ["serve", "service", "volunteer", "help", "ministry", "mission"],
};

function goalScore(post: PostPayload, interests: UserInterests): number {
  if (!interests.onboardingGoals.length) return 50;
  let score = 30;
  const lower = post.content.toLowerCase();
  for (const goal of interests.onboardingGoals) {
    const kws = GOAL_KEYWORDS[goal] ?? [];
    const matches = kws.filter((k) => lower.includes(k)).length;
    score += matches * 15;
  }
  // Category boosts
  if (post.category === "prayer" && interests.onboardingGoals.includes("Consistent Prayer")) score += 20;
  if (post.category === "testimonies" &&
      (interests.onboardingGoals.includes("Share the Gospel") ||
       interests.onboardingGoals.includes("Grow in Faith"))) score += 20;
  if (post.category === "openTable" && interests.onboardingGoals.includes("Build Community")) score += 15;
  return Math.min(100, score);
}

function authorScore(post: PostPayload, interests: UserInterests): number {
  const count = interests.engagedAuthors[post.authorId];
  if (count == null) return 30;
  return Math.min(100, 30 + Math.log(count + 1) * 20);
}

function engagementScore(post: PostPayload): number {
  const total = post.commentCount * 3 + post.amenCount * 1.5;
  if (total < 5)   return 30;
  if (total < 20)  return 50;
  if (total < 50)  return 70;
  if (total < 100) return 85;
  return Math.min(100, 85 + Math.log(total - 100) * 3);
}

function diversityScore(post: PostPayload, interests: UserInterests): number {
  const engagement = interests.preferredCategories[post.category] ?? 0;
  if (engagement < 20) return 70;
  if (engagement < 50) return 50;
  return 20;
}

function categoryBoost(post: PostPayload): number {
  if (post.category === "tip" || post.category === "funFact") return 8;
  return 0;
}

function controversyPenalty(post: PostPayload): number {
  let penalty = 0;
  if (post.amenCount > 0) {
    const ratio = post.commentCount / post.amenCount;
    if (ratio > 1.5) penalty += 30;
    else if (ratio > 1.0) penalty += 15;
  }
  const hoursSince = (Date.now() / 1000 - post.createdAt) / 3600;
  if (hoursSince < 1 && post.commentCount > 50) penalty += 30;
  return penalty;
}

function repetitionPenalty(post: PostPayload, interests: UserInterests): number {
  const count = interests.engagedAuthors[post.authorId] ?? 0;
  if (count > 6) return 25;
  if (count > 4) return 15;
  if (count > 3) return 5;
  return 0;
}

// ─── Main scoring function ────────────────────────────────────────────────────

/**
 * Default mode weights (mirrors HeyFeed "balanced" mode).
 * Server doesn't have per-user HeyFeed prefs yet; use balanced defaults.
 */
const MODE_WEIGHTS = { recency: 0.35, following: 0.30 };

function scorePost(
  post: PostPayload,
  interests: UserInterests,
  followingSet: Set<string>
): number {
  let score = 0;

  // 1. Recency
  score += recencyScore(post.createdAt) * MODE_WEIGHTS.recency * 100 / 100;

  // 2. Following
  score += followingScore(post, followingSet) * MODE_WEIGHTS.following * 100 / 100;

  // 3. Topic (18%)
  score += topicScore(post, interests) * 0.18;

  // 4. Goal (12%)
  score += goalScore(post, interests) * 0.12;

  // 5. Author affinity (9%)
  score += authorScore(post, interests) * 0.09;

  // 6. Engagement quality (12%)
  score += engagementScore(post) * 0.12;

  // 7. Diversity (8%)
  score += diversityScore(post, interests) * 0.08;

  // 8. Category boost
  score += categoryBoost(post);

  // 9. Anti-ragebait
  score -= controversyPenalty(post);

  // 10. Repetition penalty
  score -= repetitionPenalty(post, interests);

  return Math.min(100, Math.max(0, score));
}

// ─── Author diversity pass ─────────────────────────────────────────────────────

function applyAuthorDiversity(
  scored: Array<{ post: PostPayload; score: number }>
): Array<{ post: PostPayload; score: number }> {
  const authorCount: Record<string, number> = {};
  const result: typeof scored = [];

  for (const item of scored) {
    const count = authorCount[item.post.authorId] ?? 0;
    if (count < 3) {   // max 3 consecutive posts from same author
      result.push(item);
      authorCount[item.post.authorId] = count + 1;
    }
  }

  // Append remaining posts from authors that were capped
  const included = new Set(result.map((i) => i.post.id));
  for (const item of scored) {
    if (!included.has(item.post.id)) result.push(item);
  }

  return result;
}

// ─── Ethical filters ──────────────────────────────────────────────────────────

function applyEthicalFilters(posts: PostPayload[]): PostPayload[] {
  const seen = new Set<string>();
  const authorCount: Record<string, number> = {};
  return posts.filter((p) => {
    const hash = p.content.toLowerCase().slice(0, 50);
    if (seen.has(hash)) return false;
    seen.add(hash);
    const count = authorCount[p.authorId] ?? 0;
    if (count >= 10) return false;
    authorCount[p.authorId] = count + 1;
    return true;
  });
}

// ─── Route ────────────────────────────────────────────────────────────────────

// Server-side session cap defaults (mirror HomeFeedAlgorithm.swift)
const DEFAULT_SESSION_CAP = 25;

app.post("/rank", (req: Request, res: Response) => {
  const body = req.body as RankRequest;

  if (!body?.posts?.length) {
    res.status(400).json({ error: "posts required" });
    return;
  }

  const followingSet = new Set<string>(body.followingIds ?? []);
  const interests: UserInterests = body.interests ?? {
    engagedTopics: {},
    engagedAuthors: {},
    preferredCategories: {},
    onboardingGoals: [],
  };

  // ── Session cap enforcement ───────────────────────────────────────────────
  // The client reports how many cards it has already shown this session.
  // The server trims the ranked list so the total never exceeds the cap.
  // This provides a server-side hard limit that cannot be bypassed by a
  // modified client.
  const sessionCap = Math.min(
    Math.max(1, body.sessionCap ?? DEFAULT_SESSION_CAP),
    DEFAULT_SESSION_CAP   // never allow a client to raise its own cap
  );
  const cardsServed = Math.max(0, body.sessionCardsServed ?? 0);
  const cardsRemaining = Math.max(0, sessionCap - cardsServed);

  if (cardsRemaining === 0) {
    const response: RankResponse = {
      rankedIds: [],
      sessionCapRemaining: 0,
      sessionExhausted: true,
    };
    res.json(response);
    return;
  }
  // ─────────────────────────────────────────────────────────────────────────

  // 1. Ethical filters
  const filtered = applyEthicalFilters(body.posts);

  // 2. Score
  const scored = filtered.map((post) => ({
    post,
    score: scorePost(post, interests, followingSet),
  }));

  // 3. Sort
  scored.sort((a, b) => b.score - a.score);

  // 4. Author diversity
  const diversified = applyAuthorDiversity(scored);

  // 5. Apply session cap — trim to remaining budget
  const capped = diversified.slice(0, cardsRemaining);

  const rankedIds = capped.map((i) => i.post.id);
  const newRemaining = cardsRemaining - rankedIds.length;
  const response: RankResponse = {
    rankedIds,
    sessionCapRemaining: newRemaining,
    sessionExhausted: newRemaining === 0,
  };
  res.json(response);
});

app.get("/health", (_req, res) => res.json({ status: "ok" }));

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT ?? "8080", 10);
app.listen(PORT, () => console.log(`Feed ranking service on :${PORT}`));
