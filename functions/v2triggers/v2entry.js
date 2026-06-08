"use strict";

/**
 * v2entry.js
 *
 * Aggregates all Gen-2 (Firebase Functions v2) trigger-style exports for the
 * "v2triggers" Firebase codebase.
 *
 * ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────────
 * The Firebase CLI infers function generation from the SDK each file imports.
 * When a file imports from firebase-functions/v2/scheduler or
 * firebase-functions/v2/database, the CLI applies v2 CPU/concurrency settings
 * to ALL functions exported from that file.
 *
 * index.js must stay Gen-1 clean for its large set of callable exports.
 * Scheduled triggers and RTDB/Firestore event triggers live here instead.
 *
 * ── HOW THIS FILE IS DEPLOYED ────────────────────────────────────────────────
 * This file is the entry point for the "v2triggers" codebase defined in
 * firebase.json. Before deploy, prepare-deploy.sh copies this file and its
 * dependencies (v2functions.js, v2intelligenceFunctions.js, shabbatMiddleware.js,
 * intelligence/) into functions/v2triggers/, making the bundle self-contained.
 *
 * At runtime, all require() calls below use ./ (same directory) because this
 * file has been copied into functions/v2triggers/ by the predeploy hook.
 *
 * ── EXPORTS ───────────────────────────────────────────────────────────────────
 * v2functions.js:
 *   • onRealtimeCommentCreate       — RTDB onValueCreated trigger
 *   • onMessageSent                 — Firestore onDocumentCreated trigger
 *   • sendDailyNotificationDigest   — onSchedule (8am UTC daily)
 *
 * v2intelligenceFunctions.js:
 *   • buildDailyIntelligenceBriefs  — onSchedule (7am + 7pm UTC)
 *   • getIntelligenceBrief          — onCall callable
 *   • recordIntelligenceAction      — onCall callable
 */

// ── v2functions: notification triggers + scheduled digest ─────────────────────
const v2 = require("./v2functions");
exports.onRealtimeCommentCreate       = v2.onRealtimeCommentCreate;
exports.onMessageSent                 = v2.onMessageSent;
exports.sendDailyNotificationDigest   = v2.sendDailyNotificationDigest;

// ── v2intelligenceFunctions: scheduled brief + callables ──────────────────────
const v2intel = require("./v2intelligenceFunctions");
exports.buildDailyIntelligenceBriefs  = v2intel.buildDailyIntelligenceBriefs;
exports.getIntelligenceBrief          = v2intel.getIntelligenceBrief;
exports.recordIntelligenceAction      = v2intel.recordIntelligenceAction;

// ── biblicalAlignmentFunctions: callable + scheduled alignment ────────────────
// NOTE: attachSharedKnowledgeIntegrity, voteKnowledgeIntegrity,
// getWeeklyAlignmentSummary, updateAlignmentProfile are owned by the creator
// codebase (Backend/functions) and must not be re-exported here.
exports.checkBiblicalAlignment           = v2.checkBiblicalAlignment;
exports.suggestBiblicalRewrite           = v2.suggestBiblicalRewrite;
exports.saveAICorrection                 = v2.saveAICorrection;
exports.getDiscernmentPrompt             = v2.getDiscernmentPrompt;
exports.generateWeeklyAlignmentSummary   = v2.generateWeeklyAlignmentSummary;

// NOTE: feedContextFunctions (computeFeedContextLabels, attachFeedContextToRankedPosts,
// updateUserContextLabelPreferences, trackContextLabelEvent, suppressContextLabelForUser)
// are owned by the creator codebase (Backend/functions) and must not be re-exported here.

// ── smartInboxDenormalization: per-message inbox metadata triggers ─────────────
exports.onMessageCreatedForSmartInbox    = v2.onMessageCreatedForSmartInbox;
exports.onMessageCreatedClearsNeedsReply = v2.onMessageCreatedClearsNeedsReply;

// ── Berean v1 callables (2026-06-07) ──────────────────────────────────────────
// bereanChat          — main Berean answer callable (routes through callModel)
// bereanMemory        — memory summarization callable (berean_memory_summarize)
// bereanCrisisDetect  — crisis detection only; AI answer never returned; T&S gate
// bereanBibleLookup   — server-side Bible API proxy (BIBLE_API_KEY stays server-side)
exports.bereanChat         = v2.bereanChat;
exports.bereanMemory       = v2.bereanMemory;
exports.bereanCrisisDetect = v2.bereanCrisisDetect;
exports.bereanBibleLookup  = v2.bereanBibleLookup;

// ── Selah callables (2026-06-07) ──────────────────────────────────────────────
// indexSelahNote       — indexes a SelahNote into the user's private Pinecone namespace
// querySelahCorpus     — retrieves semantically similar notes from the user's namespace
// runDiscernmentCheck  — NeMo → verse fetch → Claude → validate → Firestore save
// shareDiscernmentCheck — promote a private discernment check to 'shared' (NeMo re-check)
exports.indexSelahNote        = v2.indexSelahNote;
exports.querySelahCorpus      = v2.querySelahCorpus;
exports.runDiscernmentCheck   = v2.runDiscernmentCheck;
exports.shareDiscernmentCheck = v2.shareDiscernmentCheck;

// ── 242hub triggers ───────────────────────────────────────────────────────────
exports.flockIntelligence      = v2.flockIntelligence;
exports.processSermonMemory    = v2.processSermonMemory;
exports.reviewPrayerSubmission = v2.reviewPrayerSubmission;
