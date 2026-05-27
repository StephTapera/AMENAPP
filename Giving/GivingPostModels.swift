import Foundation
import FirebaseFirestore

struct GivingPost: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var createdAt: Timestamp?
    var narrative: String
    var organizationId: String
    var organizationName: String
    var goalAmount: Int?
    var currentAmount: Int
    var linkedVerses: [LinkedVerse]
    var tags: [String]
    var visibility: String
    var engagementHearts: Int
    var engagementComments: Int
    var engagementShares: Int

    struct LinkedVerse: Codable, Identifiable {
        var id: String { "\(book)\(chapter)\(verse)" }
        var book: String
        var chapter: Int
        var verse: Int
        var text: String
    }

    var progressFraction: Double {
        guard let goal = goalAmount, goal > 0 else { return 0 }
        return min(Double(currentAmount) / Double(goal), 1.0)
    }

    var formattedGoal: String? {
        guard let goal = goalAmount else { return nil }
        return "$\(goal / 100)"
    }

    var formattedCurrent: String { "$\(currentAmount / 100)" }
}

struct OrganizationStub: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var category: [String]
    var logoUrl: String?
    var website: String?
    var trustScore: Int?
    var verified: OrgVerification?

    struct OrgVerification: Codable {
        var ecfaStatus: Bool
        var charityNavigatorStatus: Bool
        var candidStatus: Bool
        var bbbStatus: Bool
    }

    var badgeCount: Int {
        var count = 0
        if verified?.ecfaStatus == true { count += 1 }
        if verified?.charityNavigatorStatus == true { count += 1 }
        if verified?.candidStatus == true { count += 1 }
        if verified?.bbbStatus == true { count += 1 }
        return count
    }
}
