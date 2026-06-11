import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - DrivingModeBanner
//
// Thin (56 pt) Liquid Glass bar shown in HomeView when AmenContextMode == .driving.
// Shows car icon + label + "Berean Voice" button.
// Posts .amenLaunchBereanVoice notification when tapped.

struct DrivingModeBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Driving Mode")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                NotificationCenter.default.post(
                    name: .amenLaunchBereanVoice,
                    object: nil
                )
            } label: {
                Text("Berean Voice")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    // Glass-on-glass fixed per seam sweep: button sits inside a
                    // livingGlassMaterial banner — use tinted solid fill instead.
                    .background(Capsule().fill(Color.white.opacity(0.20)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .livingGlassMaterial(tint: .orange)
        .padding(.horizontal, 12)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Driving mode activated"
            )
        }
    }
}

// MARK: - SundayModeCalloutBanner
//
// Thin banner shown when AmenContextMode == .church.
// "Good morning, ready for church?" + "Church Mode" button.
// Tapping "Church Mode" posts .amenOpenChurchMode so HomeView / ContentView
// can present SundayHomeView as appropriate.

struct SundayModeCalloutBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Good morning, ready for church?")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button {
                NotificationCenter.default.post(
                    name: .amenOpenChurchMode,
                    object: nil
                )
            } label: {
                Text("Church Mode")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    // Glass-on-glass fixed per seam sweep: button sits inside a
                    // livingGlassMaterial banner — use tinted solid fill instead.
                    .background(Capsule().fill(Color.white.opacity(0.20)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .livingGlassMaterial(tint: .purple)
        .padding(.horizontal, 12)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Church mode available. Tap Church Mode to switch."
            )
        }
    }
}

// MARK: - EventCheckInBanner
//
// Shown when AmenContextMode == .event.
// Writes attendance record to spaces/{spaceId}/attendance/{uid} on check-in.

struct EventCheckInBanner: View {
    let spaceName: String
    let spaceId: String

    @State private var didCheckIn = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(didCheckIn ? Color.green : Color.primary)

            Text("\(spaceName) is starting soon")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            if didCheckIn {
                Text("Checked in")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15), in: Capsule())
            } else {
                Button {
                    performCheckIn()
                } label: {
                    Text("Check In")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        // Glass-on-glass fixed per seam sweep: button sits inside a
                        // livingGlassMaterial banner — use tinted solid fill instead.
                        .background(Capsule().fill(Color.white.opacity(0.20)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .livingGlassMaterial(tint: .blue)
        .padding(.horizontal, 12)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(spaceName) is starting soon. Check in now."
            )
        }
    }

    private func performCheckIn() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = ["checkedInAt": FieldValue.serverTimestamp()]
        Firestore.firestore()
            .collection("spaces").document(spaceId)
            .collection("attendance").document(uid)
            .setData(data, merge: true) { _ in
                Task { @MainActor in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        didCheckIn = true
                    }
                }
            }
    }
}

// MARK: - TravelModeBanner
//
// Shown when AmenContextMode == .travel.
// Posts .amenFindLocalChurch on button tap to open church finder.

struct TravelModeBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("You're traveling — find a local church")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button {
                NotificationCenter.default.post(
                    name: .amenFindLocalChurch,
                    object: nil
                )
            } label: {
                Text("Find Churches")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    // Glass-on-glass fixed per seam sweep: button sits inside a
                    // livingGlassMaterial banner — use tinted solid fill instead.
                    .background(Capsule().fill(Color.white.opacity(0.20)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .livingGlassMaterial(tint: .teal)
        .padding(.horizontal, 12)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Travel mode detected. Find a local church nearby."
            )
        }
    }
}

// MARK: - Supporting Notification.Name extensions

extension Notification.Name {
    /// Fires when the user taps "Berean Voice" from the Driving Mode banner.
    static let amenLaunchBereanVoice = Notification.Name("AmenLaunchBereanVoice")
    /// Fires when the user taps "Church Mode" from the Sunday Mode banner.
    static let amenOpenChurchMode    = Notification.Name("AmenOpenChurchMode")
    /// Fires when the user taps "Find Churches" from the Travel Mode banner.
    static let amenFindLocalChurch   = Notification.Name("AmenFindLocalChurch")
}
