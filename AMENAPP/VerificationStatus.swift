import Foundation

enum VerificationStatus: String, Codable, CaseIterable {
    case unverified
    case pending
    case verified
    case rejected
    
    var icon: String {
        switch self {
        case .unverified: return "questionmark.circle"
        case .pending:    return "clock.circle"
        case .verified:   return "checkmark.circle.fill"
        case .rejected:   return "xmark.circle"
        }
    }
    
    var displayLabel: String {
        switch self {
        case .unverified: return "Unverified"
        case .pending:    return "Pending"
        case .verified:   return "Verified"
        case .rejected:   return "Rejected"
        }
    }
}
