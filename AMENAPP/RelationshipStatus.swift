//
//  RelationshipStatus.swift
//  AMENAPP
//
//  Created by Production Audit on 2/20/26.
//  P0-1: Unified relationship state enum to prevent state corruption
//

import Foundation

/// Unified relationship status enum that enforces mutual exclusivity
/// Prevents contradictory states like `isFollowing && isBlocked`
enum RelationshipStatus: String, Codable, Equatable {
    case notFollowing = "NOT_FOLLOWING"
    case following = "FOLLOWING"
    case requested = "REQUESTED"           // Private account, follow request pending
    case blocked = "BLOCKED"               // Current user blocked target
    case blockedBy = "BLOCKED_BY"          // Target user blocked current user
    case mutualBlock = "MUTUAL_BLOCK"      // Both users blocked each other
    case selfProfile = "SELF"              // Viewing own profile
    
    /// Whether interaction is allowed with this user
    var isInteractionAllowed: Bool {
        switch self {
        case .notFollowing, .following, .requested:
            return true
        case .blocked, .blockedBy, .mutualBlock:
            return false
        case .selfProfile:
            return true  // Can always interact with own profile
        }
    }
    
    /// Display text for UI buttons
    var displayText: String {
        switch self {
        case .notFollowing:
            return "Follow"
        case .following:
            return "Following"
        case .requested:
            return "Requested"
        case .blocked:
            return "Blocked"
        case .blockedBy, .mutualBlock:
            return "Unavailable"
        case .selfProfile:
            return "Edit Profile"
        }
    }
    
    /// Icon name for button state
    var iconName: String? {
        switch self {
        case .notFollowing:
            return "person.badge.plus"
        case .following:
            return "person.badge.checkmark"
        case .requested:
            return "clock"
        case .blocked:
            return "person.fill.xmark"
        case .blockedBy, .mutualBlock:
            return "exclamationmark.triangle"
        case .selfProfile:
            return "pencil"
        }
    }
    
    /// Whether this state allows viewing profile content
    var canViewProfile: Bool {
        switch self {
        case .notFollowing, .following, .requested, .selfProfile:
            return true
        case .blocked:
            return true  // Can view but not interact
        case .blockedBy, .mutualBlock:
            return false  // Completely blocked
        }
    }
    
    /// Whether this state allows sending messages
    var canSendMessage: Bool {
        switch self {
        case .following, .selfProfile:
            return true
        case .notFollowing, .requested, .blocked, .blockedBy, .mutualBlock:
            return false
        }
    }
    
    /// Whether follower/following counts should be visible
    var shouldShowCounts: Bool {
        switch self {
        case .notFollowing, .following, .requested, .selfProfile:
            return true
        case .blocked:
            return true  // Can see but not interact
        case .blockedBy, .mutualBlock:
            return false
        }
    }
    
    /// Whether posts/content should be visible (respects privacy settings)
    func canViewContent(isPrivate: Bool, isFollowing: Bool) -> Bool {
        switch self {
        case .selfProfile:
            return true  // Always see own content
        case .following:
            return true  // Following always sees content
        case .notFollowing, .requested:
            return !isPrivate  // Only if public
        case .blocked:
            return !isPrivate  // Can see public content even if blocked
        case .blockedBy, .mutualBlock:
            return false  // Cannot see any content
        }
    }
}

// MARK: - Relationship Status Helper

extension RelationshipStatus {
    /// Determine relationship status from boolean flags
    /// Used for migration from old boolean-based system
    static func fromFlags(
        isSelf: Bool,
        isFollowing: Bool,
        isRequested: Bool,
        isBlocked: Bool,
        isBlockedBy: Bool
    ) -> RelationshipStatus {
        // Self profile takes precedence
        if isSelf {
            return .selfProfile
        }
        
        // Mutual block
        if isBlocked && isBlockedBy {
            return .mutualBlock
        }
        
        // Blocked by target
        if isBlockedBy {
            return .blockedBy
        }
        
        // Current user blocked target
        if isBlocked {
            return .blocked
        }
        
        // Follow request pending (private account)
        if isRequested {
            return .requested
        }
        
        // Following
        if isFollowing {
            return .following
        }
        
        // Default: not following
        return .notFollowing
    }
}
