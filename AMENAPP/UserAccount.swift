import Foundation

struct UserAccount: Codable, Identifiable, Hashable {
    let id: String
    let accountType: AccountType
    var displayName: String
    var username: String
    var bio: String?
    var profilePhotoURL: String?
    var coverPhotoURL: String?
    var verificationStatus: VerificationStatus
    var churchAffiliationSummary: ChurchAffiliationSummary?
    var createdAt: Date
    var updatedAt: Date
}
