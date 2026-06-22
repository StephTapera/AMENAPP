//
//  MessageSettings.swift
//  AMENAPP
//
//  Comprehensive message settings model for AMEN app
//  Supports notifications, privacy, safety, and personalization
//

import Foundation
import FirebaseFirestore

// MARK: - Enums

enum MessageRequestPermission: String, Codable, CaseIterable {
    case everyone = "everyone"
    case peopleIFollow = "peopleIFollow"
    case mutualFollowsOnly = "mutualFollowsOnly"
    case trustedConnectionsOnly = "trustedConnectionsOnly"
    case noOne = "noOne"
    
    var displayName: String {
        switch self {
        case .everyone: return "Everyone"
        case .peopleIFollow: return "People I Follow"
        case .mutualFollowsOnly: return "Mutual Follows Only"
        case .trustedConnectionsOnly: return "Trusted Connections Only"
        case .noOne: return "No One"
        }
    }
    
    var description: String {
        switch self {
        case .everyone:
            return "Anyone can send you message requests"
        case .peopleIFollow:
            return "Only people you follow can send requests"
        case .mutualFollowsOnly:
            return "Only people who follow you back can send requests"
        case .trustedConnectionsOnly:
            return "Only verified or church connections can send requests"
        case .noOne:
            return "Turn off message requests completely"
        }
    }
}

enum SafetyMode: String, Codable, CaseIterable {
    case relaxed = "relaxed"
    case standard = "standard"
    case strict = "strict"
    
    var displayName: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .standard: return "Standard"
        case .strict: return "Strict"
        }
    }
    
    var description: String {
        switch self {
        case .relaxed:
            return "Basic filtering and warnings"
        case .standard:
            return "Balanced protection with smart filtering"
        case .strict:
            return "Maximum protection and strict filtering"
        }
    }
}

enum ChatAccentColor: String, Codable, CaseIterable {
    case amenRed = "amenRed"
    case softBlue = "softBlue"
    case forest = "forest"
    case olive = "olive"
    case warmGray = "warmGray"
    case burgundy = "burgundy"
    case gold = "gold"
    
    var displayName: String {
        switch self {
        case .amenRed: return "AMEN Red"
        case .softBlue: return "Soft Blue"
        case .forest: return "Forest"
        case .olive: return "Olive"
        case .warmGray: return "Warm Gray"
        case .burgundy: return "Burgundy"
        case .gold: return "Gold"
        }
    }
}

enum ConversationTint: String, Codable, CaseIterable {
    case off = "off"
    case softTint = "softTint"
    case subtleGlassGradient = "subtleGlassGradient"
    
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .softTint: return "Soft Tint"
        case .subtleGlassGradient: return "Subtle Glass"
        }
    }
}

enum MessageAppearance: String, Codable, CaseIterable {
    case classic = "classic"
    case softGlass = "softGlass"
    case minimal = "minimal"
    
    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .softGlass: return "Soft Glass"
        case .minimal: return "Minimal"
        }
    }
}

// MARK: - Message Settings Model

struct MessageSettings: Codable {
    
    // MARK: - Notifications
    var muteUnknownSenders: Bool
    var notifyForMessageRequests: Bool
    var notifyForGroupMessages: Bool
    var notifyForCalls: Bool
    
    // MARK: - Privacy
    var allowReadReceipts: Bool
    var showTypingIndicators: Bool
    var showActivityStatus: Bool
    var whoCanSendMessageRequests: MessageRequestPermission
    var whoCanCallYou: MessageRequestPermission
    
    // MARK: - Safety
    var safetyMode: SafetyMode
    var filterOffensiveWords: Bool
    var customHiddenWords: [String]
    var blurSensitiveImages: Bool
    var hideMediaFromUnknownSenders: Bool
    var warnAboutSuspiciousLinks: Bool
    var autoLimitRepeatRequests: Bool
    var enableSensitiveContentReview: Bool
    
    // MARK: - Personalization
    var chatAccentColor: ChatAccentColor
    var conversationTint: ConversationTint
    var messageAppearance: MessageAppearance
    
    // MARK: - Metadata
    var lastUpdated: Date
    
    // MARK: - Defaults
    
    static func defaultSettings(isMinor: Bool = false) -> MessageSettings {
        MessageSettings(
            // Notifications
            muteUnknownSenders: true,
            notifyForMessageRequests: false,
            notifyForGroupMessages: true,
            notifyForCalls: true,
            
            // Privacy
            allowReadReceipts: true,
            showTypingIndicators: true,
            showActivityStatus: false,
            whoCanSendMessageRequests: isMinor ? .mutualFollowsOnly : .peopleIFollow,
            whoCanCallYou: .trustedConnectionsOnly,
            
            // Safety
            safetyMode: isMinor ? .strict : .standard,
            filterOffensiveWords: true,
            customHiddenWords: [],
            blurSensitiveImages: true,
            hideMediaFromUnknownSenders: true,
            warnAboutSuspiciousLinks: true,
            autoLimitRepeatRequests: true,
            enableSensitiveContentReview: true,
            
            // Personalization
            chatAccentColor: .amenRed,
            conversationTint: .off,
            messageAppearance: .softGlass,
            
            // Metadata
            lastUpdated: Date()
        )
    }
    
    // MARK: - Firestore Mapping
    
    enum CodingKeys: String, CodingKey {
        case muteUnknownSenders
        case notifyForMessageRequests
        case notifyForGroupMessages
        case notifyForCalls
        case allowReadReceipts
        case showTypingIndicators
        case showActivityStatus
        case whoCanSendMessageRequests
        case whoCanCallYou
        case safetyMode
        case filterOffensiveWords
        case customHiddenWords
        case blurSensitiveImages
        case hideMediaFromUnknownSenders
        case warnAboutSuspiciousLinks
        case autoLimitRepeatRequests
        case enableSensitiveContentReview
        case chatAccentColor
        case conversationTint
        case messageAppearance
        case lastUpdated
    }
}

// MARK: - Validation

extension MessageSettings {
    
    /// Validates settings and returns sanitized version
    func validated() -> MessageSettings {
        var validated = self
        
        // Cap custom hidden words to 100 items, 50 chars each
        validated.customHiddenWords = Array(customHiddenWords
            .prefix(100)
            .map { String($0.prefix(50)).lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )
        
        // If muteUnknownSenders is true, notifyForMessageRequests should default to false
        if validated.muteUnknownSenders {
            validated.notifyForMessageRequests = false
        }
        
        return validated
    }
}
