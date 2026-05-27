/**
 * missingFunctions.ts
 *
 * Minimal stubs for Cloud Functions called by the iOS client via httpsCallable()
 * that have no backend implementation yet.
 *
 * Each stub:
 *  - Requires authentication (rejects unauthenticated callers with a clear error)
 *  - Returns an "unimplemented" HttpsError so the client receives a structured error
 *    rather than a silent hang or generic network failure
 *  - Is wired into index.ts via `export * from "./stubs/missingFunctions"`
 *
 * When a feature is built out, delete the stub here and add the real export to index.ts.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";

// ---------------------------------------------------------------------------
// 1. bereanGenericProxy
//    Called by: Feature03_ScriptureEcho, Feature05_AccountabilityThread,
//               Feature06_VoiceDevotional, Feature09_SharedTestimonyDraft,
//               Feature10_PrayerRoomMode, PostComposerServices
//    Purpose: General-purpose Berean AI proxy for features that share a common
//             request/response shape without a dedicated callable.
// ---------------------------------------------------------------------------
export const bereanGenericProxy = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement bereanGenericProxy — route to Anthropic Claude with
    //       feature-specific system prompts based on request.data.feature.
    throw new HttpsError(
      "unimplemented",
      "bereanGenericProxy is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 2. createMediaReflection
//    Called by: AmenMediaReflectionSheet.swift
//    Purpose: Generates an AI-powered reflection on a shared media item.
// ---------------------------------------------------------------------------
export const createMediaReflection = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement createMediaReflection — accept mediaId + context,
    //       call Claude to produce a spiritual reflection, persist to Firestore.
    throw new HttpsError(
      "unimplemented",
      "createMediaReflection is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 3. sermonSnapProxy
//    Called by: BereanSnapService.swift
//    Purpose: AI-powered sermon snap / sermon summary generation.
// ---------------------------------------------------------------------------
export const sermonSnapProxy = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement sermonSnapProxy — accept sermon transcript or recording ID,
    //       call Claude to produce a structured sermon summary (key points, scripture
    //       references, application steps), persist to Firestore.
    throw new HttpsError(
      "unimplemented",
      "sermonSnapProxy is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 4. acceptSafeConnection
//    Called by: SafeConnectionService.swift
//    Purpose: Server-authoritative acceptance of a trust/safety connection request.
// ---------------------------------------------------------------------------
export const acceptSafeConnection = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement acceptSafeConnection — validate request.data.connectionId,
    //       verify caller is the invited party, update connection document to
    //       "accepted", fan-out notifications to both parties.
    throw new HttpsError(
      "unimplemented",
      "acceptSafeConnection is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 5. askAmenCompanion
//    Called by: AskAmenCompanionRouter.swift
//    Purpose: Conversational AI companion endpoint.
// ---------------------------------------------------------------------------
export const askAmenCompanion = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement askAmenCompanion — accept conversational message + history,
    //       call Claude with the Amen Companion system prompt, return reply.
    //       Apply rate limiting and AI usage tracking.
    throw new HttpsError(
      "unimplemented",
      "askAmenCompanion is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 6. bereanShieldAnalyze
//    Called by: BereanShieldService.swift (GUARDIAN content moderation)
//    Purpose: AI-powered content moderation / safety classification.
// ---------------------------------------------------------------------------
export const bereanShieldAnalyze = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement bereanShieldAnalyze — accept text/media content,
    //       run through the Berean Shield pipeline (Perspective API + Claude
    //       harm classification), return SafetyDecision with harm categories.
    throw new HttpsError(
      "unimplemented",
      "bereanShieldAnalyze is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 7. classifyEnvironment
//    Called by: EnvironmentContextService.swift (Spatial Social OS)
//    Purpose: Classifies the user's physical/spatial environment context.
// ---------------------------------------------------------------------------
export const classifyEnvironment = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement classifyEnvironment — accept sensor/location signals from
    //       request.data, return EnvironmentContext (church, home, commute, etc.)
    //       to drive Spatial Social OS adaptive UI and content recommendations.
    throw new HttpsError(
      "unimplemented",
      "classifyEnvironment is not yet available."
    );
  }
);

// ---------------------------------------------------------------------------
// 8. approveMediaMetadata
//    Called by: AmenMediaAIMetadataReviewSheet.swift
//    Purpose: Server-authoritative approval of AI-generated media metadata.
// ---------------------------------------------------------------------------
export const approveMediaMetadata = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    // TODO: Implement approveMediaMetadata — validate request.data.mediaId +
    //       request.data.metadata, verify caller owns the media item, write
    //       approved metadata to mediaMeta/{mediaId} via Admin SDK (never trust
    //       client writes to this collection).
    throw new HttpsError(
      "unimplemented",
      "approveMediaMetadata is not yet available."
    );
  }
);
