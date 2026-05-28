//
//  AmenPermissionsService.swift
//  AMENAPP
//
//  Real-time client for the resolved PermissionSet stored in permissions/{uid}.
//
//  Usage:
//    @StateObject private var permsService = AmenPermissionsService()
//    .onAppear { permsService.startListening(for: Auth.auth().currentUser?.uid) }
//    .onChange(of: Auth.auth().currentUser?.uid) { uid in permsService.startListening(for: uid) }
//
//  Then gate UI on:
//    permsService.permissions?.canPostPublic == true
//    permsService.permissions?.shouldShowComposer
//    permsService.permissions?.sendDM != .none
//
//  The client drives affordances only. Every action is enforced server-side
//  in Cloud Functions and Firestore security rules.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - AmenPermissionsService

@MainActor
final class AmenPermissionsService: ObservableObject {

    // MARK: Published state

    @Published private(set) var permissions: AmenPermissionSet?
    @Published private(set) var isLoaded = false
    @Published private(set) var error: Error?

    // MARK: Private

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: Lifecycle

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time listener

    /// Start or restart the real-time listener for a given uid.
    /// Pass nil to stop listening (e.g. on sign-out).
    func startListening(for uid: String?) {
        listener?.remove()
        listener = nil
        isLoaded = false
        permissions = nil
        error = nil

        guard let uid else { return }

        listener = db.collection("permissions").document(uid)
            .addSnapshotListener { [weak self] snapshot, err in
                guard let self else { return }
                Task { @MainActor in
                    if let err {
                        self.error = err
                        self.isLoaded = true
                        return
                    }
                    guard let snapshot, snapshot.exists else {
                        // permissions/{uid} not yet written — fall back to restricted base
                        self.permissions = .restrictedBase
                        self.isLoaded = true
                        return
                    }
                    do {
                        self.permissions = try snapshot.data(as: AmenPermissionSet.self)
                        self.error = nil
                    } catch {
                        self.error = error
                        self.permissions = .restrictedBase
                    }
                    self.isLoaded = true
                }
            }
    }

    func stopListening() {
        startListening(for: nil)
    }

    // MARK: - Callables

    /// Updates the caller's identityMode and receives the freshly resolved PermissionSet.
    /// The listener will also fire automatically via the Firestore trigger, but the
    /// callable response is returned immediately for optimistic UI updates.
    @discardableResult
    func setMode(_ mode: AmenIdentityMode) async throws -> AmenPermissionSet {
        let callable = functions.httpsCallable("setMode")
        let result = try await callable.call(["mode": mode.rawValue])

        guard let data = result.data as? [String: Any],
              let success = data["success"] as? Bool, success,
              let permsData = data["permissions"] as? [String: Any] else {
            throw AmenPermissionsError.unexpectedResponse
        }

        let decoded = try decodeDictionary(permsData, as: AmenPermissionSet.self)
        permissions = decoded
        return decoded
    }

    /// Checks pairwise messaging eligibility server-side before opening a compose sheet.
    func canInitiateDM(with targetUid: String) async throws -> AmenInitiateDMResponse {
        let callable = functions.httpsCallable("initiateDM")
        let result = try await callable.call(["targetUid": targetUid])

        guard let data = result.data as? [String: Any],
              let allowed = data["allowed"] as? Bool else {
            throw AmenPermissionsError.unexpectedResponse
        }
        let reason = data["reason"] as? String
        return AmenInitiateDMResponse(allowed: allowed, reason: reason)
    }

    /// Records the account's date of birth and derives the age tier (teen/adult).
    /// The server enforces the minimum age of 13 and rejects accounts younger than that.
    /// Permissions update automatically via the Firestore snapshot listener after the server
    /// triggers onUserWrite from the ageTier change.
    @discardableResult
    func setDateOfBirth(_ date: Date) async throws -> AmenAgeTier {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let isoString = formatter.string(from: date)

        let callable = functions.httpsCallable("setDateOfBirth")
        let result = try await callable.call(["dateOfBirth": isoString])

        guard let data = result.data as? [String: Any],
              let tierRaw = data["ageTier"] as? String,
              let tier = AmenAgeTier(rawValue: tierRaw) else {
            throw AmenPermissionsError.unexpectedResponse
        }
        return tier
    }

    /// Initiates the guardian consent flow for an under-13 account.
    /// Returns the linkId created server-side.
    func requestGuardianConsent(guardianEmail: String) async throws -> String {
        let callable = functions.httpsCallable("requestGuardianConsent")
        let result = try await callable.call(["guardianEmail": guardianEmail])

        guard let data = result.data as? [String: Any],
              let linkId = data["linkId"] as? String else {
            throw AmenPermissionsError.unexpectedResponse
        }
        return linkId
    }

    // MARK: - Convenience gates

    /// Whether the post composer should be presented.
    var canShowComposer: Bool {
        permissions?.canPostPublic == true
    }

    /// Whether the DM entry point should be presented for this account.
    var canShowDMEntry: Bool {
        permissions?.canSendAnyDM == true
    }

    /// Whether the account is loaded and in an active, non-restricted state.
    var isFullyActive: Bool {
        guard let p = permissions else { return false }
        return p.canPostPublic || p.canSendAnyDM || p.canBeDiscovered
    }

    // MARK: - Private helpers

    private func decodeDictionary<T: Decodable>(_ dict: [String: Any], as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

// MARK: - Error

enum AmenPermissionsError: LocalizedError {
    case unexpectedResponse
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Unexpected response from the server."
        case .permissionDenied(let reason):
            return reason
        }
    }
}

// MARK: - SwiftUI Environment Convenience

private struct PermissionsServiceKey: EnvironmentKey {
    static let defaultValue: AmenPermissionsService = AmenPermissionsService()
}

extension EnvironmentValues {
    var permissionsService: AmenPermissionsService {
        get { self[PermissionsServiceKey.self] }
        set { self[PermissionsServiceKey.self] = newValue }
    }
}

// MARK: - View modifier helpers

extension View {
    /// Hides the view when the account lacks the given capability.
    /// Falls back to hidden while permissions are loading (fail-closed).
    func requiresPermission(_ keyPath: KeyPath<AmenPermissionSet, Bool>,
                            using service: AmenPermissionsService) -> some View {
        let allowed = service.permissions.map { $0[keyPath: keyPath] } ?? false
        return self.opacity(allowed ? 1 : 0).allowsHitTesting(allowed)
    }
}
