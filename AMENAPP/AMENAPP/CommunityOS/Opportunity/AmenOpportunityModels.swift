// AmenOpportunityModels.swift
// AMEN CommunityOS — Opportunity OS (A10)
//
// Phase 3 Agent A10: Jobs, volunteer positions, mentorship requests, and referrals.
// All contact info is protected — contactRef is ALWAYS an Amen inbox thread reference.
// Raw email / phone NEVER appears in any model, service, or view.
//
// Naming notes (collision avoidance):
//   - AmenJob, AmenVolunteerOpportunity, AmenMentorship are already defined in
//     CommunityOS/Core/AmenCoreModels.swift as C1 canonical objects.
//     This file defines richer, feed-oriented variants:
//       AmenJobPost          (job board posting)
//       AmenVolunteerPost    (volunteer opportunity posting)
//       AmenMentorshipPost   (mentorship request posting)
//       AmenOpportunityApplication (application record)
//   - JobType, ExperienceLevel are defined in JobModels.swift — imported, not redefined.
//   - MentorshipStatus is defined in AmenCoreModels.swift — not redefined here.
//   - ApplicationStatus is defined in JobModels.swift — not redefined here.
//   - SpawnProvenance is defined in CommunityOS/Core/CommunityObjectTypes.swift.

import Foundation

// MARK: - AmenOpportunityCategory
// Discriminator enum used by feed views to segment the three content types.
// Named AmenOpportunityCategory (not OpportunityType) to avoid future collisions.

enum AmenOpportunityCategory: String, Codable, CaseIterable, Sendable {
    case job                  = "job"
    case volunteerPosition    = "volunteerPosition"
    case mentorship           = "mentorship"
    case internship           = "internship"
    case projectCollaboration = "projectCollaboration"
    case referral             = "referral"

    var displayName: String {
        switch self {
        case .job:                  return "Job"
        case .volunteerPosition:    return "Volunteer"
        case .mentorship:           return "Mentorship"
        case .internship:           return "Internship"
        case .projectCollaboration: return "Collaboration"
        case .referral:             return "Referral"
        }
    }

    var systemImage: String {
        switch self {
        case .job:                  return "briefcase.fill"
        case .volunteerPosition:    return "figure.wave"
        case .mentorship:           return "person.2.fill"
        case .internship:           return "graduationcap.fill"
        case .projectCollaboration: return "puzzlepiece.fill"
        case .referral:             return "person.badge.plus"
        }
    }
}

// MARK: - AmenJobPost

/// Feed-layer job posting. Richer than C1's AmenJob — includes requirements, tags,
/// filled status, application deadline, and the safe contactRef pattern.
///
/// CRITICAL: contactRef is an Amen inbox thread reference (e.g. "inbox://thread/xyz").
/// Raw email and phone are never stored or surfaced here.
///
/// Stored at /jobPosts/{id}.
struct AmenJobPost: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var organization: String
    /// Link to /organizations/{orgId} if this poster is a verified org.
    var orgId: String?
    var description: String
    var requirements: [String]
    /// Uses JobType from JobModels.swift (fullTime, partTime, contract, etc.)
    var jobType: JobType
    /// Uses ExperienceLevel from JobModels.swift.
    var experienceLevel: ExperienceLevel
    /// "Remote" | "City, State" | "Hybrid" — nil if unspecified.
    var location: String?
    var isRemote: Bool
    /// Optional salary range shown only when the poster provides it.
    var salaryRange: String?
    var applicationDeadline: Date?
    var tags: [String]
    /// AMEN inbox thread reference. NEVER a raw email or phone number.
    var contactRef: String
    /// External URL (https) to apply. Nil routes to the Amen inbox flow.
    /// Must never be a mailto: or tel: link.
    var applicationUrl: String?
    var provenance: SpawnProvenance?
    /// Firebase Auth UID of the user who posted this.
    var postedBy: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    /// True when the role is filled — hidden from the feed by default.
    var isFilled: Bool
}

// MARK: - AmenVolunteerPost

/// Feed-layer volunteer opportunity posting.
///
/// CRITICAL: contactRef is always an Amen inbox reference.
/// Raw contact info is never stored here.
///
/// Stored at /volunteerPosts/{id}.
struct AmenVolunteerPost: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var orgId: String
    var orgName: String
    var description: String
    /// Human-readable commitment string e.g. "2 hours/week", "One-time event".
    var commitment: String
    var skills: [String]
    var location: String?
    var startDate: Date?
    var tags: [String]
    /// AMEN inbox thread reference. NEVER a raw email or phone number.
    var contactRef: String
    var provenance: SpawnProvenance?
    var postedBy: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var isFilled: Bool
}

// MARK: - AmenMentorshipPost

/// Mentorship request posting. A mentee describes what they are looking for.
///
/// CRITICAL: contactRef is always an Amen inbox reference.
/// isPublic controls whether this request appears in the feed or is invite-only.
///
/// Stored at /mentorshipPosts/{id}.
/// MentorshipPostStatus mirrors the intent of MentorshipStatus from AmenCoreModels,
/// but is specific to this feed-layer posting (open/inProgress/completed/cancelled).
struct AmenMentorshipPost: Codable, Identifiable, Sendable {
    var id: String
    var menteeId: String
    var topic: String
    var description: String
    /// Human-readable cadence: "Weekly", "Monthly", "As needed".
    var desiredFrequency: String
    var skills: [String]
    /// Public posts appear in the feed. Private posts are invite-only.
    var isPublic: Bool
    /// AMEN inbox thread reference. NEVER raw PII.
    var contactRef: String
    var provenance: SpawnProvenance?
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var status: MentorshipPostStatus
}

// MARK: - MentorshipPostStatus

/// Status of a mentorship *request posting* (distinct from MentorshipStatus in AmenCoreModels.swift,
/// which tracks an active pairing). Named MentorshipPostStatus to avoid the name collision.
enum MentorshipPostStatus: String, Codable, CaseIterable, Sendable {
    case open       = "open"
    case inProgress = "inProgress"
    case completed  = "completed"
    case cancelled  = "cancelled"

    var displayName: String {
        switch self {
        case .open:       return "Open"
        case .inProgress: return "In Progress"
        case .completed:  return "Completed"
        case .cancelled:  return "Cancelled"
        }
    }
}

// MARK: - AmenOpportunityApplication

/// Application record created when a user applies to any opportunity type.
/// The application message is routed via the Amen inbox — the poster's
/// email, phone, and any external contact info are never shared.
///
/// Stored at /opportunityApplications/{id}.
struct AmenOpportunityApplication: Codable, Identifiable, Sendable {
    var id: String
    var opportunityId: String
    var opportunityCategory: AmenOpportunityCategory
    var applicantId: String
    /// The intro message the applicant wrote. Delivered via Amen inbox thread.
    var message: String
    /// Optional reference to an uploaded resume or portfolio file in Firebase Storage.
    var resumeRef: String?
    /// Uses ApplicationStatus from JobModels.swift.
    var status: ApplicationStatus
    var createdAt: Date
    var isDeleted: Bool
}
