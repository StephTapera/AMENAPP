// AmenSmartPillEligibilityContext.swift
// AMENAPP
//
// Context inputs for the smart pill eligibility engine (Phase 4B).

import Foundation

struct AmenSmartPillEligibilityContext {
    let conversationId: String
    let messageCount: Int
    let unreadCount: Int
    let lastMessage: AppMessage?
    let selectedMessage: AppMessage?
    let userLanguageCode: String        // ISO 639-1, e.g. "en"
    let isGroupConversation: Bool
    let detectedLanguage: String?       // ISO 639-1 of last non-user message
    let hasVoiceMessage: Bool
    let hasMediaMessage: Bool
    let hasLongText: Bool               // text.count > longMessageCharThreshold
    let safetySignalPresent: Bool
    let transcriptAvailable: Bool
    let isNetworkAvailable: Bool
}
