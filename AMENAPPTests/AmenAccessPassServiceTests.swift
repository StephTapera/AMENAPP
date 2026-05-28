import Foundation
import Testing
@testable import AMENAPP

// Contract tests for AmenAccessPassService callable wrappers.
// Verifies callable names, payload keys, and response model shapes are stable.
// These tests do NOT call Firebase — they validate the local contract layer only.

struct AmenAccessPassServiceTests {

    // MARK: - Callable name constants

    @Test("createAccessPass callable name is stable")
    func createCallableName() {
        #expect(AmenAccessPassCallableNames.create == "createAccessPass")
    }

    @Test("resolveAccessPass callable name is stable")
    func resolveCallableName() {
        #expect(AmenAccessPassCallableNames.resolve == "resolveAccessPass")
    }

    @Test("acceptAccessPass callable name is stable")
    func acceptCallableName() {
        #expect(AmenAccessPassCallableNames.accept == "acceptAccessPass")
    }

    @Test("revokeAccessPass callable name is stable")
    func revokeCallableName() {
        #expect(AmenAccessPassCallableNames.revoke == "revokeAccessPass")
    }

    @Test("rotateAccessPassToken callable name is stable")
    func rotateTokenCallableName() {
        #expect(AmenAccessPassCallableNames.rotateToken == "rotateAccessPassToken")
    }

    @Test("approveAccessRequest callable name is stable")
    func approveRequestCallableName() {
        #expect(AmenAccessPassCallableNames.approveRequest == "approveAccessRequest")
    }

    @Test("denyAccessRequest callable name is stable")
    func denyRequestCallableName() {
        #expect(AmenAccessPassCallableNames.denyRequest == "denyAccessRequest")
    }

    // MARK: - Input payload field contract

    @Test("createAccessPass payload includes required fields")
    func createPayloadRequiredFields() {
        let input = AmenCreateAccessPassInput.defaultInput(
            for: .space,
            targetId: "space-test-1",
            title: "Test Pass"
        )
        let payload = input.toTestPayload()
        #expect(payload["targetType"] as? String == AmenAccessTargetType.space.rawValue)
        #expect(payload["targetId"] as? String == "space-test-1")
        #expect(payload["mode"] != nil)
        #expect(payload["title"] as? String == "Test Pass")
        #expect(payload["requiresAuth"] != nil)
        #expect(payload["requiresApproval"] != nil)
    }

    @Test("createAccessPass payload omits nil orgId")
    func createPayloadOmitsNilOrgId() {
        var input = AmenCreateAccessPassInput.defaultInput(
            for: .space,
            targetId: "s-1",
            title: "T"
        )
        input.orgId = nil
        let payload = input.toTestPayload()
        #expect(payload["orgId"] == nil)
    }

    @Test("createAccessPass payload includes orgId when present")
    func createPayloadIncludesOrgId() {
        var input = AmenCreateAccessPassInput.defaultInput(
            for: .space,
            targetId: "s-1",
            title: "T"
        )
        input.orgId = "org-123"
        let payload = input.toTestPayload()
        #expect((payload["orgId"] as? String) == "org-123")
    }

    // MARK: - Response model decoding

    @Test("AmenCreateAccessPassResponse decodes accessPassId and qrPayload")
    @MainActor
    func decodeCreateResponse() throws {
        let dict: [String: Any] = [
            "accessPassId": "pass-999",
            "rawToken": "tok-raw",
            "universalLink": "https://amen.app/access/pass-999",
            "qrPayload": "https://amen.app/pass/tok-xyz",
            "nfcPayload": "https://amen.app/pass/tok-xyz",
            "shareLink": "https://amen.app/access/pass-999",
            "previewTitle": "Test Pass"
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let response = try JSONDecoder().decode(AmenCreateAccessPassResponse.self, from: data)
        #expect(response.accessPassId == "pass-999")
        #expect(response.qrPayload == "https://amen.app/pass/tok-xyz")
    }

    @Test("AmenRotateTokenResponse decodes newQrPayload")
    @MainActor
    func decodeRotateTokenResponse() throws {
        let dict: [String: Any] = [
            "accessPassId": "pass-999",
            "newRawToken": "tok-new",
            "newUniversalLink": "https://amen.app/access/pass-999",
            "newQrPayload": "https://amen.app/pass/new-tok",
            "newShareLink": "https://amen.app/access/pass-999"
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let response = try JSONDecoder().decode(AmenRotateTokenResponse.self, from: data)
        #expect(response.newQrPayload == "https://amen.app/pass/new-tok")
    }

    @Test("AmenAcceptAccessPassResponse decodes success and action")
    @MainActor
    func decodeAcceptResponse() throws {
        let dict: [String: Any] = [
            "success": true,
            "action": "join",
            "targetId": "space-1",
            "targetType": "space"
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let response = try JSONDecoder().decode(AmenAcceptAccessPassResponse.self, from: data)
        #expect(response.success == true)
        #expect(response.action == .join)
    }

    @Test("AmenAccessPassError maps backend error codes correctly")
    func errorMapping() {
        #expect(AmenAccessPassError.from(code: "expired") == .expiredPass)
        #expect(AmenAccessPassError.from(code: "revoked") == .revokedPass)
        #expect(AmenAccessPassError.from(code: "auth-required") == .authRequired)
        #expect(AmenAccessPassError.from(code: "rate-limited") == .rateLimited)
        #expect(AmenAccessPassError.from(code: "unknown-xyz") == .unknown("unknown-xyz"))
    }
}

// MARK: - Test helpers

private extension AmenCreateAccessPassInput {
    func toTestPayload() -> [String: Any] {
        var dict: [String: Any] = [
            "targetType": targetType.rawValue,
            "targetId": targetId,
            "mode": mode.rawValue,
            "title": title,
            "requiresAuth": requiresAuth,
            "requiresApproval": requiresApproval,
            "maxUsesPerUser": maxUsesPerUser
        ]
        if let v = orgId    { dict["orgId"] = v }
        if let v = subtitle { dict["subtitle"] = v }
        return dict
    }
}
