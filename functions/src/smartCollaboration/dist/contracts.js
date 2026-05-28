"use strict";
// contracts.ts
// AMEN Smart Collaboration Layer — TypeScript contracts
//
// Mirrors the Swift types in AmenSmartCollaborationContracts.swift.
// Single source of truth for all Cloud Function request/response shapes
// and Firestore sub-collection paths.
//
// Non-negotiable rules:
//   1. generatedBy is always a service account ID — never the caller's uid.
//   2. requestorId on ThreadPrayerSignal is NEVER returned to non-requestors.
//   3. All AI text fields are written server-side only — never from client payloads.
//   4. No raw message body text in any logged or analytics field.
Object.defineProperty(exports, "__esModule", { value: true });
exports.SmartPaths = void 0;
// MARK: - Firestore Path Helpers
// Mirrors Swift AmenSmartCollaborationPaths — single source of truth.
exports.SmartPaths = {
    // DM thread sub-collections
    dmSmartContext: (conversationId) => `conversations/${conversationId}/smartContext/main`,
    dmSmartActions: (conversationId) => `conversations/${conversationId}/smartActions`,
    dmPrayerSignals: (conversationId) => `conversations/${conversationId}/prayerSignals`,
    dmSummary: (conversationId) => `conversations/${conversationId}/summary/main`,
    dmPresence: (conversationId, userId) => `conversations/${conversationId}/presence/${userId}`,
    // Channel sub-collections
    channelSmartContext: (spaceId, channelId) => `spaces/${spaceId}/channels/${channelId}/smartContext/main`,
    channelSmartActions: (spaceId, channelId) => `spaces/${spaceId}/channels/${channelId}/smartActions`,
    channelPrayerSignals: (spaceId, channelId) => `spaces/${spaceId}/channels/${channelId}/prayerSignals`,
    channelSummary: (spaceId, channelId) => `spaces/${spaceId}/channels/${channelId}/summary/main`,
    channelPresence: (spaceId, channelId, userId) => `spaces/${spaceId}/channels/${channelId}/presence/${userId}`,
    channelPulse: (spaceId, channelId) => `spaces/${spaceId}/channels/${channelId}/pulse/main`,
};
