/**
 * spiritualOSFunctions.js
 * AMEN App — Spiritual OS Cloud Functions (Phase 3)
 *
 * All functions follow the project standard:
 *   - enforceAppCheck: true (App Check required)
 *   - Auth validated via requireAuth()
 *   - UID must match payload userId
 *   - Rate-limited via rateLimiter.js
 *
 * Functions exported:
 *   getSpiritualDigest       — daily digest, AI-personalized
 *   getHubItems              — paginated unified inbox stream
 *   getPlannerEvents         — merged planner calendar
 *   getPlannerSuggestions    — AI formation nudges (max 5/day)
 *   getAssistantResponse     — Berean assistant bar Q&A
 *   updateContextState       — context engine server sync
 *   dismissSuggestion        — user dismisses a nudge
 *   pinHubItem               — user pins/unpins a hub item
 *   cleanupContextOnLogout   — wipe context on logout
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const {checkRateLimit} = require("./rateLimiter");

// ─── Secrets ──────────────────────────────────────────────────────────────────

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// ─── Constants ────────────────────────────────────────────────────────────────

const REGION = "us-central1";
const db = () => admin.firestore();

// ─── Shared auth guard ────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
}

function requireSelf(request, userId) {
  if (request.auth.uid !== userId) {
    throw new HttpsError("permission-denied", "Cannot access another user's data.");
  }
}

// ─── Claude helper ────────────────────────────────────────────────────────────

async function callClaude(apiKey, systemPrompt, userPrompt, maxTokens = 512) {
  const fetch = (await import("node-fetch")).default;
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{role: "user", content: userPrompt}],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Claude error ${response.status}: ${err}`);
  }

  const json = await response.json();
  return json.content?.[0]?.text ?? "";
}

// ─── AI DISCLOSURE LABEL ──────────────────────────────────────────────────────

const AI_DISCLOSURE_LABEL = "Berean AI · powered by Anthropic";

// ─── 1. getSpiritualDigest ────────────────────────────────────────────────────

exports.getSpiritualDigest = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {userId, forceRefresh = false} = request.data;
      requireSelf(request, userId);

      await checkRateLimit(userId, "getSpiritualDigest", 60, 60);

      const now = new Date();
      const hour = now.getUTCHours();
      const timeOfDay =
        hour >= 5 && hour < 12 ? "morning" :
        hour >= 12 && hour < 17 ? "afternoon" :
        hour >= 17 && hour < 21 ? "evening" : "night";

      // Check for existing digest today (unless forceRefresh)
      if (!forceRefresh) {
        const startOfDay = new Date(now);
        startOfDay.setUTCHours(0, 0, 0, 0);

        const existing = await db()
            .collection("spiritualOS_digest")
            .doc(userId)
            .collection("items")
            .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(startOfDay))
            .limit(1)
            .get();

        if (!existing.empty) {
          const items = [];
          const all = await db()
              .collection("spiritualOS_digest")
              .doc(userId)
              .collection("items")
              .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(startOfDay))
              .orderBy("priority", "desc")
              .limit(20)
              .get();

          all.forEach((doc) => items.push({itemId: doc.id, ...doc.data()}));

          return {
            greeting: `Good ${timeOfDay}`,
            items,
            timeOfDay,
            generatedAt: now.toISOString(),
          };
        }
      }

      // Generate greeting via Claude
      let greeting = `Good ${timeOfDay}`;
      try {
        const greetingText = await callClaude(
            ANTHROPIC_API_KEY.value(),
            `You write warm, faith-based greetings for the AMEN app.
Be brief (under 15 words), invitational, non-denominational, and encouraging.
Reference time of day naturally. No exclamation points unless joyful context.
Output ONLY the greeting text, nothing else.`,
            `Write a ${timeOfDay} greeting for a faith-based social app.`,
            40,
        );
        if (greetingText.trim()) greeting = greetingText.trim();
      } catch (_) {
        // Fallback to simple greeting — digest continues without AI greeting
      }

      // Seed a basic verse item as the anchor
      const endOfDay = new Date(now);
      endOfDay.setUTCHours(23, 59, 59, 999);

      const itemRef = db()
          .collection("spiritualOS_digest")
          .doc(userId)
          .collection("items")
          .doc();

      const seedItem = {
        itemId: itemRef.id,
        userId,
        type: "verse",
        title: "Today's verse",
        body: "Your word is a lamp to my feet and a light to my path. — Psalm 119:105",
        sourceRef: null,
        sourceType: "scripture",
        priority: 90,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(endOfDay),
        aegisFlags: null,
      };

      await itemRef.set(seedItem);

      return {
        greeting,
        items: [seedItem],
        timeOfDay,
        generatedAt: now.toISOString(),
      };
    },
);

// ─── 2. getHubItems ───────────────────────────────────────────────────────────

exports.getHubItems = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {userId, lastItemId = null, pageSize = 20, filterType = null} = request.data;
      requireSelf(request, userId);

      await checkRateLimit(userId, "getHubItems", 120, 60);

      const limit = Math.min(pageSize, 30);
      let query = db()
          .collection("spiritualOS_hub")
          .doc(userId)
          .collection("items")
          .where("isArchived", "==", false)
          .orderBy("createdAt", "desc")
          .limit(limit + 1);

      if (filterType) {
        query = query.where("type", "==", filterType);
      }

      if (lastItemId) {
        const cursorDoc = await db()
            .collection("spiritualOS_hub")
            .doc(userId)
            .collection("items")
            .doc(lastItemId)
            .get();
        if (cursorDoc.exists) {
          query = query.startAfter(cursorDoc);
        }
      }

      const snap = await query.get();
      const docs = snap.docs;
      const hasMore = docs.length > limit;
      const items = docs.slice(0, limit).map((d) => ({itemId: d.id, ...d.data()}));

      return {
        items,
        hasMore,
        nextCursor: hasMore ? items[items.length - 1].itemId : null,
      };
    },
);

// ─── 3. getPlannerEvents ──────────────────────────────────────────────────────

exports.getPlannerEvents = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {
        userId,
        startDate,
        endDate,
        includeBereanSuggestions = true,
      } = request.data;
      requireSelf(request, userId);

      await checkRateLimit(userId, "getPlannerEvents", 60, 60);

      const start = new Date(startDate);
      const end = new Date(endDate);

      const snap = await db()
          .collection("spiritualOS_planner")
          .doc(userId)
          .collection("events")
          .where("startDate", ">=", admin.firestore.Timestamp.fromDate(start))
          .where("startDate", "<=", admin.firestore.Timestamp.fromDate(end))
          .where("isCompleted", "==", false)
          .orderBy("startDate", "asc")
          .limit(50)
          .get();

      const events = snap.docs.map((d) => ({eventId: d.id, ...d.data()}));

      let suggestions = [];
      if (includeBereanSuggestions && events.length > 0) {
        const titlesSnippet = events
            .slice(0, 5)
            .map((e) => e.title)
            .join(", ");

        try {
          const raw = await callClaude(
              ANTHROPIC_API_KEY.value(),
              `You suggest gentle faith formation nudges for the AMEN planner.
Tone: warm, invitational, no obligation or guilt. Max 140 chars each.
Output a JSON array of objects: [{"itemId":"","promptLabel":"","bereanNote":"","targetDate":"ISO8601"}]
Return at most 2 suggestions. No markdown, no code block, raw JSON only.`,
              `User has upcoming: ${titlesSnippet}. Suggest 1-2 gentle faith activities.`,
              200,
          );

          const parsed = JSON.parse(raw);
          if (Array.isArray(parsed)) {
            suggestions = parsed.slice(0, 2).map((s) => ({
              itemId: s.itemId || db().collection("_").doc().id,
              promptLabel: (s.promptLabel || "").slice(0, 28),
              bereanNote: (s.bereanNote || "").slice(0, 140),
              targetDate: s.targetDate || startDate,
              aiDisclosureLabel: AI_DISCLOSURE_LABEL,
            }));
          }
        } catch (_) {
          // Suggestions are optional — planner works fine without them
        }
      }

      return {events, suggestions};
    },
);

// ─── 4. getPlannerSuggestions ─────────────────────────────────────────────────

exports.getPlannerSuggestions = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {userId, contextMode = "default", upcomingEventTitles = []} = request.data;
      requireSelf(request, userId);

      // Hard rate limit: max 5 suggestions per user per day (CF-enforced)
      await checkRateLimit(userId, "getPlannerSuggestions_daily", 5, 86400);
      await checkRateLimit(userId, "getPlannerSuggestions", 20, 60);

      const titlesStr = upcomingEventTitles.slice(0, 5).join(", ");

      let suggestions = [];
      try {
        const raw = await callClaude(
            ANTHROPIC_API_KEY.value(),
            `You are Berean, a gentle faith formation assistant for the AMEN app.
Your suggestions are dismissible nudges — never obligations, never guilt-inducing.
Tone: warm, invitational, brief. Output raw JSON array only (no markdown).
Each item: {"surfaceContext":"string","promptLabel":"string (max 28 chars)","promptText":"string (max 200 chars)","priority":number 0-100}`,
            `Context: ${contextMode}. User events: ${titlesStr || "none"}.
Generate 2-3 gentle faith formation suggestions.`,
            400,
        );

        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          suggestions = parsed.slice(0, 3).map((s) => ({
            surfaceContext: s.surfaceContext || "assistantBar",
            promptLabel: (s.promptLabel || "").slice(0, 28),
            promptText: (s.promptText || "").slice(0, 200),
            priority: typeof s.priority === "number" ? Math.max(0, Math.min(100, s.priority)) : 50,
            aiDisclosureLabel: AI_DISCLOSURE_LABEL,
          }));

          // Persist to Firestore for client-side access
          const batch = db().batch();
          const now = admin.firestore.FieldValue.serverTimestamp();
          const expiresAt = admin.firestore.Timestamp.fromDate(
              new Date(Date.now() + 24 * 60 * 60 * 1000),
          );

          suggestions.forEach((s) => {
            const ref = db()
                .collection("spiritualOS_suggestions")
                .doc(userId)
                .collection("items")
                .doc();
            batch.set(ref, {
              itemId: ref.id,
              userId,
              surfaceContext: s.surfaceContext,
              promptLabel: s.promptLabel,
              promptText: s.promptText,
              isDismissed: false,
              priority: s.priority,
              expiresAt,
              createdAt: now,
            });
          });
          await batch.commit();
        }
      } catch (_) {
        // Return empty suggestions on AI failure
      }

      return {suggestions};
    },
);

// ─── 5. getAssistantResponse ──────────────────────────────────────────────────

exports.getAssistantResponse = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {
        userId,
        query,
        queryType = "text",
        surfaceContext = "assistantBar",
        contextMode = "default",
      } = request.data;
      requireSelf(request, userId);

      if (!query || query.length > 1000) {
        throw new HttpsError("invalid-argument", "Query must be 1-1000 characters.");
      }

      await checkRateLimit(userId, "getAssistantResponse", 60, 60);

      const system = `You are Berean, the AMEN app's faith assistant.
Answer questions with scripture, warmth, and humility.
Always cite Bible verses inline when making doctrinal claims (e.g. Romans 8:28).
Never fabricate scripture. Acknowledge uncertainty. Be non-divisive across denominations.
Provide 1-3 suggested follow-up questions at the end.
Current context: ${surfaceContext}, mode: ${contextMode}.
Output raw JSON: {"answer":"string","sources":[{"type":"scripture|community","ref":"string","title":"string","snippet":"string or null"}],"suggestedFollowUps":["string"]}`;

      let answer = "";
      let sources = [];
      let suggestedFollowUps = [];

      try {
        const raw = await callClaude(
            ANTHROPIC_API_KEY.value(),
            system,
            query,
            600,
        );

        const parsed = JSON.parse(raw);
        answer = parsed.answer || raw;
        sources = (parsed.sources || []).slice(0, 5).map((s) => ({
          type: s.type || "scripture",
          ref: s.ref || "",
          title: s.title || "",
          snippet: s.snippet || null,
        }));
        suggestedFollowUps = (parsed.suggestedFollowUps || []).slice(0, 3);
      } catch (_) {
        // On parse failure, use raw text as answer
        try {
          answer = await callClaude(
              ANTHROPIC_API_KEY.value(),
              `You are Berean, a biblical AI assistant. Answer faithfully and cite scripture.`,
              query,
              400,
          );
        } catch (err) {
          throw new HttpsError("internal", "Berean is temporarily unavailable.");
        }
      }

      return {
        answer,
        sources,
        suggestedFollowUps,
        aiDisclosureLabel: AI_DISCLOSURE_LABEL,
      };
    },
);

// ─── 6. updateContextState ────────────────────────────────────────────────────

exports.updateContextState = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {
        userId,
        mode = "default",
        timeOfDay,
        isSundayChurchTime = false,
        isNearChurch = false,
        isDriving = false,
        isTraveling = false,
        lastUpdated,
      } = request.data;
      requireSelf(request, userId);

      await checkRateLimit(userId, "updateContextState", 120, 60);

      // Validate mode
      const validModes = ["default", "worship", "driving", "travel", "focus", "rest",
        "driveMode", "worshipMode", "travelMode", "eveningReflection"];
      const safeMode = validModes.includes(mode) ? mode : "default";

      await db()
          .collection("spiritualOS_context")
          .doc(userId)
          .set({
            userId,
            mode: safeMode,
            timeOfDay: timeOfDay || "morning",
            isSundayChurchTime: Boolean(isSundayChurchTime),
            // isNearChurch is privacy-sensitive — only stored if explicitly true from client
            isNearChurch: Boolean(isNearChurch),
            isDriving: Boolean(isDriving),
            isTraveling: Boolean(isTraveling),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

      return {success: true};
    },
);

// ─── 7. dismissSuggestion ─────────────────────────────────────────────────────

exports.dismissSuggestion = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {userId, itemId, collectionHint = "suggestions"} = request.data;
      requireSelf(request, userId);

      if (!itemId) throw new HttpsError("invalid-argument", "itemId required.");

      await checkRateLimit(userId, "dismissSuggestion", 120, 60);

      const collection = collectionHint === "planner" ?
        "spiritualOS_planner" :
        "spiritualOS_suggestions";

      const subCollection = collectionHint === "planner" ? "events" : "items";

      await db()
          .collection(collection)
          .doc(userId)
          .collection(subCollection)
          .doc(itemId)
          .update({isDismissed: true});

      return {success: true};
    },
);

// ─── 8. pinHubItem ────────────────────────────────────────────────────────────

exports.pinHubItem = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {userId, itemId, isPinned} = request.data;
      requireSelf(request, userId);

      if (!itemId) throw new HttpsError("invalid-argument", "itemId required.");
      if (typeof isPinned !== "boolean") {
        throw new HttpsError("invalid-argument", "isPinned must be boolean.");
      }

      await checkRateLimit(userId, "pinHubItem", 120, 60);

      await db()
          .collection("spiritualOS_hub")
          .doc(userId)
          .collection("items")
          .doc(itemId)
          .update({isPinned});

      return {success: true};
    },
);

// ─── 9. cleanupContextOnLogout ────────────────────────────────────────────────

exports.cleanupContextOnLogout = onCall(
    {region: REGION, enforceAppCheck: true},
    async (request) => {
      requireAuth(request);
      const {userId} = request.data;
      requireSelf(request, userId);

      await checkRateLimit(userId, "cleanupContextOnLogout", 10, 60);

      await db()
          .collection("spiritualOS_context")
          .doc(userId)
          .delete();

      return {success: true};
    },
);
