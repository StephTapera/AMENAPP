// FindChurch2SearchExtension.swift
// AMENAPP — Find Church 2.0, Wave 2
//
// Extends search functionality to include gatherings.
// Provides pure helper functions for chip-based filtering and life-stage sorting.

import Foundation
import CoreLocation

// MARK: - GatheringSearchResult

/// Wraps a `GatheringObject` as a search result conforming to `Identifiable`.
struct GatheringSearchResult: Identifiable {
    let gathering: GatheringObject

    var id: String { gathering.id }

    /// Human-readable subtitle combining type and cadence.
    var subtitle: String {
        "\(gathering.gatheringType.displayName) · \(gathering.meetingCadence.rawValue.capitalized)"
    }
}

// MARK: - FitChip Filtering

/// Filters a list of churches using the active `FitChip` selections from a `SeekerProfile`.
///
/// - Parameters:
///   - chips:     The chips the seeker has toggled on.
///   - churches:  The full candidate list.
///   - location:  Required when `.nearMe` is active; ignored otherwise.
///   - radiusMiles: Maximum distance for `.nearMe` filter (default 20 mi).
/// - Returns: Churches satisfying ALL active chip conditions.
func filterFitChips(_ chips: [SeekerProfile.FitChip],
                    from churches: [ChurchObject],
                    location: CLLocation? = nil,
                    radiusMiles: Double = 20.0) -> [ChurchObject] {
    guard !chips.isEmpty else { return churches }

    return churches.filter { church in
        chips.allSatisfy { chip in
            churchSatisfies(chip: chip, church: church,
                            location: location, radiusMiles: radiusMiles)
        }
    }
}

// MARK: - Life-Stage Sorting

/// Sorts gatherings so those whose `lifeStage` array contains `lifeStage` appear first.
/// Within each partition the original relative order is preserved (stable).
func sortByLifeStage(_ lifeStage: GatheringObject.LifeStageTag,
                     gatherings: [GatheringObject]) -> [GatheringObject] {
    gatherings.sorted { a, b in
        let aMatches = a.lifeStage.contains(lifeStage)
        let bMatches = b.lifeStage.contains(lifeStage)
        // Both match or both don't match → preserve original order via stable sort semantics
        if aMatches == bMatches { return false }
        return aMatches  // matching items come first
    }
}

// MARK: - Private chip-matching helpers

private func churchSatisfies(chip: SeekerProfile.FitChip,
                              church: ChurchObject,
                              location: CLLocation?,
                              radiusMiles: Double) -> Bool {
    switch chip {

    case .nearMe:
        guard let loc = location else { return true }  // no location = don't filter
        return church.coordinate.distance(from: loc) <= radiusMiles

    case .serviceToday:
        let todayWeekday = Calendar.current.component(.weekday, from: Date()) // 1=Sun
        return church.serviceTimes.contains { $0.dayOfWeek == todayWeekday }

    case .youngAdults:
        return church.ministryTags.contains("youth")
            || church.ministryTags.contains("young_adults")

    case .families:
        return church.accessibility.hasChildcare
            || church.ministryTags.contains("families")

    case .traditional:
        return church.beliefs?.worshipStyle == "traditional"
            || church.beliefs?.worshipStyle == "liturgical"

    case .modernWorship:
        return church.beliefs?.worshipStyle == "contemporary"

    case .smallChurch:
        if let count = church.staffCount { return count <= 5 }
        return true  // unknown size → include

    case .largeChurch:
        if let count = church.staffCount { return count > 10 }
        return true

    case .nonDenominational:
        return church.denominationIsFlexible
            || church.denominationFamily?.lowercased() == "non-denominational"

    case .baptist:
        return church.denominationFamily?.lowercased().contains("baptist") == true

    case .methodist:
        return church.denominationFamily?.lowercased().contains("methodist") == true

    case .pentecostal:
        return church.denominationFamily?.lowercased().contains("pentecostal") == true
            || church.denominationFamily?.lowercased().contains("charismatic") == true

    case .catholic:
        return church.denominationFamily?.lowercased().contains("catholic") == true

    case .orthodox:
        return church.denominationFamily?.lowercased().contains("orthodox") == true

    case .spanishService:
        return church.serviceTimes.contains { $0.languages.contains("es") }
            || church.accessibility.languages.contains("es")

    case .aslAvailable:
        return church.accessibility.hasASL
            || church.serviceTimes.contains { $0.isAccessibleASL }
    }
}
