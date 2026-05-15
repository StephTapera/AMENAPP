//
//  HolidayAwarenessService.swift
//  AMENAPP
//
//  Resolves the holiday context for today's Daily Verse banner.
//
//  Priority order (highest wins):
//    1. Major Christian events day-of (Easter, Good Friday, Christmas)
//    2. Biblical feasts day-of (Passover, Yom Kippur, Sukkot)
//    3. Consistent Christian events day-of (Pentecost, Advent start, etc.)
//    4. Biblically-consistent civic holidays day-of (Thanksgiving, Mother's Day, etc.)
//    5. Discernment holidays day-of (Halloween, Valentine's, etc.)
//    6. Personal celebrations day-of (birthday, anniversary — only if opted in)
//    7. No holiday → normal daily verse
//
//  Firestore structure (backend authoritative):
//    holiday_calendar/{year}/days/{yyyy-MM-dd}/observances/{holidayId}
//
//  Client fallback: LiturgicalCalendarEngine + static lookup tables.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class HolidayAwarenessService: ObservableObject {

    static let shared = HolidayAwarenessService()

    @Published private(set) var todayContext: HolidayContextResponse = .noHoliday
    @Published private(set) var isLoading = false

    private lazy var db = Firestore.firestore()
    private let calendar = LiturgicalCalendarEngine.shared
    private let cacheKey = "holiday_context_v2"
    private let cacheDateKey = "holiday_context_date_v2"

    private init() {
        loadCachedContext()
    }

    // MARK: - Public API

    /// Resolves holiday context for today. Call once per app-launch day.
    func resolveToday(
        settings: HolidayAwarenessSettings = .defaultSettings,
        personalCelebrations: PersonalHolidayCelebrations? = nil
    ) async {
        // Use cached value if it is still today's
        if let cached = loadCachedContext(),
           Calendar.current.isDateInToday(cached.date) {
            todayContext = cached
            return
        }

        isLoading = true
        defer { isLoading = false }

        let result = await resolveContext(settings: settings, personalCelebrations: personalCelebrations)
        todayContext = result
        cacheContext(result)
    }

    // MARK: - Context Resolution

    private func resolveContext(
        settings: HolidayAwarenessSettings,
        personalCelebrations: PersonalHolidayCelebrations?
    ) async -> HolidayContextResponse {
        guard settings.enabled else { return .noHoliday }

        let userTimezone = TimeZone(identifier: settings.timezone) ?? .current
        let localDate = localToday(timezone: userTimezone)
        let year = Calendar.current.component(.year, from: localDate)
        let dateString = isoDate(localDate)

        // Step 1: Try backend Firestore override for today's observances
        if let firestoreContext = await fetchFirestoreContext(dateString: dateString, year: year, settings: settings) {
            return firestoreContext
        }

        // Step 2: Fall back to on-device LiturgicalCalendarEngine
        return resolveFromEngine(localDate: localDate, settings: settings, personalCelebrations: personalCelebrations)
    }

    // MARK: - Engine-Based Resolution (Offline Fallback)

    private func resolveFromEngine(
        localDate: Date,
        settings: HolidayAwarenessSettings,
        personalCelebrations: PersonalHolidayCelebrations?
    ) -> HolidayContextResponse {
        let year = Calendar.current.component(.year, from: localDate)
        let allObservances = calendar.calendarForYear(year)

        // Find observances that are "day of" today
        let todayObservances = allObservances.filter { obs in
            Calendar.current.isDate(obs.date, inSameDayAs: localDate) &&
            settings.allows(category: obs.type.category)
        }

        if todayObservances.isEmpty {
            // Check personal celebrations if enabled
            if settings.showPersonalCelebrations,
               let personal = personalCelebrations,
               let celebration = personal.activeCelebration() {
                return HolidayContextResponse(
                    date: localDate,
                    bannerContent: celebration.bannerContent,
                    holidayType: nil,
                    shouldShowHolidayBanner: true,
                    shouldShowDiscernmentFraming: false,
                    holidayPriority: 2,
                    reason: "Personal celebration: \(celebration.rawValue)",
                    personalCelebration: celebration
                )
            }
            return .noHoliday
        }

        // Sort by priority weight (highest first)
        let sorted = todayObservances.sorted { $0.type.priorityWeight > $1.type.priorityWeight }
        guard let primary = sorted.first else { return .noHoliday }

        // Respect quiet mode on solemn days
        if settings.quietModeOnSolemnDays,
           primary.type == .goodFriday || primary.type == .holySaturday || primary.type == .ashWednesday {
            return .noHoliday
        }

        guard let content = HolidayBannerCatalog.content(for: primary.type) else { return .noHoliday }

        let isDiscernment = primary.type.category == .discernment
        return HolidayContextResponse(
            date: localDate,
            bannerContent: content,
            holidayType: primary.type,
            shouldShowHolidayBanner: true,
            shouldShowDiscernmentFraming: isDiscernment,
            holidayPriority: primary.type.priorityWeight,
            reason: "Day-of: \(primary.type.displayName)",
            personalCelebration: nil
        )
    }

    // MARK: - Firestore Fetch

    private func fetchFirestoreContext(
        dateString: String,
        year: Int,
        settings: HolidayAwarenessSettings
    ) async -> HolidayContextResponse? {
        do {
            let path = db
                .collection("holiday_calendar").document("\(year)")
                .collection("days").document(dateString)
                .collection("observances")

            let snapshot = try await path.getDocuments()
            guard !snapshot.isEmpty else { return nil }

            // Parse and pick highest-priority observance
            var best: (priority: Int, type: HolidayType, content: HolidayBannerContent)?
            for doc in snapshot.documents {
                let data = doc.data()
                guard
                    let typeRaw = data["id"] as? String,
                    let holidayType = HolidayType(rawValue: typeRaw),
                    settings.allows(category: holidayType.category)
                else { continue }

                let priority = data["priority"] as? Int ?? holidayType.priorityWeight
                if best == nil || priority > best!.priority {
                    // Use Firestore copy if available, else fall back to catalog
                    let content = firestoreContent(from: data, type: holidayType) ??
                                  HolidayBannerCatalog.content(for: holidayType)
                    if let c = content {
                        best = (priority, holidayType, c)
                    }
                }
            }

            guard let winner = best else { return nil }
            let isDiscernment = winner.type.category == .discernment
            let localDate = localToday(timezone: TimeZone(identifier: settings.timezone) ?? .current)

            return HolidayContextResponse(
                date: localDate,
                bannerContent: winner.content,
                holidayType: winner.type,
                shouldShowHolidayBanner: true,
                shouldShowDiscernmentFraming: isDiscernment,
                holidayPriority: winner.priority,
                reason: "Firestore: \(winner.type.displayName)",
                personalCelebration: nil
            )
        } catch {
            dlog("[HolidayAwareness] Firestore fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Tries to build HolidayBannerContent from raw Firestore document data.
    private func firestoreContent(from data: [String: Any], type: HolidayType) -> HolidayBannerContent? {
        guard
            let title   = data["shortBannerTitle"]   as? String,
            let message = data["shortBannerMessage"]  as? String,
            let verse   = data["primaryVerseReference"] as? String
        else { return nil }

        let ctaLabel  = data["callToActionLabel"]  as? String ?? "Reflect"
        let ctaRoute  = data["callToActionRoute"]  as? String ?? "amen://berean"
        let reflection = data["expandedReflection"] as? String ?? ""
        let addl = data["scriptures"] as? [String] ?? []
        let theme = data["theme"] as? String ?? ""
        let tone  = data["allowedTone"] as? String ?? ""
        let catRaw = data["category"] as? String ?? type.category.rawValue
        let category = HolidayCategory(rawValue: catRaw) ?? type.category
        let conRaw = data["consistencyLevel"] as? String ?? "consistent"
        let consistency = HolidayConsistencyLevel(rawValue: conRaw) ?? .consistent
        let canonicalName = data["canonicalName"] as? String ?? type.displayName

        return HolidayBannerContent(
            category: category,
            consistencyLevel: consistency,
            canonicalName: canonicalName,
            shortBannerTitle: title,
            shortBannerMessage: message,
            primaryScriptureReference: verse,
            additionalScriptures: addl,
            theme: theme,
            callToActionLabel: ctaLabel,
            callToActionRoute: ctaRoute,
            expandedReflection: reflection,
            allowedTone: tone,
            prohibitedTone: ""
        )
    }

    // MARK: - getDailyVerseContext (used by Cloud Function and BereanChat)

    /// Returns the holiday context for a given user + date, suitable for passing to generateDailyVerse.
    func getDailyVerseContext(
        userId: String,
        date: Date = Date(),
        timezone: String = TimeZone.current.identifier
    ) async -> DailyVerseHolidayContext {
        let settings = await loadUserSettings(userId: userId)
        let localDate = localToday(timezone: TimeZone(identifier: timezone) ?? .current)
        let year = Calendar.current.component(.year, from: localDate)
        let allObservances = calendar.calendarForYear(year)

        let todayObservances = allObservances.filter { obs in
            Calendar.current.isDate(obs.date, inSameDayAs: localDate) &&
            settings.allows(category: obs.type.category)
        }.sorted { $0.type.priorityWeight > $1.type.priorityWeight }

        if let primary = todayObservances.first,
           let content = HolidayBannerCatalog.content(for: primary.type) {
            return DailyVerseHolidayContext(
                holidayName: content.canonicalName,
                category: primary.type.category.rawValue,
                theme: content.theme,
                primaryScripture: content.primaryScriptureReference,
                additionalScriptures: content.additionalScriptures,
                tone: content.allowedTone,
                bannerTitle: content.shortBannerTitle,
                bannerMessage: content.shortBannerMessage,
                isDiscernmentHoliday: primary.type.category == .discernment,
                priority: primary.type.priorityWeight
            )
        }

        return DailyVerseHolidayContext(
            holidayName: nil, category: nil, theme: nil,
            primaryScripture: nil, additionalScriptures: [],
            tone: nil, bannerTitle: nil, bannerMessage: nil,
            isDiscernmentHoliday: false, priority: 0
        )
    }

    // MARK: - User Settings Loader

    private func loadUserSettings(userId: String) async -> HolidayAwarenessSettings {
        do {
            let doc = try await db
                .collection("users").document(userId)
                .collection("settings").document("holidayAwareness")
                .getDocument()
            if doc.exists, let decoded = try? doc.data(as: HolidayAwarenessSettings.self) {
                return decoded
            }
        } catch { /* fall through */ }
        return .defaultSettings
    }

    // MARK: - Utilities

    private func localToday(timezone: TimeZone) -> Date {
        var cal = Calendar.current
        cal.timeZone = timezone
        return cal.startOfDay(for: Date())
    }

    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: - Cache

    @discardableResult
    private func loadCachedContext() -> HolidayContextResponse? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let dateData = UserDefaults.standard.data(forKey: cacheDateKey),
            let cachedDate = try? JSONDecoder().decode(Date.self, from: dateData),
            Calendar.current.isDateInToday(cachedDate),
            let ctx = try? JSONDecoder().decode(CachedHolidayContext.self, from: data)
        else { return nil }

        let response = HolidayContextResponse(
            date: ctx.date,
            bannerContent: ctx.bannerContent,
            holidayType: ctx.holidayTypeRaw.flatMap { HolidayType(rawValue: $0) },
            shouldShowHolidayBanner: ctx.shouldShowHolidayBanner,
            shouldShowDiscernmentFraming: ctx.shouldShowDiscernmentFraming,
            holidayPriority: ctx.holidayPriority,
            reason: ctx.reason,
            personalCelebration: ctx.personalCelebrationRaw.flatMap {
                PersonalHolidayCelebrations.PersonalCelebration(rawValue: $0)
            }
        )
        todayContext = response
        return response
    }

    private func cacheContext(_ ctx: HolidayContextResponse) {
        let cacheable = CachedHolidayContext(from: ctx)
        guard
            let data = try? JSONEncoder().encode(cacheable),
            let dateData = try? JSONEncoder().encode(ctx.date)
        else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(dateData, forKey: cacheDateKey)
    }

    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
    }
}

// MARK: - Codable Cache Wrapper

/// Codable wrapper so HolidayContextResponse can be cached in UserDefaults.
private struct CachedHolidayContext: Codable {
    let date: Date
    let bannerContent: HolidayBannerContent?
    let holidayTypeRaw: String?
    let shouldShowHolidayBanner: Bool
    let shouldShowDiscernmentFraming: Bool
    let holidayPriority: Int
    let reason: String
    let personalCelebrationRaw: String?

    init(from response: HolidayContextResponse) {
        self.date = response.date
        self.bannerContent = response.bannerContent
        self.holidayTypeRaw = response.holidayType?.rawValue
        self.shouldShowHolidayBanner = response.shouldShowHolidayBanner
        self.shouldShowDiscernmentFraming = response.shouldShowDiscernmentFraming
        self.holidayPriority = response.holidayPriority
        self.reason = response.reason
        self.personalCelebrationRaw = response.personalCelebration?.rawValue
    }
}

extension HolidayBannerContent: Codable {}

// MARK: - Daily Verse Holiday Context (for Cloud Function + Berean)

/// Passed to the generateDailyVerse Cloud Function when a holiday is active.
struct DailyVerseHolidayContext: Codable {
    let holidayName: String?
    let category: String?
    let theme: String?
    let primaryScripture: String?
    let additionalScriptures: [String]
    let tone: String?
    let bannerTitle: String?
    let bannerMessage: String?
    let isDiscernmentHoliday: Bool
    let priority: Int

    var hasHoliday: Bool { holidayName != nil }
}
