// CommunityOpportunityModels.swift
// AMEN App — CommunityOS / Opportunity OS (A10)
//
// Data model for volunteer, job, and mentorship posts surfaced in the community feed.
// Distinct from IntegrationOS JobOpportunity which is for external career listings.
// Community opportunities always route contact through the Amen inbox (no raw info shown).

import Foundation

// MARK: - OpportunityPost

struct OpportunityPost: Identifiable, Codable {
    var id: String
    var title: String
    var description: String
    var type: CommunityOpportunityType
    var organizationName: String
    var orgId: String?
    var location: String
    var isRemote: Bool
    var compensationRange: String?
    var skillTags: [String]
    var postedByUserId: String
    var contactMethod: OpportunityContactMethod
    var createdAt: Date
    var updatedAt: Date
    var scamRiskLevel: OpportunityScamRiskLevel
}

// MARK: - CommunityOpportunityType

enum CommunityOpportunityType: String, CaseIterable, Codable {
    case volunteer   = "Volunteer"
    case fullTime    = "Full Time"
    case partTime    = "Part Time"
    case mentorship  = "Mentorship"
    case internship  = "Internship"

    var icon: String {
        switch self {
        case .volunteer:  return "figure.wave"
        case .fullTime:   return "briefcase.fill"
        case .partTime:   return "clock"
        case .mentorship: return "person.2.fill"
        case .internship: return "graduationcap"
        }
    }
}

// MARK: - OpportunityContactMethod

enum OpportunityContactMethod: String, Codable {
    case amenInboxOnly  = "amenInboxOnly"
    case emailOnly      = "emailOnly"
    case externalLink   = "externalLink"
}

// MARK: - OpportunityScamRiskLevel

enum OpportunityScamRiskLevel: String, Codable {
    case low, medium, high, flagged
}

// MARK: - ScamFlag

enum ScamFlag: String, CaseIterable {
    case fakeOrg            = "fake_org"
    case suspiciousRequest  = "suspicious_request"
    case requestedPayment   = "requested_payment"
    case noContactInfo      = "no_contact_info"

    var displayLabel: String {
        switch self {
        case .fakeOrg:           return "Fake Organization"
        case .suspiciousRequest: return "Suspicious Request"
        case .requestedPayment:  return "Asked Me for Money"
        case .noContactInfo:     return "No Verifiable Contact Info"
        }
    }
}
