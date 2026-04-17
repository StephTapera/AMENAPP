import * as admin from "firebase-admin";

if (!admin.apps.length) {
    admin.initializeApp();
}


// AI Proxy Functions
export * from "./bereanChatProxy";
export * from "./openAIProxy";
export * from "./whisperProxy";
export * from "./generateDailyVerse";

// Berean Spiritual Intelligence Layers (System 16)
//   - bereanGenerateStructuredResponse: spiritual state discernment + structured AI response
//   - bereanStudyPassage: Living Scripture Graph hydration (cross-refs, word study, context)
export * from "./berean/controllers/generateStructuredResponse";
export * from "./berean/controllers/studyPassage";

// Accessibility Intelligence Layer
export * from "./refineTranslation";
export * from "./transformContent";

// Group Link Functions
export * from "./groupLinks";

// Suggested Accounts Rail
export * from "./suggestedAccounts";

// Trust + Intelligence (Berean infrastructure)
export * from "./trustIntelligence";

// Action Threads — server-authoritative care workflow CRUD
// All state transitions and participant invitations are validated server-side.
export * from "./actionThreads";

// Private/Follower Feed Builder
export * from "./feedBuilder";

// Server-authoritative feature flags (CRITICAL-3)
// Safety flags are read from Firestore by Cloud Functions — never trusted from the client.
// Must be exported before antiHarassmentEnforcement (which imports from it).
export * from "./serverFeatureFlags";

// Anti-Harassment Enforcement — server-side restriction checks on message sends
// CRITICAL-1: Enforces messaging/dm_freeze/no_contact restrictions and block checks
// unconditionally on the server, regardless of the client write path.
export * from "./antiHarassmentEnforcement";

// Account Suspension — Firebase Auth disablement for critical harassment tier
// HIGH-2: Auto-suspends accounts when critical/minor-safety queue items are created.
export * from "./accountSuspension";

// Safety Reporting — server-side report creation with validation
// HIGH-3: submitReport callable validates reason, verifies evidence, computes
// escalationTier and priority server-side. Direct client writes to userReports
// are now blocked in Firestore rules (allow create: if false).
export * from "./submitReport";

// Media Scanning — Cloud Vision SafeSearch on every Storage upload
// HIGH-1: Scans images for CSAM/explicit/violence signals on onFinalize.
// VERY_LIKELY → delete file + suspend account
// LIKELY      → quarantine file + queue for human review
// POSSIBLE    → flag originating document, queue for human review
export * from "./mediaScanning";

// Account Deletion — Algolia record removal (App Store Guideline 5.1.1)
// Called by AccountDeletionService during full account deletion flow.
// Deletes the user record from "users" index and all posts from "posts" index.
export * from "./deleteAlgoliaUser";

// CRITICAL: Post deletion cascade — cleans up comments, reactions, reposts,
// savedPosts, feed items, Algolia record, and Storage media when a post is deleted.
export * from "./postDeletionCascade";

// CRITICAL: Full account deletion cascade — deletes all user content across
// every collection and subcollection (App Store Guideline 5.1.1 compliance).
export * from "./userAccountDeletionCascade";

// CRITICAL: Block relationship cleanup — removes follow edges, pending follow
// requests, and restricts shared conversations when a block is created.
export * from "./blockRelationshipCleanup";

// Atomic block/unblock — writes to BOTH blockedUsers top-level collection
// (used by antiHarassmentEnforcement) and users/{uid}/blockedUsers subcollection
// (used by Firestore rules) in a single batch. Prevents partial-block drift.
export * from "./createBlock";

// Atomic follow/unfollow — writes follows edge doc AND follows_index doc
// (used by callerFollows() in Firestore rules for follower-only content gating)
// in a single batch. Prevents follows_index missing entries that silently break
// follower-only post visibility.
export * from "./createFollow";

// Notification Functions — Server-side pipeline
//
// Firestore triggers use gen2 syntax (firebase-functions/v2/firestore) so they
// coexist with gen2 onCall functions in the same deployment.
export * from "./notifications/onSocialEvent";
export * from "./notifications/counts";
export * from "./notifications/maintenance";
export * from "./notifications/invalidation";

// 5.4 FIX — Prayer answered fan-out: processes ≤100 supporter batches per
// invocation, eliminating the timeout risk of sequential single-function fan-out.
export * from "./notifications/prayerAnsweredBatch";

// 5.6 FIX — Quiet hours digest: scheduled every 30 min to batch-deliver push
// notifications to users whose quiet window has ended.
export * from "./notifications/deliverQuietHoursDigest";

// Church Visit Lifecycle — phase-triggered follow-up scheduling and FCM nudges
// Triggered on attended/reflected phase transitions in users/{uid}/churchInteractions/{churchId}
export * from "./churchVisitLifecycle";

// Church Journey System — full Find Church → Plan → Notes → Reflection orchestration
// createChurchJourney, updateChurchJourneyTiming, promoteJourneyToPrepActive,
// promoteJourneyToArrived, generateReflectionSeedFromNotes,
// scheduleMidweekReflectionReminder, learnChurchRoutine,
// cleanupStaleChurchJourneys, generatePrepSuggestions
export * from "./churchJourney";

// Post Creation Finalizer — text moderation, status transition (publishing→published),
// Algolia indexing. Feed fanout for followers-only posts is in feedBuilder.ts.
// Exported as finalizePostOnCreate to avoid conflict with the onPostCreated
// mention-handler in onSocialEvent.ts.
export * from "./onPostCreated";

// Algolia sync — keeps "posts" index current on post edit and deletion
export * from "./algoliaSync";

// Scheduled maintenance — counter reconciliation, stale data pruning, token cleanup
export * from "./scheduledMaintenance";

// Username change rate limiting — 30-day cooldown enforced server-side
// Section-13 FIX: trackUsernameChange trigger writes to userSafetyRecords on
// every username change; usernameChangeCooldownRelease (in scheduledMaintenance)
// re-enables canChangeUsername after 30 days.
export * from "./usernameChangeTracking";

// Smart Activity Layer — Followers/Following lists with precomputed activity state
// Triggers: posts/{postId}, prayers/{prayerId}, churchNotes/{noteId} writes
// Callable: markRelationshipSeen (batched seen-state flush from client)
// Scheduled: reconcileRelationshipStates (daily stale doc cleanup)
export * from "./socialGraph";

// Creator Functions
export * from "./creator/createProject";
export * from "./creator/updateProject";
export * from "./creator/deleteProject";
export * from "./creator/autosaveProject";
export * from "./creator/queueProcessingJob";
export * from "./creator/processVideoProxy";
export * from "./creator/generateThumbnail";
export * from "./creator/transcribeMedia";
export * from "./creator/generateSubtitleTrack";
export * from "./creator/translateSubtitleTrack";
export * from "./creator/buildOutputVariants";
export * from "./creator/renderExport";
export * from "./creator/publishProject";
export * from "./creator/moderateCreatorAsset";
export * from "./creator/verifyAuthenticitySignals";
export * from "./creator/saveBrandKit";
export * from "./creator/cloneTemplateToProject";
export * from "./creator/recordCreatorAnalytics";
export * from "./creator/enforceCreatorEntitlement";
export * from "./creator/cleanupOrphanedAssets";
export * from "./creator/retryFailedCreatorJob";
