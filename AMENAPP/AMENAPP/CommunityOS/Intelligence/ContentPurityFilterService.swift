// ContentPurityFilterService.swift
// AMEN App — Community Around Content OS / Intelligence
//
// Manages the user's purity filter preference and provides filtering decisions
// for ContentObject and raw PurityRating values.
// All mutation is @MainActor-safe via @AppStorage.

import Foundation
import SwiftUI

// MARK: - PurityFilterLevel

/// The user-selectable level of purity filtering applied to content in their feed and discovery.
enum PurityFilterLevel: String, CaseIterable, Codable {
    case allowAll    = "allow_all"
    case familySafe  = "family_safe"
    case churchSafe  = "church_safe"
    case kidsSafe    = "kids_safe"

    var displayName: String {
        switch self {
        case .allowAll:   return "Allow All"
        case .familySafe: return "Family Safe"
        case .churchSafe: return "Church Safe"
        case .kidsSafe:   return "Kids Safe"
        }
    }

    var description: String {
        switch self {
        case .allowAll:
            return "Show all content regardless of purity rating. Unreviewed content is included."
        case .familySafe:
            return "Show content rated Family Safe or not yet reviewed. Recommended for most households."
        case .churchSafe:
            return "Show only content rated Family Safe. Best for shared devices and church environments."
        case .kidsSafe:
            return "Show only content explicitly rated Family Safe. Strictest setting for young children."
        }
    }

    /// The PurityRating values permitted through this filter level.
    var allowedRatings: [PurityRating] {
        switch self {
        case .allowAll:
            return PurityRating.allCases
        case .familySafe:
            return [.familySafe, .unreviewed]
        case .churchSafe:
            return [.familySafe]
        case .kidsSafe:
            return [.familySafe]
        }
    }
}

// Expose allCases on PurityRating for filter logic
extension PurityRating: CaseIterable {
    public static var allCases: [PurityRating] {
        [.familySafe, .someConcerns, .notRecommended, .unreviewed]
    }
}

// MARK: - ContentPurityFilterService

/// @MainActor service that manages the user's current purity filter level
/// and provides shouldShow decisions for content objects and raw ratings.
///
/// Filter preference is persisted via @AppStorage under the key "purityFilterLevel"
/// so it survives app restarts without a server round-trip.
@MainActor
final class ContentPurityFilterService: ObservableObject {

    // MARK: Singleton

    static let shared = ContentPurityFilterService()

    private init() {}

    // MARK: Persistence

    /// Persisted raw value of the user's chosen filter level.
    @AppStorage("purityFilterLevel") private var storedLevel: String = PurityFilterLevel.familySafe.rawValue

    // MARK: Public API

    /// The current filter level. Setting this value persists the change immediately.
    var filterLevel: PurityFilterLevel {
        get {
            PurityFilterLevel(rawValue: storedLevel) ?? .familySafe
        }
        set {
            storedLevel = newValue.rawValue
            dlog("[ContentPurityFilterService] filterLevel updated to: \(newValue.displayName)")
            objectWillChange.send()
        }
    }

    /// Returns true if the content object passes the current filter level.
    /// Always returns true when the purityEngine flag is disabled.
    func shouldShow(contentObject: ContentObject) -> Bool {
        guard CommunityOSFlagService.shared.isEnabled(.purityEngine) else {
            return true
        }
        return shouldShow(purityRating: contentObject.purityRating)
    }

    /// Returns true if the given purity rating passes the current filter level.
    /// Always returns true when the purityEngine flag is disabled.
    func shouldShow(purityRating: PurityRating) -> Bool {
        guard CommunityOSFlagService.shared.isEnabled(.purityEngine) else {
            return true
        }
        let allowed = filterLevel.allowedRatings.contains(purityRating)
        dlog("[ContentPurityFilterService] shouldShow(\(purityRating.rawValue)) → \(allowed) at level: \(filterLevel.displayName)")
        return allowed
    }
}
