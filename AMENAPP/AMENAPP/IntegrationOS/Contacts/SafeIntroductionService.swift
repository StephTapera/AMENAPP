// SafeIntroductionService.swift — AMEN IntegrationOS
// Actor for Firestore-based mutual introduction flow.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig

actor SafeIntroductionService {
    static let shared = SafeIntroductionService()
    private init() {}

    private let db = Firestore.firestore()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_contacts_enabled").boolValue }

    // MARK: - Request Introduction

    func requestIntroduction(to targetUID: String, introducerUID: String, message: String?) async throws {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        let request = IntroductionRequest(
            requesterId: uid,
            introducerUid: introducerUID,
            targetUid: targetUID,
            message: message,
            status: .pending,
            createdAt: Date(),
            resolvedAt: nil
        )
        try db.collection("introductionRequests").document(request.id).setData(from: request)
    }

    // MARK: - Respond to Introduction

    func respond(requestId: String, accept: Bool) async throws {
        guard isEnabled else { return }
        let status: IntroductionStatus = accept ? .accepted : .declined
        try await db.collection("introductionRequests").document(requestId).updateData([
            "status": status.rawValue,
            "resolvedAt": Timestamp(date: Date())
        ])
    }

    // MARK: - Fetch Pending

    func fetchPendingIntroductions() async throws -> [IntroductionRequest] {
        guard isEnabled else { return [] }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        let snap = try await db.collection("introductionRequests")
            .whereField("targetUid", isEqualTo: uid)
            .whereField("status", isEqualTo: IntroductionStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: IntroductionRequest.self) }
    }

    // MARK: - Fetch Sent

    func fetchSentIntroductions() async throws -> [IntroductionRequest] {
        guard isEnabled else { return [] }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }
        let snap = try await db.collection("introductionRequests")
            .whereField("requesterId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: IntroductionRequest.self) }
    }
}
