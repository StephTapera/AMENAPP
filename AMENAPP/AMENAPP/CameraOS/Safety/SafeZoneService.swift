// SafeZoneService.swift
// AMENAPP — Camera OS
// User-defined Safe Zones: home/school/work locations that trigger extra review.
// Zones stored locally (UserDefaults). Location matching uses CoreLocation.
//
// Design: Liquid Glass on dark/black camera context.
//   Pre-iOS 26: .ultraThinMaterial + strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
//   iOS 26+:    .amenGlassEffect() on controls

import Foundation
import CoreLocation
import SwiftUI

// MARK: - SafeZoneService

@MainActor
final class SafeZoneService: ObservableObject {

    // MARK: Shared instance

    static let shared = SafeZoneService()

    // MARK: Published state

    @Published var safeZones: [CameraSafeZone] = []

    // MARK: Private constants

    private let defaultsKey = "cameraOS_safeZones"
    private let defaults: UserDefaults
    private let locationProvider: SafeZoneLocationProviding

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        locationProvider: SafeZoneLocationProviding? = nil
    ) {
        self.defaults = defaults
        self.locationProvider = locationProvider ?? CoreLocationSafeZoneLocationProvider()
        load()
    }

    // MARK: - Public API

    /// Adds a new safe zone centered on the given location.
    @discardableResult
    func addSafeZone(
        name: String,
        location: CLLocation,
        radiusMeters: Double,
        triggerExtraReview: Bool
    ) -> CameraSafeZone {
        let zone = CameraSafeZone(
            id: UUID().uuidString,
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radiusMeters: radiusMeters,
            triggerExtraReview: triggerExtraReview,
            isActive: true
        )
        safeZones.append(zone)
        save()
        return zone
    }

    /// Adds a new safe zone at the user's consented current location.
    @discardableResult
    func addSafeZoneAtCurrentLocation(
        name: String,
        radiusMeters: Double,
        triggerExtraReview: Bool
    ) async throws -> CameraSafeZone {
        let location = try await locationProvider.requestCurrentLocation()
        return addSafeZone(
            name: name,
            location: location,
            radiusMeters: radiusMeters,
            triggerExtraReview: triggerExtraReview
        )
    }

    /// Removes the zone with the given id.
    func removeSafeZone(id: String) {
        safeZones.removeAll { $0.id == id }
        save()
    }

    /// Flips the isActive flag for the zone with the given id.
    func toggleZone(id: String) {
        guard let index = safeZones.firstIndex(where: { $0.id == id }) else { return }
        let old = safeZones[index]
        safeZones[index] = CameraSafeZone(
            id: old.id,
            name: old.name,
            latitude: old.latitude,
            longitude: old.longitude,
            radiusMeters: old.radiusMeters,
            triggerExtraReview: old.triggerExtraReview,
            isActive: !old.isActive
        )
        save()
    }

    /// Returns the first active zone whose center is within radiusMeters of the given location.
    func isInAnySafeZone(location: CLLocation) -> CameraSafeZone? {
        safeZones.first { zone in
            guard zone.isActive else { return false }
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            return location.distance(from: center) <= zone.radiusMeters
        }
    }

    // MARK: - Private helpers

    private func load() {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([CameraSafeZone].self, from: data)
        else { return }
        safeZones = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(safeZones) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

// MARK: - SafeZoneLocationProviding

@MainActor
protocol SafeZoneLocationProviding {
    func requestCurrentLocation() async throws -> CLLocation
}

enum SafeZoneLocationError: Error {
    case locationServicesDisabled
    case authorizationDenied
    case requestInProgress
    case unavailable
}

@MainActor
final class CoreLocationSafeZoneLocationProvider: NSObject, SafeZoneLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw SafeZoneLocationError.locationServicesDisabled
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return try await requestLocation()
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                guard self.continuation == nil else {
                    continuation.resume(throwing: SafeZoneLocationError.requestInProgress)
                    return
                }
                self.continuation = continuation
                self.manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            throw SafeZoneLocationError.authorizationDenied
        @unknown default:
            throw SafeZoneLocationError.unavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(SafeZoneLocationError.authorizationDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(SafeZoneLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(SafeZoneLocationError.unavailable))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            guard self.continuation == nil else {
                continuation.resume(throwing: SafeZoneLocationError.requestInProgress)
                return
            }
            self.continuation = continuation
            self.manager.requestLocation()
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let location):
            continuation.resume(returning: location)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - SafeZoneManagerView

struct SafeZoneManagerView: View {

    // MARK: Props

    @ObservedObject var service: SafeZoneService

    // MARK: Private state

    @State private var isShowingAddAlert = false
    @State private var newZoneName = ""

    // MARK: Layout constants

    private let amberGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if service.safeZones.isEmpty {
                    emptyState
                } else {
                    zoneList
                }
            }
            .navigationTitle("Safe Zones")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton
                }
            }
            .alert("Add Safe Zone", isPresented: $isShowingAddAlert) {
                addZoneAlert
            } message: {
                Text("Enter a name for this safe zone. The zone will be centered on your current location.")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.systemScaled(44, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Safe Zones")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Add locations like home, school, or work. Posts taken near these zones will receive extra review before publishing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Zone list

    private var zoneList: some View {
        List {
            ForEach(service.safeZones) { zone in
                SafeZoneRow(zone: zone, accentColor: amberGold) { id in
                    service.toggleZone(id: id)
                }
            }
            .onDelete { offsets in
                offsets.forEach { index in
                    service.removeSafeZone(id: service.safeZones[index].id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityLabel("Safe zones list")
    }

    // MARK: - Toolbar add button

    private var addButton: some View {
        Button {
            newZoneName = ""
            isShowingAddAlert = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add safe zone")
        .accessibilityHint("Opens a dialog to add a new safe zone at your current location")
    }

    // MARK: - Add zone alert content

    @ViewBuilder
    private var addZoneAlert: some View {
        TextField("Zone name (e.g. Home, School)", text: $newZoneName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(false)

        Button("Add") {
            let name = newZoneName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            Task {
                try? await service.addSafeZoneAtCurrentLocation(
                    name: name,
                    radiusMeters: 200,
                    triggerExtraReview: true
                )
            }
        }
        .disabled(newZoneName.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Confirm add safe zone")

        Button("Cancel", role: .cancel) {}
            .accessibilityLabel("Cancel adding safe zone")
    }
}

// MARK: - SafeZoneRow

private struct SafeZoneRow: View {

    let zone: CameraSafeZone
    let accentColor: Color
    let onToggle: (String) -> Void

    private var radiusText: String {
        let meters = Int(zone.radiusMeters)
        return "\(meters) m radius"
    }

    private var extraReviewText: String {
        zone.triggerExtraReview ? "Extra review on" : "No extra review"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Zone icon
            ZStack {
                Circle()
                    .fill(zone.isActive ? accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: "mappin.circle.fill")
                    .font(.systemScaled(20))
                    .foregroundStyle(zone.isActive ? accentColor : .secondary)
            }
            .accessibilityHidden(true)

            // Zone info
            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(radiusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Text(extraReviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Active toggle
            Toggle("", isOn: Binding(
                get: { zone.isActive },
                set: { _ in onToggle(zone.id) }
            ))
            .labelsHidden()
            .tint(accentColor)
            .accessibilityLabel("\(zone.name) active")
            .accessibilityHint(zone.isActive ? "Tap to deactivate this safe zone" : "Tap to activate this safe zone")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(zone.name), \(radiusText), \(extraReviewText), \(zone.isActive ? "active" : "inactive")"
        )
    }
}

// MARK: - Preview

#Preview("Safe Zone Manager") {
    SafeZoneManagerView(service: SafeZoneService())
}
