import * as admin from "firebase-admin";

if (!admin.apps.length) {
    admin.initializeApp();
}

// Smart Attachments — resolveSmartAttachment, saveMediaGraphItem, etc.
export * from "./smartAttachments";

// Berean Chat Proxy
export * from "./bereanChatProxy";

// Berean Operating Layer — generateBereanOperatingResponse
export * from "./berean/bereanOperatingLayer";
export * from "./berean/controllers/premiumBereanCallables";

// Church Trust & Safety OS — verification, moderation, grounding, livestream
// submitChurchVerificationRequest, submitChurchProfileUpdate,
// reviewChurchModerationItem, refreshChurchLivestreamState,
// generateGroundedChurchAnswer, syncYouTubeChurchStreams,
// updateChurchLiveSignals, moderateChurchMediaUpload, onChurchVerificationReviewed
export * from "./church/controllers/churchTrustCallables";

// Feed Context — computeFeedContextLabels, attachFeedContextToRankedPosts,
// updateUserContextLabelPreferences, trackContextLabelEvent, suppressContextLabelForUser
export * from "./feedContext";

// Giving OS — saveGivingProfile, submitBenevolenceRequest, getRankedFeed, generateAnnualReview
export * from "./giving/controllers/givingCallables";

// Benevolence Moderation — onBenevolenceRequestCreated, onBenevolenceRequestUpdated
export * from "./giving/controllers/benevolenceModeration";

// Nonprofit Ingestion — dailyNonprofitDataSync, weeklyDisasterEventCleanup, weeklyBenevolenceRequestCleanup
export * from "./giving/controllers/nonprofitIngestion";

// Media Post Index — onMediaPostCreate, onMediaPostUpdate, onMediaPostDelete
export * from "./mediaPostIndex";

// Presence Intelligence — generatePresenceSignals, updatePresencePreferences
export * from "./presence/presenceIntelligence";

// Smart Share — getSmartShareTargets, enforceSharePermissions, createSharePayload,
// generateDeepLink, moderateShareNote, saveToNotes, createReminderPayload,
// generateStoryCard, createChurchNotePreview, notifyRecipients, trackShareEvent,
// deliverSmartShare, saveToCollection, reflectPrivately, createDiscussionThread
export * from "./share/smartShare";
