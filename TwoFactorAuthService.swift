//
//  TwoFactorAuthService.swift
//  AMENAPP
//
//  Two-Factor Authentication (2FA) service using phone SMS.
//
//  STORAGE STRATEGY
//  - Phone number (PII): stored in Keychain only. Never UserDefaults.
//  - 2FA enabled flag: UserDefaults (non-sensitive bool).
//  - Migration: on first load, if old UserDefaults phone key exists, move it to
//    Keychain then delete the UserDefaults entry.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import Combine
import Security

class TwoFactorAuthService: ObservableObject {
    static let shared = TwoFactorAuthService()

    @Published var is2FAEnabled = false
    /// Redacted display value only — e.g. "••• ••• 1234". Never the full number.
    @Published var maskedPhone: String?
    @Published var verificationId: String?
    @Published var isVerifying = false
    /// Number of unused backup codes remaining. Nil = not yet loaded.
    @Published var backupCodesRemaining: Int? = nil
    /// True when backup code count is low (≤ 2 remaining)
    var isBackupCodesLow: Bool { (backupCodesRemaining ?? Int.max) <= 2 }

    private let db = Firestore.firestore()

    // UserDefaults keys (only non-PII)
    private let udEnabledKey = "twoFactorAuthEnabled"
    // Legacy migration key — will be deleted after first run
    private let udLegacyPhoneKey = "twoFactorPhoneNumber"
    // Keychain service + account
    private let keychainService = "com.amen.app"
    private let keychainPhoneAccount = "twoFactorPhone"

    private init() {
        migratePhoneToKeychainIfNeeded()
        load2FASettings()
    }

    // MARK: - Load / Migration

    /// One-time migration: if old UserDefaults phone value exists, move to Keychain.
    private func migratePhoneToKeychainIfNeeded() {
        guard let legacyPhone = UserDefaults.standard.string(forKey: udLegacyPhoneKey),
              !legacyPhone.isEmpty else { return }
        // Store in Keychain
        _ = keychainSave(legacyPhone)
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: udLegacyPhoneKey)
        print("🔐 Migrated 2FA phone from UserDefaults to Keychain")
    }

    func load2FASettings() {
        is2FAEnabled = UserDefaults.standard.bool(forKey: udEnabledKey)
        // Load masked display value from Keychain (never log full number)
        if let stored = keychainLoad() {
            maskedPhone = maskPhone(stored)
        }
        print("📱 2FA Settings loaded — Enabled: \(is2FAEnabled)")
    }

    // MARK: - Setup 2FA

    func setupTwoFactor(phoneNumber: String) async throws -> String {
        let formatted = formatPhoneNumber(phoneNumber)
        // Never log the full phone number
        print("📱 Setting up 2FA (number redacted)")

        #if targetEnvironment(simulator)
        print("⚠️ SIMULATOR: Use Firebase Console test phone numbers")
        #endif

        do {
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(formatted, uiDelegate: nil)
            self.verificationId = verificationID
            // Temporarily hold in memory only — not written to disk yet
            self._pendingPhoneNumber = formatted
            return verificationID
        } catch let error as NSError {
            if error.domain == "FIRAuthErrorDomain" {
                switch error.code {
                case 17010: throw TwoFactorError.setupFailed("Invalid phone number format.")
                case 17007: throw TwoFactorError.setupFailed("Phone number already linked to another account.")
                case 17028: throw TwoFactorError.setupFailed("Too many attempts. Please try again later.")
                case 17999: throw TwoFactorError.setupFailed("App verification failed. Check your internet connection.")
                default: throw TwoFactorError.setupFailed(error.localizedDescription)
                }
            }
            throw TwoFactorError.setupFailed(error.localizedDescription)
        }
    }

    // Temporary in-memory store only during verification flow
    private var _pendingPhoneNumber: String?

    // MARK: - Verify + Enable

    func verifyAndEnable2FA(verificationCode: String) async throws {
        guard let verificationId = verificationId else { throw TwoFactorError.noVerificationId }
        guard let phoneNumber = _pendingPhoneNumber else { throw TwoFactorError.noVerificationId }
        guard let user = Auth.auth().currentUser else { throw TwoFactorError.notAuthenticated }

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationId,
            verificationCode: verificationCode
        )

        do {
            if !user.providerData.contains(where: { $0.providerID == "phone" }) {
                try await user.link(with: credential)
            } else {
                _ = try await user.reauthenticate(with: credential)
            }

            // Persist to Keychain (PII)
            guard keychainSave(phoneNumber) else {
                throw TwoFactorError.setupFailed("Could not securely save phone number.")
            }
            _pendingPhoneNumber = nil

            // Persist enabled flag to UserDefaults (non-PII bool)
            is2FAEnabled = true
            UserDefaults.standard.set(true, forKey: udEnabledKey)
            maskedPhone = maskPhone(phoneNumber)

            // Save to Firestore — store only masked value, not full number
            try await db.collection("users").document(user.uid).updateData([
                "twoFactorEnabled": true,
                "twoFactorMaskedPhone": maskPhone(phoneNumber),
                "twoFactorEnabledAt": Timestamp(date: Date())
            ])
            print("✅ 2FA enabled successfully")
        } catch {
            print("❌ Failed to enable 2FA")
            throw TwoFactorError.verificationFailed(error.localizedDescription)
        }
    }

    // MARK: - Disable 2FA

    func disable2FA() async throws {
        guard let user = Auth.auth().currentUser else { throw TwoFactorError.notAuthenticated }

        is2FAEnabled = false
        maskedPhone = nil
        verificationId = nil
        _pendingPhoneNumber = nil

        UserDefaults.standard.removeObject(forKey: udEnabledKey)
        _ = keychainDelete()

        try await db.collection("users").document(user.uid).updateData([
            "twoFactorEnabled": false,
            "twoFactorDisabledAt": Timestamp(date: Date())
        ])
        print("⚠️ 2FA disabled")
    }

    // MARK: - Verify at Sign-In

    func send2FACode(phoneNumber: String) async throws -> String {
        let formatted = formatPhoneNumber(phoneNumber)
        print("📱 Sending 2FA code (number redacted)")
        let verificationID = try await PhoneAuthProvider.provider()
            .verifyPhoneNumber(formatted, uiDelegate: nil)
        self.verificationId = verificationID
        return verificationID
    }

    func verify2FACode(verificationCode: String) async throws -> Bool {
        guard let verificationId = verificationId else { throw TwoFactorError.noVerificationId }
        guard let user = Auth.auth().currentUser else { throw TwoFactorError.notAuthenticated }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationId,
                verificationCode: verificationCode
            )
            _ = try await user.reauthenticate(with: credential)
            print("✅ 2FA verification successful")
            return true
        } catch {
            print("❌ 2FA verification failed")
            throw TwoFactorError.verificationFailed(error.localizedDescription)
        }
    }

    // MARK: - Check Status

    func check2FAStatus(userId: String) async -> Bool {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            let enabled = doc.data()?["twoFactorEnabled"] as? Bool ?? false
            let masked = doc.data()?["twoFactorMaskedPhone"] as? String
            await MainActor.run {
                self.is2FAEnabled = enabled
                self.maskedPhone = masked
            }
            return enabled
        } catch {
            print("❌ Failed to check 2FA status")
            return false
        }
    }

    func get2FAPhone(userId: String) async throws -> String {
        // Return full phone from Keychain for signed-in user's own flow
        if let stored = keychainLoad() { return stored }
        // Fallback: Firestore masked
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let masked = doc.data()?["twoFactorMaskedPhone"] as? String else {
            throw TwoFactorError.setupFailed("No phone number configured for 2FA")
        }
        return masked
    }

    // MARK: - Backup Codes

    /// Loads the remaining backup code count from the user document.
    /// The count field is maintained by the app — incremented on generation, decremented on use.
    func loadBackupCodeCount(userId: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            let count = doc.data()?["backupCodesRemaining"] as? Int
            await MainActor.run { self.backupCodesRemaining = count }
        } catch {
            print("⚠️ Could not load backup code count: \(error.localizedDescription)")
        }
    }

    /// Generates 6 new backup codes, stores them in the secured subcollection,
    /// and updates the `backupCodesRemaining` count on the user document.
    /// Returns the plaintext codes to display once to the user.
    func regenerateBackupCodes(userId: String) async throws -> [String] {
        let codes: [String] = (0..<6).map { _ in
            String(format: "%04d-%04d", Int.random(in: 1000...9999), Int.random(in: 1000...9999))
        }

        // Delete old backup codes subcollection documents
        let codesRef = db.collection("users").document(userId).collection("backupCodes")
        let existing = try? await codesRef.getDocuments()
        if let existing {
            let batch = db.batch()
            for doc in existing.documents {
                batch.deleteDocument(doc.reference)
            }
            try? await batch.commit()
        }

        // Write new codes
        let newBatch = db.batch()
        for code in codes {
            let docRef = codesRef.document()
            newBatch.setData(["code": code, "used": false, "createdAt": Timestamp(date: Date())], forDocument: docRef)
        }
        try await newBatch.commit()

        // Update the count on the user document
        try await db.collection("users").document(userId).updateData([
            "backupCodesRemaining": codes.count,
            "backupCodesRegeneratedAt": Timestamp(date: Date())
        ])

        await MainActor.run { self.backupCodesRemaining = codes.count }
        return codes
    }

    func verifyBackupCode(_ code: String, userId: String) async throws -> Bool {
        let normalized = code
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)

        let doc = try await db.collection("users").document(userId).getDocument()
        guard var backupCodes = doc.data()?["backupCodes"] as? [String] else {
            throw TwoFactorError.verificationFailed("No backup codes configured")
        }

        var matched: String?
        for stored in backupCodes {
            let norm = stored.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .trimmingCharacters(in: .whitespaces)
            if norm.lowercased() == normalized.lowercased() { matched = stored; break }
        }
        guard let valid = matched else {
            throw TwoFactorError.verificationFailed("Invalid backup code")
        }
        backupCodes.removeAll { $0 == valid }
        let newCount = max(0, backupCodes.count)
        try await db.collection("users").document(userId).updateData([
            "backupCodes": backupCodes,
            "backupCodesRemaining": newCount,
            "lastBackupCodeUsedAt": Timestamp(date: Date())
        ])
        await MainActor.run { self.backupCodesRemaining = newCount }
        return true
    }

    // MARK: - Keychain Helpers

    @discardableResult
    private func keychainSave(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        _ = keychainDelete() // Remove any existing entry first
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainPhoneAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func keychainLoad() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainPhoneAccount,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    private func keychainDelete() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainPhoneAccount
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Phone Formatting / Masking

    private func formatPhoneNumber(_ number: String) -> String {
        let digits = number.filter { $0.isNumber }
        if digits.hasPrefix("1") && digits.count == 11 { return "+\(digits)" }
        if digits.count == 10 { return "+1\(digits)" }
        if number.hasPrefix("+") { return number }
        return "+\(digits)"
    }

    private func maskPhone(_ phone: String) -> String {
        // Show only last 4 digits: ••• ••• 1234
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 4 else { return "••• ••••" }
        let last4 = String(digits.suffix(4))
        return "••• ••• \(last4)"
    }
}

// MARK: - Errors

enum TwoFactorError: LocalizedError {
    case notAuthenticated
    case noVerificationId
    case verificationFailed(String)
    case setupFailed(String)
    case noBackupCodes
    case invalidBackupCode

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to enable 2FA."
        case .noVerificationId: return "No verification ID. Please request a new code."
        case .verificationFailed(let m): return "Verification failed: \(m)"
        case .setupFailed(let m): return "Failed to set up 2FA: \(m)"
        case .noBackupCodes: return "No backup codes found. Please contact support."
        case .invalidBackupCode: return "Invalid backup code. Please try again."
        }
    }
}
