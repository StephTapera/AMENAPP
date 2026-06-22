// SettingsCallableClient.swift
// AMEN — Settings/Safety system · Foundation
//
// Thin wrapper over the Settings/Safety callable Cloud Functions. Every sensitive
// op (S2) routes through here, pinned to the contract region (us-east1). Callers
// degrade gracefully: if a callable is not deployed yet, this throws .notDeployed
// and the surface shows a SettingsDisabledSurface rather than a dead button.

import Foundation
import FirebaseFunctions

enum SettingsCallableError: Error, LocalizedError {
    case notDeployed
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notDeployed: return "This action isn’t available yet."
        case .unavailable: return "This action is temporarily unavailable. Please try again."
        case .failed(let message): return message
        }
    }
}

final class SettingsCallableClient {

    static let shared = SettingsCallableClient()

    // Pinned to the frozen contract region. New Settings functions deploy to us-east1
    // (us-central1 is at quota).
    private lazy var functions = Functions.functions(region: SettingsFunctionContract.region)

    private init() {}

    /// Invoke a Settings/Safety callable. Throws SettingsCallableError on failure so
    /// the calling surface can show a safe disabled/error state.
    @discardableResult
    func call(_ callable: SettingsFunctionContract.Callable, payload: [String: Any] = [:]) async throws -> [String: Any] {
        do {
            let result = try await functions.httpsCallable(callable.rawValue).call(payload)
            return (result.data as? [String: Any]) ?? [:]
        } catch let error as NSError {
            // Map Firebase Functions errors to graceful settings errors.
            if error.domain == FunctionsErrorDomain,
               let code = FunctionsErrorCode(rawValue: error.code) {
                switch code {
                case .notFound, .unimplemented:
                    throw SettingsCallableError.notDeployed
                case .unavailable, .deadlineExceeded:
                    throw SettingsCallableError.unavailable
                default:
                    throw SettingsCallableError.failed(error.localizedDescription)
                }
            }
            throw SettingsCallableError.failed(error.localizedDescription)
        }
    }
}
