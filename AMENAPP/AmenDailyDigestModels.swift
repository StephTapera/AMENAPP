import Foundation

struct AmenDailyDigest: Codable, Identifiable, Equatable {
    let id: String
    let dateKey: String
    let greeting: String
    let title: String
    let verseText: String
    let verseReference: String
    let contextText: String?
    let reflectionText: String?
    let prayerPrompt: String?
    let passage: AmenDailyPassage?
    let weather: AmenDailyWeatherContext?
    let holiday: AmenDailyHolidayContext?
    let actions: [AmenDailyDigestAction]
    let priority: AmenDailyDigestPriority
    let generatedAt: Date?
    let source: AmenDailyDigestSource

    var collapsedActions: [AmenDailyDigestAction] { Array(actions.prefix(2)) }

    var shareText: String {
        var parts = ["\(verseText)\n- \(verseReference)"]
        if let reflectionText, !reflectionText.isEmpty { parts.append(reflectionText) }
        parts.append("From Amen")
        return parts.joined(separator: "\n\n")
    }

    static func fallback(date: Date = Date(), source: AmenDailyDigestSource = .bundled) -> AmenDailyDigest {
        let dateKey = AmenDailyDigestDateKey.string(from: date)
        return AmenDailyDigest(
            id: "amen-daily-\(dateKey)",
            dateKey: dateKey,
            greeting: AmenDailyDigestDateKey.greeting(for: date),
            title: "Good morning",
            verseText: "The Lord is my shepherd; I shall not want.",
            verseReference: "Psalm 23:1",
            contextText: "Start today grounded.",
            reflectionText: "God's care is steady before the day begins. Take a quiet moment to receive his presence and move with peace.",
            prayerPrompt: "Lord, guide my attention today and help me walk with trust.",
            passage: AmenDailyPassage(reference: "Psalm 23", title: "The Lord Is My Shepherd", book: "Psalm", chapter: 23, startVerse: 1, endVerse: 6),
            weather: nil,
            holiday: nil,
            actions: [
                AmenDailyDigestAction(id: "start_selah", title: "Start Selah", systemImage: "sparkles", destination: .selah, analyticsName: "start_selah"),
                AmenDailyDigestAction(id: "read_passage", title: "Read Passage", systemImage: "book", destination: .passage(reference: "Psalm 23"), analyticsName: "read_passage")
            ],
            priority: .defaultVerse,
            generatedAt: date,
            source: source
        )
    }

    func asPersonalizedVerse() -> PersonalizedDailyVerse {
        PersonalizedDailyVerse(
            reference: verseReference,
            text: verseText,
            theme: title,
            reflection: reflectionText ?? contextText ?? "",
            actionPrompt: prayerPrompt ?? "Take a quiet moment with today's passage.",
            relatedVerses: passage.map { [$0.reference] } ?? [],
            prayerPrompt: prayerPrompt ?? "Lord, help me receive your word today.",
            personalizedFor: nil,
            date: AmenDailyDigestDateKey.date(from: dateKey) ?? Date()
        )
    }
}

struct AmenDailyWeatherContext: Codable, Equatable {
    let temperature: Int?
    let condition: String?
    let high: Int?
    let low: Int?
    let precipitationChance: Int?
    let alertLevel: WeatherAlertLevel
    let summary: String?
    let spiritualTieIn: String?
}

enum WeatherAlertLevel: String, Codable, Equatable { case none, notable, severe }

struct AmenDailyHolidayContext: Codable, Equatable {
    let name: String
    let type: AmenDailyHolidayType
    let message: String
    let suggestedVerseReference: String?
    let dateKey: String
}

enum AmenDailyHolidayType: String, Codable, Equatable { case general, christian, season }

struct AmenDailyPassage: Codable, Equatable {
    let reference: String
    let title: String?
    let book: String?
    let chapter: Int?
    let startVerse: Int?
    let endVerse: Int?
}

struct AmenDailyDigestAction: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String?
    let destination: AmenDailyDigestDestination
    let analyticsName: String
}

enum AmenDailyDigestDestination: Codable, Equatable {
    case selah
    case passage(reference: String)
    case bereanAI(prompt: String)
    case churchNotes(prefill: String?)
    case findAChurch
    case prayer(prompt: String?)
    case share(text: String)
    case journal(prefill: String?)
    case none

    enum CodingKeys: String, CodingKey { case type, reference, prompt, prefill, text }

    var analyticsValue: String {
        switch self {
        case .selah: return "selah"
        case .passage: return "passage"
        case .bereanAI: return "berean_ai"
        case .churchNotes: return "church_notes"
        case .findAChurch: return "find_a_church"
        case .prayer: return "prayer"
        case .share: return "share"
        case .journal: return "journal"
        case .none: return "none"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "selah": self = .selah
        case "passage": self = .passage(reference: try container.decodeIfPresent(String.self, forKey: .reference) ?? "")
        case "bereanAI", "berean_ai": self = .bereanAI(prompt: try container.decodeIfPresent(String.self, forKey: .prompt) ?? "")
        case "churchNotes", "church_notes": self = .churchNotes(prefill: try container.decodeIfPresent(String.self, forKey: .prefill))
        case "findAChurch", "find_a_church": self = .findAChurch
        case "prayer": self = .prayer(prompt: try container.decodeIfPresent(String.self, forKey: .prompt))
        case "share": self = .share(text: try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "journal": self = .journal(prefill: try container.decodeIfPresent(String.self, forKey: .prefill))
        default: self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .selah: try container.encode("selah", forKey: .type)
        case .passage(let reference):
            try container.encode("passage", forKey: .type)
            try container.encode(reference, forKey: .reference)
        case .bereanAI(let prompt):
            try container.encode("bereanAI", forKey: .type)
            try container.encode(prompt, forKey: .prompt)
        case .churchNotes(let prefill):
            try container.encode("churchNotes", forKey: .type)
            try container.encodeIfPresent(prefill, forKey: .prefill)
        case .findAChurch: try container.encode("findAChurch", forKey: .type)
        case .prayer(let prompt):
            try container.encode("prayer", forKey: .type)
            try container.encodeIfPresent(prompt, forKey: .prompt)
        case .share(let text):
            try container.encode("share", forKey: .type)
            try container.encode(text, forKey: .text)
        case .journal(let prefill):
            try container.encode("journal", forKey: .type)
            try container.encodeIfPresent(prefill, forKey: .prefill)
        case .none: try container.encode("none", forKey: .type)
        }
    }
}

enum AmenDailyDigestPriority: String, Codable, Equatable {
    case christianHoliday, generalHoliday, severeWeather, notableWeather, personalContinuation, defaultVerse
}

enum AmenDailyDigestSource: String, Codable, Equatable { case bundled, remoteConfig, backend, cached }

enum AmenDailyDigestState: Equatable {
    case idle
    case loading(AmenDailyDigest?)
    case loaded(AmenDailyDigest)
    case fallback(AmenDailyDigest)
    case failed(String, AmenDailyDigest)

    var digest: AmenDailyDigest? {
        switch self {
        case .idle: return nil
        case .loading(let digest): return digest
        case .loaded(let digest), .fallback(let digest), .failed(_, let digest): return digest
        }
    }
}

enum AmenDailyDigestDateKey {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Daily Verse"
        }
    }
}
