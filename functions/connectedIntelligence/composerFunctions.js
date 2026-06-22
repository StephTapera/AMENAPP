/**
 * composerFunctions.js — Berean composer @calendar write pipeline (Connected Intelligence v1)
 *
 * Agent D (@Tool Mentions) — Phase 2. Backend half of the @calendar WRITE flow.
 *
 * NEVER a silent write. Two callables enforce drafts_for_approval:
 *
 *   composerCalendarDraft  — Parses natural-language write intent ("schedule prayer
 *                            night Friday") into a structured DRAFT event. Writes the
 *                            draft to berean/{uid}/calendarDrafts/{draftId} with
 *                            status:'pending'. Does NOT touch any external calendar.
 *
 *   composerCalendarCommit — Given a draftId, verifies (a) the user owns it, (b) it is
 *                            still pending, (c) the user holds an ACTIVE, berean-scoped
 *                            ConnectorGrant for `calendar` carrying the write_commit
 *                            scope, then performs event_create. Marks the draft
 *                            'committed'. This is the ConfirmationGate's server side.
 *
 * Invariants enforced here (defense in depth — the client also gates):
 *   - Minor-scoped accounts: BLOCKED from both callables (zero connector writes).
 *   - Grant must be status==='active', unexpired, surfaces include 'berean', scopes
 *     include 'write_commit'. Missing/insufficient ⇒ permission-denied, no write.
 *   - The draft ceiling is drafts_for_approval: a draft is inert until committed.
 *
 * The actual provider event_create is delegated to a pluggable adapter
 * (calendarProviderCreate). Until Agent A/B wires the real Google/EventKit adapter,
 * the default adapter returns a deterministic pointer and records the intended event in
 * berean/{uid}/calendarEvents/{draftId} so nothing is lost and the flow is testable
 * end-to-end WITHOUT a third-party write. Swap the adapter when the provider lands.
 *
 * OWNER: Agent D. The ONLY backend module Agent D may create.
 */

"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret}       = require("firebase-functions/params");
const admin                = require("firebase-admin");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const REGION            = "us-central1";

// ─── Shared helpers ──────────────────────────────────────────────────────────

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return request.auth.uid;
}

/** Minor invariant: zero connector writes for minor-scoped accounts. */
function assertNotMinor(request) {
  const claim = request.auth?.token?.minorScoped;
  if (claim === true || claim === "true") {
    throw new HttpsError(
        "permission-denied",
        "Connector actions are unavailable for this account.",
    );
  }
}

function toEpochMs(value) {
  if (value == null) return null;
  if (typeof value === "number") return value;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.seconds === "number") return value.seconds * 1000;
  return null;
}

/**
 * Loads the user's calendar ConnectorGrant and asserts it unlocks a berean WRITE.
 * Throws permission-denied if the grant is missing/inactive/expired, not berean-scoped,
 * or lacks the write_commit scope.
 */
async function assertCalendarWriteGrant(uid) {
  const db = admin.firestore();
  const snap = await db
      .collection("berean").doc(uid)
      .collection("connectorGrants").doc("calendar")
      .get();

  if (!snap.exists) {
    throw new HttpsError("permission-denied", "Connect your calendar first.");
  }
  const grant = snap.data() || {};

  if (grant.status !== "active") {
    throw new HttpsError("permission-denied", "Calendar access is not active.");
  }
  const surfaces = Array.isArray(grant.surfaces) ? grant.surfaces : [];
  if (!surfaces.includes("berean")) {
    throw new HttpsError(
        "permission-denied",
        "Calendar isn’t shared with Berean. Update access to enable this.",
    );
  }
  const scopes = Array.isArray(grant.scopes) ? grant.scopes : [];
  if (!scopes.includes("write_commit")) {
    throw new HttpsError(
        "permission-denied",
        "Calendar write permission is required to create events.",
    );
  }
  const expiresMs = toEpochMs(grant.expiresAt);
  if (expiresMs !== null && expiresMs <= Date.now()) {
    throw new HttpsError("permission-denied", "Calendar access has expired.");
  }
  return grant;
}

// ─── Claude NL → structured draft ─────────────────────────────────────────────

async function parseDraftWithClaude(apiKey, text) {
  const fetch = (await import("node-fetch")).default;
  const nowISO = new Date().toISOString();

  const system =
    "You convert a short scheduling request into ONE calendar event. " +
    "Return STRICT JSON only, no prose, with keys: " +
    "title (string), startISO (ISO 8601 with timezone offset), " +
    "endISO (ISO 8601 or null), allDay (boolean), " +
    "humanReadable (short plain-English echo), " +
    "lowConfidence (boolean: true if the date/time was ambiguous). " +
    `Resolve relative dates against the current time ${nowISO}. ` +
    "If no explicit time is given, set allDay true and pick a sensible default; " +
    "set lowConfidence true. Never invent attendees, locations, or recurrence.";

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type":      "application/json",
      "x-api-key":         apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model:      "claude-sonnet-4-6",
      max_tokens: 400,
      system,
      messages:   [{role: "user", content: text.slice(0, 1000)}],
      temperature: 0.1,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new HttpsError("internal", `Draft parse failed: ${response.status} ${err}`);
  }
  const json = await response.json();
  const raw = json.content?.[0]?.text ?? "";
  let parsed;
  try {
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    parsed = JSON.parse(raw.slice(start, end + 1));
  } catch (e) {
    throw new HttpsError("internal", "Could not read that into an event.");
  }

  // Validate shape; never fabricate beyond what the model returned.
  if (!parsed.title || !parsed.startISO) {
    throw new HttpsError("invalid-argument", "Couldn’t find an event title or time.");
  }
  return {
    title:         String(parsed.title).slice(0, 200),
    startISO:      String(parsed.startISO),
    endISO:        parsed.endISO ? String(parsed.endISO) : null,
    allDay:        Boolean(parsed.allDay),
    humanReadable: String(parsed.humanReadable || parsed.title).slice(0, 300),
    lowConfidence: Boolean(parsed.lowConfidence),
  };
}

// ─── Pluggable provider adapter (event_create) ────────────────────────────────
// Default adapter records intent in Firestore and returns a pointer WITHOUT calling a
// third-party API. Replace with the real Google Calendar / EventKit adapter when ready.

async function calendarProviderCreate(uid, draft) {
  const db = admin.firestore();
  const ref = db
      .collection("berean").doc(uid)
      .collection("calendarEvents").doc(draft.draftId);
  await ref.set({
    title:        draft.title,
    startISO:     draft.startISO,
    endISO:       draft.endISO,
    allDay:       draft.allDay,
    source:       "berean_composer",
    createdAt:    admin.firestore.FieldValue.serverTimestamp(),
    provider:     "pending_provider_adapter",
  }, {merge: true});

  // Pointer is a deep-link-shaped reference to the source of truth.
  return `amen://calendar/event/${draft.draftId}`;
}

// ─── composerCalendarDraft ────────────────────────────────────────────────────
// Input:  { text: string }
// Output: { ok: boolean, draft: CalendarDraft | null, error?: string }

exports.composerCalendarDraft = onCall(
    {region: REGION, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 30},
    async (request) => {
      const uid = requireAuth(request);
      assertNotMinor(request);

      const text = request.data?.text;
      if (!text || typeof text !== "string" || !text.trim()) {
        return {ok: false, draft: null, error: "Nothing to schedule."};
      }

      try {
        const parsed = await parseDraftWithClaude(ANTHROPIC_API_KEY.value(), text.trim());

        const db = admin.firestore();
        const draftRef = db
            .collection("berean").doc(uid)
            .collection("calendarDrafts").doc();
        const draftId = draftRef.id;

        // drafts_for_approval: persist as PENDING — inert until committed.
        await draftRef.set({
          ...parsed,
          draftId,
          status:    "pending",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {ok: true, draft: {draftId, ...parsed}, error: undefined};
      } catch (err) {
        if (err instanceof HttpsError) {
          // Surface as a degraded result rather than throwing — client shows a chip.
          return {ok: false, draft: null, error: err.message};
        }
        return {ok: false, draft: null, error: "Calendar is unavailable right now."};
      }
    },
);

// ─── composerCalendarCommit ───────────────────────────────────────────────────
// Input:  { draftId: string }
// Output: { ok: boolean, pointer: string | null, error?: string }
// This is the server side of the ConfirmationGate — the ONLY path to event_create.

exports.composerCalendarCommit = onCall(
    {region: REGION, timeoutSeconds: 30},
    async (request) => {
      const uid = requireAuth(request);
      assertNotMinor(request);

      const draftId = request.data?.draftId;
      if (!draftId || typeof draftId !== "string") {
        return {ok: false, pointer: null, error: "Missing draft."};
      }

      try {
        // 1. Verify the grant ALLOWS a berean-scoped write_commit (defense in depth).
        await assertCalendarWriteGrant(uid);

        const db = admin.firestore();
        const draftRef = db
            .collection("berean").doc(uid)
            .collection("calendarDrafts").doc(draftId);

        // 2. Load + validate the draft inside a transaction (idempotent commit).
        const pointer = await db.runTransaction(async (tx) => {
          const snap = await tx.get(draftRef);
          if (!snap.exists) {
            throw new HttpsError("not-found", "That draft no longer exists.");
          }
          const draft = snap.data();
          if (draft.status === "committed") {
            // Idempotent: return the existing pointer, do not double-write.
            return draft.pointer || `amen://calendar/event/${draftId}`;
          }
          if (draft.status !== "pending") {
            throw new HttpsError("failed-precondition", "This draft can’t be confirmed.");
          }

          // 3. event_create via the provider adapter.
          const createdPointer = await calendarProviderCreate(uid, {draftId, ...draft});

          tx.update(draftRef, {
            status:       "committed",
            pointer:      createdPointer,
            committedAt:  admin.firestore.FieldValue.serverTimestamp(),
          });
          return createdPointer;
        });

        return {ok: true, pointer, error: undefined};
      } catch (err) {
        if (err instanceof HttpsError) {
          return {ok: false, pointer: null, error: err.message};
        }
        return {ok: false, pointer: null, error: "Could not create the event. Nothing was written."};
      }
    },
);
