import Foundation

enum BereanOSError: LocalizedError {
    case featureDisabled
    case rateLimitExceeded
    case unauthorized
    case unknown(String)
    /// Alias used by perspective + debate services for CF error messages.
    case cloudFunctionError(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "This feature is not yet available."
        case .rateLimitExceeded:
            return "You've reached the usage limit for this feature. Please try again later."
        case .unauthorized:
            return "You must be signed in to use this feature."
        case .unknown(let msg):
            return msg
        case .cloudFunctionError(let msg):
            return msg
        }
    }
}
