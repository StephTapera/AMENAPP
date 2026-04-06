// HeaderContextProvider.swift
// Smart Header Orchestrator — Context model & provider

import SwiftUI
import Combine

// MARK: - Feed Intent Mode

enum FeedIntentMode: String, CaseIterable, Identifiable {
    case reflect  = "Reflect"
    case learn    = "Learn"
    case connect  = "Connect"
    case create   = "Create"
    case pray     = "Pray"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .reflect: return "moon.stars"
        case .learn:   return "book.fill"
        case .connect: return "person.2.fill"
        case .create:  return "pencil.and.sparkles"
        case .pray:    return "hands.sparkles.fill"
        }
    }

    var accentColor: String {
        switch self {
        case .reflect: return "indigo"
        case .learn:   return "blue"
        case .connect: return "teal"
        case .create:  return "orange"
        case .pray:    return "purple"
        }
    }
}

// MARK: - Context Model

struct HeaderContext {
    var timeOfDay: TimeOfDay
    var userName: String
    var intentMode: FeedIntentMode?
    var screenType: ScreenType
    var scrollOffset: CGFloat
    var hasVerseReady: Bool
    var verseAlreadyShownToday: Bool
    var isFirstLaunchToday: Bool

    static let `default` = HeaderContext(
        timeOfDay: .morning,
        userName: "",
        intentMode: nil,
        screenType: .feed,
        scrollOffset: 0,
        hasVerseReady: false,
        verseAlreadyShownToday: false,
        isFirstLaunchToday: false
    )
}

// MARK: - Supporting Enums

enum TimeOfDay {
    case earlyMorning   // 5–8
    case morning        // 8–12
    case afternoon      // 12–17
    case evening        // 17–21
    case night          // 21–24 / 0–5

    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8:   return .earlyMorning
        case 8..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .night
        }
    }
}

enum ScreenType {
    case feed, profile, church, berean, resources, messages, create, settings, other
}

// MARK: - Provider

@MainActor
final class HeaderContextProvider: ObservableObject {
    @Published private(set) var context = HeaderContext.default

    private var cancellables = Set<AnyCancellable>()
    private let lastShownVerseKey = "topChrome_verseShownDate"
    private let lastLaunchKey    = "topChrome_lastLaunchDate"

    init() {
        refresh()
    }

    func refresh(
        screenType: ScreenType = .feed,
        intentMode: FeedIntentMode? = nil,
        scrollOffset: CGFloat = 0,
        userName: String = "",
        hasVerseReady: Bool = false
    ) {
        let lastShown  = UserDefaults.standard.object(forKey: lastShownVerseKey) as? Date
        let lastLaunch = UserDefaults.standard.object(forKey: lastLaunchKey) as? Date
        let isFirst    = lastLaunch.map { !Calendar.current.isDate($0, inSameDayAs: Date()) } ?? true

        if isFirst {
            UserDefaults.standard.set(Date(), forKey: lastLaunchKey)
        }

        context = HeaderContext(
            timeOfDay: .current,
            userName: userName,
            intentMode: intentMode,
            screenType: screenType,
            scrollOffset: scrollOffset,
            hasVerseReady: hasVerseReady,
            verseAlreadyShownToday: lastShown.map { Calendar.current.isDate($0, inSameDayAs: Date()) } ?? false,
            isFirstLaunchToday: isFirst
        )
    }

    func markVerseShown() {
        UserDefaults.standard.set(Date(), forKey: lastShownVerseKey)
        context.verseAlreadyShownToday = true
    }
}
