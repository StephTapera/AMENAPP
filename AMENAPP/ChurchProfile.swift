import Foundation

struct ChurchProfile: Codable, Identifiable, Hashable {
    let id: String
    let ownerUserId: String

    var displayName: String
    var username: String
    var bio: String?

    var logoURL: String?
    var coverPhotoURL: String?

    var websiteURL: String?
    var livestreamURL: String?
    var givingURL: String?
    var phoneNumber: String?
    var email: String?

    var verificationStatus: VerificationStatus
    var denomination: String?
    var address: ChurchAddress?
    var serviceTimes: [ChurchServiceTime]

    var adminUserIds: [String]
    var moderatorUserIds: [String]
    var contentManagerUserIds: [String]

    var memberCountApprox: Int?
    var createdAt: Date
    var updatedAt: Date
}
