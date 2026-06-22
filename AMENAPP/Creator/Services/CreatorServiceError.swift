import Foundation

enum CreatorServiceError: LocalizedError {
    case notImplemented
    case invalidState
    case blocked
    case notFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Not implemented"
        case .invalidState:
            return "Invalid state"
        case .blocked:
            return "Blocked"
        case .notFound:
            return "Not found"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}
