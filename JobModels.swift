// JobModels.swift
// AMENAPP
//
// Complete data model layer for AMEN Jobs & Opportunities platform.
// Follows StudioModels.swift conventions: Identifiable + Codable + @DocumentID,
// rich enums with label/icon/color, ModerationState reuse, AMENFeeConfig pattern.

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Job Listing

struct JobListing: Identifiable, Codable {
    @DocumentID var id: String?
    var employerId: String
    var employerName: String
    var employerLogoURL: String?
    var employerVerified: Bool
    var title: String
    var description: String
    var requirements: [String]
    var responsibilities: [String]
    var benefits: [String]
    var jobType: JobType
    var classification: JobClassification
    var workArrangement: WorkArrangement
    var category: JobCategory
    var skills: [String]
    var experienceLevel: ExperienceLevel
    var educationRequirement: EducationLevel?
    var location: String?
    var city: String?
    var state: String?
    var country: String?
    var compensationType: CompensationType
    var salaryMin: Double?
    var salaryMax: Double?
    var salaryCurrency: String
    var salaryPeriod: SalaryPeriod?
    var applicationDeadline: Date?
    var startDate: Date?
    var applyModel: ApplyModel
    var externalApplyURL: String?
    var screeningQuestions: [ScreeningQuestion]
    var isActive: Bool
    var isFeatured: Bool
    var featuredExpiry: Date?
    var isPromoted: Bool
    var promotedExpiry: Date?
    var postingTier: JobPostingTier
    var moderationState: ModerationState
    var safetyScore: Double        // 0.0–1.0 computed by JobSafetyEngine
    var viewCount: Int
    var applicationCount: Int
    var saveCount: Int
    var searchKeywords: [String]
    // P1 #7: Geohash proximity index — 5-char precision (~2.4 km bounding box).
    // Written on job creation via JobService.postJob. Used for Firestore range queries.
    // TODO: Deploy Firestore index for jobs(geohash ASC, isActive ASC)
    var latitude: Double?
    var longitude: Double?
    var geohash: String?
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?

    // MARK: Computed

    var formattedSalary: String {
        switch compensationType {
        case .volunteer:     return "Volunteer"
        case .undisclosed:   return "Undisclosed"
        case .negotiable:    return "Negotiable"
        default:
            guard let min = salaryMin else { return compensationType.label }
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = salaryCurrency
            formatter.maximumFractionDigits = 0
            let minStr = formatter.string(from: NSNumber(value: min)) ?? "$\(Int(min))"
            if let max = salaryMax {
                let maxStr = formatter.string(from: NSNumber(value: max)) ?? "$\(Int(max))"
                return "\(minStr) – \(maxStr)\(salaryPeriod.map { "/\($0.shortLabel)" } ?? "")"
            }
            return "\(minStr)+\(salaryPeriod.map { "/\($0.shortLabel)" } ?? "")"
        }
    }

    var isExpired: Bool {
        if let deadline = applicationDeadline {
            return deadline < Date()
        }
        if let exp = expiresAt {
            return exp < Date()
        }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case id, employerId, employerName, employerLogoURL, employerVerified
        case title, description, requirements, responsibilities, benefits
        case jobType, classification, workArrangement, category
        case skills, experienceLevel, educationRequirement
        case location, city, state, country
        case compensationType, salaryMin, salaryMax, salaryCurrency, salaryPeriod
        case applicationDeadline, startDate
        case applyModel, externalApplyURL, screeningQuestions
        case isActive, isFeatured, featuredExpiry, isPromoted, promotedExpiry
        case postingTier, moderationState, safetyScore
        case viewCount, applicationCount, saveCount, searchKeywords
        case latitude, longitude, geohash
        case createdAt, updatedAt, expiresAt
    }
}

// MARK: - Job Seeker Profile

struct JobSeekerProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var displayName: String
    var headline: String           // "Youth Pastor seeking full-time remote role"
    var bio: String
    var avatarURL: String?
    var resumeURL: String?
    var portfolioURL: String?
    var skills: [String]
    var experienceLevel: ExperienceLevel
    var desiredJobTypes: [JobType]
    var desiredCategories: [JobCategory]
    var desiredArrangements: [WorkArrangement]
    var desiredCompensationMin: Double?
    var desiredLocation: String?
    var openToRelocate: Bool
    var openToWorkVisibility: OpenToWorkVisibility
    var isActive: Bool
    var trustScore: Double          // 0.0–1.0
    var moderationState: ModerationState
    var searchKeywords: [String]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId, displayName, headline, bio, avatarURL
        case resumeURL, portfolioURL, skills, experienceLevel
        case desiredJobTypes, desiredCategories, desiredArrangements
        case desiredCompensationMin, desiredLocation, openToRelocate
        case openToWorkVisibility, isActive, trustScore, moderationState
        case searchKeywords, createdAt, updatedAt
    }
}

// MARK: - Employer Profile

struct EmployerProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var organizationName: String
    var organizationType: EmployerType
    var description: String
    var logoURL: String?
    var bannerURL: String?
    var websiteURL: String?
    var location: String?
    var employeeCount: EmployeeCount?
    var isVerified: Bool
    var verificationLevel: VerificationLevel
    var activeJobCount: Int
    var totalHires: Int
    var responseRate: Double        // 0–1
    var averageResponseDays: Double
    var subscriptionTier: RecruiterSubscriptionTier
    var trustScore: Double
    var moderationState: ModerationState
    var searchKeywords: [String]
    var createdAt: Date
    var updatedAt: Date

    var responseRateLabel: String {
        let pct = Int(responseRate * 100)
        return "\(pct)% response rate"
    }

    var responseTimeLabel: String {
        let days = Int(averageResponseDays)
        if days <= 1 { return "Responds within a day" }
        if days <= 3 { return "Responds within \(days) days" }
        return "Responds within a week"
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, organizationName, organizationType, description
        case logoURL, bannerURL, websiteURL, location, employeeCount
        case isVerified, verificationLevel, activeJobCount, totalHires
        case responseRate, averageResponseDays
        case subscriptionTier, trustScore, moderationState
        case searchKeywords, createdAt, updatedAt
    }
}

// MARK: - Job Application

struct JobApplication: Identifiable, Codable {
    @DocumentID var id: String?
    var jobId: String
    var jobTitle: String
    var employerId: String
    var applicantId: String
    var applicantName: String
    var applyModel: ApplyModel
    var coverNote: String?
    var resumeURL: String?
    var portfolioURL: String?
    var screeningAnswers: [ScreeningAnswer]
    var status: ApplicationStatus
    var employerNotes: String?
    var isRead: Bool
    var consentToShareProfile: Bool  // explicit consent before submit
    var moderationState: ModerationState
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, jobId, jobTitle, employerId, applicantId, applicantName
        case applyModel, coverNote, resumeURL, portfolioURL
        case screeningAnswers, status, employerNotes, isRead
        case consentToShareProfile, moderationState, createdAt, updatedAt
    }
}

// MARK: - Screening Question / Answer

struct ScreeningQuestion: Identifiable, Codable {
    var id: String = UUID().uuidString
    var question: String
    var questionType: ScreeningQuestionType
    var isRequired: Bool
    var options: [String]?          // for .multipleChoice

    enum CodingKeys: String, CodingKey {
        case id, question, questionType, isRequired, options
    }
}

struct ScreeningAnswer: Identifiable, Codable {
    var id: String = UUID().uuidString
    var questionId: String
    var answer: String

    enum CodingKeys: String, CodingKey {
        case id, questionId, answer
    }
}

// MARK: - Saved Job

struct SavedJob: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var jobId: String
    var jobTitle: String
    var employerName: String
    var savedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId, jobId, jobTitle, employerName, savedAt
    }
}

// MARK: - Job Alert

struct JobAlert: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var alertName: String
    var keywords: [String]
    var categories: [JobCategory]
    var jobTypes: [JobType]
    var arrangements: [WorkArrangement]
    var location: String?
    var isActive: Bool
    var frequency: AlertFrequency
    var lastTriggeredAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId, alertName, keywords, categories, jobTypes, arrangements
        case location, isActive, frequency, lastTriggeredAt, createdAt
    }
}

// MARK: - Match Results (local, not Firestore)

struct JobMatchResult: Identifiable {
    let id: String
    let job: JobListing
    var overallScore: Double           // 0–1 composite
    var skillMatchScore: Double
    var titleSimilarityScore: Double
    var experienceScore: Double
    var locationFitScore: Double
    var remoteFitScore: Double
    var compensationFitScore: Double
    var recruiterQualityScore: Double
    var safetyScore: Double
    var explanation: String            // "Why this matched" short text
    var matchReasons: [MatchReason]
}

struct MatchReason: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let score: Double
}

struct CandidateMatchResult: Identifiable {
    let id: String
    let seeker: JobSeekerProfile
    var overallScore: Double
    var skillMatchScore: Double
    var experienceScore: Double
    var explanation: String
}

// MARK: - Search Filters

struct JobSearchFilters {
    var jobTypes: Set<JobType> = []
    var classifications: Set<JobClassification> = []
    var arrangements: Set<WorkArrangement> = []
    var categories: Set<JobCategory> = []
    var experienceLevels: Set<ExperienceLevel> = []
    var compensationMin: Double?
    var compensationMax: Double?
    var location: String?
    var postedWithin: PostedWithin?
    var sortBy: JobSortOption = .relevance

    var isEmpty: Bool {
        jobTypes.isEmpty && classifications.isEmpty && arrangements.isEmpty &&
        categories.isEmpty && experienceLevels.isEmpty &&
        compensationMin == nil && compensationMax == nil &&
        location == nil && postedWithin == nil
    }

    var activeFilterCount: Int {
        var count = 0
        if !jobTypes.isEmpty { count += 1 }
        if !classifications.isEmpty { count += 1 }
        if !arrangements.isEmpty { count += 1 }
        if !categories.isEmpty { count += 1 }
        if !experienceLevels.isEmpty { count += 1 }
        if compensationMin != nil || compensationMax != nil { count += 1 }
        if location != nil { count += 1 }
        if postedWithin != nil { count += 1 }
        return count
    }
}

// MARK: - Fee Configuration

struct JobFeeConfig {
    // Posting tiers
    static let freePostingLimit: Int = 1
    static let standardPostingPrice: Double = 29.99
    static let premiumPostingPrice: Double = 79.99
    static let featuredPostingPrice: Double = 149.99
    // Boost
    static let promotedBoostPerDay: Double = 4.99
    // Recruiter subscriptions
    static let recruiterBasicMonthly: Double = 19.99
    static let recruiterProMonthly: Double = 49.99
    static let churchHiringMonthly: Double = 39.99
}

// MARK: - Notification Types

enum JobNotificationType: String {
    case newApplication         = "new_application"
    case applicationViewed      = "application_viewed"
    case applicationStatusUpdate = "application_status_update"
    case newJobMatch            = "new_job_match"
    case savedJobExpiring       = "saved_job_expiring"
    case jobAlertTriggered      = "job_alert_triggered"
    case recruiterMessage       = "recruiter_message"
    case interviewScheduled     = "interview_scheduled"
    case jobApproved            = "job_approved"
    case jobRejected            = "job_rejected"
    case jobExpired             = "job_expired"
}

// MARK: - Firestore Collection Constants

enum JobCollections {
    static let jobListings       = "jobListings"
    static let jobSeekerProfiles = "jobSeekerProfiles"
    static let employerProfiles  = "employerProfiles"
    static let jobApplications   = "jobApplications"
    static let savedJobs         = "savedJobs"
    static let jobAlerts         = "jobAlerts"
    static let analytics         = "jobAnalyticsEvents"
    static let moderationFlags   = "jobModerationFlags"
    static let notifications     = "jobNotifications"
}

// MARK: - JobType

enum JobType: String, Codable, CaseIterable, Identifiable {
    case fullTime       = "full_time"
    case partTime       = "part_time"
    case contract       = "contract"
    case freelance      = "freelance"
    case internship     = "internship"
    case volunteer      = "volunteer"
    case ministryStaff  = "ministry_staff"
    case churchStaff    = "church_staff"
    case paidCreator    = "paid_creator"
    case apprenticeship = "apprenticeship"
    case temporary      = "temporary"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullTime:      return "Full-Time"
        case .partTime:      return "Part-Time"
        case .contract:      return "Contract"
        case .freelance:     return "Freelance"
        case .internship:    return "Internship"
        case .volunteer:     return "Volunteer"
        case .ministryStaff: return "Ministry Staff"
        case .churchStaff:   return "Church Staff"
        case .paidCreator:   return "Paid Creator"
        case .apprenticeship: return "Apprenticeship"
        case .temporary:     return "Temporary"
        }
    }

    var icon: String {
        switch self {
        case .fullTime:      return "briefcase.fill"
        case .partTime:      return "clock.fill"
        case .contract:      return "doc.text.fill"
        case .freelance:     return "person.badge.key.fill"
        case .internship:    return "graduationcap.fill"
        case .volunteer:     return "hands.sparkles.fill"
        case .ministryStaff: return "cross.fill"
        case .churchStaff:   return "building.columns.fill"
        case .paidCreator:   return "camera.fill"
        case .apprenticeship: return "hammer.fill"
        case .temporary:     return "calendar.badge.clock"
        }
    }

    var color: Color {
        switch self {
        case .fullTime:      return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .partTime:      return Color(red: 0.30, green: 0.70, blue: 0.55)
        case .contract:      return Color(red: 0.70, green: 0.45, blue: 0.90)
        case .freelance:     return Color(red: 0.90, green: 0.55, blue: 0.20)
        case .internship:    return Color(red: 0.25, green: 0.75, blue: 0.75)
        case .volunteer:     return Color(red: 0.35, green: 0.80, blue: 0.35)
        case .ministryStaff: return Color(red: 0.85, green: 0.40, blue: 0.40)
        case .churchStaff:   return Color(red: 0.80, green: 0.60, blue: 0.25)
        case .paidCreator:   return Color(red: 0.95, green: 0.35, blue: 0.65)
        case .apprenticeship: return Color(red: 0.55, green: 0.45, blue: 0.85)
        case .temporary:     return Color(red: 0.60, green: 0.60, blue: 0.70)
        }
    }
}

// MARK: - JobClassification

enum JobClassification: String, Codable, CaseIterable, Identifiable {
    case christianOrg    = "christian_org"
    case churchMinistry  = "church_ministry"
    case secular         = "secular"
    case faithFriendly   = "faith_friendly"
    case missionOrg      = "mission_org"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .christianOrg:   return "Christian Org"
        case .churchMinistry: return "Church / Ministry"
        case .secular:        return "Secular"
        case .faithFriendly:  return "Faith-Friendly"
        case .missionOrg:     return "Mission Org"
        }
    }

    var icon: String {
        switch self {
        case .christianOrg:   return "cross.circle.fill"
        case .churchMinistry: return "building.columns.fill"
        case .secular:        return "globe"
        case .faithFriendly:  return "heart.circle.fill"
        case .missionOrg:     return "airplane"
        }
    }

    var color: Color {
        switch self {
        case .christianOrg:   return Color(red: 0.85, green: 0.40, blue: 0.40)
        case .churchMinistry: return Color(red: 0.80, green: 0.60, blue: 0.25)
        case .secular:        return Color(red: 0.45, green: 0.55, blue: 0.70)
        case .faithFriendly:  return Color(red: 0.35, green: 0.75, blue: 0.55)
        case .missionOrg:     return Color(red: 0.25, green: 0.65, blue: 0.85)
        }
    }
}

// MARK: - WorkArrangement

enum WorkArrangement: String, Codable, CaseIterable, Identifiable {
    case remote  = "remote"
    case hybrid  = "hybrid"
    case onSite  = "on_site"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        case .onSite: return "On-Site"
        }
    }

    var icon: String {
        switch self {
        case .remote: return "wifi"
        case .hybrid: return "building.2.fill"
        case .onSite: return "mappin.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .remote: return Color(red: 0.20, green: 0.70, blue: 0.50)
        case .hybrid: return Color(red: 0.70, green: 0.50, blue: 0.90)
        case .onSite: return Color(red: 0.90, green: 0.50, blue: 0.25)
        }
    }
}

// MARK: - JobCategory

enum JobCategory: String, Codable, CaseIterable, Identifiable {
    case pastoralMinistry  = "pastoral_ministry"
    case worship           = "worship"
    case youthMinistry     = "youth_ministry"
    case administration    = "administration"
    case education         = "education"
    case technology        = "technology"
    case design            = "design"
    case media             = "media"
    case healthcare        = "healthcare"
    case counseling        = "counseling"
    case missions          = "missions"
    case socialWork        = "social_work"
    case finance           = "finance"
    case marketing         = "marketing"
    case chaplaincy        = "chaplaincy"
    case nonprofit         = "nonprofit"
    case communityOutreach = "community_outreach"
    case childrenMinistry  = "children_ministry"
    case familyMinistry    = "family_ministry"
    case other             = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pastoralMinistry:  return "Pastoral Ministry"
        case .worship:           return "Worship"
        case .youthMinistry:     return "Youth Ministry"
        case .administration:    return "Administration"
        case .education:         return "Education"
        case .technology:        return "Technology"
        case .design:            return "Design"
        case .media:             return "Media"
        case .healthcare:        return "Healthcare"
        case .counseling:        return "Counseling"
        case .missions:          return "Missions"
        case .socialWork:        return "Social Work"
        case .finance:           return "Finance"
        case .marketing:         return "Marketing"
        case .chaplaincy:        return "Chaplaincy"
        case .nonprofit:         return "Nonprofit"
        case .communityOutreach: return "Community Outreach"
        case .childrenMinistry:  return "Children's Ministry"
        case .familyMinistry:    return "Family Ministry"
        case .other:             return "Other"
        }
    }

    var icon: String {
        switch self {
        case .pastoralMinistry:  return "cross.fill"
        case .worship:           return "music.note"
        case .youthMinistry:     return "figure.walk"
        case .administration:    return "folder.fill"
        case .education:         return "book.fill"
        case .technology:        return "desktopcomputer"
        case .design:            return "paintbrush.fill"
        case .media:             return "video.fill"
        case .healthcare:        return "stethoscope"
        case .counseling:        return "bubble.left.and.bubble.right.fill"
        case .missions:          return "airplane"
        case .socialWork:        return "hands.sparkles.fill"
        case .finance:           return "dollarsign.circle.fill"
        case .marketing:         return "megaphone.fill"
        case .chaplaincy:        return "person.and.background.striped.horizontal"
        case .nonprofit:         return "heart.fill"
        case .communityOutreach: return "figure.2.arms.open"
        case .childrenMinistry:  return "figure.and.child.holdinghands"
        case .familyMinistry:    return "house.fill"
        case .other:             return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pastoralMinistry:  return Color(red: 0.85, green: 0.40, blue: 0.40)
        case .worship:           return Color(red: 0.75, green: 0.45, blue: 0.90)
        case .youthMinistry:     return Color(red: 0.20, green: 0.75, blue: 0.55)
        case .administration:    return Color(red: 0.45, green: 0.55, blue: 0.75)
        case .education:         return Color(red: 0.30, green: 0.65, blue: 0.90)
        case .technology:        return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .design:            return Color(red: 0.95, green: 0.45, blue: 0.65)
        case .media:             return Color(red: 0.90, green: 0.35, blue: 0.35)
        case .healthcare:        return Color(red: 0.35, green: 0.80, blue: 0.65)
        case .counseling:        return Color(red: 0.60, green: 0.45, blue: 0.85)
        case .missions:          return Color(red: 0.25, green: 0.65, blue: 0.85)
        case .socialWork:        return Color(red: 0.35, green: 0.80, blue: 0.35)
        case .finance:           return Color(red: 0.25, green: 0.70, blue: 0.45)
        case .marketing:         return Color(red: 0.90, green: 0.55, blue: 0.20)
        case .chaplaincy:        return Color(red: 0.70, green: 0.50, blue: 0.40)
        case .nonprofit:         return Color(red: 0.85, green: 0.35, blue: 0.55)
        case .communityOutreach: return Color(red: 0.55, green: 0.75, blue: 0.30)
        case .childrenMinistry:  return Color(red: 0.95, green: 0.70, blue: 0.20)
        case .familyMinistry:    return Color(red: 0.80, green: 0.55, blue: 0.30)
        case .other:             return Color(red: 0.60, green: 0.60, blue: 0.65)
        }
    }
}

// MARK: - ExperienceLevel

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case noExperience = "no_experience"
    case entryLevel   = "entry_level"
    case midLevel     = "mid_level"
    case seniorLevel  = "senior_level"
    case lead         = "lead"
    case executive    = "executive"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noExperience: return "No Experience Required"
        case .entryLevel:   return "Entry Level"
        case .midLevel:     return "Mid Level"
        case .seniorLevel:  return "Senior Level"
        case .lead:         return "Lead / Principal"
        case .executive:    return "Executive / Director"
        }
    }

    var icon: String {
        switch self {
        case .noExperience: return "person.fill"
        case .entryLevel:   return "star.fill"
        case .midLevel:     return "star.leadinghalf.filled"
        case .seniorLevel:  return "star.fill"
        case .lead:         return "rosette"
        case .executive:    return "crown.fill"
        }
    }

    var yearsRange: String {
        switch self {
        case .noExperience: return "0 years"
        case .entryLevel:   return "0–2 years"
        case .midLevel:     return "2–5 years"
        case .seniorLevel:  return "5–10 years"
        case .lead:         return "7+ years"
        case .executive:    return "10+ years"
        }
    }
}

// MARK: - EducationLevel

enum EducationLevel: String, Codable, CaseIterable, Identifiable {
    case none       = "none"
    case highSchool = "high_school"
    case associates = "associates"
    case bachelors  = "bachelors"
    case masters    = "masters"
    case doctorate  = "doctorate"
    case seminary   = "seminary"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:       return "No Requirement"
        case .highSchool: return "High School Diploma"
        case .associates: return "Associate's Degree"
        case .bachelors:  return "Bachelor's Degree"
        case .masters:    return "Master's Degree"
        case .doctorate:  return "Doctorate"
        case .seminary:   return "Seminary / Theological"
        }
    }
}

// MARK: - CompensationType

enum CompensationType: String, Codable, CaseIterable, Identifiable {
    case salaried    = "salaried"
    case hourly      = "hourly"
    case stipend     = "stipend"
    case volunteer   = "volunteer"
    case negotiable  = "negotiable"
    case undisclosed = "undisclosed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .salaried:    return "Salary"
        case .hourly:      return "Hourly"
        case .stipend:     return "Stipend"
        case .volunteer:   return "Unpaid / Volunteer"
        case .negotiable:  return "Negotiable"
        case .undisclosed: return "Not Disclosed"
        }
    }

    var icon: String {
        switch self {
        case .salaried:    return "dollarsign.circle.fill"
        case .hourly:      return "clock.fill"
        case .stipend:     return "banknote.fill"
        case .volunteer:   return "hands.sparkles.fill"
        case .negotiable:  return "arrow.left.arrow.right.circle.fill"
        case .undisclosed: return "eye.slash.fill"
        }
    }
}

// MARK: - SalaryPeriod

enum SalaryPeriod: String, Codable, CaseIterable, Identifiable {
    case annual  = "annual"
    case monthly = "monthly"
    case weekly  = "weekly"
    case hourly  = "hourly"
    case project = "project"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .annual:  return "Per Year"
        case .monthly: return "Per Month"
        case .weekly:  return "Per Week"
        case .hourly:  return "Per Hour"
        case .project: return "Per Project"
        }
    }

    var shortLabel: String {
        switch self {
        case .annual:  return "yr"
        case .monthly: return "mo"
        case .weekly:  return "wk"
        case .hourly:  return "hr"
        case .project: return "project"
        }
    }
}

// MARK: - ApplyModel

enum ApplyModel: String, Codable, CaseIterable, Identifiable {
    case externalApply   = "external_apply"
    case amenEasyApply   = "amen_easy_apply"
    case expressInterest = "express_interest"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .externalApply:   return "Apply on Site"
        case .amenEasyApply:   return "Easy Apply"
        case .expressInterest: return "Express Interest"
        }
    }

    var icon: String {
        switch self {
        case .externalApply:   return "arrow.up.right.square.fill"
        case .amenEasyApply:   return "checkmark.seal.fill"
        case .expressInterest: return "hand.raised.fill"
        }
    }

    var ctaLabel: String {
        switch self {
        case .externalApply:   return "Apply on Employer Site"
        case .amenEasyApply:   return "Easy Apply"
        case .expressInterest: return "Express Interest"
        }
    }
}

// MARK: - JobPostingTier

enum JobPostingTier: String, Codable, CaseIterable, Identifiable {
    case free     = "free"
    case standard = "standard"
    case premium  = "premium"
    case featured = "featured"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free:     return "Free"
        case .standard: return "Standard"
        case .premium:  return "Premium"
        case .featured: return "Featured"
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .free:     return 0.0
        case .standard: return 29.99
        case .premium:  return 79.99
        case .featured: return 149.99
        }
    }

    var maxActiveListings: Int {
        switch self {
        case .free:     return 1
        case .standard: return 5
        case .premium:  return 20
        case .featured: return 50
        }
    }

    var includesFeaturedPlacement: Bool {
        self == .featured
    }

    var includesAnalytics: Bool {
        self == .premium || self == .featured
    }
}

// MARK: - ApplicationStatus

enum ApplicationStatus: String, Codable, CaseIterable, Identifiable {
    case submitted    = "submitted"
    case viewed       = "viewed"
    case shortlisted  = "shortlisted"
    case interviewing = "interviewing"
    case offered      = "offered"
    case hired        = "hired"
    case declined     = "declined"
    case withdrawn    = "withdrawn"
    case expired      = "expired"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .submitted:    return "Submitted"
        case .viewed:       return "Viewed"
        case .shortlisted:  return "Shortlisted"
        case .interviewing: return "Interviewing"
        case .offered:      return "Offer Received"
        case .hired:        return "Hired"
        case .declined:     return "Not Selected"
        case .withdrawn:    return "Withdrawn"
        case .expired:      return "Expired"
        }
    }

    var icon: String {
        switch self {
        case .submitted:    return "paperplane.fill"
        case .viewed:       return "eye.fill"
        case .shortlisted:  return "star.fill"
        case .interviewing: return "person.2.fill"
        case .offered:      return "envelope.badge.fill"
        case .hired:        return "checkmark.seal.fill"
        case .declined:     return "xmark.circle.fill"
        case .withdrawn:    return "arrow.uturn.backward.circle.fill"
        case .expired:      return "clock.badge.xmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .submitted:    return Color(red: 0.45, green: 0.55, blue: 0.75)
        case .viewed:       return Color(red: 0.55, green: 0.55, blue: 0.75)
        case .shortlisted:  return Color(red: 0.90, green: 0.65, blue: 0.20)
        case .interviewing: return Color(red: 0.30, green: 0.70, blue: 0.90)
        case .offered:      return Color(red: 0.30, green: 0.75, blue: 0.55)
        case .hired:        return Color(red: 0.20, green: 0.80, blue: 0.45)
        case .declined:     return Color(red: 0.80, green: 0.35, blue: 0.35)
        case .withdrawn:    return Color(red: 0.60, green: 0.60, blue: 0.65)
        case .expired:      return Color(red: 0.55, green: 0.55, blue: 0.55)
        }
    }

    var isTerminal: Bool {
        self == .hired || self == .declined || self == .withdrawn || self == .expired
    }
}

// MARK: - OpenToWorkVisibility

enum OpenToWorkVisibility: String, Codable, CaseIterable, Identifiable {
    case publicVisible          = "public"
    case verifiedRecruitersOnly = "verified_recruiters"
    case churchesOnly           = "churches_only"
    case privateUntilApplying   = "private"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .publicVisible:          return "Everyone"
        case .verifiedRecruitersOnly: return "Verified Recruiters Only"
        case .churchesOnly:           return "Churches & Ministries Only"
        case .privateUntilApplying:   return "Private (Until I Apply)"
        }
    }

    var description: String {
        switch self {
        case .publicVisible:
            return "Anyone on AMEN can see you're open to work."
        case .verifiedRecruitersOnly:
            return "Only verified employers can discover your profile."
        case .churchesOnly:
            return "Only verified churches and ministries can find you."
        case .privateUntilApplying:
            return "Your profile is hidden until you apply to a specific role."
        }
    }

    var icon: String {
        switch self {
        case .publicVisible:          return "globe"
        case .verifiedRecruitersOnly: return "checkmark.shield.fill"
        case .churchesOnly:           return "building.columns.fill"
        case .privateUntilApplying:   return "eye.slash.fill"
        }
    }
}

// MARK: - EmployerType

enum EmployerType: String, Codable, CaseIterable, Identifiable {
    case church             = "church"
    case ministry           = "ministry"
    case christianNonprofit = "christian_nonprofit"
    case faithFriendlyCompany = "faith_friendly_company"
    case christianSchool    = "christian_school"
    case missionOrg         = "mission_org"
    case mediaMinistry      = "media_ministry"
    case individual         = "individual"
    case other              = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .church:               return "Church"
        case .ministry:             return "Ministry"
        case .christianNonprofit:   return "Christian Nonprofit"
        case .faithFriendlyCompany: return "Faith-Friendly Company"
        case .christianSchool:      return "Christian School"
        case .missionOrg:           return "Mission Organization"
        case .mediaMinistry:        return "Media Ministry"
        case .individual:           return "Individual / Freelance"
        case .other:                return "Other"
        }
    }

    var icon: String {
        switch self {
        case .church:               return "building.columns.fill"
        case .ministry:             return "cross.fill"
        case .christianNonprofit:   return "heart.fill"
        case .faithFriendlyCompany: return "building.2.fill"
        case .christianSchool:      return "graduationcap.fill"
        case .missionOrg:           return "airplane"
        case .mediaMinistry:        return "video.fill"
        case .individual:           return "person.fill"
        case .other:                return "ellipsis.circle.fill"
        }
    }
}

// MARK: - EmployeeCount

enum EmployeeCount: String, Codable, CaseIterable, Identifiable {
    case solo         = "solo"
    case small2to10   = "2_10"
    case medium11to50 = "11_50"
    case large51to200 = "51_200"
    case enterprise201plus = "201_plus"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solo:           return "Solo"
        case .small2to10:     return "2–10 employees"
        case .medium11to50:   return "11–50 employees"
        case .large51to200:   return "51–200 employees"
        case .enterprise201plus: return "201+ employees"
        }
    }
}

// MARK: - RecruiterSubscriptionTier

enum RecruiterSubscriptionTier: String, Codable, CaseIterable, Identifiable {
    case free         = "free"
    case basic        = "basic"
    case professional = "professional"
    case churchHiring = "church_hiring"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free:         return "Free"
        case .basic:        return "Basic"
        case .professional: return "Professional"
        case .churchHiring: return "Church Hiring"
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .free:         return 0.0
        case .basic:        return 19.99
        case .professional: return 49.99
        case .churchHiring: return 39.99
        }
    }

    var maxActiveJobs: Int {
        switch self {
        case .free:         return 1
        case .basic:        return 5
        case .professional: return 25
        case .churchHiring: return 15
        }
    }

    var canMessageCandidates: Bool {
        self != .free
    }

    var includesAnalytics: Bool {
        self == .professional || self == .churchHiring
    }
}

// MARK: - AlertFrequency

enum AlertFrequency: String, Codable, CaseIterable, Identifiable {
    case instant = "instant"
    case daily   = "daily"
    case weekly  = "weekly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instant: return "Instantly"
        case .daily:   return "Daily Digest"
        case .weekly:  return "Weekly Digest"
        }
    }
}

// MARK: - ScreeningQuestionType

enum ScreeningQuestionType: String, Codable, CaseIterable, Identifiable {
    case freeText       = "free_text"
    case yesNo          = "yes_no"
    case multipleChoice = "multiple_choice"
    case numeric        = "numeric"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .freeText:       return "Free Response"
        case .yesNo:          return "Yes / No"
        case .multipleChoice: return "Multiple Choice"
        case .numeric:        return "Number"
        }
    }
}

// MARK: - PostedWithin

enum PostedWithin: String, Codable, CaseIterable, Identifiable {
    case past24Hours = "24h"
    case pastWeek    = "7d"
    case pastMonth   = "30d"
    case anytime     = "anytime"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .past24Hours: return "Last 24 hours"
        case .pastWeek:    return "Last week"
        case .pastMonth:   return "Last month"
        case .anytime:     return "Any time"
        }
    }

    var cutoffDate: Date? {
        let cal = Calendar.current
        switch self {
        case .past24Hours: return cal.date(byAdding: .hour, value: -24, to: Date())
        case .pastWeek:    return cal.date(byAdding: .day, value: -7, to: Date())
        case .pastMonth:   return cal.date(byAdding: .day, value: -30, to: Date())
        case .anytime:     return nil
        }
    }
}

// MARK: - JobSortOption

enum JobSortOption: String, Codable, CaseIterable, Identifiable {
    case relevance        = "relevance"
    case newest           = "newest"
    case salaryHighToLow  = "salary_high"
    case salaryLowToHigh  = "salary_low"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance:       return "Most Relevant"
        case .newest:          return "Newest"
        case .salaryHighToLow: return "Salary: High to Low"
        case .salaryLowToHigh: return "Salary: Low to High"
        }
    }
}

// MARK: - Job Moderation Flag

struct JobModerationFlag: Identifiable, Codable {
    @DocumentID var id: String?
    var targetId: String             // jobId or employerId
    var targetType: String           // "job" or "employer"
    var reporterId: String
    var reason: JobModerationReason
    var flagDescription: String?
    var status: JobFlagStatus
    var actionTaken: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, targetId, targetType, reporterId
        case reason, flagDescription, status, actionTaken, createdAt
    }
}

enum JobModerationReason: String, Codable, CaseIterable {
    case scamJob              = "scam_job"
    case fakeRecruiter        = "fake_recruiter"
    case advanceFee           = "advance_fee"
    case predatoryReligious   = "predatory_religious"
    case exploitativeVolunteer = "exploitative_volunteer"
    case traffickingConcern   = "trafficking_concern"
    case harassmentContact    = "harassment_contact"
    case misleadingInfo       = "misleading_info"
    case inappropriateContent = "inappropriate_content"
    case other                = "other"

    var label: String {
        switch self {
        case .scamJob:              return "Scam Job Listing"
        case .fakeRecruiter:        return "Fake Recruiter"
        case .advanceFee:           return "Advance-Fee Fraud"
        case .predatoryReligious:   return "Predatory Religious Content"
        case .exploitativeVolunteer: return "Exploitative Volunteer Role"
        case .traffickingConcern:   return "Trafficking / Safety Concern"
        case .harassmentContact:    return "Harassment via Messaging"
        case .misleadingInfo:       return "Misleading Information"
        case .inappropriateContent: return "Inappropriate Content"
        case .other:                return "Other"
        }
    }
}

enum JobFlagStatus: String, Codable {
    case pending  = "pending"
    case reviewed = "reviewed"
    case resolved = "resolved"
    case dismissed = "dismissed"
}
