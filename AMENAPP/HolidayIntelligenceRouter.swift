//
//  HolidayIntelligenceRouter.swift
//  AMENAPP
//
//  Holiday Intelligence Router — the decision engine that determines what
//  seasonal content to surface, where, and when across all app surfaces.
//
//  Input signals:
//    - Current date / liturgical state
//    - Holiday lead-up/day-of/follow-up windows
//    - User observance profile (preferences, denomination, muted holidays)
//    - User church status (linked or not)
//    - Church events nearby
//    - User interaction history (dismissals, engagement)
//    - Spiritual context from Berean / PSG
//    - App surface being rendered
//
//  Routing outputs:
//    - Which banner state to display
//    - Whether to augment Discover
//    - Whether Berean should bias toward holiday framing
//    - Whether to show Find a Church entry points
//    - Whether to show church service reminders
//    - Whether to show a human connection reminder
//    - Whether to suggest Church Notes templates
//
//  Priority rules:
//    1. Crisis / human support safety always wins
//    2. Major holiday exact day wins over generic seasonal content
//    3. User-linked church local event beats generic app holiday prompt
//    4. Discover can hold multiple seasonal cards, banner should remain concise
//    5. Do not over-trigger if the user dismissed repeatedly
//    6. Blend, do not overwhelm
//

import Foundation
import Combine
import FirebaseAuth

// MARK: - App Surface

/// Every surface that can display seasonal content.
enum SeasonalSurface: String, CaseIterable {
    case dailyVerseBanner     = "daily_verse_banner"
    case discover             = "discover"
    case bereanChat           = "berean_chat"
    case churchNotes          = "church_notes"
    case findAChurch          = "find_a_church"
    case notifications        = "notifications"
    case home                 = "home"
}

// MARK: - Banner State

/// What the daily verse banner should display.
enum SeasonalBannerState: Equatable {
    case normalVerse                           // Default daily verse
    case holidayReflection(HolidayBannerData)  // Holiday-aware verse/reflection
    case serviceReminder(ServiceReminderData)  // Church service reminder
    case guidedReflection(ReflectionData)      // "Take a quiet moment..."
}

struct HolidayBannerData: Equatable {
    let holidayName: String
    let title: String
    let subtitle: String
    let scriptureReference: String
    let ctaLabel: String
    let ctaDeepLink: String
}

struct ServiceReminderData: Equatable {
    let holidayName: String
    let title: String
    let subtitle: String
    let ctaLabel: String
    let ctaDeepLink: String
}

struct ReflectionData: Equatable {
    let seasonName: String
    let title: String
    let prompt: String
    let ctaLabel: String
    let ctaDeepLink: String
}

// MARK: - Discover Module

/// A seasonal card for the Discover screen.
struct SeasonalDiscoverModule: Identifiable, Equatable {
    let id: String
    let moduleType: ModuleType
    let title: String
    let subtitle: String
    let iconName: String
    let ctaLabel: String
    let ctaDeepLink: String
    let priority: Int

    enum ModuleType: String, Equatable {
        case holidaySpotlight     = "holiday_spotlight"
        case nearbyServices       = "nearby_services"
        case seasonExplainer      = "season_explainer"
        case guidedReflection     = "guided_reflection"
        case churchRecommendation = "church_recommendation"
        case firstTimeVisitHelp   = "first_time_visit"
        case inviteFriend         = "invite_friend"
        case holidayPrayerPrompt  = "holiday_prayer"
        case askBerean            = "ask_berean"
    }
}

// MARK: - Routing Decision

/// The complete routing output for a given surface.
struct SeasonalRoutingDecision {
    let surface: SeasonalSurface
    let shouldShowSeasonalContent: Bool
    let bannerState: SeasonalBannerState?
    let discoverModules: [SeasonalDiscoverModule]
    let bereanPromptInjection: String?
    let churchNotesTemplate: ChurchNotesTemplateData?
    let findAChurchBoost: FindAChurchBoostData?
    let humanConnectionReminder: Bool
    let suppressReason: String?
}

struct ChurchNotesTemplateData: Equatable {
    let seasonName: String
    let templateTitle: String
    let prompts: [String]
}

struct FindAChurchBoostData: Equatable {
    let reason: String
    let holidayName: String?
    let eventTypes: [String]
    let isFirstTimeFriendlyPriority: Bool
}

// MARK: - Dismissal Tracking

/// Tracks how many times a user has dismissed seasonal content.
struct SeasonalDismissal: Codable {
    let holidayType: String
    var dismissCount: Int
    var lastDismissedAt: Date
}

// MARK: - Holiday Intelligence Router

@MainActor
final class HolidayIntelligenceRouter: ObservableObject {

    static let shared = HolidayIntelligenceRouter()

    @Published private(set) var currentBannerState: SeasonalBannerState = .normalVerse
    @Published private(set) var currentDiscoverModules: [SeasonalDiscoverModule] = []
    @Published private(set) var showHumanConnectionReminder: Bool = false

    private let calendar = LiturgicalCalendarEngine.shared
    private let dismissalKey = "seasonal_dismissals_v1"
    private var dismissals: [String: SeasonalDismissal] = [:]

    private init() {
        loadDismissals()
    }

    // MARK: - Route for Surface

    /// Main routing function. Call for each surface to get the decision.
    func route(
        for surface: SeasonalSurface,
        userHasLinkedChurch: Bool = false,
        userChurchHasEvents: Bool = false,
        userIsIsolated: Bool = false,
        userDenomination: DenominationProfile = .nonDenominational
    ) -> SeasonalRoutingDecision {
        let state = calendar.currentState()

        // Check if seasonal content should be suppressed
        if let suppressReason = shouldSuppress(state: state, surface: surface) {
            return SeasonalRoutingDecision(
                surface: surface,
                shouldShowSeasonalContent: false,
                bannerState: .normalVerse,
                discoverModules: [],
                bereanPromptInjection: nil,
                churchNotesTemplate: nil,
                findAChurchBoost: nil,
                humanConnectionReminder: false,
                suppressReason: suppressReason
            )
        }

        switch surface {
        case .dailyVerseBanner:
            return routeBanner(state: state, userHasLinkedChurch: userHasLinkedChurch, userChurchHasEvents: userChurchHasEvents)
        case .discover:
            return routeDiscover(state: state, userHasLinkedChurch: userHasLinkedChurch, userIsIsolated: userIsIsolated)
        case .bereanChat:
            return routeBerean(state: state)
        case .churchNotes:
            return routeChurchNotes(state: state)
        case .findAChurch:
            return routeFindAChurch(state: state, userHasLinkedChurch: userHasLinkedChurch)
        case .notifications:
            return routeNotifications(state: state)
        case .home:
            return routeHome(state: state, userHasLinkedChurch: userHasLinkedChurch, userIsIsolated: userIsIsolated)
        }
    }

    /// Refreshes all surface routing decisions.
    func refreshAll(
        userHasLinkedChurch: Bool = false,
        userChurchHasEvents: Bool = false,
        userIsIsolated: Bool = false
    ) {
        let bannerDecision = route(for: .dailyVerseBanner, userHasLinkedChurch: userHasLinkedChurch, userChurchHasEvents: userChurchHasEvents)
        currentBannerState = bannerDecision.bannerState ?? .normalVerse

        let discoverDecision = route(for: .discover, userHasLinkedChurch: userHasLinkedChurch, userIsIsolated: userIsIsolated)
        currentDiscoverModules = discoverDecision.discoverModules

        showHumanConnectionReminder = discoverDecision.humanConnectionReminder
    }

    // MARK: - Surface-Specific Routing

    private func routeBanner(state: LiturgicalState, userHasLinkedChurch: Bool, userChurchHasEvents: Bool) -> SeasonalRoutingDecision {
        var bannerState: SeasonalBannerState = .normalVerse

        // Priority 1: Day-of a major holiday
        if let dayOf = state.activeObservances.first(where: { $0.window == .dayOf }) {
            bannerState = .holidayReflection(HolidayBannerData(
                holidayName: dayOf.name,
                title: dayOf.name,
                subtitle: dayOf.summary,
                scriptureReference: dayOf.scriptureReferences.first ?? "",
                ctaLabel: "Reflect with Berean",
                ctaDeepLink: "amen://berean?season=\(dayOf.type.rawValue)"
            ))
        }
        // Priority 2: Church has events and it's lead-up
        else if userChurchHasEvents, let leadUp = state.activeObservances.first(where: { $0.window == .leadUp && $0.priorityWeight >= 7 }) {
            bannerState = .serviceReminder(ServiceReminderData(
                holidayName: leadUp.name,
                title: "\(leadUp.name) is coming",
                subtitle: "Your church has special services",
                ctaLabel: "See Services",
                ctaDeepLink: "amen://find-church?holiday=\(leadUp.type.rawValue)"
            ))
        }
        // Priority 3: High-priority season lead-up
        else if let leadUp = state.activeObservances.first(where: { $0.window == .leadUp && $0.priorityWeight >= 8 }) {
            bannerState = .guidedReflection(ReflectionData(
                seasonName: state.seasonDisplayName,
                title: "Prepare for \(leadUp.name)",
                prompt: leadUp.summary,
                ctaLabel: "Start Reflection",
                ctaDeepLink: "amen://berean?season=\(leadUp.type.rawValue)"
            ))
        }
        // Priority 4: High-priority season in general
        else if state.isHighPrioritySeason {
            bannerState = .holidayReflection(HolidayBannerData(
                holidayName: state.seasonDisplayName,
                title: state.seasonDisplayName,
                subtitle: state.currentSeason.shortDescription,
                scriptureReference: "",
                ctaLabel: "Reflect",
                ctaDeepLink: "amen://berean?season=\(state.currentSeason.rawValue)"
            ))
        }

        return SeasonalRoutingDecision(
            surface: .dailyVerseBanner,
            shouldShowSeasonalContent: bannerState != .normalVerse,
            bannerState: bannerState,
            discoverModules: [],
            bereanPromptInjection: nil,
            churchNotesTemplate: nil,
            findAChurchBoost: nil,
            humanConnectionReminder: false,
            suppressReason: nil
        )
    }

    private func routeDiscover(state: LiturgicalState, userHasLinkedChurch: Bool, userIsIsolated: Bool) -> SeasonalRoutingDecision {
        var modules: [SeasonalDiscoverModule] = []

        // Holiday spotlight
        if let active = state.activeObservances.sorted(by: { $0.priorityWeight > $1.priorityWeight }).first {
            modules.append(SeasonalDiscoverModule(
                id: "spotlight_\(active.type.rawValue)",
                moduleType: .holidaySpotlight,
                title: active.name,
                subtitle: active.summary,
                iconName: "sparkles",
                ctaLabel: "Explore",
                ctaDeepLink: "amen://berean?season=\(active.type.rawValue)",
                priority: active.priorityWeight
            ))
        }

        // Nearby services (if high-priority holiday approaching)
        if let upcoming = state.upcomingObservances.first(where: { $0.priorityWeight >= 7 && $0.daysUntil <= 7 }) {
            modules.append(SeasonalDiscoverModule(
                id: "services_\(upcoming.type.rawValue)",
                moduleType: .nearbyServices,
                title: "\(upcoming.name) Services Near You",
                subtitle: "\(upcoming.daysUntil) days away",
                iconName: "mappin.circle.fill",
                ctaLabel: "Find Services",
                ctaDeepLink: "amen://find-church?holiday=\(upcoming.type.rawValue)",
                priority: upcoming.priorityWeight
            ))
        }

        // Season explainer (during high-priority seasons)
        if state.isHighPrioritySeason {
            modules.append(SeasonalDiscoverModule(
                id: "explainer_\(state.currentSeason.rawValue)",
                moduleType: .seasonExplainer,
                title: "What is \(state.seasonDisplayName)?",
                subtitle: state.currentSeason.shortDescription,
                iconName: "book.fill",
                ctaLabel: "Learn More",
                ctaDeepLink: "amen://berean?explain=\(state.currentSeason.rawValue)",
                priority: 5
            ))
        }

        // Ask Berean seasonal
        if state.isHighPrioritySeason || !state.activeObservances.isEmpty {
            modules.append(SeasonalDiscoverModule(
                id: "berean_seasonal",
                moduleType: .askBerean,
                title: "Ask Berean about \(state.seasonDisplayName)",
                subtitle: "Get a personalized seasonal reflection",
                iconName: "sparkles",
                ctaLabel: "Ask Now",
                ctaDeepLink: "amen://berean?season=\(state.currentSeason.rawValue)",
                priority: 4
            ))
        }

        // First-time visit help (for Easter/Christmas if user has no church)
        if !userHasLinkedChurch {
            if let major = state.activeObservances.first(where: { ($0.type == .easter || $0.type == .christmas) && $0.window != .none }) {
                modules.append(SeasonalDiscoverModule(
                    id: "firstvisit_\(major.type.rawValue)",
                    moduleType: .firstTimeVisitHelp,
                    title: "What to Expect at Church This \(major.name)",
                    subtitle: "First time? We'll help you prepare.",
                    iconName: "person.crop.circle.badge.checkmark",
                    ctaLabel: "Get Ready",
                    ctaDeepLink: "amen://berean?firstvisit=\(major.type.rawValue)",
                    priority: 8
                ))
            }
        }

        // Human connection reminder for isolated users during holidays
        let needsHumanReminder = userIsIsolated && state.isHighPrioritySeason

        return SeasonalRoutingDecision(
            surface: .discover,
            shouldShowSeasonalContent: !modules.isEmpty,
            bannerState: nil,
            discoverModules: modules.sorted { $0.priority > $1.priority },
            bereanPromptInjection: nil,
            churchNotesTemplate: nil,
            findAChurchBoost: nil,
            humanConnectionReminder: needsHumanReminder,
            suppressReason: nil
        )
    }

    private func routeBerean(state: LiturgicalState) -> SeasonalRoutingDecision {
        let prompt = state.toBereanSystemPrompt()

        return SeasonalRoutingDecision(
            surface: .bereanChat,
            shouldShowSeasonalContent: state.isHighPrioritySeason || !state.activeObservances.isEmpty,
            bannerState: nil,
            discoverModules: [],
            bereanPromptInjection: prompt,
            churchNotesTemplate: nil,
            findAChurchBoost: nil,
            humanConnectionReminder: false,
            suppressReason: nil
        )
    }

    private func routeChurchNotes(state: LiturgicalState) -> SeasonalRoutingDecision {
        guard state.isHighPrioritySeason else {
            return SeasonalRoutingDecision(
                surface: .churchNotes,
                shouldShowSeasonalContent: false,
                bannerState: nil,
                discoverModules: [],
                bereanPromptInjection: nil,
                churchNotesTemplate: nil,
                findAChurchBoost: nil,
                humanConnectionReminder: false,
                suppressReason: nil
            )
        }

        let template = SeasonalPromptService.shared.churchNotesTemplate(for: state.currentSeason)

        return SeasonalRoutingDecision(
            surface: .churchNotes,
            shouldShowSeasonalContent: template != nil,
            bannerState: nil,
            discoverModules: [],
            bereanPromptInjection: nil,
            churchNotesTemplate: template,
            findAChurchBoost: nil,
            humanConnectionReminder: false,
            suppressReason: nil
        )
    }

    private func routeFindAChurch(state: LiturgicalState, userHasLinkedChurch: Bool) -> SeasonalRoutingDecision {
        var boost: FindAChurchBoostData?

        // Boost Find a Church during major holidays
        if let active = state.activeObservances.first(where: { $0.priorityWeight >= 7 }) {
            let eventTypes: [String]
            switch active.type {
            case .easter:
                eventTypes = ["Easter Sunday Service", "Sunrise Service", "Family Service", "Baptism"]
            case .christmas, .christmasEve:
                eventTypes = ["Christmas Eve Service", "Candlelight Service", "Family Service", "Christmas Day Service"]
            case .goodFriday:
                eventTypes = ["Good Friday Service", "Prayer Vigil"]
            case .pentecost:
                eventTypes = ["Prayer Night", "Worship Night", "Revival Service"]
            case .ashWednesday:
                eventTypes = ["Ash Wednesday Service"]
            default:
                eventTypes = ["Special Service", "Holiday Service"]
            }

            boost = FindAChurchBoostData(
                reason: "\(active.name) is \(active.window == .dayOf ? "today" : "approaching")",
                holidayName: active.name,
                eventTypes: eventTypes,
                isFirstTimeFriendlyPriority: !userHasLinkedChurch
            )
        }

        return SeasonalRoutingDecision(
            surface: .findAChurch,
            shouldShowSeasonalContent: boost != nil,
            bannerState: nil,
            discoverModules: [],
            bereanPromptInjection: nil,
            churchNotesTemplate: nil,
            findAChurchBoost: boost,
            humanConnectionReminder: false,
            suppressReason: nil
        )
    }

    private func routeNotifications(state: LiturgicalState) -> SeasonalRoutingDecision {
        // Notifications are handled by SeasonalPromptService
        return SeasonalRoutingDecision(
            surface: .notifications,
            shouldShowSeasonalContent: state.isHighPrioritySeason || !state.activeObservances.isEmpty,
            bannerState: nil,
            discoverModules: [],
            bereanPromptInjection: nil,
            churchNotesTemplate: nil,
            findAChurchBoost: nil,
            humanConnectionReminder: false,
            suppressReason: nil
        )
    }

    private func routeHome(state: LiturgicalState, userHasLinkedChurch: Bool, userIsIsolated: Bool) -> SeasonalRoutingDecision {
        // Home combines banner + discover hints
        let bannerDecision = routeBanner(state: state, userHasLinkedChurch: userHasLinkedChurch, userChurchHasEvents: false)
        let needsHumanReminder = userIsIsolated && state.isHighPrioritySeason

        return SeasonalRoutingDecision(
            surface: .home,
            shouldShowSeasonalContent: bannerDecision.shouldShowSeasonalContent,
            bannerState: bannerDecision.bannerState,
            discoverModules: [],
            bereanPromptInjection: nil,
            churchNotesTemplate: nil,
            findAChurchBoost: nil,
            humanConnectionReminder: needsHumanReminder,
            suppressReason: nil
        )
    }

    // MARK: - Suppression Logic

    private func shouldSuppress(state: LiturgicalState, surface: SeasonalSurface) -> String? {
        // Never suppress Berean's seasonal awareness
        if surface == .bereanChat { return nil }

        // Check if user has dismissed this holiday too many times
        for obs in state.activeObservances {
            if let dismissal = dismissals[obs.type.rawValue], dismissal.dismissCount >= 3 {
                return "User dismissed \(obs.name) content \(dismissal.dismissCount) times"
            }
        }

        return nil
    }

    // MARK: - Dismissal Tracking

    /// Records that the user dismissed seasonal content for a holiday.
    func recordDismissal(for holidayType: HolidayType) {
        let key = holidayType.rawValue
        if var existing = dismissals[key] {
            existing.dismissCount += 1
            existing.lastDismissedAt = Date()
            dismissals[key] = existing
        } else {
            dismissals[key] = SeasonalDismissal(
                holidayType: key,
                dismissCount: 1,
                lastDismissedAt: Date()
            )
        }
        saveDismissals()
    }

    /// Resets dismissal counts (call at start of each new season).
    func resetDismissals() {
        dismissals.removeAll()
        saveDismissals()
    }

    // MARK: - Dismissal Persistence

    private func loadDismissals() {
        guard let data = UserDefaults.standard.data(forKey: dismissalKey),
              let decoded = try? JSONDecoder().decode([String: SeasonalDismissal].self, from: data) else {
            return
        }
        dismissals = decoded
    }

    private func saveDismissals() {
        guard let data = try? JSONEncoder().encode(dismissals) else { return }
        UserDefaults.standard.set(data, forKey: dismissalKey)
    }
}
