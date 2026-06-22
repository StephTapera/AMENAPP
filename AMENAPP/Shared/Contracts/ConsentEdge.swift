import Foundation

enum ConsentEdge: String, Codable, CaseIterable, Sendable {
    case notesToMatching
    case notesToGiving
    case messagesToPrayer
    case locationToVisits
    case givingToFeed
    case activityToCheckIns
    case graphToBerean
    case graphToCohorts
    case activityToRhythm
    case crossDeviceContinuity
}

struct ConsentState: Codable, Equatable, Sendable {
    let edge: ConsentEdge
    var isEnabled: Bool
    var updatedAt: Date

    static func defaults(now: Date = Date()) -> [ConsentState] {
        ConsentEdge.allCases.map { edge in
            ConsentState(edge: edge, isEnabled: edge == .activityToRhythm, updatedAt: now)
        }
    }
}
