import * as admin from "firebase-admin";

if (!admin.apps.length) {
    admin.initializeApp();
}

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
