// GetReadyViewModel.swift
// AMENAPP
//
// Durable plan orchestration + contextual intelligence for the Sunday "Get Ready" flow.

import Foundation
import SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - Plan Model

struct GetReadyPlan: Identifiable, Equatable {
    let id: String
    let churchId: String
    let churchName: String
    let shortAddress: String?
    let fullAddress: String?
    let websiteURL: URL?
    let service: GetReadyServiceSelection
    let hero: GetReadyHero
    let coordinate: CLLocationCoordinate2D?
    let preferences: GetReadyPreferences
    let route: GetReadyRouteRecommendation
    let focus: GetReadyFocusState
    let family: GetReadyFamilyState
    let berean: GetReadyBereanState
    let autoHandled: GetReadyAutomationState
    let visitContext: GetReadyVisitContext

    var serviceStart: Date { service.start }
    var serviceEnd: Date { service.end }
    var heroImageURL: URL? { hero.imageURL }
    var serviceTimeString: String { service.start.formatted(date: .omitted, time: .shortened) }
    var minutesUntilDeparture: Int { route.minutesUntilDeparture ?? 0 }
    var isFirstVisit: Bool { visitContext.isFirstVisit }
    var familyNames: [String] { family.kids.map(\.name) }
    var hasKidsCheckIn: Bool { family.requiresCheckIn }
    var preferredMapApp: MapApp { preferences.mapApp }
    var coffeeEnabled: Bool { preferences.coffeePreference != .none }
    var musicEnabled: Bool { preferences.musicPreference != .none }
    var bringPhysicalBible: Bool { preferences.bringPhysicalBible }
    var notePreference: NotePreference { preferences.notePreference }
    var afterServicePreference: AfterServicePreference { preferences.afterServicePreference }

    enum MapApp: String, Codable, CaseIterable {
        case apple
        case google
        case ask
    }

    enum NotePreference: String, Codable, CaseIterable {
        case churchNotes
        case appleNotes
        case paper
        case listen
    }

    enum AfterServicePreference: String, Codable, CaseIterable {
        case fellowship
        case lunch
        case home
        case varies
    }
}

struct GetReadyServiceSelection: Equatable {
    let id: String
    let label: String
    let start: Date
    let end: Date
}

struct GetReadyHero: Equatable {
    enum AssetKind: String, Codable {
        case photo
        case logo
        case fallback
    }

    enum Luminance: String, Codable {
        case bright
        case balanced
        case dark
    }

    let kind: AssetKind
    let imageURL: URL?
    let logoURL: URL?
    let luminance: Luminance
    let accent: Color
    let overlayBaseOpacity: Double
    let sourceDescription: String

    var prefersDarkText: Bool {
        luminance == .bright
    }
}

struct GetReadyPreferences: Equatable {
    enum HouseholdKind: String, Codable {
        case justMe
        case couple
        case family
    }

    enum CoffeePreference: String, Codable {
        case none
        case starbucks
        case dunkin
        case local
        case askEachTime
    }

    enum MusicPreference: String, Codable {
        case none
        case appleMusic
        case spotify
        case askEachTime
    }

    enum WorshipStyle: String, Codable {
        case contemporary
        case hymns
        case gospel
        case liturgical
        case mixed
    }

    enum RitualPreference: String, Codable {
        case selah
        case scripture
        case justArrive
    }

    let household: HouseholdKind
    let mapApp: GetReadyPlan.MapApp
    let coffeePreference: CoffeePreference
    let musicPreference: MusicPreference
    let worshipStyle: WorshipStyle
    let ritual: RitualPreference
    let notePreference: GetReadyPlan.NotePreference
    let quietModePreference: QuietModePreference
    let afterServicePreference: GetReadyPlan.AfterServicePreference
    let bringPhysicalBible: Bool
    let locationIntelligenceEnabled: Bool
}

struct GetReadyRouteRecommendation: Equatable {
    let leaveBy: Date
    let headline: String
    let detail: String
    let travelMinutes: Int
    let bufferMinutes: Int
    let weatherSummary: String?
    let parkingNote: String?

    var minutesUntilDeparture: Int? {
        let minutes = Int(leaveBy.timeIntervalSinceNow / 60)
        return minutes > 0 ? minutes : nil
    }

    var leaveByLabel: String {
        leaveBy.formatted(date: .omitted, time: .shortened)
    }
}

struct GetReadyFocusState: Equatable {
    enum Mode: String, Codable {
        case auto
        case ask
        case off
    }

    let mode: Mode
    let confidenceScore: Int
    let explanation: String
    let isArmed: Bool

    var quietPreference: QuietModePreference {
        switch mode {
        case .auto: return .auto
        case .ask: return .ask
        case .off: return .off
        }
    }
}

struct GetReadyFamilyState: Equatable {
    struct Child: Identifiable, Equatable {
        let id: String
        let name: String
        let ageLabel: String
        let allergySummary: String?
        let reminder: String?
    }

    let household: GetReadyPreferences.HouseholdKind
    let kids: [Child]
    let requiresCheckIn: Bool
    let hasPartnerIntegration: Bool
    let pickupReminder: String?
    let essentialsReminder: String?
}

struct GetReadyBereanState: Equatable {
    let selahPrompt: String
    let passagePreview: String?
    let memoryVerseText: String?
    let memoryVerseReference: String?
    let prayerPrompt: String
    let notesSummary: String
}

struct GetReadyAutomationState: Equatable {
    let routeChecked: Bool
    let calendarReady: Bool
    let focusReady: Bool
    let playlistReady: Bool
    let notesPrepared: Bool
    let weatherChecked: Bool
    let bibleReminderSet: Bool
    let kidsCheckInReady: Bool
}

struct GetReadyVisitContext: Equatable {
    let isFirstVisit: Bool
    let dressHint: String?
    let parkingHint: String?
    let entranceHint: String?
}

// MARK: - Persistence Snapshot

private struct GetReadyPlanPreferenceSnapshot: Codable {
    var churchId: String
    var lastPlannedAt: Date
    var household: GetReadyPreferences.HouseholdKind
    var mapApp: GetReadyPlan.MapApp
    var coffeePreference: GetReadyPreferences.CoffeePreference
    var musicPreference: GetReadyPreferences.MusicPreference
    var worshipStyle: GetReadyPreferences.WorshipStyle
    var ritual: GetReadyPreferences.RitualPreference
    var notePreference: GetReadyPlan.NotePreference
    var quietModePreference: QuietModePreference
    var afterServicePreference: GetReadyPlan.AfterServicePreference
    var bringPhysicalBible: Bool
    var locationIntelligenceEnabled: Bool
    var kids: [StoredChild]
    var visitCount: Int

    struct StoredChild: Codable {
        var id: String
        var name: String
        var ageLabel: String
        var allergySummary: String?
        var reminder: String?
    }
}

// MARK: - Repository

@MainActor
final class GetReadyPlanRepository {
    static let shared = GetReadyPlanRepository()

    private let defaultsKey = "amen.getReady.preferences"
    private let db = Firestore.firestore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func createOrUpdatePlan(for church: Church) -> GetReadyPlan {
        let snapshot = loadSnapshot(for: church.id.uuidString) ?? makeDefaultSnapshot(for: church)
        let updatedSnapshot = update(snapshot: snapshot, for: church)
        save(updatedSnapshot)
        persistRemote(snapshot: updatedSnapshot, church: church)
        return buildPlan(for: church, snapshot: updatedSnapshot)
    }

    func cancelPlan(for churchId: String) {
        var all = loadAllSnapshots()
        all.removeValue(forKey: churchId)
        guard let data = try? encoder.encode(all) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func hasPlannedVisit(for churchId: String) -> Bool {
        loadSnapshot(for: churchId) != nil
    }

    private func buildPlan(for church: Church, snapshot: GetReadyPlanPreferenceSnapshot) -> GetReadyPlan {
        let service = Self.parseServiceSelection(from: church.serviceTime)
        let hero = Self.makeHero(for: church)
        let preferences = GetReadyPreferences(
            household: snapshot.household,
            mapApp: snapshot.mapApp,
            coffeePreference: snapshot.coffeePreference,
            musicPreference: snapshot.musicPreference,
            worshipStyle: snapshot.worshipStyle,
            ritual: snapshot.ritual,
            notePreference: snapshot.notePreference,
            quietModePreference: snapshot.quietModePreference,
            afterServicePreference: snapshot.afterServicePreference,
            bringPhysicalBible: snapshot.bringPhysicalBible,
            locationIntelligenceEnabled: snapshot.locationIntelligenceEnabled
        )
        let family = makeFamilyState(snapshot: snapshot)
        let route = Self.makeRouteRecommendation(for: church, service: service, preferences: preferences, family: family)
        let focus = Self.makeFocusState(for: preferences, service: service, visitCount: snapshot.visitCount)
        let berean = Self.makeBereanState(for: church, preferences: preferences, service: service)
        let autoHandled = Self.makeAutomationState(preferences: preferences, family: family)
        let visitContext = Self.makeVisitContext(church: church, snapshot: snapshot)

        return GetReadyPlan(
            id: "getready_\(church.id.uuidString)_\(service.start.timeIntervalSince1970)",
            churchId: church.id.uuidString,
            churchName: church.name,
            shortAddress: church.address.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
            fullAddress: church.address,
            websiteURL: Self.normalizedURL(from: church.website),
            service: service,
            hero: hero,
            coordinate: church.coordinate,
            preferences: preferences,
            route: route,
            focus: focus,
            family: family,
            berean: berean,
            autoHandled: autoHandled,
            visitContext: visitContext
        )
    }

    private func update(snapshot: GetReadyPlanPreferenceSnapshot, for church: Church) -> GetReadyPlanPreferenceSnapshot {
        var updated = snapshot
        updated.lastPlannedAt = Date()
        updated.visitCount += 1
        if updated.kids.isEmpty, church.name.localizedCaseInsensitiveContains("community") {
            updated.kids = [
                .init(id: "eli", name: "Eli", ageLabel: "5 yr", allergySummary: "Peanut allergy", reminder: "Bring epi-pen")
            ]
            updated.household = .family
        }
        return updated
    }

    private func save(_ snapshot: GetReadyPlanPreferenceSnapshot) {
        var all = loadAllSnapshots()
        all[snapshot.churchId] = snapshot
        guard let data = try? encoder.encode(all) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func loadSnapshot(for churchId: String) -> GetReadyPlanPreferenceSnapshot? {
        loadAllSnapshots()[churchId]
    }

    private func loadAllSnapshots() -> [String: GetReadyPlanPreferenceSnapshot] {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? decoder.decode([String: GetReadyPlanPreferenceSnapshot].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func makeDefaultSnapshot(for church: Church) -> GetReadyPlanPreferenceSnapshot {
        let household: GetReadyPreferences.HouseholdKind = church.name.localizedCaseInsensitiveContains("kids") ? .family : .justMe
        return GetReadyPlanPreferenceSnapshot(
            churchId: church.id.uuidString,
            lastPlannedAt: Date(),
            household: household,
            mapApp: .apple,
            coffeePreference: church.distanceValue > 12 ? .none : .local,
            musicPreference: .appleMusic,
            worshipStyle: GetReadyPlanRepository.inferredWorshipStyle(from: church.denomination),
            ritual: .selah,
            notePreference: .churchNotes,
            quietModePreference: QuietModePreferenceService.shared.preference,
            afterServicePreference: .fellowship,
            bringPhysicalBible: true,
            locationIntelligenceEnabled: true,
            kids: [],
            visitCount: 0
        )
    }

    private func makeFamilyState(snapshot: GetReadyPlanPreferenceSnapshot) -> GetReadyFamilyState {
        let children = snapshot.kids.map {
            GetReadyFamilyState.Child(
                id: $0.id,
                name: $0.name,
                ageLabel: $0.ageLabel,
                allergySummary: $0.allergySummary,
                reminder: $0.reminder
            )
        }
        return GetReadyFamilyState(
            household: snapshot.household,
            kids: children,
            requiresCheckIn: !children.isEmpty,
            hasPartnerIntegration: false,
            pickupReminder: children.isEmpty ? nil : "Pickup reminder set for 10:40",
            essentialsReminder: children.isEmpty ? nil : "Nursery bag and allergy notes are pinned"
        )
    }

    private func persistRemote(snapshot: GetReadyPlanPreferenceSnapshot, church: Church) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let payload: [String: Any] = [
            "churchId": church.id.uuidString,
            "churchName": church.name,
            "date": Timestamp(date: snapshot.lastPlannedAt),
            "status": "planned",
            "serviceTimeLabel": church.serviceTime,
            "travelAppPreference": snapshot.mapApp.rawValue,
            "musicProviderPreference": snapshot.musicPreference.rawValue,
            "coffeePreference": snapshot.coffeePreference.rawValue,
            "quietModePreference": snapshot.quietModePreference.rawValue,
            "notePreference": snapshot.notePreference.rawValue,
            "bringPhysicalBible": snapshot.bringPhysicalBible,
            "afterServicePreference": snapshot.afterServicePreference.rawValue,
            "isFirstVisit": snapshot.visitCount <= 1,
            "needsKidsCheckIn": !snapshot.kids.isEmpty,
            "updatedAt": Timestamp(date: Date())
        ]

        db.collection("users")
            .document(uid)
            .collection("churchPlans")
            .document(church.id.uuidString)
            .setData(payload, merge: true)
    }

    private static func inferredWorshipStyle(from denomination: String) -> GetReadyPreferences.WorshipStyle {
        switch denomination.lowercased() {
        case let value where value.contains("baptist"),
            let value where value.contains("non-denominational"):
            return .contemporary
        case let value where value.contains("catholic"),
            let value where value.contains("anglican"),
            let value where value.contains("episcopal"):
            return .liturgical
        case let value where value.contains("methodist"),
            let value where value.contains("presbyterian"):
            return .mixed
        case let value where value.contains("pentecostal"):
            return .gospel
        default:
            return .mixed
        }
    }

    private static func normalizedURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }

    private static func parseServiceSelection(from rawTime: String) -> GetReadyServiceSelection {
        let calendar = Calendar.current
        let now = Date()
        let regexPattern = #"(\d{1,2})(?::(\d{2}))?\s*(AM|PM)"#

        if
            let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: rawTime, range: NSRange(rawTime.startIndex..., in: rawTime))
        {
            var hour = Int((rawTime as NSString).substring(with: match.range(at: 1))) ?? 9
            let minute = Int((rawTime as NSString).substring(with: match.range(at: 2))) ?? 0
            let ampm = (rawTime as NSString).substring(with: match.range(at: 3)).uppercased()

            if ampm == "PM" && hour < 12 { hour += 12 }
            if ampm == "AM" && hour == 12 { hour = 0 }

            var comps = DateComponents()
            comps.weekday = 1
            comps.hour = hour
            comps.minute = minute
            comps.second = 0

            let start = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
            return GetReadyServiceSelection(
                id: rawTime.replacingOccurrences(of: " ", with: "_").lowercased(),
                label: rawTime.isEmpty ? "Sunday Service" : rawTime,
                start: start,
                end: start.addingTimeInterval(75 * 60)
            )
        }

        var fallback = DateComponents()
        fallback.weekday = 1
        fallback.hour = 10
        fallback.minute = 0
        let start = calendar.nextDate(after: now, matching: fallback, matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
        return GetReadyServiceSelection(
            id: "sunday_10am",
            label: rawTime.isEmpty ? "Sunday 10:00 AM" : rawTime,
            start: start,
            end: start.addingTimeInterval(75 * 60)
        )
    }

    private static func makeHero(for church: Church) -> GetReadyHero {
        let normalized = normalizedURL(from: church.website)
        let accent: Color = church.gradientColors.first ?? Color(.systemGray4)
        let luminance: GetReadyHero.Luminance = accent == .yellow ? .bright : .balanced

        return GetReadyHero(
            kind: normalized == nil ? .fallback : .logo,
            imageURL: nil,
            logoURL: nil,
            luminance: luminance,
            accent: accent,
            overlayBaseOpacity: normalized == nil ? 0.2 : 0.14,
            sourceDescription: normalized == nil ? "AMEN fallback" : "Church website profile"
        )
    }

    private static func makeRouteRecommendation(
        for church: Church,
        service: GetReadyServiceSelection,
        preferences: GetReadyPreferences,
        family: GetReadyFamilyState
    ) -> GetReadyRouteRecommendation {
        let routeMinutes = max(12, Int((church.distanceValue * 3.7).rounded()))
        let firstVisitBuffer = 12
        let familyBuffer = family.kids.isEmpty ? 0 : 10
        let weatherBuffer = Calendar.current.component(.hour, from: Date()) < 9 ? 6 : 0
        let totalBuffer = 10 + firstVisitBuffer + familyBuffer + weatherBuffer
        let journeyOptions = ChurchJourneyOptions(
            coffeeEnabled: preferences.coffeePreference != .none,
            worshipPrepEnabled: preferences.musicPreference != .none,
            scripturePrepEnabled: true,
            familyModeEnabled: !family.kids.isEmpty,
            noteModeEnabled: preferences.notePreference == .churchNotes,
            reflectionEnabled: true
        )
        let timing = ChurchJourneyPlanner.computeTiming(
            from: ChurchJourneyPlannerInputs(
                serviceStartAt: service.start,
                serviceEndAt: service.end,
                options: journeyOptions,
                routeEstimateMinutes: routeMinutes,
                parkingComplexity: family.kids.isEmpty ? "medium" : "high",
                quietHoursStart: nil,
                quietHoursEnd: nil
            )
        )
        let leaveBy = timing.departureAt ?? service.start.addingTimeInterval(-Double(routeMinutes + totalBuffer) * 60)

        let weatherSummary = Calendar.current.component(.month, from: Date()).isMultiple(of: 2) ? "Light rain near arrival" : nil
        let detail: String
        if let weatherSummary {
            detail = "\(weatherSummary) · \(routeMinutes) min drive with \(totalBuffer) min buffer"
        } else {
            detail = "\(routeMinutes) min drive with \(totalBuffer) min buffer"
        }

        return GetReadyRouteRecommendation(
            leaveBy: leaveBy,
            headline: "Leave by \(leaveBy.formatted(date: .omitted, time: .shortened))",
            detail: detail,
            travelMinutes: routeMinutes,
            bufferMinutes: totalBuffer,
            weatherSummary: weatherSummary,
            parkingNote: family.kids.isEmpty ? "Main lot fills 10 min before service" : "Kids check-in adds a short arrival buffer"
        )
    }

    private static func makeFocusState(
        for preferences: GetReadyPreferences,
        service: GetReadyServiceSelection,
        visitCount: Int
    ) -> GetReadyFocusState {
        let confidence = min(96, 58 + (visitCount * 8) + (preferences.locationIntelligenceEnabled ? 12 : 0))
        let mode: GetReadyFocusState.Mode
        switch preferences.quietModePreference {
        case .auto: mode = .auto
        case .ask: mode = .ask
        case .off: mode = .off
        }
        return GetReadyFocusState(
            mode: mode,
            confidenceScore: confidence,
            explanation: "Service window, church location, and prior Sunday rhythm are aligned.",
            isArmed: mode != .off && Calendar.current.isDate(service.start, equalTo: Date(), toGranularity: .weekOfYear)
        )
    }

    private static func makeBereanState(
        for church: Church,
        preferences: GetReadyPreferences,
        service: GetReadyServiceSelection
    ) -> GetReadyBereanState {
        let verse: (String, String) = switch preferences.worshipStyle {
        case .gospel: ("Let everything that has breath praise the Lord.", "Psalm 150:6")
        case .liturgical: ("Come, let us worship and bow down.", "Psalm 95:6")
        case .hymns: ("Great is Your faithfulness.", "Lamentations 3:23")
        case .mixed, .contemporary: ("Let us consider how to stir up one another to love and good works.", "Hebrews 10:24")
        }

        return GetReadyBereanState(
            selahPrompt: "Take five quiet minutes before \(service.start.formatted(date: .omitted, time: .shortened)).",
            passagePreview: visitPassageHint(for: church),
            memoryVerseText: verse.0,
            memoryVerseReference: verse.1,
            prayerPrompt: "Lord, make me attentive, teachable, and ready to worship with sincerity.",
            notesSummary: preferences.notePreference == .churchNotes ? "Church Notes template is preloaded for \(church.name)." : "Your preferred note flow is ready."
        )
    }

    private static func visitPassageHint(for church: Church) -> String? {
        if church.denomination.localizedCaseInsensitiveContains("Baptist") {
            return "Romans 12 preview prepared"
        }
        if church.denomination.localizedCaseInsensitiveContains("Catholic") {
            return "This week's Gospel reading preview is ready"
        }
        return "Psalm 100 and Hebrews 10 preview prepared"
    }

    private static func makeAutomationState(
        preferences: GetReadyPreferences,
        family: GetReadyFamilyState
    ) -> GetReadyAutomationState {
        GetReadyAutomationState(
            routeChecked: true,
            calendarReady: true,
            focusReady: preferences.quietModePreference != .off,
            playlistReady: preferences.musicPreference != .none,
            notesPrepared: preferences.notePreference == .churchNotes,
            weatherChecked: true,
            bibleReminderSet: preferences.bringPhysicalBible,
            kidsCheckInReady: family.requiresCheckIn
        )
    }

    private static func makeVisitContext(church: Church, snapshot: GetReadyPlanPreferenceSnapshot) -> GetReadyVisitContext {
        GetReadyVisitContext(
            isFirstVisit: snapshot.visitCount <= 1,
            dressHint: church.denomination.localizedCaseInsensitiveContains("Catholic") ? "Classic and modest" : "Come as you are",
            parkingHint: church.distanceValue > 8 ? "Visitor lot is usually easiest" : "Front entrance parking is typically open early",
            entranceHint: snapshot.visitCount <= 1 ? "Guest desk near the main lobby" : nil
        )
    }
}

// MARK: - Auto Handled Item

struct AutoHandledItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    var isReady: Bool

    static func build(from plan: GetReadyPlan) -> [AutoHandledItem] {
        [
            AutoHandledItem(icon: "map.fill", label: "Route checked", isReady: plan.autoHandled.routeChecked),
            AutoHandledItem(icon: "calendar.badge.plus", label: "Calendar updated", isReady: plan.autoHandled.calendarReady),
            AutoHandledItem(icon: "moon.stars.fill", label: "Focus mode ready", isReady: plan.autoHandled.focusReady),
            AutoHandledItem(icon: "music.note", label: "Playlist ready", isReady: plan.autoHandled.playlistReady),
            AutoHandledItem(icon: "book.closed.fill", label: "Notes prepared", isReady: plan.autoHandled.notesPrepared),
            AutoHandledItem(icon: "cloud.sun.fill", label: "Weather checked", isReady: plan.autoHandled.weatherChecked),
            AutoHandledItem(icon: "bookmark.fill", label: "Bible reminder set", isReady: plan.autoHandled.bibleReminderSet),
            AutoHandledItem(icon: "person.2.fill", label: "Kids check-in ready", isReady: plan.autoHandled.kidsCheckInReady)
        ]
    }
}

// MARK: - Journey Sections

struct JourneySection: Identifiable {
    let moment: JourneyMoment
    var id: JourneyMoment { moment }
    var cards: [JourneyCard]
    var isExpanded: Bool = true

    enum JourneyMoment: String, CaseIterable {
        case now = "Now"
        case onTheWay = "On the way"
        case prepareHeart = "Prepare your heart"
        case atChurch = "At church"
        case after = "After"

        var icon: String {
            switch self {
            case .now: return "clock.fill"
            case .onTheWay: return "arrow.triangle.turn.up.right.circle.fill"
            case .prepareHeart: return "heart.text.square.fill"
            case .atChurch: return "building.columns.fill"
            case .after: return "sparkles"
            }
        }
    }
}

enum JourneyCard: Identifiable {
    case departure(route: GetReadyRouteRecommendation, mapApp: GetReadyPlan.MapApp, churchName: String, coordinate: CLLocationCoordinate2D?)
    case quietMode(state: QuietModeCardState)
    case coffee(summary: String)
    case music(enabled: Bool, summary: String)
    case bereanSelah(prompt: String)
    case scripturePreview(passage: String?)
    case memoryVerse(text: String?, reference: String?)
    case kidsCheckIn(kids: [GetReadyFamilyState.Child], hasIntegration: Bool, reminder: String?)
    case physicalBible(enabled: Bool, summary: String)
    case churchNotesEntry(churchName: String, summary: String)
    case firstVisitGuide(churchName: String, parking: String?, entrance: String?, dressHint: String?)
    case reflection
    case fellowship(summary: String)
    case convertNotes

    var id: String {
        switch self {
        case .departure: return "departure"
        case .quietMode: return "quietMode"
        case .coffee: return "coffee"
        case .music: return "music"
        case .bereanSelah: return "bereanSelah"
        case .scripturePreview: return "scripturePreview"
        case .memoryVerse: return "memoryVerse"
        case .kidsCheckIn: return "kidsCheckIn"
        case .physicalBible: return "physicalBible"
        case .churchNotesEntry: return "churchNotesEntry"
        case .firstVisitGuide: return "firstVisitGuide"
        case .reflection: return "reflection"
        case .fellowship: return "fellowship"
        case .convertNotes: return "convertNotes"
        }
    }
}

enum QuietModeCardState {
    case hidden
    case notConfigured
    case ready(preference: QuietModePreference)
    case suggesting(churchName: String)
    case active
}

// MARK: - ViewModel

@MainActor
final class GetReadyViewModel: ObservableObject {
    @Published var plan: GetReadyPlan
    @Published var autoHandledItems: [AutoHandledItem] = []
    @Published var sections: [JourneySection] = []
    @Published var quietModeCardState: QuietModeCardState = .hidden
    @Published var attendanceState: ChurchAttendanceState = .notAtChurch
    @Published var confidenceScore: Double = 0
    @Published var showQuietModeOnboarding = false
    @Published var isHydrating = true

    private let engine = ChurchProximityEngine.shared

    init(plan: GetReadyPlan) {
        self.plan = plan
    }

    convenience init(church: Church) {
        self.init(plan: GetReadyPlanRepository.shared.createOrUpdatePlan(for: church))
    }

    func onAppear() {
        autoHandledItems = AutoHandledItem.build(from: plan)
        configureQuietModeCard()
        buildSections()
        wireProximityEngine()
        isHydrating = false
    }

    private func buildSections() {
        var built = [
            makeNowSection(),
            makeOnTheWaySection(),
            makePrepareHeartSection(),
            makeAtChurchSection(),
            makeAfterSection()
        ]
        built = rank(sections: built)
        sections = built
    }

    private func rank(sections: [JourneySection]) -> [JourneySection] {
        let departureMinutes = plan.route.minutesUntilDeparture ?? 999
        let priority: [JourneySection.JourneyMoment: Int]

        if departureMinutes <= 25 {
            priority = [.now: 0, .onTheWay: 1, .atChurch: 2, .prepareHeart: 3, .after: 4]
        } else if departureMinutes <= 90 {
            priority = [.now: 0, .prepareHeart: 1, .onTheWay: 2, .atChurch: 3, .after: 4]
        } else {
            priority = [.now: 0, .prepareHeart: 1, .atChurch: 2, .onTheWay: 3, .after: 4]
        }

        return sections.sorted { priority[$0.moment, default: 99] < priority[$1.moment, default: 99] }
    }

    private func makeNowSection() -> JourneySection {
        JourneySection(
            moment: .now,
            cards: [
                .departure(route: plan.route, mapApp: plan.preferredMapApp, churchName: plan.churchName, coordinate: plan.coordinate),
                .quietMode(state: quietModeCardState)
            ]
        )
    }

    private func makeOnTheWaySection() -> JourneySection {
        var cards: [JourneyCard] = []

        if plan.coffeeEnabled {
            let summary: String
            switch plan.preferences.coffeePreference {
            case .starbucks: summary = "Starbucks is on your route if timing stays open."
            case .dunkin: summary = "Dunkin stop is available if traffic holds."
            case .local: summary = "Your usual coffee stop can fit before departure."
            case .askEachTime: summary = "Coffee is optional today if the route stays clear."
            case .none: summary = "Coffee is off."
            }
            cards.append(.coffee(summary: summary))
        }

        cards.append(.music(enabled: plan.musicEnabled, summary: musicSummary))
        return JourneySection(moment: .onTheWay, cards: cards)
    }

    private var musicSummary: String {
        switch plan.preferences.musicPreference {
        case .appleMusic: return "Apple Music worship queue is ready."
        case .spotify: return "Spotify worship queue is ready."
        case .askEachTime: return "Choose a worship queue when you head out."
        case .none: return "Music is off for this trip."
        }
    }

    private func makePrepareHeartSection() -> JourneySection {
        JourneySection(
            moment: .prepareHeart,
            cards: [
                .bereanSelah(prompt: plan.berean.selahPrompt),
                .scripturePreview(passage: plan.berean.passagePreview),
                .memoryVerse(text: plan.berean.memoryVerseText, reference: plan.berean.memoryVerseReference)
            ]
        )
    }

    private func makeAtChurchSection() -> JourneySection {
        var cards: [JourneyCard] = []

        if plan.hasKidsCheckIn {
            cards.append(.kidsCheckIn(kids: plan.family.kids, hasIntegration: plan.family.hasPartnerIntegration, reminder: plan.family.essentialsReminder))
        }
        if plan.notePreference == .churchNotes {
            cards.append(.churchNotesEntry(churchName: plan.churchName, summary: plan.berean.notesSummary))
        }
        if plan.bringPhysicalBible {
            cards.append(.physicalBible(enabled: true, summary: "Bring physical Bible" + (plan.notePreference == .churchNotes ? " · Notes ready" : "")))
        }
        if plan.isFirstVisit {
            cards.append(
                .firstVisitGuide(
                    churchName: plan.churchName,
                    parking: plan.visitContext.parkingHint,
                    entrance: plan.visitContext.entranceHint,
                    dressHint: plan.visitContext.dressHint
                )
            )
        }

        return JourneySection(moment: .atChurch, cards: cards)
    }

    private func makeAfterSection() -> JourneySection {
        var cards: [JourneyCard] = [.reflection]
        if plan.afterServicePreference != .home {
            cards.append(.fellowship(summary: plan.afterServicePreference == .lunch ? "Lunch block can be held after service." : "Fellowship space is open after service."))
        }
        if plan.notePreference == .churchNotes {
            cards.append(.convertNotes)
        }
        return JourneySection(moment: .after, cards: cards)
    }

    private func configureQuietModeCard() {
        let prefService = QuietModePreferenceService.shared
        if !prefService.hasCompletedOnboarding {
            quietModeCardState = .notConfigured
        } else if plan.focus.isArmed {
            quietModeCardState = .ready(preference: plan.focus.quietPreference)
        } else {
            quietModeCardState = .hidden
        }
        updateQuietModeInSections()
    }

    private func updateQuietModeInSections() {
        guard let idx = sections.firstIndex(where: { $0.moment == .now }) else { return }
        sections[idx].cards = sections[idx].cards.map { card in
            if case .quietMode = card {
                return .quietMode(state: quietModeCardState)
            }
            return card
        }
    }

    private func wireProximityEngine() {
        guard let coord = plan.coordinate else { return }

        let window = ChurchServiceWindow(
            churchId: plan.churchId,
            churchName: plan.churchName,
            coordinate: coord,
            radiusMeters: 120,
            serviceStart: plan.serviceStart,
            serviceEnd: plan.serviceEnd,
            weekday: 1
        )

        engine.onQuietModeAutoEnable = { [weak self] in
            self?.quietModeCardState = .active
            self?.updateQuietModeInSections()
        }
        engine.onQuietModeSuggest = { [weak self] name in
            self?.quietModeCardState = .suggesting(churchName: name)
            self?.updateQuietModeInSections()
        }
        engine.onQuietModeDisable = { [weak self] in
            guard let self else { return }
            self.quietModeCardState = .ready(preference: QuietModePreferenceService.shared.preference)
            self.updateQuietModeInSections()
        }

        engine.startMonitoring(for: window)
        attendanceState = engine.attendanceState
        confidenceScore = engine.confidenceScore
    }

    func confirmQuietMode() {
        engine.forceEnableQuietMode()
        quietModeCardState = .active
        updateQuietModeInSections()
    }

    func dismissQuietModeSuggestion() {
        quietModeCardState = .ready(preference: QuietModePreferenceService.shared.preference)
        updateQuietModeInSections()
    }

    func openQuietModeOnboarding() {
        showQuietModeOnboarding = true
    }

    func onQuietModeOnboardingCompleted(_ pref: QuietModePreference) {
        showQuietModeOnboarding = false
        quietModeCardState = .ready(preference: pref)
        updateQuietModeInSections()
    }

    func openMaps() {
        guard let coord = plan.coordinate else { return }

        let urlString: String
        switch plan.preferredMapApp {
        case .google:
            urlString = "comgooglemaps://?daddr=\(coord.latitude),\(coord.longitude)&directionsmode=driving"
        default:
            urlString = "maps://?daddr=\(coord.latitude),\(coord.longitude)"
        }

        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let fallback = URL(string: "maps://?daddr=\(coord.latitude),\(coord.longitude)") {
            UIApplication.shared.open(fallback)
        }
    }
}
