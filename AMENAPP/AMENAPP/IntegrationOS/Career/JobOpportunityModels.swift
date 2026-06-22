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

// JobApplication, JobType, CompensationType, ApplicationStatus defined in JobModels.swift
