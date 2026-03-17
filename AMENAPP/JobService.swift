// JobService.swift
// AMENAPP
//
// @MainActor singleton service for all Jobs & Opportunities platform operations.
// Follows StudioDataService.swift conventions: listener arrays, idempotency guards,
// Firestore.Encoder/Decoder, private notification helpers.

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class JobService: ObservableObject {

    static let shared = JobService()

    // MARK: - Published State

    @Published var featuredJobs: [JobListing] = []
    @Published var recentJobs: [JobListing] = []
    @Published var searchResults: [JobListing] = []
    @Published var matchRecommendations: [JobMatchResult] = []

    @Published var myApplications: [JobApplication] = []
    @Published var mySavedJobs: [SavedJob] = []
    @Published var myPostedJobs: [JobListing] = []
    @Published var myJobAlerts: [JobAlert] = []
    @Published var candidateInbox: [JobApplication] = []

    @Published var mySeekerProfile: JobSeekerProfile?
    @Published var myEmployerProfile: EmployerProfile?

    @Published var unreadApplicationCount: Int = 0

    @Published var isLoadingJobs: Bool = false
    @Published var isLoadingApplications: Bool = false
    @Published var isSearching: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private State

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var isListening = false

    private var currentUserId: String? { Auth.auth().currentUser?.uid }

    private init() {}

    // MARK: - Listener Setup

    // PERF: Call setupListeners() lazily — only when the user navigates to the Jobs
    // tab for the first time. Do NOT call from AppLifecycleManager or ContentView.onAppear.
    // This prevents 6 unnecessary Firestore listeners from running for users who never
    // open the Jobs section (the majority of sessions initially).
    //
    // Callers: AMENConnectView (when selectedTab == .jobs) or JobSearchView.onAppear.

    func setupListeners() {
        guard !isListening, let userId = currentUserId else { return }
        isListening = true

        // Seeker profile listener
        let seekerListener = db.collection(JobCollections.jobSeekerProfiles)
            .document(userId)
            .addSnapshotListener { [weak self] snap, _ in
                self?.mySeekerProfile = try? snap?.data(as: JobSeekerProfile.self)
            }
        listeners.append(seekerListener)

        // Employer profile listener
        let employerListener = db.collection(JobCollections.employerProfiles)
            .document(userId)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myEmployerProfile = try? snap?.data(as: EmployerProfile.self)
            }
        listeners.append(employerListener)

        // My applications listener (seeker side)
        let appListener = db.collection(JobCollections.jobApplications)
            .whereField("applicantId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myApplications = snap?.documents.compactMap {
                    try? $0.data(as: JobApplication.self)
                } ?? []
            }
        listeners.append(appListener)

        // Saved jobs listener
        let savedListener = db.collection(JobCollections.savedJobs)
            .whereField("userId", isEqualTo: userId)
            .order(by: "savedAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snap, _ in
                self?.mySavedJobs = snap?.documents.compactMap {
                    try? $0.data(as: SavedJob.self)
                } ?? []
            }
        listeners.append(savedListener)

        // My posted jobs listener (employer side)
        let postedListener = db.collection(JobCollections.jobListings)
            .whereField("employerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myPostedJobs = snap?.documents.compactMap {
                    try? $0.data(as: JobListing.self)
                } ?? []
            }
        listeners.append(postedListener)

        // Recruiter inbox listener (applications to my jobs)
        let inboxListener = db.collection(JobCollections.jobApplications)
            .whereField("employerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                let apps = snap?.documents.compactMap {
                    try? $0.data(as: JobApplication.self)
                } ?? []
                self.candidateInbox = apps
                self.unreadApplicationCount = apps.filter { !$0.isRead }.count
            }
        listeners.append(inboxListener)

        // Job alerts listener
        let alertsListener = db.collection(JobCollections.jobAlerts)
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snap, _ in
                self?.myJobAlerts = snap?.documents.compactMap {
                    try? $0.data(as: JobAlert.self)
                } ?? []
            }
        listeners.append(alertsListener)
    }

    func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
        isListening = false
    }

    // MARK: - Featured Jobs

    func fetchFeaturedJobs(limit: Int = 20) async -> [JobListing] {
        isLoadingJobs = true
        defer { isLoadingJobs = false }

        do {
            let snap = try await db.collection(JobCollections.jobListings)
                .whereField("isActive", isEqualTo: true)
                .whereField("isFeatured", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            let jobs = snap.documents.compactMap { try? $0.data(as: JobListing.self) }
            featuredJobs = jobs
            return jobs
        } catch {
            // Fallback: load recent jobs
            return await fetchRecentJobs(limit: limit)
        }
    }

    func fetchRecentJobs(limit: Int = 30) async -> [JobListing] {
        do {
            let snap = try await db.collection(JobCollections.jobListings)
                .whereField("isActive", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            let jobs = snap.documents.compactMap { try? $0.data(as: JobListing.self) }
            recentJobs = jobs
            return jobs
        } catch {
            errorMessage = "Could not load jobs."
            return []
        }
    }

    // MARK: - Single Job Fetch

    func fetchJob(id: String) async -> JobListing? {
        do {
            let doc = try await db.collection(JobCollections.jobListings).document(id).getDocument()
            return try doc.data(as: JobListing.self)
        } catch {
            return nil
        }
    }

    // MARK: - Search Jobs

    func searchJobs(query: String, filters: JobSearchFilters, page: Int = 0, pageSize: Int = 25) async -> [JobListing] {
        isSearching = true
        defer { isSearching = false }

        do {
            // Fetch a broader pool from Firestore, then rank client-side
            var firestoreQuery = db.collection(JobCollections.jobListings)
                .whereField("isActive", isEqualTo: true)

            // Apply simple filter if single type/arrangement selected (Firestore limitation: only one inequality per query)
            if filters.arrangements.count == 1, let arrangement = filters.arrangements.first {
                firestoreQuery = firestoreQuery.whereField("workArrangement", isEqualTo: arrangement.rawValue)
            }
            if filters.jobTypes.count == 1, let jobType = filters.jobTypes.first {
                firestoreQuery = firestoreQuery.whereField("jobType", isEqualTo: jobType.rawValue)
            }

            let snap = try await firestoreQuery
                .order(by: "createdAt", descending: true)
                .limit(to: 200)  // fetch more for client-side ranking
                .getDocuments()

            let allJobs = snap.documents.compactMap { try? $0.data(as: JobListing.self) }
            let ranked = JobSearchRanker.rank(jobs: allJobs, query: query, filters: filters, sort: filters.sortBy)
            let paginated = Array(ranked.dropFirst(page * pageSize).prefix(pageSize))

            if page == 0 { searchResults = paginated }
            else { searchResults.append(contentsOf: paginated) }

            return paginated
        } catch {
            errorMessage = "Search failed. Please try again."
            return []
        }
    }

    // MARK: - Post Job

    func postJob(_ listing: JobListing) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }
        isSaving = true
        defer { isSaving = false }

        // Safety check
        let safetyDecision = await JobSafetyEngine.shared.evaluateJobPosting(listing)
        guard safetyDecision.isAllowed || safetyDecision == .allow else {
            let msg = safetyDecision.displayMessage ?? "This listing cannot be published."
            throw JobServiceError.safetyViolation(msg)
        }

        var newListing = listing
        newListing.employerId = userId
        newListing.createdAt = Date()
        newListing.updatedAt = Date()
        newListing.safetyScore = await JobSafetyEngine.shared.computeJobSafetyScore(listing)

        // Build search keywords
        newListing.searchKeywords = buildJobKeywords(listing)

        // P1 #7: Compute and store geohash if coordinates are provided so proximity
        // queries can use a Firestore range index instead of fetching the full collection.
        if let lat = newListing.latitude, let lon = newListing.longitude {
            newListing.geohash = JobService.geohash(lat: lat, lon: lon)
        }

        let encoded = try Firestore.Encoder().encode(newListing)
        try await db.collection(JobCollections.jobListings).addDocument(data: encoded)
    }

    func updateJob(_ listing: JobListing) async throws {
        guard let jobId = listing.id else { throw JobServiceError.missingId }
        isSaving = true
        defer { isSaving = false }

        var updated = listing
        updated.updatedAt = Date()
        updated.safetyScore = await JobSafetyEngine.shared.computeJobSafetyScore(listing)
        updated.searchKeywords = buildJobKeywords(listing)

        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection(JobCollections.jobListings).document(jobId).setData(encoded, merge: true)
    }

    func deactivateJob(_ jobId: String) async throws {
        try await db.collection(JobCollections.jobListings).document(jobId).updateData([
            "isActive": false,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Applications

    func submitApplication(_ application: JobApplication) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }

        // Safety check on cover note
        if let coverNote = application.coverNote, !coverNote.isEmpty {
            let decision = await JobSafetyEngine.shared.evaluateApplication(text: coverNote, applicantId: userId)
            if !decision.isAllowed {
                throw JobServiceError.safetyViolation(decision.displayMessage ?? "Application content violates policies.")
            }
        }

        // Ensure consent was given
        guard application.consentToShareProfile else {
            throw JobServiceError.consentRequired
        }

        var app = application
        app.applicantId = userId
        app.createdAt = Date()
        app.updatedAt = Date()
        app.status = .submitted
        app.isRead = false

        let encoded = try Firestore.Encoder().encode(app)
        let docRef = try await db.collection(JobCollections.jobApplications).addDocument(data: encoded)

        // Increment application count on job
        try await db.collection(JobCollections.jobListings).document(app.jobId).updateData([
            "applicationCount": FieldValue.increment(Int64(1))
        ])

        // Notify recruiter
        await sendJobNotification(
            toUserId: app.employerId,
            type: .newApplication,
            title: "New Application",
            body: "\(app.applicantName) applied for \(app.jobTitle)",
            relatedId: docRef.documentID
        )

        // Log analytics
        logJobApply(jobId: app.jobId)
    }

    func withdrawApplication(_ applicationId: String) async throws {
        try await db.collection(JobCollections.jobApplications).document(applicationId).updateData([
            "status": ApplicationStatus.withdrawn.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func updateApplicationStatus(_ applicationId: String, status: ApplicationStatus, notes: String? = nil) async throws {
        var data: [String: Any] = [
            "status": status.rawValue,
            "isRead": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let notes = notes { data["employerNotes"] = notes }
        try await db.collection(JobCollections.jobApplications).document(applicationId).updateData(data)
    }

    func markApplicationRead(_ applicationId: String) async {
        try? await db.collection(JobCollections.jobApplications).document(applicationId).updateData([
            "isRead": true
        ])
    }

    func fetchApplicationsForJob(_ jobId: String) async -> [JobApplication] {
        do {
            let snap = try await db.collection(JobCollections.jobApplications)
                .whereField("jobId", isEqualTo: jobId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            return snap.documents.compactMap { try? $0.data(as: JobApplication.self) }
        } catch {
            return []
        }
    }

    // MARK: - Saved Jobs

    func isJobSaved(_ jobId: String) -> Bool {
        mySavedJobs.contains { $0.jobId == jobId }
    }

    func saveJob(_ jobId: String, title: String, employer: String) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }
        guard !isJobSaved(jobId) else { return }  // idempotency

        let saved = SavedJob(
            userId: userId,
            jobId: jobId,
            jobTitle: title,
            employerName: employer,
            savedAt: Date()
        )
        let encoded = try Firestore.Encoder().encode(saved)
        try await db.collection(JobCollections.savedJobs).addDocument(data: encoded)

        // Increment save count on job
        try? await db.collection(JobCollections.jobListings).document(jobId).updateData([
            "saveCount": FieldValue.increment(Int64(1))
        ])
    }

    func unsaveJob(_ savedJobId: String) async throws {
        try await db.collection(JobCollections.savedJobs).document(savedJobId).delete()
    }

    // MARK: - Seeker Profile

    func saveSeekerProfile(_ profile: JobSeekerProfile) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }
        isSaving = true
        defer { isSaving = false }

        var updated = profile
        updated.userId = userId
        updated.updatedAt = Date()
        if updated.createdAt == Date(timeIntervalSince1970: 0) || profile.id == nil {
            updated.createdAt = Date()
        }
        updated.searchKeywords = buildSeekerKeywords(profile)

        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection(JobCollections.jobSeekerProfiles).document(userId).setData(encoded, merge: true)
    }

    func fetchSeekerProfile(for userId: String) async -> JobSeekerProfile? {
        do {
            let doc = try await db.collection(JobCollections.jobSeekerProfiles).document(userId).getDocument()
            return try doc.data(as: JobSeekerProfile.self)
        } catch {
            return nil
        }
    }

    func deleteSeekerProfile() async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }
        try await db.collection(JobCollections.jobSeekerProfiles).document(userId).delete()
        mySeekerProfile = nil
    }

    // MARK: - Employer Profile

    func saveEmployerProfile(_ profile: EmployerProfile) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }
        isSaving = true
        defer { isSaving = false }

        var updated = profile
        updated.userId = userId
        updated.updatedAt = Date()
        if profile.id == nil { updated.createdAt = Date() }
        updated.searchKeywords = [profile.organizationName.lowercased(), profile.organizationType.label.lowercased()]

        let encoded = try Firestore.Encoder().encode(updated)
        try await db.collection(JobCollections.employerProfiles).document(userId).setData(encoded, merge: true)
    }

    func fetchEmployerProfile(for userId: String) async -> EmployerProfile? {
        do {
            let doc = try await db.collection(JobCollections.employerProfiles).document(userId).getDocument()
            return try doc.data(as: EmployerProfile.self)
        } catch {
            return nil
        }
    }

    // MARK: - Match Recommendations

    func fetchMatchRecommendations() async -> [JobMatchResult] {
        guard let seeker = mySeekerProfile else { return [] }

        let jobs = await fetchRecentJobs(limit: 100)
        if jobs.isEmpty { return [] }

        // Fetch employer profiles for quality scoring
        let employerIds = Set(jobs.map { $0.employerId })
        var employers: [String: EmployerProfile] = [:]
        for empId in employerIds.prefix(20) {
            if let emp = await fetchEmployerProfile(for: empId) {
                employers[empId] = emp
            }
        }

        let results = JobMatchingEngine.matchJobsForSeeker(seeker: seeker, jobs: jobs, employers: employers)
        matchRecommendations = Array(results.prefix(20))
        return matchRecommendations
    }

    // MARK: - Job Alerts

    func createJobAlert(_ alert: JobAlert) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }

        var newAlert = alert
        newAlert.userId = userId
        newAlert.createdAt = Date()
        newAlert.isActive = true

        let encoded = try Firestore.Encoder().encode(newAlert)
        try await db.collection(JobCollections.jobAlerts).addDocument(data: encoded)
    }

    func updateJobAlert(_ alertId: String, isActive: Bool) async throws {
        try await db.collection(JobCollections.jobAlerts).document(alertId).updateData([
            "isActive": isActive
        ])
    }

    func deleteJobAlert(_ alertId: String) async throws {
        try await db.collection(JobCollections.jobAlerts).document(alertId).delete()
    }

    // MARK: - Analytics

    func logJobView(jobId: String, surface: String = "search") {
        guard let userId = currentUserId else { return }
        let event: [String: Any] = [
            "jobId": jobId,
            "userId": userId,
            "eventType": "view",
            "surface": surface,
            "timestamp": FieldValue.serverTimestamp()
        ]
        db.collection(JobCollections.analytics).addDocument(data: event)

        // Increment view count
        db.collection(JobCollections.jobListings).document(jobId).updateData([
            "viewCount": FieldValue.increment(Int64(1))
        ])
    }

    func logJobApply(jobId: String) {
        guard let userId = currentUserId else { return }
        let event: [String: Any] = [
            "jobId": jobId,
            "userId": userId,
            "eventType": "apply",
            "timestamp": FieldValue.serverTimestamp()
        ]
        db.collection(JobCollections.analytics).addDocument(data: event)
    }

    // MARK: - Reports / Moderation

    func reportJob(jobId: String, reason: JobModerationReason, description: String? = nil) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }

        let flag = JobModerationFlag(
            targetId: jobId,
            targetType: "job",
            reporterId: userId,
            reason: reason,
            flagDescription: description,
            status: .pending,
            actionTaken: nil,
            createdAt: Date()
        )
        let encoded = try Firestore.Encoder().encode(flag)
        try await db.collection(JobCollections.moderationFlags).addDocument(data: encoded)
    }

    func reportEmployer(employerId: String, reason: JobModerationReason, description: String? = nil) async throws {
        guard let userId = currentUserId else { throw JobServiceError.notAuthenticated }

        let flag = JobModerationFlag(
            targetId: employerId,
            targetType: "employer",
            reporterId: userId,
            reason: reason,
            flagDescription: description,
            status: .pending,
            actionTaken: nil,
            createdAt: Date()
        )
        let encoded = try Firestore.Encoder().encode(flag)
        try await db.collection(JobCollections.moderationFlags).addDocument(data: encoded)
    }

    // MARK: - Church / Ministry Opportunities

    func fetchChurchOpportunities(limit: Int = 20) async -> [JobListing] {
        do {
            let snap = try await db.collection(JobCollections.jobListings)
                .whereField("isActive", isEqualTo: true)
                .whereField("classification", isEqualTo: JobClassification.churchMinistry.rawValue)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snap.documents.compactMap { try? $0.data(as: JobListing.self) }
        } catch {
            return []
        }
    }

    func fetchVolunteerOpportunities(limit: Int = 20) async -> [JobListing] {
        do {
            let snap = try await db.collection(JobCollections.jobListings)
                .whereField("isActive", isEqualTo: true)
                .whereField("jobType", isEqualTo: JobType.volunteer.rawValue)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            return snap.documents.compactMap { try? $0.data(as: JobListing.self) }
        } catch {
            return []
        }
    }

    // MARK: - Private Helpers

    private func buildJobKeywords(_ listing: JobListing) -> [String] {
        var keywords: [String] = []
        keywords.append(contentsOf: listing.title.lowercased().split(separator: " ").map(String.init))
        keywords.append(listing.category.label.lowercased())
        keywords.append(listing.jobType.label.lowercased())
        keywords.append(listing.workArrangement.label.lowercased())
        keywords.append(listing.classification.label.lowercased())
        keywords.append(contentsOf: listing.skills.map { $0.lowercased() })
        if let city = listing.city { keywords.append(city.lowercased()) }
        if let state = listing.state { keywords.append(state.lowercased()) }
        return Array(Set(keywords))  // deduplicate
    }

    private func buildSeekerKeywords(_ profile: JobSeekerProfile) -> [String] {
        var keywords: [String] = []
        keywords.append(contentsOf: profile.headline.lowercased().split(separator: " ").map(String.init))
        keywords.append(contentsOf: profile.skills.map { $0.lowercased() })
        keywords.append(profile.experienceLevel.label.lowercased())
        keywords.append(contentsOf: profile.desiredCategories.map { $0.label.lowercased() })
        if let loc = profile.desiredLocation { keywords.append(loc.lowercased()) }
        return Array(Set(keywords))
    }

    private func sendJobNotification(
        toUserId: String,
        type: JobNotificationType,
        title: String,
        body: String,
        relatedId: String?
    ) async {
        var data: [String: Any] = [
            "toUserId": toUserId,
            "type": type.rawValue,
            "title": title,
            "body": body,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let relatedId = relatedId { data["relatedId"] = relatedId }
        try? await db.collection(JobCollections.notifications).addDocument(data: data)
    }

    // MARK: - Proximity Search (Geohash)

    /// P1 #7: Fetch jobs near a coordinate using a Firestore geohash range query.
    /// Instead of loading the full collection client-side (O(n)), we query only documents
    /// whose geohash prefix matches the caller's 4-char prefix (~40 km bounding box),
    /// then filter the smaller result set for exact radius.
    ///
    /// TODO: Deploy Firestore composite index: jobs(geohash ASC, isActive ASC)
    func fetchJobsNear(lat: Double, lon: Double, radiusKm: Double = 50) async throws -> [JobListing] {
        let prefix = String(JobService.geohash(lat: lat, lon: lon, precision: 4).prefix(4))
        let snapshot = try await db.collection(JobCollections.jobListings)
            .whereField("geohash", isGreaterThanOrEqualTo: prefix)
            .whereField("geohash", isLessThan: prefix + "~")
            .whereField("isActive", isEqualTo: true)
            .limit(to: 50)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: JobListing.self) }
            .filter { job in
                guard let jobLat = job.latitude, let jobLon = job.longitude else { return true }
                return Self.haversineDistanceKm(lat1: lat, lon1: lon, lat2: jobLat, lon2: jobLon) <= radiusKm
            }
    }

    // MARK: - Geohash Helpers

    /// Encode a coordinate into a geohash string at the requested character precision.
    /// Precision 5 ≈ ±2.4 km; precision 4 ≈ ±20 km (suitable for bounding-box queries).
    static func geohash(lat: Double, lon: Double, precision: Int = 5) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var minLat = -90.0,  maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var hash = ""
        var isLon = true
        var bit = 0
        var charIndex = 0
        while hash.count < precision {
            if isLon {
                let mid = (minLon + maxLon) / 2
                if lon >= mid { charIndex = charIndex * 2 + 1; minLon = mid }
                else          { charIndex = charIndex * 2;     maxLon = mid }
            } else {
                let mid = (minLat + maxLat) / 2
                if lat >= mid { charIndex = charIndex * 2 + 1; minLat = mid }
                else          { charIndex = charIndex * 2;     maxLat = mid }
            }
            isLon.toggle()
            bit += 1
            if bit == 5 {
                hash.append(base32[charIndex])
                bit = 0; charIndex = 0
            }
        }
        return hash
    }

    /// Haversine great-circle distance between two coordinates, in kilometres.
    static func haversineDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

// MARK: - Errors

enum JobServiceError: LocalizedError {
    case notAuthenticated
    case missingId
    case consentRequired
    case safetyViolation(String)
    case firestoreError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:      return "You must be signed in to continue."
        case .missingId:             return "Missing document ID."
        case .consentRequired:       return "You must consent to share your profile before applying."
        case .safetyViolation(let msg): return msg
        case .firestoreError(let e): return e.localizedDescription
        }
    }
}
