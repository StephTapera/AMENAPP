import Foundation

enum VerificationStatus: String, Codable, CaseIterable {
    case unverified
    case pending
    case verified
    case rejected
}
