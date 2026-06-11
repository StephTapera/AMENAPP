import CoreLocation
import Foundation
import Testing
@testable import AMENAPP

@MainActor
@Suite("SafeZoneService current location")
struct SafeZoneServiceTests {

    @Test("Adding at current location stores provider coordinate")
    func addSafeZoneAtCurrentLocationUsesProviderLocation() async throws {
        let defaults = makeDefaults()
        let location = CLLocation(latitude: 33.4484, longitude: -112.0740)
        let service = SafeZoneService(
            defaults: defaults,
            locationProvider: FixedSafeZoneLocationProvider(location: location)
        )

        let zone = try await service.addSafeZoneAtCurrentLocation(
            name: "Home",
            radiusMeters: 200,
            triggerExtraReview: true
        )

        #expect(zone.latitude == location.coordinate.latitude)
        #expect(zone.longitude == location.coordinate.longitude)
        #expect(service.safeZones.count == 1)
        #expect(service.safeZones.first?.latitude == location.coordinate.latitude)
        #expect(service.safeZones.first?.longitude == location.coordinate.longitude)
    }

    @Test("Current location failure does not save a placeholder zone")
    func addSafeZoneAtCurrentLocationFailureDoesNotSaveZone() async {
        let service = SafeZoneService(
            defaults: makeDefaults(),
            locationProvider: FailingSafeZoneLocationProvider()
        )

        do {
            _ = try await service.addSafeZoneAtCurrentLocation(
                name: "Home",
                radiusMeters: 200,
                triggerExtraReview: true
            )
            Issue.record("Expected current-location failure")
        } catch {
            #expect(service.safeZones.isEmpty)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SafeZoneServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private struct FixedSafeZoneLocationProvider: SafeZoneLocationProviding {
    let location: CLLocation

    func requestCurrentLocation() async throws -> CLLocation {
        location
    }
}

@MainActor
private struct FailingSafeZoneLocationProvider: SafeZoneLocationProviding {
    func requestCurrentLocation() async throws -> CLLocation {
        throw SafeZoneLocationError.authorizationDenied
    }
}
