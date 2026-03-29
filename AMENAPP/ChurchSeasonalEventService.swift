//
//  ChurchSeasonalEventService.swift
//  AMENAPP
//
//  Church Seasonal Event Service — Firestore-backed system for churches to
//  publish seasonal events (Easter services, Christmas Eve, prayer nights,
//  Lent gatherings, etc.) and for users to discover them.
//
//  Church-facing value:
//    - Seasonal event publishing (admin uploads schedule)
//    - Special service discovery (users find holiday services)
//    - First-time visitor journeys during holidays
//    - Post-service follow-up ("How was your experience?")
//    - Volunteer/service coordination for holiday weekends
//
//  User-facing value:
//    - Find holiday-specific services nearby
//    - "What to expect" for first-time visitors
//    - Save to calendar, get directions, invite a friend
//    - Family-friendly service filters
//    - Livestream availability
//
//  Firestore schema:
//    churchSeasonalEvents/{eventId}
//      - churchId, title, eventType, startDateTime, endDateTime
//      - holidayTags, isFirstTimeFriendly, hasKidsProgram
//      - hasLivestream, location, parkingInfo, whatToExpect
//      - audienceTags, displayPriority
//
//  Privacy: Event data is public (church-published). No user data involved.
//

import Foundation
import Combine
import FirebaseFirestore
import CoreLocation

// MARK: - Church Event Type

enum ChurchEventType: String, Codable, CaseIterable {
    case sundayService        = "sunday_service"
    case specialService       = "special_service"
    case candlelightService   = "candlelight_service"
    case sunriseService       = "sunrise_service"
    case prayerNight          = "prayer_night"
    case worshipNight         = "worship_night"
    case revivalService       = "revival_service"
    case youthEvent           = "youth_event"
    case familyEvent          = "family_event"
    case communityOutreach    = "community_outreach"
    case bibleStudy           = "bible_study"
    case smallGroup           = "small_group"
    case baptismService       = "baptism_service"
    case conference           = "conference"
    case fastingPrayer        = "fasting_prayer"
    case ashWednesdayService  = "ash_wednesday_service"

    var displayName: String {
        switch self {
        case .sundayService:       return "Sunday Service"
        case .specialService:      return "Special Service"
        case .candlelightService:  return "Candlelight Service"
        case .sunriseService:      return "Sunrise Service"
        case .prayerNight:         return "Prayer Night"
        case .worshipNight:        return "Worship Night"
        case .revivalService:      return "Revival Service"
        case .youthEvent:          return "Youth Event"
        case .familyEvent:         return "Family Event"
        case .communityOutreach:   return "Community Outreach"
        case .bibleStudy:          return "Bible Study"
        case .smallGroup:          return "Small Group"
        case .baptismService:      return "Baptism Service"
        case .conference:          return "Conference"
        case .fastingPrayer:       return "Fasting & Prayer"
        case .ashWednesdayService: return "Ash Wednesday Service"
        }
    }

    var icon: String {
        switch self {
        case .sundayService:       return "building.columns.fill"
        case .specialService:      return "sparkles"
        case .candlelightService:  return "flame.fill"
        case .sunriseService:      return "sunrise.fill"
        case .prayerNight:         return "hands.sparkles.fill"
        case .worshipNight:        return "music.note"
        case .revivalService:      return "flame.fill"
        case .youthEvent:          return "person.3.fill"
        case .familyEvent:         return "figure.2.and.child.holdinghands"
        case .communityOutreach:   return "heart.fill"
        case .bibleStudy:          return "book.fill"
        case .smallGroup:          return "person.2.fill"
        case .baptismService:      return "drop.fill"
        case .conference:          return "person.3.sequence.fill"
        case .fastingPrayer:       return "hands.sparkles.fill"
        case .ashWednesdayService: return "cross.fill"
        }
    }
}

// MARK: - Audience Tag

enum AudienceTag: String, Codable, CaseIterable {
    case everyone       = "everyone"
    case families       = "families"
    case youngAdults    = "young_adults"
    case singles        = "singles"
    case youth          = "youth"
    case children       = "children"
    case men            = "men"
    case women          = "women"
    case seniors        = "seniors"
    case newVisitors    = "new_visitors"

    var displayName: String {
        switch self {
        case .everyone:    return "Everyone"
        case .families:    return "Families"
        case .youngAdults: return "Young Adults"
        case .singles:     return "Singles"
        case .youth:       return "Youth"
        case .children:    return "Children"
        case .men:         return "Men"
        case .women:       return "Women"
        case .seniors:     return "Seniors"
        case .newVisitors: return "New Visitors"
        }
    }
}

// MARK: - Church Seasonal Event

struct ChurchSeasonalEvent: Identifiable, Codable {
    let id: String
    let churchId: String
    let churchName: String
    let title: String
    let eventDescription: String
    let eventType: ChurchEventType
    let startDateTime: Date
    let endDateTime: Date
    let holidayTags: [HolidayType]
    let isFirstTimeFriendly: Bool
    let hasKidsProgram: Bool
    let hasLivestream: Bool
    let livestreamUrl: String?
    let location: EventLocation
    let parkingInfo: String?
    let whatToExpect: String?
    let registrationUrl: String?
    let audienceTags: [AudienceTag]
    let displayPriority: Int
    let createdAt: Date

    struct EventLocation: Codable, Equatable {
        let address: String
        let city: String
        let state: String
        let zipCode: String
        let latitude: Double?
        let longitude: Double?

        var formattedAddress: String {
            "\(address), \(city), \(state) \(zipCode)"
        }
    }

    /// Whether the event is upcoming (hasn't ended yet).
    var isUpcoming: Bool {
        endDateTime > Date()
    }

    /// Days until the event starts.
    var daysUntilStart: Int {
        max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: startDateTime)).day ?? 0)
    }

    /// Whether the event is happening today.
    var isToday: Bool {
        Calendar.current.isDateInToday(startDateTime)
    }
}

// MARK: - Church Calendar Profile

/// A church's holiday calendar configuration (for church admin features).
struct ChurchCalendarProfile: Codable {
    let churchId: String
    let denominationProfile: DenominationProfile
    let supportedObservances: [HolidayType]
    let customEvents: [String]              // IDs of custom events
    let theologyTags: [String]              // e.g., "reformed", "charismatic"
    let holidayContentOverrides: [String: String]  // holidayType → custom description
    let updatedAt: Date
}

// MARK: - Post-Service Follow-Up

struct PostServiceFollowUp: Codable, Identifiable {
    let id: String
    let eventId: String
    let userId: String
    let type: FollowUpType
    let message: String
    let createdAt: Date
    var response: String?
    var respondedAt: Date?

    enum FollowUpType: String, Codable {
        case experienceFeedback     // "How was your experience?"
        case prayerOffer            // "Would you like prayer?"
        case returnIntent           // "Would you like to come back?"
        case groupConnect           // "Would you like to join a group?"
        case nextSteps              // "What's your next step?"
    }
}

// MARK: - Service

@MainActor
final class ChurchSeasonalEventService: ObservableObject {

    static let shared = ChurchSeasonalEventService()

    @Published private(set) var nearbyEvents: [ChurchSeasonalEvent] = []
    @Published private(set) var holidayEvents: [ChurchSeasonalEvent] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private let cacheKey = "church_seasonal_events_v1"
    private let cacheTTL: TimeInterval = 1800 // 30 minutes

    private var lastFetchTime: Date?

    private init() {}

    // MARK: - Fetch Events

    /// Fetches upcoming seasonal events, optionally filtered by holiday and location.
    func fetchEvents(
        holiday: HolidayType? = nil,
        nearLocation: CLLocationCoordinate2D? = nil,
        radiusMiles: Double = 25,
        limit: Int = 20
    ) async {
        // Check cache freshness
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTTL,
           !nearbyEvents.isEmpty {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            var query: Query = db.collection("churchSeasonalEvents")
                .whereField("endDateTime", isGreaterThan: Timestamp(date: Date()))
                .order(by: "endDateTime")
                .limit(to: limit)

            // Filter by holiday tag if specified
            if let holiday = holiday {
                query = db.collection("churchSeasonalEvents")
                    .whereField("holidayTags", arrayContains: holiday.rawValue)
                    .whereField("endDateTime", isGreaterThan: Timestamp(date: Date()))
                    .order(by: "endDateTime")
                    .limit(to: limit)
            }

            let snapshot = try await query.getDocuments()

            var events: [ChurchSeasonalEvent] = snapshot.documents.compactMap { doc in
                try? doc.data(as: ChurchSeasonalEvent.self)
            }

            // Client-side location filtering if coordinates provided
            if let location = nearLocation {
                let userLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
                let radiusMeters = radiusMiles * 1609.34

                events = events.filter { event in
                    guard let lat = event.location.latitude,
                          let lng = event.location.longitude else { return true }
                    let eventLocation = CLLocation(latitude: lat, longitude: lng)
                    return userLocation.distance(from: eventLocation) <= radiusMeters
                }
            }

            // Sort by priority then date
            events.sort { lhs, rhs in
                if lhs.displayPriority != rhs.displayPriority {
                    return lhs.displayPriority > rhs.displayPriority
                }
                return lhs.startDateTime < rhs.startDateTime
            }

            self.nearbyEvents = events
            self.lastFetchTime = Date()

            // Separate holiday-specific events
            let state = LiturgicalCalendarEngine.shared.currentState()
            let activeHolidays = Set(state.activeObservances.map(\.type))
            self.holidayEvents = events.filter { event in
                !event.holidayTags.filter({ activeHolidays.contains($0) }).isEmpty
            }

        } catch {
            dlog("[ChurchSeasonalEvent] Fetch failed: \(error.localizedDescription)")
        }
    }

    /// Fetches events for a specific church.
    func fetchEventsForChurch(_ churchId: String, limit: Int = 10) async -> [ChurchSeasonalEvent] {
        do {
            let snapshot = try await db.collection("churchSeasonalEvents")
                .whereField("churchId", isEqualTo: churchId)
                .whereField("endDateTime", isGreaterThan: Timestamp(date: Date()))
                .order(by: "endDateTime")
                .limit(to: limit)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                try? doc.data(as: ChurchSeasonalEvent.self)
            }
        } catch {
            dlog("[ChurchSeasonalEvent] Church fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - First-Time Visitor Helpers

    /// Returns first-time-friendly events for a given holiday.
    func firstTimeFriendlyEvents(for holiday: HolidayType) -> [ChurchSeasonalEvent] {
        nearbyEvents.filter { event in
            event.isFirstTimeFriendly && event.holidayTags.contains(holiday)
        }
    }

    /// Returns family-friendly events (has kids program).
    func familyFriendlyEvents() -> [ChurchSeasonalEvent] {
        nearbyEvents.filter(\.hasKidsProgram)
    }

    /// Returns events with livestream available.
    func livestreamEvents() -> [ChurchSeasonalEvent] {
        nearbyEvents.filter(\.hasLivestream)
    }

    // MARK: - Post-Service Follow-Up

    /// Creates a post-service follow-up for a user after attending an event.
    func createFollowUp(
        eventId: String,
        userId: String,
        type: PostServiceFollowUp.FollowUpType
    ) async {
        let messages: [PostServiceFollowUp.FollowUpType: String] = [
            .experienceFeedback: "How was your experience at the service?",
            .prayerOffer: "Would you like prayer for anything?",
            .returnIntent: "Would you like to come back next week?",
            .groupConnect: "Would you like to join a small group?",
            .nextSteps: "What's your next step in your faith journey?"
        ]

        let followUp = PostServiceFollowUp(
            id: UUID().uuidString,
            eventId: eventId,
            userId: userId,
            type: type,
            message: messages[type] ?? "How was your experience?",
            createdAt: Date(),
            response: nil,
            respondedAt: nil
        )

        do {
            let data = try Firestore.Encoder().encode(followUp)
            try await db.collection("users").document(userId)
                .collection("serviceFollowUps")
                .document(followUp.id)
                .setData(data)
        } catch {
            dlog("[ChurchSeasonalEvent] Follow-up creation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Church Admin: Publish Event

    /// Publishes a seasonal event (for church admin use).
    func publishEvent(_ event: ChurchSeasonalEvent) async -> Bool {
        do {
            let data = try Firestore.Encoder().encode(event)
            try await db.collection("churchSeasonalEvents")
                .document(event.id)
                .setData(data)
            return true
        } catch {
            dlog("[ChurchSeasonalEvent] Publish failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Deletes a seasonal event (for church admin use).
    func deleteEvent(_ eventId: String) async -> Bool {
        do {
            try await db.collection("churchSeasonalEvents")
                .document(eventId)
                .delete()
            return true
        } catch {
            dlog("[ChurchSeasonalEvent] Delete failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reset

    func reset() {
        nearbyEvents.removeAll()
        holidayEvents.removeAll()
        lastFetchTime = nil
    }
}
