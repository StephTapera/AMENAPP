// GivingModels.swift
// AMENAPP
//
// Core data models for the AMEN Giving / Nonprofits system.
// Truth-first, privacy-first, transparency-first.
// No vanity metrics. No paid placement. No prosperity coding.

import Foundation
import SwiftUI

// MARK: - Cause Areas

enum GivingCause: String, CaseIterable, Codable, Identifiable {
    case fosterCare = "Foster Care"
    case persecutedChurch = "Persecuted Church"
    case disasterRelief = "Disaster Relief"
    case homelessness = "Homelessness"
    case pregnancyWomen = "Pregnancy & Women"
    case prisonMinistry = "Prison Ministry"
    case refugeeResettlement = "Refugee Resettlement"
    case antiTrafficking = "Anti-Trafficking"
    case localChurchBenevolence = "Local Church & Benevolence"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fosterCare: return "heart.fill"
        case .persecutedChurch: return "cross.fill"
        case .disasterRelief: return "house.fill"
        case .homelessness: return "person.fill"
        case .pregnancyWomen: return "figure.and.child.holdinghands"
        case .prisonMinistry: return "key.fill"
        case .refugeeResettlement: return "globe.americas.fill"
        case .antiTrafficking: return "shield.fill"
        case .localChurchBenevolence: return "building.columns.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Geographic Preference

enum GeographicPreference: String, CaseIterable, Codable {
    case localFirst = "Local-first"
    case balanced = "Balanced"
    case global = "Global"
}

// MARK: - Theological Alignment

enum TheologicalAlignment: String, CaseIterable, Codable {
    case denominationallyNeutral = "Denominationally Neutral"
    case catholic = "Catholic"
    case evangelical = "Evangelical"
    case orthodox = "Orthodox"
    case nonDenominational = "Non-denominational"
}

// MARK: - Giving Style

enum GivingStyle: String, CaseIterable, Codable {
    case oneTime = "One-time"
    case recurring = "Recurring"
    case inKind = "In-kind"
    case timeVolunteer = "Time / Volunteer"
}

// MARK: - Trust Badges

enum TrustBadge: String, Codable, CaseIterable {
    case irs501c3 = "501(c)(3)"
    case ecfa = "ECFA"
    case charityNavigator = "Charity Navigator"
    case candid = "Candid / GuideStar"
    case bbbWiseGiving = "BBB Wise Giving"
    case localPartner = "Local partner verified"
    case pastoralReviewed = "Pastoral reviewed"
    case fieldResponseActive = "Field response active"
    case financialsCurrent = "Financials current"

    var icon: String {
        switch self {
        case .irs501c3: return "checkmark.seal.fill"
        case .ecfa: return "shield.checkered"
        case .charityNavigator: return "star.fill"
        case .candid: return "doc.badge.checkmark"
        case .bbbWiseGiving: return "building.fill"
        case .localPartner: return "mappin.circle.fill"
        case .pastoralReviewed: return "person.badge.checkmark"
        case .fieldResponseActive: return "bolt.fill"
        case .financialsCurrent: return "chart.bar.fill"
        }
    }

    var color: Color {
        switch self {
        case .irs501c3: return .green
        case .ecfa: return Color(red: 0.20, green: 0.55, blue: 0.30)
        case .charityNavigator: return Color(red: 0.85, green: 0.60, blue: 0.10)
        case .candid: return Color(red: 0.25, green: 0.45, blue: 0.80)
        case .bbbWiseGiving: return Color(red: 0.60, green: 0.10, blue: 0.10)
        case .localPartner: return Color(red: 0.10, green: 0.45, blue: 0.75)
        case .pastoralReviewed: return Color(red: 0.45, green: 0.30, blue: 0.65)
        case .fieldResponseActive: return Color(red: 0.85, green: 0.40, blue: 0.10)
        case .financialsCurrent: return Color(red: 0.20, green: 0.60, blue: 0.40)
        }
    }
}

// MARK: - Ranking Explanation Token

struct RankingExplanation: Codable {
    let tokens: [RankingToken]

    struct RankingToken: Codable {
        let key: String
        let label: String
    }

    var isEmpty: Bool { tokens.isEmpty }
}

// MARK: - Gift Impact

struct GiftImpact: Identifiable, Codable {
    let id: String
    let amount: Int        // dollars
    let description: String
    let fiscalYear: String
    let sourceUrl: String?
    let verifiedAt: Date?
    let confidence: DataConfidence
}

// MARK: - Recent Action

struct OrgRecentAction: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let region: String
    let occurredAt: Date?
    let verifiedAt: Date?
    let sourceUrl: String?
    let confidence: DataConfidence
}

// MARK: - Transparency Data

struct OrgTransparency: Codable {
    let programExpenseRatio: Double?    // e.g. 0.82
    let adminExpenseRatio: Double?
    let fundraisingExpenseRatio: Double?
    let fiscalYear: String?
    let sourceProviders: [String]
    let verificationStatus: VerificationStatus
    let verifiedAt: Date?
    let confidence: DataConfidence
    let notes: String?

    var programCentsLabel: String? {
        guard let ratio = programExpenseRatio else { return nil }
        let cents = Int(ratio * 100)
        return "\(cents)¢ of every dollar to programs"
    }

    var sourceLabel: String? {
        guard let year = fiscalYear, let provider = sourceProviders.first else { return nil }
        return "Source: \(provider) · \(year)"
    }

    enum VerificationStatus: String, Codable {
        case verified = "verified"
        case inProgress = "in_progress"
        case stale = "stale"
        case unavailable = "unavailable"
    }
}

// MARK: - Data Confidence

enum DataConfidence: String, Codable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    case unverified = "unverified"
}

// MARK: - Organization

struct GivingOrganization: Identifiable, Codable {
    let id: String
    let name: String
    let slug: String
    let description: String
    let causeCategories: [GivingCause]
    let serviceRegions: [ServiceRegion]
    let theologicalAffiliations: [TheologicalAlignment]
    let givingStylesSupported: [GivingStyle]
    let websiteUrl: String?
    let donationUrl: String?
    let volunteerUrl: String?
    let logoUrl: String?
    let isActive: Bool
    let isLocalPartner: Bool
    let isDisasterResponder: Bool
    let trustBadges: [TrustBadge]
    let trustScore: Double          // 0.0 – 1.0
    let transparency: OrgTransparency?
    let giftImpacts: [GiftImpact]
    let recentActions: [OrgRecentAction]
    var rankScore: Double = 0
    var rankingExplanation: RankingExplanation?

    struct ServiceRegion: Codable {
        let country: String?
        let state: String?
        let county: String?
        let metro: String?
        let zipCodes: [String]?
        let isLocal: Bool
        let isGlobal: Bool

        var displayLabel: String {
            if let metro { return metro }
            if let county { return county }
            if let state { return state }
            if let country { return country }
            return isGlobal ? "Global" : "Local"
        }
    }

    var primaryLocalityLabel: String {
        serviceRegions.first?.displayLabel ?? (isLocalPartner ? "Local" : "Global")
    }

    var primaryCauseLabel: String {
        causeCategories.first?.rawValue ?? "Community"
    }
}

// MARK: - Cause Brief

struct CauseBrief: Identifiable, Codable {
    let id: String
    let title: String
    let slug: String
    let causeCategory: GivingCause
    let regionScope: String?
    let summary: String
    let body: String
    let scriptureRefs: [String]
    let linkedOrgIds: [String]
    let linkedPrayerTopics: [String]
    let linkedVolunteerActions: [String]
    let publishedAt: Date?
    let updatedAt: Date?
    let isActive: Bool
}

// MARK: - Disaster Event

struct DisasterEvent: Identifiable, Codable {
    let id: String
    let title: String
    let eventType: DisasterEventType
    let sourceProvider: String
    let sourceUrl: String?
    let severity: DisasterSeverity
    let regions: [String]
    let summary: String
    let startedAt: Date?
    let updatedAt: Date?
    let isActive: Bool
    let linkedOrgIds: [String]

    enum DisasterEventType: String, Codable {
        case hurricane = "hurricane"
        case earthquake = "earthquake"
        case wildfire = "wildfire"
        case flood = "flood"
        case refugeeDisplacement = "refugee_displacement"
        case other = "other"

        var icon: String {
            switch self {
            case .hurricane: return "wind"
            case .earthquake: return "waveform.path"
            case .wildfire: return "flame.fill"
            case .flood: return "drop.fill"
            case .refugeeDisplacement: return "person.3.fill"
            case .other: return "exclamationmark.triangle.fill"
            }
        }
    }

    enum DisasterSeverity: String, Codable {
        case critical = "critical"
        case high = "high"
        case moderate = "moderate"
    }
}

// MARK: - Giving Profile (User Intent)

struct GivingProfile: Codable {
    var causePreferences: [GivingCause]
    var geographicPreference: GeographicPreference
    var theologicalAlignment: TheologicalAlignment
    var givingStylePreferences: [GivingStyle]
    var locationMode: LocationMode
    var zipCode: String?
    var homeRegion: HomeRegion?
    var completedIntentFlowAt: Date?
    var rankProfileVersion: Int

    enum LocationMode: String, Codable {
        case systemLocation = "system_location"
        case zip = "zip"
        case manual = "manual"
        case none = "none"
    }

    struct HomeRegion: Codable {
        var state: String?
        var county: String?
        var metro: String?
    }

    static var empty: GivingProfile {
        GivingProfile(
            causePreferences: [],
            geographicPreference: .balanced,
            theologicalAlignment: .denominationallyNeutral,
            givingStylePreferences: [],
            locationMode: .none,
            rankProfileVersion: 1
        )
    }

    var isComplete: Bool {
        !causePreferences.isEmpty && completedIntentFlowAt != nil
    }
}

// MARK: - Benevolence Request

struct BenevolenceRequest: Identifiable, Codable {
    let id: String
    let requesterUserId: String
    let churchId: String?
    let verificationType: VerificationType
    let category: BenevolenceCategory
    let title: String
    let summary: String
    let requestedAmount: Int      // cents
    let approvedCapAmount: Int?   // cents
    let currency: String
    var status: RequestStatus
    var guardianStatus: GuardianStatus
    let expiresAt: Date?
    var fulfillmentState: FulfillmentState
    let createdAt: Date?

    var requestedAmountFormatted: String {
        let dollars = requestedAmount / 100
        return "$\(dollars)"
    }

    var approvedCapFormatted: String? {
        guard let cap = approvedCapAmount else { return nil }
        return "$\(cap / 100) cap"
    }

    enum VerificationType: String, Codable {
        case churchAdmin = "church_admin"
        case pastorElder = "pastor_elder"
        case benevolenceTeam = "benevolence_team"
        case localPartner = "local_partner"

        var label: String {
            switch self {
            case .churchAdmin: return "Church admin verification"
            case .pastorElder: return "Pastoral attestation"
            case .benevolenceTeam: return "Church benevolence team verified"
            case .localPartner: return "Approved local partner verification"
            }
        }
    }

    enum BenevolenceCategory: String, Codable {
        case carRepair = "car_repair"
        case grocerySupport = "grocery_support"
        case funeralExpenses = "funeral_expenses"
        case rentBridge = "rent_bridge"
        case schoolSupplies = "school_supplies"
        case utilitySupport = "utility_support"
        case medicalSupport = "medical_support"
        case other = "other"

        var label: String {
            switch self {
            case .carRepair: return "Vehicle repair"
            case .grocerySupport: return "Grocery support"
            case .funeralExpenses: return "Funeral expenses"
            case .rentBridge: return "Rent bridge"
            case .schoolSupplies: return "School supplies"
            case .utilitySupport: return "Utility support"
            case .medicalSupport: return "Medical support"
            case .other: return "Other"
            }
        }
    }

    enum RequestStatus: String, Codable {
        case draft = "draft"
        case verificationPending = "verification_pending"
        case guardianReview = "guardian_review"
        case humanReview = "human_review"
        case approved = "approved"
        case active = "active"
        case fulfilled = "fulfilled"
        case expired = "expired"
        case closed = "closed"
        case denied = "denied"
    }

    enum GuardianStatus: String, Codable {
        case pending = "pending"
        case cleared = "cleared"
        case flagged = "flagged"
        case escalated = "escalated"
    }

    enum FulfillmentState: String, Codable {
        case notStarted = "not_started"
        case partiallyFunded = "partially_funded"
        case fullyFunded = "fully_funded"
        case distributed = "distributed"
    }
}

// MARK: - Giving Session

struct GivingSession: Identifiable, Codable {
    let id: String
    let userId: String
    let orgId: String?
    let requestId: String?
    let destinationType: DestinationType
    let amount: Int       // cents
    let currency: String
    var status: SessionStatus
    let createdAt: Date?
    var completedAt: Date?
    var receiptId: String?

    enum DestinationType: String, Codable {
        case org = "org"
        case request = "request"
        case church = "church"
    }

    enum SessionStatus: String, Codable {
        case pending = "pending"
        case processing = "processing"
        case completed = "completed"
        case failed = "failed"
        case refunded = "refunded"
    }
}

// MARK: - Tax Receipt

struct GivingReceipt: Identifiable, Codable {
    let id: String
    let userId: String
    let destinationType: GivingSession.DestinationType
    let destinationId: String
    let destinationName: String
    let amount: Int       // cents
    let currency: String
    let receiptUrl: String?
    let taxYear: Int
    let issuedAt: Date?

    var amountFormatted: String {
        let dollars = Double(amount) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

// MARK: - Giving Journal Entry

struct GivingJournalEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let destinationType: GivingSession.DestinationType
    let destinationId: String
    let destinationName: String
    let givingSessionId: String?
    var note: String
    var scriptureRef: String?
    var privateTags: [String]
    let createdAt: Date?
    var showAmount: Bool = false
    var amount: Int?    // optional — hidden in UI by default
}

// MARK: - Annual Review

struct GivingAnnualReview: Codable {
    let userId: String
    let year: Int
    let churchGivingTotal: Int      // cents
    let nonprofitGivingTotal: Int   // cents
    let localGivingTotal: Int       // cents
    let globalGivingTotal: Int      // cents
    let recurringGivingTotal: Int   // cents
    let destinationCount: Int
    let generatedAt: Date?

    var totalGiving: Int { churchGivingTotal + nonprofitGivingTotal }
    var totalFormatted: String { "$\(totalGiving / 100)" }

    var churchPercent: Int {
        guard totalGiving > 0 else { return 0 }
        return Int((Double(churchGivingTotal) / Double(totalGiving)) * 100)
    }

    var nonprofitPercent: Int { 100 - churchPercent }
}

// MARK: - Berean Giving Recommendation

struct BereanGivingRecommendation: Identifiable {
    let id = UUID()
    let org: GivingOrganization?
    let request: BenevolenceRequest?
    let brief: CauseBrief?
    let reason: String
    let scriptureRef: String?
    let scriptureText: String?
    let fitLabel: String
    let actionLabel: String
    let destinationType: RecommendationType

    enum RecommendationType {
        case organization
        case benevolenceRequest
        case causeBrief
        case reflect
    }
}

struct BereanGivingResponse {
    let prompt: String
    let summary: String
    let recommendations: [BereanGivingRecommendation]
    let closingReflection: String
    let generatedAt: Date
}

// MARK: - Feed Section

enum GivingFeedSection: String, CaseIterable, Identifiable {
    case activeResponse = "Active Response"
    case bestMatches = "Best Matches"
    case localFirst = "Local-first"
    case causeBriefs = "Cause Briefs"
    case trustedGlobal = "Trusted Global"
    case stewardship = "Stewardship"
    case requests = "Requests"

    var id: String { rawValue }
}

// MARK: - Feed Tab

enum GivingFeedTab: String, CaseIterable, Identifiable {
    case vetted = "Vetted"
    case causes = "Causes"
    case local = "Local"
    case stewardship = "Stewardship"
    case requests = "Requests"

    var id: String { rawValue }
}
