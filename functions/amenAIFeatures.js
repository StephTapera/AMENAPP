/**
 * amenAIFeatures.js
 * AMEN App — Three primary AI callable features for client UI
 *
 * A. getDailyDigest({ dateKey, timezone, locale })
 *    Morning card data: dailyVerse, prayerReminders, unreadMentorMessages,
 *    churchEvents, spaceUpdates, studiesToContinue, reflectionPrompt.
 *    Cached in Firestore dailyDigests/{uid}/{dateKey} — computed once per day per user.
 *    Rate limit: 5 calls / day.
 *
 * B. generateCreatorDraft({ type, topic, audience, tone })
 *    Draft-only assistant for mentors/churches.
 *    types: "post" | "devotional" | "studyGuide" | "announcement"
 *    Returns { draft: string, type: string } — NEVER auto-publishes.
 *    Rate limit: 20 calls / hour.
 *
 * C. ragSearch({ query, scope })
 *    scope: "churchNotes" | "savedVerses" | "posts" | "sermons" | "all"
 *    Embeds query → searches Pinecone → returns ranked results.
 *    Multilingual: stub only — results returned in source language.
 *    Rate limit: 30 calls / hour.
 *
 * Hard rules (never violate):
 *   - Auth check on every callable (unauthenticated → throw)
 *   - Input validation before any external call
 *   - API keys via Secret Manager / defineSecret only
 *   - generateCreatorDraft never auto-publishes; always draft_only: true
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { enforceRateLimit } = require("./rateLimiter");
const {
  openaiEmbed,
  pineconeQuery,
  logFunction,
} = require("./mlClients");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";

// Pinecone namespaces that ragSearch queries
const RAG_NAMESPACES = {
  churchNotes: "church-notes-embeddings",
  savedVerses: "scripture-embeddings",
  posts: "testimony-embeddings",
  sermons: "sermon-embeddings",
};

// ─── Shared helpers ───────────────────────────────────────────────────────────

function db() {
  return admin.firestore();
}

/**
 * Call Anthropic Claude. Returns the text content of the first message block.
 * Uses fetch (Node 18+ native) so no extra dependency is needed.
 */
async function callClaude(apiKey, model, systemPrompt, userContent, maxTokens = 512, temperature = 0.7) {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{ role: "user", content: userContent }],
      temperature,
    }),
    signal: AbortSignal.timeout(25000),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude error ${response.status}: ${err}`);
  }

  const json = await response.json();
  return json.content?.[0]?.text ?? "";
}

// ─── A. getDailyDigest ────────────────────────────────────────────────────────

/**
 * Returns the morning card payload for the Liquid Glass morning card in iOS.
 *
 * Response shape:
 * {
 *   dailyVerse:            { reference, text, reflection }
 *   prayerReminders:       Array<{ postId, excerpt, hoursAgo }>
 *   unreadMentorMessages:  Array<{ senderId, senderName, preview, threadId }>
 *   churchEvents:          Array<{ eventId, title, startsAt, church }>
 *   spaceUpdates:          Array<{ spaceId, spaceName, summary, unreadCount }>
 *   studiesToContinue:     Array<{ studyId, title, progressPct, nextLesson }>
 *   reflectionPrompt:      string
 *   cached:                boolean
 *   generatedAt:           string (ISO)
 * }
 *
 * Cached in: dailyDigests/{uid}/{dateKey}
 * Rate limit: 5 / day per user
 */
exports.getDailyDigest = onCall(
  {
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR // flip to true once App Check is wired in all environments
    timeoutSeconds: 60,
  },
  async (request) => {
    // ── Auth ──────────────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── Input validation ──────────────────────────────────────────────────────
    const { dateKey, timezone = "UTC", forceRefresh = false } = request.data || {};
    if (!dateKey || typeof dateKey !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) {
      throw new HttpsError("invalid-argument", "dateKey must be YYYY-MM-DD.");
    }

    // ── Rate limit: 5 per day ─────────────────────────────────────────────────
    await enforceRateLimit(uid, "getDailyDigest", 5, 86400);

    // ── Cache check ───────────────────────────────────────────────────────────
    const cacheRef = db().collection("dailyDigests").doc(uid).collection("dates").doc(dateKey);

    if (!forceRefresh) {
      const cached = await cacheRef.get();
      if (cached.exists) {
        logFunction("getDailyDigest", { uid, dateKey, cached: true });
        return { ...cached.data(), cached: true };
      }
    }

    const startMs = Date.now();

    // ── Parallel data fetches ─────────────────────────────────────────────────

    const startOfDay = new Date(`${dateKey}T00:00:00Z`);
    const endOfDay = new Date(`${dateKey}T23:59:59Z`);
    const nowTs = admin.firestore.Timestamp.now();

    const [
      userSnap,
      prayerPostsSnap,
      mentorMessagesSnap,
      churchEventsSnap,
      spaceUpdatesSnap,
      studiesSnap,
    ] = await Promise.allSettled([
      // User profile
      db().collection("users").doc(uid).get(),

      // User's own unanswered prayer requests posted in last 7 days
      db().collection("posts")
        .where("authorId", "==", uid)
        .where("category", "==", "prayer")
        .where("amenCount", "==", 0)
        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 7 * 86400000)
        ))
        .orderBy("createdAt", "desc")
        .limit(5)
        .get(),

      // Unread DMs from mentors (role == "mentor" or "pastor")
      db().collection("users").doc(uid)
        .collection("conversations")
        .where("hasUnread", "==", true)
        .where("partnerRole", "in", ["mentor", "pastor", "elder"])
        .orderBy("lastMessageAt", "desc")
        .limit(5)
        .get(),

      // Church events in the next 7 days
      db().collection("churchEvents")
        .where("attendeeIds", "array-contains", uid)
        .where("startsAt", ">=", nowTs)
        .where("startsAt", "<=", admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + 7 * 86400000)
        ))
        .orderBy("startsAt", "asc")
        .limit(5)
        .get(),

      // Spaces user belongs to — unread updates
      db().collection("spaces")
        .where("memberIds", "array-contains", uid)
        .where("lastActivityAt", ">=", admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 24 * 3600000)
        ))
        .orderBy("lastActivityAt", "desc")
        .limit(5)
        .get(),

      // Studies in progress
      db().collection("users").doc(uid)
        .collection("studyProgress")
        .where("isComplete", "==", false)
        .where("progressPct", ">", 0)
        .orderBy("progressPct", "desc")
        .limit(4)
        .get(),
    ]);

    // ── Shape data safely (handle Firestore misses) ───────────────────────────

    const userData = userSnap.status === "fulfilled" && userSnap.value.exists
      ? userSnap.value.data()
      : {};

    const prayerReminders = (prayerPostsSnap.status === "fulfilled"
      ? prayerPostsSnap.value.docs : []).map((d) => {
      const p = d.data();
      return {
        postId: d.id,
        excerpt: (p.content || "").slice(0, 100),
        hoursAgo: Math.round((Date.now() - (p.createdAt?.toMillis?.() ?? 0)) / 3600000),
      };
    });

    const unreadMentorMessages = (mentorMessagesSnap.status === "fulfilled"
      ? mentorMessagesSnap.value.docs : []).map((d) => {
      const c = d.data();
      return {
        threadId: d.id,
        senderId: c.partnerId || "",
        senderName: c.partnerName || "Mentor",
        preview: (c.lastMessage || "").slice(0, 80),
      };
    });

    const churchEvents = (churchEventsSnap.status === "fulfilled"
      ? churchEventsSnap.value.docs : []).map((d) => {
      const e = d.data();
      return {
        eventId: d.id,
        title: e.title || "",
        startsAt: e.startsAt?.toDate?.()?.toISOString?.() ?? null,
        church: e.churchName || e.churchId || "",
      };
    });

    const spaceUpdates = (spaceUpdatesSnap.status === "fulfilled"
      ? spaceUpdatesSnap.value.docs : []).map((d) => {
      const s = d.data();
      return {
        spaceId: d.id,
        spaceName: s.name || "",
        summary: (s.lastActivitySummary || "").slice(0, 100),
        unreadCount: s.unreadCounts?.[uid] ?? 0,
      };
    });

    const studiesToContinue = (studiesSnap.status === "fulfilled"
      ? studiesSnap.value.docs : []).map((d) => {
      const s = d.data();
      return {
        studyId: d.id,
        title: s.studyTitle || s.title || "",
        progressPct: s.progressPct ?? 0,
        nextLesson: s.nextLessonTitle || null,
      };
    });

    // ── Daily verse — simple daily rotation from bibleVerses collection ───────
    //   We compute a day-of-year index and pick a verse deterministically.

    const dayOfYear = Math.floor(
      (new Date(dateKey) - new Date(new Date(dateKey).getFullYear(), 0, 0)) / 86400000
    );
    const verseIndex = ((dayOfYear + uid.charCodeAt(0)) % 200) + 1;

    let dailyVerse = {
      reference: "Psalm 119:105",
      text: "Your word is a lamp to my feet and a light to my path.",
      reflection: "Let God's Word guide each step you take today.",
    };

    try {
      const verseSnap = await db().collection("bibleVerses")
        .orderBy("sortKey")
        .offset(verseIndex)
        .limit(1)
        .get();

      if (!verseSnap.empty) {
        const v = verseSnap.docs[0].data();
        const verseText = v.text || dailyVerse.text;
        const verseRef = v.reference || dailyVerse.reference;

        // Ask Claude for a one-sentence reflection
        let reflection = dailyVerse.reflection;
        try {
          reflection = await callClaude(
            ANTHROPIC_API_KEY.value(),
            "claude-haiku-4-5-20251001",
            `You write one-sentence spiritual reflections for a faith-based app.
Be warm, encouraging, and scripture-rooted. Max 20 words.
Output ONLY the sentence — no quotes, no extra text.`,
            `Bible verse: "${verseRef} — ${verseText}"\nWrite a one-sentence reflection for today.`,
            60,
            0.6
          );
          reflection = reflection.trim();
        } catch (_) { /* use default */ }

        dailyVerse = { reference: verseRef, text: verseText, reflection };
      }
    } catch (_) { /* use default verse */ }

    // ── Reflection prompt — Claude-generated, personalized ────────────────────

    let reflectionPrompt = "One thing to reflect on today: What is one area where you can trust God more fully?";

    try {
      const userName = userData.displayName || "friend";
      const recentInterests = (userData.interests || []).slice(0, 3).join(", ") || "faith";
      const rawPrompt = await callClaude(
        ANTHROPIC_API_KEY.value(),
        "claude-haiku-4-5-20251001",
        `You generate one brief, open-ended spiritual reflection prompt for a faith-based app.
Rules:
- Start with "One thing to reflect on today:"
- Max 25 words after the prefix
- Be specific to the user's interests but universally accessible
- Warm, not preachy. Question or invitation form.
- Output ONLY the full prompt sentence, nothing else.`,
        `User interests: ${recentInterests}. Today's date: ${dateKey}. Generate a reflection prompt.`,
        80,
        0.8
      );
      if (rawPrompt.trim().length > 10) {
        reflectionPrompt = rawPrompt.trim();
      }
    } catch (_) { /* use default */ }

    // ── Assemble and cache ────────────────────────────────────────────────────

    const digest = {
      dailyVerse,
      prayerReminders,
      unreadMentorMessages,
      churchEvents,
      spaceUpdates,
      studiesToContinue,
      reflectionPrompt,
      cached: false,
      generatedAt: new Date().toISOString(),
    };

    // Write to cache — TTL enforced by checking dateKey on read
    try {
      await cacheRef.set({
        ...digest,
        uid,
        dateKey,
        cachedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (cacheErr) {
      console.warn("[getDailyDigest] Cache write failed:", cacheErr.message);
    }

    logFunction("getDailyDigest", { uid, dateKey, cached: false, durationMs: Date.now() - startMs });
    return digest;
  }
);

// ─── B. generateCreatorDraft ──────────────────────────────────────────────────

/**
 * Draft assistant for mentors and church content creators.
 *
 * Input:
 *   type:     "post" | "devotional" | "studyGuide" | "announcement"
 *   topic:    string (required, max 300 chars)
 *   audience: string (optional, e.g. "young adults", "new believers")
 *   tone:     "warm" | "formal" | "encouraging" | "teaching" (default "warm")
 *
 * Response:
 *   { draft: string, type: string, draft_only: true }
 *
 * NEVER auto-publishes. draft_only: true is always set.
 * Rate limit: 20 / hour per user.
 */
exports.generateCreatorDraft = onCall(
  {
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    timeoutSeconds: 60,
  },
  async (request) => {
    // ── Auth ──────────────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── Input validation ──────────────────────────────────────────────────────
    const {
      type,
      topic,
      audience = "faith community",
      tone = "warm",
    } = request.data || {};

    const VALID_TYPES = ["post", "devotional", "studyGuide", "announcement"];
    const VALID_TONES = ["warm", "formal", "encouraging", "teaching"];

    if (!type || !VALID_TYPES.includes(type)) {
      throw new HttpsError(
        "invalid-argument",
        `type must be one of: ${VALID_TYPES.join(", ")}.`
      );
    }
    if (!topic || typeof topic !== "string" || topic.trim().length < 5) {
      throw new HttpsError("invalid-argument", "topic is required (min 5 characters).");
    }
    if (topic.length > 300) {
      throw new HttpsError("invalid-argument", "topic must be 300 characters or fewer.");
    }
    const safeTone = VALID_TONES.includes(tone) ? tone : "warm";
    const safeAudience = typeof audience === "string"
      ? audience.slice(0, 100)
      : "faith community";

    // ── Rate limit: 20 / hour ─────────────────────────────────────────────────
    await enforceRateLimit(uid, "generateCreatorDraft", 20, 3600);

    // ── System prompts per type ───────────────────────────────────────────────

    const typeInstructions = {
      post: `You write draft social media posts for faith leaders on AMEN, a Christian social platform.
The post should:
- Be 50–200 words
- Include 1 relevant scripture reference (chapter:verse format)
- End with a question or call to engage the community
- Be in a ${safeTone} tone
- Target audience: ${safeAudience}
Output ONLY the post text. Do not add titles, headings, or metadata.`,

      devotional: `You write daily devotional drafts for faith leaders on AMEN, a Christian platform.
The devotional should:
- Have a title (max 8 words)
- Include an opening scripture (reference + text)
- Body: 150–300 words of reflection
- Close with a brief prayer (2–4 sentences)
- Tone: ${safeTone}
- Audience: ${safeAudience}
Output ONLY the devotional text with its structure. No metadata.`,

      studyGuide: `You write Bible study guide drafts for faith leaders on AMEN.
The guide should:
- Title (max 8 words)
- Main scripture passage (reference only)
- 3–4 discussion questions
- A "going deeper" section with 1–2 cross-references
- Application challenge (1 sentence)
- Tone: ${safeTone}
- Audience: ${safeAudience}
Output ONLY the study guide content. No metadata.`,

      announcement: `You write church/community announcement drafts for leaders on AMEN, a Christian platform.
The announcement should:
- Be 50–120 words
- Be clear about what, when, and how to join/respond
- Tone: ${safeTone}
- Audience: ${safeAudience}
Output ONLY the announcement text. No metadata or subject lines.`,
    };

    const systemPrompt = typeInstructions[type];
    const userPrompt = `Topic: ${topic.trim()}${safeAudience !== "faith community" ? `\nAudience: ${safeAudience}` : ""}`;

    const maxTokensPerType = {
      post: 350,
      devotional: 700,
      studyGuide: 800,
      announcement: 300,
    };

    const startMs = Date.now();
    let draft = "";

    try {
      draft = await callClaude(
        ANTHROPIC_API_KEY.value(),
        "claude-sonnet-4-6",
        systemPrompt,
        userPrompt,
        maxTokensPerType[type],
        0.75
      );
    } catch (err) {
      console.error("[generateCreatorDraft] Claude error:", err.message);
      throw new HttpsError("internal", "Draft generation failed. Please try again.");
    }

    logFunction("generateCreatorDraft", {
      uid, type, topicLen: topic.length, durationMs: Date.now() - startMs,
    });

    // draft_only: true is a hard contract — never remove this flag
    return {
      draft: draft.trim(),
      type,
      draft_only: true,
    };
  }
);

// ─── C. ragSearch ─────────────────────────────────────────────────────────────

/**
 * Semantic RAG search across AMEN content using Pinecone.
 *
 * Input:
 *   query:  string (required, max 500 chars)
 *   scope:  "churchNotes" | "savedVerses" | "posts" | "sermons" | "all"
 *
 * Response:
 *   { results: Array<SearchResult>, scope, query, resultCount }
 *
 * SearchResult: { id, title, excerpt, score, type, sourceRef }
 *
 * Multilingual: // TODO(gate: DECISION) — multilingual: results returned in source language; requires translation layer decision
 *
 * Rate limit: 30 / hour per user.
 */
exports.ragSearch = onCall(
  {
    region: REGION,
    secrets: ["PINECONE_API_KEY", "PINECONE_HOST"],
    enforceAppCheck: true, // requires App Check token; disable locally via FUNCTIONS_EMULATOR
    timeoutSeconds: 30,
  },
  async (request) => {
    // ── Auth ──────────────────────────────────────────────────────────────────
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const uid = request.auth.uid;

    // ── Input validation ──────────────────────────────────────────────────────
    const { query, scope = "all" } = request.data || {};

    const VALID_SCOPES = ["churchNotes", "savedVerses", "posts", "sermons", "all"];

    if (!query || typeof query !== "string" || query.trim().length < 3) {
      throw new HttpsError("invalid-argument", "query must be at least 3 characters.");
    }
    if (query.length > 500) {
      throw new HttpsError("invalid-argument", "query must be 500 characters or fewer.");
    }
    if (!VALID_SCOPES.includes(scope)) {
      throw new HttpsError(
        "invalid-argument",
        `scope must be one of: ${VALID_SCOPES.join(", ")}.`
      );
    }

    // ── Rate limit: 30 / hour ─────────────────────────────────────────────────
    await enforceRateLimit(uid, "ragSearch", 30, 3600);

    // TODO(gate: DECISION) — multilingual: query is searched as-is; results returned in source language.
    // When multilingual support is added: detect language, translate query to English before
    // embedding, then translate result excerpts back to the user's locale.

    const startMs = Date.now();
    const safeQuery = query.trim();

    // ── Embed query ───────────────────────────────────────────────────────────
    let queryVector;
    try {
      queryVector = await openaiEmbed(safeQuery, null); // no caching for search queries
    } catch (err) {
      console.error("[ragSearch] Embedding error:", err.message);
      throw new HttpsError("internal", "Search embedding failed. Please try again.");
    }

    // ── Determine namespaces to search ───────────────────────────────────────
    const namespaceEntries = scope === "all"
      ? Object.entries(RAG_NAMESPACES)
      : [[scope, RAG_NAMESPACES[scope]]].filter(([, ns]) => !!ns);

    if (namespaceEntries.length === 0) {
      return { results: [], scope, query: safeQuery, resultCount: 0 };
    }

    // ── Query each Pinecone namespace in parallel ─────────────────────────────
    const perNamespaceLimit = scope === "all" ? 5 : 10;

    const queryResults = await Promise.allSettled(
      namespaceEntries.map(async ([scopeKey, namespace]) => {
        try {
          const matches = await pineconeQuery(namespace, queryVector, perNamespaceLimit);
          return { scopeKey, matches: matches || [] };
        } catch (err) {
          console.warn(`[ragSearch] Pinecone query failed for ${namespace}:`, err.message);
          return { scopeKey, matches: [] };
        }
      })
    );

    // ── Merge + enrich results ────────────────────────────────────────────────
    const allMatches = [];
    for (const settled of queryResults) {
      if (settled.status !== "fulfilled") continue;
      const { scopeKey, matches } = settled.value;

      for (const match of matches) {
        if ((match.score || 0) < 0.30) continue; // minimum relevance threshold

        // Build result from Pinecone metadata (no extra Firestore read needed for MVP)
        const meta = match.metadata || {};
        allMatches.push({
          id: match.id,
          title: meta.title || meta.reference || meta.book
            ? [meta.book, meta.chapter && meta.verse ? `${meta.chapter}:${meta.verse}` : ""].filter(Boolean).join(" ")
            : match.id,
          excerpt: (meta.text || meta.content || meta.excerpt || "").slice(0, 200),
          score: Math.round((match.score || 0) * 1000) / 1000,
          type: scopeKey,
          sourceRef: meta.reference || meta.postId || meta.noteId || match.id,
          authorId: meta.authorId || null,
        });
      }
    }

    // Sort by score descending, cap at 20 total results
    allMatches.sort((a, b) => b.score - a.score);
    const results = allMatches.slice(0, 20);

    // ── Privacy filter: ACL-enforce every result before returning ──────────────
    //   CRITICAL FIX (2026-06-12): The previous implementation kept all posts
    //   regardless of privacy, allowing private testimony embeddings to be
    //   returned to callers who shouldn't have access. See docs/privacy-model.md §10.
    //
    //   For posts: batch Firestore reads to check privacy level + block status.
    //   For churchNotes: user-scoped at upsert time — only return caller's own.
    //   For savedVerses / sermons: public by default.

    const postResults = results.filter(
      (r) => r.type === "posts" && r.authorId && r.authorId !== uid
    );
    const nonPostResults = results.filter(
      (r) => !(r.type === "posts" && r.authorId && r.authorId !== uid)
    );

    // Batch ACL check for post results
    const accessiblePostIds = new Set();
    if (postResults.length > 0) {
      await Promise.allSettled(
        postResults.map(async (r) => {
          try {
            const postSnap = await db().collection("posts").doc(r.id).get();
            if (!postSnap.exists) return; // deleted post

            const postData = postSnap.data();
            const postAuthorId = postData.authorId || postData.userId || "";

            // Block check: deny if either party has blocked the other
            const [blockedByAuthor, callerBlocked] = await Promise.all([
              db().collection("blockedUsers").doc(`${postAuthorId}_${uid}`).get(),
              db().collection("blockedUsers").doc(`${uid}_${postAuthorId}`).get(),
            ]);
            if (blockedByAuthor.exists || callerBlocked.exists) return;

            // Normalise privacy level across schema versions
            const raw = postData.privacyLevel || postData.visibility || "public";
            const level = raw === "Everyone" ? "public"
              : raw === "Followers" ? "followers"
              : raw === "Community Only" ? "trustedCircle"
              : raw;

            if (level === "public" || level === "everyone") {
              accessiblePostIds.add(r.id);
            } else if (level === "followers") {
              const followDoc = await db()
                .collection("follows_index")
                .doc(`${uid}_${postAuthorId}`)
                .get();
              if (followDoc.exists) accessiblePostIds.add(r.id);
            } else if (level === "trustedCircle") {
              const [ab, ba] = await Promise.all([
                db().collection("follows_index").doc(`${uid}_${postAuthorId}`).get(),
                db().collection("follows_index").doc(`${postAuthorId}_${uid}`).get(),
              ]);
              if (ab.exists && ba.exists) accessiblePostIds.add(r.id);
            }
            // church / space / private / unknown → deny from RAG results
          } catch (checkErr) {
            console.warn(`[ragSearch] ACL check failed for post ${r.id}:`, checkErr.message);
          }
        })
      );
    }

    // Caller owns their own post results — always accessible
    const ownedPostResults = results.filter(
      (r) => r.type === "posts" && r.authorId === uid
    );

    const safeResults = [
      ...ownedPostResults,
      ...postResults.filter((r) => accessiblePostIds.has(r.id)),
      ...nonPostResults.filter((r) => {
        // Church notes are user-scoped — only return caller's own
        if (r.type === "churchNotes" && r.authorId && r.authorId !== uid) return false;
        return true;
      }),
    ];

    logFunction("ragSearch", {
      uid, scope, queryLen: safeQuery.length,
      resultCount: safeResults.length, durationMs: Date.now() - startMs,
    });

    return {
      results: safeResults,
      scope,
      query: safeQuery,
      resultCount: safeResults.length,
    };
  }
);
