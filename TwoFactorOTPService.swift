import Foundation
import Combine
import FirebaseFunctions
import FirebaseAuth

/// Service for managing Two-Factor Authentication OTP codes
@MainActor
class TwoFactorOTPService: ObservableObject {
    static let shared = TwoFactorOTPService()

    // MARK: - Published Properties

    @Published var isRequesting = false
    @Published var isVerifying = false
    @Published var errorMessage: String?
    @Published var otpId: String?
    @Published var deliveryMethod: String?
    @Published var maskedDestination: String?
    @Published var expiresAt: Date?

    // MARK: - Private Properties

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Request OTP

    /// Request a 2FA OTP code to be sent via email or SMS
    /// - Parameter deliveryMethod: "email" or "sms"
    /// - Returns: True if request was successful
    func requestOTP(deliveryMethod: String) async throws -> Bool {
        guard ["email", "sms"].contains(deliveryMethod) else {
            throw TwoFactorOTPError.invalidDeliveryMethod
        }

        isRequesting = true
        errorMessage = nil

        defer {
            isRequesting = false
        }

        do {
            let callable = functions.httpsCallable("request2FAOTP")
            let result = try await callable.call(["deliveryMethod": deliveryMethod])

            guard let data = result.data as? [String: Any],
                  let success = data["success"] as? Bool,
                  success else {
                throw TwoFactorOTPError.requestFailed
            }

            // Store response data
            self.otpId = data["otpId"] as? String
            self.deliveryMethod = data["deliveryMethod"] as? String
            self.maskedDestination = data["destination"] as? String

            if let expiresAtMs = data["expiresAt"] as? Double {
                self.expiresAt = Date(timeIntervalSince1970: expiresAtMs / 1000)
            }

            dlog("✅ 2FA OTP requested successfully")
            dlog("   - OTP ID: \(self.otpId ?? "unknown")")
            dlog("   - Method: \(self.deliveryMethod ?? "unknown")")
            dlog("   - Destination: \(self.maskedDestination ?? "unknown")")

            return true

        } catch let error as NSError {
            dlog("❌ Failed to request 2FA OTP: \(error.localizedDescription)")

            // Parse Firebase Functions error
            if let details = error.userInfo["details"] as? [String: Any],
               let message = details["message"] as? String {
                errorMessage = message
            } else {
                errorMessage = error.localizedDescription
            }

            throw TwoFactorOTPError.requestFailed
        }
    }

    // MARK: - Verify OTP

    /// Verify a 2FA OTP code
    /// - Parameters:
    ///   - otpId: The OTP ID from the request
    ///   - code: The 6-digit code entered by the user
    /// - Returns: Session token if verification was successful
    func verifyOTP(otpId: String, code: String) async throws -> String {
        guard code.count == 6,
              code.allSatisfy({ $0.isNumber }) else {
            throw TwoFactorOTPError.invalidCode
        }

        isVerifying = true
        errorMessage = nil

        defer {
            isVerifying = false
        }

        do {
            let callable = functions.httpsCallable("verify2FAOTP")
            let result = try await callable.call([
                "otpId": otpId,
                "code": code
            ])

            guard let data = result.data as? [String: Any],
                  let success = data["success"] as? Bool,
                  let verified = data["verified"] as? Bool,
                  success && verified else {
                throw TwoFactorOTPError.verificationFailed
            }

            guard let sessionToken = data["sessionToken"] as? String else {
                throw TwoFactorOTPError.verificationFailed
            }

            dlog("✅ 2FA OTP verified successfully")

            // Clear local state
            self.otpId = nil
            self.deliveryMethod = nil
            self.maskedDestination = nil
            self.expiresAt = nil

            return sessionToken

        } catch let error as NSError {
            dlog("❌ Failed to verify 2FA OTP: \(error.localizedDescription)")

            // Parse Firebase Functions error
            if let details = error.userInfo["details"] as? [String: Any],
               let message = details["message"] as? String {
                errorMessage = message
            } else {
                errorMessage = error.localizedDescription
            }

            throw TwoFactorOTPError.verificationFailed
        }
    }

    // MARK: - Helper Methods

    /// Reset the service state
    func reset() {
        otpId = nil
        deliveryMethod = nil
        maskedDestination = nil
        expiresAt = nil
        errorMessage = nil
        isRequesting = false
        isVerifying = false
    }

    /// Check if the OTP has expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    /// Get time remaining until expiration
    var timeRemaining: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : 0
    }

    /// Format time remaining as string
    var timeRemainingString: String {
        guard let remaining = timeRemaining else { return "" }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Error Types

enum TwoFactorOTPError: LocalizedError {
    case invalidDeliveryMethod
    case requestFailed
    case invalidCode
    case verificationFailed
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .invalidDeliveryMethod:
            return "Delivery method must be 'email' or 'sms'"
        case .requestFailed:
            return "Failed to request verification code"
        case .invalidCode:
            return "Code must be 6 digits"
        case .verificationFailed:
            return "Verification failed. Please check your code and try again."
        case .sessionExpired:
            return "Your code has expired. Please request a new one."
        }
    }
}
