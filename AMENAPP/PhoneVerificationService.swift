//
//  PhoneVerificationService.swift
//  AMENAPP
//
//  Phone number verification service for identity verification
//  Uses Firebase Phone Auth for SMS OTP verification
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Verification Status

enum PhoneVerificationStatus {
    case notStarted
    case codeSent
    case verifying
    case verified
    case failed(Error)
    
    var isVerified: Bool {
        if case .verified = self {
            return true
        }
        return false
    }
}

// MARK: - Phone Verification Service

@MainActor
class PhoneVerificationService: ObservableObject {
    static let shared = PhoneVerificationService()
    
    @Published var verificationStatus: PhoneVerificationStatus = .notStarted
    @Published var phoneNumber: String = ""
    @Published var isPhoneVerified: Bool = false
    
    private let db = Firestore.firestore()
    private var verificationID: String?
    
    private init() {
        // Load verification status on init
        Task {
            await loadVerificationStatus()
        }
    }
    
    // MARK: - Send Verification Code
    
    /// Send SMS verification code to phone number
    /// - Parameter phoneNumber: Phone number in E.164 format (e.g., +1234567890)
    func sendVerificationCode(to phoneNumber: String) async throws {
        #if DEBUG
        dlog("📱 Sending verification code to: \(phoneNumber)")
        #endif
        
        // Validate phone number format
        guard phoneNumber.hasPrefix("+") && phoneNumber.count >= 10 else {
            throw PhoneVerificationError.invalidPhoneNumber
        }
        
        verificationStatus = .verifying
        
        do {
            // Firebase Phone Auth - send verification code
            let verificationID = try await PhoneAuthProvider.provider()
                .verifyPhoneNumber(phoneNumber, uiDelegate: nil)
            
            self.verificationID = verificationID
            self.phoneNumber = phoneNumber
            self.verificationStatus = .codeSent
            
            dlog("✅ Verification code sent successfully")
            dlog("   Verification ID: [REDACTED]")
            
        } catch {
            dlog("❌ Failed to send verification code: \(error.localizedDescription)")
            verificationStatus = .failed(error)
            throw error
        }
    }
    
    // MARK: - Verify Code
    
    /// Verify SMS code entered by user
    /// - Parameter code: 6-digit SMS verification code
    func verifyCode(_ code: String) async throws {
        dlog("🔐 Verifying code: \(code)")
        
        guard let verificationID = verificationID else {
            throw PhoneVerificationError.noVerificationID
        }
        
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else {
            throw PhoneVerificationError.invalidCode
        }
        
        verificationStatus = .verifying
        
        do {
            // Create credential with verification ID and code
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: code
            )
            
            // Link credential to current user (if signed in)
            if let currentUser = Auth.auth().currentUser {
                // Link phone number to existing account
                try await currentUser.link(with: credential)
                dlog("✅ Phone number linked to account")
            } else {
                // Sign in with phone credential (new user)
                try await Auth.auth().signIn(with: credential)
                dlog("✅ Signed in with phone number")
            }
            
            // Mark as verified in Firestore
            try await markPhoneAsVerified()
            
            verificationStatus = .verified
            isPhoneVerified = true
            
            dlog("✅ Phone verification complete!")
            
        } catch {
            dlog("❌ Verification failed: \(error.localizedDescription)")
            verificationStatus = .failed(error)
            throw error
        }
    }
    
    // MARK: - Persistence
    
    /// Mark phone number as verified in Firestore user document
    private func markPhoneAsVerified() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw PhoneVerificationError.notAuthenticated
        }
        
        let userRef = db.collection("users").document(userId)
        
        try await userRef.updateData([
            "phoneVerified": true,
            "phoneNumber": phoneNumber,
            "phoneVerifiedAt": FieldValue.serverTimestamp(),
            "verificationBadges": FieldValue.arrayUnion(["phone"]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        dlog("✅ User document updated with phone verification")
    }
    
    /// Load verification status from Firestore
    func loadVerificationStatus() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ Not authenticated - cannot load verification status")
            return
        }
        
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            if let data = userDoc.data() {
                let phoneVerified = data["phoneVerified"] as? Bool ?? false
                let storedPhoneNumber = data["phoneNumber"] as? String ?? ""
                
                await MainActor.run {
                    isPhoneVerified = phoneVerified
                    phoneNumber = storedPhoneNumber
                    verificationStatus = phoneVerified ? .verified : .notStarted
                }
                
                dlog("✅ Loaded phone verification status: \(phoneVerified)")
            }
            
        } catch {
            dlog("⚠️ Could not load verification status: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Resend Code
    
    /// Resend verification code to the same phone number
    func resendVerificationCode() async throws {
        guard !phoneNumber.isEmpty else {
            throw PhoneVerificationError.noPhoneNumber
        }
        
        try await sendVerificationCode(to: phoneNumber)
    }
    
    // MARK: - Reset
    
    /// Reset verification state (for testing or retry)
    func reset() {
        verificationID = nil
        phoneNumber = ""
        verificationStatus = .notStarted
    }
}

// MARK: - Phone Verification Errors

enum PhoneVerificationError: LocalizedError {
    case invalidPhoneNumber
    case invalidCode
    case noVerificationID
    case noPhoneNumber
    case notAuthenticated
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber:
            return "Please enter a valid phone number in international format (e.g., +1234567890)"
        case .invalidCode:
            return "Please enter a valid 6-digit verification code"
        case .noVerificationID:
            return "No verification in progress. Please request a new code."
        case .noPhoneNumber:
            return "No phone number provided"
        case .notAuthenticated:
            return "You must be signed in to verify your phone number"
        case .verificationFailed:
            return "Verification failed. Please try again."
        }
    }
}

// MARK: - Firestore Schema Extension

/*
 users/{userId}:
 {
   phoneVerified: boolean
   phoneNumber: string (E.164 format)
   phoneVerifiedAt: timestamp
   verificationBadges: [string] // e.g., ["email", "phone", "photo"]
   verificationTier: string // "new", "emailVerified", "phoneVerified", "photoVerified", "trusted"
 }
 */
