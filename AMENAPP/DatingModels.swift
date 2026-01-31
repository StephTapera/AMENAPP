//
//  DatingModels.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Dating Profile Model

struct DatingProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var userId: String // Link to main user account
    
    // Basic Info
    var name: String
    var age: Int
    var gender: String
    var locationLat: Double?
    var locationLon: Double?
    var locationCity: String
    var photos: [String] // URLs to profile photos
    
    // Faith Information
    var denomination: String
    var churchName: String?
    var churchCity: String?
    var faithLevel: String // "New Believer", "Growing", "Mature"
    var faithYears: Int?
    var testimony: String?
    
    // Preferences & Personality
    var bio: String
    var interests: [String]
    var priorities: [String] // What they value most
    var dealBreakers: [String]
    var lookingFor: String // "Friendship", "Dating", "Marriage"
    
    // Match Preferences
    var preferredGenderToMatch: String
    var preferredAgeMin: Int
    var preferredAgeMax: Int
    var preferredMaxDistance: Double // in miles
    var preferredDenominations: [String]
    var preferredFaithLevels: [String]
    
    // Safety & Verification
    var isPhoneVerified: Bool
    var isChurchVerified: Bool
    var emergencyContact: String?
    var meetingPreference: String // "Video First", "Group Only", "Flexible"
    var reportCount: Int
    var isBanned: Bool
    
    // Metadata
    var createdAt: Date
    var lastActive: Date
    var isOnline: Bool
    
    // Computed properties
    var location: CLLocationCoordinate2D? {
        guard let lat = locationLat, let lon = locationLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var gradientColors: [Color] {
        // Generate colors based on denomination or use default
        switch denomination.lowercased() {
        case "baptist":
            return [Color.blue, Color.cyan]
        case "catholic":
            return [Color.purple, Color.indigo]
        case "pentecostal":
            return [Color.orange, Color.red]
        case "methodist":
            return [Color.green, Color.teal]
        case "non-denominational":
            return [Color.pink, Color.purple]
        default:
            return [Color(red: 0.9, green: 0.3, blue: 0.5), Color(red: 0.6, green: 0.2, blue: 0.8)]
        }
    }
    
    var preferredAgeRange: ClosedRange<Int> {
        return preferredAgeMin...preferredAgeMax
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DatingProfile, rhs: DatingProfile) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Match Model

struct DatingMatch: Identifiable, Codable {
    let id: UUID
    let user1Id: String
    let user2Id: String
    var matchedAt: Date
    var conversationId: String?
    var isActive: Bool
    var user1LastRead: Date?
    var user2LastRead: Date?
    
    // Computed
    var hasUnreadMessages: Bool {
        // This would be determined by comparing message timestamps
        return false
    }
}

// MARK: - Swipe Action Model

struct SwipeAction: Codable {
    let id: UUID
    let swiperId: String // Who swiped
    let profileId: String // Who was swiped on
    let action: SwipeType
    let timestamp: Date
}

enum SwipeType: String, Codable {
    case like
    case pass
    case superLike
}

// MARK: - Dating Message Model

struct DatingMessage: Identifiable, Codable {
    let id: UUID
    let matchId: String
    let senderId: String
    let receiverId: String
    var content: String
    var timestamp: Date
    var isRead: Bool
    var messageType: MessageType
    
    // Computed
    var isFromCurrentUser: Bool {
        // Would check against current user ID
        return false
    }
}

enum MessageType: String, Codable {
    case text
    case icebreaker
    case verseShare
    case videoCallInvite
    case prayerRequest
}

// MARK: - Report Model

enum DatingReportReason: String, Codable, CaseIterable {
    case inappropriate = "Inappropriate Content"
    case fake = "Fake Profile"
    case harassment = "Harassment"
    case safety = "Safety Concern"
    case scam = "Scam or Spam"
    case other = "Other"
}

enum ReviewStatus: String, Codable {
    case pending
    case reviewed
    case actionTaken
    case dismissed
}

struct ProfileReport: Codable {
    let id: UUID
    let reporterId: String
    let reportedProfileId: String
    let reason: DatingReportReason
    let description: String?
    let timestamp: Date
    var reviewStatus: ReviewStatus
}

// MARK: - Profile Filters

struct ProfileFilters: Codable {
    var ageRange: ClosedRange<Int>?
    var maxDistance: Double?
    var denominations: [String]?
    var faithLevels: [String]?
    var mustHaveChurchVerification: Bool
    
    init(
        ageRange: ClosedRange<Int>? = nil,
        maxDistance: Double? = 50,
        denominations: [String]? = nil,
        faithLevels: [String]? = nil,
        mustHaveChurchVerification: Bool = false
    ) {
        self.ageRange = ageRange
        self.maxDistance = maxDistance
        self.denominations = denominations
        self.faithLevels = faithLevels
        self.mustHaveChurchVerification = mustHaveChurchVerification
    }
}

// MARK: - Conversation Summary (for messages list)

struct ConversationSummary: Identifiable {
    let id: UUID
    let matchId: String
    let otherUserProfile: DatingProfile
    let lastMessage: DatingMessage?
    let unreadCount: Int
    
    var timeAgo: String {
        guard let lastMessage = lastMessage else { return "" }
        let interval = Date().timeIntervalSince(lastMessage.timestamp)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - Block Model

struct ProfileBlock: Codable {
    let id: UUID
    let blockerId: String
    let blockedId: String
    let timestamp: Date
}

// MARK: - Notification Model

struct DatingNotification: Identifiable, Codable {
    let id: UUID
    let userId: String
    let type: DatingNotificationType
    let relatedProfileId: String?
    let message: String
    let timestamp: Date
    var isRead: Bool
}

enum DatingNotificationType: String, Codable {
    case newMatch
    case newMessage
    case profileLike
    case profileView
    case verificationComplete
}

// MARK: - Phone Verification Model

struct PhoneVerification: Codable {
    let phoneNumber: String
    let code: String
    let expiresAt: Date
    var attempts: Int
    var isVerified: Bool
}

// MARK: - Sample Data for Development

extension DatingProfile {
    static let sample = DatingProfile(
        id: UUID(),
        userId: "sample-user-1",
        name: "Sarah",
        age: 28,
        gender: "Female",
        locationLat: 37.7749,
        locationLon: -122.4194,
        locationCity: "San Francisco, CA",
        photos: [],
        denomination: "Non-Denominational",
        churchName: "Grace Community Church",
        churchCity: "San Francisco, CA",
        faithLevel: "Growing",
        faithYears: 12,
        testimony: "I found Christ during college and haven't looked back since!",
        bio: "Jesus follower seeking someone to grow in faith with. Love worship music and serving at church!",
        interests: ["Worship", "Bible Study", "Coffee", "Hiking"],
        priorities: ["Faith-centered relationship", "Good communication", "Family values"],
        dealBreakers: ["Different faith", "No church involvement"],
        lookingFor: "Dating",
        preferredGenderToMatch: "Male",
        preferredAgeMin: 25,
        preferredAgeMax: 35,
        preferredMaxDistance: 25,
        preferredDenominations: ["Non-Denominational", "Baptist", "Evangelical"],
        preferredFaithLevels: ["Growing", "Mature"],
        isPhoneVerified: true,
        isChurchVerified: true,
        emergencyContact: "+1234567890",
        meetingPreference: "Video First",
        reportCount: 0,
        isBanned: false,
        createdAt: Date(),
        lastActive: Date(),
        isOnline: true
    )
    
    static func sampleProfiles() -> [DatingProfile] {
        return [
            DatingProfile(
                id: UUID(),
                userId: "user-1",
                name: "Sarah",
                age: 28,
                gender: "Female",
                locationLat: 37.7749,
                locationLon: -122.4194,
                locationCity: "San Francisco, CA",
                photos: [],
                denomination: "Non-Denominational",
                churchName: "Grace Community Church",
                churchCity: "San Francisco, CA",
                faithLevel: "Growing",
                faithYears: 12,
                testimony: nil,
                bio: "Jesus follower seeking someone to grow in faith with. Love worship music and serving at church!",
                interests: ["Worship", "Bible Study", "Coffee", "Hiking"],
                priorities: ["Faith-centered", "Communication"],
                dealBreakers: ["Different faith"],
                lookingFor: "Dating",
                preferredGenderToMatch: "Male",
                preferredAgeMin: 25,
                preferredAgeMax: 35,
                preferredMaxDistance: 25,
                preferredDenominations: [],
                preferredFaithLevels: [],
                isPhoneVerified: true,
                isChurchVerified: true,
                emergencyContact: nil,
                meetingPreference: "Video First",
                reportCount: 0,
                isBanned: false,
                createdAt: Date(),
                lastActive: Date(),
                isOnline: true
            ),
            DatingProfile(
                id: UUID(),
                userId: "user-2",
                name: "Michael",
                age: 32,
                gender: "Male",
                locationLat: 37.7749,
                locationLon: -122.4194,
                locationCity: "Oakland, CA",
                photos: [],
                denomination: "Baptist",
                churchName: "New Life Fellowship",
                churchCity: "Oakland, CA",
                faithLevel: "Mature",
                faithYears: 15,
                testimony: nil,
                bio: "Faith, family, and fitness. Looking for a God-fearing woman to build a life with. Youth pastor with a heart for discipleship.",
                interests: ["Prayer", "Fitness", "Travel", "Music"],
                priorities: ["Spiritual leadership", "Family values"],
                dealBreakers: ["No church involvement"],
                lookingFor: "Marriage",
                preferredGenderToMatch: "Female",
                preferredAgeMin: 24,
                preferredAgeMax: 32,
                preferredMaxDistance: 30,
                preferredDenominations: [],
                preferredFaithLevels: [],
                isPhoneVerified: true,
                isChurchVerified: true,
                emergencyContact: nil,
                meetingPreference: "Flexible",
                reportCount: 0,
                isBanned: false,
                createdAt: Date(),
                lastActive: Date(),
                isOnline: false
            ),
            DatingProfile(
                id: UUID(),
                userId: "user-3",
                name: "Emily",
                age: 25,
                gender: "Female",
                locationLat: 37.7749,
                locationLon: -122.4194,
                locationCity: "Berkeley, CA",
                photos: [],
                denomination: "Catholic",
                churchName: "St. Mary's Cathedral",
                churchCity: "Berkeley, CA",
                faithLevel: "Growing",
                faithYears: 8,
                testimony: nil,
                bio: "Passionate about serving others and growing closer to God daily. Love reading theology and volunteering!",
                interests: ["Volunteering", "Reading", "Art", "Cooking"],
                priorities: ["Shared values", "Kindness"],
                dealBreakers: ["Dishonesty"],
                lookingFor: "Dating",
                preferredGenderToMatch: "Male",
                preferredAgeMin: 23,
                preferredAgeMax: 30,
                preferredMaxDistance: 20,
                preferredDenominations: [],
                preferredFaithLevels: [],
                isPhoneVerified: true,
                isChurchVerified: false,
                emergencyContact: nil,
                meetingPreference: "Group Only",
                reportCount: 0,
                isBanned: false,
                createdAt: Date(),
                lastActive: Date(),
                isOnline: true
            )
        ]
    }
}

extension DatingMessage {
    static let sample = DatingMessage(
        id: UUID(),
        matchId: "match-1",
        senderId: "user-1",
        receiverId: "user-2",
        content: "Hey! How's your day going?",
        timestamp: Date().addingTimeInterval(-120),
        isRead: false,
        messageType: .text
    )
}
