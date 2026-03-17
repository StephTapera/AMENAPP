//
//  BiometricAuthService.swift
//  AMENAPP
//
//  Face ID / Touch ID authentication service
//

import Foundation
import LocalAuthentication
import SwiftUI
import Combine

class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()
    
    @Published var isBiometricEnabled = false
    @Published var biometricType: BiometricType = .none
    
    private let context = LAContext()
    private let userDefaultsKey = "biometricAuthEnabled"
    
    enum BiometricType {
        case none
        case faceID
        case touchID
        case opticID
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return "xmark.circle"
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            }
        }
    }
    
    private init() {
        checkBiometricAvailability()
        loadBiometricPreference()
    }
    
    // MARK: - Check Availability
    
    func checkBiometricAvailability() {
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .opticID
            case .none:
                biometricType = .none
            @unknown default:
                biometricType = .none
            }
            
            print("✅ BiometricAuth: \(biometricType.displayName) available")
        } else {
            biometricType = .none
            
            if let error = error {
                print("⚠️ BiometricAuth: Not available - \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Authenticate
    
    func authenticate(reason: String = "Sign in to AMEN") async -> Bool {
        // Check if biometric is enabled in settings
        guard isBiometricEnabled else {
            print("⚠️ BiometricAuth: Disabled in settings")
            return false
        }
        
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("⚠️ BiometricAuth: Not available - \(error?.localizedDescription ?? "unknown")")
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            
            if success {
                print("✅ BiometricAuth: Authentication successful")
                
                // Success haptic
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            }
            
            return success
            
        } catch let error as LAError {
            print("❌ BiometricAuth: Failed - \(error.localizedDescription)")
            
            // Error haptic
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
            
            // Handle specific errors
            switch error.code {
            case .userCancel:
                print("   User cancelled biometric authentication")
            case .userFallback:
                print("   User chose fallback (password)")
            case .biometryNotEnrolled:
                print("   Biometry not enrolled")
            case .biometryLockout:
                print("   Biometry locked out (too many failed attempts)")
            case .authenticationFailed:
                print("   Authentication failed")
            default:
                print("   Error code: \(error.code.rawValue)")
            }
            
            return false
        } catch {
            // Catch any other errors
            print("❌ BiometricAuth: Unexpected error - \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Settings
    
    func enableBiometric() {
        isBiometricEnabled = true
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
        print("✅ BiometricAuth: Enabled")
    }
    
    func disableBiometric() {
        isBiometricEnabled = false
        UserDefaults.standard.set(false, forKey: userDefaultsKey)
        print("⚠️ BiometricAuth: Disabled")
    }
    
    private func loadBiometricPreference() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: userDefaultsKey)
        print("📱 BiometricAuth: Loaded preference - enabled: \(isBiometricEnabled)")
    }
    
    // MARK: - Check if Available
    
    var isBiometricAvailable: Bool {
        return biometricType != .none
    }
    
    // MARK: - Authenticate with Passcode Fallback
    
    func authenticateWithPasscodeFallback(reason: String = "Sign in to AMEN") async -> Bool {
        let context = LAContext()
        var error: NSError?
        
        // Allow fallback to device passcode
        context.localizedFallbackTitle = "Use Passcode"
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            print("⚠️ BiometricAuth: Device authentication not available - \(error?.localizedDescription ?? "unknown")")
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, // This includes passcode fallback
                localizedReason: reason
            )
            
            if success {
                print("✅ BiometricAuth: Authentication successful (with passcode fallback)")
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            }
            
            return success
            
        } catch {
            print("❌ BiometricAuth: Failed - \(error.localizedDescription)")
            
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
            
            return false
        }
    }
}
