import Foundation
import FirebaseFunctions

@MainActor
final class AmenDailyDigestService: ObservableObject {
    static let shared = AmenDailyDigestService()

    @Published private(set) var state: AmenDailyDigestState = .idle

    private let functions = Functions.functions(region: "us-central1")
    private let weatherProvider: AmenDailyDigestWeatherProvider
    private let cacheKey = "amenDailyDigest.cache.v1"
    private let cacheDateKey = "amenDailyDigest.cacheDateKey.v1"
    private var currentLoadTask: Task<Void, Never>?

    var digest: AmenDailyDigest? { state.digest }

    init(weatherProvider: AmenDailyDigestWeatherProvider = .shared) {
        self.weatherProvider = weatherProvider
    }

    func loadDigest(forceRefresh: Bool = false) async {
        guard AMENFeatureFlags.shared.amenDailyDigestEnabled else {
            state = .fallback(AmenDailyDigest.fallback())
            return
        }
        let dateKey = AmenDailyDigestDateKey.string(from: Date())
        let cached = loadCachedDigest(for: dateKey)
        if !forceRefresh, let cached {
            state = .loaded(cached)
            trackLoaded(cached)
            return
        }
        if let currentLoadTask, !currentLoadTask.isCancelled { return }
        let fallback = cached ?? AmenDailyDigest.fallback()
        state = .loading(fallback)
        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let weather = self.weatherProvider.currentWeatherContext()
                let digest = try await self.fetchBackendDigest(dateKey: dateKey, weather: weather)
                self.cache(digest)
                self.state = .loaded(digest)
                self.trackLoaded(digest)
            } catch {
                self.state = .fallback(fallback)
                self.trackFallback(fallback)
            }
            self.currentLoadTask = nil
        }
        await currentLoadTask?.value
    }

    private func fetchBackendDigest(dateKey: String, weather: AmenDailyWeatherContext?) async throws -> AmenDailyDigest {
        var payload: [String: Any] = [
            "dateKey": dateKey,
            "timezone": TimeZone.current.identifier,
            "locale": Locale.current.identifier,
            "countryCode": Locale.current.region?.identifier ?? "US",
            "weatherEnabled": AMENFeatureFlags.shared.amenDailyDigestWeatherEnabled,
            "holidayEnabled": AMENFeatureFlags.shared.amenDailyDigestHolidayEnabled,
            "christianCalendarEnabled": AMENFeatureFlags.shared.amenDailyDigestChristianCalendarEnabled,
            "personalizationEnabled": false
        ]
        if let weather {
            payload["weather"] = weather.asPayload
        }
        let result = try await functions.httpsCallable("getAmenDailyDigest").call(payload)
        let object = result.data as? [String: Any] ?? [:]
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AmenDailyDigest.self, from: data)
    }

    private func loadCachedDigest(for dateKey: String) -> AmenDailyDigest? {
        guard UserDefaults.standard.string(forKey: cacheDateKey) == dateKey,
              let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let digest = try? decoder.decode(AmenDailyDigest.self, from: data) else { return nil }
        return AmenDailyDigest(id: digest.id, dateKey: digest.dateKey, greeting: digest.greeting, title: digest.title, verseText: digest.verseText, verseReference: digest.verseReference, contextText: digest.contextText, reflectionText: digest.reflectionText, prayerPrompt: digest.prayerPrompt, passage: digest.passage, weather: digest.weather, holiday: digest.holiday, actions: digest.actions, priority: digest.priority, generatedAt: digest.generatedAt, source: .cached)
    }

    private func cache(_ digest: AmenDailyDigest) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(digest) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(digest.dateKey, forKey: cacheDateKey)
    }

    private func trackLoaded(_ digest: AmenDailyDigest) {
        AMENAnalyticsService.shared.track(.amenDailyDigestLoaded(dateKey: digest.dateKey, priority: digest.priority.rawValue, hasWeather: digest.weather != nil, hasHoliday: digest.holiday != nil, source: digest.source.rawValue))
        if digest.weather != nil { AMENAnalyticsService.shared.track(.amenDailyWeatherShown(dateKey: digest.dateKey, priority: digest.priority.rawValue, hasWeather: true, hasHoliday: digest.holiday != nil, source: digest.source.rawValue)) }
        if digest.holiday != nil { AMENAnalyticsService.shared.track(.amenDailyHolidayShown(dateKey: digest.dateKey, priority: digest.priority.rawValue, hasWeather: digest.weather != nil, hasHoliday: true, source: digest.source.rawValue)) }
    }

    private func trackFallback(_ digest: AmenDailyDigest) {
        AMENAnalyticsService.shared.track(.amenDailyDigestFallbackUsed(dateKey: digest.dateKey, priority: digest.priority.rawValue, hasWeather: digest.weather != nil, hasHoliday: digest.holiday != nil, source: digest.source.rawValue))
    }
}

private extension AmenDailyWeatherContext {
    var asPayload: [String: Any] {
        var payload: [String: Any] = ["alertLevel": alertLevel.rawValue]
        payload["temperature"] = temperature
        payload["condition"] = condition
        payload["high"] = high
        payload["low"] = low
        payload["precipitationChance"] = precipitationChance
        payload["summary"] = summary
        payload["spiritualTieIn"] = spiritualTieIn
        return payload
    }
}
