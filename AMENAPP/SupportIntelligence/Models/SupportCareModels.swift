//
//  SupportCareModels.swift
//  AMENAPP
//
//  Production-facing care routing models for the Resources Intelligence System.
//  These types define domains, actions, trusted contacts, plans, and explainable
//  classifications without exposing internal reasoning codes to end users.
//

import Foundation

enum ResourceSupportDomain: String, Codable, CaseIterable, Sendable {
    case crisisImmediate
    case emotionalWellness
    case anxietyStress
    case depressionHopelessness
    case griefLoss
    case lonelinessCommunity
    case churchHurt
    case counselingTherapy
    case marriageRelationships
    case addictionRecovery
    case financialNeed
    case foodHousingNeed
    case pastoralCare
    case prayerSupport
    case accountability
    case bibleGuidance
    case serviceVolunteer
    case givingNonprofits
    case helpingSomeoneElse
    case newcomerChurchDiscovery
}

enum SupportRoutingLevel: String, Codable, Sendable {
    case none
    case gentleSupport
    case guidedSupport
    case immediateHelp
}

enum SupportActionType: String, Codable, Sendable {
    case openGroundingExercise = "open_grounding_exercise"
    case openBreathingTool = "open_breathing_tool"
    case openPrayerFlow = "open_prayer_flow"
    case openBerean = "open_berean"
    case openFindChurch = "open_find_church"
    case openCounselingResources = "open_counseling_resources"
    case openSupportGroups = "open_support_groups"
    case openNonprofitResources = "open_nonprofit_resources"
    case openHelpingSomeoneElse = "open_helping_someone_else"
    case call988 = "call_988"
    case text988 = "text_988"
    case textCrisisLine = "text_crisis_line"
    case call911 = "call_911"
    case messageTrustedContact = "message_trusted_contact"
    case saveToPrivateNotes = "save_to_private_notes"
    case convertToPrivatePrayer = "convert_to_private_prayer"
    case shareWithPastorOrCareTeam = "share_with_pastor_or_care_team"
    case viewResourcePlan = "view_resource_plan"
}

struct SupportAction: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var type: SupportActionType
    var title: String
    var promptTemplate: String?
    var filters: [String: String]
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        type: SupportActionType,
        title: String,
        promptTemplate: String? = nil,
        filters: [String: String] = [:],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.promptTemplate = promptTemplate
        self.filters = filters
        self.metadata = metadata
    }
}

struct SupportClassification: Codable, Sendable {
    var domains: [ResourceSupportDomain]
    var severity: SupportRiskTier
    var confidence: Double
    var helpingSomeoneElse: Bool
    var reasoningCodes: [SupportReasonCode]
    var detectedThemes: [SupportTheme]
    var sourceSurface: SupportSurface
    var createdAt: Date

    static func empty(surface: SupportSurface) -> SupportClassification {
        SupportClassification(
            domains: [],
            severity: .none,
            confidence: 0,
            helpingSomeoneElse: false,
            reasoningCodes: [.noSignalsSufficient],
            detectedThemes: [],
            sourceSurface: surface,
            createdAt: Date()
        )
    }
}

struct SupportRouteDecision: Codable, Sendable {
    var routingLevel: SupportRoutingLevel
    var domains: [ResourceSupportDomain]
    var actions: [SupportAction]
    var promptType: SupportPromptType?
    var shouldSuppressGiving: Bool
    var shouldOfferTrustedContact: Bool
    var shouldOfferFollowUp: Bool
    var supportingReasons: [SupportReasonCode]
    var sourceSurface: SupportSurface

    static func none(surface: SupportSurface) -> SupportRouteDecision {
        SupportRouteDecision(
            routingLevel: .none,
            domains: [],
            actions: [],
            promptType: nil,
            shouldSuppressGiving: false,
            shouldOfferTrustedContact: false,
            shouldOfferFollowUp: false,
            supportingReasons: [],
            sourceSurface: surface
        )
    }
}

struct SupportTrustedContact: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, CaseIterable, Sendable {
        case friend
        case spouse
        case pastor
        case mentor
        case accountabilityPartner
        case careTeam
        case emergencyContact
    }

    var id: String
    var displayName: String
    var role: Role
    var phoneNumber: String?
    var email: String?
    var allowPrayerRequests: Bool
    var allowUrgentMessages: Bool
    var createdAt: Date
}

struct SupportPlanStep: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case done
        case dismissed
    }

    var id: String
    var type: SupportActionType
    var title: String
    var status: Status
    var deepLink: String?
    var createdAt: Date
}

struct SupportResourcePlan: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var domains: [ResourceSupportDomain]
    var createdFrom: SupportSurface
    var steps: [SupportPlanStep]
    var createdAt: Date
    var updatedAt: Date
}
