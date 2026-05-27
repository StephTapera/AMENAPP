// AmenGatheringIntegrationModels.swift
// Models for gathering + integration platform surface

import Foundation

// MARK: - Gathering Integration State

struct AmenGatheringIntegrationState {
    var selectedProvider: AmenIntegrationProvider?
    var meetingLink: AmenGatheringMeetingLinkResult?
    var isCreatingLink = false
    var linkError: AmenIntegrationClientError?

    var hasLink: Bool { meetingLink?.joinUrl != nil }
    var joinUrl: URL? {
        guard let urlString = meetingLink?.joinUrl else { return nil }
        return URL(string: urlString)
    }
}

// MARK: - Schedule Gathering Form

struct AmenScheduleGatheringForm {
    var title: String = ""
    var gatheringType: AmenGatheringType = .smallGroup
    var date: Date = Date().addingTimeInterval(86400) // tomorrow
    var durationMinutes: Int = 60
    var timezone: TimeZone = .current
    var provider: AmenIntegrationProvider? = nil
    var useAISuggestions: Bool = false
    var selectedTitle: String? = nil
    var selectedAgenda: [AmenGatheringAgendaItem] = []
    var selectedScripture: AmenGatheringScriptureSuggestion? = nil
    var notes: String = ""

    var startAtMs: Double { date.timeIntervalSince1970 * 1000 }
    var endAtMs: Double { (date.timeIntervalSince1970 + Double(durationMinutes) * 60) * 1000 }

    var effectiveTitle: String {
        if let selected = selectedTitle, !selected.isEmpty { return selected }
        return title
    }

    var isValid: Bool {
        !effectiveTitle.trimmingCharacters(in: .whitespaces).isEmpty && date > Date()
    }

    var durationLabel: String {
        if durationMinutes < 60 { return "\(durationMinutes) min" }
        let hrs = durationMinutes / 60
        let mins = durationMinutes % 60
        return mins == 0 ? "\(hrs) hr" : "\(hrs) hr \(mins) min"
    }
}

// MARK: - Gathering Types

enum AmenGatheringType: String, CaseIterable, Identifiable {
    case prayerNight
    case bibleStudy
    case worshipNight
    case churchService
    case smallGroup
    case volunteerOpportunity
    case retreat
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prayerNight: return "Prayer Night"
        case .bibleStudy: return "Bible Study"
        case .worshipNight: return "Worship Night"
        case .churchService: return "Church Service"
        case .smallGroup: return "Small Group"
        case .volunteerOpportunity: return "Volunteer"
        case .retreat: return "Retreat"
        case .custom: return "Custom"
        }
    }

    var systemIcon: String {
        switch self {
        case .prayerNight: return "hands.sparkles.fill"
        case .bibleStudy: return "book.fill"
        case .worshipNight: return "music.note"
        case .churchService: return "cross.fill"
        case .smallGroup: return "person.3.fill"
        case .volunteerOpportunity: return "heart.fill"
        case .retreat: return "leaf.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }
}

// MARK: - AI Suggestion State

@MainActor
final class AmenGatheringAISuggestionsViewModel: ObservableObject {
    @Published private(set) var titleSuggestions: [AmenGatheringTitleSuggestion] = []
    @Published private(set) var agendaItems: [AmenGatheringAgendaItem] = []
    @Published private(set) var scriptureSuggestions: [AmenGatheringScriptureSuggestion] = []
    @Published private(set) var followUpPrompts: [String] = []
    @Published private(set) var isLoading = false
    @Published var selectedTitle: AmenGatheringTitleSuggestion?
    @Published var confirmedAgenda: [AmenGatheringAgendaItem] = []
    @Published var confirmedScripture: AmenGatheringScriptureSuggestion?

    private let service = AmenIntegrationService.shared

    func loadSuggestions(for type: AmenGatheringType, durationMinutes: Int = 60) async {
        isLoading = true
        async let titles = service.suggestTitles(gatheringType: type.rawValue)
        async let agenda = service.suggestAgenda(gatheringType: type.rawValue, durationMinutes: durationMinutes)
        async let scripture = service.suggestScripture(gatheringType: type.rawValue)

        do {
            let (t, a, s) = try await (titles, agenda, scripture)
            titleSuggestions = t
            agendaItems = a
            scriptureSuggestions = s
        } catch {
            // Suggestions are non-blocking — fail silently, user can proceed without them
        }
        isLoading = false
    }

    func confirmTitle(_ suggestion: AmenGatheringTitleSuggestion) {
        selectedTitle = suggestion
    }

    func confirmAgenda(_ items: [AmenGatheringAgendaItem]) {
        confirmedAgenda = items
    }

    func confirmScripture(_ suggestion: AmenGatheringScriptureSuggestion) {
        confirmedScripture = suggestion
    }
}
