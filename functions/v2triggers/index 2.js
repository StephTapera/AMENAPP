"use strict";

/**
 * v2triggers/index.js
 *
 * Entry point for the "v2triggers" Firebase codebase.
 *
 * ── HOW THIS WORKS ────────────────────────────────────────────────────────────
 * Before Firebase deploys this codebase, the predeploy hook in firebase.json
 * runs prepare-deploy.sh, which copies the following files from functions/ into
 * this directory:
 *
 *   v2entry.js, v2functions.js, v2intelligenceFunctions.js,
 *   shabbatMiddleware.js, intelligence/ (full directory)
 *
 * This makes the codebase self-contained at deploy time. Node.js then resolves
 * all require() calls within this directory without needing the parent.
 *
 * ── WHY THIS CODEBASE EXISTS ─────────────────────────────────────────────────
 * The Firebase CLI infers function generation from the SDK imports in each file.
 * When a file imports from firebase-functions/v2/scheduler or
 * firebase-functions/v2/database, the CLI applies v2 CPU/concurrency settings
 * to ALL functions in that file — including any Gen-1 callables.
 *
 * The "default" codebase (functions/index.js) stays Gen-1 clean for its many
 * callable exports. This codebase handles ONLY Gen-2 trigger-style functions.
 *
 * ── FUNCTIONS DEPLOYED FROM THIS CODEBASE ────────────────────────────────────
 *   From v2functions.js:
 *     • onRealtimeCommentCreate       (RTDB onValueCreated trigger)
 *     • onMessageSent                 (Firestore onDocumentCreated trigger)
 *     • sendDailyNotificationDigest   (onSchedule — 8am UTC daily)
 *
 *   From v2intelligenceFunctions.js:
 *     • buildDailyIntelligenceBriefs  (onSchedule — 7am + 7pm UTC)
 *     • getIntelligenceBrief          (onCall — also in default codebase)
 *     • recordIntelligenceAction      (onCall — also in default codebase)
 *
 * ── DEPLOY COMMANDS ───────────────────────────────────────────────────────────
 * Deploy all v2 triggers:
 *   firebase deploy --only functions:v2triggers --project amen-5e359
 *
 * Deploy only the intelligence scheduler:
 *   firebase deploy \
 *     --only "functions:v2triggers:buildDailyIntelligenceBriefs" \
 *     --project amen-5e359
 *
 * Deploy only notification triggers:
 *   firebase deploy \
 *     --only "functions:v2triggers:onRealtimeCommentCreate,functions:v2triggers:onMessageSent,functions:v2triggers:sendDailyNotificationDigest" \
 *     --project amen-5e359
 */

module.exports = require("./v2entry");
