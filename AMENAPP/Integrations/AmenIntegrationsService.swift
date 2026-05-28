import Foundation
import FirebaseFunctions
import UIKit

@MainActor
final class AmenIntegrationsService: ObservableObject {
    @Published private(set) var accounts: [AmenIntegrationAccountSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let functions = Functions.functions(region: "us-central1")

    var accountCards: [AmenIntegrationAccountSummary] {
        AmenIntegrationAccountSummary.Provider.allCases.map { provider in
            accounts.first(where: { $0.provider == provider }) ?? .placeholder(provider: provider)
        }
    }

    func refreshAccounts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("getAmenIntegrationAccounts").call([:])
            let data = result.data as? [String: Any]
            let rawAccounts = data?["accounts"] as? [[String: Any]] ?? []
            accounts = rawAccounts.compactMap(Self.parseAccount)
            errorMessage = nil
        } catch {
            errorMessage = readableError(error)
        }
    }

    func connect(provider: AmenIntegrationAccountSummary.Provider) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await functions.httpsCallable("startIntegrationOAuth").call([
                "provider": provider.rawValue
            ])
            guard
                let data = result.data as? [String: Any],
                let authUrlString = data["authorizationUrl"] as? String,
                let url = URL(string: authUrlString)
            else {
                throw AmenIntegrationsClientError.invalidResponse
            }
            await UIApplication.shared.open(url)
            errorMessage = nil
        } catch {
            errorMessage = readableError(error)
        }
    }

    func revoke(account: AmenIntegrationAccountSummary) async {
        guard account.status != .notConnected else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await functions.httpsCallable("revokeAmenIntegrationAccount").call([
                "accountId": account.id
            ])
            await refreshAccounts()
        } catch {
            errorMessage = readableError(error)
        }
    }

    func createMeeting(from draft: AmenMeetingDraft) async throws -> URL {
        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let payload: [String: Any] = [
            "requestId": requestId,
            "provider": draft.provider.rawValue,
            "accountId": draft.accountId,
            "title": draft.title,
            "description": draft.description,
            "agenda": draft.agenda,
            "scriptureFocus": draft.scriptureFocus,
            "startTime": ISO8601DateFormatter().string(from: draft.startTime),
            "endTime": ISO8601DateFormatter().string(from: draft.endTime),
            "privacyLevel": draft.privacyLevel,
            "amenSpaceId": draft.amenSpaceId as Any,
            "participants": []
        ]
        let result = try await functions.httpsCallable("createAmenMeeting").call(payload)
        guard
            let data = result.data as? [String: Any],
            let meetingUrlString = data["meetingUrl"] as? String,
            let meetingUrl = URL(string: meetingUrlString)
        else {
            throw AmenIntegrationsClientError.invalidResponse
        }
        return meetingUrl
    }

    private static func parseAccount(_ data: [String: Any]) -> AmenIntegrationAccountSummary? {
        guard
            let id = data["id"] as? String,
            let providerRaw = data["provider"] as? String,
            let provider = AmenIntegrationAccountSummary.Provider(rawValue: providerRaw)
        else { return nil }

        let statusRaw = data["status"] as? String ?? "notConnected"
        let status = AmenIntegrationAccountSummary.Status(rawValue: statusRaw) ?? .error
        let scopes = data["scopes"] as? [String] ?? []
        let workspaceName = data["workspaceName"] as? String
        let expiresAtMillis = data["expiresAtMillis"] as? Double

        return AmenIntegrationAccountSummary(
            id: id,
            provider: provider,
            status: status,
            scopes: scopes,
            workspaceName: workspaceName,
            expiresAtMillis: expiresAtMillis
        )
    }

    private func readableError(_ error: Error) -> String {
        let message = (error as NSError).localizedDescription
        if message.contains("disabled") {
            return "This integration is not enabled for your account yet."
        }
        if message.contains("App Check") {
            return "AMEN could not verify this app session. Please try again."
        }
        return message
    }
}

enum AmenIntegrationsClientError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "AMEN received an unexpected integrations response."
        }
    }
}
