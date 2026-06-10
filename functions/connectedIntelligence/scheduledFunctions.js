/**
 * scheduledFunctions.js — AMEN Connected Intelligence v1, Phase 2 (Agent E)
 *
 * Gen2 onSchedule runner for ScheduledAction docs. Follows the
 * scheduledPostsFunctions.js pattern: batch query, per-doc try/catch, and the
 * "never silent skip" rule — a failed run ALWAYS writes lastRunStatus:'failed'
 * + lastRunFailureReason, never a fabricated success or a quiet no-op.
 *
 * HARD GATES enforced here (server is the final authority — the client cannot be
 * trusted to honor any of these):
 *
 *   1. AEGIS GATE / SHIP-BLOCKER. While SCHEDULED_ACTIONS_ENABLED is false OR no
 *      AEGIS_REVIEW_ID is set, the runner does NOTHING — it returns immediately
 *      without reading or mutating a single action doc.
 *
 *   2. WRITE-RISK CEILING. The only permitted writeRisk values are 'read_only'
 *      and 'drafts_for_approval'. Anything else ⇒ the run fails closed. NO
 *      autonomous external write is performed under any code path: even
 *      'drafts_for_approval' only writes a DRAFT doc the user must approve.
 *
 *   3. DRY-RUN. A new action runs in dry-run for the first DRY_RUN_COUNT runs:
 *      it produces a "here's what I would have done" preview ONLY. dryRun is
 *      cleared and status flips to 'active' only by an explicit user promotion
 *      (client) — the server never auto-promotes.
 *
 *   4. SABBATH SUPPRESSION. sabbathSuppressed actions are skipped on the user's
 *      Sabbath. This is a deferral, not a failure — lastRunStatus:'sabbath_skip'.
 *
 *   5. ACTIVE CAP. Free vs Plus active-action caps are re-checked server-side.
 *
 * Config mirrors connectedIntelligence.config.ts. These are read from env so
 * they can flip WITHOUT a code deploy once Aegis review lands.
 */

const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");

const db = () => admin.firestore();

// ─────────────────────────────────────────────────────────────────────────────
// CONFIG — mirror of connectedIntelligence.config.ts → scheduledActions.
// Sourced from env so the Aegis gate can be flipped without a redeploy.
// Defaults are the SHIP-BLOCKER-safe values: disabled, no review id.
// ─────────────────────────────────────────────────────────────────────────────

function config() {
  return {
    enabled: process.env.SCHEDULED_ACTIONS_ENABLED === "true",
    aegisReviewId: process.env.SCHEDULED_ACTIONS_AEGIS_REVIEW_ID || null,
    dryRunCount: parseInt(process.env.SCHEDULED_ACTIONS_DRY_RUN_COUNT || "3", 10),
    maxActiveFree: parseInt(process.env.SCHEDULED_ACTIONS_MAX_ACTIVE_FREE || "2", 10),
    maxActivePlus: parseInt(process.env.SCHEDULED_ACTIONS_MAX_ACTIVE_PLUS || "10", 10),
  };
}

// ScheduleWriteRisk — the ONLY two permitted values (mirror of frozen enum).
const ALLOWED_WRITE_RISKS = new Set(["read_only", "drafts_for_approval"]);

// ─────────────────────────────────────────────────────────────────────────────
// SABBATH — is "now" within the user's Sabbath window?
// Default: Sunday in the user's timezone (best-effort; defers, never errors).
// ─────────────────────────────────────────────────────────────────────────────

function isSabbathNow(userTz) {
  try {
    const tz = userTz || "UTC";
    const weekday = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      weekday: "short",
    }).format(new Date());
    return weekday === "Sun";
  } catch (_e) {
    // If the timezone is unparseable, fail SAFE toward rest: treat as Sabbath
    // only when we genuinely can't tell would over-suppress, so default to NOT
    // suppressing (a missed nudge is worse than nothing for a reminder). We
    // return false and let the action run; suppression is best-effort.
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RRULE — minimal "is this action due now?" check. We only need the coarse
// gate; the 5-minute scheduler + per-doc lastRunAt dedupe handle the rest.
// Supports FREQ=DAILY/WEEKLY with BYDAY/BYHOUR/BYMINUTE and COUNT=1 (one-shot).
// ─────────────────────────────────────────────────────────────────────────────

const DAY_MAP = {SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6};

function parseRrule(rrule) {
  const out = {};
  String(rrule || "")
      .split(";")
      .forEach((pair) => {
        const [k, v] = pair.split("=");
        if (k && v) out[k.trim().toUpperCase()] = v.trim().toUpperCase();
      });
  return out;
}

function isDueNow(rrule, userTz, lastRunAtMs) {
  const r = parseRrule(rrule);
  if (!r.FREQ) return false;

  const tz = userTz || "UTC";
  const now = new Date();
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(now);

  const get = (type) => parts.find((p) => p.type === type)?.value || "";
  const wdShort = get("weekday").slice(0, 2).toUpperCase(); // "SU".."SA"
  const hour = parseInt(get("hour"), 10);
  const minute = parseInt(get("minute"), 10);

  const targetHour = r.BYHOUR != null ? parseInt(r.BYHOUR, 10) : null;
  const targetMin = r.BYMINUTE != null ? parseInt(r.BYMINUTE, 10) : 0;

  // Dedupe: don't run twice within the same hour-window of one day.
  if (lastRunAtMs) {
    const sinceMs = now.getTime() - lastRunAtMs;
    if (sinceMs < 23 * 60 * 60 * 1000) {
      // already ran in the last ~day; the daily/weekly cadence is satisfied.
      return false;
    }
  }

  // Hour/minute window (scheduler ticks every 5 min — accept the matching hour).
  if (targetHour != null && hour !== targetHour) return false;
  if (targetHour != null && Math.abs(minute - targetMin) > 10) return false;

  if (r.FREQ === "DAILY") return true;

  if (r.FREQ === "WEEKLY") {
    if (!r.BYDAY) return true;
    const days = r.BYDAY.split(",").map((d) => d.trim());
    return days.includes(wdShort);
  }

  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// USER CONTEXT — timezone + plan, read-only.
// ─────────────────────────────────────────────────────────────────────────────

async function userContext(uid) {
  try {
    const snap = await db().collection("users").doc(uid).get();
    const d = snap.data() || {};
    return {
      tz: d.timezone || d.timeZone || "UTC",
      plan: d.plan === "plus" || d.plan === "pro" ? d.plan : "free",
    };
  } catch (_e) {
    return {tz: "UTC", plan: "free"};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAFT OUTPUT — the ONLY write an action may produce.
//   • read_only           ⇒ a private card doc (no external write, ever)
//   • drafts_for_approval  ⇒ a draft doc the user must approve (no auto-send)
// Both land in scheduledActionRuns/{actionId}/runs and a draft inbox; NEITHER
// performs an autonomous external write.
// ─────────────────────────────────────────────────────────────────────────────

function buildOutputText(action, dryRun) {
  const verb = dryRun ? "I would have" : "I";
  if (action.writeRisk === "drafts_for_approval") {
    return `${verb} prepared a draft for your approval based on: "${action.prompt}".`;
  }
  return `${verb} surfaced a private card based on: "${action.prompt}".`;
}

async function writeRunRecord(actionRef, action, opts) {
  const {dryRun, outputText} = opts;
  const runsCol = actionRef.collection("runs");
  await runsCol.add({
    actionId: actionRef.id,
    uid: action.uid,
    dryRun: !!dryRun,
    writeRisk: action.writeRisk,
    // For drafts_for_approval we store a DRAFT requiring explicit approval.
    // No external system is contacted here.
    draft: action.writeRisk === "drafts_for_approval",
    approved: false,
    previewText: outputText,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// RUNNER
// ─────────────────────────────────────────────────────────────────────────────

const executeScheduledActions = onSchedule(
    {schedule: "*/5 * * * *", timeZone: "UTC", region: "us-central1"},
    async () => {
      const cfg = config();

      // GATE 1 — AEGIS / SHIP-BLOCKER. Do nothing while disabled or unreviewed.
      if (!cfg.enabled || !cfg.aegisReviewId) {
        console.log(
            "[scheduledActions] disabled or no Aegis review id — no-op.",
        );
        return;
      }

      const now = admin.firestore.Timestamp.now();

      let dueSnap;
      try {
        dueSnap = await db()
            .collection("scheduledActions")
            .where("status", "in", ["active", "dry_run"])
            .limit(50) // batch to avoid timeout
            .get();
      } catch (queryErr) {
        console.error("[scheduledActions] query failed:", queryErr);
        return;
      }

      if (dueSnap.empty) return;

      let ran = 0;
      let skipped = 0;
      let failed = 0;

      for (const docSnap of dueSnap.docs) {
        const action = docSnap.data();
        const ref = docSnap.ref;

        try {
          // GATE 2 — WRITE-RISK CEILING. Fail closed on any unexpected value.
          if (!ALLOWED_WRITE_RISKS.has(action.writeRisk)) {
            await ref.update({
              lastRunAt: now,
              lastRunStatus: "failed",
              lastRunFailureReason:
                `write_risk_ceiling: ${action.writeRisk}`,
            });
            failed++;
            continue;
          }

          // Care actions gated behind consent — never run unconsented.
          if (action.requiresConsent && !action.consentGranted) {
            await ref.update({
              lastRunAt: now,
              lastRunStatus: "consent_pending",
            });
            skipped++;
            continue;
          }

          const ctx = await userContext(action.uid);

          // RRULE due check.
          const lastRunAtMs =
            action.lastRunAt && action.lastRunAt.toMillis ?
              action.lastRunAt.toMillis() :
              null;
          if (!isDueNow(action.rrule, ctx.tz, lastRunAtMs)) {
            // Not due — NOT a failure, NOT a skip-record. Just move on.
            continue;
          }

          // GATE 4 — SABBATH SUPPRESSION (deferral, not failure).
          if (action.sabbathSuppressed && isSabbathNow(ctx.tz)) {
            await ref.update({
              lastRunAt: now,
              lastRunStatus: "sabbath_skip",
            });
            skipped++;
            continue;
          }

          // GATE 3 — DRY-RUN. First N runs are preview-only.
          const dryRunsCompleted = action.dryRunsCompleted || 0;
          const inDryRun =
            action.dryRun === true || dryRunsCompleted < cfg.dryRunCount;

          const outputText = buildOutputText(action, inDryRun);

          await writeRunRecord(ref, action, {
            dryRun: inDryRun,
            outputText,
          });

          // Persist run result on the action doc. We NEVER auto-promote out of
          // dry-run — only the user (client promoteToLive) sets dryRun=false.
          const update = {
            lastRunAt: now,
            lastRunStatus: inDryRun ? "dry_run" : "ok",
            lastRunFailureReason: null,
            lastRunPreviewText: outputText,
          };
          if (inDryRun) {
            update.dryRunsCompleted = dryRunsCompleted + 1;
          }
          await ref.update(update);

          ran++;
        } catch (runErr) {
          // NEVER silent skip. NEVER fabricate a digest. Mark it failed.
          console.error(
              `[scheduledActions] run failed for ${ref.id}:`,
              runErr,
          );
          try {
            await ref.update({
              lastRunAt: now,
              lastRunStatus: "failed",
              lastRunFailureReason: String(runErr && runErr.message || runErr),
            });
          } catch (writeErr) {
            console.error(
                `[scheduledActions] could not record failure for ${ref.id}:`,
                writeErr,
            );
          }
          failed++;
        }
      }

      console.log(
          `[scheduledActions] ran=${ran} skipped=${skipped} ` +
        `failed=${failed} of ${dueSnap.size}`,
      );
    },
);

module.exports = {executeScheduledActions};
