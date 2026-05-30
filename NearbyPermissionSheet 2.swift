// NearbyPermissionSheet.swift
// AMENAPP
//
// Liquid Glass consent sheet shown BEFORE any location access for "Find People Nearby".
// Explains what is shared, why, how to turn it off.
// No location is read until the user taps "Allow".

import SwiftUI
import CoreLocation

// MARK: - NearbyPermissionSheet

/// Full consent + education sheet for the "Find People Nearby" feature.
/// Present this `.sheet` before calling `NearbyUsersService.requestNearbySearch`.
struct NearbyPermissionSheet: View {

    // MARK: - Actions

    let onAllow: () -> Void    // User tapped "Allow" — proceed with location request
    let onDismiss: () -> Void  // User tapped "Not Now" — do not access location

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Pull indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // Hero icon
                    heroIcon
                        .padding(.top, 24)
                        .padding(.bottom, 20)

                    // Title + subtitle
                    VStack(spacing: 8) {
                        Text("Find Believers Near You")
                            .font(AMENFont.bold(22))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text("Connect with AMEN members in your neighborhood — for fellowship, prayer, or just to know you're not alone in your faith walk.")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                    // Privacy detail cards
                    VStack(spacing: 10) {
                        privacyCard(
                            icon: "location.slash.fill",
                            iconColor: Color.green,
                            title: "Approximate location only",
                            body: "AMEN never stores your exact GPS coordinates. We use a 500-metre fuzzy zone — enough to find nearby believers, not enough to pinpoint your address."
                        )
                        privacyCard(
                            icon: "clock.fill",
                            iconColor: Color.orange,
                            title: "Expires in 1 hour",
                            body: "Your location preference is automatically deleted after 1 hour. It only lasts as long as your active search session."
                        )
                        privacyCard(
                            icon: "hand.raised.fill",
                            iconColor: Color.purple,
                            title: "Always opt-in",
                            body: "AMEN never tracks you in the background. Location is only accessed when you tap \"Find People Near Me\" — and you can turn it off any time."
                        )
                        privacyCard(
                            icon: "eye.slash.fill",
                            iconColor: Color.blue,
                            title: "You control visibility",
                            body: "You choose whether others can find you. Private accounts and users who opted out of discovery are never shown or discoverable."
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)

                    // Privacy policy link
                    Button {
                        if let url = URL(string: "https://amenapp.com/privacy") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Read our Privacy Policy")
                                .font(AMENFont.medium(13))
                            Image(systemName: "arrow.up.right")
                                .font(.systemScaled(11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 24)
                }
            }

            // CTA buttons
            ctaButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Hero Icon

    private var heroIcon: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 100, height: 100)

            // Glass pill
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
                .frame(width: 80, height: 80)
                .shadow(color: Color.accentColor.opacity(0.15), radius: 16, y: 6)

            // Icon
            Image(systemName: "person.2.wave.2.fill")
                .font(.systemScaled(32, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Privacy Card

    private func privacyCard(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            .flexibleFrame(minWidth: 40, maxWidth: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body)")
    }

    // MARK: - CTA Buttons

    private var ctaButtons: some View {
        VStack(spacing: 10) {
            // Primary — Allow
            Button(action: onAllow) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.systemScaled(15, weight: .semibold))
                    Text("Allow & Find People")
                        .font(AMENFont.bold(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Allow location access and find people nearby")

            // Secondary — Not Now
            Button(action: onDismiss) {
                Text("Not Now")
                    .font(AMENFont.medium(15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Decline, don't use location")
        }
    }
}

// MARK: - NearbyPermissionDeniedView

/// Shown when the user has denied location permission in Settings.
struct NearbyPermissionDeniedView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.systemScaled(44, weight: .light))
                .foregroundStyle(.orange)
                .padding(.top, 40)

            Text("Location Access Needed")
                .font(AMENFont.semiBold(18))
                .multilineTextAlignment(.center)

            Text("To find believers near you, go to Settings → AMEN → Location and enable \"While Using the App\".")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open Settings", action: onOpenSettings)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.accentColor))
                .buttonStyle(ScaleButtonStyle())

            Button("Maybe Later", action: onDismiss)
                .font(AMENFont.medium(14))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}

// MARK: - View helper

private extension View {
    /// A type-erased flexible frame helper for compatibility
    @ViewBuilder
    func flexibleFrame(minWidth: CGFloat? = nil, maxWidth: CGFloat? = nil) -> some View {
        self.frame(minWidth: minWidth, maxWidth: maxWidth)
    }
}
