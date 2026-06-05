// OrgAssistantService.swift — AMEN IntegrationOS
// Actor that calls the `orgAssistant` Cloud Function.
// All outputs are marked approved: false per contract.

import Foundation
import FirebaseFunctions
import FirebaseRemoteConfig

actor OrgAssistantService {
    static let shared = OrgAssistantService()
    private init() {}

    private let functions = Functions.functions()
    private let ledger = ConsentLedgerService.shared
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_knowledge_enabled").booleanValue }

    // MARK: - Ask

    func ask(orgId: String, question: String, history: [OrgAssistantMessage]) async throws -> OrgAssistantMessage {
        guard isEnabled else { throw IntegrationOSError.providerUnavailable("orgAssistant") }
        guard await ledger.isGranted(scope: .orgKnowledgeRead, providerId: "amen") else {
            throw IntegrationOSError.consentDenied(.orgKnowledgeRead)
        }

        let historyPayload = history.map { msg -> [String: Any] in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let payload: [String: Any] = [
            "orgId": orgId,
            "question": question,
            "history": historyPayload
        ]

        let result = try await functions.httpsCallable("orgAssistant").call(payload)
        guard let data = result.data as? [String: Any],
              let answer = data["answer"] as? String else {
            throw IntegrationOSError.providerUnavailable("orgAssistant")
        }

        // Rule: all AI-generated outputs start approved: false
        return OrgAssistantMessage(
            role: .assistant,
            content: answer,
            approved: false,
            timestamp: Date(),
            citations: data["citations"] as? [String] ?? []
        )
    }
}
