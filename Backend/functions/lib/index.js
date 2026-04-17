"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
const admin = __importStar(require("firebase-admin"));
if (!admin.apps.length) {
    admin.initializeApp();
}
// AI Proxy Functions
__exportStar(require("./bereanChatProxy"), exports);
__exportStar(require("./openAIProxy"), exports);
__exportStar(require("./whisperProxy"), exports);
__exportStar(require("./generateDailyVerse"), exports);
// Berean Spiritual Intelligence Layers (System 16)
//   - bereanGenerateStructuredResponse: spiritual state discernment + structured AI response
//   - bereanStudyPassage: Living Scripture Graph hydration (cross-refs, word study, context)
__exportStar(require("./berean/controllers/generateStructuredResponse"), exports);
__exportStar(require("./berean/controllers/studyPassage"), exports);
// Accessibility Intelligence Layer
__exportStar(require("./refineTranslation"), exports);
__exportStar(require("./transformContent"), exports);
// Group Link Functions
__exportStar(require("./groupLinks"), exports);
// Suggested Accounts Rail
__exportStar(require("./suggestedAccounts"), exports);
// Trust + Intelligence (Berean infrastructure)
__exportStar(require("./trustIntelligence"), exports);
// Action Threads — server-authoritative care workflow CRUD
// All state transitions and participant invitations are validated server-side.
__exportStar(require("./actionThreads"), exports);
// Private/Follower Feed Builder
__exportStar(require("./feedBuilder"), exports);
// Server-authoritative feature flags (CRITICAL-3)
// Safety flags are read from Firestore by Cloud Functions — never trusted from the client.
// Must be exported before antiHarassmentEnforcement (which imports from it).
__exportStar(require("./serverFeatureFlags"), exports);
// Anti-Harassment Enforcement — server-side restriction checks on message sends
// CRITICAL-1: Enforces messaging/dm_freeze/no_contact restrictions and block checks
// unconditionally on the server, regardless of the client write path.
__exportStar(require("./antiHarassmentEnforcement"), exports);
// Account Suspension — Firebase Auth disablement for critical harassment tier
// HIGH-2: Auto-suspends accounts when critical/minor-safety queue items are created.
__exportStar(require("./accountSuspension"), exports);
// Safety Reporting — server-side report creation with validation
// HIGH-3: submitReport callable validates reason, verifies evidence, computes
// escalationTier and priority server-side. Direct client writes to userReports
// are now blocked in Firestore rules (allow create: if false).
__exportStar(require("./submitReport"), exports);
// Media Scanning — Cloud Vision SafeSearch on every Storage upload
// HIGH-1: Scans images for CSAM/explicit/violence signals on onFinalize.
// VERY_LIKELY → delete file + suspend account
// LIKELY      → quarantine file + queue for human review
// POSSIBLE    → flag originating document, queue for human review
__exportStar(require("./mediaScanning"), exports);
// Account Deletion — Algolia record removal (App Store Guideline 5.1.1)
// Called by AccountDeletionService during full account deletion flow.
// Deletes the user record from "users" index and all posts from "posts" index.
__exportStar(require("./deleteAlgoliaUser"), exports);
// CRITICAL: Post deletion cascade — cleans up comments, reactions, reposts,
// savedPosts, feed items, Algolia record, and Storage media when a post is deleted.
__exportStar(require("./postDeletionCascade"), exports);
// CRITICAL: Full account deletion cascade — deletes all user content across
// every collection and subcollection (App Store Guideline 5.1.1 compliance).
__exportStar(require("./userAccountDeletionCascade"), exports);
// CRITICAL: Block relationship cleanup — removes follow edges, pending follow
// requests, and restricts shared conversations when a block is created.
__exportStar(require("./blockRelationshipCleanup"), exports);
// Atomic block/unblock — writes to BOTH blockedUsers top-level collection
// (used by antiHarassmentEnforcement) and users/{uid}/blockedUsers subcollection
// (used by Firestore rules) in a single batch. Prevents partial-block drift.
__exportStar(require("./createBlock"), exports);
// Atomic follow/unfollow — writes follows edge doc AND follows_index doc
// (used by callerFollows() in Firestore rules for follower-only content gating)
// in a single batch. Prevents follows_index missing entries that silently break
// follower-only post visibility.
__exportStar(require("./createFollow"), exports);
// Notification Functions — Server-side pipeline
//
// Firestore triggers use gen2 syntax (firebase-functions/v2/firestore) so they
// coexist with gen2 onCall functions in the same deployment.
__exportStar(require("./notifications/onSocialEvent"), exports);
__exportStar(require("./notifications/counts"), exports);
__exportStar(require("./notifications/maintenance"), exports);
__exportStar(require("./notifications/invalidation"), exports);
// 5.4 FIX — Prayer answered fan-out: processes ≤100 supporter batches per
// invocation, eliminating the timeout risk of sequential single-function fan-out.
__exportStar(require("./notifications/prayerAnsweredBatch"), exports);
// 5.6 FIX — Quiet hours digest: scheduled every 30 min to batch-deliver push
// notifications to users whose quiet window has ended.
__exportStar(require("./notifications/deliverQuietHoursDigest"), exports);
// Church Visit Lifecycle — phase-triggered follow-up scheduling and FCM nudges
// Triggered on attended/reflected phase transitions in users/{uid}/churchInteractions/{churchId}
__exportStar(require("./churchVisitLifecycle"), exports);
// Post Creation Finalizer — text moderation, status transition (publishing→published),
// Algolia indexing. Feed fanout for followers-only posts is in feedBuilder.ts.
// Exported as finalizePostOnCreate to avoid conflict with the onPostCreated
// mention-handler in onSocialEvent.ts.
__exportStar(require("./onPostCreated"), exports);
// Algolia sync — keeps "posts" index current on post edit and deletion
__exportStar(require("./algoliaSync"), exports);
// Scheduled maintenance — counter reconciliation, stale data pruning, token cleanup
__exportStar(require("./scheduledMaintenance"), exports);
// Username change rate limiting — 30-day cooldown enforced server-side
// Section-13 FIX: trackUsernameChange trigger writes to userSafetyRecords on
// every username change; usernameChangeCooldownRelease (in scheduledMaintenance)
// re-enables canChangeUsername after 30 days.
__exportStar(require("./usernameChangeTracking"), exports);
// Smart Activity Layer — Followers/Following lists with precomputed activity state
// Triggers: posts/{postId}, prayers/{prayerId}, churchNotes/{noteId} writes
// Callable: markRelationshipSeen (batched seen-state flush from client)
// Scheduled: reconcileRelationshipStates (daily stale doc cleanup)
__exportStar(require("./socialGraph"), exports);
// Creator Functions
__exportStar(require("./creator/createProject"), exports);
__exportStar(require("./creator/updateProject"), exports);
__exportStar(require("./creator/deleteProject"), exports);
__exportStar(require("./creator/autosaveProject"), exports);
__exportStar(require("./creator/queueProcessingJob"), exports);
__exportStar(require("./creator/processVideoProxy"), exports);
__exportStar(require("./creator/generateThumbnail"), exports);
__exportStar(require("./creator/transcribeMedia"), exports);
__exportStar(require("./creator/generateSubtitleTrack"), exports);
__exportStar(require("./creator/translateSubtitleTrack"), exports);
__exportStar(require("./creator/buildOutputVariants"), exports);
__exportStar(require("./creator/renderExport"), exports);
__exportStar(require("./creator/publishProject"), exports);
__exportStar(require("./creator/moderateCreatorAsset"), exports);
__exportStar(require("./creator/verifyAuthenticitySignals"), exports);
__exportStar(require("./creator/saveBrandKit"), exports);
__exportStar(require("./creator/cloneTemplateToProject"), exports);
__exportStar(require("./creator/recordCreatorAnalytics"), exports);
__exportStar(require("./creator/enforceCreatorEntitlement"), exports);
__exportStar(require("./creator/cleanupOrphanedAssets"), exports);
__exportStar(require("./creator/retryFailedCreatorJob"), exports);
//# sourceMappingURL=index.js.map