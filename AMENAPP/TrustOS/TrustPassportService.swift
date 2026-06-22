// TrustPassportService.swift
// AMENAPP — Trust OS
//
// Manages the user's Trust Passport level: reads from Firestore,
// enforces vendor-gate guards on upgrade, and records ledger entries.

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Errors

enum TrustPassportError: LocalizedError {
    case vendorGateRequired(PassportLevel)

    var errorDescription: String? {
        switch self {
        case .vendorGateRequired(let level):
            return "Upgrading to \(level.displayName) requires a third-party verification step."
        }
    }
}

// MARK: - Service

@MainActor
final class TrustPassportService: ObservableObject {

    static let shared = TrustPassportService()

    @Published var currentLevel: PassportLevel = .email

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Fetch

    /// Reads `users/{uid}/trustPassport` and updates `currentLevel`.
    func fetchCurrentLevel(uid: String) async {
        let ref = db.collection("users").document(uid).collection("trustPassport").document("passport")
        do {
            let snapshot = try await ref.getDocument()
            if let raw = snapshot.data()?["level"] as? String,
               let level = PassportLevel(rawValue: raw) {
                currentLevel = level
            }
        } catch {
            print("[TrustPassport] fetchCurrentLevel failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Upgrade

    /// Attempts to upgrade the user's passport to `level`.
    /// Throws `TrustPassportError.vendorGateRequired` if the level needs a vendor gate.
    func upgrade(to level: PassportLevel, uid: String) async throws {
        guard !level.requiresVendorGate else {
            throw TrustPassportError.vendorGateRequired(level)
        }

        let previousLevel = currentLevel

        let passportRef = db
            .collection("users")
            .document(uid)
            .collection("trustPassport")
            .document("passport")

        try await passportRef.setData(["level": level.rawValue], merge: true)
        currentLevel = level

        let entry = TrustLedgerEntry(
            uid: uid,
            action: "passport_upgrade",
            whatChanged: "Trust Passport upgraded from \(previousLevel.rawValue) to \(level.rawValue)",
            why: "User initiated passport level upgrade",
            reversible: false,
            createdAt: Date().timeIntervalSince1970
        )
        await TrustLedgerService.shared.writeEntry(entry)
    }

    // MARK: - Action Gate

    /// Returns `true` when the given action requires Church-level verification or above.
    func requiresUpgrade(for action: String) -> Bool {
        let churchGatedActions: Set<String> = ["shareToSpaces", "mentoring", "hostEvent"]
        guard churchGatedActions.contains(action) else { return false }
        return currentLevel < .church
    }

    // MARK: - Badge

    /// SF symbol name representing the current passport level.
    var verificationBadge: String {
        switch currentLevel {
        case .email:    return "envelope.badge.shield.half.filled"
        case .phone:    return "phone.badge.checkmark"
        case .identity: return "person.badge.shield.checkmark"
        case .church:   return "building.columns.badge.checkmark"
        case .leader:   return "star.badge.circle"
        case .org:      return "building.2.badge.checkmark"
        }
    }
}
