// LowDataBanner.swift
// AMEN — Global Resilience System
// Compact banner shown while the device is in low-data mode.
// Observes LowDataModeManager.shared; auto-hides when the condition clears.

import SwiftUI
import Combine

// MARK: - LowDataBanner

/// Overlay banner that appears when `LowDataModeManager.shared.isEffectiveLowData`
/// is `true`. The user can dismiss it for the current session; it reappears
/// automatically if the condition was resolved and then returns.
struct LowDataBanner: View {

    // MARK: State

    @ObservedObject private var manager = LowDataModeManager.shared

    /// Tracks whether the user has manually dismissed the banner this session.
    @State private var dismissed: Bool = false

    // MARK: Body

    var body: some View {
        if manager.isEffectiveLowData && !dismissed {
            bannerContent
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: manager.isEffectiveLowData)
        }
    }

    // MARK: Banner Layout

    private var bannerContent: some View {
        HStack(spacing: 10) {
            // Leading icon
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            // Label
            Text("Low Data Mode")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Data & Access settings button
            Button {
                NotificationCenter.default.post(
                    name: .openDataAccessSettings,
                    object: nil
                )
            } label: {
                Text("Data & Access")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.regularMaterial)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Data and Access Settings")

            // Dismiss button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss low data mode banner")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: 14)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onChange(of: manager.isEffectiveLowData) { _, newValue in
            // Reset dismissal so the banner can reappear if the condition returns.
            if !newValue {
                dismissed = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Low Data Banner — visible") {
    ZStack(alignment: .top) {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()

        VStack {
            LowDataBanner()
            Spacer()
        }
    }
}
