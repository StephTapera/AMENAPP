// WebhookRouterService.swift — AMEN IntegrationOS
// Actor that verifies webhook signatures and routes to registered handlers.

import Foundation
import CryptoKit

actor WebhookRouterService {
    static let shared = WebhookRouterService()
    private init() {}

    typealias WebhookHandler = (WebhookPayload) async throws -> Void
    private var handlers: [String: WebhookHandler] = [:]

    // MARK: - Registration

    func registerHandler(for providerId: String, handler: @escaping WebhookHandler) {
        handlers[providerId] = handler
    }

    func unregisterHandler(for providerId: String) {
        handlers.removeValue(forKey: providerId)
    }

    // MARK: - Route

    func route(payload: WebhookPayload, secret: String) async throws {
        guard verify(payload: payload, secret: secret) else {
            throw IntegrationOSError.webhookSignatureInvalid
        }
        guard let handler = handlers[payload.providerId] else { return }
        try await handler(payload)
    }

    // MARK: - Signature Verification (HMAC-SHA256)

    private func verify(payload: WebhookPayload, secret: String) -> Bool {
        guard let keyData = secret.data(using: .utf8) else { return false }
        let key = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: payload.body, using: key)
        let expected = Data(mac).map { String(format: "%02x", $0) }.joined()
        return expected == payload.signature
    }
}
