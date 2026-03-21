/**
 * fellowshipMatcher.js
 *
 * Scheduled Cloud Function that:
 * 1. Reads recent prayers and testimonies from Firestore
 * 2. Groups them by user
 * 3. Uses the Claude API to detect deep spiritual theme matches between users
 * 4. For strong matches, generates a fellowship conversation starter
 * 5. Builds an OpenTable deep-link (2 covers, date +3 days, user's city)
 * 6. Writes a fellowshipSuggestions document for each matched user
 *
 * Runs every 12 hours. Each run only looks at content from the last 7 days
 * to keep Claude token usage bounded.
 */

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const Anthropic = require("@anthropic-ai/sdk");

// ── Config ───────────────────────────────────────────────────────────────────

const LOOKBACK_DAYS = 7;
const MIN_CAPTURES_PER_USER = 1; // require at least 1 prayer or testimony
const MATCH_SCORE_THRESHOLD = 75; // 0–100; Claude returns a numeric score
const MAX_USERS_PER_RUN = 50;     // cap to keep runtime bounded
const REGION = "us-central1";

// ── Helpers ──────────────────────────────────────────────────────────────────

function getAnthropicClient() {
  // Key stored via: firebase functions:config:set anthropic.key="sk-ant-..."
  // Or via Secret Manager (recommended for production).
  const key = process.env.ANTHROPIC_API_KEY
    || (process.env.FUNCTIONS_EMULATOR ? process.env.ANTHROPIC_API_KEY_LOCAL : null);
  if (!key) throw new Error("ANTHROPIC_API_KEY environment variable not set");
  return new Anthropic.default({ apiKey: key });
}

/**
 * Build an OpenTable search URL pre-filled with 2 covers, date+3, and city.
 * Format: https://www.opentable.com/s?covers=2&dateTime=YYYY-MM-DDTHH:MM&term=CITY
 */
function buildOpenTableURL(city) {
  const plusThree = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000);
  const dateStr = plusThree.toISOString().slice(0, 10); // YYYY-MM-DD
  const params = new URLSearchParams({
    covers: "2",
    dateTime: `${dateStr}T19:00`,
    term: city || "nearby",
  });
  return `https://www.opentable.com/s?${params.toString()}`;
}

/**
 * Ask Claude to score the spiritual theme overlap between two users' content
 * and, if strong, return a conversation starter.
 *
 * Returns: { score: number, theme: string, starter: string } or null
 */
async function analyzeMatch(client, userA, userB) {
  const prompt = `You are a thoughtful spiritual community facilitator.

Below are recent prayers and testimonies from two anonymous believers.

USER A:
${userA.captures.map((c) => `- ${c}`).join("\n")}

USER B:
${userB.captures.map((c) => `- ${c}`).join("\n")}

Task:
1. Identify whether these two people share a deep, specific spiritual theme (not just generic faith). Examples of deep themes: "surrendering fear about career to God", "wrestling with forgiveness after betrayal", "finding trust in God during grief".
2. Rate the strength of the thematic overlap on a scale of 0–100.
3. If the score is ${MATCH_SCORE_THRESHOLD} or above, write a warm, specific conversation starter (1–2 sentences) that references the shared theme WITHOUT quoting private content directly.

Respond ONLY with valid JSON matching this schema:
{
  "score": <number 0-100>,
  "theme": "<short theme label, max 60 chars>",
  "starter": "<conversation starter sentence or empty string if score < ${MATCH_SCORE_THRESHOLD}>"
}`;

  const message = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 300,
    messages: [{ role: "user", content: prompt }],
  });

  const text = message.content[0]?.text ?? "";
  // Strip markdown code fences if present
  const jsonStr = text.replace(/^```json?\s*/m, "").replace(/\s*```$/m, "").trim();
  const result = JSON.parse(jsonStr);
  return result;
}

// ── Main matching logic ──────────────────────────────────────────────────────

async function runFellowshipMatcher() {
  const db = admin.firestore();
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000)
  );

  // 1. Fetch recent prayers and testimonies
  const [prayerSnap, testimonySnap] = await Promise.all([
    db.collection("prayers")
      .where("createdAt", ">=", cutoff)
      .limit(500)
      .get(),
    db.collection("testimonies")
      .where("createdAt", ">=", cutoff)
      .limit(500)
      .get(),
  ]);

  // 2. Group content by userId
  const userContent = {}; // { [userId]: string[] }

  prayerSnap.docs.forEach((doc) => {
    const { userId, content } = doc.data();
    if (!userId || !content) return;
    userContent[userId] = userContent[userId] || [];
    userContent[userId].push(content);
  });

  testimonySnap.docs.forEach((doc) => {
    const { userId, content } = doc.data();
    if (!userId || !content) return;
    userContent[userId] = userContent[userId] || [];
    userContent[userId].push(content);
  });

  // Filter to users with enough content
  const eligibleUserIds = Object.keys(userContent).filter(
    (uid) => userContent[uid].length >= MIN_CAPTURES_PER_USER
  );

  if (eligibleUserIds.length < 2) {
    console.log("Not enough eligible users for fellowship matching.");
    return;
  }

  // Cap to MAX_USERS_PER_RUN (shuffle for fairness across runs)
  const shuffled = eligibleUserIds.sort(() => Math.random() - 0.5).slice(0, MAX_USERS_PER_RUN);

  // 3. Fetch user display names and cities in one batch
  const userDocs = await Promise.all(
    shuffled.map((uid) => db.collection("users").doc(uid).get())
  );
  const userMeta = {};
  userDocs.forEach((snap) => {
    if (snap.exists) {
      const { displayName, city } = snap.data();
      userMeta[snap.id] = { displayName: displayName || "Someone", city: city || "" };
    }
  });

  // 4. Check which pairs already have recent suggestions (avoid re-sending)
  const recentSuggestionsSnap = await db.collection("fellowshipSuggestions")
    .where("createdAt", ">=", cutoff)
    .get();
  const recentPairs = new Set(
    recentSuggestionsSnap.docs.map((d) => {
      const { userId1, userId2 } = d.data();
      return [userId1, userId2].sort().join("|");
    })
  );

  // 5. Iterate over unique pairs and call Claude
  const client = getAnthropicClient();
  let matchesFound = 0;
  const batch = db.batch();

  for (let i = 0; i < shuffled.length; i++) {
    for (let j = i + 1; j < shuffled.length; j++) {
      const uid1 = shuffled[i];
      const uid2 = shuffled[j];
      const pairKey = [uid1, uid2].sort().join("|");

      // Skip pairs that were already matched recently
      if (recentPairs.has(pairKey)) continue;

      let result;
      try {
        result = await analyzeMatch(client, {
          captures: userContent[uid1].slice(0, 5), // send max 5 captures per user
        }, {
          captures: userContent[uid2].slice(0, 5),
        });
      } catch (err) {
        console.error(`Claude error for pair ${pairKey}:`, err.message);
        continue;
      }

      if (!result || result.score < MATCH_SCORE_THRESHOLD || !result.starter) continue;

      matchesFound++;
      const now = admin.firestore.FieldValue.serverTimestamp();

      // Write one suggestion document per user (so security rules on recipientUserId work)
      [uid1, uid2].forEach((recipientId) => {
        const partnerMeta = userMeta[recipientId === uid1 ? uid2 : uid1] || {};
        const recipientMeta = userMeta[recipientId] || {};
        const ref = db.collection("fellowshipSuggestions").doc();
        batch.set(ref, {
          userId1: uid1,
          userId2: uid2,
          recipientUserId: recipientId,
          partnerUserId: recipientId === uid1 ? uid2 : uid1,
          partnerDisplayName: partnerMeta.displayName || "Someone",
          theme: result.theme,
          conversationStarter: result.starter,
          matchScore: result.score,
          opentableURL: buildOpenTableURL(recipientMeta.city),
          status: "pending",   // "pending" | "viewed" | "dismissed"
          createdAt: now,
        });
      });
    }
  }

  if (matchesFound > 0) {
    await batch.commit();
    console.log(`✅ fellowshipMatcher: wrote ${matchesFound * 2} suggestions for ${matchesFound} pairs`);
  } else {
    console.log("fellowshipMatcher: no new strong matches found this run.");
  }
}

// ── Exports ──────────────────────────────────────────────────────────────────

/**
 * Scheduled: runs every 12 hours.
 */
exports.fellowshipMatcher = onSchedule(
  { schedule: "every 12 hours", region: REGION, timeoutSeconds: 540 },
  async () => {
    await runFellowshipMatcher();
  }
);

/**
 * Trigger: also run when a new prayer is created (near-realtime matching).
 * Debounce effect: we skip pairs that already have a recent suggestion.
 */
exports.onNewPrayerFellowshipCheck = onDocumentCreated(
  { document: "prayers/{docId}", region: REGION },
  async (event) => {
    const data = event.data?.data();
    if (!data?.userId || !data?.content) return;
    // Run the full matcher — it's efficient because it skips recent pairs
    await runFellowshipMatcher();
  }
);
