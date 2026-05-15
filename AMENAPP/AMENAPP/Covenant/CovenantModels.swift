import Foundation
import FirebaseFirestore

// MARK: - Covenant

struct Covenant: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var name: String
    var tagline: String
    var description: String
    var coverImageURL: String?
    var avatarURL: String?
    var tiers: [CovenantTier]
    var operatingMode: CovenantOperatingMode
    var trustBadges: [TrustBadgeType]
    var memberCount: Int
    var paidMemberCount: Int
    var isPublic: Bool
    var isPaused: Bool
    var createdAt: Timestamp
    var updatedAt: Timestamp
}

// MARK: - Covenant Tier

struct CovenantTier: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var price: Double
    var currency: String
    var billingPeriod: BillingPeriod
    var description: String
    var perks: [String]
    var roomAccess: [String]
    var isPopular: Bool

    enum BillingPeriod: String, Codable, CaseIterable {
        case monthly, annual, oneTime = "one_time"
        var displayLabel: String {
            switch self {
            case .monthly: return "/month"
            case .annual:  return "/year"
            case .oneTime: return " one-time"
            }
        }
    }
}

// MARK: - Covenant Operating Mode

enum CovenantOperatingMode: String, Codable, CaseIterable {
    case teaching, prayer, event, quiet, launch

    var displayName: String {
        switch self {
        case .teaching: return "Teaching Mode"
        case .prayer:   return "Prayer Mode"
        case .event:    return "Event Mode"
        case .quiet:    return "Quiet Mode"
        case .launch:   return "Launch Mode"
        }
    }

    var icon: String {
        switch self {
        case .teaching: return "book.fill"
        case .prayer:   return "hands.sparkles.fill"
        case .event:    return "calendar.badge.plus"
        case .quiet:    return "moon.fill"
        case .launch:   return "arrow.up.right.circle.fill"
        }
    }

    var tintColor: String {
        switch self {
        case .teaching: return "blue"
        case .prayer:   return "purple"
        case .event:    return "orange"
        case .quiet:    return "gray"
        case .launch:   return "green"
        }
    }
}

// MARK: - Covenant Room

struct CovenantRoom: Identifiable, Codable {
    @DocumentID var id: String?
    var covenantId: String
    var name: String
    var description: String
    var type: RoomType
    var isLocked: Bool
    var requiredTierId: String?
    var creatorOnly: Bool
    var slowModeSeconds: Int
    var unreadCount: Int
    var lastMessage: String?
    var lastMessageAt: Timestamp?
    var createdAt: Timestamp

    enum RoomType: String, Codable, CaseIterable {
        case announcements, prayer, study, qa = "q_and_a", community
        case events, innerCircle = "inner_circle", moderators

        var displayName: String {
            switch self {
            case .announcements: return "Announcements"
            case .prayer:        return "Prayer"
            case .study:         return "Study"
            case .qa:            return "Q&A"
            case .community:     return "Community"
            case .events:        return "Events"
            case .innerCircle:   return "Inner Circle"
            case .moderators:    return "Moderators"
            }
        }

        var icon: String {
            switch self {
            case .announcements: return "megaphone.fill"
            case .prayer:        return "hands.sparkles.fill"
            case .study:         return "book.fill"
            case .qa:            return "questionmark.bubble.fill"
            case .community:     return "bubble.left.and.bubble.right.fill"
            case .events:        return "calendar"
            case .innerCircle:   return "circle.hexagongrid.fill"
            case .moderators:    return "shield.fill"
            }
        }
    }
}

// MARK: - Covenant Message

struct CovenantMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var covenantId: String
    var roomId: String
    var authorId: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    var body: String
    var mentions: [MentionEntity]
    var replyCount: Int
    var lastReplyAt: Timestamp?
    var participantsPreview: [String]
    var aiThreadSummary: String?
    var threadLocked: Bool
    var reactions: [String: Int]
    var isPinned: Bool
    var isDeleted: Bool
    var deletedAt: Timestamp?
    var deletedBy: String?
    var deletionReason: String?
    var createdAt: Timestamp
}

// MARK: - Thread Reply

struct CovenantThreadReply: Identifiable, Codable {
    @DocumentID var id: String?
    var covenantId: String
    var roomId: String
    var parentMessageId: String
    var authorId: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    var body: String
    var mentions: [MentionEntity]
    var isMarkedAnswer: Bool
    var createdAt: Timestamp
}

// MARK: - Mention Entity

struct MentionEntity: Codable, Identifiable {
    var id: String { "\(type.rawValue)-\(entityId)-\(range.location)" }
    var type: MentionType
    var entityId: String
    var display: String
    var range: MentionRange

    enum MentionType: String, Codable {
        case user, creator, room, everyone, paid, tier
    }

    struct MentionRange: Codable {
        var location: Int
        var length: Int
    }
}

// MARK: - Covenant Activity

struct CovenantActivity: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var type: ActivityType
    var title: String
    var body: String
    var covenantId: String?
    var roomId: String?
    var postId: String?
    var threadId: String?
    var eventId: String?
    var deepLink: String
    var isRead: Bool
    var priority: ActivityPriority
    var groupId: String?
    var createdAt: Timestamp
    var expiresAt: Timestamp?

    enum ActivityType: String, Codable {
        case mention, reply, creatorAnnouncement = "creator_announcement"
        case newPaidPost = "new_paid_post", eventReminder = "event_reminder"
        case prayerFollowUp = "prayer_follow_up", moderationNotice = "moderation_notice"
        case tierUpdate = "tier_update", digestReady = "digest_ready"
        case roomInvite = "room_invite"

        var displayName: String {
            switch self {
            case .mention:              return "Mentioned You"
            case .reply:                return "Replied to You"
            case .creatorAnnouncement:  return "Creator Announcement"
            case .newPaidPost:          return "New Post"
            case .eventReminder:        return "Upcoming Event"
            case .prayerFollowUp:       return "Prayer Follow-Up"
            case .moderationNotice:     return "Moderation Notice"
            case .tierUpdate:           return "Tier Update"
            case .digestReady:          return "Digest Ready"
            case .roomInvite:           return "Room Invite"
            }
        }

        var icon: String {
            switch self {
            case .mention:             return "at"
            case .reply:               return "bubble.left.fill"
            case .creatorAnnouncement: return "megaphone.fill"
            case .newPaidPost:         return "doc.richtext.fill"
            case .eventReminder:       return "calendar.badge.clock"
            case .prayerFollowUp:      return "hands.sparkles.fill"
            case .moderationNotice:    return "shield.lefthalf.filled"
            case .tierUpdate:          return "crown.fill"
            case .digestReady:         return "newspaper.fill"
            case .roomInvite:          return "arrow.right.circle.fill"
            }
        }
    }

    enum ActivityPriority: String, Codable {
        case low, normal, high, urgent
    }
}

// MARK: - Prayer Request

struct CovenantPrayerRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var sourceMessageId: String?
    var covenantId: String
    var roomId: String?
    var authorUserId: String
    var body: String
    var visibility: PrayerVisibility
    var prayedCount: Int
    var followUpRequested: Bool
    var lastUpdateAt: Timestamp?
    var status: PrayerStatus
    var createdAt: Timestamp

    enum PrayerVisibility: String, Codable {
        case `public`, membersOnly = "members_only", anonymous
    }

    enum PrayerStatus: String, Codable {
        case open, updated, answered, closed
        var displayLabel: String {
            switch self {
            case .open:     return "Open"
            case .updated:  return "Updated"
            case .answered: return "Answered"
            case .closed:   return "Closed"
            }
        }
        var color: String {
            switch self {
            case .open:     return "blue"
            case .updated:  return "orange"
            case .answered: return "green"
            case .closed:   return "gray"
            }
        }
    }
}

// MARK: - Moderation Queue

struct CovenantModerationItem: Identifiable, Codable {
    @DocumentID var id: String?
    var covenantId: String
    var contentType: ContentType
    var contentId: String
    var contentSnippet: String
    var reportCount: Int
    var reportReasons: [String]
    var status: ModerationStatus
    var assignedTo: String?
    var resolvedBy: String?
    var resolvedAt: Timestamp?
    var auditLog: [ModerationAuditEntry]
    var createdAt: Timestamp

    enum ContentType: String, Codable {
        case message, threadReply = "thread_reply", post, profile
    }

    enum ModerationStatus: String, Codable {
        case pending, reviewing, approved, blocked, escalated, requestEdit = "request_edit"
        var displayLabel: String {
            switch self {
            case .pending:     return "Pending"
            case .reviewing:   return "Under Review"
            case .approved:    return "Approved"
            case .blocked:     return "Blocked"
            case .escalated:   return "Escalated"
            case .requestEdit: return "Edit Requested"
            }
        }
    }
}

struct ModerationAuditEntry: Codable {
    var action: String
    var performedBy: String
    var note: String?
    var timestamp: Timestamp
}

// MARK: - Trust Badge

enum TrustBadgeType: String, Codable, CaseIterable {
    case verifiedCreator = "verified_creator"
    case churchVerified = "church_verified"
    case ministryVerified = "ministry_verified"
    case healthyCommunity = "healthy_community"
    case newCommunity = "new_community"
    case moderatedRoom = "moderated_room"
    case paidMembersOnly = "paid_members_only"
    case sensitiveTopic = "sensitive_topic"

    var displayName: String {
        switch self {
        case .verifiedCreator:   return "Verified Creator"
        case .churchVerified:    return "Church Verified"
        case .ministryVerified:  return "Ministry Verified"
        case .healthyCommunity:  return "Healthy Community"
        case .newCommunity:      return "New Community"
        case .moderatedRoom:     return "Moderated"
        case .paidMembersOnly:   return "Paid Members Only"
        case .sensitiveTopic:    return "Sensitive Topic"
        }
    }

    var icon: String {
        switch self {
        case .verifiedCreator:   return "checkmark.seal.fill"
        case .churchVerified:    return "building.columns.fill"
        case .ministryVerified:  return "cross.fill"
        case .healthyCommunity:  return "heart.fill"
        case .newCommunity:      return "sparkles"
        case .moderatedRoom:     return "shield.fill"
        case .paidMembersOnly:   return "crown.fill"
        case .sensitiveTopic:    return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .verifiedCreator:   return "blue"
        case .churchVerified:    return "purple"
        case .ministryVerified:  return "indigo"
        case .healthyCommunity:  return "green"
        case .newCommunity:      return "orange"
        case .moderatedRoom:     return "teal"
        case .paidMembersOnly:   return "yellow"
        case .sensitiveTopic:    return "red"
        }
    }
}

// MARK: - Covenant Membership

struct CovenantMembership: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var covenantId: String
    var tierId: String?
    var role: MemberRole
    var status: MembershipStatus
    var joinedAt: Timestamp
    var expiresAt: Timestamp?
    var privacySetting: MemberPrivacy

    enum MemberRole: String, Codable {
        case member, moderator, admin, creator
    }

    enum MembershipStatus: String, Codable {
        case active, trialing, pastDue = "past_due", canceled, paused
        var isActive: Bool { self == .active || self == .trialing }
    }

    enum MemberPrivacy: String, Codable {
        case visible, membersOnly = "members_only", hidden
    }
}

// MARK: - Churn Signal

struct CovenantMemberSignal: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var covenantId: String
    var churnRisk: ChurnRisk
    var reasons: [String]
    var suggestedAction: String?
    var computedAt: Timestamp

    enum ChurnRisk: String, Codable {
        case low, medium, high
    }
}

// MARK: - Content Calendar

struct CovenantScheduledContent: Identifiable, Codable {
    @DocumentID var id: String?
    var covenantId: String
    var targetType: TargetType
    var payload: [String: String]
    var scheduledAt: Timestamp
    var status: ScheduleStatus
    var createdBy: String
    var createdAt: Timestamp

    enum TargetType: String, Codable {
        case post, story, event, devotional, studyDrop = "study_drop", digestHighlight = "digest_highlight"
        var displayName: String {
            switch self {
            case .post:            return "Post"
            case .story:           return "Story"
            case .event:           return "Event"
            case .devotional:      return "Devotional"
            case .studyDrop:       return "Study Drop"
            case .digestHighlight: return "Digest Highlight"
            }
        }
    }

    enum ScheduleStatus: String, Codable {
        case scheduled, published, failed, canceled
    }
}

// MARK: - Onboarding

struct CovenantOnboarding: Codable {
    var welcomeTitle: String
    var welcomeBody: String
    var featuredPostIds: [String]
    var recommendedRoomIds: [String]
    var introPrompt: String
    var rules: [String]
    var updatedAt: Timestamp
}

// MARK: - Covenant Analytics

struct CovenantAnalytics: Codable {
    var covenantId: String
    var dateKey: String
    var monthlyRecurringRevenue: Double
    var paidMemberCount: Int
    var freeMemberCount: Int
    var trialingCount: Int
    var pastDueCount: Int
    var canceledCount: Int
    var churnRiskCount: Int
    var tierDistribution: [String: Int]
    var topContentIds: [String]
    var eventConversionRate: Double
    var roomEngagementRate: Double
}

// MARK: - Report

struct CovenantReport: Identifiable, Codable {
    @DocumentID var id: String?
    var reporterId: String
    var covenantId: String?
    var contentType: String
    var contentId: String
    var reason: ReportReason
    var additionalNote: String?
    var status: ReportStatus
    var assignedTo: String?
    var createdAt: Timestamp

    enum ReportReason: String, Codable, CaseIterable {
        case harassment, spam, misinformation, financialManipulation = "financial_manipulation"
        case sexualContent = "sexual_content", hatefulContent = "hateful_content"
        case selfHarmConcern = "self_harm_concern", spiritualAbuse = "spiritual_abuse", other

        var displayName: String {
            switch self {
            case .harassment:            return "Harassment"
            case .spam:                  return "Spam"
            case .misinformation:        return "Misinformation"
            case .financialManipulation: return "Financial Manipulation"
            case .sexualContent:         return "Sexual Content"
            case .hatefulContent:        return "Hateful Content"
            case .selfHarmConcern:       return "Self-Harm Concern"
            case .spiritualAbuse:        return "Unsafe Spiritual Abuse"
            case .other:                 return "Other"
            }
        }
    }

    enum ReportStatus: String, Codable {
        case submitted, reviewing, resolved, dismissed
    }
}

// MARK: - Creator Verification

struct CreatorVerificationRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var creatorId: String
    var userId: String
    var type: VerificationType
    var status: VerificationStatus
    var submittedAt: Timestamp
    var reviewedAt: Timestamp?
    var reviewerId: String?

    enum VerificationType: String, Codable {
        case identity, church, ministry
        var displayName: String {
            switch self {
            case .identity: return "Identity Verified"
            case .church:   return "Church Verified"
            case .ministry: return "Ministry Verified"
            }
        }
    }

    enum VerificationStatus: String, Codable {
        case pending, approved, rejected, moreInfoNeeded = "more_info_needed"
    }
}

// MARK: - Catch-Up Summary

struct CovenantCatchUpSummary: Codable {
    var covenantId: String
    var roomId: String?
    var threadId: String?
    var since: Date
    var summary: String
    var decisions: [String]
    var prayerUpdates: [String]
    var unansweredQuestions: [String]
    var upcomingEvents: [String]
    var suggestedActions: [String]
}

// MARK: - Deep Link Route

enum CovenantDeepLinkRoute: Equatable {
    case covenantHome(covenantId: String)
    case room(covenantId: String, roomId: String)
    case post(covenantId: String, postId: String)
    case event(covenantId: String, eventId: String)
    case creator(creatorId: String)
    case digest(digestId: String)
}

// MARK: - Search

enum CovenantSearchScope: String, CaseIterable {
    case all, posts, rooms, messages, events, scripture, creators
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .all:       return "magnifyingglass"
        case .posts:     return "doc.richtext"
        case .rooms:     return "bubble.left.and.bubble.right"
        case .messages:  return "text.bubble"
        case .events:    return "calendar"
        case .scripture: return "book"
        case .creators:  return "person.crop.circle"
        }
    }
}

struct CovenantSearchResult: Identifiable {
    var id: String
    var scope: CovenantSearchScope
    var title: String
    var subtitle: String?
    var imageURL: String?
    var deepLink: CovenantDeepLinkRoute?
    var isLocked: Bool
}
