// OpportunityModels.swift — AMEN IntegrationOS

import Foundation

struct JobOpportunity: Codable, Identifiable {
    var id: String = UUID().uuidString
    let posterId: String
    let orgId: String?
    let orgName: String
    let title: String
    let description: String
    let location: String
    let isRemote: Bool
    let jobType: JobType
    let ministryArea: String?
    let compensationType: CompensationType
    let compensationRange: String?
    let tags: [String]
    let applicationURL: String?
    let contactEmail: String?
    let expiresAt: Date?
    let createdAt: Date
    let isActive: Bool
}

struct JobApplication: Codable, Identifiable {
    var id: String = UUID().uuidString
    let opportunityId: String
    let applicantId: String
    let coverNote: String?
    let portfolioURL: String?
    let status: ApplicationStatus
    let appliedAt: Date
}

enum JobType: String, Codable, CaseIterable {
    case fullTime = "full_time"
    case partTime = "part_time"
    case volunteer = "volunteer"
    case internship = "internship"
    case contract = "contract"
}

enum CompensationType: String, Codable, CaseIterable {
    case paid = "paid"
    case volunteer = "volunteer"
    case stipend = "stipend"
}

enum ApplicationStatus: String, Codable {
    case submitted, underReview, interviewed, offered, rejected, withdrawn
}
