// AmenLiveBannerView.swift
// AMENAPP — Amen Live in-app banner
//
// Pill-shaped overlay that appears at the top of the screen when a live session
// is active for the user's church/org network.
//
// This is the in-app stand-in for Dynamic Island (iOS SwiftUI layer).
// The native ActivityKit Live Activity phase is defined in AmenLiveActivityContract.swift.
//
// Usage:
//   In your root ContentView or NavigationStack, add:
//     .overlay(alignment: .top) {
//         AmenLiveBannerView(churchIds: userProfile.churchIds)
//             .padding(.top, 8)
//     }
//
// Formation rules enforced:
//   - NO count-based UI ("N watching", "N praying" → forbidden)
//   - Dismiss sets .dismissed state — banner does not re-appear for this session
//   - Action button is fully wired: calls recordLiveAction CF callable
//   - Compact pill → tapping expands to full card
//   - .ultraThinMaterial background with live pulse indicator (not a count dot)

import SwiftUI

// MARK: - AmenLiveBannerView

struct AmenLiveBannerView: View {

    /// IDs of the user's churches/orgs. Pass from user profile on appear.
    let churchIds: [String]

    @StateObject private var viewModel = AmenLiveViewModel()

    /// Whether the banner is currently expanded (tapped to reveal full card).
    @State private var isExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if case .visible(let session) = viewModel.bannerState {
                bannerPill(session: session)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal:   .move(edge: .top).combined(with: .opacity)
                            )
                    )
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.72), value: viewModel.bannerState)
        .onAppear {
            viewModel.startObserving(churchIds: churchIds)
        }
        .onChange(of: churchIds) { _, newIds in
            viewModel.startObserving(churchIds: newIds)
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }

    // MARK: - Banner pill

    @ViewBuilder
    private func bannerPill(session: AmenLiveSession) -> some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedCard(session: session)
            } else {
                compactPill(session: session)
            }
        }
        .background(pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 22 : 30, style: .continuous))
        .overlay(pillBorder)
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        .padding(.horizontal, 16)
        .animation(
            reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75),
            value: isExpanded
        )
    }

    // MARK: - Compact pill

    private func compactPill(session: AmenLiveSession) -> some View {
        HStack(spacing: 10) {
            // Live pulse indicator — a pulsing dot, NOT a count
            LivePulseIndicator(color: accentColor(for: session.type))

            // Type icon
            Image(systemName: session.type.symbolName)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(accentColor(for: session.type))
                .accessibilityHidden(true)

            // Title
            Text(session.title)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action button (compact)
            Button {
                Task { await viewModel.handleAction(session) }
            } label: {
                Text(session.actionLabel)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(accentColor(for: session.type))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.actionLabel)
            .accessibilityHint("Tap to \(session.actionLabel.lowercased())")

            // Dismiss button
            Button {
                viewModel.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color(.systemGray5))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss live banner")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live: \(session.title) from \(session.hostName)")
        .accessibilityHint("Tap to expand details")
    }

    // MARK: - Expanded card

    private func expandedCard(session: AmenLiveSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with collapse button
            HStack(alignment: .top, spacing: 10) {
                // Type icon in circle
                ZStack {
                    Circle()
                        .fill(accentColor(for: session.type).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: session.type.symbolName)
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(accentColor(for: session.type))
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    // Type label + live pulse
                    HStack(spacing: 6) {
                        LivePulseIndicator(color: accentColor(for: session.type))
                        Text(session.type.displayLabel.uppercased())
                            .font(.systemScaled(10, weight: .bold))
                            .foregroundStyle(accentColor(for: session.type))
                            .accessibilityLabel("Type: \(session.type.displayLabel)")
                    }

                    // Title
                    Text(session.title)
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Collapse + dismiss buttons
                VStack(spacing: 6) {
                    Button {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75)) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color(.systemGray5))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse banner")

                    Button {
                        viewModel.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color(.systemGray5))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss live banner")
                }
            }

            // Host name
            Text(session.hostName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Subtitle (optional)
            if let subtitle = session.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Full-width action button
            Button {
                Task { await viewModel.handleAction(session) }
            } label: {
                Text(session.actionLabel)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accentColor(for: session.type))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.actionLabel)
            .accessibilityHint("Tap to \(session.actionLabel.lowercased())")
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live session from \(session.hostName): \(session.title)")
    }

    // MARK: - Background & border

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Color(.systemBackground)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: isExpanded ? 22 : 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: isExpanded ? 22 : 30, style: .continuous)
                    .fill(Color.white.opacity(0.45))
            }
        }
    }

    private var pillBorder: some View {
        RoundedRectangle(cornerRadius: isExpanded ? 22 : 30, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }

    // MARK: - Helpers

    private func accentColor(for type: AmenLiveType) -> Color {
        Color(red: type.accentRed, green: type.accentGreen, blue: type.accentBlue)
    }
}

// MARK: - LivePulseIndicator

/// Subtle pulsing dot that indicates an active live session.
/// This is a status indicator only — it is NOT a count or metric.
private struct LivePulseIndicator: View {
    let color: Color

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.6 : 1.0)
                .opacity(pulsing ? 0.0 : 0.6)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: false)
            ) {
                pulsing = true
            }
        }
        .accessibilityLabel("Live")
        .accessibilityHidden(false)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Compact pill") {
    let session = AmenLiveSession(
        id:                "preview_1",
        title:             "Sunday Morning Prayer",
        subtitle:          "Join Grace Community Church in prayer before the service.",
        type:              .prayerEvent,
        hostId:            "church_grace",
        hostName:          "Grace Community Church",
        startedAt:         Date().timeIntervalSince1970,
        scheduledEndAt:    Date().addingTimeInterval(3600).timeIntervalSince1970,
        isActive:          true,
        backingEntityId:   "church_grace",
        backingEntityKind: "CHURCH",
        actionLabel:       "Join Prayer",
        actionHandler:     "recordLiveAction",
        actionTarget:      "church_grace"
    )
    _ = session // suppress unused warning in preview

    return ZStack(alignment: .top) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        // Direct preview — in production, pass real churchIds from user profile
        AmenLiveBannerView(churchIds: ["church_grace"])
            .padding(.top, 60)
    }
}
#endif
