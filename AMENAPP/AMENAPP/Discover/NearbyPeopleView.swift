// NearbyPeopleView.swift
// AMEN App — Nearby People Discovery
//
// Privacy-gated sheet shown when the user taps the "Near Me" filter chip
// in AmenDiscoverView. Gated by AMENFeatureFlags.nearbyPeopleDiscoveryEnabled.
//
// Location data is NEVER stored in Firestore. Proximity matching uses
// server-side ephemeral geohash queries only — no coordinates are persisted.

import SwiftUI
import CoreLocation

// MARK: - NearbyPeopleView

struct NearbyPeopleView: View {

    @StateObject private var vm = NearbyPeopleViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Near Me")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .task { await vm.requestLocationAndLoad() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .requestingPermission:
            locationPermissionPrompt
        case .denied:
            locationDeniedView
        case .loading:
            loadingView
        case .loaded(let profiles):
            if profiles.isEmpty {
                emptyView
            } else {
                profileList(profiles)
            }
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Sub-views

    private var locationPermissionPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.amenGold)
            Text("Find Believers Near You")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text("AMEN uses your approximate location to surface other believers nearby. Your exact location is never stored or shared.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await vm.requestLocationAndLoad() }
            } label: {
                Label("Allow Location", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.amenGold)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationDeniedView: some View {
        ContentUnavailableView {
            Label("Location Access Needed", systemImage: "location.slash.fill")
        } description: {
            Text("Enable location access in Settings to find believers near you.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.amenGold)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Finding believers near you…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No One Nearby Yet", systemImage: "person.2.slash")
        } description: {
            Text("Be the first to represent your faith in this area. Invite a friend to join AMEN.")
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Something Went Wrong", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await vm.requestLocationAndLoad() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.amenGold)
        }
    }

    private func profileList(_ profiles: [NearbyPersonProfile]) -> some View {
        List(profiles) { profile in
            NearbyPersonRow(profile: profile)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }
}

// MARK: - NearbyPersonRow

private struct NearbyPersonRow: View {
    let profile: NearbyPersonProfile

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: profile.profileImageURL ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let church = profile.churchAffiliation {
                    Text(church)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let distanceLabel = profile.distanceLabel {
                Text(distanceLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Models

struct NearbyPersonProfile: Identifiable, Decodable {
    let id: String
    let displayName: String
    let profileImageURL: String?
    let churchAffiliation: String?
    /// Human-readable distance string (e.g. "0.4 mi") — server-computed, never raw coordinates.
    let distanceLabel: String?
}

// MARK: - ViewModel

@MainActor
final class NearbyPeopleViewModel: ObservableObject {

    enum State {
        case requestingPermission
        case denied
        case loading
        case loaded([NearbyPersonProfile])
        case error(String)
    }

    @Published var state: State = .requestingPermission

    private let locationManager = CLLocationManager()

    func requestLocationAndLoad() async {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            state = .requestingPermission
            locationManager.requestWhenInUseAuthorization()
            // Re-check after a short delay for the permission dialog to resolve
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await requestLocationAndLoad()
        case .denied, .restricted:
            state = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            await loadNearbyPeople()
        @unknown default:
            state = .denied
        }
    }

    private func loadNearbyPeople() async {
        state = .loading
        // Placeholder: real implementation calls a Cloud Function that accepts
        // a geohash computed client-side. Raw coordinates are never sent to Firestore.
        // The Cloud Function returns NearbyPersonProfile objects with distanceLabel
        // already formatted server-side.
        try? await Task.sleep(nanoseconds: 500_000_000) // simulate network
        state = .loaded([])
    }
}
