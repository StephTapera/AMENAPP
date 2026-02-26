//
//  TwoFactorAuthService.swift
//  AMENAPP
//
//  Two-Factor Authentication (2FA) service using phone SMS
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import Combine

class TwoFactorAuthService: ObservableObject {
    static let shared = TwoFactorAuthService()
    
    @Published var is2FAEnabled = false
    @Published var phoneNumber: String?
    @Published var verificationId: String?
    @Published var isVerifying = false
    
    private let db = Firestore.firestore()
    private let userDefaultsKey = "twoFactorAuthEnabled"
    private let phoneNumberKey = "twoFactorPhoneNumber"
    
    private init() {
        load2FASettings()
    }
    
    // MARK: - Check 2FA Status
    
    func load2FASettings() {
        is2FAEnabled = UserDefaults.standard.bool(forKey: userDefaultsKey)
        phoneNumber = UserDefaults.standard.string(forKey: phoneNumberKey)
        
        print("📱 2FA Settings loaded - Enabled: \(is2FAEnabled), Phone: \(phoneNumber ?? "none")")
    }
    
    // MARK: - Setup 2FA
    
    /// Send verification code to phone number to set up 2FA
    func setupTwoFactor(phoneNumber: String) async throws -> String {
        // Format phone number to E.164
        let formattedPhone = formatPhoneNumber(phoneNumber)
        
        print("📱 Setting up 2FA for phone: \(formattedPhone)")
        print("📱 Raw phone input: \(phoneNumber)")
        
        #if targetEnvironment(simulator)
        print("⚠️ SIMULATOR DETECTED: Phone Auth has limitations in simulator")
        print("💡 To test in simulator, you need to:")
        print("   1. Go to Firebase Console → Authentication → Sign-in method → Phone")
        print("   2. Click 'Phone numbers for testing'")
        print("   3. Add test phone number (e.g., +1 650 555 1234) with test code (e.g., 123456)")
        print("   4. Use that exact number here")
        print("   OR test on a real device for full SMS functionality")
        #endif
        
        do {
            // Send SMS verification code
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(formattedPhone, uiDelegate: nil)
            
            self.verificationId = verificationID
            self.phoneNumber = formattedPhone
            
            print("✅ 2FA verification code sent to \(formattedPhone)")
            print("✅ Verification ID: \(verificationID)")
            
            return verificationID
            
        } catch let error as NSError {
            print("❌ Phone verification failed with error:")
            print("   Code: \(error.code)")
            print("   Domain: \(error.domain)")
            print("   Description: \(error.localizedDescription)")
            print("   UserInfo: \(error.userInfo)")
            
            // Check for common Firebase Phone Auth errors
            if error.domain == "FIRAuthErrorDomain" {
                switch error.code {
                case 17010: // Invalid phone number
                    throw TwoFactorError.setupFailed("Invalid phone number format. Please use format: +1 (555) 123-4567")
                case 17007: // Phone number already in use
                    throw TwoFactorError.setupFailed("This phone number is already linked to another account")
                case 17028: // Firebase verification quota exceeded
                    throw TwoFactorError.setupFailed("Too many verification attempts. Please try again later")
                case 17999: // App verification failed (reCAPTCHA)
                    throw TwoFactorError.setupFailed("App verification failed. Make sure you have a working internet connection")
                default:
                    throw TwoFactorError.setupFailed(error.localizedDescription)
                }
            }
            
            throw TwoFactorError.setupFailed(error.localizedDescription)
        }
    }
    
    /// Verify SMS code and enable 2FA
    func verifyAndEnable2FA(verificationCode: String) async throws {
        guard let verificationId = verificationId,
              let phoneNumber = phoneNumber else {
            throw TwoFactorError.noVerificationId
        }
        
        print("🔐 Verifying 2FA code...")
        
        // Verify the SMS code
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationId,
            verificationCode: verificationCode
        )
        
        // Link phone credential to current user (for 2FA)
        guard let user = Auth.auth().currentUser else {
            throw TwoFactorError.notAuthenticated
        }
        
        do {
            // Try to link phone to account (if not already linked)
            if !user.providerData.contains(where: { $0.providerID == "phone" }) {
                try await user.link(with: credential)
                print("✅ Phone credential linked to account")
            } else {
                // Phone already linked, just verify the code is correct
                _ = try await user.reauthenticate(with: credential)
                print("✅ Phone credential verified")
            }
            
            // Enable 2FA in settings
            is2FAEnabled = true
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
            UserDefaults.standard.set(phoneNumber, forKey: phoneNumberKey)
            
            // Save to Firestore
            try await db.collection("users")
                .document(user.uid)
                .updateData([
                    "twoFactorEnabled": true,
                    "twoFactorPhone": phoneNumber,
                    "twoFactorEnabledAt": Timestamp(date: Date())
                ])
            
            print("✅ 2FA enabled successfully")
            
        } catch {
            print("❌ Failed to enable 2FA: \(error.localizedDescription)")
            throw TwoFactorError.verificationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Disable 2FA
    
    func disable2FA() async throws {
        guard let user = Auth.auth().currentUser else {
            throw TwoFactorError.notAuthenticated
        }
        
        // Disable in settings
        is2FAEnabled = false
        phoneNumber = nil
        verificationId = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: phoneNumberKey)
        
        // Update Firestore
        try await db.collection("users")
            .document(user.uid)
            .updateData([
                "twoFactorEnabled": false,
                "twoFactorDisabledAt": Timestamp(date: Date())
            ])
        
        print("⚠️ 2FA disabled")
    }
    
    // MARK: - Verify 2FA at Sign-In
    
    /// Send 2FA code during sign-in
    func send2FACode(phoneNumber: String) async throws -> String {
        let formattedPhone = formatPhoneNumber(phoneNumber)
        
        print("📱 Sending 2FA code to \(formattedPhone)")
        
        let verificationID = try await PhoneAuthProvider.provider()
            .verifyPhoneNumber(formattedPhone, uiDelegate: nil)
        
        self.verificationId = verificationID
        
        print("✅ 2FA code sent")
        
        return verificationID
    }
    
    /// Verify 2FA code during sign-in
    func verify2FACode(verificationCode: String) async throws -> Bool {
        guard let verificationId = verificationId else {
            throw TwoFactorError.noVerificationId
        }
        
        isVerifying = true
        
        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationId,
                verificationCode: verificationCode
            )
            
            // Verify the code by re-authenticating
            guard let user = Auth.auth().currentUser else {
                throw TwoFactorError.notAuthenticated
            }
            
            _ = try await user.reauthenticate(with: credential)
            
            isVerifying = false
            print("✅ 2FA verification successful")
            
            return true
            
        } catch {
            isVerifying = false
            print("❌ 2FA verification failed: \(error.localizedDescription)")
            throw TwoFactorError.verificationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Check if User Has 2FA
    
    func check2FAStatus(userId: String) async -> Bool {
        do {
            let doc = try await db.collection("users")
                .document(userId)
                .getDocument()
            
            let enabled = doc.data()?["twoFactorEnabled"] as? Bool ?? false
            let phone = doc.data()?["twoFactorPhone"] as? String
            
            DispatchQueue.main.async {
                self.is2FAEnabled = enabled
                self.phoneNumber = phone
            }
            
            return enabled
            
        } catch {
            print("❌ Failed to check 2FA status: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get user's 2FA phone number from Firestore
    func get2FAPhone(userId: String) async throws -> String {
        let doc = try await db.collection("users")
            .document(userId)
            .getDocument()
        
        guard let phone = doc.data()?["twoFactorPhone"] as? String else {
            throw TwoFactorError.setupFailed("No phone number configured for 2FA")
        }
        
        return phone
    }
    
    // MARK: - Backup Code Verification (P0 SECURITY)
    
    /// Verify backup code and remove it from Firestore (one-time use)
    /// Returns true if code is valid, false otherwise
    func verifyBackupCode(_ code: String, userId: String) async throws -> Bool {
        print("🔐 Verifying backup code for user: \(userId)")
        
        // Normalize code format (remove spaces, convert to uppercase)
        let normalizedCode = code.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        do {
            // Fetch user document to get backup codes
            let doc = try await db.collection("users")
                .document(userId)
                .getDocument()
            
            guard var backupCodes = doc.data()?["backupCodes"] as? [String] else {
                print("❌ No backup codes found for user")
                throw TwoFactorError.verificationFailed("No backup codes configured")
            }
            
            // Check if any backup code matches (normalize stored codes too)
            var matchedCode: String?
            for storedCode in backupCodes {
                let normalizedStored = storedCode.replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                if normalizedStored.lowercased() == normalizedCode.lowercased() {
                    matchedCode = storedCode
                    break
                }
            }
            
            guard let validCode = matchedCode else {
                print("❌ Backup code does not match any stored codes")
                throw TwoFactorError.verificationFailed("Invalid backup code")
            }
            
            // Remove the used code (one-time use)
            backupCodes.removeAll { $0 == validCode }
            
            // Update Firestore with remaining codes
            try await db.collection("users")
                .document(userId)
                .updateData([
                    "backupCodes": backupCodes,
                    "lastBackupCodeUsedAt": Timestamp(date: Date())
                ])
            
            print("✅ Backup code verified and removed. Remaining codes: \(backupCodes.count)")
            
            return true
            
        } catch let error as TwoFactorError {
            throw error
        } catch {
            print("❌ Failed to verify backup code: \(error.localizedDescription)")
            throw TwoFactorError.verificationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        // Remove all non-digit characters
        let digits = phoneNumber.filter { $0.isNumber }
        
        print("📱 Formatting phone number:")
        print("   Input: \(phoneNumber)")
        print("   Digits only: \(digits)")
        print("   Digit count: \(digits.count)")
        
        // Add country code if not present (assume US +1)
        var formatted: String
        if digits.hasPrefix("1") && digits.count == 11 {
            formatted = "+\(digits)"
        } else if digits.count == 10 {
            formatted = "+1\(digits)"
        } else if phoneNumber.hasPrefix("+") {
            formatted = phoneNumber
        } else {
            formatted = "+\(digits)"
        }
        
        print("   Formatted: \(formatted)")
        return formatted
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
        case .notAuthenticated:
            return "You must be signed in to enable 2FA"
        case .noVerificationId:
            return "No verification ID found. Please request a new code."
        case .verificationFailed(let message):
            return "Verification failed: \(message)"
        case .setupFailed(let message):
            return "Failed to set up 2FA: \(message)"
        case .noBackupCodes:
            return "No backup codes found. Please contact support."
        case .invalidBackupCode:
            return "Invalid backup code. Please try again or use another code."
        }
    }
}
