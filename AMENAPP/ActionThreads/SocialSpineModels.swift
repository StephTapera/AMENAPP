import Foundation

// MARK: - Social Spine Context

/// Canonical context compiled before any governed social action is executed.
/// Surfaces should add compiler adapters instead of inventing their own safety state.
struct SocialContext: Codable, Identifiable, Equatable {
    let id: String
    let action: SocialAction
    let actor: SocialActorContext
    let surface: SocialSurfaceContext
    let thread: SocialThreadContext
    let relationship: SocialRelationshipEdge
    let content: SocialContentContext
    let risk: SocialRiskVector
    let compiledAt: Date
    let compilerVersion: String

    init(
        id: String = UUID().uuidString,
        action: SocialAction,
        actor: SocialActorContext,
        surface: SocialSurfaceContext,
        thread: SocialThreadContext = .empty,
        relationship: SocialRelationshipEdge = .unknown,
        content: SocialContentContext,
        risk: SocialRiskVector,
        compiledAt: Date = Date(),
        compilerVersion: String = "social_spine_context_v1"
    ) {
        self.id = id
        self.action = action
        self.actor = actor
        self.surface = surface
        self.thread = thread
        self.relationship = relationship
        self.content = content
        self.risk = risk
        self.compiledAt = compiledAt
        self.compilerVersion = compilerVersion
    }
}

struct SocialAction: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case post
        case comment
        case directMessage = "direct_message"
        case groupMessage = "group_message"
        case callUtterance = "call_utterance"
        case join
        case donate
        case actionSuggestion = "action_suggestion"
        case actionThread = "action_thread"
        case unknown
    }

    let kind: Kind
    let verb: String
    let sourceId: String?
    let targetId: String?
}

struct SocialActorContext: Codable, Equatable {
    enum Role: String, Codable, CaseIterable {
        case member
        case leader
        case pastor
        case guardian
        case moderator
        case organization
        case unknown
    }

    enum AgeBand: String, Codable, CaseIterable {
        case under13 = "under_13"
        case minor
        case adult
        case unknown

        var isMinorOrUnknown: Bool { self != .adult }
    }

    enum TrustLevel: String, Codable, CaseIterable {
        case new
        case basic
        case trusted
        case verified
        case exemplary
        case unknown
    }

    struct ModerationHistory: Codable, Equatable {
        let activeStrikes: Int
        let lifetimeStrikes: Int
        let recentBlocks: Int
        let recentAppealsUpheld: Int

        static let empty = ModerationHistory(
            activeStrikes: 0,
            lifetimeStrikes: 0,
            recentBlocks: 0,
            recentAppealsUpheld: 0
        )
    }

    let userId: String?
    let role: Role
    let ageBand: AgeBand
    let trustLevel: TrustLevel
    let moderationHistory: ModerationHistory

    var hasElevatedAuthority: Bool {
        role == .leader || role == .pastor || role == .moderator || role == .organization
    }
}

struct SocialSurfaceContext: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case feed
        case comment
        case directMessage = "direct_message"
        case group
        case room
        case call
        case profile
        case donation
        case actionThread = "action_thread"
        case unknown
    }

    enum Visibility: String, Codable, CaseIterable {
        case `private`
        case participants
        case mutuals
        case community
        case publicFeed = "public_feed"
        case unknown

        var isPublicLike: Bool {
            self == .community || self == .publicFeed
        }
    }

    enum PrivacyTier: String, Codable, CaseIterable {
        case publicCommunity = "tier_p"
        case confidential = "tier_c"
        case sacred = "tier_s"
    }

    let kind: Kind
    let visibility: Visibility
    let privacyTier: PrivacyTier
    let communityId: String?
    let organizationId: String?
}

struct SocialThreadContext: Codable, Equatable {
    enum Temperature: String, Codable, CaseIterable {
        case calm
        case warm
        case heated
        case critical
    }

    enum ConflictRisk: String, Codable, CaseIterable, Comparable {
        case low
        case medium
        case high
        case critical

        private var rank: Int {
            switch self {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            case .critical: return 3
            }
        }

        static func < (lhs: ConflictRisk, rhs: ConflictRisk) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    let threadId: String?
    let temperature: Temperature
    let conflictRisk: ConflictRisk
    let recentInterventionCount: Int
    let unresolvedReports: Int

    static let empty = SocialThreadContext(
        threadId: nil,
        temperature: .calm,
        conflictRisk: .low,
        recentInterventionCount: 0,
        unresolvedReports: 0
    )
}

struct SocialRelationshipEdge: Codable, Equatable {
    enum Familiarity: String, Codable, CaseIterable {
        case none
        case acquaintance
        case friend
        case mentor
        case pastor
        case guardian
        case unknown
    }

    enum PowerAsymmetry: String, Codable, CaseIterable {
        case none
        case actorOverTarget = "actor_over_target"
        case targetOverActor = "target_over_actor"
        case mutual
        case unknown
    }

    let targetUserId: String?
    let familiarity: Familiarity
    let powerAsymmetry: PowerAsymmetry
    let isGuardianApproved: Bool

    static let unknown = SocialRelationshipEdge(
        targetUserId: nil,
        familiarity: .unknown,
        powerAsymmetry: .unknown,
        isGuardianApproved: false
    )
}

struct SocialContentContext: Codable, Equatable {
    enum Sensitivity: String, Codable, CaseIterable {
        case standard
        case elevated
        case high
        case critical
    }

    let text: String
    let mediaCount: Int
    let claims: [String]
    let containsPII: Bool
    let containsScripture: Bool
    let containsMinor: Bool
    let sensitivity: Sensitivity
    let languageCode: String?
}

struct SocialRiskVector: Codable, Equatable {
    enum Level: String, Codable, CaseIterable, Comparable {
        case none
        case low
        case medium
        case high
        case critical

        private var rank: Int {
            switch self {
            case .none: return 0
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            case .critical: return 4
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    let minorSafety: Level
    let selfHarm: Level
    let abuse: Level
    let harassment: Level
    let privacy: Level
    let medical: Level
    let financial: Level
    let theological: Level
    let spam: Level

    var overall: Level {
        [minorSafety, selfHarm, abuse, harassment, privacy, medical, financial, theological, spam].max() ?? .none
    }

    static let empty = SocialRiskVector(
        minorSafety: .none,
        selfHarm: .none,
        abuse: .none,
        harassment: .none,
        privacy: .none,
        medical: .none,
        financial: .none,
        theological: .none,
        spam: .none
    )
}

// MARK: - Constitution Verdict

struct SocialConstitutionVerdict: Codable, Equatable {
    enum Decision: String, Codable, CaseIterable, Comparable {
        case allow
        case nudge
        case requireEdit = "require_edit"
        case holdReview = "hold_review"
        case block
        case escalate

        var rank: Int {
            switch self {
            case .allow: return 0
            case .nudge: return 1
            case .requireEdit: return 2
            case .holdReview: return 3
            case .block: return 4
            case .escalate: return 5
            }
        }

        static func < (lhs: Decision, rhs: Decision) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    enum Article: String, Codable, CaseIterable {
        case articleIHumanDignity = "article_i_human_dignity"
        case articleIIMinorSafety = "article_ii_minor_safety"
        case articleIIITruthAndClaims = "article_iii_truth_and_claims"
        case articleIVPrivacyAndConsent = "article_iv_privacy_and_consent"
        case articleVFormationOverEngagement = "article_v_formation_over_engagement"
        case articleVICommunityPeace = "article_vi_community_peace"
        case articleVIIStewardship = "article_vii_stewardship"
        case communitySubConstitution = "community_sub_constitution"
    }

    struct Evidence: Codable, Identifiable, Equatable {
        let id: String
        let article: Article
        let signal: String
        let weight: Double
        let summary: String

        init(
            id: String = UUID().uuidString,
            article: Article,
            signal: String,
            weight: Double,
            summary: String
        ) {
            self.id = id
            self.article = article
            self.signal = signal
            self.weight = weight
            self.summary = summary
        }
    }

    let decision: Decision
    let winningArticle: Article
    let rationale: String
    let evidenceTrail: [Evidence]
    let requiresHumanReview: Bool
    let isAppealable: Bool

    static func allow(evidence: [Evidence] = []) -> SocialConstitutionVerdict {
        SocialConstitutionVerdict(
            decision: .allow,
            winningArticle: .articleIHumanDignity,
            rationale: "No constitutional rule requires intervention.",
            evidenceTrail: evidence,
            requiresHumanReview: false,
            isAppealable: false
        )
    }
}

struct SocialSubConstitutionRule: Codable, Identifiable, Equatable {
    let id: String
    let communityId: String
    let articleName: String
    let appliesToSurfaceKinds: [SocialSurfaceContext.Kind]
    let triggerSignals: [String]
    let decision: SocialConstitutionVerdict.Decision
    let rationale: String
    let ratifiedAt: Date?

    var isRatified: Bool { ratifiedAt != nil }
}
