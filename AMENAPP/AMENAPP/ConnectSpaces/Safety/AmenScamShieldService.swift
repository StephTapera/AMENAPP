// AmenScamShieldService.swift
// AMEN Connect + Spaces — Scam Shield Detection Service
// Built 2026-06-02

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Service

@MainActor
final class AmenScamShieldService: ObservableObject {

    static let shared = AmenScamShieldService()

    private let functions = Functions.functions()

    // MARK: - Local pre-screen

    /// Fast keyword-based pre-screen before the CF call.
    /// Returns matched flag types; empty array means clean at this layer.
    func localPrescreen(text: String) -> [AmenScamFlagType] {
        let lower = text.lowercased()
        var flags: [AmenScamFlagType] = []

        let moneyTerms = ["send me", "transfer", "payment", "venmo", "zelle"]
        if moneyTerms.contains(where: { lower.contains($0) }) {
            flags.append(.moneyRequest)
        }

        let giftCardTerms = ["gift card", "apple card", "google play"]
        if giftCardTerms.contains(where: { lower.contains($0) }) {
            flags.append(.giftCardRequest)
        }

        let cryptoTerms = ["bitcoin", "crypto", "wallet address", "eth", "usdt"]
        if cryptoTerms.contains(where: { lower.contains($0) }) {
            flags.append(.cryptoRequest)
        }

        let offPlatformTerms = ["outside the app", "off platform", "direct pay"]
        if offPlatformTerms.contains(where: { lower.contains($0) }) {
            flags.append(.offPlatformPaymentRequest)
        }

        return flags
    }

    // MARK: - Scan

    /// Scans a message against the Firebase callable and returns a flag if found.
    ///
    /// Calling pattern:
    /// 1. localPrescreen is called first — if it finds flags, they are shown immediately.
    /// 2. This function is always called regardless; it fires the CF in the background.
    /// Returns nil if the CF reports no flags.
    func scan(messageId: String, authorId: String, text: String) async -> AmenScamShieldFlag? {
        guard Auth.auth().currentUser != nil else { return nil }
        do {
            let callable = functions.httpsCallable(AmenSpacesPhase1Callable.scanMessageForScam.rawValue)
            let result = try await callable.call([
                "messageId": messageId,
                "authorId": authorId,
                "text": text
            ])
            guard let data = result.data as? [String: Any] else { return nil }
            return decodeFlag(from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Decode

    private func decodeFlag(from data: [String: Any]) -> AmenScamShieldFlag? {
        guard
            let id = data["id"] as? String,
            let messageId = data["messageId"] as? String,
            let authorId = data["authorId"] as? String,
            let rawFlagTypes = data["flagTypes"] as? [String],
            let confidence = data["confidence"] as? Double
        else { return nil }

        guard confidence > 0 else { return nil }

        let flagTypes = rawFlagTypes.compactMap(AmenScamFlagType.init(rawValue:))
        guard !flagTypes.isEmpty else { return nil }

        return AmenScamShieldFlag(
            id: id,
            messageId: messageId,
            authorId: authorId,
            flagTypes: flagTypes,
            confidence: confidence,
            surfaced: data["surfaced"] as? Bool ?? true,
            reviewedByHuman: data["reviewedByHuman"] as? Bool ?? false,
            flaggedAt: (data["flaggedAt"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }
}
