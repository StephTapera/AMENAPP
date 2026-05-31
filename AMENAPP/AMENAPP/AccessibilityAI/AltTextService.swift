//
//  AltTextService.swift
//  AMENAPP
//
//  A8 — Per-media alt text generation via the a11yAltTextProxy Cloud Function.
//  Results are cached in-process so rapid scroll / re-render doesn't trigger
//  redundant CF round-trips for the same image URL.
//

import Foundation
import FirebaseFunctions

// MARK: - AltTextService

@MainActor
final class AltTextService {

    static let shared = AltTextService()
    private init() {}

    private var cache: [String: String] = [:]
    private let functions = Functions.functions()

    // MARK: - Public API

    func generateAltText(for imageURL: URL, context: String?) async -> String? {
        guard AMENFeatureFlags.shared.perMediaCaptionAltTextEnabled else { return nil }

        let key = imageURL.absoluteString
        if let cached = cache[key] { return cached }

        let payload: [String: Any] = [
            "imageUrl": key,
            "context": context ?? ""
        ]

        do {
            let result = try await functions.httpsCallable("a11yAltTextProxy").safeCall(payload)
            guard
                let data = result.data as? [String: Any],
                let altText = data["altText"] as? String
            else {
                dlog("[AltTextService] Unexpected response shape from a11yAltTextProxy")
                return nil
            }
            cache[key] = altText
            return altText
        } catch {
            // Network errors and CF errors are non-fatal — callers display whatever
            // text the user typed (or nothing) rather than blocking the compose flow.
            dlog("[AltTextService] a11yAltTextProxy error: \(error.localizedDescription)")
            return nil
        }
    }

    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - Private Helpers

private func dlog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
