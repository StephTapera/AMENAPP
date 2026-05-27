// AmenIntegrationService.swift
// AMEN Integrations Platform — Firebase callable wrapper service
// All provider calls go through Firebase Functions. No direct API calls from iOS.

import Foundation
import FirebaseFunctions

@MainActor
final class AmenIntegrationService {

    static let shared = AmenIntegrationService()
    private let functions = Functions.functions()

    // MARK: - Connections

    func listConnections() async throws -> [AmenIntegrationConnection] {
        let result = try await functions.httpsCallable("integrationsListConnections").call()
        guard let data = result.data as? [String: Any],
              let raw = data["connections"] as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict -> AmenIntegrationConnection? in
            guard let accountId = dict["accountId"] as? String,
                  let providerRaw = dict["provider"] as? String,
                  let provider = AmenIntegrationProvider(rawValue: providerRaw),
                  let statusRaw = dict["status"] as? String else { return nil }
            let status = AmenIntegrationStatus(rawValue: statusRaw) ?? .error
            return AmenIntegrationConnection(
                accountId: accountId,
                provider: provider,
                status: status,
                isOrgLevel: dict["isOrgLevel"] as? Bool ?? false,
                displayName: dict["displayName"] as? String,
                email: dict["email"] as? String,
                workspaceName: dict["workspaceName"] as? String,
                connectedAt: dict["connectedAt"] as? Double,
                expiresAt: dict["expiresAt"] as? Double
            )
        }
    }

    // MARK: - OAuth

    func startOAuth(provider: AmenIntegrationProvider) async throws -> AmenOAuthStartResponse {
        let result = try await functions.httpsCallable("integrationsStartOAuth").call(["provider": provider.rawValue])
        guard let data = result.data as? [String: Any] else {
            throw AmenIntegrationClientError.unknown("bad-response")
        }
        if let errorCode = data["errorCode"] as? String {
            throw AmenIntegrationClientError.from(errorCode, provider: provider)
        }
        guard let authUrl = data["authUrl"] as? String,
              let stateToken = data["stateToken"] as? String else {
            throw AmenIntegrationClientError.unknown("missing-fields")
        }
        return AmenOAuthStartResponse(authUrl: authUrl, stateToken: stateToken)
    }

    func completeOAuth(provider: AmenIntegrationProvider, code: String, stateToken: String) async throws -> AmenOAuthCompleteResponse {
        let result = try await functions.httpsCallable("integrationsCompleteOAuth").call([
            "provider": provider.rawValue,
            "code": code,
            "stateToken": stateToken,
        ])
        guard let data = result.data as? [String: Any] else {
            throw AmenIntegrationClientError.unknown("bad-response")
        }
        if let errorCode = data["errorCode"] as? String {
            throw AmenIntegrationClientError.from(errorCode, provider: provider)
        }
        return AmenOAuthCompleteResponse(
            success: data["success"] as? Bool,
            errorCode: nil,
            provider: data["provider"] as? String,
            status: data["status"] as? String,
            displayName: data["displayName"] as? String,
            email: data["email"] as? String
        )
    }

    func refreshConnection(provider: AmenIntegrationProvider) async throws {
        let result = try await functions.httpsCallable("integrationsRefreshConnection").call(["provider": provider.rawValue])
        if let data = result.data as? [String: Any], let errorCode = data["errorCode"] as? String {
            throw AmenIntegrationClientError.from(errorCode, provider: provider)
        }
    }

    func disconnectProvider(provider: AmenIntegrationProvider) async throws {
        let result = try await functions.httpsCallable("integrationsDisconnectProvider").call(["provider": provider.rawValue])
        if let data = result.data as? [String: Any], let errorCode = data["errorCode"] as? String {
            throw AmenIntegrationClientError.from(errorCode, provider: provider)
        }
    }

    // MARK: - Meeting Links

    func createMeetingLink(gatheringId: String, provider: AmenIntegrationProvider) async throws -> AmenGatheringMeetingLinkResult {
        let result = try await functions.httpsCallable("gatheringsCreateMeetingLink").call([
            "gatheringId": gatheringId,
            "provider": provider.rawValue,
        ])
        guard let data = result.data as? [String: Any] else {
            throw AmenIntegrationClientError.unknown("bad-response")
        }
        if let errorCode = data["errorCode"] as? String {
            throw AmenIntegrationClientError.from(errorCode, provider: provider)
        }
        return AmenGatheringMeetingLinkResult(
            success: data["success"] as? Bool,
            errorCode: nil,
            gatheringId: data["gatheringId"] as? String,
            provider: data["provider"] as? String,
            joinUrl: data["joinUrl"] as? String,
            providerMeetingId: data["providerMeetingId"] as? String
        )
    }

    // MARK: - AI Suggestions

    func suggestTitles(gatheringType: String, contextHint: String? = nil) async throws -> [AmenGatheringTitleSuggestion] {
        var params: [String: Any] = ["gatheringType": gatheringType]
        if let hint = contextHint { params["contextHint"] = hint }
        let result = try await functions.httpsCallable("gatheringSuggestTitles").call(params)
        guard let data = result.data as? [String: Any],
              let raw = data["suggestions"] as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let title = d["title"] as? String else { return nil }
            return AmenGatheringTitleSuggestion(title: title, rationale: d["rationale"] as? String)
        }
    }

    func suggestAgenda(gatheringType: String, durationMinutes: Int) async throws -> [AmenGatheringAgendaItem] {
        let result = try await functions.httpsCallable("gatheringSuggestAgenda").call([
            "gatheringType": gatheringType,
            "durationMinutes": durationMinutes,
        ])
        guard let data = result.data as? [String: Any],
              let raw = data["agendaItems"] as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let dur = d["durationMinutes"] as? Int,
                  let activity = d["activity"] as? String else { return nil }
            return AmenGatheringAgendaItem(durationMinutes: dur, activity: activity, scriptureReference: d["scriptureReference"] as? String)
        }
    }

    func suggestScripture(gatheringType: String) async throws -> [AmenGatheringScriptureSuggestion] {
        let result = try await functions.httpsCallable("gatheringSuggestScripture").call(["gatheringType": gatheringType])
        guard let data = result.data as? [String: Any],
              let raw = data["suggestions"] as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let ref = d["reference"] as? String,
                  let theme = d["theme"] as? String,
                  let preview = d["preview"] as? String else { return nil }
            return AmenGatheringScriptureSuggestion(reference: ref, theme: theme, preview: preview)
        }
    }

    func sendReminder(gatheringId: String) async throws -> Int {
        let result = try await functions.httpsCallable("gatheringsSendReminder").call(["gatheringId": gatheringId])
        guard let data = result.data as? [String: Any] else { return 0 }
        if let errorCode = data["errorCode"] as? String {
            throw AmenIntegrationClientError.from(errorCode)
        }
        return data["recipientCount"] as? Int ?? 0
    }

    func listSlackChannels() async throws -> [[String: Any]] {
        let result = try await functions.httpsCallable("integrationsListSlackChannels").call()
        guard let data = result.data as? [String: Any],
              let channels = data["channels"] as? [[String: Any]] else { return [] }
        return channels
    }
}
