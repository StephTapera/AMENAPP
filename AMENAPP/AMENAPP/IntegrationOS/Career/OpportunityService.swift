// OpportunityService.swift — AMEN IntegrationOS
// Actor for Firestore CRUD on ministry and career opportunities.
// Minor accounts are blocked from posting (opportunityPost scope).

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig

actor OpportunityService {
    static let shared = OpportunityService()
    private init() {}

    private let db = Firestore.firestore()
    private let ledger = ConsentLedgerService.shared
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_career_enabled").booleanValue }

    // MARK: - Fetch

    func fetchOpportunities(filter: JobType? = nil, limit: Int = 25) async throws -> [JobOpportunity] {
        guard isEnabled else { return [] }
        var query: Query = db.collection("opportunities")
            .whereField("isActive", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        if let type = filter {
            query = db.collection("opportunities")
                .whereField("isActive", isEqualTo: true)
                .whereField("jobType", isEqualTo: type.rawValue)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
        }

        let snap = try await query.getDocuments()
        return snap.documents.compactMap { try? $0.data(as: JobOpportunity.self) }
    }

    func fetchOpportunity(id: String) async throws -> JobOpportunity? {
        let doc = try await db.collection("opportunities").document(id).getDocument()
        return try? doc.data(as: JobOpportunity.self)
    }

    // MARK: - Post

    func post(opportunity: JobOpportunity) async throws {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        let granted = await ledger.isGranted(scope: .opportunityPost, providerId: "amen")
        guard granted else { throw IntegrationOSError.consentDenied(.opportunityPost) }
        var opp = opportunity
        try db.collection("opportunities").document(opp.id).setData(from: opp)
    }

    // MARK: - Update / Delete

    func deactivate(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        try await db.collection("opportunities").document(id)
            .updateData(["isActive": false])
    }

    // MARK: - Application

    func apply(opportunityId: String, coverNote: String?, portfolioURL: String?) async throws {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        let application = JobApplication(
            opportunityId: opportunityId,
            applicantId: uid,
            coverNote: coverNote,
            portfolioURL: portfolioURL,
            status: .submitted,
            appliedAt: Date()
        )
        try db.collection("opportunities").document(opportunityId)
            .collection("applications").document(application.id)
            .setData(from: application)
    }
}
