/**
 * churchEnhancementFunctions.js
 * AMEN App — Find Church Enhancement Cloud Functions
 *
 * Functions:
 *   generateChurchVibe          — weekly cron: Claude sunday vibe phrase per church
 *   computeChurchDNA            — on-demand: 6-axis theology scores from sermon notes
 *   computePrayerMomentum       — weekly cron: answered prayer trend per church
 *   generateChurchSundayPulse   — every 10 min Sundays: sentiment from social mentions
 *   generateFirstVisitGuide     — on-demand: Claude-generated first visit guide
 *   inferUserLearningStyle      — on-demand: classify note-taker learning style
 *   inferPastorStyle            — on-demand: classify pastor teaching style
 */

"use strict";

const {onCall, HttpsError}         = require("firebase-functions/v2/https");
const {onSchedule}                 = require("firebase-functions/v2/scheduler");
const {defineSecret}               = require("firebase-functions/params");
const admin                        = require("firebase-admin");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const REGION            = "us-central1";

// ─── Shared helpers ────────────────────────────────────────────────────────────

async function callClaude(apiKey, systemPrompt, userContent, maxTokens = 300, temperature = 0.3) {
  const fetch    = (await import("node-fetch")).default;
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method:  "POST",
    headers: {
      "Content-Type":      "application/json",
      "x-api-key":         apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model:     "claude-sonnet-4-6",
      max_tokens: maxTokens,
      system:    systemPrompt,
      messages:  [{role: "user", content: userContent}],
      temperature,
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude error ${response.status}: ${err}`);
  }
  const json = await response.json();
  return json.content?.[0]?.text ?? "";
}

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
}

// ─── GENERATE CHURCH VIBE (weekly, Monday 7am UTC) ────────────────────────────

exports.generateChurchVibe = onSchedule(
    {schedule: "0 7 * * 1", region: REGION, secrets: [ANTHROPIC_API_KEY]},
    async () => {
      const db     = admin.firestore();
      const apiKey = ANTHROPIC_API_KEY.value();
      const snap   = await db.collection("churches").limit(200).get();

      for (const doc of snap.docs) {
        const churchId = doc.id;
        const church   = doc.data();

        try {
          // Gather: last 5 Google reviews, last 3 sermon note tones, music genre tags
          const reviewsSnap = await db.collection(`churches/${churchId}/reviews`)
              .orderBy("createdAt", "desc").limit(5).get();
          const reviews = reviewsSnap.docs.map((d) => d.data().text ?? "").filter(Boolean);

          const notesSnap = await db.collection("notes")
              .where("churchId", "==", churchId)
              .orderBy("createdAt", "desc").limit(3).get();
          const noteTones = notesSnap.docs.map((d) => (d.data().keyPoints ?? []).slice(0, 2).join(". "));

          const musicTags = church.musicGenreTags ?? [];

          const context = [
            reviews.length   ? `Recent visitor reviews:\n${reviews.join("\n")}` : "",
            noteTones.length ? `Recent sermon themes:\n${noteTones.join("\n")}`  : "",
            musicTags.length ? `Music style: ${musicTags.join(", ")}`            : "",
          ].filter(Boolean).join("\n\n");

          if (!context.trim()) continue;

          const system = `You are analyzing a church's atmosphere. Based on the data provided, generate exactly one short phrase (max 5 words) describing the Sunday morning vibe. Examples: 'warm and deeply expository', 'high-energy and welcoming', 'quiet and contemplative'. Return only the phrase, nothing else.`;
          const vibe   = (await callClaude(apiKey, system, context, 30, 0.6)).trim();

          if (vibe) {
            await db.doc(`churches/${churchId}`).set({sundayVibe: vibe}, {merge: true});
          }
        } catch (err) {
          console.error(`generateChurchVibe ${churchId}:`, err.message);
        }
      }
    },
);

// ─── COMPUTE CHURCH DNA (on-demand) ──────────────────────────────────────────

exports.computeChurchDNA = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY]},
    async (request) => {
      requireAuth(request);
      const {churchId} = request.data;
      if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

      const db       = admin.firestore();
      const apiKey   = ANTHROPIC_API_KEY.value();
      const notesSnap = await db.collection("notes")
          .where("churchId", "==", churchId)
          .orderBy("createdAt", "desc")
          .limit(50).get();

      const aggregated = notesSnap.docs
          .flatMap((d) => [...(d.data().keyPoints ?? []), ...(d.data().scriptureReferences ?? [])])
          .slice(0, 300)
          .join(". ");

      if (!aggregated.trim()) {
        return {scores: {}};
      }

      const system = `Score this church's sermon content on these 6 axes from 0-100: grace_emphasis, word_centrality, evangelism_focus, holy_spirit_gifts, community_justice, eschatology_urgency. Return only a JSON object with these exact keys and integer values.`;
      const raw    = await callClaude(apiKey, system, aggregated, 200, 0.2);
      const clean  = raw.replace(/```json|```/g, "").trim();

      let scores = {};
      try {
        scores = JSON.parse(clean);
      } catch {
        // Fallback: return empty
      }

      // Cache in Firestore
      await db.doc(`churches/${churchId}`).set(
          {dnaScores: scores, dnaScoresUpdatedAt: admin.firestore.FieldValue.serverTimestamp()},
          {merge: true},
      );

      return {scores};
    },
);

// ─── COMPUTE PRAYER MOMENTUM (weekly) ────────────────────────────────────────

exports.computePrayerMomentum = onSchedule(
    {schedule: "0 3 * * 1", region: REGION},
    async () => {
      const db  = admin.firestore();
      const now = new Date();
      const d90 = new Date(now.getTime() - 90 * 86400000);
      const d180 = new Date(now.getTime() - 180 * 86400000);

      const churchesSnap = await db.collection("churches").limit(200).get();

      for (const doc of churchesSnap.docs) {
        const churchId = doc.id;
        try {
          const recent = await db.collection(`churches/${churchId}/answeredPrayers`)
              .where("answeredAt", ">=", admin.firestore.Timestamp.fromDate(d90)).get();
          const prior  = await db.collection(`churches/${churchId}/answeredPrayers`)
              .where("answeredAt", ">=", admin.firestore.Timestamp.fromDate(d180))
              .where("answeredAt", "<",  admin.firestore.Timestamp.fromDate(d90)).get();

          const recentCount = recent.docs.length;
          const priorCount  = prior.docs.length;

          // Unique uid count for recentCount
          const uniqueUids = new Set(recent.docs.map((d) => d.data().uid)).size;
          if (uniqueUids < 20) continue;

          const percentChange = priorCount > 0 ? ((recentCount - priorCount) / priorCount) * 100 : 0;
          const label = percentChange > 15 ? "rising" : percentChange < -15 ? "quieter" : "steady";

          // Compute 6-month monthly counts
          const counts = [];
          for (let m = 5; m >= 0; m--) {
            const start = new Date(now.getFullYear(), now.getMonth() - m, 1);
            const end   = new Date(now.getFullYear(), now.getMonth() - m + 1, 1);
            const mSnap = await db.collection(`churches/${churchId}/answeredPrayers`)
                .where("answeredAt", ">=", admin.firestore.Timestamp.fromDate(start))
                .where("answeredAt", "<",  admin.firestore.Timestamp.fromDate(end)).get();
            counts.push(mSnap.docs.length);
          }

          await db.doc(`churches/${churchId}`).set({
            prayerMomentum: {
              label, percentChange, sampleSize: uniqueUids,
              last6MonthCounts: counts,
              computedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          }, {merge: true});
        } catch (err) {
          console.error(`computePrayerMomentum ${churchId}:`, err.message);
        }
      }
    },
);

// ─── GENERATE FIRST VISIT GUIDE (on-demand, 30-day cache) ────────────────────

exports.generateFirstVisitGuide = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 60},
    async (request) => {
      requireAuth(request);
      const {churchId, churchName, denomination, memberCount} = request.data;
      if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

      const db     = admin.firestore();
      const apiKey = ANTHROPIC_API_KEY.value();

      // Check 30-day cache
      const docSnap = await db.doc(`churches/${churchId}`).get();
      const cached  = docSnap.data()?.firstVisitGuide;
      if (cached?.cachedAt) {
        const age = Date.now() - cached.cachedAt.toMillis();
        if (age < 30 * 86400000) return cached;
      }

      // Fetch extra context from Firestore
      const sermonSeries = docSnap.data()?.currentSermonSeries ?? "";
      const sundayVibe   = docSnap.data()?.sundayVibe ?? "";

      const prompt = `Generate a first visit guide for ${churchName}. It is a ${denomination || "Christian"} church with ${memberCount || "unknown"} members.${sermonSeries ? ` Their recent sermon series is ${sermonSeries}.` : ""}${sundayVibe ? ` They are known for ${sundayVibe}.` : ""} Structure the response as JSON with these exact keys: parking (string), arrivalTip (string), whatToWear (string), serviceFlow (array of strings, each a time-stamped moment), conversationStarters (array of 3 strings). Return only valid JSON.`;

      const system = "You are a helpful church visitor guide. Be warm, practical, and specific.";
      const raw    = (await callClaude(apiKey, system, prompt, 800, 0.5))
          .replace(/```json|```/g, "").trim();

      let guide = {};
      try { guide = JSON.parse(raw); } catch { guide = {}; }

      // Cache
      await db.doc(`churches/${churchId}`).set(
          {firstVisitGuide: {...guide, cachedAt: admin.firestore.FieldValue.serverTimestamp()}},
          {merge: true},
      );

      return guide;
    },
);

// ─── INFER USER LEARNING STYLE ────────────────────────────────────────────────

exports.inferUserLearningStyle = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY]},
    async (request) => {
      requireAuth(request);
      const uid  = request.auth.uid;
      const db   = admin.firestore();
      const apiKey = ANTHROPIC_API_KEY.value();

      const notesSnap = await db.collection("churchNotes")
          .where("userId", "==", uid)
          .orderBy("date", "desc")
          .limit(20).get();

      if (notesSnap.docs.length < 3) return {style: ""};

      // Compute stats
      const notes = notesSnap.docs.map((d) => d.data());
      const avgLength = notes.reduce((s, n) => s + (n.content?.length ?? 0), 0) / notes.length;
      const listCount = notes.reduce((s, n) => s + ((n.keyPoints?.length ?? 0) > 3 ? 1 : 0), 0);
      const refCount  = notes.reduce((s, n) => s + (n.scriptureReferences?.length ?? 0), 0);
      const applyCount = notes.reduce((s, n) => {
        const c = n.content ?? "";
        return s + (c.match(/\b(I will|this means|apply|action)\b/gi)?.length ?? 0);
      }, 0);

      const stats = `Average note length: ${Math.round(avgLength)} chars. List-heavy notes: ${listCount}/${notes.length}. Scripture refs per note: ${(refCount / notes.length).toFixed(1)}. Application sentences: ${applyCount}.`;

      const system = `Based on these sermon note patterns: ${stats}, classify this note-taker's learning style as one of: analytical, narrative, illustrative, applicational. Return only the word.`;
      const style  = (await callClaude(apiKey, system, stats, 10, 0.1)).trim().toLowerCase();
      const valid  = ["analytical", "narrative", "illustrative", "applicational"];
      const result = valid.includes(style) ? style : "";

      if (result) {
        await db.doc(`users/${uid}`).set({learningStyle: result}, {merge: true});
      }

      return {style: result};
    },
);

// ─── INFER PASTOR STYLE ───────────────────────────────────────────────────────

exports.inferPastorStyle = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY]},
    async (request) => {
      requireAuth(request);
      const {churchId} = request.data;
      if (!churchId) throw new HttpsError("invalid-argument", "churchId is required.");

      const db   = admin.firestore();
      const apiKey = ANTHROPIC_API_KEY.value();

      const cutoff  = new Date(Date.now() - 180 * 86400000);
      const notesSnap = await db.collection("notes")
          .where("churchId", "==", churchId)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(cutoff))
          .limit(50).get();

      if (notesSnap.docs.length < 5) return {style: ""};

      const aggregated = notesSnap.docs
          .flatMap((d) => d.data().keyPoints ?? [])
          .slice(0, 150)
          .join(". ");

      const system = `Based on these sermon notes from the same pastor, classify their teaching style as: structured (clear outlines), expository (verse-by-verse), narrative (story-driven), or topical (theme-based). Return only the word.`;
      const style  = (await callClaude(apiKey, system, aggregated, 10, 0.1)).trim().toLowerCase();
      const valid  = ["structured", "expository", "narrative", "topical"];
      const result = valid.includes(style) ? style : "";

      if (result) {
        await db.doc(`churches/${churchId}`).set({pastorStyle: result}, {merge: true});
      }

      return {style: result};
    },
);
