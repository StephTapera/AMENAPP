// AmenGroupPulseCardView.swift
// AMEN App — Smart Collaboration Layer: Slice 6 — Group Pulse Card
//
// Slice 6 design rules enforced here:
//   1. isAligned is nil unless strong server evidence exists — never infer or display without it.
//   2. "urgent" gets a calm, amber visual treatment — no alarming colors, no pressure language.
//   3. Flag OFF → completely invisible (EmptyView at the top-level guard).
//   4. All states covered: loading, empty/no-pulse, normal, elevated, urgent, stale, error, offline.
//   5. VoiceOver labels on every interactive and informational element. Reduce Motion respected.
//   6. Read-only — no client writes to the pulse document.
//
// Analytics: .groupPulseViewed(urgencyLevel:) is fired once on first card appearance.
// Feature gate: RemoteKillSwitch.shared.groupDiscussionPulseEnabled (default OFF).

import SwiftUI

// MARK: - AmenGroupPulseCardView

struct AmenGroupPulseCardView: View {

    let spaceId: String
    let channelId: String

    @ObservedObject private var service = AmenGroupPulseService.shared

    /// Local dismiss — not persisted, resets when the parent view is recreated.
    @State private var isDismissed = false
    /// Prevents firing the analytics view event more than once per appearance.
    @State private var analyticsDidFire = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled

    // MARK: Body

    var body: some View {
        // Rule 3: flag OFF → no space, no layout impact.
        guard AMENFeatureFlags.shared.groupDiscussionPulseEnabled, !isDismissed else {
            return AnyView(EmptyView())
        }
        return AnyView(content)
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        if service.isLoading {
            loadingCard
        } else if let error = service.error {
            errorChip(error)
        } else if let pulse = service.currentPulse {
            pulseCard(pulse)
                .onAppear { fireAnalyticsOnce(urgency: pulse.urgency) }
        } else {
            // No pulse document yet — take no space.
            EmptyView()
        }
    }

    // MARK: - Loading state

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            shimmerRow(width: 120, height: 14)
            shimmerRow(width: 200, height: 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Group pulse loading")
    }

    @ViewBuilder
    private func shimmerRow(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: height)
            .shimmeringIfAllowed()
    }

    // MARK: - Error state

    private func errorChip(_ error: Error) -> some View {
        Text("Group pulse unavailable")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel("Group pulse unavailable")
    }

    // MARK: - Pulse card

    private func pulseCard(_ pulse: GroupDiscussionPulse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 8) {
                Text("Group Pulse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                urgencyBadge(pulse.urgency)

                // Dismiss button
                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss group pulse card")
            }

            Divider()

            // Active participant count
            Text("\(pulse.activeParticipantCount) \(pulse.activeParticipantCount == 1 ? "person" : "people") active")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // Topic momentum bar
            momentumBar(pulse.topicMomentum)

            // Alignment — only shown when server has provided evidence
            alignmentRow(pulse)

            // Stale banner
            if pulse.isStale {
                staleBanner(spaceId: spaceId, channelId: channelId)
            }

            // Offline indicator
            offlineOverlay(pulse)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cardAccessibilityLabel(pulse))
    }

    // MARK: - Urgency badge

    @ViewBuilder
    private func urgencyBadge(_ urgency: AmenPulseUrgency) -> some View {
        switch urgency {
        case .normal:
            // Calm — no badge shown
            EmptyView()
        case .elevated:
            badge(label: "Active", color: .blue)
        case .urgent:
            // Amber — calm, non-alarming
            badge(label: "Needs attention", color: Color(red: 0.85, green: 0.65, blue: 0.10))
        }
    }

    private func badge(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Momentum bar

    private func momentumBar(_ momentum: Double) -> some View {
        let clamped = min(max(momentum, 0.0), 1.0)
        let percent = Int(clamped * 100)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Topic momentum")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: geo.size.width * clamped, height: 4)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Topic momentum: \(percent) percent")
    }

    // MARK: - Alignment row

    @ViewBuilder
    private func alignmentRow(_ pulse: GroupDiscussionPulse) -> some View {
        // Rule 1: only render when isAligned is explicitly non-nil.
        if let aligned = pulse.isAligned {
            if aligned {
                let count = pulse.alignmentEvidenceMessageIds.count
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                    Text("Participants appear to be aligned")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if count > 0 {
                        Text("(\(count) \(count == 1 ? "message" : "messages") cited)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    count > 0
                        ? "Participants appear aligned based on \(count) \(count == 1 ? "message" : "messages")"
                        : "Participants appear to be aligned"
                )
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                    Text("Mixed perspectives detected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mixed perspectives detected in this discussion")
            }
        }
        // nil → nothing rendered (rule 1)
    }

    // MARK: - Stale banner

    private func staleBanner(spaceId: String, channelId: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.85, green: 0.65, blue: 0.10))
                .frame(width: 7, height: 7)

            Text("Pulse may be outdated")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task {
                    await service.requestPulseGeneration(spaceId: spaceId, channelId: channelId)
                }
            } label: {
                Text("Refresh")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Refresh group pulse")
        }
        .padding(.top, 4)
    }

    // MARK: - Offline overlay row

    @ViewBuilder
    private func offlineOverlay(_ pulse: GroupDiscussionPulse) -> some View {
        if scenePhase != .active {
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Showing last known pulse. Currently offline.")
        }
    }

    // MARK: - Card-level accessibility label

    private func cardAccessibilityLabel(_ pulse: GroupDiscussionPulse) -> String {
        let urgencyLabel: String
        switch pulse.urgency {
        case .normal:   urgencyLabel = "normal"
        case .elevated: urgencyLabel = "active"
        case .urgent:   urgencyLabel = "needs attention"
        }
        return "Group pulse. \(urgencyLabel). \(pulse.activeParticipantCount) \(pulse.activeParticipantCount == 1 ? "person" : "people") active."
    }

    // MARK: - Analytics

    private func fireAnalyticsOnce(urgency: AmenPulseUrgency) {
        guard !analyticsDidFire else { return }
        analyticsDidFire = true
        AMENAnalyticsService.shared.track(
            .groupPulseViewed(urgencyLevel: urgency.rawValue)
        )
    }
}

// MARK: - Reduce-Motion shimmer helper

private extension View {
    /// Applies a subtle shimmer animation unless the user has requested reduced motion.
    @ViewBuilder
    func shimmeringIfAllowed() -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.shimmering()
        }
    }
}

// MARK: - Minimal shimmer modifier
// A lightweight, self-contained shimmer. No external dependency required.

private struct ShimmeringModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.25), location: 0.45),
                        .init(color: Color.white.opacity(0.40), location: 0.50),
                        .init(color: Color.white.opacity(0.25), location: 0.55),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2
                }
            }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmeringModifier())
    }
}
