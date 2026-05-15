//
//  AmenConnectModels.swift
//  AMENAPP
//
//  Created by Steph on 1/14/26.
//

import Foundation
import SwiftUI
import PhotosUI

// MARK: - Legacy User Profile Model

struct AmenConnectProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var age: Int
    var birthYear: Int
    var bio: String
    var profilePhoto: Data?

    var yearsSaved: Int
    var isBaptized: Bool
    var churchName: String
    var churchCity: String
    var churchState: String

    var interests: [String]
    var denomination: String?
    var lookingFor: String

    var location: String {
        "\(churchCity), \(churchState)"
    }

    var savedDescription: String {
        if yearsSaved == 0 {
            return "Recently saved"
        } else if yearsSaved == 1 {
            return "Saved for 1 year"
        } else {
            return "Saved for \(yearsSaved) years"
        }
    }

    var baptismStatus: String {
        isBaptized ? "Baptized" : "Not yet baptized"
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        age: Int = 18,
        birthYear: Int = 2006,
        bio: String = "",
        profilePhoto: Data? = nil,
        yearsSaved: Int = 0,
        isBaptized: Bool = false,
        churchName: String = "",
        churchCity: String = "",
        churchState: String = "",
        interests: [String] = [],
        denomination: String? = nil,
        lookingFor: String = "Fellowship"
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.birthYear = birthYear
        self.bio = bio
        self.profilePhoto = profilePhoto
        self.yearsSaved = yearsSaved
        self.isBaptized = isBaptized
        self.churchName = churchName
        self.churchCity = churchCity
        self.churchState = churchState
        self.interests = interests
        self.denomination = denomination
        self.lookingFor = lookingFor
    }
}

extension AmenConnectProfile {
    static let sampleProfiles: [AmenConnectProfile] = [
        AmenConnectProfile(
            name: "Sarah Johnson",
            age: 28,
            birthYear: 1998,
            bio: "Designer, community builder, and outdoor person looking for trusted local connection.",
            yearsSaved: 5,
            isBaptized: true,
            churchName: "Grace Community Church",
            churchCity: "Austin",
            churchState: "TX",
            interests: ["Outdoor", "Design", "Photography"],
            denomination: "Non-denominational",
            lookingFor: "Fellowship"
        ),
        AmenConnectProfile(
            name: "Michael Chen",
            age: 32,
            birthYear: 1994,
            bio: "Software engineer, volunteer leader, and mentor for college students.",
            yearsSaved: 10,
            isBaptized: true,
            churchName: "New Life Baptist Church",
            churchCity: "San Jose",
            churchState: "CA",
            interests: ["Music", "Technology", "Mentoring"],
            denomination: "Baptist",
            lookingFor: "Fellowship"
        )
    ]
}

struct AmenConnectFilters {
    var ageRange: ClosedRange<Int> = 18...100
    var maxDistance: Double = 50
    var baptizedOnly: Bool = false
    var denomination: String?
    var lookingFor: String?
    var minYearsSaved: Int = 0
}

// MARK: - Amen Connect Product Model

enum AmenConnectRoom: String, CaseIterable, Identifiable {
    case lobby = "Lobby"
    case discover = "Discover"
    case spaces = "Spaces"
    case dms = "DMs"
    case activity = "Activity"
    case announcements = "Announcements"
    case discussions = "Discussions"
    case meetings = "Meetings"
    case calendar = "Calendar"
    case boards = "Boards"
    case marketplace = "Marketplace"
    case creators = "Creators"
    case safety = "Safety"
    case admin = "Admin"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .lobby: return "sparkles"
        case .discover: return "magnifyingglass"
        case .spaces: return "square.grid.2x2"
        case .dms: return "bubble.left.and.bubble.right"
        case .activity: return "bell.badge"
        case .announcements: return "megaphone"
        case .discussions: return "number"
        case .meetings: return "video"
        case .calendar: return "calendar"
        case .boards: return "rectangle.on.rectangle"
        case .marketplace: return "storefront"
        case .creators: return "person.crop.rectangle.stack"
        case .safety: return "shield.checkered"
        case .admin: return "slider.horizontal.3"
        }
    }
}

enum AmenConnectSpaceType: String, CaseIterable, Codable, Identifiable {
    case church = "Church"
    case ministry = "Ministry"
    case bibleStudy = "Bible Study"
    case college = "College"
    case university = "University"
    case studentGroup = "Student Group"
    case campusOrganization = "Campus Organization"
    case nonprofit = "Nonprofit"
    case neighborhood = "Neighborhood"
    case parentGroup = "Parent Group"
    case volunteerTeam = "Volunteer Team"
    case smallBusiness = "Small Business"
    case eventTeam = "Event Team"
    case personalGroup = "Personal Group"
    case marketplaceGroup = "Marketplace Group"
    case creatorCommunity = "Creator Community"
    case mentorCohort = "Mentor Cohort"
    case classCourse = "Class/Course"

    var id: String { rawValue }
}

enum AmenConnectRole: String, CaseIterable, Codable, Identifiable {
    case owner
    case admin
    case moderator
    case leader
    case mentor
    case creator
    case teacher
    case member
    case paidMember
    case guest
    case youth
    case parentGuardian
    case readOnly

    var id: String { rawValue }
}

enum AmenConnectVisibility: String, Codable, CaseIterable {
    case publicToSpace
    case channelOnly
    case leadersOnly
    case privateGroup
    case anonymous
    case confidential
    case youthProtected
    case paidTier
}

enum AmenConnectSafetyStatus: String, Codable, CaseIterable {
    case pending
    case allowed
    case allowWithWarning
    case needsReview
    case blocked
    case escalated
}

enum AmenConnectAIModerationOutcome: String, Codable, CaseIterable {
    case allow
    case allowWithWarning = "allow_with_warning"
    case suggestRewrite = "suggest_rewrite"
    case requireConfirmation = "require_confirmation"
    case sendToModeration = "send_to_moderation"
    case block
    case escalateToSafety = "escalate_to_safety"
    case showCrisisSupport = "show_crisis_support"
}

enum AmenConnectIntent: String, Codable, CaseIterable, Identifiable {
    case announcement
    case discussion
    case question
    case task
    case event
    case meeting
    case jobPost = "job_post"
    case babysittingRequest = "babysitting_request"
    case tutoringRequest = "tutoring_request"
    case serviceRequest = "service_request"
    case rideRequest = "ride_request"
    case housingRequest = "housing_request"
    case volunteerNeed = "volunteer_need"
    case studyTopic = "study_topic"
    case supportRequest = "support_request"
    case safetyRisk = "safety_risk"
    case decision
    case poll
    case fileResource = "file_resource"
    case mentorshipRequest = "mentorship_request"
    case paidOffer = "paid_offer"
    case productOffer = "product_offer"
    case liveSession = "live_session"
    case bookingRequest = "booking_request"

    var id: String { rawValue }
}

enum AmenConnectMarketplaceCategory: String, CaseIterable, Codable, Identifiable {
    case jobs = "Jobs"
    case babysitting = "Babysitting"
    case tutoring = "Tutoring"
    case services = "Services"
    case rides = "Rides"
    case housing = "Housing"
    case volunteering = "Volunteering"
    case mentorship = "Mentorship"
    case items = "Items"
    case localHelp = "Local Help"
    case digitalProducts = "Digital Products"
    case paidEvents = "Paid Events"
    case bookings = "Bookings"

    var id: String { rawValue }
}

enum AmenConnectProfileType: String, CaseIterable, Codable, Identifiable {
    case creator
    case mentor
    case teacher
    case pastorLeader = "pastor/leader"
    case tutor
    case babysitter
    case coach
    case organization
    case collegeUniversityGroup = "college/university group"
    case communityGroup = "community group"
    case localServiceProvider = "local service provider"
    case nonprofit
    case smallBusiness = "small business"

    var id: String { rawValue }
}

enum AmenConnectTrustBadge: String, CaseIterable, Codable, Identifiable {
    case identityVerified = "Identity Verified"
    case communityVerified = "Community Verified"
    case leaderVerified = "Leader Verified"
    case businessVerified = "Business Verified"
    case mentorVerified = "Mentor Verified"
    case youthSafe = "Youth Safe"
    case backgroundChecked = "Background Checked"
    case organizationVerified = "Organization Verified"
    case safeCreator = "Safe Creator"
    case trustedSeller = "Trusted Seller"
    case verifiedSitter = "Verified Sitter"
    case verifiedTutor = "Verified Tutor"

    var id: String { rawValue }
}

struct AmenConnectSpace: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var type: AmenConnectSpaceType
    var description: String
    var ownerId: String
    var visibility: AmenConnectVisibility
    var safetyMode: String
    var aiEnabled: Bool
    var aiExclusions: [String]
    var memberCount: Int
    var unreadCount: Int
    var nextEventTitle: String?
    var trustBadges: [AmenConnectTrustBadge]
}

struct AmenConnectChannel: Identifiable, Codable, Hashable {
    var id: String
    var spaceId: String
    var name: String
    var type: String
    var visibility: AmenConnectVisibility
    var allowedRoles: [AmenConnectRole]
    var aiSummaryEnabled: Bool
    var unreadCount: Int
    var pinnedMessage: String?
}

struct AmenConnectMessage: Identifiable, Codable, Hashable {
    var id: String
    var channelId: String
    var senderId: String
    var body: String
    var intent: AmenConnectIntent?
    var mentions: [String]
    var reactionCount: Int
    var threadCount: Int
    var safetyStatus: AmenConnectSafetyStatus
    var aiEligible: Bool
    var aiExcluded: Bool
}

struct AmenConnectMeeting: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var hostName: String
    var type: String
    var startsIn: String
    var attendeeCount: Int
    var isPaid: Bool
    var requiresRecordingConsent: Bool
    var safetyStatus: AmenConnectSafetyStatus
}

struct AmenConnectMarketplaceListing: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var category: AmenConnectMarketplaceCategory
    var locationLabel: String
    var compensation: String
    var posterName: String
    var verificationLevel: String
    var safetyStatus: AmenConnectSafetyStatus
    var expiresLabel: String
    var trustBadges: [AmenConnectTrustBadge]
}

struct AmenConnectCreatorProfile: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var type: AmenConnectProfileType
    var bio: String
    var memberCount: Int
    var isPaidEnabled: Bool
    var liveSoonLabel: String?
    var trustBadges: [AmenConnectTrustBadge]
    var safetyStatus: AmenConnectSafetyStatus
}

struct AmenConnectMembershipTier: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var priceLabel: String
    var benefits: [String]
    var accessRules: [String]
    var safetyFlags: [String]
    var moderationStatus: AmenConnectSafetyStatus
}

struct AmenConnectBoard: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var type: String
    var blocks: [String]
    var visibility: AmenConnectVisibility
    var aiEligible: Bool
}

struct AmenConnectActivityItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var detail: String
    var room: AmenConnectRoom
    var isPriority: Bool
    var requiresAction: Bool
}

struct AmenConnectBackendContract: Identifiable, Hashable {
    var id: String { functionName }
    var functionName: String
    var purpose: String
    var serverAuthoritativeFields: [String]
    var collectionsTouched: [String]
}
