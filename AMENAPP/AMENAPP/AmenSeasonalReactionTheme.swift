import Foundation

struct AmenSeasonalReactionTheme: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let triggerType: AmenContextualTriggerType
    let effectType: AmenContextualEffectType
    let morphSystemImage: String
    let microcopy: String
    let startMonth: Int
    let startDay: Int
    let endMonth: Int
    let endDay: Int

    func isActive(on date: Date, calendar: Calendar = .current) -> Bool {
        let year = calendar.component(.year, from: date)
        guard
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: startDay)),
            let end = calendar.date(from: DateComponents(year: year, month: endMonth, day: endDay))
        else {
            return false
        }

        if start <= end {
            return (start ... end).contains(date)
        }

        guard
            let nextYearEnd = calendar.date(from: DateComponents(year: year + 1, month: endMonth, day: endDay))
        else {
            return false
        }
        return (start ... nextYearEnd).contains(date)
    }

    static let easterWindow = AmenSeasonalReactionTheme(
        id: "easter",
        title: "Easter",
        triggerType: .seasonal,
        effectType: .seasonalIconMorph,
        morphSystemImage: "cross.case.fill",
        microcopy: "Resurrection season",
        startMonth: 3,
        startDay: 20,
        endMonth: 4,
        endDay: 30
    )

    static let christmasWindow = AmenSeasonalReactionTheme(
        id: "christmas",
        title: "Christmas",
        triggerType: .seasonal,
        effectType: .seasonalIconMorph,
        morphSystemImage: "star.fill",
        microcopy: "Advent season",
        startMonth: 12,
        startDay: 1,
        endMonth: 12,
        endDay: 31
    )

    static let allThemes: [AmenSeasonalReactionTheme] = [
        .easterWindow,
        .christmasWindow
    ]

    static func current(for date: Date) -> AmenSeasonalReactionTheme? {
        allThemes.first { $0.isActive(on: date) }
    }
}
