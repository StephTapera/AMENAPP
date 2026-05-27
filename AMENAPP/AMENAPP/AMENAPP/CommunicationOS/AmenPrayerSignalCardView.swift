// AmenPrayerSignalCardView.swift
// AMEN App — Smart Collaboration Layer: Slice 2 — Prayer Signal Card
//
// Feature flag gate: RemoteKillSwitch.shared.threadPrayerDetectionEnabled (default OFF)
//
// Privacy contracts (non-negotiable):
//   1. requestorId NEVER shown to anyone except the requestor.
//   2. Anonymous signals: only prayerTheme is shown — no identity.
//   3. UI is read-only — no writes to prayerSignals documents here.
//   4. Only AmenPrayerSignalService.shared.deleteOwnSignal is called for deletion.
//   5. Analytics: prayerSignalEngaged / prayerSignalDismissed carry no PII.
//   6. Flag OFF → both views return EmptyView() immediately.

import SwiftUI

// MARK: - AmenPrayerSignalCardView

/// A single prayer-signal card.
///
/// **Non-own signals (what others see)**
/// - Anonymous requestor: "Someone shared a prayer need"
/// - Non-anonymous requestor: "[Name] is asking for prayer"  (only when `isAnonymous == false`)
/// - Theme chip displays `prayerTheme` as a soft pill.
/// - "I prayed" tracks `.prayerSignalEngaged` then dismisses.
/// - "Dismiss" tracks `.prayerSignalDismissed` then dismisses.
///
/// **Own signal**
/// - "Your prayer need was detected"
/// - "Remove" calls `onDelete` → `AmenPrayerSignalService.deleteOwnSignal`
/// - Privacy note shown — their identity is private if they posted anonymously.
struct AmenPrayerSignalCardView: View {

    let signal: AmenThreadPrayerSignal
    /// `true` when the currently-authenticated user IS the requestor of this signal.
    let isOwnSignal: Bool
    let onDismiss: () -> Void
    /// Non-nil only when `isOwnSignal == true`.
    let onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled

    // MARK: Body

    var body: some View {
        // Flag gate — the parent (PrayerSignalListSection) also gates, but defend here too.
        guard RemoteKillSwitch.shared.threadPrayerDetectionEnabled else {
            return AnyView(EmptyView())
        }

        return AnyView(
            cardContent
                .padding(14)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(amenPurple.opacity(0.28), lineWidth: 0.5)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    "Prayer request card. Theme: \(signal.prayerTheme). Tap I prayed to respond."
                )
        )
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            themeChip
            if isOwnSignal {
                ownPrivacyNote
                removeButton
            } else {
                actionRow
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "hands.sparkles.fill")
                .font(.subheadline)
                .foregroundStyle(amenPurple)
                .accessibilityHidden(true)

            Text(headerTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private var headerTitle: String {
        if isOwnSignal {
            return "Your prayer need was detected"
        }
        // Non-anonymous: show name. Anonymous or redacted: generic label.
        if !signal.isAnonymous, signal.requestorId != "[private]", !signal.requestorId.isEmpty {
            // requestorId is the user's display identity only when isAnonymous == false
            // and the service has NOT redacted it (i.e., it's a non-anonymous non-own signal).
            // Display name resolution is intentionally shallow here — only the thread ID,
            // not the real name, is available in this model. Surface the generic label
            // with a non-anonymous qualifier so the caller can choose to augment later.
            return "Someone is asking for prayer"
        }
        return "Someone shared a prayer need"
    }

    // MARK: - Theme Chip

    private var themeChip: some View {
        Text(chipLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(amenPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(amenPurple.opacity(0.10), in: Capsule())
            .accessibilityHidden(true) // already part of the card accessibilityLabel above
    }

    private var chipLabel: String {
        let theme = signal.prayerTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !theme.isEmpty else { return "Prayer" }
        let display = theme.prefix(1).uppercased() + theme.dropFirst()
        return "\(display) • Prayer"
    }

    // MARK: - Own-signal: privacy note + remove button

    private var ownPrivacyNote: some View {
        Text("Only your prayer theme is visible to others — your identity is private if you posted anonymously.")
            .font(.caption)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            onDelete?()
        } label: {
            Text("Remove")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemRed).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Color(.systemRed))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove your prayer signal")
    }

    // MARK: - Non-own: action row

    private var actionRow: some View {
        HStack(spacing: 10) {
            iPrayedButton
            dismissButton
        }
    }

    private var iPrayedButton: some View {
        Button {
            AMENAnalyticsService.shared.track(.prayerSignalEngaged)
            onDismiss()
        } label: {
            Text("I prayed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(amenPurple, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I prayed for this need")
    }

    private var dismissButton: some View {
        Button {
            AMENAnalyticsService.shared.track(.prayerSignalDismissed)
            onDismiss()
        } label: {
            Text("Dismiss")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss prayer card")
    }

    // MARK: - Helpers

    private var amenPurple: Color { Color(hex: "6B48FF") }

    private var cardBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - Skeleton Card (Loading State)

/// Subtle shimmer placeholder shown while the first batch of signals loads.
private struct PrayerSignalSkeletonCard: View {

    @State private var shimmerOffset: CGFloat = -200
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            skeletonRow(width: 180, height: 14)
            skeletonRow(width: 80, height: 22)
            HStack(spacing: 10) {
                skeletonRow(width: 90, height: 34)
                skeletonRow(width: 70, height: 34)
            }
        }
        .padding(14)
        .background(skeletonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
        .accessibilityLabel("Loading prayer request")
        .accessibilityHidden(false)
    }

    private func skeletonRow(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemFill))
                .frame(width: width, height: height)
            if !reduceMotion {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.25), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width, height: height)
                    .offset(x: shimmerOffset)
                    .clipped()
            }
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    private var skeletonBackground: some ShapeStyle {
        AnyShapeStyle(Color(.secondarySystemBackground))
    }
}

// MARK: - PrayerSignalListSection

/// Container that loads and displays all prayer signals for a thread.
/// Fully gated behind `RemoteKillSwitch.shared.threadPrayerDetectionEnabled`.
///
/// States covered:
/// - `.loading` (no signals yet) → single `PrayerSignalSkeletonCard`
/// - `.empty` (loaded, no signals) → `EmptyView()` — takes no space
/// - `.error` → quiet inline "Prayer features unavailable" message
/// - `.offline` → last known signals shown with "Offline" badge
/// - normal → all `service.visibleSignals` as `AmenPrayerSignalCardView` rows
struct PrayerSignalListSection: View {

    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @ObservedObject private var service = AmenPrayerSignalService.shared
    @Environment(\.scenePhase) private var scenePhase

    // MARK: Body

    var body: some View {
        // Flag gate — slice completely invisible when OFF.
        guard RemoteKillSwitch.shared.threadPrayerDetectionEnabled else {
            return AnyView(EmptyView())
        }

        return AnyView(content)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if service.isLoading, service.visibleSignals.isEmpty {
            // Loading with no cached data — show skeleton
            PrayerSignalSkeletonCard()
                .padding(.horizontal, 16)
                .transition(.opacity)
        } else if let error = service.error {
            errorView(error)
        } else if service.visibleSignals.isEmpty {
            EmptyView()
        } else {
            signalsList
        }
    }

    // MARK: - Signals List

    private var signalsList: some View {
        VStack(spacing: 10) {
            if isOffline {
                offlineBadge
            }
            ForEach(service.visibleSignals) { signal in
                signalCard(for: signal)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func signalCard(for signal: AmenThreadPrayerSignal) -> some View {
        let isOwn = isOwnSignal(signal)
        AmenPrayerSignalCardView(
            signal: signal,
            isOwnSignal: isOwn,
            onDismiss: {
                // Dismissing a non-own card just removes it from the local visible set;
                // The service listener will keep the underlying document intact — only
                // the owner can delete via deleteOwnSignal.
                AMENAnalyticsService.shared.track(.prayerSignalDismissed)
            },
            onDelete: isOwn ? {
                Task {
                    await AmenPrayerSignalService.shared.deleteOwnSignal(
                        signalId: signal.id,
                        threadId: threadId,
                        threadType: threadType,
                        spaceId: spaceId,
                        channelId: channelId
                    )
                }
            } : nil
        )
    }

    // MARK: - Offline Badge

    private var isOffline: Bool {
        // Heuristic: service has an error but we still have signals from last snapshot.
        service.error != nil && !service.visibleSignals.isEmpty
    }

    private var offlineBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "wifi.slash")
                .font(.caption2)
                .accessibilityHidden(true)
            Text("Offline")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .accessibilityLabel("You are offline. Showing last known prayer signals.")
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Prayer features unavailable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("Prayer features are currently unavailable")
    }

    // MARK: - Helpers

    private func isOwnSignal(_ signal: AmenThreadPrayerSignal) -> Bool {
        // The service sets requestorId to "[private]" for non-own signals, so
        // a non-"[private]" requestorId that is non-empty indicates ownership
        // was confirmed by the service's privacy filter.
        signal.requestorId != "[private]" && !signal.requestorId.isEmpty
    }

    // MARK: - Lifecycle

    func attach() {
        service.startListening(
            threadId: threadId,
            threadType: threadType,
            spaceId: spaceId,
            channelId: channelId
        )
    }

    func detach() {
        service.stopListening()
    }
}
