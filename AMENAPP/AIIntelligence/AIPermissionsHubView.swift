// AIPermissionsHubView.swift
// AMENAPP
//
// Wave 3 — iOS-Settings-style per-capability permissions hub. Each row shows the
// REAL current authorization state and a working control:
//   - OS-managed capabilities (camera, microphone, contacts, location) show the
//     live authorization status and deep-link to Settings — the only honest
//     control an app has over them (it cannot flip them silently).
//   - App-managed capabilities (Berean memory, journal access for AI) are real
//     toggles persisted on device and honored at the read site (§2.6).
//
// Gated by AMENFeatureFlags.shared.aiPermissionsHubEnabled (default OFF).

import SwiftUI
import AVFoundation
import Contacts
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

struct AIPermissionsHubView: View {
    @StateObject private var model = PermissionsHubModel()
    @State private var memoryEnabled = true
    @AppStorage("ai.permissions.journalAccess") private var journalAccess = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $memoryEnabled) {
                    Label("Let Berean remember", systemImage: "brain.head.profile")
                }
                .tint(.blue)
                .onChange(of: memoryEnabled) { _, on in
                    // Real: inverts the on-device memory pause used by BereanMemoryStore.
                    UserDefaults.standard.set(!on, forKey: MemoryLedgerService.pauseDefaultsKey)
                }

                Toggle(isOn: $journalAccess) {
                    Label("Journal access for AI", systemImage: "book.closed")
                }
                .tint(.blue)
            } header: {
                Text("In-app (you control these here)")
            } footer: {
                Text("These are honored on this device. Turning memory off stops new memory being saved.")
            }

            Section {
                ForEach(model.osCapabilities) { cap in
                    capabilityRow(cap)
                }
            } header: {
                Text("System permissions")
            } footer: {
                Text("iOS controls these. Tap to review or change them in Settings.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AI Permissions")
        .onAppear {
            memoryEnabled = !UserDefaults.standard.bool(forKey: MemoryLedgerService.pauseDefaultsKey)
            model.refresh()
        }
    }

    private func capabilityRow(_ cap: OSCapability) -> some View {
        Button {
            openSettings()
        } label: {
            HStack {
                Label(cap.title, systemImage: cap.symbol)
                    .foregroundStyle(.primary)
                Spacer()
                Text(cap.statusText)
                    .font(.caption)
                    .foregroundStyle(cap.isGranted ? .green : .secondary) // green = granted state
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Capability model (reads REAL authorization statuses)

struct OSCapability: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let statusText: String
    let isGranted: Bool
}

@MainActor
final class PermissionsHubModel: ObservableObject {
    @Published private(set) var osCapabilities: [OSCapability] = []

    private let locationManager = CLLocationManager()

    func refresh() {
        osCapabilities = [
            capability(id: "camera", title: "Camera", symbol: "camera",
                       status: AVCaptureDevice.authorizationStatus(for: .video)),
            capability(id: "microphone", title: "Microphone", symbol: "mic",
                       status: AVCaptureDevice.authorizationStatus(for: .audio)),
            contactsCapability(),
            locationCapability()
        ]
    }

    private func capability(id: String, title: String, symbol: String,
                            status: AVAuthorizationStatus) -> OSCapability {
        let granted = status == .authorized
        return OSCapability(id: id, title: title, symbol: symbol,
                            statusText: text(forAV: status), isGranted: granted)
    }

    private func contactsCapability() -> OSCapability {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let granted = status == .authorized
        let text: String
        switch status {
        case .authorized: text = "Allowed"
        case .denied: text = "Off"
        case .restricted: text = "Restricted"
        case .notDetermined: text = "Not set"
        // Plain default also covers .limited (iOS 18+) without an availability guard.
        default: text = "Limited"
        }
        return OSCapability(id: "contacts", title: "Contacts", symbol: "person.2",
                            statusText: text, isGranted: granted)
    }

    private func locationCapability() -> OSCapability {
        let status = locationManager.authorizationStatus
        let granted = status == .authorizedAlways || status == .authorizedWhenInUse
        let text: String
        switch status {
        case .authorizedAlways: text = "Always"
        case .authorizedWhenInUse: text = "While using"
        case .denied: text = "Off"
        case .restricted: text = "Restricted"
        case .notDetermined: text = "Not set"
        @unknown default: text = "Limited"
        }
        return OSCapability(id: "location", title: "Location", symbol: "location",
                            statusText: text, isGranted: granted)
    }

    private func text(forAV status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not set"
        @unknown default: return "Limited"
        }
    }
}

#if DEBUG
#Preview("AI Permissions hub") {
    NavigationStack { AIPermissionsHubView() }
}
#endif
