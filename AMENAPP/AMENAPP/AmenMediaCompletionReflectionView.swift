// AmenMediaCompletionReflectionView.swift
// AMENAPP
//
// Canonical end-of-media completion screen — the primary anti-doomscroll mechanic.
// Replaces "next video auto-loads" with an intentional pause and a set of
// spiritually meaningful actions. No autoplay. No variable-reward loop.
//
// Gated by AMENFeatureFlags.shared.mediaCompletionReflectionEnabled

import SwiftUI

// MARK: - AmenMediaCompletionReflectionView

struct AmenMediaCompletionReflectionView: View {

    // MARK: Inputs

    let mediaTitle: String?
    let sessionType: String?
    let completedCount: Int
    let totalCount: Int
    let onAction: (AmenMediaCompletionAction) -> Void

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Animation State

    @State private var appeared = false
    @State private var breatheScale: CGFloat = 1.0

    // MARK: Computed

    /// The primary actions that appear in the 2-column grid (excludes bottom-row items).
    private var gridActions: [AmenMediaCompletionAction] {
        [.pray, .reflect, .saveToNotes, .discuss, .share, .continueSession]
    }

    private var headlineText: String {
        if let title = mediaTitle, !title.isEmpty {
            return "You finished \u{201C}\(title)\u{201D}"
        }
        return "Session complete"
    }

    private var progressText: String {
        guard totalCount > 0 else { return "" }
        return "Item \(completedCount) of \(totalCount) complete"
    }

    // MARK: Body

    var body: some View {
        // Feature gate — show a minimal Done view when flag is OFF
        if !AMENFeatureFlags.shared.mediaCompletionReflectionEnabled {
            minimalDoneView
        } else {
            fullReflectionView
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.97))
                .onAppear {
                    if reduceMotion {
                        appeared = true
                    } else {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            appeared = true
                        }
                        startBreatheAnimation()
                    }
                    AMENAnalyticsService.shared.track(
                        .feedMeaningfulInteraction(type: "completion_shown")
                    )
                }
        }
    }

    // MARK: Full Reflection View

    private var fullReflectionView: some View {
        ZStack {
            // Base white background
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Completion Icon + Breathe Ring ──────────────────────
                    completionIconSection
                        .padding(.top, 52)
                        .padding(.bottom, 20)

                    // ── Progress Pill ───────────────────────────────────────
                    if totalCount > 0 {
                        progressPill
                            .padding(.bottom, 32)
                    }

                    // ── 2-Column Action Grid ────────────────────────────────
                    actionGrid
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // ── Bottom Row: Take Break + End Session ────────────────
                    bottomRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }
        }
    }

    // MARK: Completion Icon Section

    private var completionIconSection: some View {
        VStack(spacing: 14) {
            ZStack {
                // Breathe ring — skip when reduceMotion
                if !reduceMotion {
                    Circle()
                        .stroke(Color.black.opacity(0.06), lineWidth: 1.5)
                        .frame(width: 96, height: 96)
                        .scaleEffect(breatheScale)
                        .animation(
                            .easeInOut(duration: 2.4)
                            .repeatForever(autoreverses: true),
                            value: breatheScale
                        )
                }

                // Checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.black)
                    .accessibilityHidden(true)
            }
            .accessibilityHidden(true)

            // Headline
            Text(headlineText)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Progress Pill

    private var progressPill: some View {
        Text(progressText)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
            )
            .accessibilityLabel(progressText)
    }

    // MARK: 2-Column Action Grid

    private var actionGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(gridActions) { action in
                CompletionActionButton(
                    action: action,
                    style: action == .continueSession ? .secondary : .primary,
                    onTap: { onAction(action) }
                )
            }
        }
    }

    // MARK: Bottom Row

    private var bottomRow: some View {
        VStack(spacing: 14) {
            // Take Break — black pill, prominent
            Button {
                onAction(.takeBreak)
            } label: {
                Label(AmenMediaCompletionAction.takeBreak.title,
                      systemImage: AmenMediaCompletionAction.takeBreak.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AmenMediaCompletionAction.takeBreak.title)

            // End Session — subtle text button
            Button {
                onAction(.endSession)
            } label: {
                Text(AmenMediaCompletionAction.endSession.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AmenMediaCompletionAction.endSession.title)
        }
    }

    // MARK: Minimal Done View (feature flag OFF)

    private var minimalDoneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.black)
                .accessibilityHidden(true)
            Text("Done")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Button {
                onAction(.endSession)
            } label: {
                Text("Close")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: Breathe Animation

    private func startBreatheAnimation() {
        // Trigger via a slight delay so the spring entrance completes first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            breatheScale = 1.18
        }
    }
}

// MARK: - Completion Action Button

/// A single cell in the 2-column action grid.
private struct CompletionActionButton: View {

    enum ButtonStyle {
        case primary    // solid dark fill
        case secondary  // light fill — used for "Continue" to de-emphasize it
    }

    let action: AmenMediaCompletionAction
    let style: ButtonStyle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text(action.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 88)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:   return Color(.secondarySystemBackground)
        case .secondary: return Color(.tertiarySystemBackground)
        }
    }

    private var iconColor: Color {
        switch style {
        case .primary:   return .primary
        case .secondary: return .secondary
        }
    }

    private var labelColor: Color {
        switch style {
        case .primary:   return .primary
        case .secondary: return .secondary
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:   return Color(.separator).opacity(0.35)
        case .secondary: return Color(.separator).opacity(0.2)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Full — with title") {
    AmenMediaCompletionReflectionView(
        mediaTitle: "The God Who Sees You",
        sessionType: "Morning Inspiration",
        completedCount: 3,
        totalCount: 5,
        onAction: { action in
            dlog("Action tapped: \(action.title)")
        }
    )
}

#Preview("Full — no title") {
    AmenMediaCompletionReflectionView(
        mediaTitle: nil,
        sessionType: nil,
        completedCount: 5,
        totalCount: 5,
        onAction: { _ in }
    )
}

#Preview("Reduce Motion") {
    AmenMediaCompletionReflectionView(
        mediaTitle: "Faith Over Fear",
        sessionType: "Devotional",
        completedCount: 1,
        totalCount: 3,
        onAction: { _ in }
    )
}
#endif
