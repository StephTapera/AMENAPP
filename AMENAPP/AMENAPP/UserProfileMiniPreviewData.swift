//
//  UserProfileMiniPreviewData.swift
//  AMENAPP
//
//  Static preview fixtures for UserProfileViewMini.
//  Covers all required preview states.
//

import Foundation

enum UserProfileMiniPreviewData {

    // MARK: - Discovery (default)

    static let discovery = UserProfileMiniModel(
        id: "user_001",
        username: "marcusworship",
        displayName: "Marcus Williams",
        roleTitle: "Worship Leader · Atlanta, GA",
        bioShort: "Leading worship at Elevation Church. Passionate about faith, music, and community.",
        avatarURL: nil,
        followerCount: 3_420,
        sharedPrayerCount: 5,
        mutualConnectionCount: 3,
        mutualConnectionPreview: [
            MiniMutualUser(id: "m1", displayName: "Jasmine T.", avatarURL: nil),
            MiniMutualUser(id: "m2", displayName: "David R.", avatarURL: nil),
            MiniMutualUser(id: "m3", displayName: "Priya M.", avatarURL: nil)
        ],
        city: "Atlanta",
        pronoun: "he/him",
        pronunciation: "MAR-kus WIL-yams",
        badges: [
            UserMiniBadge(id: "b1", icon: "checkmark.seal.fill", label: "Verified", color: .verified)
        ],
        contextReasons: [
            UserMiniReason(id: "r1", label: "5 shared prayer topics", icon: "hands.sparkles", kind: .prayerOverlap),
            UserMiniReason(id: "r2", label: "3 mutual connections", icon: "person.2", kind: .mutualConnections),
            UserMiniReason(id: "r3", label: "Shared faith interests", icon: "sparkle", kind: .sharedInterest)
        ],
        suggestionSource: .discovery,
        credibility: UserMiniCredibility(responseLabel: "Usually responds", activeLabel: "Active today"),
        canMessage: true,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: "3 people you follow also follow Marcus.",
        recentSharedEngagementReason: "You both engage with worship leadership posts.",
        sharedTopicReason: "Shared prayer and ministry interests",
        communityReason: "Popular in Atlanta worship communities",
        popularityReason: "Frequently followed by people with similar faith interests",
        priorityExplanation: "You both engage with worship leadership posts, and 3 people you follow already know Marcus.",
        suggestionScore: 0.96,
        testimonyOverlapCount: nil,
        topicOverlapCount: 4,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - OpenTable (no trigger)

    static let openTable = UserProfileMiniModel(
        id: "user_002",
        username: "pastor_eze",
        displayName: "Ezekiel Okafor",
        roleTitle: "Pastor · Lagos & Dallas",
        bioShort: "Bridging faith and leadership. Founder of NewSeed International.",
        avatarURL: nil,
        followerCount: 12_800,
        sharedPrayerCount: nil,
        mutualConnectionCount: 7,
        mutualConnectionPreview: [
            MiniMutualUser(id: "m4", displayName: "Sara L.", avatarURL: nil)
        ],
        city: "Dallas",
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r4", label: "Faith & leadership overlap", icon: "text.bubble", kind: .topicOverlap),
            UserMiniReason(id: "r5", label: "7 mutual connections", icon: "person.2", kind: .mutualConnections)
        ],
        suggestionSource: .openTable,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: nil,
        recentSharedEngagementReason: "You both engage with faith and leadership discussions.",
        sharedTopicReason: "Leadership and church-building overlap",
        communityReason: "Often surfaced in Dallas faith communities",
        popularityReason: "Popular among people who read similar posts",
        priorityExplanation: "You've spent time with similar faith and leadership conversations recently.",
        suggestionScore: 0.88,
        testimonyOverlapCount: nil,
        topicOverlapCount: 3,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - OpenTable Unread Thread

    static let openTableUnread = UserProfileMiniModel(
        id: "user_002b",
        username: "pastor_eze",
        displayName: "Ezekiel Okafor",
        roleTitle: "Pastor · Lagos & Dallas",
        bioShort: "Bridging faith and leadership. Founder of NewSeed International.",
        avatarURL: nil,
        followerCount: 12_800,
        sharedPrayerCount: nil,
        mutualConnectionCount: 7,
        mutualConnectionPreview: [
            MiniMutualUser(id: "m4b", displayName: "Sara L.", avatarURL: nil)
        ],
        city: "Dallas",
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r4b", label: "Faith & leadership overlap", icon: "text.bubble", kind: .topicOverlap)
        ],
        suggestionSource: .openTable,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: UserMiniTrigger(
            artifactType: .openTableThread,
            artifactId: "thread_abc",
            title: "Is holistic faith leadership possible today?",
            topic: "leadership",
            viewerState: .unread
        ),
        directRelationshipReason: nil,
        recentSharedEngagementReason: "You both engage with faith and leadership discussions.",
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: "An unread thread you both participate in.",
        suggestionScore: 0.85,
        testimonyOverlapCount: nil,
        topicOverlapCount: 3,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - OpenTable Read Thread

    static let openTableRead = UserProfileMiniModel(
        id: "user_002c",
        username: "pastor_eze",
        displayName: "Ezekiel Okafor",
        roleTitle: "Pastor · Lagos & Dallas",
        bioShort: nil,
        avatarURL: nil,
        followerCount: 12_800,
        sharedPrayerCount: nil,
        mutualConnectionCount: 2,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r4c", label: "Faith & leadership overlap", icon: "text.bubble", kind: .topicOverlap)
        ],
        suggestionSource: .openTable,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: UserMiniTrigger(
            artifactType: .openTableThread,
            artifactId: "thread_abc",
            title: "Is holistic faith leadership possible today?",
            topic: "leadership",
            viewerState: .read
        ),
        directRelationshipReason: nil,
        recentSharedEngagementReason: "You've both read this discussion thread.",
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: "You've read this thread — they're a regular contributor.",
        suggestionScore: 0.78,
        testimonyOverlapCount: nil,
        topicOverlapCount: 2,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - OpenTable Replied Thread

    static let openTableReplied = UserProfileMiniModel(
        id: "user_002d",
        username: "pastor_eze",
        displayName: "Ezekiel Okafor",
        roleTitle: "Pastor",
        bioShort: nil,
        avatarURL: nil,
        followerCount: 12_800,
        sharedPrayerCount: nil,
        mutualConnectionCount: 2,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r4d", label: "Faith & leadership overlap", icon: "text.bubble", kind: .topicOverlap)
        ],
        suggestionSource: .openTable,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: UserMiniTrigger(
            artifactType: .openTableThread,
            artifactId: "thread_abc",
            title: "Is holistic faith leadership possible today?",
            topic: "leadership",
            viewerState: .replied
        ),
        directRelationshipReason: nil,
        recentSharedEngagementReason: "You've already replied in this thread.",
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: "You've both engaged in the same thread.",
        suggestionScore: 0.72,
        testimonyOverlapCount: nil,
        topicOverlapCount: 2,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Prayer

    static let prayer = UserProfileMiniModel(
        id: "user_003",
        username: "prayerandfaith",
        displayName: "Abby Johnson",
        roleTitle: "Intercessor",
        bioShort: "Standing in the gap. Praying daily for healing, restoration, and peace.",
        avatarURL: nil,
        followerCount: 890,
        sharedPrayerCount: 11,
        mutualConnectionCount: 2,
        mutualConnectionPreview: [
            MiniMutualUser(id: "m6", displayName: "James K.", avatarURL: nil)
        ],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r6", label: "11 shared prayer topics", icon: "hands.sparkles", kind: .prayerOverlap),
            UserMiniReason(id: "r7", label: "Active in prayer conversations", icon: nil, kind: .prayerOverlap)
        ],
        suggestionSource: .prayer,
        credibility: UserMiniCredibility(responseLabel: nil, activeLabel: "Prayed 3 times today"),
        canMessage: true,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: UserMiniTrigger(
            artifactType: .prayerPost,
            artifactId: "prayer_001",
            title: nil,
            topic: "healing",
            viewerState: .unread
        ),
        directRelationshipReason: nil,
        recentSharedEngagementReason: "Frequently active in prayer conversations you revisit.",
        sharedTopicReason: "Shared healing and restoration prayer themes",
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: "Suggested from shared prayer topics and recent prayer support activity.",
        suggestionScore: 0.93,
        testimonyOverlapCount: nil,
        topicOverlapCount: 2,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Prayer (already prayed today)

    static let prayerPrayedToday = UserProfileMiniModel(
        id: "user_003b",
        username: "prayerandfaith",
        displayName: "Abby Johnson",
        roleTitle: "Intercessor",
        bioShort: "Standing in the gap.",
        avatarURL: nil,
        followerCount: 890,
        sharedPrayerCount: 11,
        mutualConnectionCount: 1,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r6b", label: "11 shared prayer topics", icon: "hands.sparkles", kind: .prayerOverlap)
        ],
        suggestionSource: .prayer,
        credibility: UserMiniCredibility(responseLabel: nil, activeLabel: "Prayed 3 times today"),
        canMessage: true,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: UserMiniTrigger(
            artifactType: .prayerPost,
            artifactId: "prayer_001",
            title: nil,
            topic: "healing",
            viewerState: .prayedToday
        ),
        directRelationshipReason: nil,
        recentSharedEngagementReason: nil,
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: "You already prayed for this today.",
        suggestionScore: 0.80,
        testimonyOverlapCount: nil,
        topicOverlapCount: nil,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Testimonies

    static let testimonies = UserProfileMiniModel(
        id: "user_004",
        username: "grace_restored",
        displayName: "Natalie Cruz",
        roleTitle: nil,
        bioShort: "Sharing my journey of healing. God's grace is never-ending.",
        avatarURL: nil,
        followerCount: 1_220,
        sharedPrayerCount: 3,
        mutualConnectionCount: 1,
        mutualConnectionPreview: [
            MiniMutualUser(id: "m7", displayName: "Chris O.", avatarURL: nil)
        ],
        city: "Miami",
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r8", label: "Shared testimony themes", icon: "quote.bubble", kind: .testimonyOverlap),
            UserMiniReason(id: "r9", label: "Healing & restoration focus", icon: nil, kind: .topicOverlap)
        ],
        suggestionSource: .testimonies,
        credibility: nil,
        canMessage: true,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: UserMiniTrigger(
            artifactType: .testimonyPost,
            artifactId: "testimony_001",
            title: "God Healed My Marriage",
            topic: "healing",
            viewerState: .unread
        ),
        directRelationshipReason: nil,
        recentSharedEngagementReason: "You both spend time in healing and restoration stories.",
        sharedTopicReason: "Healing and restoration focus",
        communityReason: "Encouraging voice in Miami testimony circles",
        popularityReason: nil,
        priorityExplanation: "You both interact with testimony themes around healing and restoration.",
        suggestionScore: 0.9,
        testimonyOverlapCount: 2,
        topicOverlapCount: 2,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Already Followed

    static let alreadyFollowed = UserProfileMiniModel(
        id: "user_005",
        username: "davidtheking",
        displayName: "David Asante",
        roleTitle: "Gospel Artist",
        bioShort: "New album out now. Music for the soul.",
        avatarURL: nil,
        followerCount: 22_400,
        sharedPrayerCount: 2,
        mutualConnectionCount: 5,
        mutualConnectionPreview: [],
        city: "Houston",
        pronoun: nil,
        pronunciation: nil,
        badges: [
            UserMiniBadge(id: "b2", icon: "music.note", label: "Artist", color: .faith)
        ],
        contextReasons: [
            UserMiniReason(id: "r10", label: "5 mutual connections", icon: "person.2", kind: .mutualConnections)
        ],
        suggestionSource: .discovery,
        credibility: nil,
        canMessage: true,
        isFollowed: true,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: "5 people you follow already follow David.",
        recentSharedEngagementReason: nil,
        sharedTopicReason: "Music and worship overlap",
        communityReason: "Often appears in Houston worship communities",
        popularityReason: nil,
        priorityExplanation: "You already follow David, and several people in your network do too.",
        suggestionScore: 0.84,
        testimonyOverlapCount: nil,
        topicOverlapCount: 1,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Cannot Message

    static let cannotMessage = UserProfileMiniModel(
        id: "user_006",
        username: "faithfulone",
        displayName: "Rachel Moore",
        roleTitle: "Bible Study Leader",
        bioShort: nil,
        avatarURL: nil,
        followerCount: 540,
        sharedPrayerCount: nil,
        mutualConnectionCount: 0,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [
            UserMiniReason(id: "r11", label: "Shared faith interests", icon: "sparkle", kind: .sharedInterest)
        ],
        suggestionSource: .discovery,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: nil,
        recentSharedEngagementReason: nil,
        sharedTopicReason: "Shared Bible study and discipleship interests",
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: "Suggested from shared faith interests.",
        suggestionScore: 0.61,
        testimonyOverlapCount: nil,
        topicOverlapCount: 1,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Low Info / Missing Avatar

    static let lowInfo = UserProfileMiniModel(
        id: "user_007",
        username: "newuser2026",
        displayName: "A",  // Very short name edge case
        roleTitle: nil,
        bioShort: nil,
        avatarURL: nil,
        followerCount: nil,
        sharedPrayerCount: nil,
        mutualConnectionCount: nil,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [],
        suggestionSource: .unknown,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: nil,
        recentSharedEngagementReason: nil,
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: "Popular among people with similar interests",
        priorityExplanation: "Suggested based on limited but relevant activity.",
        suggestionScore: 0.32,
        testimonyOverlapCount: nil,
        topicOverlapCount: nil,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Low Signal (context panel suppressed)

    static let noSignal = UserProfileMiniModel(
        id: "user_007b",
        username: "quietuser",
        displayName: "Jordan Ellis",
        roleTitle: nil,
        bioShort: nil,
        avatarURL: nil,
        followerCount: 12,
        sharedPrayerCount: nil,
        mutualConnectionCount: nil,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [],
        suggestionSource: .unknown,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: nil,
        recentSharedEngagementReason: nil,
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: nil,
        suggestionScore: 0.08,   // Below 0.15 → showContextPanel = false
        testimonyOverlapCount: nil,
        topicOverlapCount: nil,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Long Name / Long Title

    static let longName = UserProfileMiniModel(
        id: "user_008",
        username: "revdrprofessor_longname_here",
        displayName: "Reverend Dr. Professor Jonathan Bartholomew-Ashworth III",
        roleTitle: "Senior Apostle, Regional Bishop & Chancellor of Faith Ministries International",
        bioShort: "Over 40 years of ministry across 12 nations. Author of 8 books on faith and leadership.",
        avatarURL: nil,
        followerCount: 87_000,
        sharedPrayerCount: 0,
        mutualConnectionCount: 1,
        mutualConnectionPreview: [],
        city: "Washington D.C.",
        pronoun: nil,
        pronunciation: nil,
        badges: [
            UserMiniBadge(id: "b3", icon: "checkmark.seal.fill", label: "Verified", color: .verified)
        ],
        contextReasons: [
            UserMiniReason(id: "r12", label: "Popular in your area", icon: "location", kind: .popularInArea)
        ],
        suggestionSource: .discovery,
        credibility: UserMiniCredibility(responseLabel: nil, activeLabel: nil),
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: nil,
        recentSharedEngagementReason: nil,
        sharedTopicReason: "Leadership and teaching overlap",
        communityReason: "Popular in your area",
        popularityReason: "Highly followed by people in similar church communities",
        priorityExplanation: "Popular in your area and relevant to the leadership content you read.",
        suggestionScore: 0.79,
        testimonyOverlapCount: nil,
        topicOverlapCount: 2,
        isProfileUnavailable: false,
        isBlocked: false
    )

    // MARK: - Blocked / Unavailable Profile

    static let blocked = UserProfileMiniModel(
        id: "user_009",
        username: "blockeduser",
        displayName: "Hidden Profile",
        roleTitle: nil,
        bioShort: nil,
        avatarURL: nil,
        followerCount: nil,
        sharedPrayerCount: nil,
        mutualConnectionCount: nil,
        mutualConnectionPreview: [],
        city: nil,
        pronoun: nil,
        pronunciation: nil,
        badges: [],
        contextReasons: [],
        suggestionSource: .discovery,
        credibility: nil,
        canMessage: false,
        isFollowed: false,
        isSavedSuggestion: false,
        profileRoute: nil,
        trigger: nil,
        directRelationshipReason: nil,
        recentSharedEngagementReason: nil,
        sharedTopicReason: nil,
        communityReason: nil,
        popularityReason: nil,
        priorityExplanation: nil,
        suggestionScore: nil,
        testimonyOverlapCount: nil,
        topicOverlapCount: nil,
        isProfileUnavailable: false,
        isBlocked: true
    )
}
