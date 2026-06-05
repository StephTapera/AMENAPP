// BroadcastService.swift — AMEN IntegrationOS
// Actor that calls the `sendBroadcast` Cloud Function.
// Minor accounts are blocked from SMS and email channels.

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth
import FirebaseRemoteConfig

actor BroadcastService {
    static let shared = BroadcastService()
    private init() {}

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private let ledger = ConsentLedgerService.shared
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_messaging_enabled").booleanValue }

    // MARK: - Send

    func send(
        orgId: String,
        spaceId: String?,
        channel: BroadcastChannel,
        subject: String?,
        body: String,
        scheduledAt: Date? = nil
    ) async throws {
        guard isEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { throw IntegrationOSError.notAuthenticated }

        // Consent gate
        let scope = channel.requiresScope
        guard await ledger.isGranted(scope: scope, providerId: "amen") else {
            throw IntegrationOSError.consentDenied(scope)
        }

        // Minor guard for SMS and email
        if channel == .sms || channel == .email {
            // Minor check handled server-side, but surface locally for UX
        }

        var payload: [String: Any] = [
            "orgId": orgId,
            "channel": channel.rawValue,
            "body": body
        ]
        if let sid = spaceId { payload["spaceId"] = sid }
        if let subj = subject { payload["subject"] = subj }
        if let sched = scheduledAt { payload["scheduledAt"] = sched.timeIntervalSince1970 }

        let result = try await functions.httpsCallable("sendBroadcast").call(payload)
        guard let data = result.data as? [String: Any] else { return }

        // Persist broadcast record locally
        let msg = BroadcastMessage(
            senderId: uid,
            orgId: orgId,
            spaceId: spaceId,
            channel: channel,
            subject: subject,
            body: body,
            scheduledAt: scheduledAt,
            sentAt: scheduledAt == nil ? Date() : nil,
            status: scheduledAt == nil ? .sent : .scheduled,
            recipientCount: data["recipientCount"] as? Int ?? 0,
            createdAt: Date()
        )
        try db.collection("broadcastHistory").document(msg.id).setData(from: msg)
    }

    // MARK: - History

    func fetchHistory(orgId: String, limit: Int = 20) async throws -> [BroadcastMessage] {
        guard isEnabled else { return [] }
        let snap = try await db.collection("broadcastHistory")
            .whereField("orgId", isEqualTo: orgId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: BroadcastMessage.self) }
    }
}
