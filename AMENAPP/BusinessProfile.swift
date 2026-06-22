import Foundation

struct BusinessProfile: Codable, Identifiable, Hashable {
    let id: String
    let ownerUserId: String

    var displayName: String
    var username: String
    var bio: String?

    var logoURL: String?
    var coverPhotoURL: String?
    var websiteURL: String?
    var contactEmail: String?

    var category: String?
    var missionStatement: String?
    var verificationStatus: VerificationStatus

    var adminUserIds: [String]
    var analyticsEnabled: Bool

    var createdAt: Date
    var updatedAt: Date
}
