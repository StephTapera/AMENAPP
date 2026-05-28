import Foundation
import FirebaseFirestore
import SwiftUI

struct OrgVerification: Codable {
    var ecfa: VerificationDetail?
    var charityNavigator: CharityNavDetail?
    var candid: VerificationDetail?
    var bbbWga: VerificationDetail?

    struct VerificationDetail: Codable {
        var status: Bool
        var checkedAt: Timestamp?
        var certNumber: String?
    }

    struct CharityNavDetail: Codable {
        var status: Bool
        var checkedAt: Timestamp?
        var rating: Int?
        var reviewCount: Int?
    }

    var trustScore: Int {
        var score = 0
        if ecfa?.status == true { score += 30 }
        if let nav = charityNavigator {
            if nav.status { score += (nav.rating ?? 0) >= 4 ? 30 : (nav.rating ?? 0) >= 3 ? 20 : 10 }
        }
        if candid?.status == true { score += 20 }
        if bbbWga?.status == true { score += 20 }
        return min(score, 100)
    }

    var trustColor: Color {
        switch trustScore {
        case 80...100: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var badges: [(name: String, verified: Bool, icon: String)] {
        [
            ("ECFA", ecfa?.status ?? false, "checkmark.seal.fill"),
            ("Charity Nav", charityNavigator?.status ?? false, "star.fill"),
            ("Candid", candid?.status ?? false, "doc.fill"),
            ("BBB", bbbWga?.status ?? false, "shield.fill")
        ]
    }
}
