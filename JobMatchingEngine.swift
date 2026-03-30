// JobMatchingEngine.swift
// AMENAPP
//
// On-device job-to-seeker matching pipeline.
// Follows StudioRankingEngine pattern: static struct, pure functions, weighted scoring.
//
// Pipeline:
//   1. Hard filters (must-have requirements)
//   2. Search retrieval (keyword + category match)
//   3. Compatibility scoring (10 weighted dimensions)
//   4. Safety filtering (suppress unsafe jobs)
//   5. Explainable reranking (build "Why this matched" explanations)

import Foundation
import SwiftUI

// MARK: - Match Score Breakdown

struct MatchScoreBreakdown {
    var skillMatch: Double         = 0
    var titleSimilarity: Double    = 0
    var experience: Double         = 0
    var locationFit: Double        = 0
    var remoteFit: Double          = 0
    var compensationFit: Double    = 0
    var availability: Double       = 0.5   // default neutral
    var recruiterQuality: Double   = 0.5   // default neutral
    var trustScore: Double         = 0
    var safetyScore: Double        = 0
}

// MARK: - Match Weights

private struct MatchWeights {
    let skillMatch: Double      = 0.20
    let titleSimilarity: Double = 0.10
    let experience: Double      = 0.10
    let locationFit: Double     = 0.10
    let remoteFit: Double       = 0.08
    let compensationFit: Double = 0.07
    let availability: Double    = 0.05
    let recruiterQuality: Double = 0.10
    let trustScore: Double      = 0.10
    let safetyScore: Double     = 0.10
}

private let weights = MatchWeights()

// MARK: - Safety Threshold

private let minimumSafetyScore: Double = 0.40   // Jobs below this are suppressed

// MARK: - JobMatchingEngine

struct JobMatchingEngine {

    // MARK: - Primary: Match Jobs to Seeker

    /// Returns ranked job matches for a job seeker.
    /// - Parameters:
    ///   - seeker: The job seeker profile
    ///   - jobs: Pool of active job listings to match against
    ///   - employers: Map of employerId -> EmployerProfile for quality scoring
    static func matchJobsForSeeker(
        seeker: JobSeekerProfile,
        jobs: [JobListing],
        employers: [String: EmployerProfile] = [:]
    ) -> [JobMatchResult] {
        // Step 1: Hard filters
        let filtered = applyHardFilters(seeker: seeker, jobs: jobs)

        // Step 2: Score each job
        var results: [JobMatchResult] = filtered.compactMap { job in
            let employer = employers[job.employerId]
            let breakdown = computeScoreBreakdown(seeker: seeker, job: job, employer: employer)
            let overall = computeWeightedScore(breakdown)
            guard overall > 0.05 else { return nil }  // skip extremely low matches
            let (explanation, reasons) = buildExplanation(scores: breakdown, job: job, seeker: seeker)
            return JobMatchResult(
                id: job.id ?? UUID().uuidString,
                job: job,
                overallScore: overall,
                skillMatchScore: breakdown.skillMatch,
                titleSimilarityScore: breakdown.titleSimilarity,
                experienceScore: breakdown.experience,
                locationFitScore: breakdown.locationFit,
                remoteFitScore: breakdown.remoteFit,
                compensationFitScore: breakdown.compensationFit,
                recruiterQualityScore: breakdown.recruiterQuality,
                safetyScore: breakdown.safetyScore,
                explanation: explanation,
                matchReasons: reasons
            )
        }

        // Step 3: Safety filter
        results = applySafetyFilter(results)

        // Step 4: Sort by overall score descending
        results.sort { $0.overallScore > $1.overallScore }

        return results
    }

    // MARK: - Secondary: Match Seekers to Job

    /// Returns ranked candidate matches for a job (employer-facing).
    static func matchSeekersForJob(
        job: JobListing,
        seekers: [JobSeekerProfile]
    ) -> [CandidateMatchResult] {
        let eligible = seekers.filter { seeker in
            // Only active seekers who have open visibility (or are in churchesOnly for church jobs)
            guard seeker.isActive else { return false }
            if seeker.openToWorkVisibility == .privateUntilApplying { return false }
            if seeker.openToWorkVisibility == .churchesOnly {
                // Only show to church/ministry jobs
                return job.classification == .churchMinistry
            }
            if seeker.moderationState != .active { return false }
            return true
        }

        var results: [CandidateMatchResult] = eligible.compactMap { seeker in
            let skillScore = computeSkillMatchForJob(job: job, seeker: seeker)
            let expScore   = computeExperienceFit(seekerLevel: seeker.experienceLevel, jobLevel: job.experienceLevel)
            let overall    = (skillScore * 0.50) + (expScore * 0.30) + (seeker.trustScore * 0.20)
            guard overall > 0.05 else { return nil }

            let reasons = buildCandidateExplanation(skillScore: skillScore, expScore: expScore, seeker: seeker, job: job)
            return CandidateMatchResult(
                id: seeker.userId,
                seeker: seeker,
                overallScore: overall,
                skillMatchScore: skillScore,
                experienceScore: expScore,
                explanation: reasons
            )
        }

        results.sort { $0.overallScore > $1.overallScore }
        return results
    }

    // MARK: - Hard Filters

    private static func applyHardFilters(seeker: JobSeekerProfile, jobs: [JobListing]) -> [JobListing] {
        return jobs.filter { job in
            // Must be active and not expired
            guard job.isActive && !job.isExpired else { return false }
            // Must pass moderation
            guard job.moderationState == .active else { return false }
            // If seeker has desired arrangements, job must match at least one
            if !seeker.desiredArrangements.isEmpty &&
               !seeker.desiredArrangements.contains(job.workArrangement) { return false }
            // If seeker has desired types, job must match at least one
            if !seeker.desiredJobTypes.isEmpty &&
               !seeker.desiredJobTypes.contains(job.jobType) { return false }
            return true
        }
    }

    // MARK: - Score Breakdown

    private static func computeScoreBreakdown(
        seeker: JobSeekerProfile,
        job: JobListing,
        employer: EmployerProfile?
    ) -> MatchScoreBreakdown {
        var b = MatchScoreBreakdown()
        b.skillMatch       = computeSkillMatch(seekerSkills: seeker.skills, jobSkills: job.skills)
        b.titleSimilarity  = computeTitleSimilarity(seekerHeadline: seeker.headline, jobTitle: job.title)
        b.experience       = computeExperienceFit(seekerLevel: seeker.experienceLevel, jobLevel: job.experienceLevel)
        b.locationFit      = computeLocationFit(seekerLocation: seeker.desiredLocation, jobCity: job.city, jobCountry: job.country, arrangement: job.workArrangement)
        b.remoteFit        = computeRemoteFit(seeker: seeker, job: job)
        b.compensationFit  = computeCompensationFit(seekerMin: seeker.desiredCompensationMin, jobMin: job.salaryMin, jobMax: job.salaryMax, compType: job.compensationType)
        b.recruiterQuality = computeRecruiterQuality(employer: employer, isVerified: job.employerVerified)
        b.trustScore       = job.employerVerified ? 0.85 : 0.50
        b.safetyScore      = job.safetyScore
        return b
    }

    // MARK: - Weighted Score

    private static func computeWeightedScore(_ b: MatchScoreBreakdown) -> Double {
        return (b.skillMatch       * weights.skillMatch)
             + (b.titleSimilarity  * weights.titleSimilarity)
             + (b.experience       * weights.experience)
             + (b.locationFit      * weights.locationFit)
             + (b.remoteFit        * weights.remoteFit)
             + (b.compensationFit  * weights.compensationFit)
             + (b.availability     * weights.availability)
             + (b.recruiterQuality * weights.recruiterQuality)
             + (b.trustScore       * weights.trustScore)
             + (b.safetyScore      * weights.safetyScore)
    }

    // MARK: - Skill Match (Jaccard similarity)

    static func computeSkillMatch(seekerSkills: [String], jobSkills: [String]) -> Double {
        guard !jobSkills.isEmpty else { return 0.5 }  // no skills listed = neutral
        guard !seekerSkills.isEmpty else { return 0.1 }

        let seekerNorm = Set(seekerSkills.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        let jobNorm    = Set(jobSkills.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })

        let intersection = seekerNorm.intersection(jobNorm).count
        let union = seekerNorm.union(jobNorm).count

        guard union > 0 else { return 0 }
        let jaccard = Double(intersection) / Double(union)

        // Bonus for high overlap
        let coverageBonus = Double(intersection) / Double(jobNorm.count) * 0.20
        return min(jaccard + coverageBonus, 1.0)
    }

    static func computeSkillMatchForJob(job: JobListing, seeker: JobSeekerProfile) -> Double {
        computeSkillMatch(seekerSkills: seeker.skills, jobSkills: job.skills)
    }

    // MARK: - Title Similarity

    static func computeTitleSimilarity(seekerHeadline: String, jobTitle: String) -> Double {
        let headlineWords = Set(seekerHeadline.lowercased().split(separator: " ").map(String.init))
        let titleWords    = Set(jobTitle.lowercased().split(separator: " ").map(String.init))

        let commonWords = Set(["a", "an", "the", "and", "or", "for", "of", "in", "to", "at", "with"])
        let meaningful = headlineWords.subtracting(commonWords)
        let titleMeaningful = titleWords.subtracting(commonWords)

        guard !titleMeaningful.isEmpty else { return 0.3 }
        let overlap = meaningful.intersection(titleMeaningful).count
        return min(Double(overlap) / Double(titleMeaningful.count), 1.0)
    }

    // MARK: - Experience Fit

    static func computeExperienceFit(seekerLevel: ExperienceLevel, jobLevel: ExperienceLevel) -> Double {
        let levels: [ExperienceLevel] = [.noExperience, .entryLevel, .midLevel, .seniorLevel, .lead, .executive]
        guard let seekerIdx = levels.firstIndex(of: seekerLevel),
              let jobIdx = levels.firstIndex(of: jobLevel) else { return 0.5 }

        let diff = abs(seekerIdx - jobIdx)
        switch diff {
        case 0: return 1.0   // exact match
        case 1: return 0.75  // one level off
        case 2: return 0.40  // two levels off
        default: return 0.10 // too far apart
        }
    }

    // MARK: - Location Fit

    static func computeLocationFit(
        seekerLocation: String?,
        jobCity: String?,
        jobCountry: String?,
        arrangement: WorkArrangement
    ) -> Double {
        // Remote jobs are location-agnostic
        if arrangement == .remote { return 0.9 }

        guard let seekerLoc = seekerLocation?.lowercased(), !seekerLoc.isEmpty else {
            return 0.5  // unknown seeker location = neutral
        }
        guard let jobCity = jobCity?.lowercased() else { return 0.5 }

        // Simple string matching for city/country
        if seekerLoc.contains(jobCity) || jobCity.contains(seekerLoc) { return 1.0 }
        if let country = jobCountry?.lowercased(), seekerLoc.contains(country) { return 0.6 }
        return 0.2
    }

    // MARK: - Remote Fit

    static func computeRemoteFit(seeker: JobSeekerProfile, job: JobListing) -> Double {
        let prefersRemote = seeker.desiredArrangements.contains(.remote)
        let jobIsRemote   = job.workArrangement == .remote
        let jobIsHybrid   = job.workArrangement == .hybrid

        if prefersRemote && jobIsRemote { return 1.0 }
        if prefersRemote && jobIsHybrid { return 0.7 }
        if !prefersRemote && jobIsRemote { return 0.6 }
        if !prefersRemote && job.workArrangement == .onSite { return 0.9 }
        return 0.5
    }

    // MARK: - Compensation Fit

    static func computeCompensationFit(
        seekerMin: Double?,
        jobMin: Double?,
        jobMax: Double?,
        compType: CompensationType
    ) -> Double {
        // Volunteer/undisclosed/negotiable are acceptable to all by default
        if compType == .volunteer || compType == .undisclosed || compType == .negotiable {
            return 0.6
        }

        guard let seekerMin = seekerMin, let jobMax = jobMax else { return 0.5 }

        if jobMax >= seekerMin {
            // Job pays at or above seeker minimum
            let ratio = jobMax / seekerMin
            return min(ratio * 0.7, 1.0)
        } else {
            // Job pays below seeker minimum
            let ratio = jobMax / seekerMin
            return max(ratio * 0.5, 0.0)
        }
    }

    // MARK: - Recruiter Quality

    static func computeRecruiterQuality(employer: EmployerProfile?, isVerified: Bool) -> Double {
        guard let employer = employer else {
            return isVerified ? 0.65 : 0.40
        }

        var score = 0.50
        if employer.isVerified { score += 0.20 }
        if employer.responseRate >= 0.80 { score += 0.15 }
        else if employer.responseRate >= 0.50 { score += 0.05 }
        if employer.totalHires > 10 { score += 0.10 }
        if employer.trustScore >= 0.70 { score += 0.05 }

        return min(score, 1.0)
    }

    // MARK: - Safety Filter

    private static func applySafetyFilter(_ results: [JobMatchResult]) -> [JobMatchResult] {
        results.filter { $0.safetyScore >= minimumSafetyScore }
    }

    // MARK: - Explanation Builder

    static func buildExplanation(
        scores: MatchScoreBreakdown,
        job: JobListing,
        seeker: JobSeekerProfile
    ) -> (String, [MatchReason]) {
        var reasons: [MatchReason] = []

        // Skill match
        if scores.skillMatch >= 0.60 {
            let sharedSkills = seeker.skills.filter { s in
                job.skills.contains(where: { $0.lowercased() == s.lowercased() })
            }.prefix(3).joined(separator: ", ")
            if !sharedSkills.isEmpty {
                reasons.append(MatchReason(icon: "checkmark.seal.fill", text: "Matches your skills in \(sharedSkills)", score: scores.skillMatch))
            }
        }

        // Remote fit
        if scores.remoteFit >= 0.85 && job.workArrangement == .remote {
            reasons.append(MatchReason(icon: "wifi", text: "Remote role aligned to your preferences", score: scores.remoteFit))
        }

        // Location fit
        if scores.locationFit >= 0.80 && job.workArrangement == .onSite, let city = job.city {
            reasons.append(MatchReason(icon: "mappin.circle.fill", text: "Opportunity in or near \(city)", score: scores.locationFit))
        }

        // Compensation fit
        if scores.compensationFit >= 0.75 {
            reasons.append(MatchReason(icon: "dollarsign.circle.fill", text: "Compensation aligns with your expectations", score: scores.compensationFit))
        }

        // Ministry/church classification
        if job.classification == .churchMinistry {
            reasons.append(MatchReason(icon: "building.columns.fill", text: "Church or ministry opportunity", score: 0.8))
        }

        // Experience level
        if scores.experience >= 0.75 {
            reasons.append(MatchReason(icon: "star.fill", text: "Experience level matches your background", score: scores.experience))
        }

        // Verified employer
        if job.employerVerified {
            reasons.append(MatchReason(icon: "checkmark.shield.fill", text: "Verified \(job.employerName)", score: 0.9))
        }

        // Generate short explanation text
        let topReason = reasons.sorted { $0.score > $1.score }.first?.text
        let explanation = topReason ?? "Matches your profile and preferences"

        return (explanation, Array(reasons.prefix(4)))
    }

    private static func buildCandidateExplanation(
        skillScore: Double,
        expScore: Double,
        seeker: JobSeekerProfile,
        job: JobListing
    ) -> String {
        var parts: [String] = []

        if skillScore >= 0.60 {
            let matched = seeker.skills.filter { s in
                job.skills.contains(where: { $0.lowercased() == s.lowercased() })
            }.prefix(2).joined(separator: ", ")
            if !matched.isEmpty { parts.append("Skills: \(matched)") }
        }

        if expScore >= 0.75 {
            parts.append("\(seeker.experienceLevel.label) experience")
        }

        if seeker.openToRelocate && job.workArrangement == .onSite {
            parts.append("Open to relocate")
        }

        return parts.isEmpty ? "Matches your requirements" : parts.joined(separator: " · ")
    }
}

// MARK: - Job Search Ranking

/// Ranks a list of job listings by relevance to a query string.
/// Used for text search results when a seeker profile is not available.
struct JobSearchRanker {

    static func rank(
        jobs: [JobListing],
        query: String,
        filters: JobSearchFilters,
        sort: JobSortOption = .relevance
    ) -> [JobListing] {
        let queryLower = query.lowercased()

        var scored: [(job: JobListing, score: Double)] = jobs.compactMap { job in
            guard job.isActive, !job.isExpired, job.moderationState == .active else { return nil }

            // Apply filters
            if !filters.jobTypes.isEmpty && !filters.jobTypes.contains(job.jobType) { return nil }
            if !filters.classifications.isEmpty && !filters.classifications.contains(job.classification) { return nil }
            if !filters.arrangements.isEmpty && !filters.arrangements.contains(job.workArrangement) { return nil }
            if !filters.categories.isEmpty && !filters.categories.contains(job.category) { return nil }
            if !filters.experienceLevels.isEmpty && !filters.experienceLevels.contains(job.experienceLevel) { return nil }
            if let cutoff = filters.postedWithin?.cutoffDate, job.createdAt < cutoff { return nil }
            if let minComp = filters.compensationMin, let salMax = job.salaryMax, salMax < minComp { return nil }
            if let maxComp = filters.compensationMax, let salMin = job.salaryMin, salMin > maxComp { return nil }

            var score = 0.0
            if queryLower.isEmpty {
                // No query: rank by featured + recency + safety
                if job.isFeatured { score += 0.30 }
                if job.isPromoted { score += 0.15 }
                score += job.safetyScore * 0.30
                // Recency bonus (decays over 30 days)
                let daysSincePost = Date().timeIntervalSince(job.createdAt) / 86400
                score += max(0, (30 - daysSincePost) / 30) * 0.25
            } else {
                // With query: relevance scoring
                let titleMatch    = job.title.lowercased().contains(queryLower) ? 0.40 : 0.0
                let categoryMatch = job.category.label.lowercased().contains(queryLower) ? 0.15 : 0.0
                let skillMatch    = job.skills.contains(where: { $0.lowercased().contains(queryLower) }) ? 0.20 : 0.0
                let descMatch     = job.description.lowercased().contains(queryLower) ? 0.10 : 0.0
                let employerMatch = job.employerName.lowercased().contains(queryLower) ? 0.15 : 0.0
                score = titleMatch + categoryMatch + skillMatch + descMatch + employerMatch
                // Quality signals
                if job.isFeatured { score += 0.10 }
                score += job.safetyScore * 0.10
            }

            return (job: job, score: score)
        }

        // Apply sort override
        switch sort {
        case .relevance:
            scored.sort { $0.score > $1.score }
        case .newest:
            scored.sort { $0.job.createdAt > $1.job.createdAt }
        case .salaryHighToLow:
            scored.sort { ($0.job.salaryMax ?? 0) > ($1.job.salaryMax ?? 0) }
        case .salaryLowToHigh:
            scored.sort { ($0.job.salaryMin ?? 0) < ($1.job.salaryMin ?? 0) }
        }

        return scored.map { $0.job }
    }
}
