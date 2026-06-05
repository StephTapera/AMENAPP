// OpportunityModels.swift
// AMEN Community OS — Opportunity OS (A10)
//
// View-model layer over IntegrationOS/Career/JobOpportunityModels.swift.
// The IntegrationOS file defines:
//   - JobOpportunity (Identifiable, Codable) — the core opportunity record
//   - JobType (fullTime, partTime, volunteer, internship, contract)
//   - CompensationType + ApplicationStatus + JobApplication
//
// This file adds:
//   1. CommunityOpportunity struct — Community OS view model wrapping JobOpportunity,
//      adding provenance, org metadata, and soft-delete per C1 contract

import Foundation

// MARK: - CommunityOpportunity

/// Community OS view-layer opportunity object.
/// Wraps JobOpportunity with provenance, org display metadata, and soft-delete per C1 §5.
///
/// contactMethod MUST always be "amenInbox" — raw email/phone is never stored or shown.
struct CommunityOpportunity: Identifiable, Codable {
    let id: String

    // MARK: Core fields (mapped from JobOpportunity)

    let jobType: JobType
    let orgId: String
    /// Denormalized for display — avoids a second org document read when rendering cards.
    let orgName: String
    var title: String
    var description: String

    /// INVARIANT: This value must always equal "amenInbox".
    /// Raw email and phone are never stored or surfaced on opportunity objects.
    let contactMethod: String

    var audience: String
    let provenance: SpawnProvenance?
    let createdAt: Date
    var softDeleted: Bool

    // MARK: Validation

    /// Asserts the contactMethod contract at runtime (debug builds only).
    func assertContactMethodContract() {
        assert(
            contactMethod == "amenInbox",
            "CRITICAL: contactMethod must be 'amenInbox'. Raw PII is never stored on opportunity objects."
        )
    }

    // MARK: Factory

    /// Converts a `JobOpportunity` from the IntegrationOS/Career layer into a CommunityOpportunity.
    init(from job: JobOpportunity, provenance: SpawnProvenance? = nil) {
        self.id = job.id
        self.jobType = job.jobType
        self.orgId = job.orgId ?? ""
        self.orgName = job.orgName
        self.title = job.title
        self.description = job.description
        self.contactMethod = "amenInbox"
        self.audience = job.isRemote ? "remote" : (job.location.isEmpty ? "open" : job.location)
        self.provenance = provenance
        self.createdAt = job.createdAt
        self.softDeleted = false
    }
}
