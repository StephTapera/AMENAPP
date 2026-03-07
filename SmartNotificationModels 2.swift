import Combine
import FirebaseFirestore

// MARK: - Notification Priority & Routing Models

/// Priority score (0.0-1.0) determines delivery channel and urgency
struct SmartNotificationPriority: Codable {
    let score: Double  // 0.0-1.0
    let level: PriorityLevel
    let factors: [PriorityFactor]
    let timestamp: Date
    
    enum PriorityLevel: String, Codable {
        case critical   // 0.8-1.0: Push immediately (DM from close friend, direct question)
        case high       // 0.6-0.8: Push with slight delay (reply, prayer update)
        case medium     // 0.4-0.6: In-app only (reactions, reposts)
        case low        // 0.2-0.4: Digest (follows, generic reactions)
        case minimal    // 0.0-0.2: Suppress or weekly digest
    }
    
    struct PriorityFactor: Codable {
        let type: FactorType
        let weight: Double
        let reason: String
        
        enum FactorType: String, Codable {
            case relationship      // Close friend vs stranger
            case intent           // Question vs passive action
            case safety           // Harassment/spam risk
            case userPreference   // Hey Feed mode, quiet hours
            case recency          // Time-sensitive content
            case engagement       // User's past behavior with this person
        }
    }
}

/// Delivery channel and timing
struct SmartNotificationRouting: Codable {
    let channel: DeliveryChannel
    let deliverAt: Date
    let collapseKey: String?  // For APNs/FCM grouping
    let priority: SmartNotificationPriority
    let ttl: TimeInterval  // Time-to-live in seconds
    
    enum DeliveryChannel: String, Codable {
        case push          // Immediate push notification
        case inApp         // In-app notification feed only
        case digest        // Bundle into digest (daily/twice daily)
        case silent        // Update badge only, no alert
        case suppress      // Don't notify at all (spam/harassment)
    }
}

/// User's notification preferences
struct SmartNotificationPreferences: Codable {
    var mode: NotificationMode = .meaningful
    var quietHours: QuietHours?
    var sundayMode: Bool = false  // Extra quiet on Sundays
    var categorySettings: [NotificationCategory: CategorySetting] = [:]
    var digestCadence: DigestCadence = .daily
    var lockScreenPrivacy: LockScreenPrivacy = .minimal
    
    enum NotificationMode: String, Codable {
        case meaningful  // Default: Only what matters
        case balanced    // Some extra notifications
        case everything  // All activity
    }
    
    struct QuietHours: Codable {
        var startTime: String  // "22:00"
        var endTime: String    // "08:00"
        var enabled: Bool
    }
    
    enum DigestCadence: String, Codable {
        case realtime    // No bundling
        case twiceDaily  // Morning + Evening
        case daily       // Once per day
        case weekly      // Sunday summary
    }
    
    enum LockScreenPrivacy: String, Codable {
        case full       // Show full message content
        case minimal    // "You have a message from Jordan"
        case nameOnly   // "You have a new message"
    }
}

/// Notification categories with individual controls
enum NotificationCategory: String, Codable, CaseIterable {
    case directMessages
    case replies
    case mentions
    case reactions
    case follows
    case prayerUpdates
    case churchNotes
    case reposts
    case groupMessages
    case crisisAlerts  // Always critical
    
    var defaultSetting: SmartNotificationPreferences.CategorySetting {
        switch self {
        case .directMessages, .crisisAlerts:
            return .init(mode: .meaningful, pushEnabled: true, soundEnabled: true)
        case .replies, .mentions, .prayerUpdates:
            return .init(mode: .meaningful, pushEnabled: true, soundEnabled: false)
        case .reactions, .reposts:
            return .init(mode: .balanced, pushEnabled: false, soundEnabled: false)
        case .follows:
            return .init(mode: .balanced, pushEnabled: false, soundEnabled: false)
        case .churchNotes:
            return .init(mode: .balanced, pushEnabled: true, soundEnabled: false)
        case .groupMessages:
            return .init(mode: .meaningful, pushEnabled: true, soundEnabled: true)
        }
    }
}

extension SmartNotificationPreferences {
    struct CategorySetting: Codable {
        var mode: CategoryMode
        var pushEnabled: Bool
        var soundEnabled: Bool
        var badgeEnabled: Bool = true
        
        enum CategoryMode: String, Codable {
            case meaningful   // Only important notifications
            case balanced     // Some notifications
            case everything   // All notifications
            case off          // Disabled
        }
    }
}

// MARK: - Actionable Notification Models

/// Payload for rich, actionable notifications
struct ActionableNotificationPayload: Codable {
    let id: String
    let category: NotificationCategory
    let title: String
    let body: String
    let privacyLevel: SmartNotificationPreferences.LockScreenPrivacy
    let deepLink: String
    let actions: [NotificationAction]
    let collapseKey: String?
    let metadata: [String: String]
    let expiresAt: Date?
    
    /// Generate privacy-safe display text
    func displayText(for privacyLevel: SmartNotificationPreferences.LockScreenPrivacy, senderName: String?) -> (title: String, body: String) {
        switch privacyLevel {
        case .full:
            return (title, body)
        case .minimal:
            if let sender = senderName {
                return ("New \(category.displayName)", "From \(sender)")
            }
            return ("New \(category.displayName)", "Tap to view")
        case .nameOnly:
            return ("New \(category.displayName)", "Tap to view")
        }
    }
}

/// Quick actions available in notification
struct NotificationAction: Codable {
    let id: String
    let title: String
    let type: ActionType
    let destructive: Bool
    let requiresAuth: Bool
    let icon: String?
    
    enum ActionType: String, Codable {
        // Message actions
        case reply
        case mute
        case markAsRequest
        case block
        
        // Follow actions
        case acceptFollow
        case declineFollow
        
        // Prayer actions
        case markPrayed
        case sendEncouragement
        
        // Comment actions
        case replyToComment
        case restrictUser
        case hideComment
        
        // Thread actions
        case muteThread
        case unmuteThread
    }
}

extension NotificationCategory {
    var displayName: String {
        switch self {
        case .directMessages: return "Message"
        case .replies: return "Reply"
        case .mentions: return "Mention"
        case .reactions: return "Reaction"
        case .follows: return "Follow"
        case .prayerUpdates: return "Prayer Update"
        case .churchNotes: return "Church Note"
        case .reposts: return "Repost"
        case .groupMessages: return "Group Message"
        case .crisisAlerts: return "Crisis Alert"
        }
    }
}

// MARK: - Digest Models

/// Bundled notification digest
struct NotificationDigest: Codable, Identifiable {
    let id: String
    let userId: String
    let period: DigestPeriod
    let items: [DigestItem]
    let createdAt: Date
    let deliveredAt: Date?
    let opened: Bool
    
    struct DigestPeriod: Codable {
        let start: Date
        let end: Date
        let type: SmartNotificationPreferences.DigestCadence
    }
    
    struct DigestItem: Codable, Identifiable {
        var id: String { category.rawValue }
        let category: NotificationCategory
        let count: Int
        let preview: [String]  // First few items
        let deepLinks: [String]
    }
    
    var summary: String {
        let categories = items.map { "\($0.count) \($0.category.displayName.lowercased())\($0.count == 1 ? "" : "s")" }
        return categories.joined(separator: ", ")
    }
}

// MARK: - Relationship Context

/// User relationship scoring for priority calculation
struct RelationshipContext: Codable {
    let targetUserId: String
    let relationshipScore: Double  // 0.0-1.0
    let factors: [Factor]
    let computedAt: Date
    
    struct Factor: Codable {
        let type: FactorType
        let value: Double
        let weight: Double
        
        enum FactorType: String, Codable {
            case mutualFollow        // Following each other
            case messagingHistory    // DM conversation depth
            case sharedPrayers       // Prayed together
            case engagement          // Likes/comments
            case sharedChurch        // Same church community
            case responseRate        // How often they respond to you
            case recency             // Recent interaction
        }
    }
    
    var level: RelationshipLevel {
        switch relationshipScore {
        case 0.8...1.0: return .closeFriend
        case 0.6..<0.8: return .friend
        case 0.4..<0.6: return .acquaintance
        case 0.2..<0.4: return .distant
        default: return .stranger
        }
    }
    
    enum RelationshipLevel: String, Codable {
        case closeFriend    // High priority
        case friend
        case acquaintance
        case distant
        case stranger       // Low priority
    }
}

// MARK: - Intent Detection

/// Content intent analysis for priority scoring
struct ContentIntent: Codable {
    let type: IntentType
    let confidence: Double  // 0.0-1.0
    let signals: [String]
    
    enum IntentType: String, Codable {
        case question           // Requires response
        case directRequest      // Asking for something
        case urgentUpdate       // Time-sensitive
        case casualEngagement   // Like, reaction
        case informational      // FYI
        case spam              // Low quality
    }
    
    var priorityBoost: Double {
        switch type {
        case .question, .directRequest: return 0.3
        case .urgentUpdate: return 0.2
        case .informational: return 0.0
        case .casualEngagement: return -0.1
        case .spam: return -0.5
        }
    }
}

// MARK: - Smart Mute Suggestions

/// Intelligent mute recommendations
struct MuteSuggestion: Codable, Identifiable {
    let id: String
    let threadId: String
    let reason: MuteReason
    let suggestedDuration: TimeInterval
    let confidence: Double
    let activitySpike: ActivitySpike?
    
    enum MuteReason: String, Codable {
        case activitySpike     // Thread suddenly very active
        case repeatedNotifications  // Same people/topic repeatedly
        case offHours          // Late night activity
        case lowEngagement     // You're not participating
    }
    
    struct ActivitySpike: Codable {
        let normalRate: Double  // Messages per hour
        let currentRate: Double
        let duration: TimeInterval
    }
    
    var displayMessage: String {
        switch reason {
        case .activitySpike:
            return "This thread is very active. Mute for \(durationString)?"
        case .repeatedNotifications:
            return "You're getting a lot of notifications from this. Mute for \(durationString)?"
        case .offHours:
            return "Activity after quiet hours. Mute until morning?"
        case .lowEngagement:
            return "You haven't responded recently. Mute for \(durationString)?"
        }
    }
    
    private var durationString: String {
        let hours = Int(suggestedDuration / 3600)
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}

// MARK: - Collapse Keys

/// Generate collapse keys for notification grouping
struct NotificationCollapseKey {
    static func generate(category: NotificationCategory, entityId: String?, userId: String) -> String {
        switch category {
        case .directMessages:
            // Collapse by conversation
            return "dm_\(entityId ?? userId)"
        case .reactions:
            // Collapse by post
            return "reactions_\(entityId ?? "all")"
        case .follows:
            // Collapse all follows
            return "follows_\(userId)"
        case .replies:
            // Collapse by parent post
            return "replies_\(entityId ?? "all")"
        case .prayerUpdates:
            // Collapse by prayer
            return "prayer_\(entityId ?? "all")"
        case .mentions:
            // Don't collapse mentions
            return "mention_\(UUID().uuidString)"
        case .churchNotes:
            // Collapse by church
            return "church_\(entityId ?? "all")"
        case .reposts:
            // Collapse by original post
            return "repost_\(entityId ?? "all")"
        case .groupMessages:
            // Collapse by group
            return "group_\(entityId ?? "all")"
        case .crisisAlerts:
            // Never collapse crisis alerts
            return "crisis_\(UUID().uuidString)"
        }
    }
}

// MARK: - Deterministic Notification ID

/// Stable, deterministic notification document IDs prevent duplicate Firestore writes.
/// Using `setData(merge: false)` with these IDs means a repeated event OVERWRITES
/// rather than creating a second document.
enum NotificationId {
    /// like_{postId}_{actorUid} — one doc per actor per post; overwrites on repeat like
    static func like(postId: String, actorUid: String) -> String {
        "like_\(postId)_\(actorUid)"
    }
    /// comment_{commentId} — each comment is unique by its own ID
    static func comment(commentId: String) -> String {
        "comment_\(commentId)"
    }
    /// reply_{commentId} — each reply is unique by its comment doc ID
    static func reply(commentId: String) -> String {
        "reply_\(commentId)"
    }
    /// follow_{recipientUid}_{actorUid} — one follow notif per pair
    static func follow(recipientUid: String, actorUid: String) -> String {
        "follow_\(recipientUid)_\(actorUid)"
    }
    /// follow_request_{recipientUid}_{actorUid}
    static func followRequest(recipientUid: String, actorUid: String) -> String {
        "followreq_\(recipientUid)_\(actorUid)"
    }
    /// mention_{postId}_{actorUid}_{mentionedUid}
    static func mention(postId: String, actorUid: String, mentionedUid: String) -> String {
        "mention_\(postId)_\(actorUid)_\(mentionedUid)"
    }
    /// tag_{postId}_{actorUid}_{taggedUid}
    static func tag(postId: String, actorUid: String, taggedUid: String) -> String {
        "tag_\(postId)_\(actorUid)_\(taggedUid)"
    }
    /// repost_{postId}_{actorUid}
    static func repost(postId: String, actorUid: String) -> String {
        "repost_\(postId)_\(actorUid)"
    }
    /// dm_{threadId}_{messageId} — each message is unique
    static func directMessage(threadId: String, messageId: String) -> String {
        "dm_\(threadId)_\(messageId)"
    }
    /// prayer_{prayerId}_{actorUid} — one notif per actor per prayer
    static func prayerUpdate(prayerId: String, actorUid: String) -> String {
        "prayer_\(prayerId)_\(actorUid)"
    }
    /// rollup_like_{postId} — one rollup doc per post (updated in-place)
    static func likeRollup(postId: String) -> String {
        "rollup_like_\(postId)"
    }
    /// ai_summary_{uid}_{YYYYMMDD}_{window} — one summary per window
    static func aiSummary(uid: String, date: String, window: String) -> String {
        "summary_\(uid)_\(date)_\(window)"
    }

    // MARK: Rollup helpers

    /// Rollup key shared by NotificationId and collapse logic for likes on a given post.
    static func likeRollupKey(postId: String) -> String { "like_\(postId)" }
}
