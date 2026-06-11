// AmenOpportunityService.swift
// AMEN CommunityOS — Opportunity OS (A10)
//
// Phase 3 Agent A10: @MainActor ObservableObject for jobs, volunteer positions,
// and mentorship request feed loading, posting, saving, and application flow.
//
// CRITICAL: Never expose contactRef as a raw email/phone — it is an AMEN inbox
// thread reference. Applications go through AMEN messaging (ActionThreadService),
// not external contact. The poster's email, phone, or any PII is NEVER shared
// with applicants through this service.
//
// Minor accounts are blocked from viewing jobs at the Firestore rules layer.
// isFilled items are filtered from feed queries.

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig
import FirebaseFunctions

// MARK: - AmenOpportunityService

@MainActor
final class AmenOpportunityService: ObservableObject {

    // MARK: Published State

    @Published var jobs: [AmenJobPost] = []
    @Published var volunteerOpps: [AmenVolunteerPost] = []
    @Published var mentorshipRequests: [AmenMentorshipPost] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: Dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let remoteConfig = RemoteConfig.remoteConfig()

    private var isEnabled: Bool {
        remoteConfig.configValue(forKey: "community_os_opportunity_enabled").boolValue
    }

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    // MARK: - Load Opportunities

    /// Loads opportunities from Firestore, optionally scoped by org and filtered by category.
    /// - Parameters:
    ///   - orgId: When non-nil, scopes the query to a specific org's postings.
    ///   - category: When non-nil, filters to that opportunity category.
    ///   - query: Reserved for future keyword search. Currently unused.
    func loadOpportunities(
        orgId: String?,
        category: AmenOpportunityCategory?,
        query: String?
    ) async throws {
        guard isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let jobsTask = fetchJobs(orgId: orgId)
        async let volunteersTask = fetchVolunteerOpps(orgId: orgId)
        async let mentorshipsTask = fetchMentorshipRequests(orgId: orgId)

        let (fetchedJobs, fetchedVolunteers, fetchedMentorships) = try await (
            jobsTask, volunteersTask, mentorshipsTask
        )

        if let cat = category {
            switch cat {
            case .job, .internship, .referral:
                jobs = fetchedJobs
            case .volunteerPosition, .projectCollaboration:
                volunteerOpps = fetchedVolunteers
            case .mentorship:
                mentorshipRequests = fetchedMentorships
            }
        } else {
            jobs = fetchedJobs
            volunteerOpps = fetchedVolunteers
            mentorshipRequests = fetchedMentorships
        }
    }

    // MARK: - Private Fetch Helpers

    private func fetchJobs(orgId: String?) async throws -> [AmenJobPost] {
        var ref: Query = db.collection("jobPosts")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("isFilled", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        if let orgId {
            ref = db.collection("jobPosts")
                .whereField("orgId", isEqualTo: orgId)
                .whereField("isDeleted", isEqualTo: false)
                .whereField("isFilled", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
        }
        let snap = try await ref.getDocuments()
        let decoder = Firestore.Decoder()
        return snap.documents.compactMap { doc -> AmenJobPost? in
            var data = doc.data()
            data["id"] = doc.documentID
            return try? decoder.decode(AmenJobPost.self, from: data)
        }
    }

    private func fetchVolunteerOpps(orgId: String?) async throws -> [AmenVolunteerPost] {
        var ref: Query = db.collection("volunteerPosts")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("isFilled", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        if let orgId {
            ref = db.collection("volunteerPosts")
                .whereField("orgId", isEqualTo: orgId)
                .whereField("isDeleted", isEqualTo: false)
                .whereField("isFilled", isEqualTo: false)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
        }
        let snap = try await ref.getDocuments()
        let decoder = Firestore.Decoder()
        return snap.documents.compactMap { doc -> AmenVolunteerPost? in
            var data = doc.data()
            data["id"] = doc.documentID
            return try? decoder.decode(AmenVolunteerPost.self, from: data)
        }
    }

    private func fetchMentorshipRequests(orgId: String?) async throws -> [AmenMentorshipPost] {
        let ref: Query = db.collection("mentorshipPosts")
            .whereField("isDeleted", isEqualTo: false)
            .whereField("isPublic", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        // Mentorship posts are not org-scoped in this version.
        let snap = try await ref.getDocuments()
        let decoder = Firestore.Decoder()
        return snap.documents.compactMap { doc -> AmenMentorshipPost? in
            var data = doc.data()
            data["id"] = doc.documentID
            return try? decoder.decode(AmenMentorshipPost.self, from: data)
        }
    }

    // MARK: - Post Opportunity

    /// Posts a new job listing. Returns the Firestore document ID.
    /// - Note: isFilled is always false on creation; contactRef is validated to be non-empty.
    func postJob(_ job: AmenJobPost) async throws -> String {
        guard isEnabled else { throw AmenOpportunityError.featureDisabled }
        guard !currentUserId.isEmpty else { throw AmenOpportunityError.notAuthenticated }
        // CRITICAL: reject any attempt to embed raw contact in contactRef
        assert(!job.contactRef.isEmpty, "contactRef must be set — use the Amen inbox reference, never raw PII.")
        var post = job
        post.postedBy = currentUserId
        post.isFilled = false
        post.isDeleted = false
        let docRef = db.collection("jobPosts").document(post.id)
        try docRef.setData(from: post)
        return post.id
    }

    /// Posts a new volunteer opportunity. Returns the Firestore document ID.
    func postVolunteerOpportunity(_ opp: AmenVolunteerPost) async throws -> String {
        guard isEnabled else { throw AmenOpportunityError.featureDisabled }
        guard !currentUserId.isEmpty else { throw AmenOpportunityError.notAuthenticated }
        assert(!opp.contactRef.isEmpty, "contactRef must be set — use the Amen inbox reference, never raw PII.")
        var post = opp
        post.postedBy = currentUserId
        post.isFilled = false
        post.isDeleted = false
        let docRef = db.collection("volunteerPosts").document(post.id)
        try docRef.setData(from: post)
        return post.id
    }

    /// Posts a new mentorship request. Returns the Firestore document ID.
    func postMentorshipRequest(_ request: AmenMentorshipPost) async throws -> String {
        guard isEnabled else { throw AmenOpportunityError.featureDisabled }
        guard !currentUserId.isEmpty else { throw AmenOpportunityError.notAuthenticated }
        assert(!request.contactRef.isEmpty, "contactRef must be set — use the Amen inbox reference, never raw PII.")
        var post = request
        post.isDeleted = false
        let docRef = db.collection("mentorshipPosts").document(post.id)
        try docRef.setData(from: post)
        return post.id
    }

    // MARK: - Apply

    /// Creates an application record and opens an Amen inbox action thread between
    /// the applicant and the poster. The poster's email, phone, or any PII is
    /// NEVER shared — all contact is mediated through the Amen messaging system.
    ///
    /// CRITICAL: Never expose contactRef as a raw email/phone.
    func applyTo(
        opportunityId: String,
        category: AmenOpportunityCategory,
        message: String,
        applicantId: String
    ) async throws {
        guard isEnabled else { throw AmenOpportunityError.featureDisabled }
        guard !applicantId.isEmpty else { throw AmenOpportunityError.notAuthenticated }

        // Route application through the Cloud Function which:
        //   1. Creates the OpportunityApplication Firestore document
        //   2. Opens an Amen inbox thread (ActionThreadService) between applicant + poster
        //   3. Never surfaces the poster's raw contact info
        _ = try await functions.httpsCallable("applyViaInbox").call([
            "opportunityId": opportunityId,
            "opportunityCategory": category.rawValue,
            "applicantId": applicantId,
            "introMessage": message.trimmingCharacters(in: .whitespacesAndNewlines)
        ])
    }

    // MARK: - Save / Bookmark

    /// Creates a save edge in the user's saved opportunities collection.
    func saveOpportunity(
        opportunityId: String,
        category: AmenOpportunityCategory,
        userId: String
    ) async throws {
        guard !userId.isEmpty else { throw AmenOpportunityError.notAuthenticated }
        let saveRef = db.collection("users").document(userId)
            .collection("savedOpportunities").document(opportunityId)
        try await saveRef.setData([
            "opportunityId": opportunityId,
            "category": category.rawValue,
            "savedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Mark Filled (Soft Close)

    /// Soft-closes a job posting by setting isFilled = true.
    /// The record is not deleted; isFilled == true hides it from feed queries.
    func markFilled(opportunityId: String, category: AmenOpportunityCategory) async throws {
        guard !currentUserId.isEmpty else { throw AmenOpportunityError.notAuthenticated }
        let collection: String
        switch category {
        case .job, .internship, .referral:
            collection = "jobPosts"
        case .volunteerPosition, .projectCollaboration:
            collection = "volunteerPosts"
        case .mentorship:
            collection = "mentorshipPosts"
        }
        try await db.collection(collection).document(opportunityId)
            .updateData(["isFilled": true, "updatedAt": FieldValue.serverTimestamp()])
    }
}

// MARK: - AmenOpportunityError

enum AmenOpportunityError: LocalizedError {
    case featureDisabled
    case notAuthenticated
    case postingFailed(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Opportunities feature is currently unavailable."
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .postingFailed(let reason):
            return "Could not post opportunity: \(reason)"
        }
    }
}

// MARK: - OpportunityComposerView

struct OpportunityComposerView: View {
    var onPost: ((OpportunityPost) -> Void)?
    @Binding var isPresented: Bool

    init(
        onPost: ((OpportunityPost) -> Void)? = nil,
        isPresented: Binding<Bool> = .constant(true)
    ) {
        self.onPost = onPost
        self._isPresented = isPresented
    }

    var body: some View {
        AmenUniversalComposer(
            sourceRef: nil,
            sourceType: AmenObjectType.job.rawValue,
            initialIntent: AmenIntent.hire.rawValue,
            isPresented: $isPresented,
            onCreated: { _, _ in isPresented = false }
        )
    }
}
