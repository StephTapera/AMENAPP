// AmenAccessPassService.swift
// AMENAPP — Access Pass Firebase Callable Wrapper
//
// All mutations happen through backend callables — never direct Firestore writes.
// App Check is enforced server-side on every callable.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AmenAccessPassService: ObservableObject {
    static let shared = AmenAccessPassService()

    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - Create

    func createAccessPass(_ input: AmenCreateAccessPassInput) async throws -> AmenCreateAccessPassResponse {
        var payload: [String: Any] = [
            "targetType": input.targetType.rawValue,
            "targetId": input.targetId,
            "mode": input.mode.rawValue,
            "title": input.title,
            "requiresAuth": input.requiresAuth,
            "requiresApproval": input.requiresApproval,
            "maxUsesPerUser": input.maxUsesPerUser,
            "safetyProfile": [
                "isSensitive": input.isSensitive,
                "requiresModeratorApproval": input.requiresModeratorApproval,
                "allowYouthAccess": input.allowYouthAccess,
                "allowGuestPreview": input.allowGuestPreview,
                "showMemberVisibilityWarning": input.showMemberVisibilityWarning,
                "showPrayerPrivacyWarning": input.showPrayerPrivacyWarning
            ],
            "landingConfig": [
                "headline": input.landingHeadline,
                "body": input.landingBody,
                "primaryActionLabel": input.primaryActionLabel,
                "allowedActions": input.allowedActions.map(\.rawValue)
            ]
        ]
        if let v = input.orgId               { payload["orgId"] = v }
        if let v = input.churchId            { payload["churchId"] = v }
        if let v = input.spaceId             { payload["spaceId"] = v }
        if let v = input.subtitle            { payload["subtitle"] = v }
        if let v = input.description         { payload["description"] = v }
        if let v = input.secondaryActionLabel { payload["secondaryActionLabel"] = v }
        if !input.allowedEmailDomains.isEmpty { payload["allowedEmailDomains"] = input.allowedEmailDomains }
        if !input.allowedRoleIds.isEmpty      { payload["allowedRoleIds"] = input.allowedRoleIds }
        if !input.allowedMemberUids.isEmpty   { payload["allowedMemberUids"] = input.allowedMemberUids }
        if let v = input.maxUses              { payload["maxUses"] = v }
        if let v = input.startsAt             { payload["startsAt"] = v.timeIntervalSince1970 * 1000 }
        if let v = input.expiresAt            { payload["expiresAt"] = v.timeIntervalSince1970 * 1000 }
        if let v = input.checkInDurationMinutes { payload["checkInDurationMinutes"] = v }

        let result = try await functions.httpsCallable("createAccessPass").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        return try decode(AmenCreateAccessPassResponse.self, from: data)
    }

    // MARK: - Resolve

    func resolveAccessPass(
        accessPassId: String,
        token: String,
        anonymousSessionId: String? = nil,
        devicePlatform: String = "ios",
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    ) async throws -> AmenAccessPassPreview {
        var payload: [String: Any] = [
            "accessPassId": accessPassId,
            "token": token,
            "devicePlatform": devicePlatform,
            "appVersion": appVersion
        ]
        if let sid = anonymousSessionId { payload["anonymousSessionId"] = sid }

        let result = try await functions.httpsCallable("resolveAccessPass").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }

        if let errorCode = data["errorCode"] as? String {
            throw AmenAccessPassError.from(code: errorCode)
        }

        return try decode(AmenAccessPassPreview.self, from: data)
    }

    // MARK: - Accept

    func acceptAccessPass(
        accessPassId: String,
        token: String,
        action: AmenAccessAction,
        requestMessage: String? = nil
    ) async throws -> AmenAcceptAccessPassResponse {
        var payload: [String: Any] = [
            "accessPassId": accessPassId,
            "token": token,
            "action": action.rawValue
        ]
        if let msg = requestMessage { payload["requestMessage"] = msg }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("acceptAccessPass").call(payload)
        } catch {
            // CF-03: surface user-facing message for backend unavailability
            let nsErr = error as NSError
            if nsErr.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: nsErr.code)
                if code == .unimplemented || code == .`internal` {
                    throw AmenAccessPassError.unknown("Access pass service is temporarily unavailable. Please try again.")
                }
            }
            throw error
        }
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }

        if let errorCode = data["errorCode"] as? String {
            throw AmenAccessPassError.from(code: errorCode)
        }

        return try decode(AmenAcceptAccessPassResponse.self, from: data)
    }

    // MARK: - Admin: Status Management

    func revokeAccessPass(accessPassId: String, reason: String? = nil) async throws {
        var payload: [String: Any] = ["accessPassId": accessPassId]
        if let r = reason { payload["reason"] = r }
        _ = try await functions.httpsCallable("revokeAccessPass").call(payload)
    }

    func pauseAccessPass(accessPassId: String) async throws {
        _ = try await functions.httpsCallable("pauseAccessPass").call(["accessPassId": accessPassId])
    }

    func resumeAccessPass(accessPassId: String) async throws {
        _ = try await functions.httpsCallable("resumeAccessPass").call(["accessPassId": accessPassId])
    }

    func rotateAccessPassToken(accessPassId: String) async throws -> AmenRotateTokenResponse {
        let result = try await functions.httpsCallable("rotateAccessPassToken").call(["accessPassId": accessPassId])
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        return try decode(AmenRotateTokenResponse.self, from: data)
    }

    // MARK: - Admin: Request Management

    func approveAccessRequest(requestId: String) async throws {
        _ = try await functions.httpsCallable("approveAccessRequest").call(["requestId": requestId])
    }

    func denyAccessRequest(requestId: String, denialReason: String? = nil) async throws {
        var payload: [String: Any] = ["requestId": requestId]
        if let r = denialReason { payload["denialReason"] = r }
        _ = try await functions.httpsCallable("denyAccessRequest").call(payload)
    }

    // MARK: - Admin: Listing

    func listAccessPassesForTarget(
        targetType: AmenAccessTargetType,
        targetId: String
    ) async throws -> [AmenAccessPassSummary] {
        let payload: [String: Any] = [
            "targetType": targetType.rawValue,
            "targetId": targetId
        ]
        let result = try await functions.httpsCallable("listAccessPassesForTarget").call(payload)
        guard let data = result.data as? [String: Any],
              let items = data["passes"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { try? decode(AmenAccessPassSummary.self, from: $0) }
    }

    func listAccessRequestsForTarget(
        targetType: AmenAccessTargetType,
        targetId: String
    ) async throws -> [AmenAccessRequest] {
        let payload: [String: Any] = [
            "targetType": targetType.rawValue,
            "targetId": targetId
        ]
        let result = try await functions.httpsCallable("listAccessRequestsForTarget").call(payload)
        guard let data = result.data as? [String: Any],
              let items = data["requests"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { try? decode(AmenAccessRequest.self, from: $0) }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: jsonData)
    }
}
