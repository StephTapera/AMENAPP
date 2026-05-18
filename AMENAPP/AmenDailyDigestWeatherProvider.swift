import CoreLocation
import Foundation

#if canImport(WeatherKit)
import WeatherKit
#endif

@MainActor
final class AmenDailyDigestWeatherProvider: NSObject, CLLocationManagerDelegate {
    static let shared = AmenDailyDigestWeatherProvider()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func currentWeatherContext() async -> AmenDailyWeatherContext? {
        guard AMENFeatureFlags.shared.amenDailyDigestWeatherEnabled else { return nil }
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            // Do not request permission from the banner. Weather is optional.
            return nil
        }

        guard let location = await currentApproximateLocation() else { return nil }
        return await weatherContext(for: approximate(location))
    }

    private func currentApproximateLocation() async -> CLLocation? {
        if let location = locationManager.location, abs(location.timestamp.timeIntervalSinceNow) < 1800 {
            return location
        }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func approximate(_ location: CLLocation) -> CLLocation {
        let roundedLatitude = (location.coordinate.latitude * 10).rounded() / 10
        let roundedLongitude = (location.coordinate.longitude * 10).rounded() / 10
        return CLLocation(latitude: roundedLatitude, longitude: roundedLongitude)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.last)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }

    private func weatherContext(for location: CLLocation) async -> AmenDailyWeatherContext? {
        #if canImport(WeatherKit)
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather
            let today = weather.dailyForecast.first
            let temperature = Int(current.temperature.converted(to: .fahrenheit).value.rounded())
            let high = today.map { Int($0.highTemperature.converted(to: .fahrenheit).value.rounded()) }
            let low = today.map { Int($0.lowTemperature.converted(to: .fahrenheit).value.rounded()) }
            let precipitationChance = today.map { Int(($0.precipitationChance * 100).rounded()) }
            let condition = String(describing: current.condition)
            let alertLevel = alertLevel(condition: condition, temperature: temperature, precipitationChance: precipitationChance)
            guard alertLevel != .none else { return nil }
            return AmenDailyWeatherContext(
                temperature: temperature,
                condition: condition,
                high: high,
                low: low,
                precipitationChance: precipitationChance,
                alertLevel: alertLevel,
                summary: summary(condition: condition, temperature: temperature, precipitationChance: precipitationChance, alertLevel: alertLevel),
                spiritualTieIn: nil
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private func alertLevel(condition: String, temperature: Int, precipitationChance: Int?) -> WeatherAlertLevel {
        let lower = condition.lowercased()
        if lower.contains("storm") || lower.contains("thunder") || temperature >= 100 || temperature <= 10 {
            return .severe
        }
        if lower.contains("rain") || lower.contains("snow") || lower.contains("fog") || temperature >= 95 || temperature <= 32 || (precipitationChance ?? 0) >= 50 {
            return .notable
        }
        return .none
    }

    private func summary(condition: String, temperature: Int, precipitationChance: Int?, alertLevel: WeatherAlertLevel) -> String {
        let lower = condition.lowercased()
        if alertLevel == .severe { return "Weather may affect your day. Plan ahead and stay safe." }
        if lower.contains("rain") { return "Rain expected today. A good day to slow down where you can." }
        if lower.contains("snow") { return "Snow may affect travel today. Leave extra margin where possible." }
        if lower.contains("fog") { return "Fog may make the morning slower. Take extra care as you go." }
        if temperature >= 95 { return "Heat may shape the day. Pace yourself and stay hydrated." }
        if temperature <= 32 { return "Cold morning ahead. Start slowly where you can." }
        if let precipitationChance, precipitationChance >= 50 { return "Precipitation is possible today. Keep a little margin where you can." }
        return "Weather may shape the day. Keep a little margin where you can."
    }
}
